#!/usr/bin/env python3
"""Writes data/ocean.bend from out/ocean.json: bunch spawners in the pairs() order BunchSpawnerRun uses, the ocean
generation config (map/ocean_gen_config.lua) and the noise tile functions as exact threshold tables (noise < t
selects the tile below t). `-` prints the module instead."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402


def integer(v):
    assert isinstance(v, int) and not isinstance(v, bool), v
    return blob.unit(v)


def snake(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name).lower()


def main():
    d = blob.sidecar("ocean.json")
    m = blob.Module("ocean", "scripts/gen/gen_ocean.py", "Bunch spawners, ocean gen config, noise tile functions.")
    bunches = []
    for b in d["bunches"]:
        prefab = ids.sid(b["prefab"]) if b.get("prefab") else blob.NONE
        closure = ids.closure_id(b["prefab_closure"]) if b.get("prefab_closure") else blob.NONE
        bunches.append([ids.sid(b["name"]), prefab, closure, integer(b["range"]), integer(b["min"]), integer(b["max"]),
                        integer(b["min_spacing"]), len(b["valid_tile_types"])] + [integer(t) for t in b["valid_tile_types"]])
    m.table("bunches", bunches, "Row i in pairs(Bunches) order: spawner prefab, bunch prefab (NONE: a closure picks it), "
                                "prefab closure, range, min, max, min_spacing, n, n valid tile types.")
    m.table("bunch_blockers", [[ids.sid(p) for p in d["bunch_blockers"]]], "Row 0: BunchBlockers.")
    noise = []
    for n in d["noise_functions"]:
        tile = blob.NONE if n["tile"] == "default" else integer(n["tile"])
        row = [tile, integer(n["table"]["first"]), len(n["table"]["steps"])]
        for step in n["table"]["steps"]:
            row += blob.f64(step["threshold"]) + [integer(step["above"])]
        noise.append(row)
    m.table("noise_functions", noise, "Row i: noise tile (NONE = default), tile for noise below the first threshold, n, "
                                      "then n (threshold f64 4 units, tile from there on); tiles sorted, default last.")
    levels = []
    for entry in d["config"]:
        key = snake(entry["key"])
        if "rows" in entry:
            levels.append((key, entry["rows"]))
        elif isinstance(entry["value"], int) and not isinstance(entry["value"], bool):
            m.const(f"config_{key}", entry["value"])
        else:
            bits = blob.f64_bits(entry["value"])
            m.const(f"config_{key}", f"({bits >> 32}, {bits & 0xFFFFFFFF})", "U32 & U32")
    for key, rows in sorted(levels):
        m.table(f"config_{key}", [[integer(r[0])] + blob.f64(r[1]) for r in rows],
                f"ocean_gen_config.{key}: (tile, level f64) rows in array order.")
    m.emit()


if __name__ == "__main__":
    main()
