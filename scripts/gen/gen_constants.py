#!/usr/bin/env python3
"""Writes data/constants.bend from out/constants_c.json (gen_constants.cpp: KK initial positions, blur kernel),
out/constants.json (extract_constants.lua: placement circle positions), the perlin permutation, read out of the
Linux dedicated server binary and, when DST_WINDOWS_EXE names it, the Windows one (the only 512-byte table
p[i] = p[i + 256] of a permutation of 0..255 that both contain), and the game build (the install's version.txt).
`-` prints the module instead."""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402

GAME = Path(os.environ.get("DST_GAME", Path.home() / ".local/share/Steam/steamapps/common/Don't Starve Together"))
BINARIES = [GAME / "bin64" / "dontstarve_dedicated_server_nullrenderer_x64"] + (
    [Path(os.environ["DST_WINDOWS_EXE"])] if "DST_WINDOWS_EXE" in os.environ else [])


def permutations_in(data):
    found = set()
    for i in range(0, len(data) - 511):
        if data[i] == data[i + 256] and data[i + 1] == data[i + 257]:
            window = data[i:i + 256]
            if window == data[i + 256:i + 512] and len(set(window)) == 256:
                found.add(bytes(window))
    return found


def perlin_permutation():
    tables = None
    for path in BINARIES:
        found = permutations_in(path.read_bytes())
        tables = found if tables is None else tables & found
    assert len(tables) == 1, f"{len(tables)} permutation tables common to the Linux and Windows binaries"
    return list(next(iter(tables)))


def f64_units(hex_bits):
    bits = int(hex_bits, 16)
    return [(bits >> 48) & 0xFFFF, (bits >> 32) & 0xFFFF, (bits >> 16) & 0xFFFF, bits & 0xFFFF]


def main():
    c = blob.sidecar("constants_c.json")
    lua = blob.sidecar("constants.json")
    m = blob.Module("constants", "scripts/gen/gen_constants.py",
                    "KK initial positions, blur kernel, placement circles, perlin permutation, game build.")
    m.comment("The build number of the game the data was generated from.")
    m.const("game_build", int((GAME / "version.txt").read_text().strip()))
    m.table("kk_positions", [f64_units(x) + f64_units(y) for x, y in c["kk_positions"]],
            "Row v: the initial KK position of vertex v (x then y, f64 bits, 4 units each): random_point() number v "
            "of a fresh minstd_rand over [0, 425]^2; island vertices continue the sequence.")
    kernel = c["blur_kernel"]
    m.const("blur_kernel_size", kernel["size"])
    m.const("blur_sigma_bits", int(kernel["sigma"], 16))
    m.table("blur_kernel", [[u for w in kernel["weights"] for u in blob.word(int(w, 16))]],
            "Row 0: GenerateBlendedMap's 1-D kernel (kernelSize 15, sigma 3.0f) as f32 bits, 2 units each.")
    circles = []
    for circle in lua["circles"]:
        circles.append([circle["kind"], circle["count"]] + [u for x, y in circle["positions"]
                                                            for u in f64_units(x) + f64_units(y)])
    m.table("circles", circles, "Row i: layout type (1 CIRCLE_EDGE, 2 CIRCLE_RANDOM), count n, then n positions "
                                "(x, y f64 bits) in generation order (CIRCLE_RANDOM's Randomize shuffle not applied).")
    perm = perlin_permutation()
    m.table("perlin", [[perm[i] | perm[i + 1] << 8 for i in range(0, 256, 2)]],
            "Row 0: the perlin permutation p[0..255] (p[i + 256] = p[i]), two bytes per unit, the lower index first.")
    m.code('''
def kk_x(+v: U32) -> U32 & U32:
  Blob.f64(kk_positions(v), 0)

def kk_y(+v: U32) -> U32 & U32:
  Blob.f64(kk_positions(v), 4)

def blur_weight(+i: U32) -> U32:
  Blob.word(blur_kernel(0), (i * 2 : U32))

def perlin_half(odd: Bool, +u: U32) -> U32:
  match odd:
    case True{}:
      (u >> 8n : U32)
    case False{}:
      (u .&. 255 : U32)

# The perlin permutation p[i & 255].
def perlin_p(+i: U32) -> U32:
  +k = (i .&. 255 : U32)
  perlin_half(U32.is_ne((k .&. 1 : U32), 0), Blob.at(perlin(0), (k >> 1n : U32)))
''')
    m.emit()


if __name__ == "__main__":
    main()
