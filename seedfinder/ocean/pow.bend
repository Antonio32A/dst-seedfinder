import Base
import ../f64/word.bend as FW
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/random.bend as FX
import ../data/blob.bend as B
import ../data/pow.bend as OWD

def f64_at(+xs: List<&2, U32>, +j: U32) -> FR.F64:
  FR.F64{B.word(xs, j), B.word(xs, (j + 2 : U32))}

def y() -> FR.F64:
  FR.F64{1072273817, 2576980378}

def neg_one() -> FR.F64:
  FR.F64{3220176896, 0}

def hi_of(x: FR.F64) -> U32:
  match x:
    case FR.F64{+h, l}:
      h

def lo_of(x: FR.F64) -> U32:
  match x:
    case FR.F64{h, +l}:
      l

def sar20(+x: U32) -> U32:
  ((x >> 20n) .|. FW.pick(U32.is_zero((x >> 31n : U32)), 0, 4294963200) : U32)

def glibc_log_hi_lo(+hi: FR.F64, +lo1: FR.F64, +t2: FR.F64, +r: FR.F64) -> FR.F64 & FR.F64:
  +ar = FA.mul(r, OWD.glibc_log_a0())
  +ar2 = FA.mul(r, ar)
  +ar3 = FA.mul(r, ar2)
  +q34 = FA.fma(r, OWD.glibc_log_a4(), OWD.glibc_log_a3())
  +q56 = FA.fma(r, OWD.glibc_log_a6(), OWD.glibc_log_a5())
  +q = FA.fma(ar2, FA.fma(q56, ar2, q34), FA.fma(r, OWD.glibc_log_a2(), OWD.glibc_log_a1()))
  +lo = FA.fma(ar3, q, FA.add(FA.add(lo1, FA.fma(ar, r, FR.neg(ar2))), FA.add(FA.sub(t2, hi), ar2)))
  (hi, lo)

def glibc_log_poly(+t1: FR.F64, +lo1: FR.F64, +r: FR.F64) -> FR.F64 & FR.F64:
  +t2 = FA.add(r, t1)
  +ar2 = FA.mul(r, FA.mul(r, OWD.glibc_log_a0()))
  glibc_log_hi_lo(FA.add(t2, ar2), FA.add(lo1, FA.add(FA.sub(t1, t2), r)), t2, r)

def glibc_log(+hi: U32, +lo: U32) -> FR.F64 & FR.F64:
  +tmp = (hi - 1072076117 : U32)
  +row = OWD.glibc_log_tab(((tmp >> 13n) .&. 127 : U32))
  +kd = FR.from_i32(sar20(tmp))
  +z : FR.F64 = FR.F64{(hi - (tmp .&. 4293918720) : U32), lo}
  glibc_log_poly(FA.fma(kd, OWD.glibc_ln2hi(), f64_at(row, 4)), FA.fma(kd, OWD.glibc_ln2lo(), f64_at(row, 8)),
    FA.fma(z, f64_at(row, 0), neg_one()))

def glibc_exp_poly(+rr: FR.F64, +row: List<&2, U32>, +top: U32) -> FR.F64:
  +r2 = FA.mul(rr, rr)
  +s = FA.fma(FA.fma(rr, OWD.glibc_exp_c5(), OWD.glibc_exp_c4()), FA.mul(r2, r2),
    FA.fma(FA.fma(rr, OWD.glibc_exp_c3(), OWD.glibc_exp_c2()), r2, FA.add(rr, f64_at(row, 0))))
  +scale : FR.F64 = FR.F64{(B.word(row, 4) + top : U32), B.word(row, 6)}
  FA.fma(scale, s, scale)

def glibc_exp(+ehi: FR.F64, +elo: FR.F64) -> FR.F64:
  +kd = FA.fma(ehi, OWD.glibc_invln2n(), OWD.glibc_shift())
  +ki = lo_of(kd)
  +km = FA.sub(kd, OWD.glibc_shift())
  +rr = FA.add(elo, FA.fma(km, OWD.glibc_negln2lon(), FA.fma(km, OWD.glibc_negln2hin(), ehi)))
  glibc_exp_poly(rr, OWD.glibc_exp_tab((ki .&. 127 : U32)), (ki << 13n : U32))

def glibc_exp_tail(+hi: FR.F64, +lo: FR.F64, +logy: FR.F64, +ehi: FR.F64) -> FR.F64:
  glibc_exp(ehi, FA.fma(y(), FA.add(FA.sub(hi, logy), lo), FA.fma(logy, y(), FR.neg(ehi))))

def glibc_tiny(tiny: Bool, +hi: FR.F64, +lo: FR.F64, +logy: FR.F64, +ehi: FR.F64) -> FR.F64:
  match tiny:
    case True{}:
      FA.add(ehi, FR.one())
    case False{}:
      glibc_exp_tail(hi, lo, logy, ehi)

def glibc_from_log(logs: FR.F64 & FR.F64) -> FR.F64:
  (+hi, +lo) = logs
  +logy = FA.add(hi, lo)
  +ehi = FA.mul(y(), logy)
  glibc_tiny((((hi_of(ehi) >> 20n) .&. 2047 : U32) < 969 : U32), hi, lo, logy, ehi)

def glibc_pow(zero: Bool, +r: FR.F64) -> FR.F64:
  match zero:
    case True{}:
      FA.mul(r, r)
    case False{}:
      glibc_from_log(glibc_log(hi_of(r), lo_of(r)))

def w3(x: FW.W128) -> U32:
  match x:
    case FW.W128{+a, b, c, d}:
      a

def w2(x: FW.W128) -> U32:
  match x:
    case FW.W128{a, +b, c, d}:
      b

def w1(x: FW.W128) -> U32:
  match x:
    case FW.W128{a, b, +c, d}:
      c

def w0(x: FW.W128) -> U32:
  match x:
    case FW.W128{a, b, c, +d}:
      d

def pick128(c: Bool, a: FW.W128, b: FW.W128) -> FW.W128:
  match c:
    case True{}:
      a
    case False{}:
      b

def add128(+a: FW.W128, +b: FW.W128) -> FW.W128:
  FW.add128_words(w3(a), w2(a), w1(a), w0(a), w3(b), w2(b), w1(b), w0(b))

def sub128(+a: FW.W128, +b: FW.W128) -> FW.W128:
  FW.sub128_words(w3(a), w2(a), w1(a), w0(a), w3(b), w2(b), w1(b), w0(b))

def lt128(+a: FW.W128, +b: FW.W128) -> Bool:
  FW.lt128_words(w3(a), w2(a), w1(a), w0(a), w3(b), w2(b), w1(b), w0(b))

def top(+w: U32) -> FW.W128:
  FW.W128{w, 0, 0, 0}

def small(+w: U32) -> FW.W128:
  FW.W128{0, 0, 0, w}

def negative(+x: FW.W128) -> Bool:
  Bool.not(U32.is_zero((w3(x) >> 31n : U32)))

def signed(+neg: Bool, +x: FW.W128) -> FW.W128:
  pick128(neg, sub128(small(0), x), x)

def magnitude(+x: FW.W128) -> FW.W128:
  signed(negative(x), x)

def shr128(+x: FW.W128, +d: U32) -> FW.W128:
  +q = (d >> 5n : U32)
  +r = (d .&. 31 : U32)
  FW.W128{FW.shr_word(3, q, r, w3(x), w2(x), w1(x), w0(x)), FW.shr_word(2, q, r, w3(x), w2(x), w1(x), w0(x)),
    FW.shr_word(1, q, r, w3(x), w2(x), w1(x), w0(x)), FW.shr_word(0, q, r, w3(x), w2(x), w1(x), w0(x))}

def shl128(+x: FW.W128, +k: U32) -> FW.W128:
  FW.shl128_words(w3(x), w2(x), w1(x), w0(x), k)

def high_sum(+x: FW.W128, +y: FW.W128, +z: FW.W128, +h: FW.W128) -> FW.W128:
  +s = add128(x, y)
  +s2 = add128(s, FW.W128{0, 0, w3(z), w2(z)})
  +c = (Bool.to_u32(lt128(s, x)) + Bool.to_u32(lt128(s2, s)) : U32)
  add128(h, FW.W128{0, c, w3(s2), w2(s2)})

def mul_hi128(+a: FW.W128, +b: FW.W128) -> FW.W128:
  high_sum(FW.mul128(w3(a), w2(a), w1(b), w0(b)), FW.mul128(w1(a), w0(a), w3(b), w2(b)),
    FW.mul128(w1(a), w0(a), w1(b), w0(b)), FW.mul128(w3(a), w2(a), w3(b), w2(b)))

def mul_hi64(+a: FW.W128, +u: FW.W128) -> FW.W128:
  +lo = FW.mul128(w1(a), w0(a), w1(u), w0(u))
  add128(FW.mul128(w3(a), w2(a), w1(u), w0(u)), FW.W128{0, 0, w3(lo), w2(lo)})

def mul_small(+a: FW.W128, +k: U32) -> FW.W128:
  +lo = FW.mul128(w1(a), w0(a), 0, k)
  +hi = FW.mul128(w3(a), w2(a), 0, k)
  add128(FW.W128{w1(hi), w0(hi), 0, 0}, lo)

def bits128(+x: FW.W128) -> U32:
  (128 - FW.clz128(w3(x), w2(x), w1(x), w0(x)) : U32)

def round_drop(+x: FW.W128, +d: U32) -> FW.W128:
  +lsb = (w0(shr128(x, d)) .&. 1 : U32)
  +bias = add128(sub128(shl128(small(1), (d - 1 : U32)), small(1)), small(lsb))
  shl128(shr128(add128(x, bias), d), d)

def round_to(+x: FW.W128, +keep: U32) -> FW.W128:
  +n = bits128(x)
  pick128((n > keep : U32), round_drop(x, (n - keep : U32)), x)

def w128_units(+a: U32, +b: U32, +c: U32, +d: U32, +e: U32, +f: U32, +g: U32, +h: U32) -> FW.W128:
  FW.W128{((a << 16n) .|. b : U32), ((c << 16n) .|. d : U32), ((e << 16n) .|. f : U32), ((g << 16n) .|. h : U32)}

def w128_at(+xs: List<&2, U32>, +j: U32) -> FW.W128:
  +rest = B.drop(xs, j)
  w128_units(B.at(rest, 0), B.at(rest, 1), B.at(rest, 2), B.at(rest, 3), B.at(rest, 4), B.at(rest, 5), B.at(rest, 6),
    B.at(rest, 7))

def log_horner(cs: List<&2, FW.W128>, +u_neg: Bool, +u: FW.W128, +p: FW.W128) -> FW.W128:
  match cs:
    case Nil{}:
      p
    case Con{+c, rest}:
      +step = mul_hi64(p, u)
      log_horner(rest, u_neg, u, pick128(u_neg, add128(c, step), sub128(c, step)))

def exp_horner(cs: List<&2, FW.W128>, +w_neg: Bool, +w: FW.W128, +p: FW.W128) -> FW.W128:
  match cs:
    case Nil{}:
      p
    case Con{+c, rest}:
      +step = mul_hi128(p, w)
      exp_horner(rest, w_neg, w, pick128(w_neg, sub128(c, step), add128(c, step)))

def series(~horner: @xs:List<&2, FW.W128> -> @+n:Bool -> @+v:FW.W128 -> @+p:FW.W128 -> FW.W128,
  cs: List<&2, FW.W128>, +neg: Bool, +v: FW.W128) -> FW.W128:
  match cs:
    case Nil{}:
      small(0)
    case Con{+c, rest}:
      horner(rest, neg, v, c)

def log1p_scaled(+zs: FW.W128, +c: U32) -> FW.W128:
  +prod = FW.mul128(w1(zs), w0(zs), 0, c)
  +u_neg = U32.is_zero(w2(prod))
  +u = magnitude(sub128(prod, FW.W128{0, 1, 0, 0}))
  +p = series(~log_horner, OWD.win_log_series(), u_neg, u)
  signed(u_neg, shr128(mul_hi64(p, u), 5))

def win_neg_log(+hi: U32, +lo: U32) -> FW.W128:
  +tmp = (hi - 1072076117 : U32)
  +row = OWD.win_log_tab(((tmp >> 12n) .&. 255 : U32))
  +iz = (hi - (tmp .&. 4293918720) : U32)
  +wide = U32.is_eq((iz >> 20n : U32), 1023)
  +mant : FW.W128 = FW.W128{0, 0, ((iz .&. 1048575) .|. 1048576 : U32), lo}
  +zs = pick128(wide, shl128(mant, 1), mant)
  +log1p = log1p_scaled(zs, B.at(row, 0))
  +l = sub128(add128(w128_at(row, 1), log1p), mul_small(OWD.win_ln2_122(), (0 - sar20(tmp) : U32)))
  sub128(small(0), l)

def rounded_whole(+t64: FW.W128) -> U32:
  +whole = (w3(t64) >> 24n : U32)
  +part : FW.W128 = FW.W128{(w3(t64) .&. 16777215 : U32), w2(t64), w1(t64), w0(t64)}
  +half = top(8388608)
  +up = lt128(half, part) || (Bool.not(lt128(part, half)) && Bool.not(U32.is_zero((whole .&. 1 : U32))))
  (whole + Bool.to_u32(up) : U32)

def sar(+x: U32, +k: U32) -> U32:
  (FW.shr(x, k) .|. FW.pick(U32.is_zero((x >> 31n : U32)), 0, U32.not(FW.shr(4294967295, k))) : U32)

def exp_scaled(+f: FW.W128) -> FW.W128:
  +j = sar(w3(add128(f, top(8192))), 14)
  +g = sub128(f, top((j << 14n : U32)))
  +g_neg = negative(g)
  +w = mul_hi128(shl128(magnitude(g), 9), OWD.win_ln2_128())
  +em = mul_hi128(series(~exp_horner, OWD.win_exp_series(), g_neg, shr128(w, 1)), w)
  +p = mul_hi128(w128_at(OWD.win_exp_coarse((sar(j, 5) + 16 : U32)), 0), w128_at(OWD.win_exp_fine((j .&. 31 : U32)), 0))
  sub128(add128(p, signed(g_neg, mul_hi128(p, em))), top(1073741824))

def pack_result(+m: FW.W128, +exponent: U32) -> FR.F64:
  +carry = (w1(m) >> 21n : U32)
  +mm = shr128(m, carry)
  FR.F64{(((exponent + carry : U32) << 20n) .|. (w1(mm) .&. 1048575) : U32), w0(mm)}

def win_finish(+e: FW.W128, +whole: U32) -> FR.F64:
  +s = add128(top(1073741824), signed(negative(e), round_to(magnitude(e), 64)))
  +big = Bool.to_u32((w3(s) >= 1073741824 : U32))
  pack_result(shr128(round_to(s, 53), (73 + big : U32)), (1022 + big - whole : U32))

def win_split(+t64: FW.W128, +whole: U32) -> FR.F64:
  +f = sub128(top((whole << 24n : U32)), t64)
  win_finish(exp_scaled(signed(negative(f), round_to(magnitude(f), 53))), whole)

def win_model(+hi: U32, +lo: U32) -> FR.F64:
  +t64 = round_to(mul_hi128(OWD.win_k_126(), win_neg_log(hi, lo)), 64)
  win_split(t64, rounded_whole(t64))

def bump(+x: FR.F64, +delta: U32) -> FR.F64:
  +l = (lo_of(x) + delta : U32)
  +up = Bool.to_u32(U32.is_zero(l) && U32.is_eq(delta, 1))
  +down = Bool.to_u32(U32.is_eq(l, 4294967295) && U32.is_eq(delta, 4294967295))
  FR.F64{(hi_of(x) + up - down : U32), l}

def exception_delta(xs: List<&2, U32>, +low: U32) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{+e, rest}:
      FW.pick(U32.is_eq((e .&. 524287 : U32), low), FW.pick(U32.is_zero((e >> 19n : U32)), 4294967295, 1),
        exception_delta(rest, low))

def win_output(+x: U32, +model: FR.F64) -> FR.F64:
  bump(model, exception_delta(OWD.win_exceptions((x >> 19n : U32)), (x .&. 524287 : U32)))

def win_edge(edge: Bool, +r: FR.F64, +x: U32) -> FR.F64:
  match edge:
    case True{}:
      r
    case False{}:
      win_output(x, win_model(hi_of(r), lo_of(r)))

def output_of(+r: FR.F64) -> U32:
  +shift = (1075 - (hi_of(r) >> 20n) : U32)
  +m : FW.W128 = FW.W128{0, 0, ((hi_of(r) .&. 1048575) .|. 1048576 : U32), lo_of(r)}
  w0(shr128(add128(sub128(shl128(m, 32), m), shl128(small(1), (shift - 1 : U32))), shift))

def same_bits(+a: FR.F64, +b: FR.F64) -> Bool:
  U32.is_eq(hi_of(a), hi_of(b)) && U32.is_eq(lo_of(a), lo_of(b))

def is_edge(+r: FR.F64) -> Bool:
  (U32.is_zero(hi_of(r)) && U32.is_zero(lo_of(r))) || same_bits(r, FR.one())

def win_model_only(edge: Bool, +r: FR.F64) -> FR.F64:
  match edge:
    case True{}:
      r
    case False{}:
      win_model(hi_of(r), lo_of(r))

def win_apply(apply: Bool, +x: U32, +model: FR.F64) -> FR.F64:
  match apply:
    case True{}:
      win_output(x, model)
    case False{}:
      model

def win_pow(+r: FR.F64) -> FR.F64:
  +x = output_of(r)
  +edge = is_edge(r)
  win_apply(same_bits(FX.from_output(x), r) && Bool.not(edge), x, win_model_only(edge, r))

def platform_pow(windows: Bool, +r: FR.F64) -> FR.F64:
  match windows:
    case True{}:
      win_pow(r)
    case False{}:
      glibc_pow(FR.is_zero(r), r)

def platform_model(windows: Bool, +r: FR.F64) -> FR.F64:
  match windows:
    case True{}:
      win_model_only(is_edge(r), r)
    case False{}:
      glibc_pow(FR.is_zero(r), r)

# pow(r, 0.8) as the game's C library computes it, for 0 <= r <= 1: glibc 2.41's __ieee754_pow_fma on Linux,
# MSVCR90 9.00.30729.9635's x87 pow on Windows (exact on AMD Zen 3 for every r = x / 4294967295.0; any other r gets
# the correctly rounded fyl2x/f2xm1 model).
def pow_08(+windows: Bool, +r: FR.F64) -> FR.F64:
  platform_pow(windows, r)

def output_pow(windows: Bool, +x: U32) -> FR.F64:
  match windows:
    case True{}:
      win_edge(U32.is_zero(x) || U32.is_eq(x, 4294967295), FX.from_output(x), x)
    case False{}:
      glibc_pow(U32.is_zero(x), FX.from_output(x))

# pow(math.random(), 0.8) for the PCG32 output x behind math.random() (r = x / 4294967295.0).
def pow_08_of_output(+windows: Bool, +x: U32) -> FR.F64:
  output_pow(windows, x)

# pow_08 without the Windows exception table (OWD.win_exceptions costs ~33 s and ~3.6 GB per build): Linux is the
# same; Windows is the correctly rounded fyl2x/f2xm1 model, 1 ulp off MSVCR90 for 48,395 of the 2^32 PCG outputs.
def pow_08_model(+windows: Bool, +r: FR.F64) -> FR.F64:
  platform_model(windows, r)
