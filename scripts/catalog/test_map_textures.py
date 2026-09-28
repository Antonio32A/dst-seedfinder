import hashlib
import json
import os
import struct
import tempfile
import unittest
import zlib

import numpy as np

from map_textures import (CELL_ALIGN, ICON_GUTTER, MAP_EDGE, MAP_EDGE_ATLAS, MINIMAP_PAPER, NOISE_TEXTURE, SHEET_WIDTH, Icon,
                          encode_png, land_colour, pack_icons, read_icons, write_map_textures)
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


def write_atlas(game_dir, atlas, texture, size, elements, pixels):
    """elements: name -> (u1, u2, v1, v2) in texels."""
    write_texture(game_dir, "minimap/" + texture, RGBA, [(size, size, pixels)])
    rows = "".join('<Element name="%s" u1="%r" u2="%r" v1="%r" v2="%r" />' % (name, x0 / size, x1 / size, y0 / size, y1 / size)
                   for name, (x0, x1, y0, y1) in elements.items())
    with open(os.path.join(game_dir, "data", atlas), "w") as f:
        f.write('<Atlas><Texture filename="%s" />\n<Elements>%s</Elements></Atlas>' % (texture, rows))


def read_output(out_dir, name):
    with open(os.path.join(out_dir, name), "rb") as f:
        return read_png(f.read())


def solid(height, width, value):
    return np.full((height, width, 4), value, np.uint8)


def mip(pixels, level):
    step = 2 ** level
    height, width = pixels.shape[:2]
    return pixels.reshape(height // step, step, width // step, step, -1).astype(float).mean((1, 3))


class WriteMapTextures(unittest.TestCase):
    def setUp(self):
        self.game_dir = self.enterContext(tempfile.TemporaryDirectory())
        self.out_dir = self.enterContext(tempfile.TemporaryDirectory())
        self.grass = noisy_pixels(4, 2, 3)
        self.edge = noisy_pixels(2, 4, 4)
        self.paper = noisy_pixels(2, 2, 3)
        self.atlas1 = noisy_pixels(64, 64, 4)
        self.atlas2 = noisy_pixels(64, 64, 4)
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
        write_atlas(self.game_dir, "minimap/minimap_data.xml", "atlas0.tex", 64, {"a.png": (32, 40, 32, 40)}, noisy_pixels(64, 64, 4))
        icons = read_icons(self.game_dir, ["a.png"])
        np.testing.assert_array_equal(icons["a.png"].pixels, self.atlas1[20:28, 4:12][::-1])

    def test_an_icon_between_half_texels_keeps_the_texels_it_touches_and_its_own_rect(self):
        icon = read_icons(self.game_dir, ["a.png", "b.png"])["a.png"]
        self.assertEqual(icon.pixels.shape, (8, 8, 4))
        self.assertEqual((icon.x, icon.y, icon.w, icon.h), (0.5, 0.5, 7, 7))

    def test_the_sheet_holds_each_icon_top_row_first_at_its_rect(self):
        manifest = self.write()
        sheet = read_output(self.out_dir, manifest["iconSheet"]["file"])
        with open(os.path.join(self.out_dir, manifest["iconSheet"]["rects"])) as f:
            described = json.load(f)
        self.assertEqual((described["width"], described["height"]), sheet.shape[1::-1])
        self.assertEqual((manifest["iconSheet"]["width"], manifest["iconSheet"]["height"]), sheet.shape[1::-1])
        rect = described["icons"]["b.png"]
        np.testing.assert_array_equal(sheet[int(rect["y"]):int(rect["y"]) + 8, int(rect["x"]):int(rect["x"]) + 16], self.atlas2[40:48, 0:16][::-1])
        self.assertEqual((rect["w"], rect["h"]), (16, 8))


class PackIcons(unittest.TestCase):
    def icons(self):
        sizes = {"a": (63, 63), "b": (127, 127), "c": (20, 40), "d": (63, 63), "e": (255, 255)}
        return {name: Icon(solid(h, w, 10 + 40 * i), 0, 0, w, h) for i, (name, (h, w)) in enumerate(sizes.items())}

    def test_each_icon_sits_at_its_rect_and_keeps_its_native_size(self):
        icons = self.icons()
        sheet, rects = pack_icons(icons)
        for name, icon in icons.items():
            rect = rects[name]
            self.assertEqual((rect["w"], rect["h"]), (icon.w, icon.h))
            np.testing.assert_array_equal(sheet[rect["y"]:rect["y"] + rect["h"], rect["x"]:rect["x"] + rect["w"]], icon.pixels)

    def test_the_rect_offset_inside_the_texels_carries_into_the_sheet_rect(self):
        _, rects = pack_icons({"a": Icon(solid(8, 8, 1), 0.5, 0.25, 7, 7.5)})
        self.assertEqual(rects["a"], {"x": ICON_GUTTER + 0.5, "y": ICON_GUTTER + 0.25, "w": 7, "h": 7.5})

    def test_gutters_repeat_the_icons_edge_texels(self):
        pixels = noisy_pixels(5, 6, 4)
        sheet, rects = pack_icons({"a": Icon(pixels, 0, 0, 6, 5)})
        x, y = rects["a"]["x"], rects["a"]["y"]
        np.testing.assert_array_equal(sheet[y - ICON_GUTTER:y, x:x + 6], np.repeat(pixels[:1], ICON_GUTTER, 0))
        np.testing.assert_array_equal(sheet[y:y + 5, x + 6:x + 6 + ICON_GUTTER], np.repeat(pixels[:, -1:], ICON_GUTTER, 1))
        np.testing.assert_array_equal(sheet[y - 1, x - 1], pixels[0, 0])

    def test_no_mip_down_to_a_sixteenth_blends_neighbouring_icons_into_an_icons_bilinear_reach(self):
        icons = self.icons()
        sheet, rects = pack_icons(icons)
        for level in range(1, 5):
            reach, step = 2 ** (level + 1), 2 ** level
            mipped = mip(sheet, level)
            for name, icon in icons.items():
                rect = rects[name]
                rows = slice(int(rect["y"] - reach) // step, -(-int(rect["y"] + rect["h"] + reach) // step))
                columns = slice(int(rect["x"] - reach) // step, -(-int(rect["x"] + rect["w"] + reach) // step))
                reached = mipped[rows, columns]
                np.testing.assert_array_equal(reached, np.broadcast_to(icon.pixels[0, 0], reached.shape),
                                              err_msg="%s at mip %d" % (name, level))

    def test_the_sheet_is_as_wide_as_its_constant_and_as_tall_as_its_shelves(self):
        sheet, _ = pack_icons(self.icons())
        self.assertEqual(sheet.shape[1], SHEET_WIDTH)
        self.assertEqual(sheet.shape[0] % CELL_ALIGN, 0)
        self.assertGreater(sheet.shape[0], 0)


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
