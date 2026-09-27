"""Reads Klei KTEX textures (the game's .tex files)."""
import functools
import struct

import numpy as np


def rgb565(c):
    r, g, b = c >> 11, c >> 5 & 0x3F, c & 0x1F
    return r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2


def colour_texels(blocks, always_four_colours):
    endpoints = blocks[:, :4].copy().view("<u2").astype(np.int64)
    c0, c1 = endpoints[:, 0], endpoints[:, 1]
    a, b = np.stack(rgb565(c0), -1), np.stack(rgb565(c1), -1)
    four = (always_four_colours | (c0 > c1))[:, None]
    third, two_thirds = np.where(four, (2 * a + b) // 3, (a + b) // 2), np.where(four, (a + 2 * b) // 3, 0)
    rgb = np.stack([a, b, third, two_thirds], 1)
    alpha = np.where(four, 255, [255, 255, 255, 0])
    palettes = np.concatenate([rgb, alpha[:, :, None]], -1)
    indices = blocks[:, 4:8].copy().view("<u4") >> 2 * np.arange(16, dtype=np.uint32) & 3
    return np.take_along_axis(palettes, indices[:, :, None].astype(np.int64), 1)


def dxt5_alpha(blocks):
    a0, a1 = blocks[:, 0:1].astype(np.int64), blocks[:, 1:2].astype(np.int64)
    steps = np.arange(1, 7)
    eight_alphas = ((7 - steps) * a0 + steps * a1) // 7
    six_alphas = ((5 - steps[:4]) * a0 + steps[:4] * a1) // 5
    six_alphas = np.concatenate([six_alphas, np.zeros_like(a0), np.full_like(a0, 255)], 1)
    palettes = np.concatenate([a0, a1, np.where(a0 > a1, eight_alphas, six_alphas)], 1)
    bits = np.pad(blocks[:, 2:8], ((0, 0), (0, 2))).copy().view("<u8")
    indices = bits >> 3 * np.arange(16, dtype=np.uint64) & 7
    return np.take_along_axis(palettes, indices.astype(np.int64), 1)


def dxt1_texels(blocks):
    return colour_texels(blocks, False)


def dxt3_texels(blocks):
    texels = colour_texels(blocks[:, 8:], True)
    texels[:, :, 3] = np.stack([blocks[:, :8] & 0xF, blocks[:, :8] >> 4], -1).reshape(-1, 16) * 17
    return texels


def dxt5_texels(blocks):
    texels = colour_texels(blocks[:, 8:], True)
    texels[:, :, 3] = dxt5_alpha(blocks[:, :8])
    return texels


def block_pixels(block_size, block_texels, raw, width, height):
    blocks_wide, blocks_high = (width + 3) // 4, (height + 3) // 4
    texels = block_texels(raw.reshape(-1, block_size))
    pixels = texels.reshape(blocks_high, blocks_wide, 4, 4, 4).transpose(0, 2, 1, 3, 4)
    return pixels.reshape(4 * blocks_high, 4 * blocks_wide, 4)[:height, :width].astype(np.uint8)


def rgba_pixels(raw, width, height):
    return raw.reshape(height, width, 4)


def rgb_pixels(raw, width, height):
    return np.concatenate([raw.reshape(height, width, 3), np.full((height, width, 1), 255, np.uint8)], -1)


PIXEL_FORMATS = {
    0: functools.partial(block_pixels, 8, dxt1_texels),
    1: functools.partial(block_pixels, 16, dxt3_texels),
    2: functools.partial(block_pixels, 16, dxt5_texels),
    4: rgba_pixels,
    5: rgb_pixels,
}


def decode(data, mip=0, flip=False, unpremultiply=False):
    """The pixels of one mip of a KTEX texture, as a (height, width, 4) uint8 RGBA array.

    Rows come in stored order, which is OpenGL's: the first row is texture coordinate v = 0, the bottom of the image.
    `flip` turns them top-down instead. `unpremultiply` divides the colour by alpha, for textures stored
    premultiplied; fully transparent pixels stay black.
    """
    assert data[:4] == b"KTEX", "not a KTEX texture"
    header, = struct.unpack_from("<I", data, 4)
    pixel_format, n_mips = header >> 4 & 0x1F, header >> 13 & 0x1F
    assert pixel_format in PIXEL_FORMATS, "unsupported KTEX pixel format %d" % pixel_format
    mips = [struct.unpack_from("<HHHI", data, 8 + 10 * i) for i in range(n_mips)]
    width, height, _, size = mips[mip]
    raw = np.frombuffer(data, np.uint8, size, 8 + 10 * n_mips + sum(m[3] for m in mips[:mip]))
    pixels = PIXEL_FORMATS[pixel_format](raw, width, height)
    if unpremultiply:
        alpha = pixels[:, :, 3:].astype(np.float64)
        colour = np.where(alpha > 0, np.minimum(pixels[:, :, :3] / np.maximum(alpha, 1) * 255, 255), 0)
        pixels = np.concatenate([np.rint(colour).astype(np.uint8), pixels[:, :, 3:]], -1)
    return pixels[::-1] if flip else pixels


def mean_rgb(data):
    """The mean RGB of a KTEX texture's full-size mip, as rounded 0-255 ints."""
    return tuple(round(channel) for channel in decode(data)[:, :, :3].reshape(-1, 3).mean(0).tolist())
