#!/usr/bin/env python3
"""Reads world dumps (.dstw, format 3, docs/world-dump.md), as a library or from the command line.

library: from dstw import World, read_dstw
         World(path)      every section of the dump, positions in world units and in exact hundredths
         read_dstw(path)  seed, w, h, entities and the tiles as an (h, w) numpy array

usage: dstw.py info [--top N] FILE   header, sections, tiles, entities, links, layouts, roads, topology, land components
       dstw.py diff A B              tile and per-prefab differences (exact, in hundredths) and whether the links,
                                     layouts, roads and topology are equal
       dstw.py graph FILE            topology nodes grouped by task, with their extents in tile coordinates
       dstw.py ents FILE PREFAB...   the positions and tiles of the given prefabs
"""
import argparse
import struct
import sys
from collections import Counter, deque
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from world import TILE_SCALE, is_land_tile, tile_coordinate  # noqa: E402

VERSION = 3
HEADER_BYTES = 36
PLATFORMS = {0: "unknown", 1: "windows", 2: "linux"}
SHARDS = {0: "forest", 1: "caves"}
LAYOUT_SOURCES = {0: "room", 1: "task set piece", 2: "start", 3: "map tag", 4: "ocean prefill", 5: "ocean room",
                  6: "maze"}
NEIGHBOURS = ((1, 0), (-1, 0), (0, 1), (0, -1))
SECTION_SUMMARIES = {
    "layouts": lambda world: f"layouts {len(world.layouts)}: " + str(Counter(
        LAYOUT_SOURCES.get(layout["source"], layout["source"]) for layout in world.layouts)),
    "roads": lambda world: f"roads {len(world.roads)} ({sum(len(points) for _, points in world.roads)} points)",
    "nodes": lambda world: f"topology {len(world.nodes)} nodes {len(world.edges)} edges",
}


class Cursor:
    """Reads the little-endian words and strings of one section payload, advancing past each."""

    def __init__(self, buf, offset):
        self.buf, self.offset = buf, offset

    def unpack(self, kind, count, size=4):
        values = struct.unpack_from(f"<{count}{kind}", self.buf, self.offset)
        self.offset += size * count
        return values

    def u32(self):
        return self.unpack("I", 1)[0]

    def u32_pairs(self, count):
        flat = self.unpack("I", 2 * count)
        return list(zip(flat[0::2], flat[1::2]))

    def i32_pairs(self, count):
        flat = self.unpack("i", 2 * count)
        return list(zip(flat[0::2], flat[1::2]))

    def string(self):
        size = self.u32()
        text = self.buf[self.offset:self.offset + size].decode()
        self.offset += size + -size % 4
        return text


class World:
    """One parsed dump. Entity positions are in world units in `entities` and in exact hundredths in `hundredths`;
    `layouts`, `roads`, `nodes` and `edges` are None when the dump has no such section."""

    def __init__(self, path):
        buf = Path(path).read_bytes()
        if buf[:4] != b"DSTW":
            raise ValueError(f"{path}: not a world dump")
        self.version, = struct.unpack_from("<I", buf, 4)
        if self.version != VERSION:
            raise ValueError(f"{path}: dump format {self.version}, this reader handles {VERSION}; regenerate it")
        self.seed, self.status, self.platform, self.shard = struct.unpack_from("<4I", buf, 8)
        self.build = self.width = self.height = 0
        self.tile_names, self.tiles, self.hundredths, self.prefabs = {}, (), {}, []
        self.wormhole_links, self.pillar_links = [], []
        self.layouts = self.roads = self.nodes = self.edges = None
        self.sections = {}
        if self.status:
            self.build, self.width, self.height = struct.unpack_from("<3I", buf, 24)
        offset = HEADER_BYTES if self.status else len(buf)
        while offset < len(buf):
            tag = buf[offset:offset + 4].decode()
            self.sections[tag], = struct.unpack_from("<I", buf, offset + 4)
            self.SECTION_READERS.get(tag, World._skip)(self, Cursor(buf, offset + 8))
            offset += 8 + self.sections[tag]
        self.entities = {prefab: [(xk / 100, zk / 100) for xk, zk in points]
                         for prefab, points in self.hundredths.items()}

    def _skip(self, cursor):
        pass

    def _read_tile_names(self, cursor):
        for _ in range(cursor.u32()):
            tile = cursor.u32()
            self.tile_names[tile] = cursor.string()

    def _read_tiles(self, cursor):
        self.tiles = cursor.unpack("H", self.width * self.height, 2)

    def _read_entities(self, cursor):
        for _ in range(cursor.u32()):
            prefab = cursor.string()
            self.prefabs.append(prefab)
            self.hundredths[prefab] = cursor.i32_pairs(cursor.u32())

    def _read_wormhole_links(self, cursor):
        self.wormhole_links = cursor.u32_pairs(cursor.u32())

    def _read_pillar_links(self, cursor):
        for _ in range(cursor.u32()):
            entry, entry_index, leave, leave_index = cursor.unpack("I", 4)
            self.pillar_links.append(((self.prefabs[entry], entry_index), (self.prefabs[leave], leave_index)))

    def _read_layouts(self, cursor):
        self.layouts = []
        for _ in range(cursor.u32()):
            name = cursor.string()
            source, transform = cursor.unpack("I", 2)
            xk, zk, *bounds = cursor.unpack("i", 6)
            members = [(self.prefabs[prefab], index) for prefab, index in cursor.u32_pairs(cursor.u32())]
            self.layouts.append(dict(name=name, source=source, transform=transform, x=xk / 100, z=zk / 100,
                                     bounds=tuple(k / 100 for k in bounds), members=members))

    def _read_roads(self, cursor):
        self.roads = []
        for _ in range(cursor.u32()):
            weight, count = cursor.unpack("I", 2)
            self.roads.append((weight, cursor.i32_pairs(count)))

    def _read_graph(self, cursor):
        self.nodes = []
        for _ in range(cursor.u32()):
            node_id = cursor.string()
            node_type = cursor.u32()
            xk, zk = cursor.unpack("i", 2)
            self.nodes.append(dict(id=node_id, type=node_type, x=xk / 100, z=zk / 100))
        self.edges = cursor.u32_pairs(cursor.u32())

    SECTION_READERS = {"TNAM": _read_tile_names, "TILE": _read_tiles, "ENTS": _read_entities,
                       "WORM": _read_wormhole_links, "PILL": _read_pillar_links, "SETP": _read_layouts,
                       "ROAD": _read_roads, "GRPH": _read_graph}

    def tile(self, tx, ty):
        """The tile id at column tx, row ty."""
        return self.tiles[ty * self.width + tx]

    def name(self, tx, ty):
        """The name of the tile at column tx, row ty (its id as text when TNAM does not name it)."""
        return self.tile_names.get(self.tile(tx, ty), str(self.tile(tx, ty)))

    def land(self, tx, ty):
        """Whether (tx, ty) is inside the map and a land tile."""
        return 0 <= tx < self.width and 0 <= ty < self.height and is_land_tile(self.tile(tx, ty))

    def tile_of(self, x, z):
        """The tile of world point (x, z), in float32 like the game's Map:GetTileCoordsAtPoint."""
        return tile_coordinate(x, self.width), tile_coordinate(z, self.height)

    def centre(self, tx, ty):
        """The world position of the centre of tile (tx, ty)."""
        return (tx - self.width / 2) * TILE_SCALE, (ty - self.height / 2) * TILE_SCALE

    def components(self):
        """4-connected land components: (component id per tile, -1 off land; size per component)."""
        component = [-1] * (self.width * self.height)
        sizes = []
        for start in range(self.width * self.height):
            if component[start] >= 0 or not is_land_tile(self.tiles[start]):
                continue
            component[start] = len(sizes)
            queue, size = deque([start]), 0
            while queue:
                ty, tx = divmod(queue.popleft(), self.width)
                size += 1
                for nx, ny in ((tx + dx, ty + dy) for dx, dy in NEIGHBOURS):
                    if self.land(nx, ny) and component[ny * self.width + nx] < 0:
                        component[ny * self.width + nx] = len(sizes)
                        queue.append(ny * self.width + nx)
            sizes.append(size)
        return component, sizes


def read_dstw(path):
    """The dump as a dict: seed, w, h, ents (prefab -> positions in world units) and tiles as an (h, w) array (None
    when the world generation gave up)."""
    world = World(path)
    tiles = np.array(world.tiles, np.uint16).reshape(world.height, world.width) if world.tiles else None
    return dict(seed=world.seed, w=world.width, h=world.height, ents=world.entities, tiles=tiles)


def header(world):
    return (f"seed {world.seed}  status {world.status}  platform {PLATFORMS.get(world.platform, world.platform)}  "
            f"shard {SHARDS.get(world.shard, world.shard)}  build {world.build}  size {world.width}x{world.height}")


def info(args):
    world = World(args.file)
    print(header(world))
    if not world.status:
        return
    print("sections", " ".join(f"{tag}:{length}" for tag, length in world.sections.items()))
    tiles = Counter(world.tile_names.get(tile, str(tile)) for tile in world.tiles)
    print("tiles", ", ".join(f"{name} {count}" for name, count in tiles.most_common(args.top)))
    print(f"entities {sum(map(len, world.hundredths.values()))} in {len(world.hundredths)} prefabs")
    for prefab, points in sorted(world.hundredths.items(), key=lambda item: -len(item[1]))[:args.top]:
        print(f"  {prefab:<32} {len(points)}")
    print(f"wormhole links {len(world.wormhole_links)}  pillar links {len(world.pillar_links)}")
    for attribute, summary in SECTION_SUMMARIES.items():
        if getattr(world, attribute) is not None:
            print(summary(world))
    _, sizes = world.components()
    print(f"land components {len(sizes)}, largest {sorted(sizes, reverse=True)[:8]}")


def diff_tiles(a, b):
    if (a.width, a.height) != (b.width, b.height):
        print("sizes differ, tiles not compared")
        return
    bad = [i for i, (x, y) in enumerate(zip(a.tiles, b.tiles)) if a.tile_names.get(x) != b.tile_names.get(y)]
    print("tile diffs", len(bad))
    if not bad:
        return
    xs, ys = [i % a.width for i in bad], [i // a.width for i in bad]
    print(f"  bbox x {min(xs)}..{max(xs)}  y {min(ys)}..{max(ys)}")
    pairs = Counter((a.tile_names.get(a.tiles[i]), b.tile_names.get(b.tiles[i])) for i in bad)
    print("  top (A, B):", pairs.most_common(8))


def diff_entities(a, b):
    same = 0
    for prefab in sorted(set(a.hundredths) | set(b.hundredths), key=str.encode):
        pa, pb = a.hundredths.get(prefab, []), b.hundredths.get(prefab, [])
        if pa == pb:
            same += 1
            continue
        ca, cb = Counter(pa), Counter(pb)
        order = "  same set, other order" if ca == cb else ""
        print(f"  {prefab:<32} A {len(pa):5d}  B {len(pb):5d}  only-A {sum((ca - cb).values()):5d}  "
              f"only-B {sum((cb - ca).values()):5d}{order}")
    print("prefabs identical", same)


def topology(world):
    return None if world.nodes is None else ([tuple(node.values()) for node in world.nodes], world.edges)


def diff(args):
    a, b = World(args.a), World(args.b)
    print("A", header(a))
    print("B", header(b))
    if not (a.status and b.status):
        return
    diff_tiles(a, b)
    diff_entities(a, b)
    verdicts = {True: "equal", False: "DIFFER"}
    for label, part in (("wormholes", lambda w: w.wormhole_links), ("pillars", lambda w: w.pillar_links),
                        ("layouts", lambda w: w.layouts), ("roads", lambda w: w.roads), ("topology", topology)):
        pa, pb = part(a), part(b)
        print(label, verdicts[pa == pb] if (pa is None) == (pb is None) else "missing in one")


def graph(args):
    world = World(args.file)
    if world.nodes is None:
        sys.exit(f"{args.file} has no GRPH section")
    tasks = {}
    for node in world.nodes:
        tx, tz = node["x"] / TILE_SCALE + world.width / 2, node["z"] / TILE_SCALE + world.height / 2
        box = tasks.setdefault(node["id"].split(":")[0], [tx, tx, tz, tz, 0])
        box[:] = [min(box[0], tx), max(box[1], tx), min(box[2], tz), max(box[3], tz), box[4] + 1]
    print(f"size {world.width}x{world.height}  nodes {len(world.nodes)}  edges {len(world.edges)}")
    for task, (x0, x1, z0, z1, count) in sorted(tasks.items(), key=lambda item: item[1][0]):
        print(f"{task:<40} n={count:3d}  x {x0:6.0f}..{x1:6.0f}  z {z0:6.0f}..{z1:6.0f}")


def entities(args):
    world = World(args.file)
    for prefab in args.prefabs:
        for index, (x, z) in enumerate(world.entities.get(prefab, [])):
            print(f"{prefab} {index} {x:.2f} {z:.2f} tile {world.tile_of(x, z)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    summary = commands.add_parser("info", help="summarise a dump")
    summary.add_argument("file")
    summary.add_argument("--top", type=int, default=15, help="how many tiles and prefabs to list")
    summary.set_defaults(run=info)
    comparison = commands.add_parser("diff", help="compare two dumps of the same world")
    comparison.add_argument("a")
    comparison.add_argument("b")
    comparison.set_defaults(run=diff)
    nodes = commands.add_parser("graph", help="topology nodes per task")
    nodes.add_argument("file")
    nodes.set_defaults(run=graph)
    positions = commands.add_parser("ents", help="list the positions of prefabs")
    positions.add_argument("file")
    positions.add_argument("prefabs", nargs="+")
    positions.set_defaults(run=entities)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
