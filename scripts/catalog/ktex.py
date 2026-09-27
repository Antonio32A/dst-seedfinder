"""Reads Klei KTEX textures (the game's .tex files)."""
import struct

BLOCK_LAYOUTS = {0: (8, 0), 2: (16, 8)}


def rgb565(c):
    r, g, b = c >> 11, c >> 5 & 0x3F, c & 0x1F
    return r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2


def mean_rgb(data):
    """The mean RGB of a KTEX texture's full-size mip, as rounded 0-255 ints."""
    assert data[:4] == b"KTEX", "not a KTEX texture"
    header, = struct.unpack_from("<I", data, 4)
    pixel_format, n_mips = header >> 4 & 0x1F, header >> 13 & 0x1F
    assert pixel_format in BLOCK_LAYOUTS, "unsupported KTEX pixel format %d" % pixel_format
    block_size, colour_offset = BLOCK_LAYOUTS[pixel_format]
    width, height, _, size = struct.unpack_from("<HHHI", data, 8)
    start = 8 + 10 * n_mips
    sums = [0, 0, 0]
    for offset in range(start, start + size, block_size):
        c0, c1, bits = struct.unpack_from("<HHI", data, offset + colour_offset)
        a, b = rgb565(c0), rgb565(c1)
        four_colour = [a, b, [(2 * x + y) / 3 for x, y in zip(a, b)], [(x + 2 * y) / 3 for x, y in zip(a, b)]]
        three_colour = [a, b, [(x + y) / 2 for x, y in zip(a, b)], (0, 0, 0)]
        palette = four_colour if c0 > c1 or colour_offset else three_colour
        for i in range(16):
            colour = palette[bits >> 2 * i & 3]
            sums = [s + c for s, c in zip(sums, colour)]
    return tuple(round(s / (width * height)) for s in sums)
