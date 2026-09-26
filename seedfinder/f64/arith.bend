import Base
import ./word.bend as F64Word
import ./repr.bend as F64Repr

# IEEE-754 double arithmetic on F64Repr.F64, round to nearest even, bit-exact with x86-64 SSE2 (addsd, subsd, mulsd,
# divsd, sqrtsd): subnormals, signed zeros, infinities, and NaNs (the first NaN operand quieted; invalid
# operations give the default NaN 0xFFF8000000000000).

def nan_or_inf(+ah: U32, +al: U32, +bh: U32, +bl: U32, invalid: Bool, +inf_sign: U32) -> F64Repr.F64:
  F64Repr.pick(F64Repr.is_nan_words(ah, al) || F64Repr.is_nan_words(bh, bl), F64Repr.first_nan(ah, al, bh, bl),
    F64Repr.pick(invalid, F64Repr.nan(), F64Repr.signed_inf(inf_sign)))

def add_near(+sign: U32, +exv: U32, +sh: U32, +sl: U32) -> F64Repr.F64:
  +k = (F64Word.clz64(sh, sl) - 1 : U32)
  F64Repr.pick(U32.is_zero((sh .|. sl : U32)), F64Repr.zero(), F64Repr.round_pack(sign, (exv - k - 1 : U32), F64Word.shl_hi(sh, sl, k), F64Word.shl(sl, k)))

# F64Repr.round_pack with its normal-range test made here, so the short normal rounding stays inline in the caller.
def packed(normal: Bool, +sign: U32, +exp: U32, +sh: U32, +sl: U32) -> F64Repr.F64:
  match normal:
    case True{}:
      F64Repr.round_normal(sign, exp, sh, sl)
    case False{}:
      F64Repr.round_general(sign, exp, sh, sl)

def add_far(+sub: Bool, +sign: U32, +exv: U32, +sh: U32, +sl: U32) -> F64Repr.F64:
  +top = (sh >= 2147483648 : U32)
  +low = (sh < 1073741824 : U32) && sub
  +nh = F64Word.pick(top, (sh >> 1n : U32), F64Word.pick(low, ((sh << 1n) .|. (sl >> 31n) : U32), sh))
  +nl = F64Word.pick(top, ((sl >> 1n) .|. (sh << 31n) .|. (sl .&. 1) : U32), F64Word.pick(low, (sl << 1n : U32), sl))
  +exp = (exv - 1 + Bool.to_u32(top) - Bool.to_u32(low) : U32)
  packed((exp < 2045 : U32), sign, exp, nh, nl)

def add_aligned(near: Bool, +sub: Bool, +sign: U32, +exv: U32, +sh: U32, +sl: U32) -> F64Repr.F64:
  match near:
    case True{}:
      add_near(sign, exv, sh, sl)
    case False{}:
      add_far(sub, sign, exv, sh, sl)

# y shifted right by d with the lost bits jammed into the lowest bit.
def aligned(near: Bool, +yh: U32, +yl: U32, +d: U32) -> F64Word.W64:
  match near:
    case True{}:
      +k = U32.to_nat((d .&. 31 : U32))
      +up = U32.to_nat(((31 - d) .&. 31 : U32))
      F64Word.W64{(yh >> k : U32), ((yl >> k) .|. ((yh << 1n) << up) .|. F64Word.nonzero(((yl << 1n) << up : U32)) : U32)}
    case False{}:
      F64Word.W64{F64Word.shr_hi(yh, d), F64Word.shr_jam_lo(yh, yl, d)}

def add_summed(+sub: Bool, +sign: U32, +exv: U32, +xh2: U32, +xl2: U32, y: F64Word.W64) -> F64Repr.F64:
  match y:
    case F64Word.W64{+ayh, +ayl}:
      +sh = F64Word.pick(sub, F64Word.sub_hi(xh2, xl2, ayh, ayl), F64Word.add_hi(xh2, xl2, ayh, ayl))
      +sl = F64Word.pick(sub, (xl2 - ayl : U32), (xl2 + ayl : U32))
      add_aligned(sub && (sh < 536870912 : U32), sub, sign, exv, sh, sl)

def add_sorted(+xh: U32, +xl: U32, +yh: U32, +yl: U32) -> F64Repr.F64:
  +sx = F64Repr.sign_of(xh)
  +sub = Bool.not(U32.is_eq(sx, F64Repr.sign_of(yh)))
  +ex = F64Repr.exp_field(xh)
  +ey = F64Repr.exp_field(yh)
  +exv = F64Word.pick(U32.is_zero(ex), 1, ex)
  +fxh = ((xh .&. F64Repr.frac_mask()) .|. F64Word.pick(U32.is_zero(ex), 0, F64Repr.hidden_bit()) : U32)
  +fyh = ((yh .&. F64Repr.frac_mask()) .|. F64Word.pick(U32.is_zero(ey), 0, F64Repr.hidden_bit()) : U32)
  +xh2 = ((fxh << 10n) .|. (xl >> 22n) : U32)
  +xl2 = (xl << 10n : U32)
  +yh2 = ((fyh << 10n) .|. (yl >> 22n) : U32)
  +yl2 = (yl << 10n : U32)
  +d = (exv - F64Word.pick(U32.is_zero(ey), 1, ey) : U32)
  add_summed(sub, sx, exv, xh2, xl2, aligned((d < 32 : U32), yh2, yl2, d))

def add_finite(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  +ma = (ah .&. F64Repr.abs_mask() : U32)
  +mb = (bh .&. F64Repr.abs_mask() : U32)
  +a_first = (ma > mb : U32) || (U32.is_eq(ma, mb) && (al >= bl : U32))
  add_sorted(F64Word.pick(a_first, ah, bh), F64Word.pick(a_first, al, bl), F64Word.pick(a_first, bh, ah), F64Word.pick(a_first, bl, al))

def add_route(special: Bool, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  match special:
    case True{}:
      +both_inf = F64Repr.is_inf_words(ah, al) && F64Repr.is_inf_words(bh, bl)
      +clash = both_inf && Bool.not(U32.is_eq(F64Repr.sign_of(ah), F64Repr.sign_of(bh)))
      nan_or_inf(ah, al, bh, bl, clash, F64Repr.sign_of(F64Word.pick(F64Repr.is_inf_words(ah, al), ah, bh)))
    case False{}:
      add_finite(ah, al, bh, bl)

def add_words(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  add_route(F64Repr.is_special_exp(ah) || F64Repr.is_special_exp(bh), ah, al, bh, bl)

def add(a: F64Repr.F64, b: F64Repr.F64) -> F64Repr.F64:
  match a:
    case F64Repr.F64{+ah, +al}:
      match b:
        case F64Repr.F64{+bh, +bl}:
          add_words(ah, al, bh, bl)

def sub(a: F64Repr.F64, b: F64Repr.F64) -> F64Repr.F64:
  match a:
    case F64Repr.F64{+ah, +al}:
      match b:
        case F64Repr.F64{+bh, +bl}:
          add_words(ah, al, (bh .^. F64Word.pick(F64Repr.is_nan_words(bh, bl), 0, F64Repr.sign_mask()) : U32), bl)

def mul_product(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +exp: U32, +a1: U32, +a0: U32, +b1: U32, +b0: U32) -> F64Repr.F64:
  +p01l = (a0 * b1 : U32)
  +p10l = (a1 * b0 : U32)
  +p11l = (a1 * b1 : U32)
  +p00h = mulhi(a0, b0)
  +p01h = mulhi(a0, b1)
  +p10h = mulhi(a1, b0)
  +p11h = mulhi(a1, b1)
  +t1a = (p00h + p01l : U32)
  +t1 = (t1a + p10l : U32)
  +c1 = (F64Word.carry(t1a, p00h) + F64Word.carry(t1, t1a) : U32)
  +t2a = (p11l + p01h : U32)
  +t2b = (t2a + p10h : U32)
  +t2 = (t2b + c1 : U32)
  +w3 = (p11h + F64Word.carry(t2a, p11l) + F64Word.carry(t2b, t2a) + F64Word.carry(t2, t2b) : U32)
  +w2 = (t2 .|. F64Word.nonzero((t1 .|. (a0 * b0 : U32) : U32)) : U32)
  +low = (w3 < 1073741824 : U32)
  F64Repr.round_pack(sign, (exp - Bool.to_u32(low) : U32), F64Word.pick(low, ((w3 << 1n) .|. (w2 >> 31n) : U32), w3),
    F64Word.pick(low, (w2 << 1n : U32), w2))

def mul_core(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +ea: U32, +ah: U32, +al: U32, +eb: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  mul_product(~mulhi, sign, (ea + eb - 1023 : U32), ((ah << 10n) .|. (al >> 22n) : U32), (al << 10n : U32),
    ((bh << 11n) .|. (bl >> 21n) : U32), (bl << 11n : U32))

def mul_normalized(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  mul_core(~mulhi, sign, F64Repr.norm_exp(ah, al), F64Repr.norm_sig_hi(ah, al), F64Repr.norm_sig_lo(ah, al), F64Repr.norm_exp(bh, bl),
    F64Repr.norm_sig_hi(bh, bl), F64Repr.norm_sig_lo(bh, bl))

def mul_special(~mulhi: @+a:U32 -> @+b:U32 -> U32, infinite: Bool, +sign: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  match infinite:
    case True{}:
      nan_or_inf(ah, al, bh, bl, F64Repr.is_zero_words(ah, al) || F64Repr.is_zero_words(bh, bl), sign)
    case False{}:
      F64Repr.pick(F64Repr.is_zero_words(ah, al) || F64Repr.is_zero_words(bh, bl), F64Repr.signed_zero(sign), mul_normalized(~mulhi, sign, ah, al, bh, bl))

def mul_route(~mulhi: @+a:U32 -> @+b:U32 -> U32, special: Bool, +sign: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  match special:
    case True{}:
      mul_special(~mulhi, F64Repr.is_special_exp(ah) || F64Repr.is_special_exp(bh), sign, ah, al, bh, bl)
    case False{}:
      mul_core(~mulhi, sign, F64Repr.exp_field(ah), ((ah .&. F64Repr.frac_mask()) .|. F64Repr.hidden_bit() : U32), al, F64Repr.exp_field(bh),
        ((bh .&. F64Repr.frac_mask()) .|. F64Repr.hidden_bit() : U32), bl)

def is_edge_exp(+h: U32) -> Bool:
  +e = F64Repr.exp_field(h)
  U32.is_zero(e) || U32.is_eq(e, 2047)

def mul_words(~mulhi: @+a:U32 -> @+b:U32 -> U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  mul_route(~mulhi, is_edge_exp(ah) || is_edge_exp(bh), F64Repr.sign_of((ah .^. bh : U32)), ah, al, bh, bl)

# mul with the 32x32 high product mulhi (F64Word.mul_hi, or F64Word.mul_hi_nat in compiled hot loops: same values).
def mul_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, a: F64Repr.F64, b: F64Repr.F64) -> F64Repr.F64:
  match a:
    case F64Repr.F64{+ah, +al}:
      match b:
        case F64Repr.F64{+bh, +bl}:
          mul_words(~mulhi, ah, al, bh, bl)

def mul(a: F64Repr.F64, b: F64Repr.F64) -> F64Repr.F64:
  mul_by(~F64Word.mul_hi, a, b)

def recip_refine(~mulhi: @+a:U32 -> @+b:U32 -> U32, +bh: U32, +bl: U32, +r1: U32) -> U32:
  +m1l = (bh * r1 : U32)
  +p1 = (m1l + mulhi(bl, r1) : U32)
  +p2 = (mulhi(bh, r1) + F64Word.carry(p1, m1l) : U32)
  +b0 = F64Word.nonzero((bl * r1 : U32))
  +e1 = (0 - p1 - b0 : U32)
  +e2 = (2147483648 - p2 - F64Word.nonzero((p1 .|. b0 : U32)) : U32)
  (r1 + (mulhi(r1, ((e2 << 28n) .|. (e1 >> 4n) : U32)) >> 27n) : U32)

# floor(2^95 / B) or one less, for a 64-bit B = (bh, bl) with its top bit set: a hardware 32/16 seed and two Newton
# steps (bounds checked exhaustively over bh).
def recip(~mulhi: @+a:U32 -> @+b:U32 -> U32, +bh: U32, +bl: U32) -> U32:
  +r0 = ((4294967295 / ((bh >> 16n) + 1)) << 15n : U32)
  +p_lo = (bh * r0 : U32)
  +e_hi = (2147483648 - mulhi(bh, r0) - F64Word.nonzero(p_lo) : U32)
  +e_lo = (0 - p_lo : U32)
  recip_refine(~mulhi, bh, bl, (r0 + mulhi(r0, ((e_hi << 1n) .|. (e_lo >> 31n) : U32)) - 2 : U32))

def rem_step(+r2: U32, +r1: U32, +r0: U32, +y2: U32, +y1: U32, +y0: U32, +k: U32) -> F64Word.W128:
  +ge = Bool.not(F64Word.lt128_words(0, r2, r1, r0, 0, y2, y1, y0))
  +b0 = F64Word.borrow(r0, y0)
  +d1 = (r1 - y1 : U32)
  +b1 = (F64Word.borrow(r1, y1) + F64Word.borrow(d1, b0) : U32)
  F64Word.W128{F64Word.pick(ge, k, 0), F64Word.pick(ge, (r2 - y2 - b1 : U32), r2), F64Word.pick(ge, (d1 - b0 : U32), r1), F64Word.pick(ge, (r0 - y0 : U32), r0)}

def rem_add(+q: U32, +k: U32, s: F64Word.W128) -> F64Word.W128:
  match s:
    case F64Word.W128{+k1, +r2, +r1, +r0}:
      F64Word.W128{(q + k + k1 : U32), r2, r1, r0}

def rem_last(+bh: U32, +bl: U32, +q: U32, s: F64Word.W128) -> F64Word.W128:
  match s:
    case F64Word.W128{+k, +r2, +r1, +r0}:
      rem_add(q, k, rem_step(r2, r1, r0, 0, bh, bl, 1))

# Reduces a remainder r < 4B by B = (bh, bl): the quotient digit q grows by floor(r / B), r becomes r mod B.
def rem_reduce(+q: U32, +r2: U32, +r1: U32, +r0: U32, +bh: U32, +bl: U32) -> F64Word.W128:
  rem_last(bh, bl, q, rem_step(r2, r1, r0, (bh >> 31n : U32), ((bh << 1n) .|. (bl >> 31n) : U32), (bl << 1n : U32), 2))

def div_exact(+sign: U32, +exp: U32, +bh: U32, +bl: U32, +z1: U32, s: F64Word.W128) -> F64Repr.F64:
  match s:
    case F64Word.W128{+z2, +r2, +r1, +r0}:
      F64Repr.round_pack(sign, exp, z1, (z2 .|. F64Word.nonzero((r2 .|. r1 .|. r0 : U32)) : U32))

def div_slow(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +exp: U32, +bh: U32, +bl: U32, +z1: U32, +rh: U32, +rl: U32, +z2: U32) -> F64Repr.F64:
  +q0 = (z2 * bl : U32)
  +q1a = (z2 * bh : U32)
  +q1 = (q1a + mulhi(z2, bl) : U32)
  +q2 = (mulhi(z2, bh) + F64Word.carry(q1, q1a) : U32)
  +b0 = F64Word.nonzero(q0)
  +d1 = (rl - q1 : U32)
  +b1 = (F64Word.borrow(rl, q1) + F64Word.borrow(d1, b0) : U32)
  div_exact(sign, exp, bh, bl, z1, rem_reduce(z2, (rh - q2 - b1 : U32), (d1 - b0 : U32), (0 - q0 : U32), bh, bl))

def div_round(~mulhi: @+a:U32 -> @+b:U32 -> U32, slow: Bool, +sign: U32, +exp: U32, +bh: U32, +bl: U32, +z1: U32, +rh: U32, +rl: U32, +z2: U32) -> F64Repr.F64:
  match slow:
    case True{}:
      div_slow(~mulhi, sign, exp, bh, bl, z1, rh, rl, z2)
    case False{}:
      F64Repr.round_pack(sign, exp, z1, z2)

def div_second(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +exp: U32, +bh: U32, +bl: U32, +r: U32, s: F64Word.W128) -> F64Repr.F64:
  match s:
    case F64Word.W128{+z1, r2, +rh, +rl}:
      +m = mulhi(rl, r)
      +lo = ((rh * r) + m : U32)
      +z2 = ((((mulhi(rh, r) + F64Word.carry(lo, m)) << 1n)) .|. (lo >> 31n) : U32)
      +near_half = (((512 - (z2 .&. 1023)) .&. 1023) < 4 : U32)
      div_round(~mulhi, near_half || (exp >= 2147483648 : U32), sign, exp, bh, bl, z1, rh, rl, z2)

def div_first(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +exp: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32, +r: U32) -> F64Repr.F64:
  +z1 = mulhi(ah, r)
  +p0 = (z1 * bl : U32)
  +p1a = (z1 * bh : U32)
  +p1 = (p1a + mulhi(z1, bl) : U32)
  +p2 = (mulhi(z1, bh) + F64Word.carry(p1, p1a) : U32)
  +n1 = ((ah << 31n) .|. (al >> 1n) : U32)
  +n0 = (al << 31n : U32)
  +b0 = F64Word.borrow(n0, p0)
  +d1 = (n1 - p1 : U32)
  +b1 = (F64Word.borrow(n1, p1) + F64Word.borrow(d1, b0) : U32)
  div_second(~mulhi, sign, exp, bh, bl, r, rem_reduce(z1, ((ah >> 1n) - p2 - b1 : U32), (d1 - b0 : U32), (n0 - p0 : U32), bh, bl))

def div_scaled(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +exp: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  div_first(~mulhi, sign, exp, ah, al, bh, bl, recip(~mulhi, bh, bl))

# The significands a, b (53 bits, bit 52 set) scaled to A = a << 10 or 11 and B = b << 11, so Z = A * 2^63 / B is
# in [2^62, 2^63). Z = z1 * 2^32 + z2 from the reciprocal, z1 exact after a remainder reduction and z2 at most 3
# below the truth; only a z2 within 3 of a rounding midpoint (or a subnormal result) needs the exact remainder.
def div_core(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +ea: U32, +ah: U32, +al: U32, +eb: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  +less = F64Word.lt64(ah, al, bh, bl)
  +k = F64Word.pick(less, 11, 10)
  div_scaled(~mulhi, sign, (ea - eb + 1022 - Bool.to_u32(less) : U32), F64Word.shl_hi(ah, al, k), F64Word.shl(al, k),
    ((bh << 11n) .|. (bl >> 21n) : U32), (bl << 11n : U32))

def pack_quotient(+sign: U32, +exp: U32, q: F64Repr.F64) -> F64Repr.F64:
  match q:
    case F64Repr.F64{+qh, +ql}:
      F64Repr.round_pack(sign, exp, qh, ql)

def div_normalized(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  div_core(~mulhi, sign, F64Repr.norm_exp(ah, al), F64Repr.norm_sig_hi(ah, al), F64Repr.norm_sig_lo(ah, al), F64Repr.norm_exp(bh, bl),
    F64Repr.norm_sig_hi(bh, bl), F64Repr.norm_sig_lo(bh, bl))

def div_zero_or_normalized(~mulhi: @+a:U32 -> @+b:U32 -> U32, +sign: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  +a_zero = F64Repr.is_zero_words(ah, al)
  +b_zero = F64Repr.is_zero_words(bh, bl)
  F64Repr.pick(a_zero && b_zero, F64Repr.nan(), F64Repr.pick(a_zero, F64Repr.signed_zero(sign), F64Repr.pick(b_zero, F64Repr.signed_inf(sign),
    div_normalized(~mulhi, sign, ah, al, bh, bl))))

def div_special(~mulhi: @+a:U32 -> @+b:U32 -> U32, infinite: Bool, +sign: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  match infinite:
    case True{}:
      +b_inf = F64Repr.is_inf_words(bh, bl)
      +finite_over_inf = b_inf && Bool.not(F64Repr.is_special_exp(ah))
      F64Repr.pick(finite_over_inf && Bool.not(F64Repr.is_nan_words(bh, bl)), F64Repr.signed_zero(sign),
        nan_or_inf(ah, al, bh, bl, b_inf && F64Repr.is_inf_words(ah, al), sign))
    case False{}:
      div_zero_or_normalized(~mulhi, sign, ah, al, bh, bl)

def div_route(~mulhi: @+a:U32 -> @+b:U32 -> U32, special: Bool, +sign: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  match special:
    case True{}:
      div_special(~mulhi, F64Repr.is_special_exp(ah) || F64Repr.is_special_exp(bh), sign, ah, al, bh, bl)
    case False{}:
      div_core(~mulhi, sign, F64Repr.exp_field(ah), ((ah .&. F64Repr.frac_mask()) .|. F64Repr.hidden_bit() : U32), al, F64Repr.exp_field(bh),
        ((bh .&. F64Repr.frac_mask()) .|. F64Repr.hidden_bit() : U32), bl)

def div_words(~mulhi: @+a:U32 -> @+b:U32 -> U32, +ah: U32, +al: U32, +bh: U32, +bl: U32) -> F64Repr.F64:
  div_route(~mulhi, is_edge_exp(ah) || is_edge_exp(bh), F64Repr.sign_of((ah .^. bh : U32)), ah, al, bh, bl)

# div with the 32x32 high product mulhi (F64Word.mul_hi, or F64Word.mul_hi_nat in compiled hot loops: same values).
def div_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, a: F64Repr.F64, b: F64Repr.F64) -> F64Repr.F64:
  match a:
    case F64Repr.F64{+ah, +al}:
      match b:
        case F64Repr.F64{+bh, +bl}:
          div_words(~mulhi, ah, al, bh, bl)

def div(a: F64Repr.F64, b: F64Repr.F64) -> F64Repr.F64:
  div_by(~F64Word.mul_hi, a, b)

def sqrt_loop(n: Nat, +xh: U32, +xl: U32, +rh: U32, +rl: U32, +qh: U32, +ql: U32) -> F64Repr.F64:
  match n:
    case 0n:
      F64Repr.F64{((qh << 9n) .|. (ql >> 23n) : U32), ((ql << 9n) .|. F64Word.nonzero((rh .|. rl : U32)) : U32)}
    case 1n+p:
      +sh = ((rh << 2n) .|. (rl >> 30n) : U32)
      +sl = ((rl << 2n) .|. (xh >> 30n) : U32)
      +th = ((qh << 2n) .|. (ql >> 30n) : U32)
      +tl = ((ql << 2n) .|. 1 : U32)
      +ge = F64Word.le64(th, tl, sh, sl)
      sqrt_loop(p, ((xh << 2n) .|. (xl >> 30n) : U32), (xl << 2n : U32), F64Word.pick(ge, F64Word.sub_hi(sh, sl, th, tl), sh),
        F64Word.pick(ge, (sl - tl : U32), sl), ((qh << 1n) .|. (ql >> 31n) : U32), ((ql << 1n) .|. Bool.to_u32(ge) : U32))

def sqrt_serial(+e: U32, +sh: U32, +sl: U32) -> F64Repr.F64:
  +even_exp = U32.is_zero((e .&. 1 : U32))
  +k = F64Word.pick(even_exp, 11, 10)
  +t = F64Word.pick(even_exp, 55, 54)
  pack_quotient(0, (((e + 2048 - 1075 - t) >> 1n) + 51 : U32),
    sqrt_loop(54n, F64Word.shl_hi(sh, sl, k), F64Word.shl(sl, k), 0, 0, 0, 0))

def sqrt_pick(slow: Bool, +e: U32, +sh: U32, +sl: U32, +exp: U32, +zh: U32, +zl: U32) -> F64Repr.F64:
  match slow:
    case True{}:
      sqrt_serial(e, sh, sl)
    case False{}:
      F64Repr.round_pack(0, exp, zh, zl)

def sqrt_second(~mulhi: @+a:U32 -> @+b:U32 -> U32, +e: U32, +sh: U32, +sl: U32, +exp: U32, +s: U32, +rh: U32, +rl: U32) -> F64Repr.F64:
  +z2 = mulhi(((rh << 31n) .|. (rl >> 1n) : U32), recip(~mulhi, s, 0))
  +zl = ((s << 31n) + z2 : U32)
  sqrt_pick((((zl + 3 - 512) .&. 1023) <= 6 : U32), e, sh, sl, exp, ((s >> 1n) + F64Word.carry(zl, z2) : U32), zl)

def sqrt_up(~mulhi: @+a:U32 -> @+b:U32 -> U32, +e: U32, +sh: U32, +sl: U32, +exp: U32, +mh: U32, +ml: U32, +s: U32, +fh: U32, +fl: U32) -> F64Repr.F64:
  +rh = F64Word.sub_hi(mh, ml, fh, fl)
  +rl = (ml - fl : U32)
  +up = F64Word.lt64((s >> 31n : U32), (s << 1n : U32), rh, rl)
  +th = (rh - (s >> 31n) - F64Word.borrow(rl, (s << 1n : U32)) - F64Word.borrow((rl - (s << 1n) : U32), 1) : U32)
  sqrt_second(~mulhi, e, sh, sl, exp, (s + Bool.to_u32(up) : U32), F64Word.pick(up, th, rh), F64Word.pick(up, (rl - (s << 1n) - 1 : U32), rl))

def sqrt_down(~mulhi: @+a:U32 -> @+b:U32 -> U32, n: Nat, +e: U32, +sh: U32, +sl: U32, +exp: U32, +mh: U32, +ml: U32, +s: U32, +fh: U32, +fl: U32) -> F64Repr.F64:
  match n:
    case 0n:
      sqrt_up(~mulhi, e, sh, sl, exp, mh, ml, s, fh, fl)
    case 1n+p:
      +down = F64Word.lt64(mh, ml, fh, fl)
      +gh = F64Word.sub_hi(fh, fl, (s >> 31n : U32), (s << 1n : U32))
      +gl = (fl - (s << 1n) : U32)
      sqrt_down(~mulhi, p, e, sh, sl, exp, mh, ml, (s - Bool.to_u32(down) : U32), F64Word.pick(down, F64Word.add_hi(gh, gl, 0, 1), fh),
        F64Word.pick(down, (gl + 1 : U32), fl))

def sqrt_top(~mulhi: @+a:U32 -> @+b:U32 -> U32, +e: U32, +sh: U32, +sl: U32, +exp: U32, +mh: U32, +ml: U32, +s16: U32) -> F64Repr.F64:
  +q = ((((mh - (s16 * s16)) << 15n) .|. (ml >> 17n)) / s16 : U32)
  +s32 = ((s16 << 16n) + q : U32)
  +s = F64Word.pick((s32 < q : U32), 4294967295, s32)
  sqrt_down(~mulhi, 2n, e, sh, sl, exp, mh, ml, s, mulhi(s, s), (s * s : U32))

def heron(+x: U32, +s: U32) -> U32:
  ((s + (x / s)) >> 1n : U32)

# M = sig << (72 + odd exponent) in [2^124, 2^126) and Z = floor(sqrt(M)) in [2^62, 2^63): Heron on the top word
# (hardware division), a Newton step to the exact 32-bit root s of the top 64 bits, then the second digit from the
# remainder and the division reciprocal of s. The estimate is within 3 of the truth, so only a Z within 3 of a
# rounding midpoint takes the exact bit-serial path.
def sqrt_core(~mulhi: @+a:U32 -> @+b:U32 -> U32, +e: U32, +sh: U32, +sl: U32) -> F64Repr.F64:
  +odd = Bool.to_u32(U32.is_zero((e .&. 1 : U32)))
  +k = (10 + odd : U32)
  +mh = F64Word.shl_hi(sh, sl, k)
  +s1 = heron(mh, heron(mh, (23171 + (mh / 92682) : U32)))
  +s2 = F64Word.pick((s1 > 65535 : U32), 65535, s1)
  +s16 = (s2 - Bool.to_u32(((s2 * s2) > mh : U32)) : U32)
  sqrt_top(~mulhi, e, sh, sl, (((e + 1025 - odd) >> 1n) - 2 : U32), mh, F64Word.shl(sl, k), s16)

def sqrt_special(+h: U32, +l: U32) -> F64Repr.F64:
  F64Repr.pick(F64Repr.is_nan_words(h, l), F64Repr.quiet_words(h, l), F64Repr.pick(F64Repr.is_zero_words(h, l) || (h < F64Repr.sign_mask() : U32),
    F64Repr.F64{h, l}, F64Repr.nan()))

def sqrt_route(~mulhi: @+a:U32 -> @+b:U32 -> U32, special: Bool, +h: U32, +l: U32) -> F64Repr.F64:
  match special:
    case True{}:
      sqrt_special(h, l)
    case False{}:
      sqrt_core(~mulhi, F64Repr.norm_exp(h, l), F64Repr.norm_sig_hi(h, l), F64Repr.norm_sig_lo(h, l))

def sqrt_words(~mulhi: @+a:U32 -> @+b:U32 -> U32, +h: U32, +l: U32) -> F64Repr.F64:
  sqrt_route(~mulhi, F64Repr.is_special_exp(h) || F64Repr.is_zero_words(h, l) || (h >= F64Repr.sign_mask() : U32), h, l)

# sqrt with the 32x32 high product mulhi (F64Word.mul_hi, or F64Word.mul_hi_nat in compiled hot loops: same values).
def sqrt_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, x: F64Repr.F64) -> F64Repr.F64:
  match x:
    case F64Repr.F64{+h, +l}:
      sqrt_words(~mulhi, h, l)

def sqrt(x: F64Repr.F64) -> F64Repr.F64:
  sqrt_by(~F64Word.mul_hi, x)

def pick128(c: Bool, a: F64Word.W128, b: F64Word.W128) -> F64Word.W128:
  match c:
    case True{}:
      a
    case False{}:
      b

def fma_round(+sign: U32, +exp: U32, n: F64Word.W128) -> F64Repr.F64:
  match n:
    case F64Word.W128{+n3, +n2, +n1, +n0}:
      F64Repr.round_pack(sign, exp, n3, (n2 .|. F64Word.nonzero((n1 .|. n0 : U32)) : U32))

def fma_normalize(zero: Bool, +sign: U32, +e: U32, s: F64Word.W128) -> F64Repr.F64:
  match zero:
    case True{}:
      F64Repr.zero()
    case False{}:
      match s:
        case F64Word.W128{+s3, +s2, +s1, +s0}:
          +k = (F64Word.clz128(s3, s2, s1, s0) - 1 : U32)
          fma_round(sign, (e + 1 - k : U32), F64Word.shl128_words(s3, s2, s1, s0, k))

def fma_combine(sub: Bool, +sp: U32, +sc: U32, +e: U32, +x3: U32, +x2: U32, +x1: U32, +x0: U32, +y3: U32, +y2: U32,
    +y1: U32, +y0: U32) -> F64Repr.F64:
  match sub:
    case True{}:
      +lt = F64Word.lt128_words(x3, x2, x1, x0, y3, y2, y1, y0)
      +d = pick128(lt, F64Word.sub128_words(y3, y2, y1, y0, x3, x2, x1, x0), F64Word.sub128_words(x3, x2, x1, x0, y3, y2, y1, y0))
      fma_normalize(U32.is_zero(((x3 .^. y3) .|. (x2 .^. y2) .|. (x1 .^. y1) .|. (x0 .^. y0) : U32)), F64Word.pick(lt, sc, sp), e, d)
    case False{}:
      fma_normalize(False{}, sp, e, F64Word.add128_words(x3, x2, x1, x0, y3, y2, y1, y0))

def fma_aligned(+sp: U32, +sc: U32, +e: U32, x: F64Word.W128, y: F64Word.W128) -> F64Repr.F64:
  match x:
    case F64Word.W128{+x3, +x2, +x1, +x0}:
      match y:
        case F64Word.W128{+y3, +y2, +y1, +y0}:
          fma_combine(Bool.not(U32.is_eq(sp, sc)), sp, sc, e, x3, x2, x1, x0, y3, y2, y1, y0)

def fma_core(+sp: U32, +ep: U32, +sc: U32, +ec: U32, +x: F64Word.W128, +y: F64Word.W128) -> F64Repr.F64:
  +d = (ep - ec : U32)
  +c_first = (d >= 2147483648 : U32)
  fma_aligned(sp, sc, F64Word.pick(c_first, ec, ep), pick128(c_first, F64Word.shr128_jam(x, (0 - d : U32)), x),
    pick128(c_first, y, F64Word.shr128_jam(y, d)))

def fma_normal(+ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> F64Repr.F64:
  +a1 = F64Repr.norm_sig_hi(ah, al)
  +a0 = F64Repr.norm_sig_lo(ah, al)
  +b1 = F64Repr.norm_sig_hi(bh, bl)
  +b0 = F64Repr.norm_sig_lo(bh, bl)
  +c1 = F64Repr.norm_sig_hi(ch, cl)
  +c0 = F64Repr.norm_sig_lo(ch, cl)
  fma_core(F64Repr.sign_of((ah .^. bh : U32)), (F64Repr.norm_exp(ah, al) + F64Repr.norm_exp(bh, bl) - 1023 : U32), F64Repr.sign_of(ch),
    F64Repr.norm_exp(ch, cl), F64Word.mul128(((a1 << 10n) .|. (a0 >> 22n) : U32), (a0 << 10n : U32), ((b1 << 10n) .|. (b0 >> 22n) : U32),
    (b0 << 10n : U32)), F64Word.W128{((c1 << 8n) .|. (c0 >> 24n) : U32), (c0 << 8n : U32), 0, 0})

def fma_zero_product(+sp: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> F64Repr.F64:
  +product_zero = F64Repr.is_zero_words(ah, al) || F64Repr.is_zero_words(bh, bl)
  F64Repr.pick(product_zero, F64Repr.pick(F64Repr.is_zero_words(ch, cl), F64Repr.signed_zero((sp .&. F64Repr.sign_of(ch) : U32)), F64Repr.F64{ch, cl}),
    mul_words(~F64Word.mul_hi, ah, al, bh, bl))

def fma_finite_product(c_inf: Bool, +sp: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> F64Repr.F64:
  match c_inf:
    case True{}:
      F64Repr.F64{ch, cl}
    case False{}:
      fma_zero_product(sp, ah, al, bh, bl, ch, cl)

def fma_infinite(product_inf: Bool, +sp: U32, +ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> F64Repr.F64:
  match product_inf:
    case True{}:
      +clash = F64Repr.is_inf_words(ch, cl) && Bool.not(U32.is_eq(F64Repr.sign_of(ch), sp))
      F64Repr.pick(F64Repr.is_zero_words(ah, al) || F64Repr.is_zero_words(bh, bl) || clash, F64Repr.nan(), F64Repr.signed_inf(sp))
    case False{}:
      fma_finite_product(F64Repr.is_inf_words(ch, cl), sp, ah, al, bh, bl, ch, cl)

def fma_special(any_nan: Bool, +ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> F64Repr.F64:
  match any_nan:
    case True{}:
      F64Repr.pick(F64Repr.is_nan_words(ah, al) || F64Repr.is_nan_words(bh, bl), F64Repr.first_nan(ah, al, bh, bl), F64Repr.quiet_words(ch, cl))
    case False{}:
      fma_infinite(F64Repr.is_inf_words(ah, al) || F64Repr.is_inf_words(bh, bl), F64Repr.sign_of((ah .^. bh : U32)), ah, al, bh, bl, ch, cl)

def fma_route(special: Bool, +ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> F64Repr.F64:
  match special:
    case True{}:
      fma_special(F64Repr.is_nan_words(ah, al) || F64Repr.is_nan_words(bh, bl) || F64Repr.is_nan_words(ch, cl), ah, al, bh, bl, ch, cl)
    case False{}:
      fma_normal(ah, al, bh, bl, ch, cl)

def is_edge(+h: U32, +l: U32) -> Bool:
  F64Repr.is_special_exp(h) || F64Repr.is_zero_words(h, l)

def fma_words(+ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> F64Repr.F64:
  fma_route(is_edge(ah, al) || is_edge(bh, bl) || is_edge(ch, cl), ah, al, bh, bl, ch, cl)

# fma(a, b, c) = a*b + c with one rounding. NaN operands propagate (the first of a, b, c, quieted).
def fma(a: F64Repr.F64, b: F64Repr.F64, c: F64Repr.F64) -> F64Repr.F64:
  match a:
    case F64Repr.F64{+ah, +al}:
      match b:
        case F64Repr.F64{+bh, +bl}:
          match c:
            case F64Repr.F64{+ch, +cl}:
              fma_words(ah, al, bh, bl, ch, cl)
