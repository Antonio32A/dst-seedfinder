#!/usr/bin/env python3
"""Writes data/cave_story.bend from out/caves.json: the story level data of the caves shard (task set cave_default,
start location caves): the tasks after Level:EnqueueATask's deepcopy, the rooms they reach, those rooms' map tags, the
lock table and the room_choices count closures. Ids are cave-local and dense: tasks in data/cave_catalog.bend's order,
rooms sorted by name bytes, tags sorted by name bytes. `-` prints the module instead."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402

KIND_INTEGER, KIND_CLOSURE = 0, 1
DEFAULT_COVE_CHANCE = 0.35
DEFAULT_COVE_MAX_EDGES = 1
POISON_BITS = {"ForceConnected": 2, "RoadPoison": 4, "ForceDisconnected": 8}
FLAG_CUSTOM_TILES, FLAG_SAFE, FLAG_CUSTOM_OBJECTS = 1, 2, 4
TAG_KINDS = {None: 0, "TAG": 1, "GLOBALTAG": 2, "ITEM": 3}
RANDOM_BODY = re.compile(r"^function\(\) return (?:(\d+) ?\+ ?)?math\.random\((\d+)(?:, ?(\d+))?\) end$")


def optional_int(v):
    if v is None:
        return blob.NONE
    assert isinstance(v, (int, bool)), v
    return int(v)


def poison_bits(tags):
    return sum(POISON_BITS.get(t, 0) for t in tags)


def count_closure_row(closure):
    """A room_choices count closure as [0, a, b, c, 0], meaning a + math.random(b) - c; math.random(m, n) is
    floor(scale * (n - m + 1)) + m, so m >= 1 gives (m - 1, n - m + 1, 0) and m = 0 gives (0, n + 1, 1)."""
    m = RANDOM_BODY.match(closure["body"])
    assert m and not closure["globals"], closure["body"]
    prefix, first, last = int(m.group(1) or 0), int(m.group(2)), m.group(3)
    if last is None:
        return [0, prefix, first, 0, 0]
    assert not prefix, closure["body"]
    low, high = first, int(last)
    return [0, low - 1, high - low + 1, 0, 0] if low >= 1 else [0, 0, high + 1, 1, 0]


MAZE_DEFAULT_TILE_SIZE = 8
MAZE_KIND_PLAIN, MAZE_KIND_SPECIAL, MAZE_KIND_ARCHIVE = range(3)


def lua_list(table):
    """A Lua array the sidecar stores as {"1": ..., "2": ...}."""
    return [table[str(i)] for i in range(1, len(table) + 1)] if table else []


def maze_choices(layouts):
    return sorted(layouts["mazes"], key=lambda maze: maze["choice"].encode())


def maze_data(m, story_tasks, maze_constants):
    """The maze tables: the constants MAZE_TYPE and MAZE_CELL_EXITS, the maze layout choices (AllLayouts keys, sorted by
    name bytes) with the layout row of each cell type, and per task the fields of task.maze_tiles."""
    layouts = blob.sidecar("layouts_caves.json")
    choices = maze_choices(layouts)
    choice_id = {c["choice"]: i for i, c in enumerate(choices)}
    cells = maze_constants["cell_exits"]
    inverse = maze_constants["cell_exits_inv"]
    assert inverse == [name for name, _ in sorted(((n, v) for n, v in cells.items() if v), key=lambda kv: kv[1])]
    assert sorted(cells.values()) == list(range(len(cells))) and cells["NO_EXITS"] == 0
    for name, value in sorted(maze_constants["types"].items(), key=lambda kv: kv[1]):
        m.const(f"maze_type_{name.removeprefix('MAZE_').lower()}", value)
    for name, value in sorted(cells.items(), key=lambda kv: kv[1]):
        m.const(f"maze_cell_{name.lower()}", value)
    m.const("maze_cell_type_count", len(cells))
    m.const("maze_kind_plain", MAZE_KIND_PLAIN)
    m.const("maze_kind_special", MAZE_KIND_SPECIAL)
    m.const("maze_kind_archive", MAZE_KIND_ARCHIVE)
    m.const("maze_default_tile_size", MAZE_DEFAULT_TILE_SIZE)
    m.table("maze_cell_names", [blob.text(n) for n in ["NO_EXITS"] + inverse],
            "Row cell type (MAZE_CELL_EXITS): the shape name MAZE_CELL_EXITS_INV gives (NO_EXITS for 0).")
    m.table("maze_choice_names", [blob.text(c["choice"]) for c in choices],
            "Row maze choice: the key of maze_layouts.AllLayouts (sorted by name bytes).")
    rows = []
    for c in choices:
        by_cell = {cell["shape"]: ids.layout_index(cell["name"]) for cell in c["shapes"]}
        rows.append([by_cell.get(name, blob.NONE) for name in ["NO_EXITS"] + inverse])
    m.table("maze_layouts", rows, "Row maze choice: per cell type (0 = NO_EXITS, then MAZE_CELL_EXITS order), the row "
                                  "in data/layouts.bend of maze_layouts.AllLayouts[choice][shape] (NONE when the "
                                  "choice has no layout for the shape; the special ones have the four SINGLE_ shapes).")
    fields = {"rooms": [], "bosses": [], "start": [], "finish": [], "keyroom": []}
    info = []
    for t in story_tasks:
        tiles = t.get("maze_tiles")
        kind = MAZE_KIND_PLAIN
        bridge = blob.NONE
        row = {name: [] for name in fields}
        if tiles:
            special = tiles.get("special") or {}
            archive = tiles.get("archive")
            kind = MAZE_KIND_ARCHIVE if archive is not None else MAZE_KIND_SPECIAL if special else MAZE_KIND_PLAIN
            bridge = tiles.get("bridge_ground", blob.NONE)
            row["rooms"] = lua_list(tiles.get("rooms"))
            row["bosses"] = lua_list(tiles.get("bosses"))
            row["start"] = lua_list(special.get("start"))
            row["finish"] = lua_list(special.get("finish"))
            row["keyroom"] = lua_list((archive or {}).get("keyroom"))
        info.append([t.get("maze_tile_size") or MAZE_DEFAULT_TILE_SIZE, kind, bridge])
        for name in fields:
            fields[name].append([choice_id[c] for c in row[name]])
    m.table("task_maze_info", info, "Row task: maze_tile_size (default 8), the shape of maze_tiles (0 plain: rooms and "
                               "bosses; 1 special: also special.start and special.finish; 2 archive: also "
                               "archive.keyroom), bridge_ground (a tile, NONE when unset). Meaningful for tasks with "
                               "the maze flag.")
    m.code('''
def task_maze_size(+task: U32) -> U32:
  Blob.at(task_maze_info(task), 0)

def task_maze_kind(+task: U32) -> U32:
  Blob.at(task_maze_info(task), 1)

def task_maze_bridge_ground(+task: U32) -> U32:
  Blob.at(task_maze_info(task), 2)

def maze_layout(+choice: U32, +cell: U32) -> U32:
  Blob.at(maze_layouts(choice), cell)

def maze_choice_name(+choice: U32) -> String:
  Blob.text(maze_choice_names(choice))

def maze_cell_name(+cell: U32) -> String:
  Blob.text(maze_cell_names(cell))
''')
    docs = {"rooms": "maze_tiles.rooms", "bosses": "maze_tiles.bosses", "start": "maze_tiles.special.start",
            "finish": "maze_tiles.special.finish", "keyroom": "maze_tiles.archive.keyroom"}
    for name, rows_of in fields.items():
        m.table(f"task_maze_{name}", rows_of, f"Row task: {docs[name]} as maze choice ids, in list order.")


def post_data(m, caves, story_tasks, rooms):
    """The strings (global ids of data/strings.bend) the required prefab check needs."""
    def sids(names):
        return [ids.sid(n) for n in names or []]

    m.table("task_required_prefabs", [sids(t.get("required_prefabs")) for t in story_tasks],
            "Row task: task.required_prefabs (string ids).")
    m.table("room_required_prefabs", [sids(r.get("required_prefabs")) for r in rooms],
            "Row room: room.required_prefabs (string ids).")
    m.table("taskset_required_prefabs", [sids(caves["taskset"]["required_prefabs"])],
            "Row 0: the task set's required_prefabs (string ids, repeats kept).")
    m.table("level_required_prefabs", [sids(caves["level"]["required_prefabs"])],
            "Row 0: the level's required_prefabs (string ids).")
    m.const("wormhole_prefab", ids.sid(caves["level"]["overrides"]["wormhole_prefab"]))


def main():
    caves = blob.sidecar("caves.json")
    story = caves["story"]
    task_names = caves["taskset"]["tasks"] + caves["taskset"]["optionaltasks"]
    tasks = story["tasks"]
    assert [t["id"] for t in tasks] == task_names and len(tasks) == 51
    task_id = {name: i for i, name in enumerate(task_names)}

    rooms = sorted(story["rooms"], key=lambda r: r["name"].encode())
    room_id = {r["name"]: i for i, r in enumerate(rooms)}
    reached = {n for t in tasks for n in [t["background_room"], t.get("cove_room_name") or "Blank"]}
    reached |= {n for t in tasks for n in (t.get("entrance_room") if isinstance(t.get("entrance_room"), list)
                                           else [t.get("entrance_room")]) if n}
    reached |= {e["key"] for t in tasks for e in t["room_choices"]}
    reached |= set(caves["start_location"]["start_node"]) | {"BGImpassable", "Blank"}
    assert reached == set(room_id), reached ^ set(room_id)

    tags = sorted(story["tags"], key=lambda t: t["tag"].encode())
    tag_id = {t["tag"]: i for i, t in enumerate(tags)}
    assert set(tag_id) == {x for r in rooms for x in r["tags"]} | {x for t in tasks for x in t["room_tags"]}

    closure_id = {c["key"]: i for i, c in enumerate(story["closures"])}

    room_names = [blob.text(r["name"]) for r in rooms]
    room_rows = []
    for r in rooms:
        flags = (FLAG_CUSTOM_TILES if r["custom_tiles"] else 0) | (FLAG_SAFE if r["SafeFromDisconnect"] else 0) | (
            FLAG_CUSTOM_OBJECTS if r["custom_objects"] else 0)
        room_rows.append([r["value"], optional_int(r.get("type")), optional_int(r.get("internal_type")),
                          optional_int(r.get("random_node_exit_weight")), optional_int(r.get("random_node_entrance_weight")),
                          flags, poison_bits(r["tags"])])
    room_tag_rows = [[tag_id[x] for x in r["tags"]] for r in rooms]

    ca_names = sorted({layer["item"] for r in rooms if r.get("ca") for layer in
                       r["ca"]["translate"] + ([r["ca"]["centroid"]] if r["ca"].get("centroid") else [])},
                      key=lambda n: n.encode())
    ca_item = {n: i for i, n in enumerate(ca_names)}
    ca_rows, ca_layer_rows = [], []
    for r in rooms:
        ca = r.get("ca")
        centroid = (ca or {}).get("centroid")
        ca_rows.append([blob.NONE] * 7 if not ca else [
            ca["iterations"], ca["seed_mode"], ca["num_random_points"], len(ca["translate"]),
            centroid["tile"] if centroid else blob.NONE, centroid["item_count"] if centroid else blob.NONE,
            ca_item[centroid["item"]] if centroid else blob.NONE])
        ca_layer_rows.append([u for layer in (ca or {}).get("translate", [])
                              for u in (layer["tile"], layer["item_count"], ca_item[layer["item"]])])

    tag_rows, tag_text = [], []
    for t in tags:
        first, second = t["first"], t["second"]
        assert first.get("kind") in TAG_KINDS, t
        value = first.get("value")
        tag_rows.append([TAG_KINDS[first.get("kind")], 1 if first and not second else 0])
        tag_text.append(blob.text(value if isinstance(value, str) else ""))

    task_tag_rows = [[tag_id[x] for x in t["room_tags"]] for t in tasks]
    task_rows, locks, keys, choices, entrance_choices = [], [], [], [], []
    for t in tasks:
        entrance = t.get("entrance_room")
        is_list = isinstance(entrance, list)
        chance = t.get("cove_room_chance")
        chance = DEFAULT_COVE_CHANCE if chance is None else chance
        task_rows.append([0 if t["kind"] == "required" else 1, optional_int(t.get("room_bg")),
                          room_id[t["background_room"]], room_id[t.get("cove_room_name") or "Blank"],
                          room_id[entrance] if entrance and not is_list else blob.NONE, 1 if is_list else 0,
                          optional_int(t.get("cove_room_chance")), optional_int(t.get("cove_room_max_edges")),
                          optional_int(t.get("crosslink_factor")), optional_int(t.get("make_loop")),
                          1 if t["maze"] else 0, poison_bits(t["room_tags"])]
                         + blob.word(blob.random_threshold(chance) if chance > 0 else 0))
        entrance_choices.append([room_id[n] for n in entrance] if is_list else [])
        locks.append([t["locks"]["length"]] + t["locks"]["ipairs"])
        keys.append([t["keys_given"]["length"]] + t["keys_given"]["ipairs"])
        row = []
        for e in t["room_choices"]:
            v = e["value"]
            row += [room_id[e["key"]]] + ([KIND_CLOSURE, closure_id[v["closure"]]] if isinstance(v, dict)
                                          else [KIND_INTEGER, v])
        choices.append(row)

    locks_keys = story["locks_keys"]
    lock_rows = []
    for lock in range(max(int(k) for k in locks_keys) + 1):
        entry = locks_keys.get(str(lock))
        lock_rows.append([entry["length"]] + entry["ipairs"] if entry else [])

    starts = [room_id[n] for n in caves["start_location"]["start_node"]]

    m = blob.Module("cave_story", "scripts/gen/gen_cave_story.py",
                    "Story level data of the caves shard (task set cave_default): tasks (ids as in "
                    "data/cave_catalog.bend), rooms (sorted by name bytes) and tags (sorted by name bytes).")
    m.table("room_names", room_names, "Row room: the room name (Blob.text).")
    m.table("rooms", room_rows, "Row room: value (tile), type (NODE_TYPE), internal_type, random_node_exit_weight, "
                                "random_node_entrance_weight (NONE when unset), flags (1 custom_tiles, 2 "
                                "SafeFromDisconnect, 4 custom_objects), poison (2 ForceConnected, 4 RoadPoison, 8 "
                                "ForceDisconnected from the tags).")
    m.table("room_tags", room_tag_rows, "Row room: the room's tag ids in ipairs order.")
    m.table("ca_rows", ca_rows, "Row room: RunCA iterations, seed_mode (CA_SEED_MODE), num_random_points, #translate, "
                                "centroid tile, centroid item_count, centroid item (ca_items index); all NONE for a "
                                "room without custom_tiles, the centroid ones also without a centroid field.")
    m.table("room_ca_layers", ca_layer_rows, "Row room: the RunCA translate layers in table order as (tile, "
                                             "item_count, items[1] as a ca_items index) triples.")
    m.table("ca_items", [blob.text(n) for n in ca_names], "Row i: a RunCA layer's first item prefab (Blob.text).")
    m.table("tag_names", [blob.text(t["tag"]) for t in tags], "Row tag: the tag name (Blob.text).")
    m.table("tag_values", tag_text, "Row tag: the value the map tag function returns (Blob.text, empty when none).")
    m.table("tags", tag_rows, "Row tag: kind of the first call (0 none, 1 TAG, 2 GLOBALTAG, 3 ITEM), 1 when a second "
                              "call on the same tagdata returns nothing.")
    m.table("tasks", task_rows, "Row task: kind (0 required, 1 optional), room_bg (tile), background_room, "
                                "cove room (Blank when unset), entrance_room (NONE when none or a list), 1 when the "
                                "entrance is a list, cove_room_chance, cove_room_max_edges, crosslink_factor, "
                                "make_loop (NONE when unset), 1 with maze_tiles, room_tags poison bits, the "
                                "math.random() < cove chance threshold (U32, 2 units; the chance defaults to 0.35).")
    m.table("task_entrance_choices", entrance_choices, "Row task: the room ids of a list entrance_room in list order.")
    m.table("task_room_tags", task_tag_rows, "Row task: the tag ids of task.room_tags in ipairs order.")
    m.table("task_locks", locks, "Row task: #locks, then the locks in ipairs order (LOCKS ids).")
    m.table("task_keys_given", keys, "Row task: #keys_given, then ipairs order.")
    m.table("locks_keys", lock_rows, "Row lock id: #LOCKS_KEYS[lock], then its keys (only the locks cave tasks use).")
    m.table("task_room_choices", choices, "Row task: room_choices in pairs() order as (room, kind, value) triples; "
                                          "kind 0 integer count, 1 index into count_closures.")
    m.table("count_closures", [count_closure_row(c) for c in story["closures"]],
            "Row closure: [0, a, b, c, 0] meaning a + math.random(b) - c, with U32 wrap-around when c exceeds a.")
    m.table("start_rooms", [starts], "Row 0: the start_node rooms of the caves start location in order.")
    story_caves = blob.sidecar("story_caves.json")
    assert [t["id"] for t in story_caves["tasks"]] == task_names
    assert {r["name"] for r in story_caves["rooms"]} == set(room_id)
    story_rooms = {r["name"]: r for r in story_caves["rooms"]}
    maze_data(m, story_caves["tasks"], caves["maze"])
    post_data(m, caves, story_caves["tasks"], [story_rooms[r["name"]] for r in rooms])
    m.const("room_count", len(rooms))
    m.const("tag_count", len(tags))
    m.const("start_room_count", len(starts))
    m.const("default_cove_max_edges", DEFAULT_COVE_MAX_EDGES)
    accessors = []
    for name, table, column in (
            ("room_value", "rooms", 0), ("room_node_type", "rooms", 1), ("room_internal_type", "rooms", 2),
            ("room_exit_weight", "rooms", 3), ("room_entrance_weight", "rooms", 4), ("room_flags", "rooms", 5),
            ("room_poison", "rooms", 6), ("tag_kind", "tags", 0), ("tag_once", "tags", 1),
            ("room_ca_iterations", "ca_rows", 0), ("room_ca_seed_mode", "ca_rows", 1),
            ("room_ca_random_points", "ca_rows", 2), ("room_ca_layer_count", "ca_rows", 3),
            ("room_ca_centroid_tile", "ca_rows", 4), ("room_ca_centroid_count", "ca_rows", 5),
            ("room_ca_centroid_item", "ca_rows", 6), ("task_kind", "tasks", 0), ("task_room_bg", "tasks", 1), ("task_background_room", "tasks", 2),
            ("task_cove_room", "tasks", 3), ("task_entrance_room", "tasks", 4),
            ("task_entrance_is_list", "tasks", 5), ("task_cove_room_chance", "tasks", 6),
            ("task_cove_room_max_edges", "tasks", 7), ("task_crosslink_factor", "tasks", 8),
            ("task_make_loop", "tasks", 9), ("task_maze", "tasks", 10), ("task_room_poison", "tasks", 11)):
        accessors.append(f"def {name}(+i: U32) -> U32:\n  Blob.at({table}(i), {column})\n")
    accessors.append("def task_cove_threshold(+i: U32) -> U32:\n  Blob.word(tasks(i), 12)\n")
    accessors.append("def start_room(+k: U32) -> U32:\n  Blob.at(start_rooms(0), k)\n")
    for name, table in (("room_name", "room_names"), ("ca_item_name", "ca_items"), ("tag_name", "tag_names"), ("tag_value", "tag_values")):
        accessors.append(f"def {name}(+i: U32) -> String:\n  Blob.text({table}(i))\n")
    m.code("\n".join(accessors))

    text = m.text()
    parsed = blob.parse_module_tables(text)
    assert parsed["task_locks"] == locks and parsed["task_keys_given"] == keys
    assert parsed["task_room_choices"] == choices and parsed["locks_keys"] == lock_rows
    assert len(parsed["rooms"]) == len(rooms) and len(parsed["tasks"]) == 51
    for t in tasks:
        for field in ("locks", "keys_given"):
            by_key = {p["key"]: p["value"] for p in t[field]["pairs"]}
            prefix = []
            while len(prefix) + 1 in by_key:
                prefix.append(by_key[len(prefix) + 1])
            assert prefix == t[field]["ipairs"], (t["id"], field)
    m.emit()


if __name__ == "__main__":
    main()
