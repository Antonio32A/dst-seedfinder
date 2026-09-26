import Base
import ../f64/word.bend as F64Word
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/random.bend as F64Random
import ../data/blob.bend as Blob
import ../data/pow.bend as PowData

def f64_at(+xs: List<&2, U32>, +j: U32) -> F64Repr.F64:
  F64Repr.F64{Blob.word(xs, j), Blob.word(xs, (j + 2 : U32))}

def y() -> F64Repr.F64:
  F64Repr.F64{1072273817, 2576980378}

def neg_one() -> F64Repr.F64:
  F64Repr.F64{3220176896, 0}

def hi_of(x: F64Repr.F64) -> U32:
  match x:
    case F64Repr.F64{+h, l}:
      h

def lo_of(x: F64Repr.F64) -> U32:
  match x:
    case F64Repr.F64{h, +l}:
      l

def sar20(+x: U32) -> U32:
  ((x >> 20n) .|. F64Word.pick(U32.is_zero((x >> 31n : U32)), 0, 4294963200) : U32)

def glibc_log_hi_lo(+hi: F64Repr.F64, +lo1: F64Repr.F64, +t2: F64Repr.F64, +r: F64Repr.F64) -> F64Repr.F64 & F64Repr.F64:
  +ar = F64Arith.mul(r, PowData.glibc_log_a0())
  +ar2 = F64Arith.mul(r, ar)
  +ar3 = F64Arith.mul(r, ar2)
  +q34 = F64Arith.fma(r, PowData.glibc_log_a4(), PowData.glibc_log_a3())
  +q56 = F64Arith.fma(r, PowData.glibc_log_a6(), PowData.glibc_log_a5())
  +q = F64Arith.fma(ar2, F64Arith.fma(q56, ar2, q34), F64Arith.fma(r, PowData.glibc_log_a2(), PowData.glibc_log_a1()))
  +lo = F64Arith.fma(ar3, q, F64Arith.add(F64Arith.add(lo1, F64Arith.fma(ar, r, F64Repr.neg(ar2))), F64Arith.add(F64Arith.sub(t2, hi), ar2)))
  (hi, lo)

def glibc_log_poly(+t1: F64Repr.F64, +lo1: F64Repr.F64, +r: F64Repr.F64) -> F64Repr.F64 & F64Repr.F64:
  +t2 = F64Arith.add(r, t1)
  +ar2 = F64Arith.mul(r, F64Arith.mul(r, PowData.glibc_log_a0()))
  glibc_log_hi_lo(F64Arith.add(t2, ar2), F64Arith.add(lo1, F64Arith.add(F64Arith.sub(t1, t2), r)), t2, r)

def glibc_log(+hi: U32, +lo: U32) -> F64Repr.F64 & F64Repr.F64:
  +tmp = (hi - 1072076117 : U32)
  +row = PowData.glibc_log_tab(((tmp >> 13n) .&. 127 : U32))
  +kd = F64Repr.from_i32(sar20(tmp))
  +z : F64Repr.F64 = F64Repr.F64{(hi - (tmp .&. 4293918720) : U32), lo}
  glibc_log_poly(F64Arith.fma(kd, PowData.glibc_ln2hi(), f64_at(row, 4)), F64Arith.fma(kd, PowData.glibc_ln2lo(), f64_at(row, 8)),
    F64Arith.fma(z, f64_at(row, 0), neg_one()))

def glibc_exp_poly(+rr: F64Repr.F64, +row: List<&2, U32>, +top: U32) -> F64Repr.F64:
  +r2 = F64Arith.mul(rr, rr)
  +s = F64Arith.fma(F64Arith.fma(rr, PowData.glibc_exp_c5(), PowData.glibc_exp_c4()), F64Arith.mul(r2, r2),
    F64Arith.fma(F64Arith.fma(rr, PowData.glibc_exp_c3(), PowData.glibc_exp_c2()), r2, F64Arith.add(rr, f64_at(row, 0))))
  +scale : F64Repr.F64 = F64Repr.F64{(Blob.word(row, 4) + top : U32), Blob.word(row, 6)}
  F64Arith.fma(scale, s, scale)

def glibc_exp(+ehi: F64Repr.F64, +elo: F64Repr.F64) -> F64Repr.F64:
  +kd = F64Arith.fma(ehi, PowData.glibc_invln2n(), PowData.glibc_shift())
  +ki = lo_of(kd)
  +km = F64Arith.sub(kd, PowData.glibc_shift())
  +rr = F64Arith.add(elo, F64Arith.fma(km, PowData.glibc_negln2lon(), F64Arith.fma(km, PowData.glibc_negln2hin(), ehi)))
  glibc_exp_poly(rr, PowData.glibc_exp_tab((ki .&. 127 : U32)), (ki << 13n : U32))

def glibc_exp_tail(+hi: F64Repr.F64, +lo: F64Repr.F64, +logy: F64Repr.F64, +ehi: F64Repr.F64) -> F64Repr.F64:
  glibc_exp(ehi, F64Arith.fma(y(), F64Arith.add(F64Arith.sub(hi, logy), lo), F64Arith.fma(logy, y(), F64Repr.neg(ehi))))

def glibc_tiny(tiny: Bool, +hi: F64Repr.F64, +lo: F64Repr.F64, +logy: F64Repr.F64, +ehi: F64Repr.F64) -> F64Repr.F64:
  match tiny:
    case True{}:
      F64Arith.add(ehi, F64Repr.one())
    case False{}:
      glibc_exp_tail(hi, lo, logy, ehi)

def glibc_from_log(logs: F64Repr.F64 & F64Repr.F64) -> F64Repr.F64:
  (+hi, +lo) = logs
  +logy = F64Arith.add(hi, lo)
  +ehi = F64Arith.mul(y(), logy)
  glibc_tiny((((hi_of(ehi) >> 20n) .&. 2047 : U32) < 969 : U32), hi, lo, logy, ehi)

def glibc_pow(zero: Bool, +r: F64Repr.F64) -> F64Repr.F64:
  match zero:
    case True{}:
      F64Arith.mul(r, r)
    case False{}:
      glibc_from_log(glibc_log(hi_of(r), lo_of(r)))

def w3(x: F64Word.W128) -> U32:
  match x:
    case F64Word.W128{+a, b, c, d}:
      a

def w2(x: F64Word.W128) -> U32:
  match x:
    case F64Word.W128{a, +b, c, d}:
      b

def w1(x: F64Word.W128) -> U32:
  match x:
    case F64Word.W128{a, b, +c, d}:
      c

def w0(x: F64Word.W128) -> U32:
  match x:
    case F64Word.W128{a, b, c, +d}:
      d

def pick128(c: Bool, a: F64Word.W128, b: F64Word.W128) -> F64Word.W128:
  match c:
    case True{}:
      a
    case False{}:
      b

def add128(+a: F64Word.W128, +b: F64Word.W128) -> F64Word.W128:
  F64Word.add128_words(w3(a), w2(a), w1(a), w0(a), w3(b), w2(b), w1(b), w0(b))

def sub128(+a: F64Word.W128, +b: F64Word.W128) -> F64Word.W128:
  F64Word.sub128_words(w3(a), w2(a), w1(a), w0(a), w3(b), w2(b), w1(b), w0(b))

def lt128(+a: F64Word.W128, +b: F64Word.W128) -> Bool:
  F64Word.lt128_words(w3(a), w2(a), w1(a), w0(a), w3(b), w2(b), w1(b), w0(b))

def top(+w: U32) -> F64Word.W128:
  F64Word.W128{w, 0, 0, 0}

def small(+w: U32) -> F64Word.W128:
  F64Word.W128{0, 0, 0, w}

def negative(+x: F64Word.W128) -> Bool:
  Bool.not(U32.is_zero((w3(x) >> 31n : U32)))

def signed(+neg: Bool, +x: F64Word.W128) -> F64Word.W128:
  pick128(neg, sub128(small(0), x), x)

def magnitude(+x: F64Word.W128) -> F64Word.W128:
  signed(negative(x), x)

def shr128(+x: F64Word.W128, +d: U32) -> F64Word.W128:
  +q = (d >> 5n : U32)
  +r = (d .&. 31 : U32)
  F64Word.W128{F64Word.shr_word(3, q, r, w3(x), w2(x), w1(x), w0(x)), F64Word.shr_word(2, q, r, w3(x), w2(x), w1(x), w0(x)),
    F64Word.shr_word(1, q, r, w3(x), w2(x), w1(x), w0(x)), F64Word.shr_word(0, q, r, w3(x), w2(x), w1(x), w0(x))}

def shl128(+x: F64Word.W128, +k: U32) -> F64Word.W128:
  F64Word.shl128_words(w3(x), w2(x), w1(x), w0(x), k)

def high_sum(+x: F64Word.W128, +y: F64Word.W128, +z: F64Word.W128, +h: F64Word.W128) -> F64Word.W128:
  +s = add128(x, y)
  +s2 = add128(s, F64Word.W128{0, 0, w3(z), w2(z)})
  +c = (Bool.to_u32(lt128(s, x)) + Bool.to_u32(lt128(s2, s)) : U32)
  add128(h, F64Word.W128{0, c, w3(s2), w2(s2)})

def mul_hi128(+a: F64Word.W128, +b: F64Word.W128) -> F64Word.W128:
  high_sum(F64Word.mul128(w3(a), w2(a), w1(b), w0(b)), F64Word.mul128(w1(a), w0(a), w3(b), w2(b)),
    F64Word.mul128(w1(a), w0(a), w1(b), w0(b)), F64Word.mul128(w3(a), w2(a), w3(b), w2(b)))

def mul_hi64(+a: F64Word.W128, +u: F64Word.W128) -> F64Word.W128:
  +lo = F64Word.mul128(w1(a), w0(a), w1(u), w0(u))
  add128(F64Word.mul128(w3(a), w2(a), w1(u), w0(u)), F64Word.W128{0, 0, w3(lo), w2(lo)})

def mul_small(+a: F64Word.W128, +k: U32) -> F64Word.W128:
  +lo = F64Word.mul128(w1(a), w0(a), 0, k)
  +hi = F64Word.mul128(w3(a), w2(a), 0, k)
  add128(F64Word.W128{w1(hi), w0(hi), 0, 0}, lo)

def bits128(+x: F64Word.W128) -> U32:
  (128 - F64Word.clz128(w3(x), w2(x), w1(x), w0(x)) : U32)

def round_drop(+x: F64Word.W128, +d: U32) -> F64Word.W128:
  +lsb = (w0(shr128(x, d)) .&. 1 : U32)
  +bias = add128(sub128(shl128(small(1), (d - 1 : U32)), small(1)), small(lsb))
  shl128(shr128(add128(x, bias), d), d)

def round_to(+x: F64Word.W128, +keep: U32) -> F64Word.W128:
  +n = bits128(x)
  pick128((n > keep : U32), round_drop(x, (n - keep : U32)), x)

def w128_units(+a: U32, +b: U32, +c: U32, +d: U32, +e: U32, +f: U32, +g: U32, +h: U32) -> F64Word.W128:
  F64Word.W128{((a << 16n) .|. b : U32), ((c << 16n) .|. d : U32), ((e << 16n) .|. f : U32), ((g << 16n) .|. h : U32)}

def w128_at(+xs: List<&2, U32>, +j: U32) -> F64Word.W128:
  +rest = Blob.drop(xs, j)
  w128_units(Blob.at(rest, 0), Blob.at(rest, 1), Blob.at(rest, 2), Blob.at(rest, 3), Blob.at(rest, 4), Blob.at(rest, 5), Blob.at(rest, 6),
    Blob.at(rest, 7))

def log_horner(cs: List<&2, F64Word.W128>, +u_neg: Bool, +u: F64Word.W128, +p: F64Word.W128) -> F64Word.W128:
  match cs:
    case Nil{}:
      p
    case Con{+c, rest}:
      +step = mul_hi64(p, u)
      log_horner(rest, u_neg, u, pick128(u_neg, add128(c, step), sub128(c, step)))

def exp_horner(cs: List<&2, F64Word.W128>, +w_neg: Bool, +w: F64Word.W128, +p: F64Word.W128) -> F64Word.W128:
  match cs:
    case Nil{}:
      p
    case Con{+c, rest}:
      +step = mul_hi128(p, w)
      exp_horner(rest, w_neg, w, pick128(w_neg, sub128(c, step), add128(c, step)))

def series(~horner: @xs:List<&2, F64Word.W128> -> @+n:Bool -> @+v:F64Word.W128 -> @+p:F64Word.W128 -> F64Word.W128,
  cs: List<&2, F64Word.W128>, +neg: Bool, +v: F64Word.W128) -> F64Word.W128:
  match cs:
    case Nil{}:
      small(0)
    case Con{+c, rest}:
      horner(rest, neg, v, c)

def log1p_scaled(+zs: F64Word.W128, +c: U32) -> F64Word.W128:
  +prod = F64Word.mul128(w1(zs), w0(zs), 0, c)
  +u_neg = U32.is_zero(w2(prod))
  +u = magnitude(sub128(prod, F64Word.W128{0, 1, 0, 0}))
  +p = series(~log_horner, PowData.win_log_series(), u_neg, u)
  signed(u_neg, shr128(mul_hi64(p, u), 5))

def win_neg_log(+hi: U32, +lo: U32) -> F64Word.W128:
  +tmp = (hi - 1072076117 : U32)
  +row = PowData.win_log_tab(((tmp >> 12n) .&. 255 : U32))
  +iz = (hi - (tmp .&. 4293918720) : U32)
  +wide = U32.is_eq((iz >> 20n : U32), 1023)
  +mant : F64Word.W128 = F64Word.W128{0, 0, ((iz .&. 1048575) .|. 1048576 : U32), lo}
  +zs = pick128(wide, shl128(mant, 1), mant)
  +log1p = log1p_scaled(zs, Blob.at(row, 0))
  +l = sub128(add128(w128_at(row, 1), log1p), mul_small(PowData.win_ln2_122(), (0 - sar20(tmp) : U32)))
  sub128(small(0), l)

def rounded_whole(+t64: F64Word.W128) -> U32:
  +whole = (w3(t64) >> 24n : U32)
  +part : F64Word.W128 = F64Word.W128{(w3(t64) .&. 16777215 : U32), w2(t64), w1(t64), w0(t64)}
  +half = top(8388608)
  +up = lt128(half, part) || (Bool.not(lt128(part, half)) && Bool.not(U32.is_zero((whole .&. 1 : U32))))
  (whole + Bool.to_u32(up) : U32)

def sar(+x: U32, +k: U32) -> U32:
  (F64Word.shr(x, k) .|. F64Word.pick(U32.is_zero((x >> 31n : U32)), 0, U32.not(F64Word.shr(4294967295, k))) : U32)

def exp_scaled(+f: F64Word.W128) -> F64Word.W128:
  +j = sar(w3(add128(f, top(8192))), 14)
  +g = sub128(f, top((j << 14n : U32)))
  +g_neg = negative(g)
  +w = mul_hi128(shl128(magnitude(g), 9), PowData.win_ln2_128())
  +em = mul_hi128(series(~exp_horner, PowData.win_exp_series(), g_neg, shr128(w, 1)), w)
  +p = mul_hi128(w128_at(PowData.win_exp_coarse((sar(j, 5) + 16 : U32)), 0), w128_at(PowData.win_exp_fine((j .&. 31 : U32)), 0))
  sub128(add128(p, signed(g_neg, mul_hi128(p, em))), top(1073741824))

def pack_result(+m: F64Word.W128, +exponent: U32) -> F64Repr.F64:
  +carry = (w1(m) >> 21n : U32)
  +mm = shr128(m, carry)
  F64Repr.F64{(((exponent + carry : U32) << 20n) .|. (w1(mm) .&. 1048575) : U32), w0(mm)}

def win_finish(+e: F64Word.W128, +whole: U32) -> F64Repr.F64:
  +s = add128(top(1073741824), signed(negative(e), round_to(magnitude(e), 64)))
  +big = Bool.to_u32((w3(s) >= 1073741824 : U32))
  pack_result(shr128(round_to(s, 53), (73 + big : U32)), (1022 + big - whole : U32))

def win_split(+t64: F64Word.W128, +whole: U32) -> F64Repr.F64:
  +f = sub128(top((whole << 24n : U32)), t64)
  win_finish(exp_scaled(signed(negative(f), round_to(magnitude(f), 53))), whole)

def win_model(+hi: U32, +lo: U32) -> F64Repr.F64:
  +t64 = round_to(mul_hi128(PowData.win_k_126(), win_neg_log(hi, lo)), 64)
  win_split(t64, rounded_whole(t64))

def bump(+x: F64Repr.F64, +delta: U32) -> F64Repr.F64:
  +l = (lo_of(x) + delta : U32)
  +up = Bool.to_u32(U32.is_zero(l) && U32.is_eq(delta, 1))
  +down = Bool.to_u32(U32.is_eq(l, 4294967295) && U32.is_eq(delta, 4294967295))
  F64Repr.F64{(hi_of(x) + up - down : U32), l}

def exception_delta(xs: List<&2, U32>, +low: U32) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{+e, rest}:
      F64Word.pick(U32.is_eq((e .&. 524287 : U32), low), F64Word.pick(U32.is_zero((e >> 19n : U32)), 4294967295, 1),
        exception_delta(rest, low))

def win_output(+x: U32, +model: F64Repr.F64) -> F64Repr.F64:
  bump(model, exception_delta(PowData.win_exceptions((x >> 19n : U32)), (x .&. 524287 : U32)))

def win_edge(edge: Bool, +r: F64Repr.F64, +x: U32) -> F64Repr.F64:
  match edge:
    case True{}:
      r
    case False{}:
      win_output(x, win_model(hi_of(r), lo_of(r)))

def output_of(+r: F64Repr.F64) -> U32:
  +shift = (1075 - (hi_of(r) >> 20n) : U32)
  +m : F64Word.W128 = F64Word.W128{0, 0, ((hi_of(r) .&. 1048575) .|. 1048576 : U32), lo_of(r)}
  w0(shr128(add128(sub128(shl128(m, 32), m), shl128(small(1), (shift - 1 : U32))), shift))

def same_bits(+a: F64Repr.F64, +b: F64Repr.F64) -> Bool:
  U32.is_eq(hi_of(a), hi_of(b)) && U32.is_eq(lo_of(a), lo_of(b))

def is_edge(+r: F64Repr.F64) -> Bool:
  (U32.is_zero(hi_of(r)) && U32.is_zero(lo_of(r))) || same_bits(r, F64Repr.one())

def win_model_only(edge: Bool, +r: F64Repr.F64) -> F64Repr.F64:
  match edge:
    case True{}:
      r
    case False{}:
      win_model(hi_of(r), lo_of(r))

def win_apply(apply: Bool, +x: U32, +model: F64Repr.F64) -> F64Repr.F64:
  match apply:
    case True{}:
      win_output(x, model)
    case False{}:
      model

def win_pow(+r: F64Repr.F64) -> F64Repr.F64:
  +x = output_of(r)
  +edge = is_edge(r)
  win_apply(same_bits(F64Random.from_output(x), r) && Bool.not(edge), x, win_model_only(edge, r))

def platform_pow(windows: Bool, +r: F64Repr.F64) -> F64Repr.F64:
  match windows:
    case True{}:
      win_pow(r)
    case False{}:
      glibc_pow(F64Repr.is_zero(r), r)

def platform_model(windows: Bool, +r: F64Repr.F64) -> F64Repr.F64:
  match windows:
    case True{}:
      win_model_only(is_edge(r), r)
    case False{}:
      glibc_pow(F64Repr.is_zero(r), r)

# pow(r, 0.8) as the game's C library computes it, for 0 <= r <= 1: glibc 2.41's __ieee754_pow_fma on Linux,
# MSVCR90 9.00.30729.9635's x87 pow on Windows (exact on AMD Zen 3 for every r = x / 4294967295.0; any other r gets
# the correctly rounded fyl2x/f2xm1 model).
def pow_08(+windows: Bool, +r: F64Repr.F64) -> F64Repr.F64:
  platform_pow(windows, r)

def output_pow(windows: Bool, +x: U32) -> F64Repr.F64:
  match windows:
    case True{}:
      win_edge(U32.is_zero(x) || U32.is_eq(x, 4294967295), F64Random.from_output(x), x)
    case False{}:
      glibc_pow(U32.is_zero(x), F64Random.from_output(x))

# pow(math.random(), 0.8) for the PCG32 output x behind math.random() (r = x / 4294967295.0).
def pow_08_of_output(+windows: Bool, +x: U32) -> F64Repr.F64:
  output_pow(windows, x)

# pow_08 without the Windows exception table (PowData.win_exceptions costs ~33 s and ~3.6 GB per build): Linux is the
# same; Windows is the correctly rounded fyl2x/f2xm1 model, 1 ulp off MSVCR90 for 48,395 of the 2^32 PCG outputs.
def pow_08_model(+windows: Bool, +r: F64Repr.F64) -> F64Repr.F64:
  platform_model(windows, r)
