import struct
import unittest

from ktex import mean_rgb

DXT1 = 0
DXT5 = 2
RED = 0xF800
BLUE = 0x001F


def ktex(pixel_format, mips):
    header = pixel_format << 4 | 1 << 9 | len(mips) << 13 | 0xFFF << 20
    mip_headers = b"".join(struct.pack("<HHHI", w, h, 0, len(data)) for w, h, data in mips)
    return b"KTEX" + struct.pack("<I", header) + mip_headers + b"".join(data for _, _, data in mips)


def dxt1_block(c0, c1, indices):
    return struct.pack("<HHI", c0, c1, sum(index << 2 * i for i, index in enumerate(indices)))


class MeanRgb(unittest.TestCase):
    def test_solid_dxt1_block_is_its_first_colour(self):
        self.assertEqual(mean_rgb(ktex(DXT1, [(4, 4, dxt1_block(RED, BLUE, [0] * 16))])), (255, 0, 0))

    def test_dxt1_interpolated_colours_sit_a_third_between_the_endpoints(self):
        self.assertEqual(mean_rgb(ktex(DXT1, [(4, 4, dxt1_block(RED, BLUE, [2] * 8 + [3] * 8))])), (128, 0, 128))

    def test_dxt1_three_colour_blocks_have_a_midpoint_and_black(self):
        self.assertEqual(mean_rgb(ktex(DXT1, [(4, 4, dxt1_block(BLUE, RED, [2] * 8 + [3] * 8))])), (64, 0, 64))

    def test_dxt5_colour_follows_the_alpha_block_and_always_has_four_colours(self):
        block = bytes([255, 0] + [0x92, 0x24, 0x49] * 2) + dxt1_block(BLUE, RED, [2] * 8 + [3] * 8)
        self.assertEqual(mean_rgb(ktex(DXT5, [(4, 4, block)])), (128, 0, 128))

    def test_only_the_full_size_mip_counts(self):
        full = dxt1_block(RED, BLUE, [0] * 16) + dxt1_block(BLUE, RED, [0] * 16)
        texture = ktex(DXT1, [(8, 4, full), (4, 2, dxt1_block(RED, BLUE, [1] * 16))])
        self.assertEqual(mean_rgb(texture), (128, 0, 128))


if __name__ == "__main__":
    unittest.main()
