#!/usr/bin/env python3
"""Writes config.schema.json (JSON Schema 2020-12 for search config v1, docs/config.md) from the caps of the spec
and the names of scripts/catalog/catalog.json. `-` prints it instead.

Run from the project root (regen.sh runs it after the catalog modules):
    python3 scripts/gen/gen_schema.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "scripts" / "catalog" / "catalog.json"
OUTPUT = ROOT / "config.schema.json"
METRICS = ("straight", "walk")
ORDERS = ("any", "fixed")
PLATFORMS = ("windows", "linux")
DEFAULT_PLATFORM = "windows"
MAX_INTEGER = 4294967295
MAX_DISTANCE = 1000000
CAPS = {"entries": 8, "rules": 16, "prefab ids": 16, "set pieces": 16, "tasks": 25, "stops": 6, "tiles": 16}


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


def metric_fields():
    return {"metric": ref("metric"), "wormholes": {"type": "boolean", "default": False}}


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
                         "additionalProperties": ref("bound")}}),
        "near": closed({"prefab": ref("prefabs"), "within": ref("distance"), **metric_fields()}, ("prefab", "within")),
        "countRule": closed({"prefab": ref("prefabs"), "min": ref("uint32"), "max": ref("uint32"), "near": ref("near")},
                            ("prefab",)),
        "distanceRule": closed({"from": ref("prefabs"), "to": ref("prefabs"), "min": ref("distance"),
                                "max": ref("distance"), **metric_fields()}, ("from", "to")),
        "tileRule": closed({"from": ref("tiles"), "to": ref("tiles"), "max": ref("uint32")}, ("from", "to", "max")),
        "routeRule": closed({"from": ref("prefabs"),
                             "visit": {"type": "array", "minItems": 1, "maxItems": CAPS["stops"],
                                       "items": ref("prefabs")},
                             "to": ref("prefabs"), "max": ref("distance"),
                             "order": {"enum": list(ORDERS), "default": "any"}, **metric_fields()},
                            ("from", "visit", "max")),
        "entry": closed({"passive": {"type": "boolean", "default": False,
                                     "description": "Only decided on candidates of the entries that aren't passive."},
                         "tasks": ref("tasks"), "prefab_swaps": ref("prefabSwaps"), "setpieces": rules("setPieceRule"),
                         "counts": rules("countRule"), "distances": rules("distanceRule"), "tiles": rules("tileRule"),
                         "routes": rules("routeRule")},
                        description="All sections and all rules must hold (AND)."),
    }


def schema(catalog):
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "DST seed finder search config v1",
        "description": f"Generated by scripts/gen/gen_schema.py from scripts/catalog/catalog.json (game build "
                       f"{catalog['game_build']}); see docs/config.md.",
        "$comment": "Not expressible here and checked by the finder: repeated object keys, integers written with a "
                    "fraction (20.0), route visit stops that share a prefab id with each other or with from/to, and "
                    "a criteria list whose entries are all passive.",
        **closed({"version": {"const": 1},
                  "platform": {"description": "The OS hosting the world. The level table (tasks, prefab_swaps, "
                                              "setpieces) is the same on both; counts, distances, tiles and routes "
                                              "are evaluated on this platform's world.",
                               "enum": list(PLATFORMS), "default": DEFAULT_PLATFORM},
                  "settings": {"description": "Reserved: only default settings.", "type": "object",
                               "additionalProperties": {"const": "default"}},
                  "criteria": {"description": "Alternatives (OR).", "type": "array", "maxItems": CAPS["entries"],
                               "items": ref("entry")}}),
        "$defs": definitions(catalog),
    }


def main():
    text = json.dumps(schema(json.loads(CATALOG.read_text(encoding="utf-8"))), indent=1, ensure_ascii=False) + "\n"
    if sys.argv[1:] == ["-"]:
        sys.stdout.write(text)
    else:
        OUTPUT.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
