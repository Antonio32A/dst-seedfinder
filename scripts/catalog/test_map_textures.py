import hashlib
import json
import os
import struct
import tempfile
import unittest
import zlib

import numpy as np

from map_textures import (CELL_ALIGN, ICON_GUTTER, MAP_EDGE, MAP_EDGE_ATLAS, MINIMAP_PAPER, NOISE_TEXTURE, SHEET_MIPS, SHEET_WIDTH,
                          Icon, encode_png, land_colour, pack_icons, read_icons, stack_levels, write_map_textures)
from test_ktex import RGB, RGBA, ktex

CHANNELS = {0: 1, 2: 3, 6: 4}


def paeth(left, up, up_left):
    estimate = left + up - up_left
    distances = [abs(estimate - left), abs(estimate - up), abs(estimate - up_left)]
    return [left, up, up_left][distances.index(min(distances))]


def unfilter(kind, row, previous, channels):
    out = bytearray(len(row))
    for i, value in enumerate(row):
        left = out[i - channels] if i >= channels else 0
        up = previous[i]
        up_left = previous[i - channels] if i >= channels else 0
        predictor = [0, left, up, (left + up) // 2, paeth(left, up, up_left)][kind]
        out[i] = (value + predictor) & 0xFF
    return bytes(out)


def read_png(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    chunks, offset = {}, 8
    while offset < len(data):
        length, = struct.unpack_from(">I", data, offset)
        kind = data[offset + 4:offset + 8]
        chunks[kind] = chunks.get(kind, b"") + data[offset + 8:offset + 8 + length]
        offset += 12 + length
    width, height, depth, colour_type = struct.unpack_from(">IIBB", chunks[b"IHDR"])
    assert depth == 8
    channels = CHANNELS[colour_type]
    stride = width * channels
    raw = zlib.decompress(chunks[b"IDAT"])
    rows, previous = [], bytes(stride)
    for y in range(height):
        line = raw[y * (stride + 1):(y + 1) * (stride + 1)]
        previous = unfilter(line[0], line[1:], previous, channels)
        rows.append(previous)
    return np.frombuffer(b"".join(rows), np.uint8).reshape(height, width, channels)


def noisy_pixels(height, width, channels):
    return np.random.default_rng(height * width * channels).integers(0, 256, (height, width, channels), np.uint8)


class EncodePng(unittest.TestCase):
    def test_rgb_pixels_decode_back_to_themselves(self):
        pixels = noisy_pixels(5, 7, 3)
        np.testing.assert_array_equal(read_png(encode_png(pixels)), pixels)

    def test_rgba_pixels_with_smooth_flat_and_noisy_rows_decode_back_to_themselves(self):
        ramp = np.add.outer(np.arange(16), np.arange(16))[:, :, None] * [3, 5, 7, 11] % 256
        pixels = np.concatenate([ramp, np.zeros((4, 16, 4)), noisy_pixels(4, 16, 4)]).astype(np.uint8)
        np.testing.assert_array_equal(read_png(encode_png(pixels)), pixels)


def write_texture(game_dir, name, pixel_format, mips):
    path = os.path.join(game_dir, "data", name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(ktex(pixel_format, [(w, h, pixels.tobytes()) for w, h, pixels in mips]))


def noisy_mips(size):
    return [noisy_pixels(size >> mip, size >> mip, 4) for mip in range(SHEET_MIPS)]


def write_atlas(game_dir, atlas, texture, size, elements, mips):
    """elements: name -> (u1, u2, v1, v2) in texels."""
    write_texture(game_dir, "minimap/" + texture, RGBA, [(size >> mip, size >> mip, pixels) for mip, pixels in enumerate(mips)])
    rows = "".join('<Element name="%s" u1="%r" u2="%r" v1="%r" v2="%r" />' % (name, x0 / size, x1 / size, y0 / size, y1 / size)
                   for name, (x0, x1, y0, y1) in elements.items())
    with open(os.path.join(game_dir, "data", atlas), "w") as f:
        f.write('<Atlas><Texture filename="%s" />\n<Elements>%s</Elements></Atlas>' % (texture, rows))


def read_output(out_dir, name):
    with open(os.path.join(out_dir, name), "rb") as f:
        return read_png(f.read())


def solid(height, width, value):
    return np.full((height, width, 4), value, np.uint8)


def atlas_region(mips, mip, top, bottom, left, right):
    """The atlas' own `mip` level over the rows top..bottom and columns left..right of level 0, edge texels repeated
    outside the atlas, rows flipped to read top first."""
    level = mips[mip]
    pad = [(max(-top >> mip, 0), max((bottom >> mip) - level.shape[0], 0)), (max(-left >> mip, 0), max((right >> mip) - level.shape[1], 0)), (0, 0)]
    inside = level[max(top >> mip, 0):bottom >> mip, max(left >> mip, 0):right >> mip]
    return np.pad(inside, pad, mode="edge")[::-1]


class WriteMapTextures(unittest.TestCase):
    def setUp(self):
        self.game_dir = self.enterContext(tempfile.TemporaryDirectory())
        self.out_dir = self.enterContext(tempfile.TemporaryDirectory())
        self.grass = noisy_pixels(4, 2, 3)
        self.edge = noisy_pixels(2, 4, 4)
        self.paper = noisy_pixels(2, 2, 3)
        self.atlas1 = noisy_mips(64)
        self.atlas2 = [pixels ^ 3 for pixels in noisy_mips(64)]
        write_texture(self.game_dir, NOISE_TEXTURE % "grass", RGB, [(2, 4, self.grass), (1, 2, noisy_pixels(2, 1, 3))])
        write_texture(self.game_dir, MAP_EDGE, RGBA, [(4, 2, self.edge)])
        write_texture(self.game_dir, MINIMAP_PAPER, RGB, [(2, 2, self.paper)])
        write_atlas(self.game_dir, "minimap/minimap_data1.xml", "atlas1.tex", 64, {"a.png": (4.5, 11.5, 20.5, 27.5)}, self.atlas1)
        write_atlas(self.game_dir, "minimap/minimap_data2.xml", "atlas2.tex", 64,
                    {"b.png": (0, 16, 40, 48), "a.png": (0, 4, 0, 4)}, self.atlas2)

    def write(self, noises=("grass",), icons=("a.png", "b.png")):
        return write_map_textures(self.game_dir, list(noises), list(icons), self.out_dir)

    def test_writes_each_noise_texture_as_its_full_size_rgb_mip(self):
        manifest = self.write()
        np.testing.assert_array_equal(read_output(self.out_dir, manifest["noise"]["grass"]), self.grass)

    def test_writes_map_edge_rgba_as_stored_and_the_paper_as_rgb(self):
        manifest = self.write([])
        np.testing.assert_array_equal(read_output(self.out_dir, manifest["mapEdge"]), self.edge)
        np.testing.assert_array_equal(read_output(self.out_dir, manifest["minimapPaper"]), self.paper)

    def test_names_every_file_after_the_hash_of_its_contents(self):
        manifest = self.write()
        files = [manifest["mapEdge"], manifest["minimapPaper"], manifest["noise"]["grass"], manifest["iconSheet"]["file"],
                 manifest["iconSheet"]["rects"]]
        for name in files:
            with open(os.path.join(self.out_dir, name), "rb") as f:
                digest = hashlib.sha256(f.read()).hexdigest()[:10]
            self.assertRegex(name, r"^(noise/)?[a-z_]+\.%s\.(png|json)$" % digest)

    def test_a_texture_changes_name_only_when_its_pixels_change(self):
        before = self.write()
        self.assertEqual(self.write(), before)
        write_texture(self.game_dir, MINIMAP_PAPER, RGB, [(2, 2, noisy_pixels(2, 2, 3) ^ 1)])
        after = self.write()
        self.assertNotEqual(after["minimapPaper"], before["minimapPaper"])
        self.assertEqual(after["mapEdge"], before["mapEdge"])

    def test_removes_files_it_did_not_write(self):
        stale = os.path.join(self.out_dir, "noise", "gone.png")
        os.makedirs(os.path.dirname(stale))
        open(stale, "w").close()
        self.write()
        self.assertFalse(os.path.exists(stale))

    def test_reads_the_minimap_from_data1_then_data2_and_ignores_the_legacy_data0(self):
        write_atlas(self.game_dir, "minimap/minimap_data.xml", "atlas0.tex", 64, {"a.png": (32, 40, 32, 40)}, noisy_mips(64))
        icon = read_icons(self.game_dir, ["a.png"])["a.png"]
        np.testing.assert_array_equal(icon.levels[0], atlas_region(self.atlas1, 0, -32, 64, -32, 64))

    def test_an_icon_keeps_the_atlas_own_mips_of_its_gutter_widened_region_and_its_own_rect(self):
        icon = read_icons(self.game_dir, ["a.png", "b.png"])["a.png"]
        self.assertEqual(len(icon.levels), SHEET_MIPS)
        for mip, level in enumerate(icon.levels):
            self.assertEqual(level.shape, (96 >> mip, 96 >> mip, 4))
            np.testing.assert_array_equal(level, atlas_region(self.atlas1, mip, -32, 64, -32, 64))
        self.assertEqual((icon.x, icon.y, icon.w, icon.h), (36.5, 36.5, 7, 7))

    def test_a_region_past_the_atlas_edge_repeats_the_edge_texels_at_every_level(self):
        icon = read_icons(self.game_dir, ["b.png"])["b.png"]
        self.assertEqual(icon.levels[0].shape, (96, 96, 4))
        for mip, level in enumerate(icon.levels):
            np.testing.assert_array_equal(level, atlas_region(self.atlas2, mip, 0, 96, -32, 64))

    def test_the_sheet_holds_each_icon_top_row_first_at_its_rect_in_every_mip_level(self):
        manifest = self.write()
        strip = read_output(self.out_dir, manifest["iconSheet"]["file"])
        with open(os.path.join(self.out_dir, manifest["iconSheet"]["rects"])) as f:
            described = json.load(f)
        levels = [strip[r["y"]:r["y"] + r["height"], r["x"]:r["x"] + r["width"]] for r in manifest["iconSheet"]["levels"]]
        self.assertEqual((described["width"], described["height"]), levels[0].shape[1::-1])
        self.assertEqual((manifest["iconSheet"]["width"], manifest["iconSheet"]["height"]), levels[0].shape[1::-1])
        self.assertEqual([level.shape[:2] for level in levels], [(levels[0].shape[0] >> mip, SHEET_WIDTH >> mip) for mip in range(SHEET_MIPS)])
        rect = described["icons"]["b.png"]
        self.assertEqual((rect["w"], rect["h"]), (16, 8))
        for mip in range(4):
            x, y = int(rect["x"]) >> mip, int(rect["y"]) >> mip
            np.testing.assert_array_equal(levels[mip][y:y + (8 >> mip), x:x + (16 >> mip)], self.atlas2[mip][40 >> mip:48 >> mip, 0:16 >> mip][::-1])


class PackIcons(unittest.TestCase):
    SIZES = {"a": (64, 64), "b": (128, 128), "c": (64, 96), "d": (64, 64), "e": (256, 256)}

    def icons(self):
        return {name: Icon([solid(h >> mip, w >> mip, 10 + 40 * i + mip) for mip in range(SHEET_MIPS)], 0.5 + i, 0.25 * i, w / 2, h / 2)
                for i, (name, (h, w)) in enumerate(self.SIZES.items())}

    def test_each_icon_region_sits_at_a_cell_aligned_origin_in_every_mip_level(self):
        icons = self.icons()
        sheet, rects = pack_icons(icons)
        for name, icon in icons.items():
            rect = rects[name]
            self.assertEqual((rect["w"], rect["h"]), (icon.w, icon.h))
            x, y = int(rect["x"] - icon.x), int(rect["y"] - icon.y)
            self.assertEqual((x % CELL_ALIGN, y % CELL_ALIGN), (0, 0))
            for mip, level in enumerate(sheet):
                pixels = icon.levels[mip]
                np.testing.assert_array_equal(level[y >> mip:(y >> mip) + pixels.shape[0], x >> mip:(x >> mip) + pixels.shape[1]], pixels)

    def test_the_rect_offset_inside_the_region_carries_into_the_sheet_rect(self):
        _, rects = pack_icons({"a": Icon([solid(64 >> mip, 64 >> mip, 1) for mip in range(SHEET_MIPS)], 36.5, 33.25, 7, 7.5)})
        self.assertEqual(rects["a"], {"x": 36.5, "y": 33.25, "w": 7, "h": 7.5})

    def test_the_sheet_is_as_wide_as_its_constant_and_each_level_halves_the_one_before(self):
        sheet, _ = pack_icons(self.icons())
        self.assertEqual(len(sheet), SHEET_MIPS)
        self.assertEqual(sheet[0].shape[1], SHEET_WIDTH)
        self.assertEqual(sheet[0].shape[0] % CELL_ALIGN, 0)
        self.assertGreater(sheet[0].shape[0], 0)
        for mip, level in enumerate(sheet):
            self.assertEqual(level.shape[:2], (sheet[0].shape[0] >> mip, SHEET_WIDTH >> mip))


class StackLevels(unittest.TestCase):
    def test_puts_level_0_on_the_left_and_the_other_levels_in_a_column_to_its_right(self):
        levels = [noisy_pixels(64 >> mip, 128 >> mip, 4) for mip in range(4)]
        strip, regions = stack_levels(levels)
        self.assertEqual(strip.shape, (64, 192, 4))
        self.assertEqual(regions, [{"x": 0, "y": 0, "width": 128, "height": 64}, {"x": 128, "y": 0, "width": 64, "height": 32},
                                   {"x": 128, "y": 32, "width": 32, "height": 16}, {"x": 128, "y": 48, "width": 16, "height": 8}])
        for level, region in zip(levels, regions):
            np.testing.assert_array_equal(strip[region["y"]:region["y"] + region["height"], region["x"]:region["x"] + region["width"]], level)


class LandColour(unittest.TestCase):
    def test_is_the_mean_of_map_edge_cell_01_times_the_mean_noise(self):
        game_dir = self.enterContext(tempfile.TemporaryDirectory())
        edge = np.zeros((4, 4, 4), np.uint8)
        edge[2:, 2:] = [200, 100, 50, 255]
        write_texture(game_dir, MAP_EDGE, RGBA, [(4, 4, edge)])
        with open(os.path.join(game_dir, "data", MAP_EDGE_ATLAS), "w") as f:
            f.write('<Atlas><Elements><Element name="02" u1="0" u2="0.5" v1="0" v2="0.5" />'
                    '<Element name="01" u1="0.5" u2="1" v1="0.5" v2="1" /></Elements></Atlas>')
        noise = np.array([[[255, 128, 0], [255, 0, 0]]], np.uint8)
        write_texture(game_dir, NOISE_TEXTURE % "grass", RGB, [(2, 1, noise)])
        self.assertEqual(land_colour(game_dir, "grass"), [200, 25, 0])


if __name__ == "__main__":
    unittest.main()
