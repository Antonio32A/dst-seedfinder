#!/usr/bin/env python3
"""Reduce a gtworld world.json (emulator or real-game dump) to the fields the catalog needs.

usage: summarize_world.py <world.json> <out.json> [source-label]
"""
import base64
import collections
import json
import struct
import sys


def tile_histogram(world):
    if not world.get("tiles"):
        return {}
    raw = base64.b64decode(world["tiles"])
    n = (len(raw) - 9) // 2
    counts = collections.Counter(struct.unpack("<%dH" % n, raw[9:9 + 2 * n]))
    names = {v: k for k, v in world.get("world_tile_map", {}).items()}
    return {names.get(t, str(t)): c for t, c in sorted(counts.items())}


def summarize(world, source):
    swaps = world.get("prefab_swaps")
    return {
        "seed": world.get("seed"),
        "source": source,
        "status": world.get("status"),
        "attempts": world.get("attempts"),
        "prefab_swaps": swaps if isinstance(swaps, dict) else None,
        "tasks": world.get("tasks"),
        "set_pieces": {k: v.get("count", 1) for k, v in (world.get("set_pieces") or {}).items()},
        "entity_counts": world.get("entity_counts") or {},
        "tile_counts": tile_histogram(world),
        "world_tile_map": world.get("world_tile_map") or {},
    }


def main():
    src, dst = sys.argv[1], sys.argv[2]
    source = sys.argv[3] if len(sys.argv) > 3 else "emulator"
    with open(src) as f:
        world = json.load(f)
    with open(dst, "w") as f:
        json.dump(summarize(world, source), f, separators=(",", ":"))


if __name__ == "__main__":
    main()
