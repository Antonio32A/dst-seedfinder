#!/usr/bin/env python3
"""Writes data/gen_tags.bend for the end-to-end generator (gen/): the string ids of the node tags Graph:ApplyPoisonTag
reads (network.lua), the catalog vocabulary of the search filters (data/search_vocab.bend order) as the generator's
string ids and tile ids (the caves' own prefabs too), to build the filters' world from a generated one, and the caves'
vocabulary prefabs whose instances change after ConvertGround. `-` prints the module instead."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402

CATALOG = blob.catalog("forest")
CAVE_CATALOG = blob.catalog("caves")
NEVER_PLACED = 4294967295
POCKET_CONTAINERS = ("shadow_container", "rabbitkinghorn_container")
PILLARS = ("tentacle_pillar", "tentacle_pillar_atrium")
CAVE_WORMHOLE = "tentacle_pillar"
WORMHOLE_MARKER = "wormhole_MARKER"
ARCHIVE_DISPENSERS = ("archive_lockbox_dispencer", "archive_lockbox_dispencer_temp")

TAGS = (("force_connected", "ForceConnected"), ("road_poison", "RoadPoison"), ("force_disconnected", "ForceDisconnected"))


def cave_added_late():
    """The prefabs a caves attempt adds after ConvertGround: Graph:PopulateVoronoi's countprefabs and distributed
    prefabs of every cave room (every swappable choice and distribute variant), the items of the map tags those rooms
    carry (a STATIC tag's layout is placed by ConvertGround), and BunchSpawnerRun's items and closure results."""
    story = blob.sidecar("story_caves.json")
    distribute = blob.sidecar("distribute_caves.json")
    added, tags = set(), set()
    for room in story["rooms"]:
        for view in room["contents"].values():
            for field in ("countprefabs", "distributeprefabs"):
                for entry in (view.get(field) or {}).get("entries", []):
                    added.add(entry["key"])
                    if isinstance(entry["value"], dict) and "prefabs" in entry["value"]:
                        added.update(entry["value"]["prefabs"].values())
        tags.update((room.get("tags") or {}).get("ipairs", []))
    for variant in distribute["variants"]:
        added.update(entry["key"] for entry in variant["entries"])
    for pick in distribute["picks"]:
        added.update(entry["key"] for entry in pick)
    for tag in blob.sidecar("layouts_caves.json")["maptags"]:
        if tag["tag"] in tags:
            for result in tag["results"]:
                added.update(call["value"] for call in (result["first"], result["second"]) if call.get("kind") == "ITEM")
    for bunch in blob.sidecar("ocean.json")["bunches"]:
        added.update([bunch["prefab"]] if bunch.get("prefab") else [])
        added.update(bunch.get("prefab_results", []))
    return added


def cave_late():
    """The prefabs whose savedata instances a caves world can get after ConvertGround: the ones added then, the
    randomization proxies (relabelled by draws) with their results, the archive's dispensers (picked by draws), and
    every target of GlobalPostPopulate's moves (customization proxies, the wormhole markers' tentacle pillars) whose
    source is one of them."""
    post = blob.sidecar("ocean_post.json")
    late = cave_added_late() | set(ARCHIVE_DISPENSERS)
    for row in post["randomization_proxies"]:
        late |= {row["proxy"], *row["real"]}
    moves = [(row["proxy"], real) for row in post["customization_proxies"] for real in row["real"]]
    moves.append((WORMHOLE_MARKER, CAVE_WORMHOLE))
    while any(source in late and target not in late for source, target in moves):
        late |= {target for source, target in moves if source in late}
    return late


def main():
    m = blob.Module("gen_tags", "scripts/gen/gen_gen.py",
                    "String ids of the node tags that Graph:ApplyPoisonTag reads.", imports=())
    for name, tag in TAGS:
        m.comment(f"\"{tag}\"")
        m.const(f"tag_{name}", ids.sid(tag))
    prefabs = [p["id"] for p in CATALOG["prefabs"]]
    table = ids.table()["index"]
    m.comment("The global string id of each catalog prefab (4294967295: a prefab the generator never places).")
    m.code("def vocab_prefab_sids() -> List<&2, U32>:\n  [" + ", ".join(str(table.get(p, NEVER_PLACED)) for p in prefabs) + "]")
    cave_only = [p["id"] for p in CAVE_CATALOG["prefabs"] if p["id"] not in set(prefabs)]
    m.comment("The global string id of each of the caves' own prefabs (search_vocab.bend cave_only, after the catalog's).")
    m.code("def cave_vocab_prefab_sids() -> List<&2, U32>:\n  [" + ", ".join(str(table.get(p, NEVER_PLACED)) for p in cave_only) + "]")
    m.comment("Slots of a string id lookup table (a power of two above every string id the forest places).")
    m.const("sid_depth", f"{max(ids.table()['forest_string_count'] - 1, 1).bit_length()}n", "Nat")
    m.comment("Slots of a string id lookup table for the caves (a power of two above every string id).")
    m.const("cave_sid_depth", f"{max(len(table) - 1, 1).bit_length()}n", "Nat")
    m.comment("GetWorldTileMap()'s id of each catalog tile.")
    m.code("def vocab_tile_ids() -> List<&2, U32>:\n  [" + ", ".join(str(t["id"]) for t in CATALOG["tiles"]) + "]")
    m.comment("Catalog indices of the wormhole and of AddWorldEntities' pocket dimension containers.")
    m.const("vocab_wormhole", prefabs.index("wormhole"))
    for name in POCKET_CONTAINERS:
        m.const(f"vocab_{name}", prefabs.index(name))
    vocabulary = prefabs + cave_only
    late = cave_late()
    m.comment("Vocabulary ids (ascending) of the caves' prefabs whose instances can change after ConvertGround: added by",
              "PopulateVoronoi or the bunch spawner, relabelled or picked by draws, or moved from such a prefab.")
    m.code("def cave_late_prefabs() -> List<&2, U32>:\n  ["
           + ", ".join(str(i) for i in sorted(vocabulary.index(p["id"]) for p in CAVE_CATALOG["prefabs"] if p["id"] in late))
           + "]")
    m.comment("Vocabulary ids of the tentacle pillars, whose teleporters are the caves' links.")
    for name in PILLARS:
        m.const(f"vocab_{name}", (prefabs + cave_only).index(name))
    m.emit()


if __name__ == "__main__":
    main()
