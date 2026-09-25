#!/usr/bin/env python3
"""Writes data/gen_tags.bend for the end-to-end generator (gen/): the string ids of the node tags Graph:ApplyPoisonTag
reads (network.lua), and the catalog vocabulary of the search filters (data/search_vocab.bend order) as the generator's
string ids and tile ids, to build the filters' world from a generated one. `-` prints the module instead."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402

CATALOG = json.loads((Path(__file__).resolve().parents[1] / "catalog" / "catalog.json").read_text(encoding="utf-8"))
NEVER_PLACED = 4294967295
POCKET_CONTAINERS = ("shadow_container", "rabbitkinghorn_container")

TAGS = (("force_connected", "ForceConnected"), ("road_poison", "RoadPoison"), ("force_disconnected", "ForceDisconnected"))


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
    m.comment("Slots of a string id lookup table (a power of two above every string id).")
    m.const("sid_depth", f"{max(len(table) - 1, 1).bit_length()}n", "Nat")
    m.comment("GetWorldTileMap()'s id of each catalog tile.")
    m.code("def vocab_tile_ids() -> List<&2, U32>:\n  [" + ", ".join(str(t["id"]) for t in CATALOG["tiles"]) + "]")
    m.comment("Catalog indices of the wormhole and of AddWorldEntities' pocket dimension containers.")
    m.const("vocab_wormhole", prefabs.index("wormhole"))
    for name in POCKET_CONTAINERS:
        m.const(f"vocab_{name}", prefabs.index(name))
    m.emit()


if __name__ == "__main__":
    main()
