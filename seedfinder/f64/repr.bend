import Base
import ./word.bend as FW

# An IEEE-754 double as its raw bits (hi word first).
type F64 is Data:
  F64{hi: U32, lo: U32}

def sign_mask() -> U32:
  2147483648

def abs_mask() -> U32:
  2147483647

def exp_mask() -> U32:
  2146435072

def frac_mask() -> U32:
  1048575

def hidden_bit() -> U32:
  1048576

def quiet_bit() -> U32:
  524288

def default_nan_hi() -> U32:
  4294443008

def zero() -> F64:
  F64{0, 0}

def neg_zero() -> F64:
  F64{2147483648, 0}

def one() -> F64:
  F64{1072693248, 0}

def half() -> F64:
  F64{1071644672, 0}

def two() -> F64:
  F64{1073741824, 0}

def inf() -> F64:
  F64{2146435072, 0}

def neg_inf() -> F64:
  F64{4293918720, 0}

# The x86 default NaN (0xFFF8000000000000), produced by invalid operations.
def nan() -> F64:
  F64{4294443008, 0}

# 2^-52, std::numeric_limits<double>::epsilon().
def epsilon() -> F64:
  F64{1018167296, 0}

def max_finite() -> F64:
  F64{2146435071, 4294967295}

def min_normal() -> F64:
  F64{1048576, 0}

def min_subnormal() -> F64:
  F64{0, 1}

def pick(c: Bool, a: F64, b: F64) -> F64:
  match c:
    case True{}:
      a
    case False{}:
      b

def exp_field(+h: U32) -> U32:
  ((h >> 20n) .&. 2047 : U32)

def sign_of(+h: U32) -> U32:
  (h >> 31n : U32)

def is_nan_words(+h: U32, +l: U32) -> Bool:
  +m = (h .&. abs_mask() : U32)
  (m > exp_mask() : U32) || (U32.is_eq(m, exp_mask()) && Bool.not(U32.is_zero(l)))

def is_inf_words(+h: U32, +l: U32) -> Bool:
  U32.is_eq((h .&. abs_mask() : U32), exp_mask()) && U32.is_zero(l)

def is_zero_words(+h: U32, +l: U32) -> Bool:
  U32.is_zero(((h .&. abs_mask()) .|. l : U32))

def is_special_exp(+h: U32) -> Bool:
  U32.is_eq(exp_field(h), 2047)

def is_nan(x: F64) -> Bool:
  match x:
    case F64{+h, +l}:
      is_nan_words(h, l)

def is_inf(x: F64) -> Bool:
  match x:
    case F64{+h, +l}:
      is_inf_words(h, l)

def is_zero(x: F64) -> Bool:
  match x:
    case F64{+h, +l}:
      is_zero_words(h, l)

def is_finite(x: F64) -> Bool:
  match x:
    case F64{+h, l}:
      Bool.not(is_special_exp(h))

def is_subnormal(x: F64) -> Bool:
  match x:
    case F64{+h, +l}:
      U32.is_zero(exp_field(h)) && Bool.not(is_zero_words(h, l))

def sign_bit(x: F64) -> Bool:
  match x:
    case F64{+h, l}:
      (h >= sign_mask() : U32)

def neg(x: F64) -> F64:
  match x:
    case F64{+h, +l}:
      F64{(h .^. sign_mask() : U32), l}

def abs(x: F64) -> F64:
  match x:
    case F64{+h, +l}:
      F64{(h .&. abs_mask() : U32), l}

def copysign_words(+h: U32, +l: U32, +sh: U32) -> F64:
  F64{((h .&. abs_mask()) .|. (sh .&. sign_mask()) : U32), l}

def copysign(x: F64, s: F64) -> F64:
  match x:
    case F64{+h, +l}:
      match s:
        case F64{+sh, sl}:
          copysign_words(h, l, sh)

def quiet_words(+h: U32, +l: U32) -> F64:
  F64{(h .|. quiet_bit() : U32), l}

def first_nan(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64:
  +a_nan = is_nan_words(ah, al)
  F64{(FW.pick(a_nan, ah, bh) .|. quiet_bit() : U32), FW.pick(a_nan, al, bl)}

def signed_zero(+sign: U32) -> F64:
  F64{(sign << 31n : U32), 0}

def signed_inf(+sign: U32) -> F64:
  F64{((sign << 31n) .|. exp_mask() : U32), 0}

def overflow_hi(over: Bool, +sign: U32, +e: U32, +rh: U32) -> U32:
  FW.pick(over, ((sign << 31n) .|. exp_mask() : U32), ((sign << 31n) + (e << 20n) + rh : U32))

def round_general(+sign: U32, +exp: U32, +sh: U32, +sl: U32) -> F64:
  +neg = (exp >= 2147483648 : U32)
  +d = FW.pick(neg, (0 - exp : U32), 0)
  +h = FW.shr_hi(sh, d)
  +l = FW.shr_jam_lo(sh, sl, d)
  +e = FW.pick(neg, 0, exp)
  +sum_lo = (l + 512 : U32)
  +sum_hi = (h + FW.carry(sum_lo, l) : U32)
  +over = Bool.not(neg) && ((e > 2045 : U32) || (U32.is_eq(e, 2045) && (sum_hi >= 2147483648 : U32)))
  +rh = (sum_hi >> 10n : U32)
  +rl = (((sum_lo >> 10n) .|. (sum_hi << 22n)) .&. U32.not(Bool.to_u32(U32.is_eq((l .&. 1023 : U32), 512))) : U32)
  +e2 = FW.pick(U32.is_zero((rh .|. rl : U32)), 0, e)
  F64{overflow_hi(over, sign, e2, rh), FW.pick(over, 0, rl)}

def round_normal(+sign: U32, +exp: U32, +sh: U32, +sl: U32) -> F64:
  +sum_lo = (sl + 512 : U32)
  +sum_hi = (sh + FW.carry(sum_lo, sl) : U32)
  +rl = (((sum_lo >> 10n) .|. (sum_hi << 22n)) .&. U32.not(Bool.to_u32(U32.is_eq((sl .&. 1023 : U32), 512))) : U32)
  F64{((sign << 31n) + (exp << 20n) + (sum_hi >> 10n) : U32), rl}

def round_route(normal: Bool, +sign: U32, +exp: U32, +sh: U32, +sl: U32) -> F64:
  match normal:
    case True{}:
      round_normal(sign, exp, sh, sl)
    case False{}:
      round_general(sign, exp, sh, sl)

# SoftFloat's roundPackToF64: sig (sh, sl) has its leading bit at bit 62 and 10 rounding bits; exp is the biased
# exponent minus one, two's complement in a U32 (negative gives a subnormal). Round to nearest even.
def round_pack(+sign: U32, +exp: U32, +sh: U32, +sl: U32) -> F64:
  round_route((exp < 2045 : U32), sign, exp, sh, sl)

def norm_shift(+h: U32, +l: U32) -> U32:
  (FW.clz64((h .&. frac_mask() : U32), l) - 11 : U32)

# Biased exponent of a finite nonzero value after normalising a subnormal (1 - shift, two's complement).
def norm_exp(+h: U32, +l: U32) -> U32:
  +e = exp_field(h)
  FW.pick(U32.is_zero(e), (1 - norm_shift(h, l) : U32), e)

# The 53-bit significand with its leading bit at bit 52 (bit 20 of the hi word), subnormals normalised.
def norm_sig_hi(+h: U32, +l: U32) -> U32:
  +f = (h .&. frac_mask() : U32)
  FW.pick(U32.is_zero(exp_field(h)), FW.shl_hi(f, l, norm_shift(h, l)), (f .|. hidden_bit() : U32))

def norm_sig_lo(+h: U32, +l: U32) -> U32:
  FW.pick(U32.is_zero(exp_field(h)), FW.shl(l, norm_shift(h, l)), l)

def from_u32_signed(+sign: U32, +x: U32) -> F64:
  +lz = FW.clz32(x)
  +m = FW.shl(x, lz)
  +e = FW.pick(U32.is_zero(x), 0, (1054 - lz : U32))
  F64{((sign << 31n) .|. (e << 20n) .|. ((m >> 11n) .&. frac_mask()) : U32), (m << 21n : U32)}

# Exact conversions from 32-bit integers ((double)x in C).
def from_u32(+x: U32) -> F64:
  from_u32_signed(0, x)

def from_i32(+x: U32) -> F64:
  +sign = (x >> 31n : U32)
  from_u32_signed(sign, FW.pick(U32.is_zero(sign), x, (0 - x : U32)))

def from_u64_signed(+sign: U32, +h: U32, +l: U32) -> F64:
  +lz = FW.clz64(h, l)
  +top = U32.is_zero(lz)
  +k = (lz - 1 : U32)
  +sh = FW.pick(top, (h >> 1n : U32), FW.shl_hi(h, l, k))
  +sl = FW.pick(top, ((l >> 1n) .|. (h << 31n) .|. (l .&. 1) : U32), FW.shl(l, k))
  round_pack(sign, FW.pick(U32.is_zero((h .|. l : U32)), 0, (1085 - lz : U32)), sh, sl)

# Conversions from 64-bit integers given as (hi, lo) words, rounded to nearest even (cvtsi2sd).
def from_u64(+h: U32, +l: U32) -> F64:
  from_u64_signed(0, h, l)

def from_i64(+h: U32, +l: U32) -> F64:
  +sign = (h >> 31n : U32)
  +neg = Bool.not(U32.is_zero(sign))
  from_u64_signed(sign, FW.pick(neg, (0 - h - FW.nonzero(l) : U32), h), FW.pick(neg, (0 - l : U32), l))

def trunc_mag(+h: U32, +l: U32) -> U32:
  +e = exp_field(h)
  FW.pick((e < 1023 : U32), 0, FW.shr_lo(((h .&. frac_mask()) .|. hidden_bit() : U32), l, (1075 - e : U32)))

def to_i32_words(+h: U32, +l: U32) -> U32:
  +m = trunc_mag(h, l)
  FW.pick((exp_field(h) >= 1054 : U32), 2147483648, FW.pick((h >= sign_mask() : U32), (0 - m : U32), m))

# C (int)x on x86-64 (cvttsd2si): truncation, 0x80000000 for NaN and out-of-range values.
def to_i32(x: F64) -> U32:
  match x:
    case F64{+h, +l}:
      to_i32_words(h, l)

def mag64_hi(+h: U32, +l: U32) -> U32:
  +e = exp_field(h)
  +sh = ((h .&. frac_mask()) .|. hidden_bit() : U32)
  FW.pick((e < 1023 : U32), 0, FW.pick((e >= 1075 : U32), FW.shl_hi(sh, l, (e - 1075 : U32)), FW.shr_hi(sh, (1075 - e : U32))))

def mag64_lo(+h: U32, +l: U32) -> U32:
  +e = exp_field(h)
  +sh = ((h .&. frac_mask()) .|. hidden_bit() : U32)
  FW.pick((e < 1023 : U32), 0, FW.pick((e >= 1075 : U32), FW.shl(l, (e - 1075 : U32)), FW.shr_lo(sh, l, (1075 - e : U32))))

def signed64(big: Bool, +neg: Bool, +mh: U32, +ml: U32) -> FW.W64:
  match big:
    case True{}:
      FW.W64{2147483648, 0}
    case False{}:
      FW.W64{FW.pick(neg, (0 - mh - FW.nonzero(ml) : U32), mh), FW.pick(neg, (0 - ml : U32), ml)}

def to_i64_words(+h: U32, +l: U32) -> FW.W64:
  signed64((exp_field(h) >= 1086 : U32), (h >= sign_mask() : U32), mag64_hi(h, l), mag64_lo(h, l))

# C (int64_t)x on x86-64 (cvttsd2si r64): truncation, 0x8000000000000000 for NaN and out-of-range values.
def to_i64(x: F64) -> FW.W64:
  match x:
    case F64{+h, +l}:
      to_i64_words(h, l)

def low_word(w: FW.W64) -> U32:
  match w:
    case FW.W64{h, l}:
      l

# C (uint32_t)x as gcc compiles it on x86-64: the low word of the 64-bit truncation.
def to_u32(x: F64) -> U32:
  low_word(to_i64(x))

def from_f32_normal(+s: U32, +e: U32, +f: U32) -> F64:
  F64{(s .|. ((e + 896) << 20n) .|. (f >> 3n) : U32), (f << 29n : U32)}

def from_f32_small(+s: U32, +f: U32) -> F64:
  +lz = FW.clz32(f)
  +m = FW.shl(f, (lz - 8 : U32))
  +e = FW.pick(U32.is_zero(f), 0, (905 - lz : U32))
  F64{(s .|. (e << 20n) .|. ((m .&. 8388607) >> 3n) : U32), (m << 29n : U32)}

def from_f32_special(+s: U32, +f: U32) -> F64:
  F64{(s .|. exp_mask() .|. FW.pick(U32.is_zero(f), 0, quiet_bit()) .|. (f >> 3n) : U32), (f << 29n : U32)}

def from_f32_route(+e: U32, +s: U32, +f: U32) -> F64:
  pick(U32.is_zero(e), from_f32_small(s, f), pick(U32.is_eq(e, 255), from_f32_special(s, f), from_f32_normal(s, e, f)))

# Exact float -> double from the float's bits (cvtss2sd: a NaN is quieted, its payload kept).
def from_f32_bits(+b: U32) -> F64:
  from_f32_route(((b >> 23n) .&. 255 : U32), (b .&. sign_mask() : U32), (b .&. 8388607 : U32))

def f32_round_pack(+sign: U32, +exp: U32, +sig: U32) -> U32:
  +neg = (exp >= 2147483648 : U32)
  +d = FW.pick(neg, (0 - exp : U32), 0)
  +s = (FW.shr(sig, d) .|. FW.nonzero(FW.pick(U32.is_zero(d), 0, FW.pick((d < 32 : U32), FW.shl(sig, (32 - d : U32)), sig))) : U32)
  +e = FW.pick(neg, 0, exp)
  +over = Bool.not(neg) && ((e > 253 : U32) || (U32.is_eq(e, 253) && ((s + 64 : U32) >= 2147483648 : U32)))
  +r = (((s + 64) >> 7n) .&. U32.not(Bool.to_u32(U32.is_eq((s .&. 127 : U32), 64))) : U32)
  +e2 = FW.pick(U32.is_zero(r), 0, e)
  FW.pick(over, ((sign << 31n) .|. 2139095040 : U32), ((sign << 31n) + (e2 << 23n) + r : U32))

def to_f32_finite(+h: U32, +l: U32) -> U32:
  +sh = ((h .&. frac_mask()) .|. hidden_bit() : U32)
  +sig = ((sh << 10n) .|. (l >> 22n) .|. FW.nonzero((l .&. 4194303 : U32)) : U32)
  +e = exp_field(h)
  FW.pick(U32.is_zero(e), (h .&. sign_mask() : U32), f32_round_pack(sign_of(h), (e - 897 : U32), sig))

def to_f32_special(+h: U32, +l: U32) -> U32:
  +f = ((h .&. frac_mask()) .|. l : U32)
  +payload = (((h .&. frac_mask()) << 3n) .|. (l >> 29n) : U32)
  ((h .&. sign_mask()) .|. 2139095040 .|. FW.pick(U32.is_zero(f), 0, (4194304 .|. payload : U32)) : U32)

# double -> float bits, rounded to nearest even (cvtsd2ss: a NaN is quieted, its payload truncated).
def to_f32_bits(x: F64) -> U32:
  match x:
    case F64{+h, +l}:
      FW.pick(is_special_exp(h), to_f32_special(h, l), to_f32_finite(h, l))

def unit_hi(+f: U32) -> U32:
  FW.shl(1, (f - 32 : U32))

def unit_lo(+f: U32) -> U32:
  FW.shl(1, f)

def mask_hi(+f: U32) -> U32:
  (unit_hi(f) - Bool.to_u32(U32.is_zero(unit_lo(f))) : U32)

def mask_lo(+f: U32) -> U32:
  (unit_lo(f) - 1 : U32)

def frac_bits(+h: U32, +l: U32, +f: U32) -> U32:
  (((h .&. mask_hi(f)) .|. (l .&. mask_lo(f))) : U32)

def cleared(+h: U32, +l: U32, +f: U32) -> F64:
  F64{(h .&. U32.not(mask_hi(f)) : U32), (l .&. U32.not(mask_lo(f)) : U32)}

def bumped(bump: Bool, +h: U32, +l: U32, +ah: U32, +al: U32, +f: U32) -> F64:
  match bump:
    case True{}:
      cleared(FW.add_hi(h, l, ah, al), (l + al : U32), f)
    case False{}:
      cleared(h, l, f)

def integral(small: Bool, +h: U32, +l: U32, +tiny: F64, +whole: F64) -> F64:
  match small:
    case True{}:
      tiny
    case False{}:
      pick((exp_field(h) >= 1075 : U32), pick(is_nan_words(h, l), quiet_words(h, l), F64{h, l}), whole)

def unquieted(+h: U32, +l: U32, +x: F64) -> F64:
  pick(is_nan_words(h, l), F64{h, l}, x)

def small_value(+h: U32, one_up: Bool) -> F64:
  F64{((h .&. sign_mask()) .|. FW.pick(one_up, 1072693248, 0) : U32), 0}

def trunc_words(+h: U32, +l: U32) -> F64:
  integral((exp_field(h) < 1023 : U32), h, l, small_value(h, False{}), cleared(h, l, (1075 - exp_field(h) : U32)))

def floor_words(+h: U32, +l: U32) -> F64:
  +f = (1075 - exp_field(h) : U32)
  +neg = (h >= sign_mask() : U32)
  +whole = bumped(neg && Bool.not(U32.is_zero(frac_bits(h, l, f))), h, l, unit_hi(f), unit_lo(f), f)
  integral((exp_field(h) < 1023 : U32), h, l, small_value(h, neg && Bool.not(is_zero_words(h, l))), whole)

def ceil_words(+h: U32, +l: U32) -> F64:
  +f = (1075 - exp_field(h) : U32)
  +pos = (h < sign_mask() : U32)
  +whole = bumped(pos && Bool.not(U32.is_zero(frac_bits(h, l, f))), h, l, unit_hi(f), unit_lo(f), f)
  integral((exp_field(h) < 1023 : U32), h, l, small_value(h, pos && Bool.not(is_zero_words(h, l))), whole)

def round_words(+h: U32, +l: U32) -> F64:
  +f = (1075 - exp_field(h) : U32)
  +half_f = (f - 1 : U32)
  +whole = bumped(True{}, h, l, unit_hi(half_f), unit_lo(half_f), f)
  integral((exp_field(h) < 1023 : U32), h, l, small_value(h, U32.is_eq(exp_field(h), 1022)), whole)

def rint_words(+h: U32, +l: U32) -> F64:
  +f = (1075 - exp_field(h) : U32)
  +odd = (FW.shr_lo(h, l, f) .&. 1 : U32)
  +half_f = (f - 1 : U32)
  +add_lo = (unit_lo(half_f) - 1 + odd : U32)
  +add_hi = (unit_hi(half_f) - Bool.to_u32((unit_lo(half_f) < (1 - odd : U32) : U32)) : U32)
  +whole = bumped(True{}, h, l, add_hi, add_lo, f)
  +above_half = U32.is_eq(exp_field(h), 1022) && Bool.not(U32.is_zero(((h .&. frac_mask()) .|. l : U32)))
  integral((exp_field(h) < 1023 : U32), h, l, small_value(h, above_half), whole)

# C floor, ceil, trunc, round (halves away from zero), quieting a NaN, and rint (halves to even), which returns a
# NaN unchanged (as glibc does).
def floor(x: F64) -> F64:
  match x:
    case F64{+h, +l}:
      floor_words(h, l)

def ceil(x: F64) -> F64:
  match x:
    case F64{+h, +l}:
      ceil_words(h, l)

def trunc(x: F64) -> F64:
  match x:
    case F64{+h, +l}:
      trunc_words(h, l)

def round(x: F64) -> F64:
  match x:
    case F64{+h, +l}:
      round_words(h, l)

def rint(x: F64) -> F64:
  match x:
    case F64{+h, +l}:
      unquieted(h, l, rint_words(h, l))

def clamp_shift(+n: U32) -> U32:
  +neg = (n >= 2147483648 : U32)
  FW.pick(neg, FW.pick(((n + 4096) < 2147483648 : U32), n, 4294963200), FW.pick((n > 4096 : U32), 4096, n))

def ldexp_finite(+h: U32, +l: U32, +n: U32) -> F64:
  +sh = norm_sig_hi(h, l)
  +sl = norm_sig_lo(h, l)
  round_pack(sign_of(h), (norm_exp(h, l) + clamp_shift(n) - 1 : U32), ((sh << 10n) .|. (sl >> 22n) : U32), (sl << 10n : U32))

def ldexp_words(passthrough: Bool, +h: U32, +l: U32, +n: U32) -> F64:
  match passthrough:
    case True{}:
      pick(is_nan_words(h, l), quiet_words(h, l), F64{h, l})
    case False{}:
      ldexp_finite(h, l, n)

# C ldexp(x, n) for an int n (two's complement U32), rounded to nearest even.
def ldexp(x: F64, +n: U32) -> F64:
  match x:
    case F64{+h, +l}:
      ldexp_words(is_special_exp(h) || is_zero_words(h, l), h, l, n)

# C frexp: x = m * 2^e with |m| in [0.5, 1); zero, inf and NaN give (x, 0).
type Frexp is Data:
  Frexp{m: F64, e: U32}

def frexp_words(passthrough: Bool, +h: U32, +l: U32) -> Frexp:
  match passthrough:
    case True{}:
      Frexp{pick(is_nan_words(h, l), quiet_words(h, l), F64{h, l}), 0}
    case False{}:
      +sh = norm_sig_hi(h, l)
      Frexp{F64{((h .&. sign_mask()) .|. 1071644672 .|. (sh .&. frac_mask()) : U32), norm_sig_lo(h, l)}, (norm_exp(h, l) - 1022 : U32)}

def frexp(x: F64) -> Frexp:
  match x:
    case F64{+h, +l}:
      frexp_words(is_special_exp(h) || is_zero_words(h, l), h, l)
