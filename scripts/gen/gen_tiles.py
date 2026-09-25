#!/usr/bin/env python3
"""Writes data/tile_groups.bend from out/tiles.json (extract_tiles.lua): the TileGroupManager ranges and special tiles
the C++ tile stages test, the ForceConnectivity/DrawRoads tiles and ROAD_PARAMETERS as float bits. `-` prints it."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402


def main():
    d = blob.sidecar("tiles.json")
    m = blob.Module("tile_groups", "scripts/gen/gen_tiles.py",
                    "Tile groups, special tiles and road parameters of the C++ tile stages.", imports=())
    for group in ("land", "ocean", "impassable", "noise"):
        m.comment(f"{group} ranges (legacy, current), inclusive")
        for k, (lo, hi) in enumerate(d[group]):
            m.const(f"{group}_{k}_lo", lo)
            m.const(f"{group}_{k}_hi", hi)
    m.comment("WORLD_TILES")
    for name, value in sorted(d["tiles"].items()):
        m.const(f"tile_{name}", value)
    m.comment("ROAD_PARAMETERS: subdivisions (integer), then (float) of each width parameter as F32 bits")
    roads = d["roads"]
    m.const("road_subdivisions", roads["subdivisions"])
    for name in ("min_width", "max_width", "min_edge_width", "max_edge_width", "width_jitter_scale"):
        m.const(f"road_{name}_bits", blob.f32_bits(roads[name]))
    m.emit()


if __name__ == "__main__":
    main()
