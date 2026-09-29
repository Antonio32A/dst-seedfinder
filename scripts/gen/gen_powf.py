#!/usr/bin/env python3
"""Writes data/powf.bend, the tables of f32/powf.bend: powf on Linux (glibc) and Windows (MSVCR90), and the growing-tree
maze's exponent table. `-` prints the module instead.

- Linux (glibc 2.41 __powf_fma): `__powf_log2_data` and `__exp2f_data` read from the host /lib64/libm.so.6 .rodata
  (the offsets of glibc-2.41-18.fc42; the digest check fails loudly on any other libm).
- Windows (MSVCR90 9.00.30729.9635 powf): the correctly rounded doubles ln(1 + i/128), 2 / (1 + i/128) and 2^(j/32);
  the DLL's own ln table is one ulp above the correctly rounded value at index 61.
- Maze exponent: (float)pow(e, -val) for val = -3..7, forest_map.lua's `math.floor(math.random() * 10.0 - 2.5)`.
"""
import hashlib
import math
import struct
import sys
from decimal import Decimal, getcontext
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import blob  # noqa: E402
from gen_pow import small_table  # noqa: E402

getcontext().prec = 80

LIBM = Path("/lib64/libm.so.6")
LIBM_DIGEST = "cb2993dbfde8e7d8041e5e93e550c7c4c4695928bdcccbcc67faa1e07825a12b"
LOG2_TAB, LOG2_POLY, EXP2_TAB, EXP2_HEAD = 0xBEB20, 0xBEC20, 0xBE780, 0xBE880
WIN_LOG_OVERRIDE = {61: 0x3FD8F11E873662C8}
MAZE_VALS = range(-3, 8)


def libm_words(offset, count):
    return list(struct.unpack(f"<{count}Q", LIBM.read_bytes()[offset:offset + 8 * count]))


def glibc_tables():
    """log2 tab (invc, logc) x 16, poly A[0..4], exp2 tab x 32 and head (shift, C[0..2]), all as u64 bits."""
    log_tab, poly = libm_words(LOG2_TAB, 32), libm_words(LOG2_POLY, 5)
    exp_tab, head = libm_words(EXP2_TAB, 32), libm_words(EXP2_HEAD, 4)
    words = log_tab + poly + exp_tab + head
    digest = hashlib.sha256(struct.pack(f"<{len(words)}Q", *words)).hexdigest()
    if digest != LIBM_DIGEST:
        sys.exit(f"gen_powf.py: {LIBM} tables differ from glibc-2.41-18.fc42 (digest {digest}); re-derive the offsets")
    return [(log_tab[2 * i], log_tab[2 * i + 1]) for i in range(16)], poly, exp_tab, head


def rounded(value):
    """The double nearest to a Decimal, as bits."""
    return struct.unpack("<Q", struct.pack("<d", float(Fraction(value))))[0]


def windows_tables():
    log, recip, exp2 = [], [], []
    for i in range(129):
        c = Decimal(128 + i) / 128
        log.append(WIN_LOG_OVERRIDE.get(i, rounded(c.ln()) if i else 0))
        recip.append(rounded(Decimal(2) / c))
    ln2 = Decimal(2).ln()
    for j in range(32):
        exp2.append(rounded((Decimal(j) / 32 * ln2).exp()))
    return log, recip, exp2


def maze_exponents():
    return [blob.f32_bits(math.pow(2.718281828459045, -val)) for val in MAZE_VALS]


def f64(bits):
    return f"F64Repr.F64{{{bits >> 32}, {bits & 0xFFFFFFFF}}}"


def f64_row(bits):
    return blob.f64(struct.unpack("<d", struct.pack("<Q", bits))[0])


def bend_module():
    log_tab, poly, exp_tab, head = glibc_tables()
    m = blob.Module("powf", "scripts/gen/gen_powf.py", "Tables of f32/powf.bend: powf on Linux and Windows.",
                    ("./blob.bend as Blob", "../f64/repr.bend as F64Repr"))
    small_table(m, "glibc_log2_tab", [f64_row(a) + f64_row(b) for a, b in log_tab],
                "__powf_log2_data.tab[i]: invc, logc (f64 bits, hi-hi first).")
    for k, bits in enumerate(poly):
        m.const(f"glibc_log2_a{k}", f64(bits), "F64Repr.F64")
    small_table(m, "glibc_exp2_tab", [f64_row(b) for b in exp_tab], "__exp2f_data.tab[i]: the scale bits of 2^(i / 32).")
    for name, bits in zip(("shift", "c0", "c1", "c2"), head):
        m.const(f"glibc_exp2_{name}", f64(bits), "F64Repr.F64")
    log, recip, exp2 = windows_tables()
    small_table(m, "win_log_tab", [f64_row(b) for b in log], "ln(1 + i / 128).")
    small_table(m, "win_recip_tab", [f64_row(b) for b in recip], "2 / (1 + i / 128).")
    small_table(m, "win_exp2_tab", [f64_row(b) for b in exp2], "2^(j / 32).")
    small_table(m, "maze_exponent_tab", [blob.word(b) for b in maze_exponents()],
                "(float)pow(e, -val) bits for val = -3..7, at row val + 3.")
    return m


def main():
    bend_module().emit()


if __name__ == "__main__":
    main()
