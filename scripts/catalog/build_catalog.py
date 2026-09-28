#!/usr/bin/env python3
"""Builds catalog.json from the static extraction (build/static.json) and the empirical world summaries.

usage: python3 build_catalog.py [--out catalog.json]
Run from anywhere; paths are relative to this file. See README.md.
"""
import argparse
import collections
import datetime
import glob
import json
import os
import re
import statistics
import sys
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WORK = os.path.join(ROOT, "build/catalog")
INPUTS = os.path.join(HERE, "inputs")
SCRIPTS = os.path.join(ROOT, "build/deps/game-scripts")
WORLDSIM = os.environ.get("WORLDSIM_DIR", "")
REALGEN = os.environ.get("REALGEN_DIR", "")
GAME_DIR = os.environ.get("DST_GAME", os.path.expanduser("~/.local/share/Steam/steamapps/common/Don't Starve Together"))

sys.path.insert(0, HERE)
import ktex  # noqa: E402
import map_textures  # noqa: E402
import names as handnames  # noqa: E402
from summarize_world import summarize  # noqa: E402


def as_list(v):
    return list(v) if v else []


def load_json(path):
    with open(path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------------------------------------------
# Empirical worlds


def real_world_sources():
    """Yields (seed, source_label, summary) for every real-game world on disk."""
    for path in sorted(glob.glob(os.path.join(ROOT, "build/groundtruth/data/worlds/*.json"))):
        yield "groundtruth_dump", path, summarize(load_json(path), "groundtruth_dump")
    for path in sorted(glob.glob(os.path.join(WORLDSIM, "gt/*/world.json")) if WORLDSIM else []):
        yield "worldsim_gt_dump", path, summarize(load_json(path), "worldsim_gt_dump")
    realgen = (glob.glob(os.path.join(REALGEN, "out/*/summary.json")) if REALGEN else []) + glob.glob(os.path.join(WORK, "build/realgen/*/summary.json"))
    for path in sorted(realgen):
        d = load_json(path)
        yield "realgen_summary", path, {
            "seed": d["seed"], "source": "realgen_summary", "status": "ok", "attempts": d.get("generate_attempts"),
            "prefab_swaps": None, "tasks": [{"task": t} for t in d.get("chosen_tasks", [])],
            "set_pieces": {k: v.get("count", 1) if isinstance(v, dict) else v for k, v in d.get("set_pieces", {}).items()},
            "entity_counts": d["entity_counts"], "tile_counts": {}, "world_tile_map": {},
        }


def collect_inputs():
    """Snapshots every input that lives outside the repository into inputs/: the world summaries of every source,
    the static extraction and the level statistics."""
    os.makedirs(INPUTS, exist_ok=True)
    real = list(real_world_sources())
    emulator = [("emulator", p, load_json(p)) for p in sorted(glob.glob(os.path.join(WORK, "worlds/*.json")))]
    with open(os.path.join(INPUTS, "worlds.jsonl"), "w") as f:
        for label, path, w in real + emulator:
            f.write(json.dumps({"source": label, "path": os.path.relpath(path, ROOT), "summary": w}, sort_keys=True) + "\n")
    for name in ["static.json", "level_table_stats.json", "level_world_stats.json"]:
        path = os.path.join(WORK, "build", name)
        if os.path.exists(path):
            with open(path) as src, open(os.path.join(INPUTS, name), "w") as dst:
                dst.write(src.read())


def world_records():
    with open(os.path.join(INPUTS, "worlds.jsonl")) as f:
        for line in f:
            r = json.loads(line)
            yield r["source"], r["path"], r["summary"]


def load_worlds():
    """One entry per seed. Real-game sources win over the emulator; disagreements are reported."""
    by_seed = {}
    disagreements = []
    per_source = collections.Counter()
    failed = []
    for label, path, w in world_records():
        if w.get("status") != "ok" or not w.get("entity_counts"):
            failed.append({"seed": w.get("seed"), "source": label, "status": w.get("status")})
            continue
        per_source[label] += 1
        seed = w["seed"]
        if seed in by_seed:
            prev = by_seed[seed]
            if prev["entity_counts"] != w["entity_counts"]:
                disagreements.append({"seed": seed, "a": prev["source"], "b": label})
            if not prev.get("tile_counts") and w.get("tile_counts"):
                prev["tile_counts"] = w["tile_counts"]
                prev["world_tile_map"] = w["world_tile_map"]
            if prev.get("prefab_swaps") is None and w.get("prefab_swaps"):
                prev["prefab_swaps"] = w["prefab_swaps"]
            continue
        by_seed[seed] = dict(w)
    return by_seed, per_source, disagreements, failed


def count_stats(values, n_worlds):
    present = [v for v in values if v > 0]
    full = values + [0] * (n_worlds - len(values))
    return {
        "worlds": len(present),
        "share": round(len(present) / n_worlds, 4) if n_worlds else 0,
        "min": min(full) if full else 0,
        "median": statistics.median(full) if full else 0,
        "max": max(full) if full else 0,
        "mean": round(statistics.fmean(full), 3) if full else 0,
        "min_when_present": min(present) if present else 0,
        "always": len(present) == n_worlds and n_worlds > 0,
        "unique": (max(full) if full else 0) <= 1,
    }


def empirical_counts(worlds, key):
    values = collections.defaultdict(list)
    for w in worlds.values():
        for name, n in (w.get(key) or {}).items():
            values[name].append(n)
    return {name: count_stats(v, len(worlds)) for name, v in values.items()}


# ---------------------------------------------------------------------------------------------------------------
# Static prefab set


class StaticSet:
    def __init__(self, static):
        self.s = static
        self.proxies = dict(static["proxies"])
        self.proxies.update(static["customization_proxies"])
        self.randomization = static["randomization_proxies"]
        self.wormhole = static["level"].get("wormhole_prefab") or "wormhole"
        self.prefabs = collections.defaultdict(dict)
        self.aliases = collections.defaultdict(set)

    def resolve(self, name):
        target = self.proxies.get(name, name)
        if target in self.randomization:
            return list(self.randomization[target])
        if target == "wormhole_MARKER":
            return [self.wormhole]
        return [target]

    def add(self, raw, kind, name, reachable=True, note=None):
        for prefab in self.resolve(raw):
            if prefab != raw:
                self.aliases[prefab].add(raw)
            key = (kind, name)
            entry = self.prefabs[prefab].get(key)
            if entry is None:
                self.prefabs[prefab][key] = {"kind": kind, "name": name, "default": reachable, "note": note}
            else:
                entry["default"] = entry["default"] or reachable
                entry["note"] = entry["note"] or note

    def sources(self, prefab):
        return sorted(self.prefabs[prefab].values(), key=lambda e: (e["kind"], e["name"]))


def count_possible(count):
    if isinstance(count, dict):
        return count.get("max", 1) > 0
    return count is None or count > 0


def forest_tasks(static):
    return {tid: t for tid, t in static["tasks"].items()}


def sandbox_candidates(static, area):
    tasks = forest_tasks(static)
    if area in ("Any", "Rare"):
        return sorted(t for t, d in tasks.items() if not d["level_set_piece_blocker"])
    return sorted(t for t, d in tasks.items() if d["room_bg"] == area and not d["level_set_piece_blocker"])


def room_is_ocean(room):
    return "ocean_population" in as_list(room.get("used_by"))


def room_tasks(room):
    out = set()
    for via in as_list(room.get("used_by")):
        m = re.match(r"^task[_a-z]*:(.*)$", via)
        if m:
            out.add(m.group(1))
    return out


def reachable_layouts(static):
    """Returns {layout: {"reachable": bool, "placements": [...]}} following every way a layout is used."""
    rooms = static["rooms"]
    result = {}
    for name, layout in static["layouts"].items():
        placements = []
        for via in as_list(layout.get("used_by")):
            placements.append(layout_placement(static, rooms, name, via))
        result[name] = {"reachable": any(p["reachable"] for p in placements), "placements": placements}
    return result


def layout_placement(static, rooms, name, via):
    if via.startswith("sandbox:"):
        _, kind, area = via.split(":", 2)
        cands = sandbox_candidates(static, area)
        return {"via": "sandbox", "kind": kind, "area": area, "tasks": cands, "reachable": bool(cands)}
    if via.startswith("room:"):
        room_name = via[5:]
        room = rooms.get(room_name, {})
        count = (room.get("countstaticlayouts") or {}).get(name)
        return {"via": "room", "room": room_name, "count": count, "ocean": room_is_ocean(room),
                "tasks": sorted(room_tasks(room)), "reachable": count_possible(count)}
    if via.startswith("maptag:"):
        return {"via": "maptag", "tag": via[7:], "reachable": True}
    if via.startswith("task_set_piece:"):
        return {"via": "task", "tasks": [via.split(":", 1)[1]], "reachable": True}
    return {"via": via, "reachable": True}


def layout_prefabs(layout):
    placeholders = set(as_list(layout.get("area_names"))) | set((layout.get("defs") or {}).keys())
    names = {}
    for prefab, stats in (layout.get("prefabs") or {}).items():
        names[prefab] = stats
    for prefab in (layout.get("raw_types") or {}):
        if prefab not in placeholders:
            names.setdefault(prefab, None)
    for choices in (layout.get("defs") or {}).values():
        for prefab in as_list(choices):
            names.setdefault(prefab, None)
    for prefab in (layout.get("count") or {}):
        if prefab not in placeholders:
            names.setdefault(prefab, None)
    return names


def build_static_set(static, layout_reach):
    ss = StaticSet(static)
    for room_name, room in static["rooms"].items():
        kind = "ocean" if room_is_ocean(room) else "room"
        for prefab, count in (room.get("countprefabs") or {}).items():
            ok = count_possible(count)
            ss.add(prefab, kind, room_name, ok, None if ok else "count is 0 at default settings (special event only)")
        for prefab, weight in (room.get("distributeprefabs") or {}).items():
            ss.add(prefab, kind, room_name, bool(weight))
        for item in as_list(room.get("tag_items")):
            if "prefab" in item:
                ss.add(item["prefab"], "special", "maptag:" + item["tag"], True, "room " + room_name)
    for name, layout in static["layouts"].items():
        reach = layout_reach[name]["reachable"]
        note = None if reach else "layout never placed in the default forest"
        for prefab in layout_prefabs(layout):
            ss.add(prefab, "layout", name, reach, note)
    add_special_sources(ss, static)
    return ss


def bunch_fn_prefabs(info):
    path = os.path.join(SCRIPTS, info["file"].split("game-scripts/", 1)[-1])
    with open(path) as f:
        lines = f.readlines()[info["first"] - 1:info["last"]]
    return sorted(set(re.findall(r'"([a-z0-9_]+)"', "".join(lines))))


def add_special_sources(ss, static):
    present = set(ss.prefabs)
    for spawner, data in static["bunches"].items():
        if spawner not in present:
            continue
        targets = [data["prefab"]] if "prefab" in data else bunch_fn_prefabs(data["prefab_fn"])
        for prefab in targets:
            ss.add(prefab, "special", "bunch:" + spawner, True, "spawned %s-%s around each %s" % (
                data.get("min"), data.get("max"), spawner))
    monkey = static["monkeyisland"]
    if monkey.get("center_prefab") in present:
        for prefab in as_list(monkey.get("dock_prefabs")) + as_list(monkey.get("endpoint_prefabs")) + as_list(monkey.get("always")):
            ss.add(prefab, "special", "monkeyisland_docks", True, "MonkeyIsland_GenerateDocks")
    for prefab in as_list(static["world_entities"]):
        ss.add(prefab, "special", "worldentities", True, "AddWorldEntities: one per world, at 0,0")


# ---------------------------------------------------------------------------------------------------------------
# Names, groups, icons


def load_atlases():
    atlases = {"minimap": {}, "inventory": {}}
    if not os.path.isdir(GAME_DIR):
        return atlases
    for xml in (os.path.join(GAME_DIR, "data", path) for path in map_textures.MINIMAP_ATLASES):
        root = ET.parse(xml).getroot()
        tex = root.find("Texture").get("filename")
        for el in root.iter("Element"):
            atlases["minimap"].setdefault(el.get("name"), {"xml": "minimap/" + os.path.basename(xml), "tex": "minimap/" + tex})
    bundle = os.path.join(GAME_DIR, "data/databundles/images.zip")
    if os.path.exists(bundle):
        with zipfile.ZipFile(bundle) as z:
            for name in sorted(n for n in z.namelist() if re.match(r"images/inventoryimages\d*\.xml$", n)):
                root = ET.fromstring(z.read(name))
                tex = root.find("Texture").get("filename")
                for el in root.iter("Element"):
                    atlases["inventory"].setdefault(el.get("name"), {"xml": name, "tex": "images/" + tex,
                                                                    "bundle": "databundles/images.zip"})
    return atlases


def minimap_icon(prefab, table, atlas):
    """The prefab's minimap icon as the game draws it: the constructor's own MiniMapEntity calls, the icon of what a
    spawner spawns, or an icon captured from the running game."""
    if prefab in handnames.SPAWNED_ICONS:
        row, match = table[handnames.SPAWNED_ICONS[prefab]], "spawned:" + handnames.SPAWNED_ICONS[prefab]
    elif prefab in handnames.CAPTURED_ICONS:
        row, match = dict(table[prefab], icon=handnames.CAPTURED_ICONS[prefab]), "captured"
    elif prefab in table:
        row, match = table[prefab], "game"
    else:
        return None
    if row["icon"] not in atlas:
        return None
    return dict(atlas[row["icon"]], element=row["icon"], match=match,
                **{key: row[key] for key in ("priority", "over_fog") if key in row})


def hidden_by_default(prefab, minimap):
    """Why the game's map doesn't draw the prefab's icon in a freshly generated world, or None when it does."""
    if minimap is None:
        return "no minimap icon"
    if minimap["match"].startswith("spawned:"):
        return "a spawner marker: the game draws nothing at its position, only what it spawns"
    return handnames.CONDITIONAL_ICONS.get(prefab)


def icon_for(prefab, atlases, minimap_icons):
    icons = {}
    inv = atlases["inventory"].get(prefab + ".tex")
    if inv:
        icons["inventory"] = dict(inv, element=prefab + ".tex", match="name")
    minimap = minimap_icon(prefab, minimap_icons, atlases["minimap"])
    if minimap:
        icons["minimap"] = minimap
    return icons


def display_name(prefab, names):
    if prefab in handnames.PREFAB_NAMES:
        return handnames.PREFAB_NAMES[prefab], "hand"
    game = names.get(prefab.upper())
    if game:
        qualifier = handnames.QUALIFIERS.get(prefab)
        return (game + " (" + qualifier + ")" if qualifier else game), "strings"
    base = handnames.variant_base(prefab)
    if base and names.get(base.upper()):
        return names[base.upper()] + " (" + prefab[len(base):].strip("_") + ")", "strings_variant"
    return prefab.replace("_", " ").capitalize(), "fallback"


def source_tags(sources, moon_rooms, moon_layouts):
    tags = set()
    for s in sources:
        kind, name = s["kind"], s["name"]
        if kind == "ocean" or name.startswith("bunch:"):
            tags.add("ocean")
        if (kind == "room" and name in moon_rooms) or (kind == "layout" and name in moon_layouts):
            tags.add("moon island")
        if name == "HermitcrabIsland":
            tags.add("hermit island")
        if name.startswith("MonkeyIsland") or name == "monkeyisland_docks":
            tags.add("monkey island")
        if kind == "layout":
            tags.add("set piece")
        if kind == "room":
            tags.add("biome")
    return sorted(tags)


def suggest_group(prefab, sources, tags, has_inventory_icon):
    if prefab in handnames.GROUPS:
        return handnames.GROUPS[prefab]
    kinds = {s["kind"] for s in sources}
    if kinds == {"layout"} and has_inventory_icon:
        return "set-piece loot"
    if has_inventory_icon:
        return "items"
    if "ocean" in tags and "biome" not in tags:
        return "ocean"
    if "moon island" in tags:
        return "moon island"
    return "other"


# ---------------------------------------------------------------------------------------------------------------
# Set pieces


def sandbox_pick_probability(areas, piece, only_areas=None):
    """P(a single AddSingleSetPeice draw picks this piece), GetRandomFromLayouts in worldgen_main.lua."""
    keys = list(areas)
    k = len(keys)
    size = {a: len(as_list(areas[a])) for a in keys}

    def keep(a):
        if size[a] < 1:
            return 0.0
        return 0.02 if a == "Rare" else 1.0

    def reroll(a):
        if size[a] < 1:
            return 1.0
        return 0.98 if a == "Rare" else 0.0

    total = 0.0
    for a in keys:
        if piece not in as_list(areas[a]) or (only_areas is not None and a not in only_areas):
            continue
        p_area = keep(a) / k + sum(reroll(f) / k / (k - 1) for f in keys if f != a)
        total += p_area / size[a]
    return total


SANDBOX_KIND = {"boon": "boon", "trap": "trap", "poi": "poi", "protected": "protected"}


def build_setpieces(static, layout_reach, emp_setpieces, ss_names):
    level = static["level"]
    out = []
    kinds = {}
    for kind, areas in static["sandboxes"].items():
        for area, pieces in areas.items():
            for piece in as_list(pieces):
                kinds.setdefault(piece, {"kind": kind, "areas": []})["areas"].append(area)
    for name in level["set_pieces"]:
        kinds.setdefault(name, {"kind": "fixed"})
    for name in as_list(level["required_setpieces"]):
        kinds.setdefault(name, {"kind": "random", "required": True})
    for name in as_list(level["random_set_pieces"]):
        kinds.setdefault(name, {"kind": "random", "required": False})
    for name in static["layouts"]:
        if name not in kinds:
            kinds[name] = {"kind": layout_kind(layout_reach[name]["placements"], level, name)}
    for name in sorted(kinds):
        out.append(setpiece_entry(static, name, kinds[name], layout_reach, emp_setpieces, ss_names))
    return out


def layout_kind(placements, level, name):
    vias = {p["via"] for p in placements}
    if name == level.get("start_setpeice"):
        return "start"
    if "ocean_prefill" in vias or any(p.get("ocean") for p in placements):
        return "ocean"
    if "maptag" in vias:
        return "maptag"
    if "room" in vias:
        return "room"
    return "other"


def setpiece_entry(static, name, info, layout_reach, emp_setpieces, ss_names):
    level = static["level"]
    layout = static["layouts"].get(name, {})
    placements = layout_reach.get(name, {}).get("placements", [])
    entry = {"name": name, "kind": info["kind"], "display_name": handnames.setpiece_name(name),
             "filterable": info["kind"] in ("boon", "trap", "poi", "protected", "fixed", "random")}
    entry["candidate_tasks"], entry["forest"] = setpiece_tasks(static, name, info, placements)
    if info["kind"] == "fixed":
        entry["fixed_count"] = level["set_pieces"][name]["count"]
        missing = sorted(set(level["set_pieces"][name]["tasks"]) - set(static["tasks"]))
        if missing:
            entry["unknown_tasks_in_game_data"] = missing
    if info["kind"] == "random":
        entry["required"] = info.get("required", False)
        entry["fixed_count"] = 1 if info.get("required") else None
        n = len(as_list(level["random_set_pieces"]))
        entry["p_per_draw"] = None if info.get("required") else round(1 / n, 6)
        entry["draws_per_world"] = level["numrandom_set_pieces"]
    if info["kind"] in SANDBOX_KIND:
        areas = static["sandboxes"][info["kind"]]
        entry["areas"] = sorted(info["areas"])
        entry["p_per_draw"] = round(sandbox_pick_probability(areas, name), 6)
        forest_areas = {a for a in info["areas"] if sandbox_candidates(static, a)}
        entry["p_placed_per_draw"] = round(sandbox_pick_probability(areas, name, forest_areas), 6)
        entry["draws_per_world"] = "boon count (settings.boons)" if info["kind"] == "boon" else 1
    entry["contents"] = setpiece_contents(layout, ss_names)
    entry["scenarios"] = as_list(layout.get("scenarios"))
    entry["data_hints"] = as_list(layout.get("data_strings"))[:20]
    entry["layout_file"] = layout.get("file")
    if name in emp_setpieces:
        entry["empirical"] = emp_setpieces[name]
    add_level_stats(entry, name, info["kind"])
    return entry


def optional_json(name):
    path = os.path.join(INPUTS, name)
    return load_json(path) if os.path.exists(path) else None


LEVEL_TABLE = optional_json("level_table_stats.json")
LEVEL_WORLD = optional_json("level_world_stats.json")


def add_level_stats(entry, name, kind):
    if not entry["filterable"]:
        return
    if kind == "random" and LEVEL_WORLD:
        stats = LEVEL_WORLD["random_set_pieces"].get(name)
        entry["level_stats"] = dict(stats or {"share": 0, "max": 0}, worlds_sampled=LEVEL_WORLD["worlds"],
                                    source="harness world mode, seeds %d..%d" % tuple(LEVEL_WORLD["seeds"]))
    elif LEVEL_TABLE:
        stats = LEVEL_TABLE["pieces"].get(name)
        entry["level_stats"] = dict(stats or {"share": 0, "max": 0}, worlds_sampled=LEVEL_TABLE["worlds"],
                                    source=LEVEL_TABLE["source"])
    if LEVEL_WORLD and name in LEVEL_WORLD["set_piece_tasks"]:
        placed = LEVEL_WORLD["set_piece_tasks"][name]
        total = sum(placed.values())
        entry["task_distribution"] = {t: round(n / total, 5) for t, n in sorted(placed.items(), key=lambda kv: -kv[1])}


def setpiece_tasks(static, name, info, placements):
    if info["kind"] in SANDBOX_KIND:
        tasks = set()
        for area in info["areas"]:
            tasks |= set(sandbox_candidates(static, area))
        return sorted(tasks), bool(tasks)
    if info["kind"] == "fixed":
        tasks = sorted(set(static["level"]["set_pieces"][name]["tasks"]) & set(static["tasks"]))
        return tasks, bool(tasks)
    if info["kind"] == "random":
        return sandbox_candidates(static, "Any"), True
    tasks = set()
    for p in placements:
        tasks |= set(p.get("tasks") or [])
    return sorted(tasks), any(p["reachable"] for p in placements)


def setpiece_contents(layout, ss_names):
    contents = []
    for raw, stats in sorted(layout_prefabs(layout).items()):
        for prefab in ss_names.resolve(raw):
            item = {"prefab": prefab}
            if raw != prefab:
                item["as"] = raw
            if stats:
                item.update({"min": stats["min"], "max": stats["max"], "p": round(stats["p"], 4)})
            contents.append(item)
    return contents


# ---------------------------------------------------------------------------------------------------------------
# Tasks, tiles, settings


def build_tasks(static):
    out = []
    order = as_list(static["level"]["taskset_tasks"]) + as_list(static["level"]["taskset_optionaltasks"])
    for tid in order:
        t = static["tasks"][tid]
        kind = "moon" if t["moon"] else t["kind"]
        out.append({
            "id": tid, "kind": kind, "required": t["kind"] == "required", "optional": t["kind"] == "optional",
            "moon": t["moon"], "background_terrain": t["room_bg"], "background_room": t["background_room"],
            "display_name": handnames.TASK_NAMES.get(tid, tid),
            "rooms": t["room_choices"], "entrance_room": t.get("entrance_room"), "region": t.get("region_id") or "mainland",
            "set_piece_blocker": t["level_set_piece_blocker"],
            "share": LEVEL_WORLD["tasks"].get(tid, 0) if LEVEL_WORLD else None,
        })
    return out


def paper_colour():
    if not os.path.isdir(GAME_DIR):
        return None
    with open(os.path.join(GAME_DIR, "data", map_textures.MINIMAP_PAPER), "rb") as f:
        return list(ktex.mean_rgb(f.read()))


def ocean_minimap_color(tile):
    return tile["ground_minimap_color"][:3] if tile["ocean"] and "ground_minimap_color" in tile else None


def land_noise(tile):
    return tile["minimap_noise"].removesuffix(".tex") if tile["land"] and "minimap_noise" in tile else None


def tile_colour(tile, paper):
    if land_noise(tile) and os.path.isdir(GAME_DIR):
        return map_textures.land_colour(GAME_DIR, land_noise(tile))
    return ocean_minimap_color(tile) or paper


def build_tiles(static, worlds):
    names = static["names"]
    paper = paper_colour()
    seen = collections.defaultdict(list)
    n_with_tiles = 0
    for w in worlds.values():
        if not w.get("tile_counts"):
            continue
        n_with_tiles += 1
        for tile, n in w["tile_counts"].items():
            seen[tile].append(n)
    out = []
    for name, t in sorted(static["tiles"].items(), key=lambda kv: kv[1]["id"]):
        turf = t.get("turf")
        label = names.get(("TURF_" + turf).upper()) if turf else None
        counts = seen.get(name, [])
        out.append({
            "name": name, "id": t["id"],
            "class": "ocean" if t["ocean"] else "impassable" if t["impassable"] else "invalid" if t["invalid"] else "land",
            "land": t["land"], "ocean": t["ocean"], "noise": t["noise"], "legacy": t.get("legacy", False),
            "display_name": label or handnames.TILE_NAMES.get(name) or (t.get("ground_name") if t.get("ground_name") != name else None),
            "turf_prefab": "turf_" + turf if turf else None,
            "color": tile_colour(t, paper),
            "minimap_noise": land_noise(t) if counts else None,
            "minimap_rank": t.get("minimap_rank") if t["land"] else None,
            "ocean_minimap_color": ocean_minimap_color(t),
            "in_forest_worlds": {"worlds": len(counts), "share": round(len(counts) / n_with_tiles, 4) if n_with_tiles else 0,
                                 "min_tiles": min(counts) if counts else 0, "max_tiles": max(counts) if counts else 0,
                                 "median_tiles": statistics.median(counts) if counts else 0},
        })
    return out, n_with_tiles


def build_settings(static):
    s = static["settings"]
    items = s["customize_items"]
    levels = [{"id": d["id"], "label": d["label"]} for d in s["levels"]]
    boons = items.get("boons", {})
    supported = {
        "boons": {"label": boons.get("label"), "image": boons.get("image"), "atlas": boons.get("atlas"),
                  "in_game_ui": True, "default": "default", "levels": levels,
                  "count_range": {k: v for k, v in s["boon_ranges"].items()},
                  "note": "number of boon draws, uniform in count_range: math.random(floor(3*m), ceil(8*m))"},
    }
    for key in ("traps", "poi", "protected"):
        supported[key] = {"label": handnames.SETTING_LABELS[key], "in_game_ui": False, "default": "default",
                          "levels": levels, "effect": {"never": 0, "other": 1},
                          "note": "not in customize.lua; level override only. never = none placed, any other level = one draw"}
    unsupported = {}
    for key, item in sorted(items.items()):
        if key in supported:
            continue
        unsupported[key] = {"label": item.get("label"), "image": item.get("image"), "atlas": item.get("atlas"),
                            "group": item.get("group"), "default": item.get("default"),
                            "options": [o.get("data") for o in as_list(item.get("options")) if isinstance(o, dict)]}
    return {"supported": supported, "unsupported_must_be_default": unsupported,
            "level_labels_source": "STRINGS.UI.SANDBOXMENU.SLIDE* via map/customize.lua worldgen_frequency_descriptions"}


def build_swaps(static):
    out = []
    for category in ("grass", "twigs", "berries"):
        sets = static["swaps"][category]
        total = sum(s["weight"] for s in sets)
        out.append({"category": category, "label": handnames.SWAP_LABELS[category], "options": [
            {"name": s["name"], "prefabs": s["prefabs"], "weight": s["weight"], "probability": s["weight"] / total,
             "primary": s["primary"], "exclude_locations": as_list(s.get("exclude_locations")),
             "empirical_share": (LEVEL_WORLD or {}).get("prefab_swaps", {}).get(category, {}).get(s["name"])}
            for s in sets]})
    return out


def swap_info(static):
    info = {}
    proxies = static["proxies"]
    for category, sets in static["swaps"].items():
        for s in sets:
            for raw in s["prefabs"]:
                prefab = proxies.get(raw, raw)
                info[prefab] = {"category": category, "option": s["name"], "primary": s["primary"], "as": raw}
    return info


# ---------------------------------------------------------------------------------------------------------------


def moon_room_names(static):
    moon_tasks = {tid for tid, t in static["tasks"].items() if t["moon"]}
    out = set()
    for name, room in static["rooms"].items():
        tasks = room_tasks(room)
        if tasks and tasks <= moon_tasks:
            out.add(name)
    return out


def moon_layout_names(static, layout_reach):
    moon_tasks = {tid for tid, t in static["tasks"].items() if t["moon"]}
    moon_rooms = moon_room_names(static)
    out = set()
    for name, info in layout_reach.items():
        tasks, rooms = set(), set()
        for p in info["placements"]:
            tasks |= set(p.get("tasks") or [])
            if p.get("room"):
                rooms.add(p["room"])
        fixed = static["level"]["set_pieces"].get(name)
        if fixed:
            tasks |= set(fixed["tasks"]) & set(static["tasks"])
        if (tasks and tasks <= moon_tasks) or (rooms and rooms <= moon_rooms):
            out.add(name)
    return out


def static_only_reason(prefab, sources, cave_only):
    if all(not s["default"] for s in sources):
        notes = sorted({s["note"] for s in sources if s["note"]})
        if prefab in cave_only:
            return "cave-only (its set pieces use cave terrains, which the forest never has)"
        return "setting/event dependent: " + "; ".join(notes)
    return "rare: only in set pieces " + ", ".join(sorted({s["name"] for s in sources if s["default"]}))


def build_prefabs(static, ss, emp, n_worlds, atlases, minimap_icons, cave_only, layout_reach):
    names = static["names"]
    swaps = swap_info(static)
    moon_rooms = moon_room_names(static)
    moon_layouts = moon_layout_names(static, layout_reach)
    out = []
    for prefab in sorted(set(ss.prefabs) | set(emp)):
        sources = ss.sources(prefab) if prefab in ss.prefabs else []
        icons = icon_for(prefab, atlases, minimap_icons)
        tags = source_tags(sources, moon_rooms, moon_layouts)
        name, name_source = display_name(prefab, names)
        entry = {
            "id": prefab, "display_name": name, "name_source": name_source,
            "game_name": names.get(prefab.upper()),
            "group": suggest_group(prefab, sources, tags, "inventory" in icons),
            "tags": tags,
            "variant_of": handnames.variant_base(prefab),
            "sources": [{k: v for k, v in s.items() if v is not None} for s in sources],
            "default_reachable": any(s["default"] for s in sources),
            "icons": icons,
        }
        reason = hidden_by_default(prefab, icons.get("minimap"))
        entry["default_shown"] = reason is None
        if reason and "minimap" in icons:
            entry["hidden_by_default"] = reason
        if ss.aliases.get(prefab):
            entry["placed_as"] = sorted(ss.aliases[prefab])
        if prefab in swaps:
            entry["swap"] = swaps[prefab]
        if prefab in emp:
            entry["empirical"] = emp[prefab]
        else:
            entry["empirical"] = count_stats([], n_worlds)
            entry["static_only_reason"] = static_only_reason(prefab, sources, cave_only)
        if not sources:
            entry["not_in_static_set"] = True
        out.append(entry)
    return out


def cave_only_prefabs(static, layout_reach, ss):
    out = set()
    for prefab, srcs in ss.prefabs.items():
        layouts = [s["name"] for s in srcs.values() if s["kind"] == "layout"]
        if layouts and len(layouts) == len(srcs) and all(not layout_reach[l]["reachable"] for l in layouts):
            if all(p.get("via") == "sandbox" for l in layouts for p in layout_reach[l]["placements"]):
                out.add(prefab)
    return out


def game_build():
    path = os.path.join(GAME_DIR, "version.txt")
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(HERE, "catalog.json"))
    ap.add_argument("--static", default=os.path.join(INPUTS, "static.json"))
    ap.add_argument("--collect", action="store_true", help="only refresh inputs/ from build/catalog")
    args = ap.parse_args()
    if args.collect:
        collect_inputs()
        return

    static = load_json(args.static)
    worlds, per_source, disagreements, failed = load_worlds()
    n_worlds = len(worlds)
    emp_prefabs = empirical_counts(worlds, "entity_counts")
    emp_setpieces = empirical_counts(worlds, "set_pieces")

    layout_reach = reachable_layouts(static)
    ss = build_static_set(static, layout_reach)
    cave_only = cave_only_prefabs(static, layout_reach, ss)
    atlases = load_atlases()
    minimap_icons = load_json(os.path.join(INPUTS, "minimap_icons.json"))

    prefabs = build_prefabs(static, ss, emp_prefabs, n_worlds, atlases, minimap_icons, cave_only, layout_reach)
    tiles, n_tile_worlds = build_tiles(static, worlds)
    empirical_only = sorted(p["id"] for p in prefabs if p.get("not_in_static_set"))
    static_only = sorted(p["id"] for p in prefabs if p["id"] not in emp_prefabs)

    catalog = {
        "schema_version": 1,
        "game_build": game_build(),
        "generated": datetime.date.today().isoformat(),
        "shard": "forest",
        "preset": "SURVIVAL_TOGETHER",
        "worlds": {"total": n_worlds, "by_source": dict(per_source), "with_tiles": n_tile_worlds,
                   "failed": failed, "seed_disagreements": disagreements},
        "settings": build_settings(static),
        "prefab_swaps": build_swaps(static),
        "tasks": build_tasks(static),
        "setpieces": build_setpieces(static, layout_reach, emp_setpieces, ss),
        "prefabs": prefabs,
        "tiles": tiles,
        "cross_check": {
            "empirical_not_static": empirical_only,
            "static_not_empirical": [{"id": p["id"], "reason": p["static_only_reason"]} for p in prefabs
                                     if p["id"] in static_only],
        },
    }
    with open(args.out, "w") as f:
        json.dump(catalog, f, indent=1, sort_keys=False)
        f.write("\n")
    print("worlds %d (%s), prefabs %d (static %d, empirical %d), empirical-not-static %d, static-only %d, "
          "setpieces %d, tasks %d, tiles %d" % (
              n_worlds, dict(per_source), len(prefabs), len(ss.prefabs), len(emp_prefabs), len(empirical_only),
              len(static_only), len(catalog["setpieces"]), len(catalog["tasks"]), len(tiles)))
    if disagreements:
        print("seed disagreements:", disagreements)


if __name__ == "__main__":
    main()
