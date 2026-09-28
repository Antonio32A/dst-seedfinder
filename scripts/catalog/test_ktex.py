import struct
import unittest

from ktex import decode

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

    def test_dxt5_colour_is_always_four_colours(self):
        block = dxt5_alpha_block(255, 255, [0] * 16) + dxt1_block(BLUE, RED, [2] * 16)
        self.assertEqual(decode(ktex(DXT5, [(4, 4, block)]))[0, 0].tolist(), [85, 0, 170, 255])

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

    def test_a_smaller_mip_is_read_after_the_larger_ones_and_cropped_out_of_its_block(self):
        texture = ktex(DXT1, [(4, 4, dxt1_block(RED, RED, [0] * 16)), (2, 2, dxt1_block(BLUE, BLUE, [0] * 16))])
        self.assertEqual(decode(texture, mip=1).tolist(), [[[0, 0, 255, 255]] * 2] * 2)

if __name__ == "__main__":
    unittest.main()
