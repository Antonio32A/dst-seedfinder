#!/usr/bin/env python3
"""Writes the textures the website's world map draws with to website/public/world-map/ (README.md).

usage: python3 map_textures.py [--catalog CATALOG] [--out DIR] [--manifest FILE]
"""
import argparse
import collections
import functools
import hashlib
import json
import math
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
MINIMAP_ATLASES = ["minimap/minimap_data1.xml", "minimap/minimap_data2.xml"]
NOISE_TEXTURE = "levels/textures/%s.tex"
PNG_COLOUR_TYPES = {3: 2, 4: 6}
SHEET_WIDTH = 2048
ICON_GUTTER = 32
CELL_ALIGN = 32
SHEET_MIPS = 6
HASH_LENGTH = 10

sys.path.insert(0, HERE)
import ktex  # noqa: E402


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def encode_png(pixels):
    """Rows are left unfiltered: decoded DXT blocks repeat a few colours, which deflate packs better that way."""
    height, width, channels = pixels.shape
    header = struct.pack(">IIBBBBB", width, height, 8, PNG_COLOUR_TYPES[channels], 0, 0, 0)
    rows = np.concatenate([np.zeros((height, 1), np.uint8), pixels.reshape(height, width * channels)], 1)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(rows.tobytes(), 9)) + png_chunk(b"IEND", b""))


def read_texture(game_dir, name, mip=0):
    with open(os.path.join(game_dir, "data", name), "rb") as f:
        return ktex.decode(f.read(), mip)


@functools.cache
def full_cell_tint(game_dir):
    edge = read_texture(game_dir, MAP_EDGE)
    height, width = edge.shape[:2]
    cell = ET.parse(os.path.join(game_dir, "data", MAP_EDGE_ATLAS)).find(".//Element[@name='01']")
    u1, u2, v1, v2 = (float(cell.get(key)) for key in ["u1", "u2", "v1", "v2"])
    return edge[round(v1 * height):round(v2 * height), round(u1 * width):round(u2 * width), :3].mean((0, 1))


def land_colour(game_dir, noise):
    """The game draws a tile layer with map_edge cell 01: the cell for a tile whose neighbours are all the same layer."""
    noise_mean = read_texture(game_dir, NOISE_TEXTURE % noise)[:, :, :3].mean((0, 1))
    return [round(channel) for channel in (full_cell_tint(game_dir) * noise_mean / 255).tolist()]


def minimap_elements(game_dir):
    """Element name -> (atlas texture, u1, u2, v1, v2). The first atlas to name an element wins, as in the game."""
    elements = {}
    for atlas in MINIMAP_ATLASES:
        root = ET.parse(os.path.join(game_dir, "data", atlas)).getroot()
        texture = os.path.join(os.path.dirname(atlas), root.find("Texture").get("filename"))
        for element in root.iter("Element"):
            uv = tuple(float(element.get(key)) for key in ["u1", "u2", "v1", "v2"])
            elements.setdefault(element.get("name"), (texture,) + uv)
    return elements


Icon = collections.namedtuple("Icon", "levels x y w h")


def aligned_span(low, high):
    """The CELL_ALIGN aligned span of texels around low..high, at least ICON_GUTTER texels wider on each side."""
    return (CELL_ALIGN * math.floor((low - ICON_GUTTER) / CELL_ALIGN), CELL_ALIGN * math.ceil((high + ICON_GUTTER) / CELL_ALIGN))


def read_icons(game_dir, names):
    """Name -> Icon: each element's cell of atlas texels at each of SHEET_MIPS mip levels, and its rect (x, y, w, h)
    inside level 0's cell.

    The cell is the rect plus ICON_GUTTER texels on every side, widened to CELL_ALIGN, so each level is the atlas' own
    mip (the game samples those, which are not a box filter of level 0) and a bilinear tap reaching ICON_GUTTER texels
    sees what the game sees. Texels stay premultiplied, as the atlas stores them. The atlas' rows run bottom first, so
    they are flipped to read top first like the PNG. Atlas rects sit on half texels: a 63 wide rect spans 64 texels.
    """
    elements = minimap_elements(game_dir)
    atlases = {texture: [read_texture(game_dir, texture, mip) for mip in range(SHEET_MIPS)]
               for texture in {elements[name][0] for name in names}}
    icons = {}
    for name in names:
        texture, u1, u2, v1, v2 = elements[name]
        height, width = atlases[texture][0].shape[:2]
        x0, x1, y0, y1 = u1 * width, u2 * width, v1 * height, v2 * height
        left, right = aligned_span(x0, x1)
        top, bottom = aligned_span(y0, y1)
        levels = []
        for mip, pixels in enumerate(atlases[texture]):
            t, b, l, r = top >> mip, bottom >> mip, left >> mip, right >> mip
            level_height, level_width = pixels.shape[:2]
            inside = pixels[max(t, 0):min(b, level_height), max(l, 0):min(r, level_width)]
            edges = [(max(-t, 0), max(b - level_height, 0)), (max(-l, 0), max(r - level_width, 0)), (0, 0)]
            levels.append(np.pad(inside, edges, mode="edge")[::-1])
        icons[name] = Icon(levels, round(x0 - left, 3), round(bottom - y1, 3), round(x1 - x0, 3), round(y1 - y0, 3))
    return icons


def pack_icons(icons):
    """Shelf-packs icons (name -> Icon) SHEET_WIDTH wide, each cell at a CELL_ALIGN aligned origin so that every sheet
    level holds the icons' own mip levels. Returns the sheet's levels and name -> {x, y, w, h}: each rect in level 0's
    texels, top row first."""
    origins, rects = {}, {}
    x = y = shelf_height = 0
    for name in sorted(icons, key=lambda name: (-icons[name].levels[0].shape[0], name)):
        icon = icons[name]
        height, width = icon.levels[0].shape[:2]
        if x + width > SHEET_WIDTH:
            x, y, shelf_height = 0, y + shelf_height, 0
        origins[name] = (x, y)
        rects[name] = {"x": x + icon.x, "y": y + icon.y, "w": icon.w, "h": icon.h}
        x, shelf_height = x + width, max(shelf_height, height)
    sheet_height = y + shelf_height
    sheet = [np.zeros((sheet_height >> mip, SHEET_WIDTH >> mip, 4), np.uint8) for mip in range(SHEET_MIPS)]
    for name, (x, y) in origins.items():
        for mip, level in enumerate(sheet):
            pixels = icons[name].levels[mip]
            level[y >> mip:(y >> mip) + pixels.shape[0], x >> mip:(x >> mip) + pixels.shape[1]] = pixels
    return sheet, rects


def stack_levels(levels):
    """One image holding a mip chain: level 0 on the left, the rest in a column to its right. Also returns each level's
    {x, y, width, height} in it."""
    width, height = levels[0].shape[1], levels[0].shape[0]
    strip = np.zeros((height, width + width // 2, 4), np.uint8)
    regions, column = [], 0
    for mip, level in enumerate(levels):
        x, top = (0, 0) if mip == 0 else (width, column)
        strip[top:top + level.shape[0], x:x + level.shape[1]] = level
        regions.append({"x": x, "y": top, "width": level.shape[1], "height": level.shape[0]})
        column += level.shape[0] if mip else 0
    return strip, regions


def write_map_textures(game_dir, noises, icon_names, out_dir):
    """Writes every texture as `<stem>.<content hash>.<extension>`, removes the other files in out_dir, and returns the
    manifest of the files written, relative to out_dir."""
    levels, rects = pack_icons(read_icons(game_dir, icon_names))
    sheet, regions = stack_levels(levels)
    images = {"noise/" + name: read_texture(game_dir, NOISE_TEXTURE % name)[:, :, :3] for name in noises}
    images.update(map_edge=read_texture(game_dir, MAP_EDGE), minimap_paper=read_texture(game_dir, MINIMAP_PAPER)[:, :, :3],
                  minimap_icons=sheet)
    payloads = {stem: (encode_png(pixels), "png") for stem, pixels in images.items()}
    payloads["minimap_icon_rects"] = (json.dumps({"width": levels[0].shape[1], "height": levels[0].shape[0], "icons": rects},
                                                 sort_keys=True).encode(), "json")
    files = {stem: "%s.%s.%s" % (stem, hashlib.sha256(data).hexdigest()[:HASH_LENGTH], extension)
             for stem, (data, extension) in payloads.items()}
    os.makedirs(os.path.join(out_dir, "noise"), exist_ok=True)
    for stem, (data, _) in payloads.items():
        with open(os.path.join(out_dir, files[stem]), "wb") as f:
            f.write(data)
    for directory, _, names in os.walk(out_dir):
        for name in names:
            if os.path.relpath(os.path.join(directory, name), out_dir) not in files.values():
                os.remove(os.path.join(directory, name))
    return {
        "noise": {name: files["noise/" + name] for name in noises},
        "mapEdge": files["map_edge"],
        "minimapPaper": files["minimap_paper"],
        "iconSheet": {"file": files["minimap_icons"], "rects": files["minimap_icon_rects"],
                      "width": levels[0].shape[1], "height": levels[0].shape[0], "levels": regions},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default=os.path.join(HERE, "catalog.json"))
    ap.add_argument("--out", default=os.path.join(ROOT, "website/public/world-map"))
    ap.add_argument("--manifest", default=os.path.join(HERE, "map_textures.json"))
    args = ap.parse_args()
    if not os.path.isdir(GAME_DIR):
        sys.exit("no game install at %s (set DST_GAME)" % GAME_DIR)
    with open(args.catalog) as f:
        catalog = json.load(f)
    noises = sorted({tile["minimap_noise"] for tile in catalog["tiles"] if tile.get("minimap_noise")})
    icon_names = sorted({prefab["icons"]["minimap"]["element"] for prefab in catalog["prefabs"] if "minimap" in prefab["icons"]})
    manifest = write_map_textures(GAME_DIR, noises, icon_names, args.out)
    with open(args.manifest, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    print("%s: %d noise textures, map_edge, minimap_paper, %d icons on a %dx%d sheet" % (
        args.out, len(noises), len(icon_names), manifest["iconSheet"]["width"], manifest["iconSheet"]["height"]))


if __name__ == "__main__":
    main()
