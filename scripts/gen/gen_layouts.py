#!/usr/bin/env python3
"""Writes data/layouts.bend (with `props` as argument: data/layout_props.bend) from out/layouts.json: every layout
reachable on the default forest path as object_layout.LayoutForDefinition returns it under each of the 8 prefab swap
states, deduplicated into variants. Coordinates are exact multiples of 1/128 tile, stored as signed x * 128.
layout_props holds the JSON text of object properties and add_topology (output only).
`-` as the last argument prints the module instead of writing it."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402
import union  # noqa: E402

KIND_INTEGER, KIND_CLOSURE, KIND_LIST = 0, 1, 4
FLAG_DISABLE_TRANSFORM, FLAG_SAFE, FLAG_AREAS, FLAG_DEFS, FLAG_COUNT, FLAG_STATIC_LIST, FLAG_TOPOLOGY = (
    1, 2, 4, 8, 16, 32, 64)
SCALE = 128


def fixed(v):
    scaled = v * SCALE
    assert scaled == int(scaled), v
    return blob.signed(int(scaled))


def optional_int(v):
    return blob.NONE if v is None else blob.unit(int(v))


class Builder:
    def __init__(self):
        self.props, self.props_index = [], {}
        self.area_lists = []
        self.variants, self.variant_index = [], {}

    def prop(self, text):
        if text is None:
            return 0
        if text not in self.props_index:
            self.props_index[text] = len(self.props) + 1
            self.props.append(text)
        return self.props_index[text]

    def variant(self, state):
        key = json.dumps(state, sort_keys=True)
        if key not in self.variant_index:
            self.variant_index[key] = len(self.variants)
            self.variants.append(state)
        return self.variant_index[key]


def area_value(v, builder):
    if isinstance(v, dict) and "closure" in v:
        return [KIND_CLOSURE, ids.closure_id(v["closure"])]
    if isinstance(v, dict) and "list" in v:
        row = [ids.sid(item) for item in v["list"]]
        builder.area_lists.append(row)
        return [KIND_LIST, len(builder.area_lists) - 1]
    assert isinstance(v, int), v
    return [KIND_INTEGER, v]


def check_static_list(state):
    flat = [(e["key"], o["x"], o["y"], o.get("properties")) for e in state["layout"] for o in e["value"]]
    listed = [(e["prefab"], e["x"], e["y"], e.get("properties")) for e in state["entities"]]
    assert flat == listed, "ConvertLayoutToEntitylist differs from the pairs() order of layout.layout"


def snapshot_row(snapshot):
    if snapshot is None:
        return []
    assert snapshot["sizearray"] == 0
    row = [snapshot["lsizenode"], snapshot["lastfree"], 1 if snapshot["dummy"] else 0]
    for slot in snapshot["slots"]:
        key = slot["key"]
        row += [ids.sid(key) if isinstance(key, str) else blob.NONE, blob.NONE if slot["next"] < 0 else slot["next"],
                1 if slot["live"] else 0]
    return row


def literal_rows(d):
    by_key = {e["closure"]: e["literals"] for e in d.get("area_literals", [])}
    return [[ids.sid(s) for s in by_key.get(c["key"], [])] for c in ids.closures()]


def variant_rows(state, name, builder):
    area_keys = {e["key"] for e in state.get("areas") or []}
    flags = FLAG_DISABLE_TRANSFORM if state.get("disable_transform") else 0
    flags |= FLAG_SAFE if state.get("SafeFromDisconnect") else 0
    flags |= FLAG_AREAS if state.get("areas") else 0
    flags |= FLAG_DEFS if state.get("defs") else 0
    flags |= FLAG_COUNT if state.get("count") else 0
    flags |= FLAG_TOPOLOGY if state.get("add_topology") else 0
    if state.get("entities") is not None:
        check_static_list(state)
        flags |= FLAG_STATIC_LIST
    ground = state.get("ground") or []
    info = ([ids.sid(name), state["type"]] + blob.f64(1.0 if state.get("scale") is None else state["scale"]) + [flags, optional_int(state.get("force_rotation")),
            optional_int(state.get("start_mask")), optional_int(state.get("fill_mask")),
            optional_int(state.get("layout_position")), len(ground), optional_int(state.get("min_dist_from_land")),
            ids.closure_id(state["initfn"]) if state.get("initfn") else blob.NONE, builder.prop(state.get("add_topology"))])
    groups, props, index = [], [], 0
    for e in state["layout"]:
        sized = e["key"] in area_keys
        groups += [ids.sid(e["key"]), len(e["value"]), 1 if sized else 0]
        for o in e["value"]:
            groups += [fixed(o["x"]), fixed(o["y"])]
            if sized:
                groups += [fixed(o["width"]), fixed(o["height"])]
            ref = builder.prop(o.get("properties"))
            if ref:
                props += [index, ref]
            index += 1
    areas = []
    for e in state.get("areas") or []:
        areas += [ids.sid(e["key"])] + area_value(e["value"], builder)
    defs = []
    for e in state.get("defs") or []:
        defs += [ids.sid(e["key"]), len(e["value"])] + [ids.sid(p) for p in e["value"]]
    count = []
    for e in state.get("count") or []:
        count += [ids.sid(e["key"])] + area_value(e["value"], builder)
    tiles = [t for row in ground for t in row] + [0]
    assert all(t < 1 << 10 for t in tiles)
    packed = [tiles[i] | tiles[i + 1] << 10 for i in range(0, len(tiles) - 1, 2)]
    return (info, packed, groups, props, areas, defs, count, snapshot_row(state.get("layout_snapshot")),
            snapshot_row(state.get("count_snapshot")))


def check_cave_layouts_exist():
    story = blob.sidecar("story_caves.json")
    named = {p["name"] for p in story["taskset"]["set_pieces"]}
    named.update(story["level"]["required_setpieces"] + story["level"]["random_set_pieces"])
    named.add(story["level"]["start_setpeice"])
    for room in story["rooms"]:
        view = room["contents"].get("depth1") or {}
        named.update(e["key"] for e in (view.get("countstaticlayouts") or {}).get("entries", []))
    for tag in blob.sidecar("layouts_caves.json")["maptags"]:
        named.update(step["value"] for r in tag["results"] for step in (r["first"], r["second"])
                     if step.get("kind") == "STATIC")
    layout_names = set(ids.table()["layouts"])
    assert named <= layout_names, sorted(named - layout_names)


def main():
    check_cave_layouts_exist()
    d = union.layouts()
    layouts = sorted(d["layouts"], key=lambda layout: ids.layout_index(layout["name"]))
    assert [ids.layout_index(layout["name"]) for layout in layouts] == list(range(len(layouts)))
    builder = Builder()
    states = [[builder.variant((layout["name"], s)) for s in layout["states"]] for layout in layouts]
    tables = {"variants": [], "ground": [], "groups": [], "props": [], "areas": [], "defs": [], "count": [],
              "layout_snapshot": [], "count_snapshot": []}
    for name, state in builder.variants:
        for key, row in zip(tables, variant_rows(state, name, builder)):
            tables[key].append(row)
    which = [a for a in sys.argv[1:] if a != "-"]
    if which == ["props"]:
        m = blob.Module("layout_props", "scripts/gen/gen_layouts.py",
                        "JSON text of layout object properties and add_topology tables (row id - 1 of the refs).")
        m.table("props", [blob.text(p) for p in builder.props], "Row id - 1: the JSON text (sorted keys).")
        m.code('''
# The JSON text of a property reference (id >= 1) of data/layouts.bend.
def text(+id: U32) -> String:
  Blob.text(props((id - 1 : U32)))
''')
    else:
        m = blob.Module("layouts", "scripts/gen/gen_layouts.py",
                        "Layouts reachable on the default forest path, per prefab swap state, indexed by layout.")
        m.comment("Swap state bits: 1 grass gekko, 2 twiggy trees, 4 juicy berries. Coordinates: signed units of 1/128.",
                  "Property refs: 0 none, else a row + 1 of data/layout_props.bend.")
        for fname, value in (("disable_transform", FLAG_DISABLE_TRANSFORM), ("safe_from_disconnect", FLAG_SAFE),
                             ("areas", FLAG_AREAS), ("defs", FLAG_DEFS), ("count", FLAG_COUNT),
                             ("static_list", FLAG_STATIC_LIST), ("topology", FLAG_TOPOLOGY)):
            m.const(f"flag_{fname}", value)
        m.const("kind_integer", KIND_INTEGER)
        m.const("kind_closure", KIND_CLOSURE)
        m.const("kind_list", KIND_LIST)
        m.const("layout_count", len(layouts))
        m.table("states", states, "Row layout: the variant of each swap state 0..7.")
        m.table("variants", tables["variants"],
                "Row variant: name (string id), type (LAYOUT), scale (f64, 4 units; 1.0 when unset, as ConvertLayoutToEntitylist sets it), flags, force_rotation, "
                "start_mask, fill_mask, layout_position (NONE when unset), ground size (0 = no ground), "
                "min_dist_from_land, initfn closure, add_topology property ref (0 = none).")
        m.table("ground", tables["ground"], "Row variant: ground tiles, size * size, row-major as layout.ground[row][col] "
                                            "(0 = no tile), two per unit (10 bits each, the lower first).")
        m.table("groups", tables["groups"],
                "Row variant: layout.layout in pairs() order: per key (string id, object count, sized), then per "
                "object x, y, (width, height when sized = the key is an area). With flag_static_list this flattened "
                "is ConvertLayoutToEntitylist's result.")
        m.table("object_props", tables["props"], "Row variant: (object index in groups order, property ref) pairs of the "
                                                 "objects that have properties.")
        m.table("areas", tables["areas"], "Row variant: layout.areas in pairs() order as (key, kind, value) triples; "
                                          "kind 1 closure id, 4 area_lists row.")
        m.table("area_lists", builder.area_lists, "Row id: a constant area list (string ids).")
        m.table("defs", tables["defs"], "Row variant: layout.defs in pairs() order: (key, n, n choices in pairs() order).")
        m.table("count", tables["count"], "Row variant: layout.count in pairs() order as (key, kind, value) triples.")
        m.table("layout_snapshot", tables["layout_snapshot"],
                "Row variant (only with areas or defs): Lua 5.1 layout of the deepcopied layout.layout: lsizenode, "
                "lastfree (node index), 1 if the node part is the dummy node, then per node: key string id (NONE = nil "
                "key), next node index (NONE = none), 1 if the value is non-nil.")
        m.table("count_snapshot", tables["count_snapshot"],
                "Row variant (only with count and defs): the same layout of the deepcopied layout.count.")
        m.table("closure_literals", literal_rows(d),
                "Row closure id (data/closures.bend): the string literals of a layout area closure's source, in "
                "source order with repeats (comments skipped); empty for other closures.")
        m.code('''
def variant(+layout: U32, +state: U32) -> U32:
  Blob.at(states(layout), state)

def name(+variant: U32) -> U32:
  Blob.at(variants(variant), 0)

def layout_type(+variant: U32) -> U32:
  Blob.at(variants(variant), 1)

# layout.scale as f64 (hi, lo).
def scale(+variant: U32) -> U32 & U32:
  Blob.f64(variants(variant), 2)

def flags(+variant: U32) -> U32:
  Blob.at(variants(variant), 6)

def has(+variant: U32, +flag: U32) -> Bool:
  U32.is_ne((flags(variant) .&. flag : U32), 0)

def force_rotation(+variant: U32) -> U32:
  Blob.at(variants(variant), 7)

def start_mask(+variant: U32) -> U32:
  Blob.at(variants(variant), 8)

def fill_mask(+variant: U32) -> U32:
  Blob.at(variants(variant), 9)

def layout_position(+variant: U32) -> U32:
  Blob.at(variants(variant), 10)

def ground_size(+variant: U32) -> U32:
  Blob.at(variants(variant), 11)

def min_dist_from_land(+variant: U32) -> U32:
  Blob.at(variants(variant), 12)

def ground_half(odd: Bool, +u: U32) -> U32:
  match odd:
    case True{}:
      (u >> 10n : U32)
    case False{}:
      (u .&. 1023 : U32)

# Ground tile k (row-major) of a variant.
def ground_tile(+variant: U32, +k: U32) -> U32:
  ground_half(U32.is_ne((k .&. 1 : U32), 0), Blob.at(ground(variant), (k >> 1n : U32)))
''')
    if sys.argv[-1:] == ["-"]:
        sys.stdout.write(m.text())
    else:
        (blob.ROOT / "seedfinder" / "data" / f"{m.name}.bend").write_text(m.text())


if __name__ == "__main__":
    main()
