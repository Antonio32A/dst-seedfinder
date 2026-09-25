import Base
import ../../f64/repr.bend as FR
import ../../f64/arith.bend as FA
import ../../f64/cmp.bend as FC
import ./ctypes.bend as VT

# Boost.Polygon 1.52 voronoi_robust_fpt.hpp: robust_fpt<double> (`RF`: value and relative error in ulps, both
# doubles, with Boost's operation order: `op=` forms add the error as re + (that.re + 1), the binary forms as
# (re + that.re) + 1), robust_dif<robust_fpt> (`RD`: positive and negative sums) and robust_sqrt_expr over
# extended_int / extended_exponent_fpt (eval1..eval4).

type RF is Data:
  RF{v: FR.F64, e: FR.F64}

type RD is Data:
  RD{pos: RF, neg: RF}

def rf(+v: FR.F64) -> RF:
  RF{v, FR.zero()}

def rf_err(+v: FR.F64, +e: FR.F64) -> RF:
  RF{v, e}

def rf_value(x: RF) -> FR.F64:
  match x:
    case RF{+v, _}:
      v

def rf_error(x: RF) -> FR.F64:
  match x:
    case RF{_, +e}:
      e

def is_pos(+x: FR.F64) -> Bool:
  FC.lt(FR.zero(), x)

def is_neg(+x: FR.F64) -> Bool:
  FC.lt(x, FR.zero())

def is_zero(+x: FR.F64) -> Bool:
  FC.eq(x, FR.zero())

def rf_is_neg(x: RF) -> Bool:
  is_neg(rf_value(x))

def rf_is_pos(x: RF) -> Bool:
  is_pos(rf_value(x))

def rf_is_zero(x: RF) -> Bool:
  is_zero(rf_value(x))

def plus_one(+x: FR.F64) -> FR.F64:
  FA.add(x, FR.one())

def rf_neg(x: RF) -> RF:
  match x:
    case RF{+v, +e}:
      RF{FR.neg(v), e}

def unnegated(+x: FR.F64) -> FR.F64:
  FR.pick(is_neg(x), FR.neg(x), x)

def cancel_error(+num: FR.F64, +sum: FR.F64) -> FR.F64:
  plus_one(unnegated(FA.div(num, sum)))

def same_signs(+a: FR.F64, +b: FR.F64) -> Bool:
  Bool.or(Bool.and(Bool.not(is_neg(a)), Bool.not(is_neg(b))), Bool.and(Bool.not(is_pos(a)), Bool.not(is_pos(b))))

def add_error(keep: Bool, +av: FR.F64, +ae: FR.F64, +bv: FR.F64, +be: FR.F64, +sum: FR.F64) -> FR.F64:
  match keep:
    case True{}:
      plus_one(FC.max(ae, be))
    case False{}:
      cancel_error(FA.sub(FA.mul(av, ae), FA.mul(bv, be)), sum)

def sub_error(keep: Bool, +av: FR.F64, +ae: FR.F64, +bv: FR.F64, +be: FR.F64, +dif: FR.F64) -> FR.F64:
  match keep:
    case True{}:
      plus_one(FC.max(ae, be))
    case False{}:
      cancel_error(FA.add(FA.mul(av, ae), FA.mul(bv, be)), dif)

# robust_fpt operator+ (and +=).
def rf_add(a: RF, b: RF) -> RF:
  match a:
    case RF{+av, +ae}:
      match b:
        case RF{+bv, +be}:
          +sum = FA.add(av, bv)
          RF{sum, add_error(same_signs(av, bv), av, ae, bv, be, sum)}

# robust_fpt operator- (and -=).
def rf_sub(a: RF, b: RF) -> RF:
  match a:
    case RF{+av, +ae}:
      match b:
        case RF{+bv, +be}:
          +dif = FA.sub(av, bv)
          RF{dif, sub_error(same_signs(av, FR.neg(bv)), av, ae, bv, be, dif)}

# robust_fpt operator*.
def rf_mul(a: RF, b: RF) -> RF:
  match a:
    case RF{+av, +ae}:
      match b:
        case RF{+bv, +be}:
          RF{FA.mul(av, bv), plus_one(FA.add(ae, be))}

# robust_fpt operator/.
def rf_div(a: RF, b: RF) -> RF:
  match a:
    case RF{+av, +ae}:
      match b:
        case RF{+bv, +be}:
          RF{FA.div(av, bv), plus_one(FA.add(ae, be))}

# robust_fpt operator*=.
def rf_mul_assign(a: RF, b: RF) -> RF:
  match a:
    case RF{+av, +ae}:
      match b:
        case RF{+bv, +be}:
          RF{FA.mul(av, bv), FA.add(ae, plus_one(be))}

# robust_fpt operator/=.
def rf_div_assign(a: RF, b: RF) -> RF:
  match a:
    case RF{+av, +ae}:
      match b:
        case RF{+bv, +be}:
          RF{FA.div(av, bv), FA.add(ae, plus_one(be))}

# robust_fpt::sqrt().
def rf_sqrt(a: RF) -> RF:
  match a:
    case RF{+v, +e}:
      RF{FA.sqrt(v), plus_one(FA.mul(e, FR.half()))}

def rd_zero() -> RD:
  RD{rf(FR.zero()), rf(FR.zero())}

# robust_dif::dif().
def rd_dif(d: RD) -> RF:
  match d:
    case RD{+p, +n}:
      rf_sub(p, n)

def rd_pos_value(d: RD) -> FR.F64:
  match d:
    case RD{+p, _}:
      rf_value(p)

def rd_neg_value(d: RD) -> FR.F64:
  match d:
    case RD{_, +n}:
      rf_value(n)

# robust_dif operator-().
def rd_negate(d: RD) -> RD:
  match d:
    case RD{+p, +n}:
      RD{n, p}

def rd_add_to(nonneg: Bool, +p: RF, +n: RF, +val: RF) -> RD:
  match nonneg:
    case True{}:
      RD{rf_add(p, val), n}
    case False{}:
      RD{p, rf_sub(n, val)}

# robust_dif += T.
def rd_add_rf(d: RD, +val: RF) -> RD:
  match d:
    case RD{+p, +n}:
      rd_add_to(Bool.not(rf_is_neg(val)), p, n, val)

def rd_sub_from(nonneg: Bool, +p: RF, +n: RF, +val: RF) -> RD:
  match nonneg:
    case True{}:
      RD{p, rf_add(n, val)}
    case False{}:
      RD{rf_sub(p, val), n}

# robust_dif -= T.
def rd_sub_rf(d: RD, +val: RF) -> RD:
  match d:
    case RD{+p, +n}:
      rd_sub_from(Bool.not(rf_is_neg(val)), p, n, val)

# robust_dif += robust_dif (and operator+ of two robust_difs).
def rd_add(a: RD, b: RD) -> RD:
  match a:
    case RD{+ap, +an}:
      match b:
        case RD{+bp, +bn}:
          RD{rf_add(ap, bp), rf_add(an, bn)}

# robust_dif -= robust_dif.
def rd_sub(a: RD, b: RD) -> RD:
  match a:
    case RD{+ap, +an}:
      match b:
        case RD{+bp, +bn}:
          RD{rf_add(ap, bn), rf_add(an, bp)}

def rd_scaled(nonneg: Bool, +p: RF, +n: RF, +val: RF) -> RD:
  match nonneg:
    case True{}:
      RD{rf_mul(p, val), rf_mul(n, val)}
    case False{}:
      RD{rf_mul(rf_neg(n), val), rf_mul(rf_neg(p), val)}

# operator*(robust_dif, T).
def rd_mul_rf(d: RD, +val: RF) -> RD:
  match d:
    case RD{+p, +n}:
      rd_scaled(Bool.not(rf_is_neg(val)), p, n, val)

def rf_scaled(nonneg: Bool, +p: RF, +n: RF, +val: RF) -> RD:
  match nonneg:
    case True{}:
      RD{rf_mul(val, p), rf_mul(val, n)}
    case False{}:
      RD{rf_mul(rf_neg(val), n), rf_mul(rf_neg(val), p)}

# operator*(T, robust_dif).
def rf_mul_rd(+val: RF, d: RD) -> RD:
  match d:
    case RD{+p, +n}:
      rf_scaled(Bool.not(rf_is_neg(val)), p, n, val)

def rd_divided(nonneg: Bool, +p: RF, +n: RF, +val: RF) -> RD:
  match nonneg:
    case True{}:
      RD{rf_div_assign(p, val), rf_div_assign(n, val)}
    case False{}:
      RD{rf_div_assign(n, rf_neg(val)), rf_div_assign(p, rf_neg(val))}

# robust_dif /= T.
def rd_div_assign(d: RD, +val: RF) -> RD:
  match d:
    case RD{+p, +n}:
      rd_divided(Bool.not(rf_is_neg(val)), p, n, val)

def rd_flip_if(flip: Bool, +d: RD) -> RD:
  Bool.pick(RD, flip, rd_negate(d), d)

# if (d.pos().fpv() < d.neg().fpv()) d = -d;
def rd_make_positive(+d: RD) -> RD:
  rd_flip_if(FC.lt(rd_pos_value(d), rd_neg_value(d)), d)

# The recompute test `x.ulp() > ULPS` (64).
def rf_needs_exact(x: RF) -> Bool:
  FC.lt(FR.F64{1078984704, 0}, rf_error(x))

def ef(b: VT.Big) -> VT.Efpt:
  VT.big_to_efpt(b)

def same_sign_efpt(+a: VT.Efpt, +b: VT.Efpt) -> Bool:
  Bool.or(Bool.and(Bool.not(VT.efpt_is_neg(a)), Bool.not(VT.efpt_is_neg(b))), Bool.and(Bool.not(VT.efpt_is_pos(a)), Bool.not(VT.efpt_is_pos(b))))

# robust_sqrt_expr::eval1: A0 * sqrt(B0).
def eval1(+a0: VT.Big, +b0: VT.Big) -> VT.Efpt:
  VT.efpt_mul(ef(a0), VT.efpt_sqrt(ef(b0)))

def sqr_times(+a: VT.Big, +b: VT.Big) -> VT.Big:
  VT.big_mul(VT.big_mul(a, a), b)

def eval2_join(same: Bool, +a: VT.Efpt, +b: VT.Efpt, +a0: VT.Big, +a1: VT.Big, +b0: VT.Big, +b1: VT.Big) -> VT.Efpt:
  match same:
    case True{}:
      VT.efpt_add(a, b)
    case False{}:
      VT.efpt_div(ef(VT.big_sub(sqr_times(a0, b0), sqr_times(a1, b1))), VT.efpt_sub(a, b))

# robust_sqrt_expr::eval2: A0 * sqrt(B0) + A1 * sqrt(B1).
def eval2(+a0: VT.Big, +a1: VT.Big, +b0: VT.Big, +b1: VT.Big) -> VT.Efpt:
  +a = eval1(a0, b0)
  +b = eval1(a1, b1)
  eval2_join(same_sign_efpt(a, b), a, b, a0, a1, b0, b1)

def eval3_join(same: Bool, +a: VT.Efpt, +b: VT.Efpt, +a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +b0: VT.Big, +b1: VT.Big, +b2: VT.Big) -> VT.Efpt:
  match same:
    case True{}:
      VT.efpt_add(a, b)
    case False{}:
      +ta3 = VT.big_sub(VT.big_add(sqr_times(a0, b0), sqr_times(a1, b1)), sqr_times(a2, b2))
      +ta4 = VT.big_mul_i32(VT.big_mul(a0, a1), 2)
      VT.efpt_div(eval2(ta3, ta4, VT.big_of_i32(1), VT.big_mul(b0, b1)), VT.efpt_sub(a, b))

# robust_sqrt_expr::eval3: A0 * sqrt(B0) + A1 * sqrt(B1) + A2 * sqrt(B2).
def eval3(+a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +b0: VT.Big, +b1: VT.Big, +b2: VT.Big) -> VT.Efpt:
  +a = eval2(a0, a1, b0, b1)
  +b = eval1(a2, b2)
  eval3_join(same_sign_efpt(a, b), a, b, a0, a1, a2, b0, b1, b2)

def eval4_join(same: Bool, +a: VT.Efpt, +b: VT.Efpt, +a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +a3: VT.Big, +b0: VT.Big, +b1: VT.Big, +b2: VT.Big, +b3: VT.Big) -> VT.Efpt:
  match same:
    case True{}:
      VT.efpt_add(a, b)
    case False{}:
      +ta0 = VT.big_sub(VT.big_sub(VT.big_add(sqr_times(a0, b0), sqr_times(a1, b1)), sqr_times(a2, b2)), sqr_times(a3, b3))
      +ta1 = VT.big_mul_i32(VT.big_mul(a0, a1), 2)
      +ta2 = VT.big_mul_i32(VT.big_mul(a2, a3), 4294967294)
      VT.efpt_div(eval3(ta0, ta1, ta2, VT.big_of_i32(1), VT.big_mul(b0, b1), VT.big_mul(b2, b3)), VT.efpt_sub(a, b))

# robust_sqrt_expr::eval4: the sum of four A_i * sqrt(B_i).
def eval4(+a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +a3: VT.Big, +b0: VT.Big, +b1: VT.Big, +b2: VT.Big, +b3: VT.Big) -> VT.Efpt:
  +a = eval2(a0, a1, b0, b1)
  +b = eval2(a2, a3, b2, b3)
  eval4_join(same_sign_efpt(a, b), a, b, a0, a1, a2, a3, b0, b1, b2, b3)
