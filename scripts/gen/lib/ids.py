"""Global string ids shared by every generated data module.

Ids are dense: the tasks first (in data/world_catalog.bend's task order, so a task's string id equals its
world_catalog task id), then every other string (rooms, layouts, prefabs, layout keys, tags, region ids, ...) sorted
by bytes. Rooms and layouts also have their own dense indices (sorted names); some names are both a task and a room.
Every generator rebuilds the same tables from the sidecars.
"""
import sys
from functools import lru_cache
from pathlib import Path

import blob

sys.path.insert(0, str(blob.GEN))
from gen_world_catalog import LITERAL_ORDER  # noqa: E402


def _entries_keys(view, field):
    return [e["key"] for e in (view or {}).get(field, {}).get("entries", [])]


def _room_strings(room):
    out = [room["name"]]
    out += (room.get("tags") or {}).get("ipairs", [])
    out += room.get("required_prefabs") or []
    for depth in ("depth1", "depth2"):
        view = room["contents"].get(depth)
        if not view:
            continue
        for field in ("countprefabs", "countstaticlayouts", "prefabdata"):
            out += _entries_keys(view, field)
        for e in (view.get("distributeprefabs") or {}).get("entries", []):
            out.append(e["key"])
            if isinstance(e["value"], dict):
                out += list(e["value"]["prefabs"].values())
    return out


def _task_strings(task):
    out = [task["id"], task.get("background_room"), task.get("cove_room_name"), task.get("region_id"),
           task.get("hub_room")]
    entrance = task.get("entrance_room")
    out += entrance if isinstance(entrance, list) else [entrance]
    out += [e["key"] for e in task["room_choices"]]
    out += (task.get("room_tags") or {}).get("ipairs", [])
    out += task.get("required_prefabs") or []
    return out


def _layout_strings(layout):
    out = [layout["name"]]
    for state in layout["states"]:
        for e in state.get("layout") or []:
            out.append(e["key"])
        for e in state.get("entities") or []:
            out.append(e["prefab"])
        for e in state.get("areas") or []:
            out.append(e["key"])
            for item in (e["value"] or {}).get("list", []) if isinstance(e["value"], dict) else []:
                out.append(item["prefab"] if isinstance(item, dict) else item)
        for e in state.get("defs") or []:
            out.append(e["key"])
            out += e["value"]
        for e in state.get("count") or []:
            out.append(e["key"])
    return out


@lru_cache(maxsize=None)
def table():
    story = blob.sidecar("story.json")
    layouts = blob.sidecar("layouts.json")
    distribute = blob.sidecar("distribute.json")
    ocean = blob.sidecar("ocean.json")
    tasks = [t["id"] for t in story["tasks"]]
    assert sorted(tasks) == sorted(LITERAL_ORDER), "task set differs from data/world_catalog.bend"
    rooms = sorted(r["name"] for r in story["rooms"])
    layout_names = sorted(layout["name"] for layout in layouts["layouts"])
    others = set()
    for t in story["tasks"]:
        others.update(_task_strings(t))
    for r in story["rooms"]:
        others.update(_room_strings(r))
    for field in ("tasks", "optionaltasks", "valid_start_tasks", "required_prefabs", "ocean_population"):
        others.update(story["taskset"][field])
    others.update(p["name"] for p in story["taskset"]["set_pieces"])
    others.update(p["name"] for p in story["taskset"]["ocean_prefill_setpieces"])
    level = story["level"]
    for field in ("required_setpieces", "random_set_pieces", "required_prefabs", "ocean_population"):
        others.update(level[field])
    others.update([level["start_setpeice"], level["start_node"]])
    for layout in layouts["layouts"]:
        others.update(_layout_strings(layout))
    for kind in layouts["sandboxes"].values():
        for area in kind:
            others.update(area["pieces"])
            if isinstance(area["area"], str):
                others.add(area["area"])
    for tag in layouts["maptags"]:
        others.add(tag["tag"])
        for r in tag["results"]:
            for step in (r["first"], r["second"]):
                if isinstance(step.get("value"), str):
                    others.add(step["value"])
    for variant in distribute["variants"]:
        others.update(e["key"] for e in variant["entries"])
    for room in distribute["rooms"]:
        for depth in room["depths"]:
            for s in depth["swappable"]:
                others.add(s["key"])
                others.update(s["prefabs"])
    for bunch in ocean["bunches"]:
        others.add(bunch["name"])
        if isinstance(bunch.get("prefab"), str):
            others.add(bunch["prefab"])
        others.update(bunch.get("prefab_results") or [])
    others.discard(None)
    others.update(rooms)
    others.update(layout_names)
    rest = sorted((s for s in others if s not in set(tasks)), key=lambda s: s.encode())
    ordered = list(LITERAL_ORDER) + rest
    known = set(ordered)
    extras = {lit for e in layouts.get("area_literals", []) for lit in e["literals"] if lit not in known}
    ordered += sorted(extras, key=lambda s: s.encode())
    known = set(ordered)
    ocean_post = blob.sidecar("ocean_post.json")
    ordered += sorted({s for s in ocean_post["strings"] if s not in known}, key=lambda s: s.encode())
    assert len(set(ordered)) == len(ordered)
    return {
        "strings": ordered,
        "index": {s: i for i, s in enumerate(ordered)},
        "others_base": len(LITERAL_ORDER),
        "rooms": sorted(rooms, key=lambda s: s.encode()),
        "layouts": sorted(layout_names, key=lambda s: s.encode()),
    }


def sid(s):
    """The global string id of s."""
    return table()["index"][s]


def room_index(name):
    """The room's row in data/rooms.bend."""
    return table()["rooms"].index(name)


def layout_index(name):
    """The layout's row in data/layouts.bend."""
    return table()["layouts"].index(name)


def _all_closures():
    out = []
    for name in ("story.json", "layouts.json", "ocean.json"):
        out += blob.sidecar(name)["closures"]
    return out


@lru_cache(maxsize=None)
def closures():
    """Every closure variant (distinct body + upvalues) of every sidecar, ordered by first source site."""
    merged = {}
    for c in _all_closures():
        entry = merged.setdefault(c["key"], {"key": c["key"], "body": c["body"], "upvalues": c["upvalues"],
                                             "globals": c["globals"], "sites": set(), "contexts": set()})
        entry["sites"].update(c["sites"])
        entry["contexts"].update(c["contexts"])

    def site_key(site):
        path, lines = site.rsplit(":", 1)
        return path, int(lines.split("-")[0])

    ordered = sorted(merged.values(), key=lambda e: (min(site_key(s) for s in e["sites"]), e["key"]))
    for i, e in enumerate(ordered):
        e["id"] = i
        e["sites"] = sorted(e["sites"], key=site_key)
        e["contexts"] = sorted(e["contexts"])
    return ordered


def closure_id(key):
    return {c["key"]: c["id"] for c in closures()}[key]


@lru_cache(maxsize=None)
def weights():
    """Distinct distribute weights (doubles), sorted; rows of data/rooms.bend's weights table."""
    values = set()
    for r in blob.sidecar("story.json")["rooms"]:
        for depth in ("depth1", "depth2"):
            for e in ((r["contents"].get(depth) or {}).get("distributeprefabs") or {}).get("entries", []):
                v = e["value"]
                values.add(float(v["weight"]) if isinstance(v, dict) else float(v))
    d = blob.sidecar("distribute.json")
    for v in d["variants"]:
        values.update(float(e["value"]) for e in v["entries"])
    for p in d["picks"]:
        values.update(float(e["value"]) for e in p)
    for o in d["ocean"]:
        values.update(float(e["value"]) for e in o.get("entries", []))
    return sorted(values)


def weight_id(v):
    return weights().index(float(v))
