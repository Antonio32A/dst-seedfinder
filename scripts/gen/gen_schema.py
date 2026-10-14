#!/usr/bin/env python3
"""Writes config.schema.json (JSON Schema 2020-12 for search config v3, docs/config.md) from the caps the finder
enforces (seedfinder/filters/), the game builds of builds.json and, per build, the names of its forest catalog
(scripts/catalog/<catalog build>/catalog.json) and of its caves sidecars (scripts/gen/out/<build>/caves.json). The
name lists of the latest build are the plain $defs; a build whose lists differ gets its own copies of the $defs that
differ (suffixed with its number), selected by `build`. `-` prints it instead. Fails when the caps table of docs/config.md (its rows in the order of WEBSITE_CAPS) or the website's caps disagree with the
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
                "tiles": "MAX_TILE_NAMES", "characters": "MAX_FILTER_NAME_LENGTH"}


def caps():
    found = {}
    for path in sorted(FILTERS.glob("*.bend")):
        for cap, noun in re.findall(r'capped(?:_text)?\([^,]+, (\d+), "([^"]+)"', path.read_text(encoding="utf-8")):
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
        "filterName": {"type": "string", "maxLength": CAPS["characters"],
                       "description": "Labels the filter and the hits it matches (their `name`)."},
        "generation": closed({"tasks": ref("tasks"), "prefab_swaps": ref("prefabSwaps"),
                              "setpieces": setpiece_items("setPieceRule", "setPieceGroup")},
                             description="The level table: a seed is a candidate when all its sections and rules hold "
                                         "(AND)."),
        "filter": closed({"name": ref("filterName"), "counts": rules("countRule"),
                          "distances": rules("distanceRule"), "tiles": rules("tileRule"),
                          "bridges": rules("bridgeRule"), "routes": rules("routeRule")},
                         description="World rules: all sections and all rules must hold (AND)."),
    }


def cave_definitions(number):
    sidecars = blob.out_dir().parent / str(number)
    cat = Catalog(*(json.loads((sidecars / name).read_text()) for name in ("caves.json", "layouts.json")))
    names = {
        "caveTaskId": sorted(cat.tasks),
        "caveSetPieceName": sorted(cat.keys),
        "cavePrefabId": sorted(prefab["id"] for prefab in catalog(number, "caves")["prefabs"]),
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
        "caveFilter": closed({"name": ref("filterName"), "counts": rules("caveCountRule"),
                              "distances": rules("caveDistanceRule"), "tiles": rules("tileRule"),
                              "bridges": rules("bridgeRule"), "routes": rules("caveRouteRule")},
                             description="World rules: all sections and all rules must hold (AND). Counts, distances "
                                         "and routes use the caves' prefabs, and `pillars` lets a distance use the "
                                         "tentacle pillar links."),
    }


def catalog(number, shard):
    return json.loads(blob.registry.catalog_path(number, shard).read_text(encoding="utf-8"))


def definitions_of(number):
    return {**definitions(catalog(number, "forest")), **cave_definitions(number)}


def refs_in(value):
    if isinstance(value, dict):
        return {ref_name for v in value.values() for ref_name in refs_in(v)} | (
            {value["$ref"].removeprefix("#/$defs/")} if "$ref" in value else set())
    if isinstance(value, list):
        return {ref_name for v in value for ref_name in refs_in(v)}
    return set()


def renamed(value, names, suffix):
    if isinstance(value, dict):
        return {k: (f"#/$defs/{v.removeprefix('#/$defs/')}{suffix}" if k == "$ref" and v.removeprefix("#/$defs/") in names
                    else renamed(v, names, suffix)) for k, v in value.items()}
    if isinstance(value, list):
        return [renamed(v, names, suffix) for v in value]
    return value


def own_definitions(base, defs):
    """The $defs of `defs` that differ from `base`, directly or through a $ref to one that does."""
    own = {name for name, value in defs.items() if base.get(name) != value}
    while True:
        more = {name for name, value in defs.items() if refs_in(value) & own} - own
        if not more:
            return own
        own |= more


def shard_switch(own, suffix):
    def at(name):
        return ref(name + suffix if name in own else name)
    return {"if": {"required": ["shard"], "properties": {"shard": {"const": "caves"}}},
            "then": {"properties": {"generation": at("caveGeneration"), "filters": {"items": at("caveFilter")}}},
            "else": {"properties": {"generation": at("generation"), "filters": {"items": at("filter")}}}}


def build_named(numbers):
    return {"required": ["build"], "properties": {"build": {"enum": numbers}}}


def builds_part():
    """The $defs of every build and the if/then/else that picks a build's names (the latest build's are unsuffixed)."""
    latest = blob.registry.latest()
    base = definitions_of(latest)
    defs = dict(base)
    groups = {}
    for entry in blob.registry.builds():
        if entry["number"] != latest:
            own_defs = definitions_of(entry["number"])
            own = own_definitions(base, own_defs)
            key = json.dumps({name: own_defs[name] for name in sorted(own)}, sort_keys=True)
            groups.setdefault(key, (own_defs, own, []))[2].append(entry["number"])
    switch = shard_switch(set(), "")
    for own_defs, own, numbers in reversed(list(groups.values())):
        suffix = f"_{numbers[0]}"
        defs.update({name + suffix: renamed(own_defs[name], own, suffix) for name in sorted(own)})
        if own:
            switch = {"if": build_named(numbers), "then": shard_switch(own, suffix), "else": switch}
    return switch, defs


def schema():
    numbers = [entry["number"] for entry in blob.registry.builds()]
    no_caves = [entry["number"] for entry in blob.registry.builds() if "caves" not in entry["shards"]]
    switch, defs = builds_part()
    shards = {"allOf": [{"if": build_named(no_caves), "then": {"properties": {"shard": {"not": {"const": "caves"}}}}}]} \
        if no_caves else {}
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "DST seed finder search config v3",
        "description": f"Generated by scripts/gen/gen_schema.py from builds.json, each build's catalogs "
                       f"(scripts/catalog/<build>/) and caves sidecars; see docs/config.md.",
        "$comment": "Not expressible here and checked by the finder: repeated object keys, integers written with a "
                    "fraction (20.0), and route visit stops that share a prefab id with each other or with from/to. The "
                    "--shard and --build flags of the finder override `shard` and `build`.",
        **closed({"version": {"description": "The config format.", "const": 3},
                  "build": {"description": "The game build the worlds are generated for; it decides the names "
                                           "the sections may use (builds.json).", "enum": numbers},
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
                              "maxItems": CAPS["entries"]}}, ("build",)),
        **shards,
        **switch,
        "$defs": defs,
    }


def main():
    text = json.dumps(schema(), indent=1, ensure_ascii=False) + "\n"
    if sys.argv[1:] == ["-"]:
        sys.stdout.write(text)
    else:
        OUTPUT.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
