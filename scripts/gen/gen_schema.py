#!/usr/bin/env python3
"""Writes config.schema.json (JSON Schema 2020-12 for search config v2, docs/config.md) from the caps the finder
enforces (seedfinder/filters/), the names of scripts/catalog/catalog.json (forest) and of the caves sidecar caves.json.
`-` prints it instead. Fails when the caps table of docs/config.md (its rows in the order of WEBSITE_CAPS) or the website's caps disagree with the
finder.

Run from the project root (regen.sh runs it after the catalog modules):
    python3 scripts/gen/gen_schema.py
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
from gen_cave_catalog import Catalog  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "scripts" / "catalog" / "catalog.json"
CAVE_CATALOG = ROOT / "scripts" / "catalog" / "cave_catalog.json"
OUTPUT = ROOT / "config.schema.json"
FILTERS = ROOT / "seedfinder" / "filters"
SPEC = ROOT / "docs" / "config.md"
WEBSITE_CONFIG = ROOT / "website" / "lib" / "config" / "seedfinder-config.ts"
METRICS = ("straight", "walk")
ORDERS = ("any", "fixed")
PLATFORMS = ("windows", "linux")
DEFAULT_PLATFORM = "windows"
SHARDS = ("forest", "caves")
DEFAULT_SHARD = "forest"
MAX_INTEGER = 4294967295
MAX_DISTANCE = 1000000
WEBSITE_CAPS = {"entries": "MAX_FILTERS", "rules": "MAX_RULES_PER_SECTION", "prefab ids": "MAX_PREFAB_IDS",
                "set pieces": "MAX_SET_PIECES_PER_RULE", "tasks": "MAX_TASKS_PER_LIST", "stops": "MAX_ROUTE_STOPS",
                "tiles": "MAX_TILE_NAMES"}


def caps():
    found = {}
    for path in sorted(FILTERS.glob("*.bend")):
        for cap, noun in re.findall(r'capped\([^,]+, (\d+), "([^"]+)"', path.read_text(encoding="utf-8")):
            found.setdefault(noun, set()).add(int(cap))
    if found.keys() != WEBSITE_CAPS.keys() or any(len(values) != 1 for values in found.values()):
        sys.exit(f"gen_schema.py: the caps in {FILTERS.relative_to(ROOT)} are not one per {list(WEBSITE_CAPS)}: "
                 f"{found}")
    finder = {noun: min(found[noun]) for noun in WEBSITE_CAPS}
    section = SPEC.read_text(encoding="utf-8").split("\n## 6. Caps\n", 1)[1].split("\n## ", 1)[0]
    rows = [line for line in section.splitlines() if line.startswith("|")][2:]
    spec = dict(zip(WEBSITE_CAPS, (int(re.search(r"\d+", row.split("|")[-2]).group()) for row in rows)))
    if len(rows) != len(WEBSITE_CAPS):
        spec["rows"] = len(rows)
    website_text = WEBSITE_CONFIG.read_text(encoding="utf-8")
    website = {noun: int(re.search(rf"export const {name} = (\d+);", website_text).group(1))
               for noun, name in WEBSITE_CAPS.items()}
    for source, got in ((SPEC, spec), (WEBSITE_CONFIG, website)):
        if got != finder:
            sys.exit(f"gen_schema.py: the caps of {source.relative_to(ROOT)} ({got}) differ from the finder's "
                     f"({finder})")
    return finder


CAPS = caps()


def ref(name):
    return {"$ref": f"#/$defs/{name}"}


def closed(properties, required=(), description=None):
    schema = {"type": "object", "additionalProperties": False, "properties": properties}
    if required:
        schema["required"] = list(required)
    if description:
        schema = {"description": description, **schema}
    return schema


def one_or_list(item, cap, description):
    return {"description": description,
            "oneOf": [ref(item), {"type": "array", "minItems": 1, "maxItems": cap, "items": ref(item)}]}


def rules(rule):
    return {"type": "array", "maxItems": CAPS["rules"], "items": ref(rule)}


def setpiece_items(rule, group):
    return {"type": "array", "maxItems": CAPS["rules"], "items": {"oneOf": [ref(rule), ref(group)]}}


def setpiece_group(rule):
    total = {**ref("bound"), "description": "Bounds the counts of every name of the group's rules, summed."}
    return closed({"any": {"type": "array", "minItems": 1, "maxItems": CAPS["rules"], "items": ref(rule)},
                   "total": total}, ("any",),
                  description="Holds when any of its rules holds (OR) and its total is within bounds.")


def metric_fields(links="wormholes"):
    return {"metric": ref("metric"), links: {"type": "boolean", "default": False}}


def names(catalog):
    return {
        "taskId": sorted(task["id"] for task in catalog["tasks"]),
        "setPieceName": sorted(piece["name"] for piece in catalog["setpieces"]
                               if piece["filterable"] and piece["forest"]),
        "prefabId": sorted(prefab["id"] for prefab in catalog["prefabs"]),
        "landTile": sorted(tile["name"] for tile in catalog["tiles"] if tile["land"]),
    }


def definitions(catalog):
    return {
        "uint32": {"type": "integer", "minimum": 0, "maximum": MAX_INTEGER},
        "distance": {"description": "World units (1 tile = 4).", "type": "number", "minimum": 0,
                     "maximum": MAX_DISTANCE},
        "metric": {"enum": list(METRICS), "default": "straight"},
        **{name: {"enum": values} for name, values in names(catalog).items()},
        "taskList": {"type": "array", "maxItems": CAPS["tasks"], "items": ref("taskId")},
        "prefabs": one_or_list("prefabId", CAPS["prefab ids"], "A prefab id or a list of them (their union)."),
        "tiles": one_or_list("landTile", CAPS["tiles"], "A land tile name or a list of them."),
        "bound": {"description": "min, or [min, max] inclusive.",
                  "oneOf": [ref("uint32"), {"type": "array", "prefixItems": [ref("uint32"), ref("uint32")],
                                            "minItems": 2, "items": False}]},
        "tasks": closed({"required": ref("taskList"), "excluded": ref("taskList")}),
        "prefabSwaps": closed({swap["category"]: {"enum": [option["name"] for option in swap["options"]]}
                               for swap in catalog["prefab_swaps"]}),
        "setPieceRule": closed({
            "tasks": ref("taskList"),
            "required": {"type": "object", "maxProperties": CAPS["set pieces"], "propertyNames": ref("setPieceName"),
                         "additionalProperties": ref("bound")},
            "placed": {"type": "array", "maxItems": CAPS["set pieces"], "uniqueItems": True,
                       "items": ref("setPieceName"),
                       "description": "Names of `required` whose bound counts only the copies the generated world "
                                      "placed (ensure placed), which makes the entry need the world."}}),
        "setPieceGroup": setpiece_group("setPieceRule"),
        "near": closed({"prefab": ref("prefabs"), "within": ref("distance"), **metric_fields()}, ("prefab", "within")),
        "countRule": closed({"prefab": ref("prefabs"), "min": ref("uint32"), "max": ref("uint32"), "near": ref("near")},
                            ("prefab",)),
        "distanceRule": closed({"from": ref("prefabs"), "to": ref("prefabs"), "min": ref("distance"),
                                "max": ref("distance"), **metric_fields()}, ("from", "to")),
        "tileRule": closed({"from": ref("tiles"), "to": ref("tiles"), "max": ref("uint32")}, ("from", "to", "max")),
        "bridgeRule": closed({"min": ref("distance"), "max": ref("distance")},
                             description="The longest turf bridge (a room's turf line along a link to a room left far "
                                         "away), in world units."),
        "routeRule": closed({"from": ref("prefabs"),
                             "visit": {"type": "array", "minItems": 1, "maxItems": CAPS["stops"],
                                       "items": ref("prefabs")},
                             "to": ref("prefabs"), "max": ref("distance"),
                             "order": {"enum": list(ORDERS), "default": "any"}, **metric_fields()},
                            ("from", "visit", "max")),
        "generation": closed({"tasks": ref("tasks"), "prefab_swaps": ref("prefabSwaps"),
                              "setpieces": setpiece_items("setPieceRule", "setPieceGroup")},
                             description="The level table: a seed is a candidate when all its sections and rules hold "
                                         "(AND)."),
        "filter": closed({"counts": rules("countRule"), "distances": rules("distanceRule"), "tiles": rules("tileRule"),
                          "bridges": rules("bridgeRule"), "routes": rules("routeRule")},
                         description="World rules: all sections and all rules must hold (AND)."),
    }


def cave_definitions():
    cat = Catalog(blob.sidecar("caves.json"), blob.sidecar("layouts.json"))
    names = {
        "caveTaskId": sorted(cat.tasks),
        "caveSetPieceName": sorted(cat.keys),
        "cavePrefabId": sorted(prefab["id"] for prefab in json.loads(CAVE_CATALOG.read_text(encoding="utf-8"))["prefabs"]),
    }
    swaps = {}
    for swap in cat.caves["prefab_swaps"]:
        swaps[swap["category"]] = {"enum": [option["name"] for option in swap["sets"] if option["valid"]]}
    return {
        **{name: {"enum": values} for name, values in names.items()},
        "caveTaskList": {"type": "array", "maxItems": CAPS["tasks"], "items": ref("caveTaskId")},
        "caveTasks": closed({"required": ref("caveTaskList"), "excluded": ref("caveTaskList")}),
        "cavePrefabSwaps": closed(swaps),
        "caveSetPieceRule": closed({
            "tasks": ref("caveTaskList"),
            "required": {"type": "object", "maxProperties": CAPS["set pieces"],
                         "propertyNames": ref("caveSetPieceName"), "additionalProperties": ref("bound")}}),
        "caveSetPieceGroup": setpiece_group("caveSetPieceRule"),
        "cavePrefabs": one_or_list("cavePrefabId", CAPS["prefab ids"], "A caves prefab id or a list of them (their union)."),
        "caveNear": closed({"prefab": ref("cavePrefabs"), "within": ref("distance"), **metric_fields("pillars")},
                           ("prefab", "within")),
        "caveCountRule": closed({"prefab": ref("cavePrefabs"), "min": ref("uint32"), "max": ref("uint32"),
                                 "near": ref("caveNear")}, ("prefab",)),
        "caveDistanceRule": closed({"from": ref("cavePrefabs"), "to": ref("cavePrefabs"), "min": ref("distance"),
                                    "max": ref("distance"), **metric_fields("pillars")}, ("from", "to")),
        "caveRouteRule": closed({"from": ref("cavePrefabs"),
                                 "visit": {"type": "array", "minItems": 1, "maxItems": CAPS["stops"],
                                           "items": ref("cavePrefabs")},
                                 "to": ref("cavePrefabs"), "max": ref("distance"),
                                 "order": {"enum": list(ORDERS), "default": "any"}, **metric_fields("pillars")},
                                ("from", "visit", "max")),
        "caveGeneration": closed({"tasks": ref("caveTasks"), "prefab_swaps": ref("cavePrefabSwaps"),
                                  "setpieces": setpiece_items("caveSetPieceRule", "caveSetPieceGroup")},
                                 description="The caves' level table: a seed is a candidate when all its sections and "
                                             "rules hold (AND)."),
        "caveFilter": closed({"counts": rules("caveCountRule"), "distances": rules("caveDistanceRule"),
                              "tiles": rules("tileRule"), "bridges": rules("bridgeRule"), "routes": rules("caveRouteRule")},
                             description="World rules: all sections and all rules must hold (AND). Counts, distances "
                                         "and routes use the caves' prefabs, and `pillars` lets a distance use the "
                                         "tentacle pillar links."),
    }


def schema(catalog):
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "DST seed finder search config v2",
        "description": f"Generated by scripts/gen/gen_schema.py from scripts/catalog/catalog.json (game build "
                       f"{catalog['game_build']}) and the caves sidecar; see docs/config.md.",
        "$comment": "Not expressible here and checked by the finder: repeated object keys, integers written with a "
                    "fraction (20.0), and route visit stops that share a prefab id with each other or with from/to. The "
                    "--shard flag of the finder overrides `shard`.",
        **closed({"version": {"const": 2},
                  "shard": {"description": "The shard whose worlds are searched: the forest (the overworld) or the "
                                           "caves. The caves shard's sections use its own tasks, set pieces and prefabs.",
                            "enum": list(SHARDS), "default": DEFAULT_SHARD},
                  "platform": {"description": "The OS hosting the world. The level table (tasks, prefab_swaps, "
                                              "setpieces) is the same on both; counts, distances, tiles, bridges "
                                              "and routes are evaluated on this platform's world.",
                               "enum": list(PLATFORMS), "default": DEFAULT_PLATFORM},
                  "settings": {"description": "Reserved: only default settings.", "type": "object",
                               "additionalProperties": {"const": "default"}},
                  "generation": {"description": "The level table, shared by every filter: only the worlds of the "
                                                "seeds it accepts are generated."},
                  "filters": {"description": "Alternatives (OR) on the generated worlds.", "type": "array",
                              "maxItems": CAPS["entries"]}}),
        "if": {"required": ["shard"], "properties": {"shard": {"const": "caves"}}},
        "then": {"properties": {"generation": ref("caveGeneration"), "filters": {"items": ref("caveFilter")}}},
        "else": {"properties": {"generation": ref("generation"), "filters": {"items": ref("filter")}}},
        "$defs": {**definitions(catalog), **cave_definitions()},
    }


def main():
    text = json.dumps(schema(json.loads(CATALOG.read_text(encoding="utf-8"))), indent=1, ensure_ascii=False) + "\n"
    if sys.argv[1:] == ["-"]:
        sys.stdout.write(text)
    else:
        OUTPUT.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
