#!/usr/bin/env python3
"""Writes data/rooms.bend from out/story.json: every room reachable on the default forest path (task rooms,
background, cove, entrance, start, blank and ocean rooms) with its contents in the pairs() order the use sites see,
per deepcopy depth (depth 1: Story:GetRoom, the task rooms, entrance rooms, the start node and the ocean rooms;
depth 2: the background and cove rooms, deepcopies of a GetRoom template), plus the Lua 5.1 node layout of
countstaticlayouts at each depth (InsertAdditionalSetPieces inserts into it). `-` prints the module instead."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402
import union  # noqa: E402

KIND_INTEGER, KIND_CLOSURE, KIND_WEIGHT, KIND_SWAPPABLE = range(4)
FLAG_CONTENTS, FLAG_DISTRIBUTE_PERCENT, FLAG_USES_FILTERS, FLAG_CUSTOM_TILES, FLAG_CUSTOM_OBJECTS, FLAG_SAFE = (
    1, 2, 4, 8, 16, 32)
FIELDS = ("countprefabs", "countstaticlayouts", "distributeprefabs", "prefabdata")
FIELD_FLAGS = {"countprefabs": 64, "countstaticlayouts": 128, "distributeprefabs": 256, "prefabdata": 512}


def value_units(v, swappables, weight):
    if isinstance(v, dict) and "closure" in v:
        return [KIND_CLOSURE, ids.closure_id(v["closure"])]
    if isinstance(v, dict) and "prefabs" in v:
        prefabs = [v["prefabs"][str(i)] for i in range(1, len(v["prefabs"]) + 1)]
        row = [ids.weight_id(v["weight"])] + [ids.sid(p) for p in prefabs]
        if row not in swappables:
            swappables.append(row)
        return [KIND_SWAPPABLE, swappables.index(row)]
    if isinstance(v, bool):
        raise ValueError(v)
    if isinstance(v, int) and not weight:
        return [KIND_INTEGER, blob.unit(v)]
    return [KIND_WEIGHT, ids.weight_id(v)]


def entries_row(view, field, swappables):
    row = []
    for e in (view or {}).get(field, {}).get("entries", []):
        row += [ids.sid(e["key"])] + value_units(e["value"], swappables, field == "distributeprefabs")
        if field == "countstaticlayouts":
            row.append(ids.layout_index(e["key"]))
    return row


def snapshot_row(snapshot):
    if snapshot is None:
        return []
    row = [snapshot["lsizenode"], snapshot["lastfree"], snapshot["sizearray"], 1 if snapshot["dummy"] else 0]
    for slot in snapshot["slots"]:
        key = slot["key"]
        row += [ids.sid(key) if isinstance(key, str) else blob.NONE, blob.NONE if slot["next"] < 0 else slot["next"],
                1 if slot["live"] else 0]
    return row


def check_swappable_orders(story):
    recorded = {}
    for room in union.distribute()["rooms"]:
        for depth, d in enumerate(room["depths"], 1):
            for sw in d["swappable"]:
                recorded[(room["name"], depth, sw["key"])] = sw["prefabs"]
    for r in story["rooms"]:
        for depth in (1, 2):
            view = r["contents"].get(f"depth{depth}") or {}
            for e in (view.get("distributeprefabs") or {}).get("entries", []):
                if isinstance(e["value"], dict):
                    by_index = [e["value"]["prefabs"][str(i)] for i in range(1, len(e["value"]["prefabs"]) + 1)]
                    assert recorded[(r["name"], depth, e["key"])] == by_index, (r["name"], e["key"])


TAG_KINDS = {None: 0, "TAG": 1, "GLOBALTAG": 2, "ITEM": 3, "STATIC": 4}


def maptag_rows():
    rows = []
    for tag in ids.maptags():
        results = tag["results"]
        kinds = {r["first"].get("kind") for r in results}
        assert len(kinds) <= 1
        kind = TAG_KINDS[next(iter(kinds))] if kinds else 0
        one_shot = 1 if all(not r["second"] for r in results) and results else 0
        values = []
        for r in results:
            v = r["first"].get("value")
            if isinstance(v, str):
                values.append(ids.sid(v) if kind != 4 else ids.layout_index(v))
            elif v is not None:
                values += [blob.NONE, blob.unit(v)]
        closure = ids.closure_id(tag["closure"]) if tag.get("closure") else blob.NONE
        rows.append([ids.sid(tag["tag"]), closure, kind, one_shot, len(results)] + values)
    return rows


def main():
    story = union.story()
    check_swappable_orders(story)
    rooms = sorted(story["rooms"], key=lambda r: ids.room_index(r["name"]))
    assert [ids.room_index(r["name"]) for r in rooms] == list(range(len(rooms)))
    info, tags, required = [], [], []
    per_depth = {f: [] for f in FIELDS}
    snapshots, generate_orders = [], []
    swappables = []
    for r in rooms:
        c = r["contents"].get("depth1")
        flags = 0
        percent = None
        if c is not None:
            flags |= FLAG_CONTENTS
            if c.get("distributepercent") is not None:
                flags |= FLAG_DISTRIBUTE_PERCENT
                percent = c["distributepercent"]
            if c.get("countprefabs_uses_filters"):
                flags |= FLAG_USES_FILTERS
            for field in FIELDS:
                if field in c:
                    flags |= FIELD_FLAGS[field]
        flags |= FLAG_CUSTOM_TILES if r["custom_tiles"] else 0
        flags |= FLAG_CUSTOM_OBJECTS if r["custom_objects"] else 0
        flags |= FLAG_SAFE if r.get("SafeFromDisconnect") else 0
        optional = [r.get(k) for k in ("internal_type", "random_node_exit_weight", "random_node_entrance_weight")]
        assert all(v is None or (isinstance(v, int) and not isinstance(v, bool)) for v in optional)
        info.append([ids.sid(r["name"]), r["value"], r["type"] if r.get("type") is not None else blob.NONE, flags]
                    + blob.f64(percent or 0.0) + blob.word(blob.random_threshold(percent) if percent else 0)
                    + [blob.NONE if v is None else blob.unit(v) for v in optional])
        tags.append([ids.sid(t) for t in (r.get("tags") or {}).get("ipairs", [])])
        required.append([ids.sid(p) for p in r.get("required_prefabs") or []])
        for depth in ("depth1", "depth2"):
            view = r["contents"].get(depth)
            for field in FIELDS:
                per_depth[field].append(entries_row(view, field, swappables))
            csl = (view or {}).get("countstaticlayouts")
            snapshots.append(snapshot_row(csl["snapshot"] if csl else None))
            cp = (view or {}).get("countprefabs")
            generate_orders.append([ids.sid(k) for k in cp["generate_order"]] if cp else [])
    start = next(r for r in rooms if r.get("start"))
    m = blob.Module("rooms", "scripts/gen/gen_rooms.py",
                    "Rooms reachable on the default forest path, indexed by room (their names sorted by bytes).")
    m.comment("Value kinds of the (key, kind, value) triples below: 0 integer literal, 1 closure id (data/closures.bend),",
              "2 weight id (the weights table, f64 bits), 3 swappable id (the swappables table).",
              "Per-depth tables have row 2 * room + depth - 1 (depth 1 or 2); keys are string ids (data/strings.bend).",
              "distributeprefabs numbers are always weights (kind 2); countprefabs / countstaticlayouts are integers.",
              "countstaticlayouts entries are (key, kind, value, layout) quadruples, layout = row in data/layouts.bend.")
    m.const("kind_integer", KIND_INTEGER)
    m.const("kind_closure", KIND_CLOSURE)
    m.const("kind_weight", KIND_WEIGHT)
    m.const("kind_swappable", KIND_SWAPPABLE)
    for name, value in (("contents", FLAG_CONTENTS), ("distribute_percent", FLAG_DISTRIBUTE_PERCENT),
                        ("uses_filters", FLAG_USES_FILTERS), ("custom_tiles", FLAG_CUSTOM_TILES),
                        ("custom_objects", FLAG_CUSTOM_OBJECTS), ("safe_from_disconnect", FLAG_SAFE)):
        m.const(f"flag_{name}", value)
    for field in FIELDS:
        m.const(f"flag_{field}", FIELD_FLAGS[field])
    m.table("rooms", info, "Row room: name (string id), value (tile), type (NODE_TYPE, NONE when unset), flags, "
                           "distributepercent "
                           "(f64, 4 units), the math.random() < distributepercent threshold (U32, 2 units), "
                           "internal_type, random_node_exit_weight, random_node_entrance_weight (NONE when unset).")
    m.table("room_tags", tags, "Row room: the room's tags (ipairs order).")
    m.table("room_required_prefabs", required, "Row room: required_prefabs.")
    for field in FIELDS:
        m.table(f"room_{field}", per_depth[field], f"Row 2 * room + depth - 1: contents.{field} in pairs() order, "
                                                   "as (key, kind, value) triples.")
    m.table("room_generate_order", generate_orders, "Row 2 * room + depth - 1: pairs() order of PopulateVoronoi's "
                                                    "generate_these (keys inserted in countprefabs order).")
    m.table("room_countstaticlayouts_layout", snapshots,
            "Row 2 * room + depth - 1: Lua 5.1 layout of contents.countstaticlayouts: lsizenode, lastfree (node index), "
            "sizearray, 1 if the node part is the dummy node, then per node: key string id (NONE = nil key), "
            "next node index (NONE = none), 1 if the value is non-nil. Empty when the room has none.")
    m.table("swappables", swappables, "Row id: weight id, then the choices (string ids) in pairs() order.")
    m.table("weights", [blob.f64(w) for w in ids.weights()], "Row id: a distribute weight as f64 bits (4 units).")
    m.table("maptags", maptag_rows(), "Row i (tags sorted by string id): tag string id, closure id, kind of the first "
                                      "call (0 none, 1 TAG, 2 GLOBALTAG, 3 ITEM, 4 STATIC), 1 if a second call on the "
                                      "same tagdata returns nothing (one-shot), n, then the n possible values: string "
                                      "ids, or for Terrarium_Spawner the layouts, value k = math.random(n) = k + 1; a "
                                      "numeric TAG value is stored as NONE followed by the number. Values are layouts "
                                      "for STATIC, string ids otherwise.")
    cave_room_names = sorted((r["name"] for r in blob.sidecar("caves.json")["story"]["rooms"]), key=lambda n: n.encode())
    assert set(cave_room_names) == {r["name"] for r in blob.sidecar("story_caves.json")["rooms"]}
    m.table("cave_rooms", [[ids.room_index(n)] for n in cave_room_names],
            "Row cave story room (data/cave_story.bend's room ids, sorted by name bytes): its row in this module.")
    m.const("forest_room_count", ids.table()["forest_room_count"])
    m.const("start_room", ids.room_index(start["name"]))
    m.table("start_countprefabs", [[ids.sid(k) for k in start["start"]["countprefabs"]],
                                   [ids.sid(k) for k in start["start"]["generate_order"]]],
            "The start node (depth 1, spawnpoint removed by AddStartingSetPiece): row 0 countprefabs keys in pairs() "
            "order, row 1 the generate_these order.")
    m.code('''
def row_of(+room: U32, +depth: U32) -> U32:
  (((room * 2 : U32) + depth : U32) - 1 : U32)

def name(+room: U32) -> U32:
  Blob.at(rooms(room), 0)

def value(+room: U32) -> U32:
  Blob.at(rooms(room), 1)

def node_type(+room: U32) -> U32:
  Blob.at(rooms(room), 2)

def flags(+room: U32) -> U32:
  Blob.at(rooms(room), 3)

def has(+room: U32, +flag: U32) -> Bool:
  U32.is_ne((flags(room) .&. flag : U32), 0)

# distributepercent as f64 (hi, lo).
def distribute_percent(+room: U32) -> U32 & U32:
  Blob.f64(rooms(room), 4)

# math.random() < distributepercent holds exactly when the PCG output is below this.
def distribute_threshold(+room: U32) -> U32:
  Blob.word(rooms(room), 8)

def internal_type(+room: U32) -> U32:
  Blob.at(rooms(room), 10)

def random_node_exit_weight(+room: U32) -> U32:
  Blob.at(rooms(room), 11)

def random_node_entrance_weight(+room: U32) -> U32:
  Blob.at(rooms(room), 12)

# The row of a room of data/cave_story.bend in this module.
def from_cave_room(+cave_room: U32) -> U32:
  Blob.at(cave_rooms(cave_room), 0)

# A distribute weight as f64 (hi, lo).
def weight(+id: U32) -> U32 & U32:
  Blob.f64(weights(id), 0)
''')
    m.emit()


if __name__ == "__main__":
    main()
