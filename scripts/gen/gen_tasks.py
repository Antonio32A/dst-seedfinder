#!/usr/bin/env python3
"""Writes data/tasks.bend from out/story.json: the tasks of task set "default" (after Level:EnqueueATask's
deepcopy, which is what storygen iterates), LOCKS_KEYS, the task set lists and the level fields storygen reads.
`-` prints the module instead."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402

KIND_INTEGER, KIND_CLOSURE = 0, 1
DEFAULT_COVE_CHANCE = 0.35
DEFAULT_COVE_MAX_EDGES = 1


def optional_int(v):
    if v is None:
        return blob.NONE
    assert isinstance(v, (int, bool)), v
    return int(v)


def count_units(v):
    if isinstance(v, dict):
        return [KIND_CLOSURE, ids.closure_id(v["closure"])]
    assert isinstance(v, int), v
    return [KIND_INTEGER, v]


def main():
    story = blob.sidecar("story.json")
    tasks = sorted(story["tasks"], key=lambda t: ids.sid(t["id"]))
    assert [ids.sid(t["id"]) for t in tasks] == list(range(len(tasks)))
    info, locks, keys, choices, tags, required = [], [], [], [], [], []
    for t in tasks:
        assert t.get("entrance_room_chance") is None and t.get("hub_room") is None and t.get("maze_tiles") is None
        assert not isinstance(t.get("entrance_room"), list) and t.get("room_choices_special") is None
        chance = t.get("cove_room_chance")
        chance = DEFAULT_COVE_CHANCE if chance is None else chance
        info.append([0 if t["kind"] == "required" else 1, t["room_bg"], ids.room_index(t["background_room"]),
                     ids.room_index(t.get("cove_room_name") or "Blank"),
                     ids.room_index(t["entrance_room"]) if t.get("entrance_room") else blob.NONE,
                     optional_int(t.get("cove_room_chance")), optional_int(t.get("cove_room_max_edges")),
                     optional_int(t.get("crosslink_factor")), optional_int(t.get("make_loop")),
                     ids.sid(t["region_id"]) if t.get("region_id") else blob.NONE,
                     optional_int(t.get("level_set_piece_blocker"))]
                    + blob.word(blob.random_threshold(chance) if chance > 0 else 0))
        locks.append([t["locks"]["length"]] + t["locks"]["ipairs"])
        keys.append([t["keys_given"]["length"]] + t["keys_given"]["ipairs"])
        row = []
        for e in t["room_choices"]:
            row += [ids.room_index(e["key"])] + count_units(e["value"])
        choices.append(row)
        room_tags = t.get("room_tags") or {"ipairs": [], "length": 0}
        tags.append([room_tags["length"]] + [ids.sid(x) for x in room_tags["ipairs"]])
        required.append([ids.sid(p) for p in t.get("required_prefabs") or []])
    locks_keys = story["locks_keys"]
    max_lock = max(int(k) for k in locks_keys)
    lock_rows = []
    for lock in range(max_lock + 1):
        entry = locks_keys.get(str(lock))
        lock_rows.append([entry["length"]] + entry["ipairs"] if entry else [])
    ts, level = story["taskset"], story["level"]
    lists = [
        [ids.sid(n) for n in ts["tasks"]],
        [ids.sid(n) for n in ts["optionaltasks"]],
        [ids.sid(n) for n in ts["valid_start_tasks"]],
        [ids.sid(n) for n in ts["required_prefabs"]],
        [ids.room_index(n) for n in ts["ocean_population"]],
        [u for p in ts["ocean_prefill_setpieces"] for u in (ids.layout_index(p["name"]), p["count"])],
        [ids.layout_index(n) for n in level["required_setpieces"]],
        [ids.layout_index(n) for n in level["random_set_pieces"]],
        [ids.sid(n) for n in level["required_prefabs"]],
        [ids.room_index(n) for n in level["ocean_population"]],
    ]
    m = blob.Module("tasks", "scripts/gen/gen_tasks.py",
                    "Tasks of task set \"default\" (row = task id = string id), lock keys, task set and level lists.")
    m.table("tasks", info, "Row task: kind (0 required, 1 optional), room_bg (tile), background_room (room), "
                           "cove room (room, Blank when unset), entrance_room (room or NONE), cove_room_chance, "
                           "cove_room_max_edges, crosslink_factor, make_loop, region_id (string id), "
                           "level_set_piece_blocker (NONE when unset), the math.random() < cove chance threshold "
                           "(U32, 2 units; the chance defaults to 0.35).")
    m.table("task_locks", locks, "Row task: #locks, then the locks in ipairs order (LOCKS ids).")
    m.table("task_keys_given", keys, "Row task: #keys_given, then ipairs order (a nil key ends ipairs early).")
    m.table("task_room_choices", choices, "Row task: room_choices in pairs() order as (room, kind, value) triples; "
                                          "kind 0 integer count, 1 closure id (data/closures.bend).")
    m.table("task_room_tags", tags, "Row task: #room_tags, then ipairs order (string ids).")
    m.table("task_required_prefabs", required, "Row task: required_prefabs (string ids).")
    m.table("locks_keys", lock_rows, "Row lock id: #LOCKS_KEYS[lock], then its keys (only the locks default tasks use).")
    m.table("lists", lists, "Row 0 taskset.tasks, 1 optionaltasks, 2 valid_start_tasks (task ids), 3 taskset "
                            "required_prefabs (string ids), 4 taskset ocean_population (rooms), 5 "
                            "ocean_prefill_setpieces in pairs() order as (layout, count), 6 level required_setpieces, "
                            "7 level random_set_pieces (layouts), 8 level required_prefabs (string ids), 9 level "
                            "ocean_population (rooms).")
    m.const("task_count", len(tasks))
    m.const("numoptionaltasks", ts["numoptionaltasks"])
    m.const("numrandom_set_pieces", level["numrandom_set_pieces"])
    m.const("start_setpiece", ids.layout_index(level["start_setpeice"]))
    m.const("start_node", ids.room_index(level["start_node"]))
    m.const("size_variation", story["size_variation"])
    m.const("default_cove_max_edges", DEFAULT_COVE_MAX_EDGES)
    m.code('''
def kind(+task: U32) -> U32:
  Blob.at(tasks(task), 0)

def room_bg(+task: U32) -> U32:
  Blob.at(tasks(task), 1)

def background_room(+task: U32) -> U32:
  Blob.at(tasks(task), 2)

def cove_room(+task: U32) -> U32:
  Blob.at(tasks(task), 3)

def entrance_room(+task: U32) -> U32:
  Blob.at(tasks(task), 4)

def cove_room_chance(+task: U32) -> U32:
  Blob.at(tasks(task), 5)

def cove_room_max_edges(+task: U32) -> U32:
  Blob.at(tasks(task), 6)

def crosslink_factor(+task: U32) -> U32:
  Blob.at(tasks(task), 7)

def make_loop(+task: U32) -> U32:
  Blob.at(tasks(task), 8)

def region_id(+task: U32) -> U32:
  Blob.at(tasks(task), 9)

def level_set_piece_blocker(+task: U32) -> U32:
  Blob.at(tasks(task), 10)

# math.random() < (cove_room_chance or 0.35) holds exactly when the PCG output is below this.
def cove_threshold(+task: U32) -> U32:
  Blob.word(tasks(task), 11)
''')
    m.emit()


if __name__ == "__main__":
    main()
