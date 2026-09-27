import struct
import unittest

from ktex import decode, mean_rgb

DXT1 = 0
DXT3 = 1
DXT5 = 2
RGBA = 4
RGB = 5
RED = 0xF800
BLUE = 0x001F


def ktex(pixel_format, mips):
    header = pixel_format << 4 | 1 << 9 | len(mips) << 13 | 0xFFF << 20
    mip_headers = b"".join(struct.pack("<HHHI", w, h, 0, len(data)) for w, h, data in mips)
    return b"KTEX" + struct.pack("<I", header) + mip_headers + b"".join(data for _, _, data in mips)


def dxt1_block(c0, c1, indices):
    return struct.pack("<HHI", c0, c1, sum(index << 2 * i for i, index in enumerate(indices)))


def dxt5_alpha_block(a0, a1, indices):
    bits = sum(index << 3 * i for i, index in enumerate(indices))
    return bytes([a0, a1]) + bits.to_bytes(6, "little")


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


class Decode(unittest.TestCase):
    def test_dxt1_block_decodes_to_opaque_rgba_pixels(self):
        pixels = decode(ktex(DXT1, [(4, 4, dxt1_block(RED, BLUE, [0] * 8 + [1] * 8))]))
        self.assertEqual(pixels.shape, (4, 4, 4))
        self.assertEqual(pixels[0, 0].tolist(), [255, 0, 0, 255])
        self.assertEqual(pixels[3, 3].tolist(), [0, 0, 255, 255])

    def test_dxt1_three_colour_blocks_make_their_last_colour_transparent_black(self):
        pixels = decode(ktex(DXT1, [(4, 4, dxt1_block(BLUE, RED, [2] * 8 + [3] * 8))]))
        self.assertEqual(pixels[0, 0].tolist(), [127, 0, 127, 255])
        self.assertEqual(pixels[3, 3].tolist(), [0, 0, 0, 0])

    def test_interpolated_colours_round_down_like_the_gl_decoder(self):
        pixels = decode(ktex(DXT1, [(4, 4, dxt1_block(0x0001, 0x0000, [2] * 8 + [3] * 8))]))
        self.assertEqual([pixels[0, 0, 2], pixels[3, 3, 2]], [5, 2])

    def test_interpolated_alphas_round_down_like_the_gl_decoder(self):
        block = dxt5_alpha_block(10, 0, [2, 7] + [0] * 14) + dxt1_block(RED, RED, [0] * 16)
        self.assertEqual(decode(ktex(DXT5, [(4, 4, block)]))[0, :2, 3].tolist(), [8, 1])

    def test_dxt5_alpha_interpolates_eight_steps_between_descending_endpoints(self):
        block = dxt5_alpha_block(210, 0, [0, 1, 2, 7] + [0] * 12) + dxt1_block(RED, RED, [0] * 16)
        alpha = decode(ktex(DXT5, [(4, 4, block)]))[:, :, 3]
        self.assertEqual(alpha[0].tolist(), [210, 0, 180, 30])

    def test_dxt5_alpha_has_six_steps_plus_zero_and_opaque_between_ascending_endpoints(self):
        block = dxt5_alpha_block(0, 200, [2, 5, 6, 7] + [0] * 12) + dxt1_block(RED, RED, [0] * 16)
        alpha = decode(ktex(DXT5, [(4, 4, block)]))[:, :, 3]
        self.assertEqual(alpha[0].tolist(), [40, 160, 0, 255])

    def test_dxt3_alpha_is_four_explicit_bits_per_pixel_low_nibble_first(self):
        block = bytes([0xF0, 0x08] + [0] * 6) + dxt1_block(BLUE, RED, [3] * 16)
        pixels = decode(ktex(DXT3, [(4, 4, block)]))
        self.assertEqual(pixels[0, :3, 3].tolist(), [0, 255, 136])
        self.assertEqual(pixels[0, 0, :3].tolist(), [170, 0, 85])

    def test_rgba_pixels_are_stored_as_they_are(self):
        pixels = decode(ktex(RGBA, [(2, 1, bytes([1, 2, 3, 4, 5, 6, 7, 8]))]))
        self.assertEqual(pixels.tolist(), [[[1, 2, 3, 4], [5, 6, 7, 8]]])

    def test_rgb_pixels_are_opaque(self):
        pixels = decode(ktex(RGB, [(1, 2, bytes([1, 2, 3, 4, 5, 6]))]))
        self.assertEqual(pixels.tolist(), [[[1, 2, 3, 255]], [[4, 5, 6, 255]]])

    def test_blocks_are_laid_out_left_to_right_then_row_by_row(self):
        blocks = [dxt1_block(colour, colour, [0] * 16) for colour in [RED, BLUE, BLUE, RED]]
        pixels = decode(ktex(DXT1, [(8, 8, b"".join(blocks))]))
        self.assertEqual([pixels[0, 0, 0], pixels[0, 7, 0], pixels[7, 0, 0], pixels[7, 7, 0]], [255, 0, 0, 255])

    def test_smaller_mips_are_cropped_out_of_their_block(self):
        texture = ktex(DXT1, [(4, 4, dxt1_block(RED, RED, [0] * 16)), (2, 2, dxt1_block(BLUE, BLUE, [0] * 16))])
        self.assertEqual(decode(texture, mip=1).tolist(), [[[0, 0, 255, 255]] * 2] * 2)

    def test_rows_come_in_stored_order_unless_flipped(self):
        texture = ktex(RGB, [(1, 2, bytes([1, 2, 3, 4, 5, 6]))])
        self.assertEqual(decode(texture, flip=True).tolist(), [[[4, 5, 6, 255]], [[1, 2, 3, 255]]])

    def test_unpremultiplying_divides_the_colour_by_alpha(self):
        texture = ktex(RGBA, [(3, 1, bytes([50, 100, 0, 128, 0, 0, 0, 0, 9, 9, 9, 255]))])
        self.assertEqual(decode(texture, unpremultiply=True).tolist(),
                         [[[100, 199, 0, 128], [0, 0, 0, 0], [9, 9, 9, 255]]])


if __name__ == "__main__":
    unittest.main()
