import os
import struct
import tempfile
import unittest
import zlib

import numpy as np

from map_textures import encode_png, land_colour, write_map_textures
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


def read_output(out_dir, name):
    with open(os.path.join(out_dir, name), "rb") as f:
        return read_png(f.read())


class WriteMapTextures(unittest.TestCase):
    def setUp(self):
        self.game_dir = tempfile.mkdtemp()
        self.out_dir = tempfile.mkdtemp()
        self.grass = noisy_pixels(4, 2, 3)
        self.edge = noisy_pixels(2, 4, 4)
        self.paper = noisy_pixels(2, 2, 3)
        write_texture(self.game_dir, "levels/textures/mini_grass_noise.tex", RGB,
                      [(2, 4, self.grass), (1, 2, noisy_pixels(2, 1, 3))])
        write_texture(self.game_dir, "levels/tiles/map_edge.tex", RGBA, [(4, 2, self.edge)])
        write_texture(self.game_dir, "images/minimap_paper.tex", RGB, [(2, 2, self.paper)])

    def test_writes_each_noise_texture_as_its_full_size_rgb_mip(self):
        write_map_textures(self.game_dir, ["mini_grass_noise"], self.out_dir)
        np.testing.assert_array_equal(read_output(self.out_dir, "noise/mini_grass_noise.png"), self.grass)

    def test_writes_map_edge_rgba_as_stored_and_the_paper_as_rgb(self):
        write_map_textures(self.game_dir, [], self.out_dir)
        np.testing.assert_array_equal(read_output(self.out_dir, "map_edge.png"), self.edge)
        np.testing.assert_array_equal(read_output(self.out_dir, "minimap_paper.png"), self.paper)


class LandColour(unittest.TestCase):
    def test_is_the_mean_of_map_edge_cell_01_times_the_mean_noise(self):
        game_dir = tempfile.mkdtemp()
        edge = np.zeros((4, 4, 4), np.uint8)
        edge[2:, 2:] = [200, 100, 50, 255]
        write_texture(game_dir, "levels/tiles/map_edge.tex", RGBA, [(4, 4, edge)])
        with open(os.path.join(game_dir, "data/levels/tiles/map_edge.xml"), "w") as f:
            f.write('<Atlas><Elements><Element name="02" u1="0" u2="0.5" v1="0" v2="0.5" />'
                    '<Element name="01" u1="0.5" u2="1" v1="0.5" v2="1" /></Elements></Atlas>')
        noise = np.array([[[255, 128, 0], [255, 0, 0]]], np.uint8)
        write_texture(game_dir, "levels/textures/mini_grass_noise.tex", RGB, [(2, 1, noise)])
        self.assertEqual(land_colour(game_dir, "mini_grass_noise"), [200, 25, 0])


if __name__ == "__main__":
    unittest.main()
