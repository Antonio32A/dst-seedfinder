#!/usr/bin/env python3
"""Writes the textures the website's world map draws with to website/public/world-map/ (README.md).

usage: python3 map_textures.py [--catalog CATALOG] [--out DIR]
"""
import argparse
import functools
import json
import os
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

import numpy as np

HERE = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
GAME_DIR = os.environ.get("DST_GAME", os.path.expanduser("~/.local/share/Steam/steamapps/common/Don't Starve Together"))
MAP_EDGE = "levels/tiles/map_edge.tex"
MAP_EDGE_ATLAS = "levels/tiles/map_edge.xml"
MINIMAP_PAPER = "images/minimap_paper.tex"
NOISE_TEXTURE = "levels/textures/%s.tex"
PNG_COLOUR_TYPES = {3: 2, 4: 6}

sys.path.insert(0, HERE)
import ktex  # noqa: E402


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def encode_png(pixels):
    """Rows are left unfiltered: decoded DXT blocks repeat a few colours, which deflate packs better unfiltered."""
    height, width, channels = pixels.shape
    header = struct.pack(">IIBBBBB", width, height, 8, PNG_COLOUR_TYPES[channels], 0, 0, 0)
    rows = np.concatenate([np.zeros((height, 1), np.uint8), pixels.reshape(height, width * channels)], 1)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(rows.tobytes(), 9)) + png_chunk(b"IEND", b""))


def read_texture(game_dir, name):
    with open(os.path.join(game_dir, "data", name), "rb") as f:
        return ktex.decode(f.read())


@functools.cache
def full_cell_tint(game_dir):
    edge = read_texture(game_dir, MAP_EDGE)
    height, width = edge.shape[:2]
    cell = ET.parse(os.path.join(game_dir, "data", MAP_EDGE_ATLAS)).find(".//Element[@name='01']")
    u1, u2, v1, v2 = (float(cell.get(key)) for key in ["u1", "u2", "v1", "v2"])
    return edge[round(v1 * height):round(v2 * height), round(u1 * width):round(u2 * width), :3].mean((0, 1))


def land_colour(game_dir, noise):
    """Map_edge cell 01 is the one a layer draws on its own tiles."""
    noise_mean = read_texture(game_dir, NOISE_TEXTURE % noise)[:, :, :3].mean((0, 1))
    return [round(channel) for channel in (full_cell_tint(game_dir) * noise_mean / 255).tolist()]


def write_map_textures(game_dir, noises, out_dir):
    os.makedirs(os.path.join(out_dir, "noise"), exist_ok=True)
    images = {"noise/%s.png" % name: read_texture(game_dir, NOISE_TEXTURE % name)[:, :, :3] for name in noises}
    images["map_edge.png"] = read_texture(game_dir, MAP_EDGE)
    images["minimap_paper.png"] = read_texture(game_dir, MINIMAP_PAPER)[:, :, :3]
    for path, pixels in images.items():
        with open(os.path.join(out_dir, path), "wb") as f:
            f.write(encode_png(pixels))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default=os.path.join(HERE, "catalog.json"))
    ap.add_argument("--out", default=os.path.join(ROOT, "website/public/world-map"))
    args = ap.parse_args()
    if not os.path.isdir(GAME_DIR):
        sys.exit("no game install at %s (set DST_GAME)" % GAME_DIR)
    with open(args.catalog) as f:
        noises = sorted({tile["minimap_noise"] for tile in json.load(f)["tiles"] if tile.get("minimap_noise")})
    write_map_textures(GAME_DIR, noises, args.out)
    print("%s: %d noise textures, map_edge, minimap_paper" % (args.out, len(noises)))


if __name__ == "__main__":
    main()
