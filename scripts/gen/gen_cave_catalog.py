#!/usr/bin/env python3
"""Generates data/cave_catalog.bend: the caves shard's level table inputs (DST_CAVE, task set cave_default) from the
sidecars caves.json and layouts.json: task numbering, the level.set_pieces key table, the sandboxes AddSetPeices draws
from, the prefab swaps and the level fields later stages read.

Run from the project root:
    python3 scripts/gen/gen_cave_catalog.py    (writes seedfinder/data/cave_catalog.bend; `-` prints it instead)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import model  # noqa: E402
from gen_catalog import nibbles  # noqa: E402

SANDBOXES = [("traps", "traps"), ("points_of_interest", "pointsofinterest"),
             ("protected_resources", "protected_resources"), ("boons", "boons")]
SWAP_CATEGORIES = ["grass", "twigs", "berries"]
NO_AREA = 31
MAX_KEYS = 63
SWAP_WEIGHTS = (3, 1)


def quoted(s):
    assert s.isascii() and '"' not in s and "\\" not in s, s
    return '"' + s + '"'


def u32_match(name, arg, rows, result="U32", default="0"):
    lines = [f"def {name}(+{arg}: U32) -> {result}:", f"  match {arg}:"]
    for k, v in rows:
        lines += [f"    case {k}:", f"      {v}"]
    lines += ["    case _:", f"      {default}", ""]
    return "\n".join(lines)


def const(name, value, result="U32"):
    return f"def {name}() -> {result}:\n  {value}\n"


def names_list(name, pairs):
    rows = ",\n".join(f"    Name{{{quoted(n)}, {i}}}" for n, i in pairs)
    return f"def {name}() -> List<&2, Name>:\n  [\n{rows}\n  ]\n"


class Catalog:
    def __init__(self, caves, layouts):
        self.caves = caves
        taskset = caves["taskset"]
        assert not any(t.get("level_set_piece_blocker") for t in caves["tasks"]), "blocker tasks are not modelled"
        assert not caves["level"]["required_setpieces"] and not caves["level"]["random_set_pieces"]
        assert caves["level"]["numrandom_set_pieces"] == 0
        self.required = taskset["tasks"]
        self.optional = taskset["optionaltasks"]
        self.picked = taskset["numoptionaltasks"]
        self.tasks = self.required + self.optional
        self.task_id = {name: i for i, name in enumerate(self.tasks)}
        assert [t["id"] for t in caves["tasks"]] == self.tasks
        self.bg = {t["id"]: t.get("room_bg") for t in caves["tasks"]}
        self.tile_name = {number: name for name, number in caves["world_tiles"].items()}
        self.sandboxes = layouts["sandboxes"]
        self.assign_areas()
        self.assign_keys()

    def assign_areas(self):
        numbers = {bg for bg in self.bg.values() if bg is not None}
        numbers |= {a["area"] for boxes in self.sandboxes.values() for a in boxes if isinstance(a["area"], int)}
        self.area_numbers = sorted(numbers)
        assert len(self.area_numbers) < NO_AREA
        assert all(bg is None or isinstance(bg, int) for bg in self.bg.values())

    def area_code(self, area):
        return 0 if area in ("Any", "Rare") else 1 + self.area_numbers.index(area)

    def task_area(self, name):
        bg = self.bg[name]
        return NO_AREA if bg is None else self.area_code(bg)

    def placeable(self, area):
        return area in ("Any", "Rare") or area in {bg for bg in self.bg.values() if bg is not None}

    def assign_keys(self):
        taskset = self.caves["taskset"]
        self.fixed = {p["name"]: p for p in taskset["set_pieces"]}
        layout = taskset["set_pieces_layout"]
        assert [s["key"] for s in layout["slots"]] == [p["name"] for p in taskset["set_pieces"]]
        self.keys = [p["name"] for p in taskset["set_pieces"]]
        self.info = {}
        for fn, kind in SANDBOXES:
            rows = []
            for area in self.sandboxes[kind]:
                code = self.area_code(area["area"])
                for piece in area["pieces"]:
                    if not self.placeable(area["area"]):
                        rows.append(0)
                        continue
                    if piece not in self.keys:
                        self.keys.append(piece)
                    rows.append(self.keys.index(piece) + 1 | code << 8)
            self.info[fn] = rows
        assert len(self.keys) <= MAX_KEYS

    def key_id(self, name):
        return self.keys.index(name) + 1

    def base_nodes(self):
        layout = self.caves["taskset"]["set_pieces_layout"]
        return [(i, self.key_id(s["key"])) for i, s in enumerate(layout["slots"]) if s["key"] is not None], layout


def swap_rows(caves):
    categories = [s["category"] for s in caves["prefab_swaps"]]
    assert categories == SWAP_CATEGORIES, categories
    rows = []
    for swap in caves["prefab_swaps"]:
        valid = [s for s in swap["sets"] if s["valid"]]
        regular, swapped = swap["sets"]
        assert regular["primary"] and (regular["weight"], swapped["weight"]) == SWAP_WEIGHTS
        rows.append((swap["category"], regular["name"], swapped["name"], swapped["valid"]))
        assert valid[0] is regular
    return rows


def sandbox_lines(cat):
    out = []
    for fn, kind in SANDBOXES:
        boxes = cat.sandboxes[kind]
        sizes = [len(a["pieces"]) for a in boxes]
        rare = next(i for i, a in enumerate(boxes) if a["area"] == "Rare")
        lo, hi = nibbles(sizes)
        out.append(f"def {fn}() -> Catalog.Sandbox:\n  Catalog.Sandbox{{{len(boxes)}, {rare}, {lo}, {hi}, {lo}, {hi}}}\n")
        out.append(u32_match(f"{fn}_info", "id", [(i + 1, v) for i, v in enumerate(cat.info[fn]) if v]))
    return out


def main():
    cat = Catalog(blob.sidecar("caves.json"), blob.sidecar("layouts.json"))
    caves = cat.caves
    nodes, layout = cat.base_nodes()
    swaps = swap_rows(caves)
    hashes = {name: model.lua_string_hash(name) for name in cat.keys}
    out = ["# Generated by scripts/gen/gen_cave_catalog.py; do not edit by hand.", "import Base",
           "import ./catalog.bend as Catalog", "", "type Name is Data:", "  Name{name: String, id: U32}", ""]
    out.append("# Task ids: the task set's required tasks in order, then its optional tasks in order.")
    out.append(names_list("tasks", [(n, i) for i, n in enumerate(cat.tasks)]))
    out.append(u32_match("task_name", "id", [(i, quoted(n)) for i, n in enumerate(cat.tasks)], "String", '""'))
    out.append(const("required_count", len(cat.required)))
    out.append(const("optional_count", len(cat.optional)))
    out.append(const("picked_count", cat.picked))
    out.append("# The area code of a task's room_bg (0 is Any/Rare, 31 no room_bg); sandbox areas use the same codes.")
    out.append(u32_match("task_area", "id", [(i, cat.task_area(n)) for i, n in enumerate(cat.tasks)], default=NO_AREA))
    required_areas = {cat.task_area(n) for n in cat.required}
    out.append(const("required_areas", sum(1 << a for a in required_areas)))
    out.append(names_list("area_names", [(cat.tile_name[n], i + 1) for i, n in enumerate(cat.area_numbers)]))
    out.append("# level.set_pieces keys: the task set's, then the sandbox items a cave task can host; 0 is none.")
    out.append(const("key_count", len(cat.keys)))
    out.append(u32_match("key_name", "key", [(cat.key_id(n), quoted(n)) for n in cat.keys], "String", '""'))
    out.append(u32_match("key_hash", "key", [(cat.key_id(n), hashes[n]) for n in cat.keys]))
    out.append(u32_match("key_count_of", "key", [(cat.key_id(n), cat.fixed[n]["count"]) for n in cat.fixed]))
    rows = []
    for name, piece in cat.fixed.items():
        ids = ", ".join(str(cat.task_id[t]) for t in piece["tasks"])
        rows.append((cat.key_id(name), f"[{ids}]"))
    out.append("# The task set's set pieces: the tasks each may go to, in the order of the task set.")
    out.append(u32_match("fixed_tasks", "key", rows, "List<&2, U32>", "Nil{}"))
    out.append("# The task set's set_pieces table after deepcopy: node position -> key, and its size and lastfree.")
    writes = "\n".join(f"  a[{p}] <- {k}" for p, k in nodes)
    out.append("def base_nodes(a: Array<U32>) -> Array<U32>:\n" + writes + "\n")
    out.append(const("base_size", layout["sizearray"] + (1 << layout["lsizenode"])))
    out.append(const("base_last_free", layout["lastfree"]))
    out.append(const("base_count", len(nodes)))
    out.append("# The sandboxes AddSetPeices picks from (sizes and ids per area in pairs() order) and, per item id, the")
    out.append("# level.set_pieces key it adds with the area code it targets (0: no cave task can host it).")
    out += sandbox_lines(cat)
    out.append(names_list("pieces", sorted((n, cat.key_id(n)) for n in cat.keys)))
    out.append("# Prefab swaps in pairs() order: category, regular variant, swapped variant.")
    out.append(const("swap_count", len(swaps)))
    out.append(u32_match("swap_category", "k", [(i, quoted(s[0])) for i, s in enumerate(swaps)], "String", '""'))
    out.append(u32_match("swap_regular", "k", [(i, quoted(s[1])) for i, s in enumerate(swaps)], "String", '""'))
    out.append(u32_match("swap_swapped", "k", [(i, quoted(s[2])) for i, s in enumerate(swaps)], "String", '""'))
    out.append("# Bit k is set when the caves allow category k's swapped variant.")
    out.append(const("swaps_possible", sum(1 << i for i, s in enumerate(swaps) if s[3])))
    level = caves["level"]
    start = caves["start_location"]
    out.append("# The level and start location fields later stages read.")
    out.append(const("background_node_min", level["background_node_range"][0]))
    out.append(const("background_node_max", level["background_node_range"][1]))
    out.append(const("layout_mode", quoted(level["overrides"]["layout_mode"]), "String"))
    out.append(const("wormhole_prefab", quoted(level["overrides"]["wormhole_prefab"]), "String"))
    out.append(const("start_setpiece", quoted(start["start_setpeice"]), "String"))
    out.append(const("start_room_count", len(start["start_node"])))
    out.append(u32_match("start_room", "k", [(i, quoted(n)) for i, n in enumerate(start["start_node"])], "String", '""'))
    valid = caves["taskset"]["valid_start_tasks"]
    out.append(const("valid_start_task_count", len(valid)))
    out.append(u32_match("valid_start_task", "k", [(i, cat.task_id[n]) for i, n in enumerate(valid)]))
    prefabs = caves["taskset"]["required_prefabs"] + level["required_prefabs"]
    out.append(const("required_prefab_count", len(prefabs)))
    out.append(u32_match("required_prefab", "k", [(i, quoted(n)) for i, n in enumerate(prefabs)], "String", '""'))
    emit(out, "cave_catalog.bend")


def emit(lines, name):
    text = "\n".join(lines) + "\n"
    if sys.argv[1:] == ["-"]:
        sys.stdout.write(text)
        return
    (Path(__file__).resolve().parents[2] / "seedfinder" / "data" / name).write_text(text)


if __name__ == "__main__":
    main()
