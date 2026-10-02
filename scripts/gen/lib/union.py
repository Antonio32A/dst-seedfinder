"""The forest and caves sidecars merged into the union tables the generated modules hold.

Everything the forest reaches keeps its position (and so its id); things only the caves reach are appended after it.
The caves sidecars are the same extractors run with GEN_SHARD=caves (out/story_caves.json, distribute_caves.json,
layouts_caves.json). What both shards reach must be identical, which is asserted here.
"""
import json
from functools import lru_cache

import blob


def _dump(v):
    return json.dumps(v, sort_keys=True)


def _shared_equal(forest, caves, what):
    for key, cave_value in caves.items():
        if key in forest:
            assert _dump(forest[key]) == _dump(cave_value), f"{what} {key} differs between the forest and the caves"


@lru_cache(maxsize=None)
def story():
    """The forest story document whose rooms also hold the caves' rooms (cave-only ones sorted by name after)."""
    forest, caves = blob.sidecar("story.json"), blob.sidecar("story_caves.json")
    forest_rooms = {r["name"]: r for r in forest["rooms"]}
    cave_rooms = {r["name"]: r for r in caves["rooms"]}
    for name in forest_rooms.keys() & cave_rooms.keys():
        forest_view = {k: v for k, v in forest_rooms[name].items() if k != "start"}
        assert _dump(forest_view) == _dump(cave_rooms[name]), f"room {name} differs between the forest and the caves"
    only = sorted((r for n, r in cave_rooms.items() if n not in forest_rooms), key=lambda r: r["name"].encode())
    merged = dict(forest)
    merged["rooms"] = forest["rooms"] + only
    return merged


@lru_cache(maxsize=None)
def layouts():
    """The forest layouts document extended by the caves' layouts, sandbox areas, map tags, area literals and mazes."""
    forest, caves = blob.sidecar("layouts.json"), blob.sidecar("layouts_caves.json")
    forest_layouts = {x["name"]: x for x in forest["layouts"]}
    cave_layouts = {x["name"]: x for x in caves["layouts"]}
    _shared_equal(forest_layouts, cave_layouts, "layout")
    merged = dict(forest)
    merged["layouts"] = forest["layouts"] + [x for n, x in cave_layouts.items() if n not in forest_layouts]
    for kind, areas in forest["sandboxes"].items():
        cave_areas = {str(a["area"]): a for a in caves["sandboxes"][kind]}
        assert {str(a["area"]) for a in areas} == set(cave_areas), f"sandbox {kind} areas differ"
        for a in areas:
            assert a["pieces"] == cave_areas[str(a["area"])]["pieces"], f"sandbox {kind} {a['area']} pieces differ"
    forest_tags = {t["tag"]: t for t in forest["maptags"]}
    cave_tags = {t["tag"]: t for t in caves["maptags"]}
    _shared_equal(forest_tags, cave_tags, "map tag")
    merged["maptags"] = forest["maptags"] + [t for n, t in cave_tags.items() if n not in forest_tags]
    known = {e["closure"] for e in forest["area_literals"]}
    merged["area_literals"] = forest["area_literals"] + [e for e in caves["area_literals"] if e["closure"] not in known]
    merged["mazes"] = caves["mazes"]
    return merged


@lru_cache(maxsize=None)
def distribute():
    """The forest distribute document extended by the caves' rooms, variants and picks (first-seen order)."""
    forest, caves = blob.sidecar("distribute.json"), blob.sidecar("distribute_caves.json")
    assert forest["land_tiles"] == caves["land_tiles"]

    def signature(entries):
        return tuple((e["key"], e["value"]) for e in entries)

    picks = list(forest["picks"])
    pick_index = {signature(p): i for i, p in enumerate(picks)}
    pick_map = []
    for p in caves["picks"]:
        sig = signature(p)
        if sig not in pick_index:
            pick_index[sig] = len(picks)
            picks.append(p)
        pick_map.append(pick_index[sig])

    variants = list(forest["variants"])
    variant_index = {signature(v["entries"]): i for i, v in enumerate(variants)}
    variant_map = []
    for v in caves["variants"]:
        sig = signature(v["entries"])
        if sig not in variant_index:
            variant_index[sig] = len(variants)
            variants.append({"entries": v["entries"], "tiles": [pick_map[t] for t in v["tiles"]]})
        else:
            forest_v = variants[variant_index[sig]]
            assert forest_v["tiles"] == [pick_map[t] for t in v["tiles"]], "same variant, different picks"
        variant_map.append(variant_index[sig])

    forest_rooms = {r["name"]: r for r in forest["rooms"]}
    rooms = list(forest["rooms"])
    for room in caves["rooms"]:
        depths = [{"swappable": d["swappable"],
                   "cases": [dict(c, variant=variant_map[c["variant"]]) for c in d["cases"]]} for d in room["depths"]]
        if room["name"] in forest_rooms:
            assert _dump(forest_rooms[room["name"]]["depths"]) == _dump(depths), f"distribute {room['name']} differs"
        else:
            rooms.append({"name": room["name"], "depths": depths})
    merged = dict(forest)
    merged.update(rooms=rooms, variants=variants, picks=picks)
    return merged
