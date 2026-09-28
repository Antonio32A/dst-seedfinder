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
HASH_LENGTH = 10

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


def minimap_elements(game_dir):
    """Element name -> (atlas texture, u1, u2, v1, v2) of the atlases the game loads for the minimap: data1, then data2."""
    elements = {}
    for atlas in MINIMAP_ATLASES:
        root = ET.parse(os.path.join(game_dir, "data", atlas)).getroot()
        texture = os.path.join(os.path.dirname(atlas), root.find("Texture").get("filename"))
        for element in root.iter("Element"):
            uv = tuple(float(element.get(key)) for key in ["u1", "u2", "v1", "v2"])
            elements.setdefault(element.get("name"), (texture,) + uv)
    return elements


Icon = collections.namedtuple("Icon", "pixels x y w h")


def read_icons(game_dir, names):
    """Name -> Icon: the texels an element's UV rect touches, premultiplied as the atlas stores them, and the rect
    itself (x, y, w, h) inside them. The atlas edges sit on half texels, so a 63 wide rect spans 64 texels."""
    elements = minimap_elements(game_dir)
    atlases = {texture: read_texture(game_dir, texture) for texture in {elements[name][0] for name in names}}
    icons = {}
    for name in names:
        texture, u1, u2, v1, v2 = elements[name]
        height, width = atlases[texture].shape[:2]
        x0, x1, y0, y1 = u1 * width, u2 * width, v1 * height, v2 * height
        left, top = math.floor(x0), math.floor(y0)
        pixels = atlases[texture][top:math.ceil(y1), left:math.ceil(x1)]
        icons[name] = Icon(pixels, round(x0 - left, 3), round(y0 - top, 3), round(x1 - x0, 3), round(y1 - y0, 3))
    return icons


def pack_icons(icons):
    """Shelf-packs icons (name -> Icon) into a sheet SHEET_WIDTH wide. Each icon gets at least ICON_GUTTER texels of its own
    edge texels on every side (what clamping to the edge samples), filling a cell aligned to CELL_ALIGN, so sampling down to
    mip 4 never blends neighbours. Returns the sheet and name -> {x, y, w, h}: each icon's UV rect in sheet texels
    (stored rows, so u = x / width and v = y / height)."""
    cells, sizes = {}, {}
    for name, icon in icons.items():
        height, width = (-(-(side + 2 * ICON_GUTTER) // CELL_ALIGN) * CELL_ALIGN for side in icon.pixels.shape[:2])
        sizes[name] = (height, width)
        cells[name] = np.pad(icon.pixels, [(ICON_GUTTER, height - icon.pixels.shape[0] - ICON_GUTTER),
                                           (ICON_GUTTER, width - icon.pixels.shape[1] - ICON_GUTTER), (0, 0)], mode="edge")
    origins, rects = {}, {}
    x = y = shelf_height = 0
    for name in sorted(cells, key=lambda name: (-sizes[name][0], name)):
        height, width = sizes[name]
        if x + width > SHEET_WIDTH:
            x, y, shelf_height = 0, y + shelf_height, 0
        origins[name] = (x, y)
        icon = icons[name]
        rects[name] = {"x": x + ICON_GUTTER + icon.x, "y": y + ICON_GUTTER + icon.y, "w": icon.w, "h": icon.h}
        x, shelf_height = x + width, max(shelf_height, height)
    sheet = np.zeros((y + shelf_height, SHEET_WIDTH, 4), np.uint8)
    for name, (x, y) in origins.items():
        sheet[y:y + cells[name].shape[0], x:x + cells[name].shape[1]] = cells[name]
    return sheet, rects


def write_map_textures(game_dir, noises, icon_names, out_dir):
    """Writes every texture as `<stem>.<content hash>.<extension>` and removes the files it didn't write. Returns the
    manifest: the file each texture went to, relative to out_dir."""
    sheet, rects = pack_icons(read_icons(game_dir, icon_names))
    images = {"noise/" + name: read_texture(game_dir, NOISE_TEXTURE % name)[:, :, :3] for name in noises}
    images.update(map_edge=read_texture(game_dir, MAP_EDGE), minimap_paper=read_texture(game_dir, MINIMAP_PAPER)[:, :, :3],
                  minimap_icons=sheet)
    payloads = {stem: (encode_png(pixels), "png") for stem, pixels in images.items()}
    payloads["minimap_icon_rects"] = (json.dumps({"width": sheet.shape[1], "height": sheet.shape[0], "icons": rects},
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
                      "width": sheet.shape[1], "height": sheet.shape[0]},
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
