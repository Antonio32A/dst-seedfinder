import Base
import ../../f64/word.bend as F64Word
import ../../f64/repr.bend as F64Repr
import ../../f64/arith.bend as F64Arith
import ./ctypes.bend as VoronoiTypes
import ./robust.bend as VoronoiRobust
import ./predicates.bend as VoronoiPredicates

# Boost.Polygon 1.52 mp_circle_formation_functor: the exact recomputation of a circle event's centre x, centre y
# and lower x, each only when its flag is set (Boost's rules for which values are refreshed together), with
# extended_int expressions evaluated in Boost's operator order and the sqrt expressions of robust.bend.

def times(+a: VoronoiTypes.Big, +b: VoronoiTypes.Big) -> VoronoiTypes.Big:
  VoronoiTypes.big_mul(a, b)

def plus(+a: VoronoiTypes.Big, +b: VoronoiTypes.Big) -> VoronoiTypes.Big:
  VoronoiTypes.big_add(a, b)

def minus(+a: VoronoiTypes.Big, +b: VoronoiTypes.Big) -> VoronoiTypes.Big:
  VoronoiTypes.big_sub(a, b)

def int(+x: U32) -> VoronoiTypes.Big:
  VoronoiTypes.big_of_i32(x)

def wide(+x: F64Word.W64) -> VoronoiTypes.Big:
  VoronoiTypes.big_of_i64(x)

def dif(+a: U32, +b: U32) -> VoronoiTypes.Big:
  wide(VoronoiTypes.dif32(a, b))

def sum(+a: U32, +b: U32) -> VoronoiTypes.Big:
  wide(VoronoiTypes.add64(VoronoiTypes.widen(a), VoronoiTypes.widen(b)))

def fpt(+b: VoronoiTypes.Big) -> F64Repr.F64:
  VoronoiTypes.big_to_f64(b)

def set_x(c: VoronoiPredicates.Circle, +v: F64Repr.F64) -> VoronoiPredicates.Circle:
  match c:
    case VoronoiPredicates.Circle{_, +y, +lx}:
      VoronoiPredicates.Circle{v, y, lx}

def set_y(c: VoronoiPredicates.Circle, +v: F64Repr.F64) -> VoronoiPredicates.Circle:
  match c:
    case VoronoiPredicates.Circle{+x, _, +lx}:
      VoronoiPredicates.Circle{x, v, lx}

def set_lx(c: VoronoiPredicates.Circle, +v: F64Repr.F64) -> VoronoiPredicates.Circle:
  match c:
    case VoronoiPredicates.Circle{+x, +y, _}:
      VoronoiPredicates.Circle{x, y, v}

def is_neg(+x: F64Repr.F64) -> Bool:
  VoronoiRobust.is_neg(x)

def sign_flip(c: Bool, +b: VoronoiTypes.Big) -> VoronoiTypes.Big:
  VoronoiTypes.big_negate_if(c, b)

def sqr_sum(+a: VoronoiTypes.Big, +b: VoronoiTypes.Big) -> VoronoiTypes.Big:
  plus(times(a, a), times(b, b))

type Ppp is Data:
  Ppp{dx0: VoronoiTypes.Big, dx1: VoronoiTypes.Big, dx2: VoronoiTypes.Big, dy0: VoronoiTypes.Big, dy1: VoronoiTypes.Big, dy2: VoronoiTypes.Big, n1: VoronoiTypes.Big, n2: VoronoiTypes.Big, inv: F64Repr.F64}

def ppp_negative_lower(nonneg: Bool, +cx: VoronoiTypes.Big, +sqr_r: VoronoiTypes.Big, +x: F64Repr.F64, +r: F64Repr.F64, +inv: F64Repr.F64) -> F64Repr.F64:
  match nonneg:
    case True{}:
      F64Repr.pick(is_neg(inv), F64Arith.sub(x, F64Arith.mul(r, inv)), F64Arith.add(x, F64Arith.mul(r, inv)))
    case False{}:
      F64Arith.div(F64Arith.mul(fpt(minus(times(cx, cx), sqr_r)), inv), F64Arith.add(fpt(cx), r))

def ppp_lower(go: Bool, c: VoronoiPredicates.Circle, +p: Ppp, +cx: VoronoiTypes.Big, +x: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      match p:
        case Ppp{+dx0, +dx1, +dx2, +dy0, +dy1, +dy2, _, _, +inv}:
          +sqr_r = times(times(sqr_sum(dx0, dy0), sqr_sum(dx1, dy1)), sqr_sum(dx2, dy2))
          +r = F64Arith.sqrt(fpt(sqr_r))
          set_lx(c, ppp_negative_lower(Bool.not(is_neg(x)), cx, sqr_r, x, r, inv))
    case False{}:
      c

def ppp_x(go: Bool, c: VoronoiPredicates.Circle, +p: Ppp, +rlx: Bool) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      match p:
        case Ppp{_, _, _, +dy0, +dy1, _, +n1, +n2, +inv}:
          +cx = minus(times(n1, dy1), times(n2, dy0))
          +x = F64Arith.mul(fpt(cx), inv)
          ppp_lower(rlx, set_x(c, x), p, cx, x)
    case False{}:
      c

def ppp_y(go: Bool, c: VoronoiPredicates.Circle, +p: Ppp) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      match p:
        case Ppp{+dx0, +dx1, _, _, _, _, +n1, +n2, +inv}:
          set_y(c, F64Arith.mul(fpt(minus(times(n2, dx0), times(n1, dx1))), inv))
    case False{}:
      c

def ppp_terms(+x1: U32, +y1: U32, +x2: U32, +y2: U32, +x3: U32, +y3: U32) -> Ppp:
  +dx0 = dif(x1, x2)
  +dx1 = dif(x2, x3)
  +dy0 = dif(y1, y2)
  +dy1 = dif(y2, y3)
  +inv = F64Arith.div(F64Repr.half(), fpt(minus(times(dx0, dy1), times(dx1, dy0))))
  +n1 = plus(times(dx0, sum(x1, x2)), times(dy0, sum(y1, y2)))
  +n2 = plus(times(dx1, sum(x2, x3)), times(dy1, sum(y2, y3)))
  Ppp{dx0, dx1, dif(x1, x3), dy0, dy1, dif(y1, y3), n1, n2, inv}

# mp_circle_formation_functor::ppp.
def ppp(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, c: VoronoiPredicates.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  +p = ppp_terms(VoronoiPredicates.site_x0(s1), VoronoiPredicates.site_y0(s1), VoronoiPredicates.site_x0(s2), VoronoiPredicates.site_y0(s2), VoronoiPredicates.site_x0(s3), VoronoiPredicates.site_y0(s3))
  ppp_y(rcy, ppp_x(rcx || rlx, c, p, rlx), p)

type Pps is Data:
  Pps{la: VoronoiTypes.Big, lb: VoronoiTypes.Big, seg: VoronoiTypes.Big, vx: VoronoiTypes.Big, vy: VoronoiTypes.Big, sx: VoronoiTypes.Big, sy: VoronoiTypes.Big, teta: VoronoiTypes.Big, denom: VoronoiTypes.Big, a: VoronoiTypes.Big, b: VoronoiTypes.Big}

def pps_terms(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Pps:
  +st = VoronoiPredicates.start(s3)
  +en = VoronoiPredicates.end(s3)
  +p1 = VoronoiPredicates.point1(s3)
  +x1 = VoronoiPredicates.site_x0(s1)
  +y1 = VoronoiPredicates.site_y0(s1)
  +x2 = VoronoiPredicates.site_x0(s2)
  +y2 = VoronoiPredicates.site_y0(s2)
  +la = dif(VoronoiPredicates.pt_y(en), VoronoiPredicates.pt_y(st))
  +lb = dif(VoronoiPredicates.pt_x(st), VoronoiPredicates.pt_x(en))
  +vx = dif(y2, y1)
  +vy = dif(x1, x2)
  +a = minus(times(la, dif(x1, VoronoiPredicates.pt_x(p1))), times(lb, dif(VoronoiPredicates.pt_y(p1), y1)))
  +b = minus(times(la, dif(x2, VoronoiPredicates.pt_x(p1))), times(lb, dif(VoronoiPredicates.pt_y(p1), y2)))
  Pps{la, lb, sqr_sum(la, lb), vx, vy, sum(x1, x2), sum(y1, y2), plus(times(la, vx), times(lb, vy)), minus(times(vx, lb), times(vy, la)), a, b}

def quarter() -> F64Repr.F64:
  F64Repr.F64{1070596096, 0}

def pps_parallel_lower(go: Bool, c: VoronoiPredicates.Circle, +a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +seg: VoronoiTypes.Big, +inv: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      +e = VoronoiTypes.efpt_to_f64(VoronoiRobust.eval2(a0, a1, seg, int(1)))
      set_lx(c, F64Arith.div(F64Arith.mul(F64Arith.mul(quarter(), e), inv), F64Arith.sqrt(fpt(seg))))
    case False{}:
      c

def quarter_scaled(+a: VoronoiTypes.Big, +inv: F64Repr.F64) -> F64Repr.F64:
  F64Arith.mul(F64Arith.mul(quarter(), fpt(a)), inv)

def pps_parallel(+p: Pps, +c: VoronoiPredicates.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match p:
    case Pps{_, _, +seg, +vx, +vy, +sx, +sy, +teta, _, +a, +b}:
      +ab = plus(a, b)
      +numer = minus(times(teta, teta), times(ab, ab))
      +den = times(teta, ab)
      +a0 = plus(VoronoiTypes.big_mul_i32(times(den, sx), 2), times(numer, vx))
      +a1 = plus(VoronoiTypes.big_mul_i32(times(den, ab), 2), times(numer, teta))
      +a2 = plus(VoronoiTypes.big_mul_i32(times(den, sy), 2), times(numer, vy))
      +inv = F64Arith.div(F64Repr.one(), fpt(den))
      +cx = F64Repr.pick(rcx, quarter_scaled(a0, inv), VoronoiPredicates.circle_x(c))
      +cy = F64Repr.pick(rcy, quarter_scaled(a2, inv), VoronoiPredicates.circle_y(c))
      pps_parallel_lower(rlx, VoronoiPredicates.Circle{cx, cy, VoronoiPredicates.circle_lx(c)}, a0, a1, seg, inv)

def half_scaled(+e: VoronoiTypes.Efpt, +inv: F64Repr.F64) -> F64Repr.F64:
  F64Arith.mul(F64Arith.mul(F64Repr.half(), VoronoiTypes.efpt_to_f64(e)), inv)

def pps_x(go: Bool, c: VoronoiPredicates.Circle, +a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +det: VoronoiTypes.Big, +inv: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      set_x(c, half_scaled(VoronoiRobust.eval2(a0, a1, int(1), det), inv))
    case False{}:
      c

def pps_y(go: Bool, c: VoronoiPredicates.Circle, +a2: VoronoiTypes.Big, +a3: VoronoiTypes.Big, +det: VoronoiTypes.Big, +inv: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      set_y(c, half_scaled(VoronoiRobust.eval2(a2, a3, int(1), det), inv))
    case False{}:
      c

def pps_lower(go: Bool, c: VoronoiPredicates.Circle, +p: Pps, +a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +det: VoronoiTypes.Big, +inv: F64Repr.F64, +middle: Bool) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      match p:
        case Pps{_, _, +seg, _, _, _, _, +teta, +denom, +a, +b}:
          +a2 = times(plus(a, b), plus(times(denom, denom), times(teta, teta)))
          +e = VoronoiRobust.eval4(a0, a1, a2, sign_flip(middle, teta), times(int(1), seg), times(det, seg), int(1), det)
          set_lx(c, F64Arith.div(half_scaled(e, inv), F64Arith.sqrt(fpt(seg))))
    case False{}:
      c

def pps_general(+p: Pps, c: VoronoiPredicates.Circle, +middle: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match p:
    case Pps{_, _, _, +vx, +vy, +sx, +sy, +teta, +denom, +a, +b}:
      +det = VoronoiTypes.big_mul_i32(times(times(plus(times(teta, teta), times(denom, denom)), a), b), 4)
      +inv1 = F64Arith.div(F64Repr.one(), fpt(denom))
      +inv = F64Arith.mul(inv1, inv1)
      +ab = plus(a, b)
      +a0 = plus(times(times(sx, denom), denom), times(times(teta, ab), vx))
      +a1 = sign_flip(middle, vx)
      +a2 = plus(times(times(sy, denom), denom), times(times(teta, ab), vy))
      +a3 = sign_flip(middle, vy)
      pps_lower(rlx, pps_y(rcy, pps_x(rcx, c, a0, a1, det, inv), a2, a3, det, inv), p, a0, a1, det, inv, middle)

def pps_route(parallel: Bool, +p: Pps, c: VoronoiPredicates.Circle, +middle: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match parallel:
    case True{}:
      pps_parallel(p, c, rcx, rcy, rlx)
    case False{}:
      pps_general(p, c, middle, rcx, rcy, rlx)

def pps_denom(p: Pps) -> VoronoiTypes.Big:
  match p:
    case Pps{_, _, _, _, _, _, _, _, +denom, _, _}:
      denom

# mp_circle_formation_functor::pps(site1, site2, site3, segment_index).
def pps(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, c: VoronoiPredicates.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  +p = pps_terms(s1, s2, s3)
  pps_route(VoronoiTypes.big_is_zero(pps_denom(p)), p, c, U32.is_eq(index, 2), rcx, rcy, rlx)

type Pss is Data:
  Pss{a0: VoronoiTypes.Big, b0: VoronoiTypes.Big, a1: VoronoiTypes.Big, b1: VoronoiTypes.Big, orientation: VoronoiTypes.Big}

def pss_terms(+st1: VoronoiPredicates.Pt, +en1: VoronoiPredicates.Pt, +st2: VoronoiPredicates.Pt, +en2: VoronoiPredicates.Pt) -> Pss:
  +a0 = dif(VoronoiPredicates.pt_x(en1), VoronoiPredicates.pt_x(st1))
  +b0 = dif(VoronoiPredicates.pt_y(en1), VoronoiPredicates.pt_y(st1))
  +a1 = dif(VoronoiPredicates.pt_x(en2), VoronoiPredicates.pt_x(st2))
  +b1 = dif(VoronoiPredicates.pt_y(en2), VoronoiPredicates.pt_y(st2))
  Pss{a0, b0, a1, b1, minus(times(a1, b0), times(a0, b1))}

def two_signed(+second: Bool) -> U32:
  F64Word.pick(second, 2, 4294967294)

def pss_parallel_y(go: Bool, c: VoronoiPredicates.Circle, +a0: VoronoiTypes.Big, +b0: VoronoiTypes.Big, +cb0: VoronoiTypes.Big, +st1: VoronoiPredicates.Pt, +st2: VoronoiPredicates.Pt, +x: U32, +y: U32, +second: Bool, +denom: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      +ca0 = VoronoiTypes.big_mul_i32(b0, two_signed(second))
      +ya = times(times(a0, a0), sum(VoronoiPredicates.pt_y(st1), VoronoiPredicates.pt_y(st2)))
      +yb = times(times(a0, b0), wide(VoronoiTypes.sub64(VoronoiTypes.add64(VoronoiTypes.widen(VoronoiPredicates.pt_x(st1)), VoronoiTypes.widen(VoronoiPredicates.pt_x(st2))), VoronoiTypes.add64(VoronoiTypes.widen(x), VoronoiTypes.widen(x)))))
      +yc = times(times(b0, b0), wide(VoronoiTypes.add64(VoronoiTypes.widen(y), VoronoiTypes.widen(y))))
      set_y(c, F64Arith.div(VoronoiTypes.efpt_to_f64(VoronoiRobust.eval2(ca0, plus(minus(ya, yb), yc), cb0, int(1))), denom))
    case False{}:
      c

def pss_parallel_x(go: Bool, c: VoronoiPredicates.Circle, +ca0: VoronoiTypes.Big, +ca1: VoronoiTypes.Big, +cb0: VoronoiTypes.Big, +denom: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      set_x(c, F64Arith.div(VoronoiTypes.efpt_to_f64(VoronoiRobust.eval2(ca0, ca1, cb0, int(1))), denom))
    case False{}:
      c

def pss_parallel_lower(go: Bool, c: VoronoiPredicates.Circle, +ca0: VoronoiTypes.Big, +ca1: VoronoiTypes.Big, +c0: VoronoiTypes.Big, +cb0: VoronoiTypes.Big, +cb2: VoronoiTypes.Big, +denom: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      +ca2 = sign_flip(VoronoiTypes.big_is_neg(c0), c0)
      set_lx(c, F64Arith.div(VoronoiTypes.efpt_to_f64(VoronoiRobust.eval3(ca0, ca1, ca2, cb0, int(1), cb2)), denom))
    case False{}:
      c

def pss_parallel_xl(go: Bool, c: VoronoiPredicates.Circle, +a0: VoronoiTypes.Big, +b0: VoronoiTypes.Big, +c0: VoronoiTypes.Big, +cb0: VoronoiTypes.Big, +st1: VoronoiPredicates.Pt, +st2: VoronoiPredicates.Pt, +x: U32, +y: U32, +second: Bool, +denom: F64Repr.F64, +rcx: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      +ca0 = VoronoiTypes.big_mul_i32(a0, two_signed(second))
      +xa = times(times(b0, b0), sum(VoronoiPredicates.pt_x(st1), VoronoiPredicates.pt_x(st2)))
      +xb = times(times(a0, b0), wide(VoronoiTypes.sub64(VoronoiTypes.add64(VoronoiTypes.widen(VoronoiPredicates.pt_y(st1)), VoronoiTypes.widen(VoronoiPredicates.pt_y(st2))), VoronoiTypes.add64(VoronoiTypes.widen(y), VoronoiTypes.widen(y)))))
      +xc = times(times(a0, a0), wide(VoronoiTypes.add64(VoronoiTypes.widen(x), VoronoiTypes.widen(x))))
      +ca1 = plus(minus(xa, xb), xc)
      pss_parallel_lower(rlx, pss_parallel_x(rcx, c, ca0, ca1, cb0, denom), ca0, ca1, c0, cb0, sqr_sum(a0, b0), denom)
    case False{}:
      c

def pss_parallel(+t: Pss, +st1: VoronoiPredicates.Pt, +st2: VoronoiPredicates.Pt, +s1: VoronoiPredicates.Site, c: VoronoiPredicates.Circle, +second: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match t:
    case Pss{+a0, +b0, _, _, _}:
      +x = VoronoiPredicates.site_x0(s1)
      +y = VoronoiPredicates.site_y0(s1)
      +denom = F64Arith.mul(F64Repr.two(), fpt(sqr_sum(a0, b0)))
      +c0 = minus(times(b0, dif(VoronoiPredicates.pt_x(st2), VoronoiPredicates.pt_x(st1))), times(a0, dif(VoronoiPredicates.pt_y(st2), VoronoiPredicates.pt_y(st1))))
      +dx = minus(times(a0, dif(y, VoronoiPredicates.pt_y(st1))), times(b0, dif(x, VoronoiPredicates.pt_x(st1))))
      +dy = minus(times(b0, dif(x, VoronoiPredicates.pt_x(st2))), times(a0, dif(y, VoronoiPredicates.pt_y(st2))))
      +cb0 = times(dx, dy)
      +cy = pss_parallel_y(rcy, c, a0, b0, cb0, st1, st2, x, y, second, denom)
      pss_parallel_xl(rcx || rlx, cy, a0, b0, c0, cb0, st1, st2, x, y, second, denom, rcx, rlx)

def pss4_first(same: Bool, +lh: VoronoiTypes.Efpt, +rh: VoronoiTypes.Efpt, +a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +a2: VoronoiTypes.Big, +b0: VoronoiTypes.Big, +b1: VoronoiTypes.Big, +b3: VoronoiTypes.Big, +b2: VoronoiTypes.Big) -> VoronoiTypes.Efpt:
  match same:
    case True{}:
      VoronoiTypes.efpt_add(lh, rh)
    case False{}:
      +c0 = minus(plus(times(times(a0, a0), b0), times(times(a1, a1), b1)), times(times(times(a2, a2), b3), b2))
      +c1 = minus(VoronoiTypes.big_mul_i32(times(a0, a1), 2), times(times(a2, a2), b3))
      VoronoiTypes.efpt_div(VoronoiRobust.eval2(c0, c1, int(1), times(b0, b1)), VoronoiTypes.efpt_sub(lh, rh))

def pss3_join(same: Bool, +lh: VoronoiTypes.Efpt, +rh: VoronoiTypes.Efpt, +a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +a2: VoronoiTypes.Big, +a3: VoronoiTypes.Big, +b0: VoronoiTypes.Big, +b1: VoronoiTypes.Big, +b3: VoronoiTypes.Big) -> VoronoiTypes.Efpt:
  match same:
    case True{}:
      VoronoiTypes.efpt_add(lh, rh)
    case False{}:
      +c0 = minus(minus(plus(times(times(a0, a0), b0), times(times(a1, a1), b1)), times(a2, a2)), times(times(times(a3, a3), b0), b1))
      +c1 = VoronoiTypes.big_mul_i32(minus(times(a0, a1), times(a2, a3)), 2)
      VoronoiTypes.efpt_div(VoronoiRobust.eval2(c0, c1, int(1), b3), VoronoiTypes.efpt_sub(lh, rh))

def pss3(+a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +a2: VoronoiTypes.Big, +a3: VoronoiTypes.Big, +b0: VoronoiTypes.Big, +b1: VoronoiTypes.Big, +b2: VoronoiTypes.Big, +b3: VoronoiTypes.Big) -> VoronoiTypes.Efpt:
  +lh = VoronoiRobust.eval2(a0, a1, b0, b1)
  +rh = VoronoiRobust.eval2(a2, a3, b2, b3)
  pss3_join(VoronoiRobust.same_sign_efpt(lh, rh), lh, rh, a0, a1, a2, a3, b0, b1, b3)

def pss4_second(same: Bool, +lh: VoronoiTypes.Efpt, +rh: VoronoiTypes.Efpt, +a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +a2: VoronoiTypes.Big, +a3: VoronoiTypes.Big, +b0: VoronoiTypes.Big, +b1: VoronoiTypes.Big, +b2: VoronoiTypes.Big, +b3: VoronoiTypes.Big) -> VoronoiTypes.Efpt:
  match same:
    case True{}:
      VoronoiTypes.efpt_add(lh, rh)
    case False{}:
      +c0 = VoronoiTypes.big_mul_i32(times(a3, a0), 2)
      +c1 = VoronoiTypes.big_mul_i32(times(a3, a1), 2)
      +c2 = minus(plus(plus(times(times(a0, a0), b0), times(times(a1, a1), b1)), times(a3, a3)), times(times(times(a2, a2), b2), b3))
      +c3 = minus(VoronoiTypes.big_mul_i32(times(a0, a1), 2), times(times(a2, a2), b3))
      VoronoiTypes.efpt_div(pss3(c0, c1, c2, c3, b0, b1, int(1), times(b0, b1)), VoronoiTypes.efpt_sub(lh, rh))

def pss4_route(zero: Bool, +a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +a2: VoronoiTypes.Big, +a3: VoronoiTypes.Big, +b0: VoronoiTypes.Big, +b1: VoronoiTypes.Big, +b2: VoronoiTypes.Big, +b3: VoronoiTypes.Big, +rh: VoronoiTypes.Efpt) -> VoronoiTypes.Efpt:
  match zero:
    case True{}:
      +lh = VoronoiRobust.eval2(a0, a1, b0, b1)
      pss4_first(VoronoiRobust.same_sign_efpt(lh, rh), lh, rh, a0, a1, a2, b0, b1, b3, b2)
    case False{}:
      +lh = VoronoiRobust.eval3(a0, a1, a3, b0, b1, int(1))
      pss4_second(VoronoiRobust.same_sign_efpt(lh, rh), lh, rh, a0, a1, a2, a3, b0, b1, b2, b3)

# sqrt_expr_evaluator_pss4.
def pss4(+a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +a2: VoronoiTypes.Big, +a3: VoronoiTypes.Big, +b0: VoronoiTypes.Big, +b1: VoronoiTypes.Big, +b2: VoronoiTypes.Big, +b3: VoronoiTypes.Big) -> VoronoiTypes.Efpt:
  +rh = VoronoiTypes.efpt_mul(VoronoiRobust.eval1(a2, b3), VoronoiTypes.efpt_sqrt(VoronoiRobust.eval2(int(1), b2, times(b0, b1), int(1))))
  pss4_route(VoronoiTypes.big_is_zero(a3), a0, a1, a2, a3, b0, b1, b2, b3, rh)

type Pss4 is Data:
  Pss4{b0: VoronoiTypes.Big, b1: VoronoiTypes.Big, b2: VoronoiTypes.Big, b3: VoronoiTypes.Big}

def pss4_with(+a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +a2: VoronoiTypes.Big, +a3: VoronoiTypes.Big, +bs: Pss4) -> F64Repr.F64:
  match bs:
    case Pss4{+b0, +b1, +b2, +b3}:
      VoronoiTypes.efpt_to_f64(pss4(a0, a1, a2, a3, b0, b1, b2, b3))

type Meet is Data:
  Meet{ix: VoronoiTypes.Big, iy: VoronoiTypes.Big, dx: VoronoiTypes.Big, dy: VoronoiTypes.Big}

def pss_numer(+along: VoronoiTypes.Big, +i: VoronoiTypes.Big, +dx: VoronoiTypes.Big, +dy: VoronoiTypes.Big, +ea: VoronoiTypes.Big, +eb: VoronoiTypes.Big) -> VoronoiTypes.Big:
  minus(times(along, sqr_sum(dx, dy)), times(i, plus(times(dx, ea), times(dy, eb))))

def pss_general_y(go: Bool, c: VoronoiPredicates.Circle, +t: Pss, +m: Meet, +sign: VoronoiTypes.Big, +bs: Pss4, +denom: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      match t:
        case Pss{+a0, +b0, +a1, +b1, _}:
          match m:
            case Meet{_, +iy, +dx, +dy}:
              +ca0 = pss_numer(b1, iy, dx, dy, a1, b1)
              +ca1 = pss_numer(b0, iy, dx, dy, a0, b0)
              set_y(c, F64Arith.div(pss4_with(ca0, ca1, times(iy, sign), int(0), bs), denom))
    case False{}:
      c

def pss_general_lower(go: Bool, c: VoronoiPredicates.Circle, +ca0: VoronoiTypes.Big, +ca1: VoronoiTypes.Big, +ca2: VoronoiTypes.Big, +orientation: VoronoiTypes.Big, +m: Meet, +bs: Pss4, +temp: F64Repr.F64, +denom: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      match m:
        case Meet{_, _, +dx, +dy}:
          +ca3 = VoronoiTypes.big_mul_i32(times(orientation, sqr_sum(dx, dy)), F64Word.pick(is_neg(temp), 4294967295, 1))
          set_lx(c, F64Arith.div(pss4_with(ca0, ca1, ca2, ca3, bs), denom))
    case False{}:
      c

def pss_general_x(go: Bool, c: VoronoiPredicates.Circle, +ca0: VoronoiTypes.Big, +ca1: VoronoiTypes.Big, +ca2: VoronoiTypes.Big, +bs: Pss4, +denom: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      set_x(c, F64Arith.div(pss4_with(ca0, ca1, ca2, int(0), bs), denom))
    case False{}:
      c

def pss_general_xl(go: Bool, c: VoronoiPredicates.Circle, +t: Pss, +m: Meet, +sign: VoronoiTypes.Big, +bs: Pss4, +temp: F64Repr.F64, +denom: F64Repr.F64, +rcx: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      match t:
        case Pss{+a0, +b0, +a1, +b1, +orientation}:
          match m:
            case Meet{+ix, _, +dx, +dy}:
              +ca0 = pss_numer(a1, ix, dx, dy, a1, b1)
              +ca1 = pss_numer(a0, ix, dx, dy, a0, b0)
              +ca2 = times(ix, sign)
              pss_general_lower(rlx, pss_general_x(rcx, c, ca0, ca1, ca2, bs, denom), ca0, ca1, ca2, orientation, m, bs, temp, denom)
    case False{}:
      c

def pss_sign(+second: Bool, +orientation: VoronoiTypes.Big) -> VoronoiTypes.Big:
  int((F64Word.pick(second, 1, 4294967295) * F64Word.pick(VoronoiTypes.big_is_neg(orientation), 1, 4294967295) : U32))

def pss_cross_terms(+t: Pss, +m: Meet) -> Pss4:
  match t:
    case Pss{+a0, +b0, +a1, +b1, _}:
      match m:
        case Meet{_, _, +dx, +dy}:
          +b3 = VoronoiTypes.big_mul_i32(times(minus(times(a0, dy), times(b0, dx)), minus(times(a1, dy), times(b1, dx))), 4294967294)
          Pss4{sqr_sum(a0, b0), sqr_sum(a1, b1), plus(times(a0, a1), times(b0, b1)), b3}

def pss_general(+t: Pss, +m: Meet, c: VoronoiPredicates.Circle, +second: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match t:
    case Pss{+a0, +b0, +a1, +b1, +orientation}:
      match m:
        case Meet{_, _, +dx, +dy}:
          +sign = pss_sign(second, orientation)
          +bs = pss_cross_terms(t, m)
          +ca0 = plus(times(a1, VoronoiTypes.big_neg(dx)), times(b1, VoronoiTypes.big_neg(dy)))
          +ca1 = plus(times(a0, VoronoiTypes.big_neg(dx)), times(b0, VoronoiTypes.big_neg(dy)))
          +temp = pss4_with(ca0, ca1, sign, int(0), bs)
          +denom = F64Arith.mul(temp, fpt(orientation))
          pss_general_xl(rcx || rlx, pss_general_y(rcy, c, t, m, sign, bs, denom), t, m, sign, bs, temp, denom, rcx, rlx)

def pss_meet_route(at_site: Bool, +t: Pss, +m: Meet, c: VoronoiPredicates.Circle, +second: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match at_site:
    case True{}:
      match t:
        case Pss{_, _, _, _, +orientation}:
          match m:
            case Meet{+ix, +iy, _, _}:
              +denom = fpt(orientation)
              +cx = F64Arith.div(fpt(ix), denom)
              VoronoiPredicates.Circle{cx, F64Arith.div(fpt(iy), denom), cx}
    case False{}:
      pss_general(t, m, c, second, rcx, rcy, rlx)

def meet_at_site(+m: Meet) -> Bool:
  match m:
    case Meet{_, _, +dx, +dy}:
      VoronoiTypes.big_is_zero(dx) && VoronoiTypes.big_is_zero(dy)

def pss_meet(+t: Pss, +en1: VoronoiPredicates.Pt, +en2: VoronoiPredicates.Pt, +s1: VoronoiPredicates.Site) -> Meet:
  match t:
    case Pss{+a0, +b0, +a1, +b1, +orientation}:
      +c0 = minus(VoronoiTypes.big_mul_i32(b0, VoronoiPredicates.pt_x(en1)), VoronoiTypes.big_mul_i32(a0, VoronoiPredicates.pt_y(en1)))
      +c1 = minus(VoronoiTypes.big_mul_i32(a1, VoronoiPredicates.pt_y(en2)), VoronoiTypes.big_mul_i32(b1, VoronoiPredicates.pt_x(en2)))
      +ix = plus(times(a0, c1), times(a1, c0))
      +iy = plus(times(b0, c1), times(b1, c0))
      Meet{ix, iy, minus(ix, VoronoiTypes.big_mul_i32(orientation, VoronoiPredicates.site_x0(s1))), minus(iy, VoronoiTypes.big_mul_i32(orientation, VoronoiPredicates.site_y0(s1)))}

def pss_route(parallel: Bool, +t: Pss, +st1: VoronoiPredicates.Pt, +en1: VoronoiPredicates.Pt, +st2: VoronoiPredicates.Pt, +en2: VoronoiPredicates.Pt, +s1: VoronoiPredicates.Site, c: VoronoiPredicates.Circle, +second: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match parallel:
    case True{}:
      pss_parallel(t, st1, st2, s1, c, second, rcx, rcy, rlx)
    case False{}:
      +m = pss_meet(t, en1, en2, s1)
      pss_meet_route(meet_at_site(m), t, m, c, second, rcx, rcy, rlx)

def pss_orientation(t: Pss) -> VoronoiTypes.Big:
  match t:
    case Pss{_, _, _, _, +o}:
      o

# mp_circle_formation_functor::pss(site1, site2, site3, point_index).
def pss(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, c: VoronoiPredicates.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  +st1 = VoronoiPredicates.end(s2)
  +en1 = VoronoiPredicates.start(s2)
  +st2 = VoronoiPredicates.start(s3)
  +en2 = VoronoiPredicates.end(s3)
  +t = pss_terms(st1, en1, st2, en2)
  pss_route(VoronoiTypes.big_is_zero(pss_orientation(t)), t, st1, en1, st2, en2, s1, c, U32.is_eq(index, 2), rcx, rcy, rlx)

type Line is Data:
  Line{a: VoronoiTypes.Big, b: VoronoiTypes.Big, c: VoronoiTypes.Big}

def sss_line(+s: VoronoiPredicates.Site) -> Line:
  +st = VoronoiPredicates.start(s)
  +en = VoronoiPredicates.end(s)
  +c = VoronoiTypes.sub64(VoronoiTypes.mul64(VoronoiTypes.widen(VoronoiPredicates.pt_x(st)), VoronoiTypes.widen(VoronoiPredicates.pt_y(en))), VoronoiTypes.mul64(VoronoiTypes.widen(VoronoiPredicates.pt_y(st)), VoronoiTypes.widen(VoronoiPredicates.pt_x(en))))
  Line{dif(VoronoiPredicates.pt_x(en), VoronoiPredicates.pt_x(st)), dif(VoronoiPredicates.pt_y(en), VoronoiPredicates.pt_y(st)), wide(c)}

def line_a(l: Line) -> VoronoiTypes.Big:
  match l:
    case Line{+a, _, _}:
      a

def line_b(l: Line) -> VoronoiTypes.Big:
  match l:
    case Line{_, +b, _}:
      b

def line_c(l: Line) -> VoronoiTypes.Big:
  match l:
    case Line{_, _, +c}:
      c

def cross_ab(+j: Line, +k: Line) -> VoronoiTypes.Big:
  minus(times(line_a(j), line_b(k)), times(line_a(k), line_b(j)))

def cross_bc(+j: Line, +k: Line) -> VoronoiTypes.Big:
  minus(times(line_b(j), line_c(k)), times(line_b(k), line_c(j)))

def cross_ac(+j: Line, +k: Line) -> VoronoiTypes.Big:
  minus(times(line_a(j), line_c(k)), times(line_a(k), line_c(j)))

def line_len(+l: Line) -> VoronoiTypes.Big:
  sqr_sum(line_a(l), line_b(l))

def sss_y(go: Bool, c: VoronoiPredicates.Circle, +l0: Line, +l1: Line, +l2: Line, +denom: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      +e = VoronoiRobust.eval3(cross_bc(l1, l2), cross_bc(l2, l0), cross_bc(l0, l1), line_len(l0), line_len(l1), line_len(l2))
      set_y(c, F64Arith.div(VoronoiTypes.efpt_to_f64(e), denom))
    case False{}:
      c

def sss_x(go: Bool, c: VoronoiPredicates.Circle, +a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +a2: VoronoiTypes.Big, +l0: Line, +l1: Line, +l2: Line, +denom: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      set_x(c, F64Arith.div(VoronoiTypes.efpt_to_f64(VoronoiRobust.eval3(a0, a1, a2, line_len(l0), line_len(l1), line_len(l2))), denom))
    case False{}:
      c

def sss_lower(go: Bool, c: VoronoiPredicates.Circle, +a0: VoronoiTypes.Big, +a1: VoronoiTypes.Big, +a2: VoronoiTypes.Big, +l0: Line, +l1: Line, +l2: Line, +denom: F64Repr.F64) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      +a3 = plus(plus(plus(int(0), times(a0, line_b(l0))), times(a1, line_b(l1))), times(a2, line_b(l2)))
      +e = VoronoiRobust.eval4(a0, a1, a2, a3, line_len(l0), line_len(l1), line_len(l2), int(1))
      set_lx(c, F64Arith.div(VoronoiTypes.efpt_to_f64(e), denom))
    case False{}:
      c

def sss_xl(go: Bool, c: VoronoiPredicates.Circle, +l0: Line, +l1: Line, +l2: Line, +denom: F64Repr.F64, +rcx: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      +a0 = cross_ac(l1, l2)
      +a1 = cross_ac(l2, l0)
      +a2 = cross_ac(l0, l1)
      sss_lower(rlx, sss_x(rcx, c, a0, a1, a2, l0, l1, l2, denom), a0, a1, a2, l0, l1, l2, denom)
    case False{}:
      c

# mp_circle_formation_functor::sss.
def sss(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, c: VoronoiPredicates.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  +l0 = sss_line(s1)
  +l1 = sss_line(s2)
  +l2 = sss_line(s3)
  +denom = VoronoiTypes.efpt_to_f64(VoronoiRobust.eval3(cross_ab(l1, l2), cross_ab(l2, l0), cross_ab(l0, l1), line_len(l0), line_len(l1), line_len(l2)))
  sss_xl(rcx || rlx, sss_y(rcy, c, l0, l1, l2, denom), l0, l1, l2, denom, rcx, rlx)
