#!/usr/bin/env python3
"""Converts a generated world (world.json of the emulator or the groundtruth dump) to the binary dump that
`seedfinder world eval` and `seedfinder world find --worlds DIR` read (filters/world.bend).

usage: world_dump.py [--platform windows|linux] WORLD.json OUT.dstw
       world_dump.py [--platform windows|linux] --tree SRC_DIR OUT_DIR   every SRC_DIR/<seed>/world.json -> OUT_DIR/<seed>.dstw

Format: little-endian u32 words.
  "DSTW" (0x57545344), format 1, seed, status (1 = generated, 0 = gave up), platform (0 unknown, 1 windows, 2 linux),
  width, height
  T = number of vocabulary tiles, then T words: the world_tile_map id of each vocabulary tile (65535 if absent)
  P = number of vocabulary prefabs, then P words: the instance count of each vocabulary prefab
  per vocabulary prefab, per instance (savedata order): x (f64: high word, low word), z (f64), x*100 and z*100 as
    int32, flags (bit 0: x was a JSON integer, bit 1: z was)
  L = number of wormhole links, then L pairs (entry index, exit index) into the `wormhole` instances
  ceil(W*H/2) words: the tiles, two u16 per word (the first tile in the low half)
The vocabulary is seedfinder/data/search_vocab.bend's (catalog order): prefabs outside it are dropped, which keeps every
instance index. Coordinates must have at most 2 decimals (the worldgen's own precision); the tool checks that Python
prints each one as the Bend code will.
"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from world import decode_tiles, wormhole_links_of, Instance  # noqa: E402

CATALOG = json.loads((ROOT / "scripts" / "catalog" / "catalog.json").read_text(encoding="utf-8"))
PREFABS = [prefab["id"] for prefab in CATALOG["prefabs"]]
TILES = [tile["name"] for tile in CATALOG["tiles"]]
MAGIC = 0x57545344
ABSENT_TILE = 65535


def centi_text(k, integer):
    if integer:
        return str(k // 100)
    sign = "-" if k < 0 else ""
    whole, fraction = divmod(abs(k), 100)
    digits = f"{fraction:02d}".rstrip("0") or "0"
    return f"{sign}{whole}.{digits}"


def coordinate(value):
    integer = isinstance(value, int)
    k = round(value * 100)
    if centi_text(k, integer) != json.dumps(value) or (integer and k % 100):
        raise ValueError(f"coordinate {value!r} has more than 2 decimals")
    return struct.unpack("<II", struct.pack("<d", float(value))), k & 0xFFFFFFFF, integer


def instance_words(x, z):
    (x_lo, x_hi), xk, x_int = coordinate(x)
    (z_lo, z_hi), zk, z_int = coordinate(z)
    return [x_hi, x_lo, z_hi, z_lo, xk, zk, int(x_int) | int(z_int) << 1]


PLATFORMS = {None: 0, "windows": 1, "linux": 2}


def words_of(data, platform):
    ok = data.get("status") in (None, "ok") and "entities" in data
    words = [MAGIC, 1, data.get("seed") or 0, int(ok), PLATFORMS[platform]]
    if not ok:
        return words
    width, height = data["width"], data["height"]
    words += [width, height, len(TILES)] + [data["world_tile_map"].get(name, ABSENT_TILE) for name in TILES]
    entities = data["entities"]
    words += [len(PREFABS)] + [len(entities.get(prefab, [])) for prefab in PREFABS]
    for prefab in PREFABS:
        for x, z in entities.get(prefab, []):
            words += instance_words(x, z)
    instances = {prefab: [Instance(prefab, i, x, z) for i, (x, z) in enumerate(positions)]
                 for prefab, positions in entities.items()}
    links = wormhole_links_of(data.get("teleporters") or [], instances)
    words += [len(links)] + [index for entry, leave in links for index in (entry.index, leave.index)]
    tiles = decode_tiles(data["tiles"])
    assert len(tiles) == width * height, (len(tiles), width, height)
    tiles += [0] * (len(tiles) % 2)
    words += [tiles[i] | tiles[i + 1] << 16 for i in range(0, len(tiles), 2)]
    return words


def convert(source, target, platform):
    data = json.loads(Path(source).read_text(encoding="utf-8"))
    words = words_of(data, platform)
    Path(target).write_bytes(struct.pack(f"<{len(words)}I", *words))
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
    else:
        convert(args[0], args[1], platform)


if __name__ == "__main__":
    main()
