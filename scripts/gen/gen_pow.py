#!/usr/bin/env python3
"""Writes data/pow.bend, the tables of ocean/pow.bend's pow(r, 0.8) for both platforms. `-` prints the module
instead; `c` prints the same tables as a C header (for .scratch/port/test/ocean/).

- Linux (glibc 2.41 __ieee754_pow_fma): `__pow_log_data` and `__exp_data` read from the host /lib64/libm.so.6 .rodata
  (the offsets of glibc-2.41-18.fc42; the digest check fails loudly on any other libm).
- Windows (MSVCR90 9.00.30729.9635 x87 pow): fixed-point tables of the correctly rounded fyl2x/f2xm1 model, computed
  here with Python's decimal module, plus the model's exceptions on this CPU (out/pow_windows_exceptions.txt, from the
  exhaustive run .scratch/port/test/ocean/pow_exceptions.sh against the real DLL).
"""
import struct
import sys
from decimal import ROUND_HALF_EVEN, Decimal, getcontext
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402

getcontext().prec = 120

LIBM = Path("/lib64/libm.so.6")
LIBM_DIGEST = "a6895f1c70a4865f771bfabe5670c44b04d078680cb819ca94d13a08e235b6f7"
LOG_HEAD, LOG_TAB, EXP_HEAD, EXP_TAB = 0xBC920, 0xBC968, 0xBA720, 0xBA7D0
OFF = 0x3FE6955500000000
LOG_INDEX_SHIFT = 44
LOG_TERMS = 13
EXP_TERMS = 9
Y_BITS = 0x3FE999999999999A
EXCEPTIONS = blob.GEN / "out" / "pow_windows_exceptions.txt"
BUCKET_SHIFT = 19


def libm_words(offset, count):
    return list(struct.unpack(f"<{count}Q", LIBM.read_bytes()[offset:offset + 8 * count]))


def glibc_tables():
    """log head (ln2hi, ln2lo, A[0..6]), log tab [(invc, logc, logctail)] x 128, exp head (invln2N, negln2hiN,
    negln2loN, C2..C5, shift at [7]), exp tab (tail, sbits) x 128, all as u64 bits."""
    import hashlib
    log_head = libm_words(LOG_HEAD, 9)
    raw = libm_words(LOG_TAB, 512)
    log_tab = [(raw[4 * i], raw[4 * i + 2], raw[4 * i + 3]) for i in range(128)]
    exp_head = libm_words(EXP_HEAD, 9)
    raw = libm_words(EXP_TAB, 256)
    exp_tab = [(raw[2 * i], raw[2 * i + 1]) for i in range(128)]
    words = log_head + [w for row in log_tab for w in row] + exp_head + [w for row in exp_tab for w in row]
    digest = hashlib.sha256(struct.pack(f"<{len(words)}Q", *words)).hexdigest()
    if digest != LIBM_DIGEST:
        sys.exit(f"gen_pow.py: {LIBM} tables differ from glibc-2.41-18.fc42 (digest {digest}); re-derive the offsets")
    return log_head, log_tab, exp_head, exp_tab


def as_double(bits):
    return struct.unpack("<d", struct.pack("<Q", bits))[0]


def fixed(value, scale):
    return int((value * (Decimal(2) ** scale)).to_integral_value(ROUND_HALF_EVEN))


def exact(bits):
    f = Fraction(as_double(bits))
    return Decimal(f.numerator) / Decimal(f.denominator)


def log_reduction():
    """[(C, -ln(C / 2^11) at 2^-122, two's complement)] for the 256 slices of z in [OFF, 2 OFF)."""
    rows = []
    for i in range(256):
        lo = Fraction(as_double(OFF + (i << LOG_INDEX_SHIFT)))
        hi = Fraction(as_double(OFF + ((i + 1) << LOG_INDEX_SHIFT)))
        c = round(Fraction(2 ** 11) / ((lo + hi) / 2))
        rows.append((c, fixed(-(Decimal(c) / 2 ** 11).ln(), 122) % (1 << 128)))
    return rows


def exp_tables():
    """2^(a/32) for a in -16..16 and 2^(b/1024) for b in 0..31, at 2^-127."""
    ln2 = Decimal(2).ln()
    coarse = [fixed((Decimal(a) / 32 * ln2).exp(), 127) for a in range(-16, 17)]
    fine = [fixed((Decimal(b) / 1024 * ln2).exp(), 127) for b in range(32)]
    return coarse, fine


def series():
    """1/k (k = 1..LOG_TERMS) and 1/(k+1)! (k = 0..EXP_TERMS-1) at 2^-127, lowest order first."""
    log = [fixed(Decimal(1) / k, 127) for k in range(1, LOG_TERMS + 1)]
    exp, fact = [], 1
    for k in range(EXP_TERMS):
        fact *= k + 1
        exp.append(fixed(Decimal(1) / fact, 127))
    return log, exp


def windows_constants():
    ln2 = Decimal(2).ln()
    return {"ln2_122": fixed(ln2, 122), "ln2_128": fixed(ln2, 128), "k_126": fixed(exact(Y_BITS) / ln2, 126)}


def exceptions():
    """[(x, delta ulp)] sorted by x."""
    rows = []
    for line in EXCEPTIONS.read_text().splitlines():
        if line and not line.startswith("#"):
            x, d = line.split()
            rows.append((int(x), int(d)))
    assert all(d in (1, -1) for _, d in rows) and rows == sorted(rows)
    return rows


def small_table(m, name, rows, doc, shift=2):
    """A blob table with 2^shift rows per chunk (blob.Module.table uses 32): shorter walks for the per-call lookups."""
    rows = [list(r) for r in rows]
    m.comment(doc)
    m.tables[name] = rows
    per = 1 << shift
    m.lines += [f"def {name}_chunk(+c: U32) -> String:", "  match c:"]
    for c in range(0, len(rows), per):
        literal = "".join(blob.encode_row(r) for r in rows[c:c + per])
        m.units += len(literal)
        m.lines += [f"    case {c // per}:", f'      "{literal}"']
    m.lines += ["    case _:", '      ""', ""]
    m.lines += [f"def {name}(+i: U32) -> List<&2, U32>:",
                f"  B.row({name}_chunk((i >> {shift}n : U32)), (i .&. {per - 1} : U32))", ""]


def units128(v):
    return [(v >> s) & 0xFFFF for s in range(112, -16, -16)]


def w128(v):
    return "FW.W128{" + ", ".join(str((v >> s) & 0xFFFFFFFF) for s in (96, 64, 32, 0)) + "}"


def f64(bits):
    return f"FR.F64{{{bits >> 32}, {bits & 0xFFFFFFFF}}}"


def bend_module():
    log_head, log_tab, exp_head, exp_tab = glibc_tables()
    m = blob.Module("pow", "scripts/gen/gen_pow.py",
                    "Tables of ocean/pow.bend: pow(r, 0.8) on Linux and Windows.",
                    ("./blob.bend as B", "../f64/word.bend as FW", "../f64/repr.bend as FR"))
    names = ["glibc_ln2hi", "glibc_ln2lo"] + [f"glibc_log_a{k}" for k in range(7)]
    for name, bits in zip(names, log_head):
        m.const(name, f64(bits), "FR.F64")
    log_rows = [blob.f64(as_double(a)) + blob.f64(as_double(b)) + blob.f64(as_double(c)) for a, b, c in log_tab]
    small_table(m, "glibc_log_tab", log_rows, "__pow_log_data.tab[i]: invc, logc, logctail.")
    names = ["glibc_invln2n", "glibc_negln2hin", "glibc_negln2lon", "glibc_exp_c2", "glibc_exp_c3", "glibc_exp_c4",
             "glibc_exp_c5", "glibc_shift"]
    for name, bits in zip(names, exp_head):
        m.const(name, f64(bits), "FR.F64")
    small_table(m, "glibc_exp_tab", [units128(tail << 64 | sbits) for tail, sbits in exp_tab],
                "__exp_data.tab[2i], tab[2i + 1]: tail bits, scale bits (hi-hi first).")
    small_table(m, "win_log_tab", [[c] + units128(v) for c, v in log_reduction()],
                "Slice i of z: C (c = C / 2^11 ~ 1/z), -ln(c) at 2^-122 (two's complement, 16-bit units, high first).")
    coarse, fine = exp_tables()
    small_table(m, "win_exp_coarse", [units128(v) for v in coarse], "Row a + 16: 2^(a/32) at 2^-127.")
    small_table(m, "win_exp_fine", [units128(v) for v in fine], "Row b: 2^(b/1024) at 2^-127.")
    log, exp = series()
    m.const("win_log_series", "[" + ", ".join(w128(v) for v in reversed(log)) + "]", "List<&2, FW.W128>")
    m.const("win_exp_series", "[" + ", ".join(w128(v) for v in reversed(exp)) + "]", "List<&2, FW.W128>")
    for name, v in windows_constants().items():
        m.const(f"win_{name}", w128(v), "FW.W128")
    buckets = [[] for _ in range(1 << (32 - BUCKET_SHIFT))]
    for x, d in exceptions():
        buckets[x >> BUCKET_SHIFT].append((x & ((1 << BUCKET_SHIFT) - 1)) | (int(d > 0) << BUCKET_SHIFT))
    m.table("win_exceptions", buckets,
            f"Bucket x >> {BUCKET_SHIFT}: the x where MSVCR90 pow = model + 1 ulp (bit {BUCKET_SHIFT} set) or - 1 ulp, "
            f"as x & {(1 << BUCKET_SHIFT) - 1} (ascending).")
    return m


def c_header():
    log_head, log_tab, exp_head, exp_tab = glibc_tables()
    coarse, fine = exp_tables()
    log, exp = series()

    def u128(v):
        return f"{{0x{v >> 64:016x}ull, 0x{v & (2 ** 64 - 1):016x}ull}}"

    def words(ws):
        return ", ".join(f"0x{w:016x}ull" for w in ws)

    out = ["/* Generated by scripts/gen/gen_pow.py c; do not edit by hand. */", "#include <stdint.h>",
           "typedef struct { uint64_t hi, lo; } PowU128;",
           f"static const uint64_t POW_LOG_HEAD[9] = {{{words(log_head)}}};",
           "static const uint64_t POW_LOG_TAB[128][3] = {" + ", ".join("{" + words(r) + "}" for r in log_tab) + "};",
           f"static const uint64_t POW_EXP_HEAD[9] = {{{words(exp_head)}}};",
           "static const uint64_t POW_EXP_TAB[128][2] = {" + ", ".join("{" + words(r) + "}" for r in exp_tab) + "};",
           "static const uint32_t WIN_LOG_C[256] = {" + ", ".join(str(c) for c, _ in log_reduction()) + "};",
           "static const PowU128 WIN_LOG_NLC[256] = {" + ", ".join(u128(v) for _, v in log_reduction()) + "};",
           "static const PowU128 WIN_EXP_COARSE[33] = {" + ", ".join(u128(v) for v in coarse) + "};",
           "static const PowU128 WIN_EXP_FINE[32] = {" + ", ".join(u128(v) for v in fine) + "};",
           f"static const PowU128 WIN_LOG_SERIES[{LOG_TERMS}] = {{" + ", ".join(u128(v) for v in log) + "};",
           f"static const PowU128 WIN_EXP_SERIES[{EXP_TERMS}] = {{" + ", ".join(u128(v) for v in exp) + "};"]
    out += [f"static const PowU128 WIN_{name.upper()} = {u128(v)};" for name, v in windows_constants().items()]
    return "\n".join(out) + "\n"


def main():
    if sys.argv[1:] == ["c"]:
        sys.stdout.write(c_header())
        return
    bend_module().emit()


if __name__ == "__main__":
    main()
