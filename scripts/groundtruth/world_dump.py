#!/usr/bin/env python3
"""Converts a generated world (world.json of the emulator or the groundtruth dump) to the world dump (docs/world-dump.md)
that `seedfinder world eval` and `seedfinder world find --worlds DIR` read.

usage: world_dump.py [--platform windows|linux] WORLD.json OUT.dstw
       world_dump.py [--platform windows|linux] --tree SRC_DIR OUT_DIR   every SRC_DIR/<seed>/world.json -> OUT_DIR/<seed>.dstw
       world_dump.py [--platform windows|linux] --worlds SRC_DIR OUT_DIR  every SRC_DIR/<seed>.json -> OUT_DIR/<seed>.dstw

A world's shard is the "shard" field of its JSON (forest when it has none), and it goes into the dump's header.

Every entity is written, whatever its prefab. Coordinates must have at most 2 decimals (the dump mod's printf): the
tool checks that each one is printed as k / 100. Road points are multiples of 0.1 and are rounded to hundredths; roads the
game dropped (null entries) are skipped.
"""
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from world import decode_tiles, pillar_links_of, wormhole_links_of, Instance  # noqa: E402

VERSION = 3
PLATFORMS = {None: 0, "windows": 1, "linux": 2}
SHARDS = {"forest": 0, "caves": 1}


def centi(value):
    k = round(value * 100)
    sign = "-" if k < 0 else ""
    whole, fraction = divmod(abs(k), 100)
    text = f"{sign}{whole}" if not fraction else f"{sign}{whole}." + f"{fraction:02d}".rstrip("0")
    if text != json.dumps(value):
        raise ValueError(f"coordinate {value!r} is not printed with at most 2 decimals")
    return k


def u32s(*values):
    return struct.pack(f"<{len(values)}I", *values)


def padded(raw):
    return raw + bytes(-len(raw) % 4)


def string(text):
    raw = text.encode("utf-8")
    return u32s(len(raw)) + padded(raw)


def section(tag, payload):
    return tag + u32s(len(payload)) + payload


def entities_payload(entities):
    prefabs = sorted((prefab for prefab, positions in entities.items() if positions), key=str.encode)
    payload = u32s(len(prefabs))
    for prefab in prefabs:
        positions = entities[prefab]
        centis = [centi(value) for position in positions for value in position]
        payload += string(prefab) + u32s(len(positions)) + struct.pack(f"<{len(centis)}i", *centis)
    return payload


def roads_payload(roads):
    kept = [road for road in roads if road is not None]
    payload = u32s(len(kept))
    for weight, *points in kept:
        centis = [round(value * 100) for point in points for value in point]
        payload += u32s(weight, len(points)) + struct.pack(f"<{len(centis)}i", *centis)
    return payload


def pillars_payload(links, entities):
    positions = {prefab: position for position, prefab in enumerate(sorted(
        (prefab for prefab, instances in entities.items() if instances), key=str.encode))}
    return u32s(len(links), *(word for entry, leave in links
                              for word in (positions[entry.prefab], entry.index, positions[leave.prefab], leave.index)))


def dump_of(data, platform):
    ok = data.get("status") in (None, "ok") and "entities" in data
    shard = data.get("shard", "forest")
    header = b"DSTW" + u32s(VERSION, data.get("seed") or 0, int(ok), PLATFORMS[platform], SHARDS[shard])
    if not ok:
        return header
    width, height = data["width"], data["height"]
    names = sorted(data["world_tile_map"].items(), key=lambda item: item[0].encode())
    tile_names = u32s(len(names)) + b"".join(u32s(tile) + string(name) for name, tile in names)
    tiles = decode_tiles(data["tiles"])
    assert len(tiles) == width * height, (len(tiles), width, height)
    entities = data["entities"]
    instances = {prefab: [Instance(prefab, i, x, z) for i, (x, z) in enumerate(positions)]
                 for prefab, positions in entities.items()}
    teleporters = data.get("teleporters") or []
    links = wormhole_links_of(teleporters, instances)
    pillars = section(b"PILL", pillars_payload(pillar_links_of(teleporters, instances), entities)) if shard == "caves" else b""
    return (header + u32s(int(data.get("meta", {}).get("build_version", 0)), width, height)
            + section(b"TNAM", tile_names)
            + section(b"TILE", padded(struct.pack(f"<{len(tiles)}H", *tiles)))
            + section(b"ENTS", entities_payload(entities))
            + section(b"WORM", u32s(len(links), *(index for entry, leave in links for index in (entry.index, leave.index))))
            + pillars
            + section(b"ROAD", roads_payload(data.get("roads") or [])))


def convert(source, target, platform):
    data = json.loads(Path(source).read_text(encoding="utf-8"))
    Path(target).write_bytes(dump_of(data, platform))
    return data.get("seed")


def main():
    args = sys.argv[1:]
    platform = None
    if args[:1] == ["--platform"]:
        platform, args = args[1], args[2:]
    if args[0] == "--tree":
        out = Path(args[2])
        out.mkdir(parents=True, exist_ok=True)
        for world in sorted(Path(args[1]).glob("*/world.json")):
            seed = convert(world, out / f"{world.parent.name}.dstw", platform)
            print(f"{world} -> {out / (world.parent.name + '.dstw')} (seed {seed})")
    elif args[0] == "--worlds":
        out = Path(args[2])
        out.mkdir(parents=True, exist_ok=True)
        for world in sorted(Path(args[1]).glob("*.json"), key=lambda path: path.stem):
            if world.stem.isdigit():
                print(f"{world} -> {out / (world.stem + '.dstw')} (seed {convert(world, out / (world.stem + '.dstw'), platform)})")
    else:
        convert(args[0], args[1], platform)


if __name__ == "__main__":
    main()
