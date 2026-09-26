import Base
import ../../f64/word.bend as F64Word
import ../../f64/repr.bend as F64Repr
import ../../f64/arith.bend as F64Arith
import ./ctypes.bend as VoronoiTypes
import ./robust.bend as VoronoiRobust
import ./predicates.bend as VoronoiPredicates
import ./exact.bend as VoronoiExact

# Boost.Polygon 1.52 lazy_circle_formation_functor and circle_formation_predicate: each circle event is first
# computed in robust_fpt arithmetic, and a coordinate whose relative error exceeds 64 ulps is recomputed by the
# exact functor (exact.bend).

def rf(+v: F64Repr.F64) -> VoronoiRobust.RF:
  VoronoiRobust.rf(v)

def rfe(+v: F64Repr.F64, +e: F64Repr.F64) -> VoronoiRobust.RF:
  VoronoiRobust.rf_err(v, e)

def num(+x: U32) -> F64Repr.F64:
  F64Repr.from_i32(x)

def err(+k: U32) -> F64Repr.F64:
  F64Repr.from_u32(k)

def cross(+a1: F64Word.W64, +b1: F64Word.W64, +a2: F64Word.W64, +b2: F64Word.W64) -> F64Repr.F64:
  VoronoiPredicates.cross(a1, b1, a2, b2)

def d(+a: U32, +b: U32) -> F64Word.W64:
  VoronoiTypes.dif32(a, b)

def w(+a: U32) -> F64Word.W64:
  VoronoiTypes.widen(a)

def triple(+a: F64Repr.F64, +b: F64Repr.F64, +c: F64Repr.F64) -> F64Repr.F64:
  F64Arith.mul(F64Arith.mul(a, b), c)

def sqr_sum(+a: F64Repr.F64, +b: F64Repr.F64) -> F64Repr.F64:
  F64Arith.add(F64Arith.mul(a, a), F64Arith.mul(b, b))

def rd_value(+x: VoronoiRobust.RD) -> F64Repr.F64:
  VoronoiRobust.rf_value(VoronoiRobust.rd_dif(x))

def rd_exact(+x: VoronoiRobust.RD) -> Bool:
  VoronoiRobust.rf_needs_exact(VoronoiRobust.rd_dif(x))

def recompute_ppp(go: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +c: VoronoiPredicates.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      VoronoiExact.ppp(s1, s2, s3, c, rcx, rcy, rlx)
    case False{}:
      c

def ppp_sums(+dx1: F64Repr.F64, +dy1: F64Repr.F64, +dx2: F64Repr.F64, +dy2: F64Repr.F64, +sx1: F64Repr.F64, +sy1: F64Repr.F64, +sx2: F64Repr.F64, +sy2: F64Repr.F64) -> VoronoiRobust.RD:
  +two = err(2)
  +c1 = VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), rfe(triple(dx1, sx1, dy2), two))
  +c2 = VoronoiRobust.rd_add_rf(c1, rfe(triple(dy1, sy1, dy2), two))
  +c3 = VoronoiRobust.rd_sub_rf(c2, rfe(triple(dx2, sx2, dy1), two))
  VoronoiRobust.rd_sub_rf(c3, rfe(triple(dy2, sy2, dy1), two))

def ppp_sums_y(+dx1: F64Repr.F64, +dy1: F64Repr.F64, +dx2: F64Repr.F64, +dy2: F64Repr.F64, +sx1: F64Repr.F64, +sy1: F64Repr.F64, +sx2: F64Repr.F64, +sy2: F64Repr.F64) -> VoronoiRobust.RD:
  +two = err(2)
  +c1 = VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), rfe(triple(dx2, sx2, dx1), two))
  +c2 = VoronoiRobust.rd_add_rf(c1, rfe(triple(dy2, sy2, dx1), two))
  +c3 = VoronoiRobust.rd_sub_rf(c2, rfe(triple(dx1, sx1, dx2), two))
  VoronoiRobust.rd_sub_rf(c3, rfe(triple(dy1, sy1, dx2), two))

def unscaled(+cx: VoronoiRobust.RD, +cy: VoronoiRobust.RD, +lx: VoronoiRobust.RD) -> VoronoiPredicates.Circle:
  VoronoiPredicates.Circle{rd_value(cx), rd_value(cy), rd_value(lx)}

def scaled(+cx: VoronoiRobust.RD, +cy: VoronoiRobust.RD, +lx: VoronoiRobust.RD, +inv: F64Repr.F64) -> VoronoiPredicates.Circle:
  VoronoiPredicates.Circle{F64Arith.mul(rd_value(cx), inv), F64Arith.mul(rd_value(cy), inv), F64Arith.mul(rd_value(lx), inv)}

def ppp_finish(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +cx: VoronoiRobust.RD, +cy: VoronoiRobust.RD, +lx: VoronoiRobust.RD, +inv: F64Repr.F64) -> VoronoiPredicates.Circle:
  +rcx = rd_exact(cx)
  +rcy = rd_exact(cy)
  +rlx = rd_exact(lx)
  recompute_ppp(rcx || rcy || rlx, s1, s2, s3, scaled(cx, cy, lx, inv), rcx, rcy, rlx)

# lazy_circle_formation_functor::ppp.
def ppp(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> VoronoiPredicates.Circle:
  +x1 = VoronoiPredicates.site_x0(s1)
  +y1 = VoronoiPredicates.site_y0(s1)
  +x2 = VoronoiPredicates.site_x0(s2)
  +y2 = VoronoiPredicates.site_y0(s2)
  +x3 = VoronoiPredicates.site_x0(s3)
  +y3 = VoronoiPredicates.site_y0(s3)
  +dx1 = F64Arith.sub(num(x1), num(x2))
  +dx2 = F64Arith.sub(num(x2), num(x3))
  +dy1 = F64Arith.sub(num(y1), num(y2))
  +dy2 = F64Arith.sub(num(y2), num(y3))
  +inv = VoronoiRobust.rf_value(rfe(F64Arith.div(F64Repr.half(), cross(d(x1, x2), d(x2, x3), d(y1, y2), d(y2, y3))), err(2)))
  +sx1 = F64Arith.add(num(x1), num(x2))
  +sx2 = F64Arith.add(num(x2), num(x3))
  +sy1 = F64Arith.add(num(y1), num(y2))
  +sy2 = F64Arith.add(num(y2), num(y3))
  +dx3 = F64Arith.sub(num(x1), num(x3))
  +dy3 = F64Arith.sub(num(y1), num(y3))
  +cx = ppp_sums(dx1, dy1, dx2, dy2, sx1, sy1, sx2, sy2)
  +cy = ppp_sums_y(dx1, dy1, dx2, dy2, sx1, sy1, sx2, sy2)
  +lx = VoronoiRobust.rd_sub_rf(cx, rfe(F64Arith.sqrt(triple(sqr_sum(dx1, dy1), sqr_sum(dx2, dy2), sqr_sum(dx3, dy3))), err(5)))
  ppp_finish(s1, s2, s3, cx, cy, lx, inv)

def pps_t_collinear(+teta: VoronoiRobust.RF, +a: VoronoiRobust.RF) -> VoronoiRobust.RD:
  +t1 = VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), VoronoiRobust.rf_div(teta, VoronoiRobust.rf_mul(rf(err(8)), a)))
  VoronoiRobust.rd_sub_rf(t1, VoronoiRobust.rf_div(a, VoronoiRobust.rf_mul(rf(err(2)), teta)))

def pps_t_general(+teta: VoronoiRobust.RF, +a: VoronoiRobust.RF, +b: VoronoiRobust.RF, +denom: VoronoiRobust.RF, +middle: Bool) -> VoronoiRobust.RD:
  +det = VoronoiRobust.rf_sqrt(VoronoiRobust.rf_mul(VoronoiRobust.rf_mul(VoronoiRobust.rf_add(VoronoiRobust.rf_mul(teta, teta), VoronoiRobust.rf_mul(denom, denom)), a), b))
  +q = VoronoiRobust.rf_div(det, VoronoiRobust.rf_mul(denom, denom))
  +t1 = Bool.pick(VoronoiRobust.RD, middle, VoronoiRobust.rd_sub_rf(VoronoiRobust.rd_zero(), q), VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), q))
  VoronoiRobust.rd_add_rf(t1, VoronoiRobust.rf_div(VoronoiRobust.rf_mul(teta, VoronoiRobust.rf_add(a, b)), VoronoiRobust.rf_mul(VoronoiRobust.rf_mul(rf(err(2)), denom), denom)))

def pps_t(collinear: Bool, +teta: VoronoiRobust.RF, +a: VoronoiRobust.RF, +b: VoronoiRobust.RF, +denom: VoronoiRobust.RF, +middle: Bool) -> VoronoiRobust.RD:
  match collinear:
    case True{}:
      pps_t_collinear(teta, a)
    case False{}:
      pps_t_general(teta, a, b, denom, middle)

def recompute_pps(go: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, +c: VoronoiPredicates.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      VoronoiExact.pps(s1, s2, s3, index, c, rcx, rcy, rlx)
    case False{}:
      c

def pps_finish(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, +cx: VoronoiRobust.RD, +cy: VoronoiRobust.RD, +lx: VoronoiRobust.RD) -> VoronoiPredicates.Circle:
  +c = unscaled(cx, cy, lx)
  +rcx = rd_exact(cx)
  +rcy = rd_exact(cy)
  +rlx = rd_exact(lx)
  recompute_pps(rcx || rcy || rlx, s1, s2, s3, index, c, rcx, rcy, rlx)

def pps_lower(+s3: VoronoiPredicates.Site, +la: F64Repr.F64, +lb: F64Repr.F64, +cx: VoronoiRobust.RD, +cy: VoronoiRobust.RD, +inv_len: VoronoiRobust.RF) -> VoronoiRobust.RD:
  +r1 = VoronoiRobust.rd_sub_rf(VoronoiRobust.rd_zero(), VoronoiRobust.rf_mul(rf(la), rf(num(VoronoiPredicates.site_x0(s3)))))
  +r2 = VoronoiRobust.rd_sub_rf(r1, VoronoiRobust.rf_mul(rf(lb), rf(num(VoronoiPredicates.site_y0(s3)))))
  +r3 = VoronoiRobust.rd_add(r2, VoronoiRobust.rf_mul_rd(rf(la), cx))
  +r = VoronoiRobust.rd_make_positive(VoronoiRobust.rd_add(r3, VoronoiRobust.rf_mul_rd(rf(lb), cy)))
  VoronoiRobust.rd_add(cx, VoronoiRobust.rd_mul_rf(r, inv_len))

# lazy_circle_formation_functor::pps(site1, site2, site3, segment_index).
def pps(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32) -> VoronoiPredicates.Circle:
  +st = VoronoiPredicates.start(s3)
  +en = VoronoiPredicates.end(s3)
  +p1 = VoronoiPredicates.point1(s3)
  +x1 = VoronoiPredicates.site_x0(s1)
  +y1 = VoronoiPredicates.site_y0(s1)
  +x2 = VoronoiPredicates.site_x0(s2)
  +y2 = VoronoiPredicates.site_y0(s2)
  +la = F64Arith.sub(num(VoronoiPredicates.pt_y(en)), num(VoronoiPredicates.pt_y(st)))
  +lb = F64Arith.sub(num(VoronoiPredicates.pt_x(st)), num(VoronoiPredicates.pt_x(en)))
  +vx = F64Arith.sub(num(y2), num(y1))
  +vy = F64Arith.sub(num(x1), num(x2))
  +ila = d(VoronoiPredicates.pt_y(en), VoronoiPredicates.pt_y(st))
  +ilb = d(VoronoiPredicates.pt_x(st), VoronoiPredicates.pt_x(en))
  +teta = rfe(cross(ila, ilb, d(x2, x1), d(y2, y1)), F64Repr.one())
  +a = rfe(cross(ila, ilb, d(VoronoiPredicates.pt_y(p1), y1), d(x1, VoronoiPredicates.pt_x(p1))), F64Repr.one())
  +b = rfe(cross(ila, ilb, d(VoronoiPredicates.pt_y(p1), y2), d(x2, VoronoiPredicates.pt_x(p1))), F64Repr.one())
  +denom = rfe(cross(d(y2, y1), d(x1, x2), ila, ilb), F64Repr.one())
  +inv_len = rfe(F64Arith.div(F64Repr.one(), F64Arith.sqrt(sqr_sum(la, lb))), err(3))
  +t = pps_t(VoronoiRobust.rf_is_zero(denom), teta, a, b, denom, U32.is_eq(index, 2))
  +cx = VoronoiRobust.rd_add(VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), rf(F64Arith.mul(F64Repr.half(), F64Arith.add(num(x1), num(x2))))), VoronoiRobust.rf_mul_rd(rf(vx), t))
  +cy = VoronoiRobust.rd_add(VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), rf(F64Arith.mul(F64Repr.half(), F64Arith.add(num(y1), num(y2))))), VoronoiRobust.rf_mul_rd(rf(vy), t))
  pps_finish(s1, s2, s3, index, cx, cy, pps_lower(s3, la, lb, cx, cy, inv_len))

def recompute_pss(go: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, +c: VoronoiPredicates.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      VoronoiExact.pss(s1, s2, s3, index, c, rcx, rcy, rlx)
    case False{}:
      c

def pss_finish(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, +cx: VoronoiRobust.RD, +cy: VoronoiRobust.RD, +lx: VoronoiRobust.RD) -> VoronoiPredicates.Circle:
  +c = unscaled(cx, cy, lx)
  +rcx = rd_exact(cx)
  +rcy = rd_exact(cy)
  +rlx = rd_exact(lx)
  recompute_pss(rcx || rcy || rlx, s1, s2, s3, index, c, rcx, rcy, rlx)

def with_det(+t: VoronoiRobust.RD, +det: VoronoiRobust.RF, +second: Bool) -> VoronoiRobust.RD:
  Bool.pick(VoronoiRobust.RD, second, VoronoiRobust.rd_add_rf(t, VoronoiRobust.rf_sqrt(det)), VoronoiRobust.rd_sub_rf(t, VoronoiRobust.rf_sqrt(det)))

def half_sum(+a: U32, +b: U32) -> F64Repr.F64:
  F64Arith.mul(F64Repr.half(), F64Arith.add(num(a), num(b)))

def pss_collinear(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, +st1: VoronoiPredicates.Pt, +en1: VoronoiPredicates.Pt, +st2: VoronoiPredicates.Pt, +a1: F64Repr.F64, +b1: F64Repr.F64) -> VoronoiPredicates.Circle:
  +x = VoronoiPredicates.site_x0(s1)
  +y = VoronoiPredicates.site_y0(s1)
  +e1x = d(VoronoiPredicates.pt_x(en1), VoronoiPredicates.pt_x(st1))
  +e1y = d(VoronoiPredicates.pt_y(en1), VoronoiPredicates.pt_y(st1))
  +a = rfe(sqr_sum(a1, b1), err(2))
  +c = rfe(cross(e1y, e1x, d(VoronoiPredicates.pt_y(st2), VoronoiPredicates.pt_y(st1)), d(VoronoiPredicates.pt_x(st2), VoronoiPredicates.pt_x(st1))), F64Repr.one())
  +det = rfe(F64Arith.mul(cross(e1x, e1y, d(x, VoronoiPredicates.pt_x(st1)), d(y, VoronoiPredicates.pt_y(st1))), cross(e1y, e1x, d(y, VoronoiPredicates.pt_y(st2)), d(x, VoronoiPredicates.pt_x(st2)))), err(3))
  +mx = F64Arith.sub(F64Arith.mul(F64Arith.add(num(VoronoiPredicates.pt_x(st1)), num(VoronoiPredicates.pt_x(st2))), F64Repr.half()), num(x))
  +my = F64Arith.sub(F64Arith.mul(F64Arith.add(num(VoronoiPredicates.pt_y(st1)), num(VoronoiPredicates.pt_y(st2))), F64Repr.half()), num(y))
  +t1 = VoronoiRobust.rd_sub_rf(VoronoiRobust.rd_sub_rf(VoronoiRobust.rd_zero(), VoronoiRobust.rf_mul(rf(a1), rf(mx))), VoronoiRobust.rf_mul(rf(b1), rf(my)))
  +t = VoronoiRobust.rd_div_assign(with_det(t1, det, U32.is_eq(index, 2)), a)
  +cx = VoronoiRobust.rd_add(VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), rf(half_sum(VoronoiPredicates.pt_x(st1), VoronoiPredicates.pt_x(st2)))), VoronoiRobust.rf_mul_rd(rf(a1), t))
  +cy = VoronoiRobust.rd_add(VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), rf(half_sum(VoronoiPredicates.pt_y(st1), VoronoiPredicates.pt_y(st2)))), VoronoiRobust.rf_mul_rd(rf(b1), t))
  +shift = VoronoiRobust.rf_div(VoronoiRobust.rf_mul(rf(F64Repr.half()), c), VoronoiRobust.rf_sqrt(a))
  +lx = Bool.pick(VoronoiRobust.RD, VoronoiRobust.rf_is_neg(c), VoronoiRobust.rd_sub_rf(cx, shift), VoronoiRobust.rd_add_rf(cx, shift))
  pss_finish(s1, s2, s3, index, cx, cy, lx)

def pss_a(nonneg: Bool, +a: VoronoiRobust.RF, +orientation: VoronoiRobust.RF, +q1: VoronoiRobust.RF, +q2: VoronoiRobust.RF) -> VoronoiRobust.RF:
  match nonneg:
    case True{}:
      VoronoiRobust.rf_add(a, VoronoiRobust.rf_mul(q1, q2))
    case False{}:
      VoronoiRobust.rf_div(VoronoiRobust.rf_mul(orientation, orientation), VoronoiRobust.rf_sub(VoronoiRobust.rf_mul(q1, q2), a))

type Lines is Data:
  Lines{a1: F64Repr.F64, b1: F64Repr.F64, a2: F64Repr.F64, b2: F64Repr.F64, q1: VoronoiRobust.RF, q2: VoronoiRobust.RF}

def pss_b(+ix: VoronoiRobust.RD, +iy: VoronoiRobust.RD, +l: Lines, +c1: VoronoiRobust.RF, +c2: VoronoiRobust.RF) -> VoronoiRobust.RD:
  match l:
    case Lines{+a1, +b1, +a2, +b2, +q1, +q2}:
      +b1s = VoronoiRobust.rd_add(VoronoiRobust.rd_zero(), VoronoiRobust.rd_mul_rf(ix, VoronoiRobust.rf_mul(rf(a1), q2)))
      +b2s = VoronoiRobust.rd_add(b1s, VoronoiRobust.rd_mul_rf(ix, VoronoiRobust.rf_mul(rf(a2), q1)))
      +b3s = VoronoiRobust.rd_add(b2s, VoronoiRobust.rd_mul_rf(iy, VoronoiRobust.rf_mul(rf(b1), q2)))
      +b4s = VoronoiRobust.rd_add(b3s, VoronoiRobust.rd_mul_rf(iy, VoronoiRobust.rf_mul(rf(b2), q1)))
      VoronoiRobust.rd_sub_rf(VoronoiRobust.rd_sub_rf(b4s, VoronoiRobust.rf_mul(q1, c1)), VoronoiRobust.rf_mul(q2, c2))

def pss_centre(+i: VoronoiRobust.RD, +t: VoronoiRobust.RD, +f1: F64Repr.F64, +f2: F64Repr.F64, +q1: VoronoiRobust.RF, +q2: VoronoiRobust.RF) -> VoronoiRobust.RD:
  VoronoiRobust.rd_add(VoronoiRobust.rd_add(i, VoronoiRobust.rd_mul_rf(t, VoronoiRobust.rf_mul(rf(f1), q2))), VoronoiRobust.rd_mul_rf(t, VoronoiRobust.rf_mul(rf(f2), q1)))

def pss_slanted_finish(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, +l: Lines, +ix: VoronoiRobust.RD, +iy: VoronoiRobust.RD, +t: VoronoiRobust.RD, +orientation: VoronoiRobust.RF) -> VoronoiPredicates.Circle:
  match l:
    case Lines{+a1, +b1, +a2, +b2, +q1, +q2}:
      +cx = pss_centre(ix, t, a1, a2, q1, q2)
      +cy = pss_centre(iy, t, b1, b2, q1, q2)
      +tp = VoronoiRobust.rd_make_positive(t)
      +lx = Bool.pick(VoronoiRobust.RD, VoronoiRobust.rf_is_neg(orientation), VoronoiRobust.rd_sub(cx, VoronoiRobust.rd_mul_rf(tp, orientation)), VoronoiRobust.rd_add(cx, VoronoiRobust.rd_mul_rf(tp, orientation)))
      pss_finish(s1, s2, s3, index, cx, cy, lx)

def pss_slanted(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, +st1: VoronoiPredicates.Pt, +en1: VoronoiPredicates.Pt, +st2: VoronoiPredicates.Pt, +en2: VoronoiPredicates.Pt, +a1: F64Repr.F64, +b1: F64Repr.F64, +a2: F64Repr.F64, +b2: F64Repr.F64, +orientation: VoronoiRobust.RF) -> VoronoiPredicates.Circle:
  +x = VoronoiPredicates.site_x0(s1)
  +y = VoronoiPredicates.site_y0(s1)
  +e1x = d(VoronoiPredicates.pt_x(en1), VoronoiPredicates.pt_x(st1))
  +e1y = d(VoronoiPredicates.pt_y(en1), VoronoiPredicates.pt_y(st1))
  +e2x = d(VoronoiPredicates.pt_x(en2), VoronoiPredicates.pt_x(st2))
  +e2y = d(VoronoiPredicates.pt_y(en2), VoronoiPredicates.pt_y(st2))
  +q1 = rfe(F64Arith.sqrt(sqr_sum(a1, b1)), err(2))
  +q2 = rfe(F64Arith.sqrt(sqr_sum(a2, b2)), err(2))
  +a0 = rfe(cross(e1x, e1y, d(VoronoiPredicates.pt_y(st2), VoronoiPredicates.pt_y(en2)), e2x), F64Repr.one())
  +a = pss_a(Bool.not(VoronoiRobust.rf_is_neg(a0)), a0, orientation, q1, q2)
  +or1 = rfe(cross(e1y, e1x, d(VoronoiPredicates.pt_y(en1), y), d(VoronoiPredicates.pt_x(en1), x)), F64Repr.one())
  +or2 = rfe(cross(e2x, e2y, d(VoronoiPredicates.pt_x(en2), x), d(VoronoiPredicates.pt_y(en2), y)), F64Repr.one())
  +det = VoronoiRobust.rf_mul(VoronoiRobust.rf_mul(VoronoiRobust.rf_mul(rf(F64Repr.two()), a), or1), or2)
  +c1 = rfe(cross(e1y, e1x, w(VoronoiPredicates.pt_y(en1)), w(VoronoiPredicates.pt_x(en1))), F64Repr.one())
  +c2 = rfe(cross(e2x, e2y, w(VoronoiPredicates.pt_x(en2)), w(VoronoiPredicates.pt_y(en2))), F64Repr.one())
  +inv = VoronoiRobust.rf_div(rf(F64Repr.one()), orientation)
  +ix = VoronoiRobust.rd_add_rf(VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), VoronoiRobust.rf_mul(VoronoiRobust.rf_mul(rf(a2), c1), inv)), VoronoiRobust.rf_mul(VoronoiRobust.rf_mul(rf(a1), c2), inv))
  +iy = VoronoiRobust.rd_add_rf(VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), VoronoiRobust.rf_mul(VoronoiRobust.rf_mul(rf(b1), c2), inv)), VoronoiRobust.rf_mul(VoronoiRobust.rf_mul(rf(b2), c1), inv))
  +l = {Lines{a1, b1, a2, b2, q1, q2} : Lines}
  +k1 = rfe(cross(e2x, e2y, w((0 - y : U32)), w(x)), F64Repr.one())
  +k2 = rfe(cross(e1x, e1y, w((0 - y : U32)), w(x)), F64Repr.one())
  +b = pss_b(ix, iy, l, k1, k2)
  +t = VoronoiRobust.rd_div_assign(with_det(VoronoiRobust.rd_sub(VoronoiRobust.rd_zero(), b), det, U32.is_eq(index, 2)), VoronoiRobust.rf_mul(a, a))
  pss_slanted_finish(s1, s2, s3, index, l, ix, iy, t, orientation)

def delta_x(+p: VoronoiPredicates.Pt, +q: VoronoiPredicates.Pt) -> F64Repr.F64:
  F64Arith.sub(num(VoronoiPredicates.pt_x(p)), num(VoronoiPredicates.pt_x(q)))

def delta_y(+p: VoronoiPredicates.Pt, +q: VoronoiPredicates.Pt) -> F64Repr.F64:
  F64Arith.sub(num(VoronoiPredicates.pt_y(p)), num(VoronoiPredicates.pt_y(q)))

def pss_route(collinear: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32, +st1: VoronoiPredicates.Pt, +en1: VoronoiPredicates.Pt, +st2: VoronoiPredicates.Pt, +en2: VoronoiPredicates.Pt, +orientation: VoronoiRobust.RF) -> VoronoiPredicates.Circle:
  match collinear:
    case True{}:
      pss_collinear(s1, s2, s3, index, st1, en1, st2, delta_x(en1, st1), delta_y(en1, st1))
    case False{}:
      pss_slanted(s1, s2, s3, index, st1, en1, st2, en2, delta_x(en1, st1), delta_y(en1, st1), delta_x(en2, st2), delta_y(en2, st2), orientation)

# lazy_circle_formation_functor::pss(site1, site2, site3, point_index).
def pss(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32) -> VoronoiPredicates.Circle:
  +st1 = VoronoiPredicates.end(s2)
  +en1 = VoronoiPredicates.start(s2)
  +st2 = VoronoiPredicates.start(s3)
  +en2 = VoronoiPredicates.end(s3)
  +orientation = rfe(cross(d(VoronoiPredicates.pt_y(en1), VoronoiPredicates.pt_y(st1)), d(VoronoiPredicates.pt_x(en1), VoronoiPredicates.pt_x(st1)), d(VoronoiPredicates.pt_y(en2), VoronoiPredicates.pt_y(st2)), d(VoronoiPredicates.pt_x(en2), VoronoiPredicates.pt_x(st2))), F64Repr.one())
  pss_route(VoronoiRobust.rf_is_zero(orientation), s1, s2, s3, index, st1, en1, st2, en2, orientation)

type Seg is Data:
  Seg{a: VoronoiRobust.RF, b: VoronoiRobust.RF, c: VoronoiRobust.RF, len: VoronoiRobust.RF, dx: F64Word.W64, dy: F64Word.W64}

def sss_seg(+s: VoronoiPredicates.Site) -> Seg:
  +st = VoronoiPredicates.start(s)
  +en = VoronoiPredicates.end(s)
  +a = rf(F64Arith.sub(num(VoronoiPredicates.pt_x(en)), num(VoronoiPredicates.pt_x(st))))
  +b = rf(F64Arith.sub(num(VoronoiPredicates.pt_y(en)), num(VoronoiPredicates.pt_y(st))))
  +c = rfe(cross(w(VoronoiPredicates.pt_x(st)), w(VoronoiPredicates.pt_y(st)), w(VoronoiPredicates.pt_x(en)), w(VoronoiPredicates.pt_y(en))), F64Repr.one())
  Seg{a, b, c, VoronoiRobust.rf_sqrt(VoronoiRobust.rf_add(VoronoiRobust.rf_mul(a, a), VoronoiRobust.rf_mul(b, b))), d(VoronoiPredicates.pt_x(en), VoronoiPredicates.pt_x(st)), d(VoronoiPredicates.pt_y(en), VoronoiPredicates.pt_y(st))}

def seg_cross(p: Seg, q: Seg) -> VoronoiRobust.RF:
  match p:
    case Seg{_, _, _, _, +pdx, +pdy}:
      match q:
        case Seg{_, _, _, _, +qdx, +qdy}:
          rfe(cross(pdx, pdy, qdx, qdy), F64Repr.one())

def seg_a(p: Seg) -> VoronoiRobust.RF:
  match p:
    case Seg{+a, _, _, _, _, _}:
      a

def seg_b(p: Seg) -> VoronoiRobust.RF:
  match p:
    case Seg{_, +b, _, _, _, _}:
      b

def seg_c(p: Seg) -> VoronoiRobust.RF:
  match p:
    case Seg{_, _, +c, _, _, _}:
      c

def seg_len(p: Seg) -> VoronoiRobust.RF:
  match p:
    case Seg{_, _, _, +l, _, _}:
      l

def term(+x: VoronoiRobust.RF, +y: VoronoiRobust.RF, +z: VoronoiRobust.RF) -> VoronoiRobust.RF:
  VoronoiRobust.rf_mul(VoronoiRobust.rf_mul(x, y), z)

def sss_centre(+f1: VoronoiRobust.RF, +f2: VoronoiRobust.RF, +f3: VoronoiRobust.RF, +p1: Seg, +p2: Seg, +p3: Seg) -> VoronoiRobust.RD:
  +s1 = VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), term(f1, seg_c(p2), seg_len(p3)))
  +s2 = VoronoiRobust.rd_sub_rf(s1, term(f2, seg_c(p1), seg_len(p3)))
  +s3 = VoronoiRobust.rd_add_rf(s2, term(f2, seg_c(p3), seg_len(p1)))
  +s4 = VoronoiRobust.rd_sub_rf(s3, term(f3, seg_c(p2), seg_len(p1)))
  +s5 = VoronoiRobust.rd_add_rf(s4, term(f3, seg_c(p1), seg_len(p2)))
  VoronoiRobust.rd_sub_rf(s5, term(f1, seg_c(p3), seg_len(p2)))

def recompute_sss(go: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +c: VoronoiPredicates.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VoronoiPredicates.Circle:
  match go:
    case True{}:
      VoronoiExact.sss(s1, s2, s3, c, rcx, rcy, rlx)
    case False{}:
      c

# lazy_circle_formation_functor::sss.
def sss(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> VoronoiPredicates.Circle:
  +p1 = sss_seg(s1)
  +p2 = sss_seg(s2)
  +p3 = sss_seg(s3)
  +x12 = seg_cross(p1, p2)
  +x23 = seg_cross(p2, p3)
  +x31 = seg_cross(p3, p1)
  +denom = VoronoiRobust.rd_add_rf(VoronoiRobust.rd_add_rf(VoronoiRobust.rd_add_rf(VoronoiRobust.rd_zero(), VoronoiRobust.rf_mul(x12, seg_len(p3))), VoronoiRobust.rf_mul(x23, seg_len(p1))), VoronoiRobust.rf_mul(x31, seg_len(p2)))
  +r = VoronoiRobust.rd_sub_rf(VoronoiRobust.rd_sub_rf(VoronoiRobust.rd_sub_rf(VoronoiRobust.rd_zero(), VoronoiRobust.rf_mul(x12, seg_c(p3))), VoronoiRobust.rf_mul(x23, seg_c(p1))), VoronoiRobust.rf_mul(x31, seg_c(p2)))
  +cx = sss_centre(seg_a(p1), seg_a(p2), seg_a(p3), p1, p2, p3)
  +cy = sss_centre(seg_b(p1), seg_b(p2), seg_b(p3), p1, p2, p3)
  +dd = VoronoiRobust.rd_dif(denom)
  +cxd = VoronoiRobust.rf_div(VoronoiRobust.rd_dif(cx), dd)
  +cyd = VoronoiRobust.rf_div(VoronoiRobust.rd_dif(cy), dd)
  +lxd = VoronoiRobust.rf_div(VoronoiRobust.rd_dif(VoronoiRobust.rd_add(cx, r)), dd)
  +rcx = VoronoiRobust.rf_needs_exact(cxd)
  +rcy = VoronoiRobust.rf_needs_exact(cyd)
  +rlx = VoronoiRobust.rf_needs_exact(lxd)
  recompute_sss(rcx || rcy || rlx, s1, s2, s3, VoronoiPredicates.Circle{VoronoiRobust.rf_value(cxd), VoronoiRobust.rf_value(cyd), VoronoiRobust.rf_value(lxd)}, rcx, rcy, rlx)

def formed(ok: Bool, +c: VoronoiPredicates.Circle) -> Maybe<&2, VoronoiPredicates.Circle>:
  match ok:
    case True{}:
      Some{c}
    case False{}:
      None{}

def form_pps(ok: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32) -> Maybe<&2, VoronoiPredicates.Circle>:
  match ok:
    case True{}:
      Some{pps(s1, s2, s3, index)}
    case False{}:
      None{}

def form_pss(ok: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +index: U32) -> Maybe<&2, VoronoiPredicates.Circle>:
  match ok:
    case True{}:
      Some{pss(s1, s2, s3, index)}
    case False{}:
      None{}

def form_ppp(ok: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  match ok:
    case True{}:
      Some{ppp(s1, s2, s3)}
    case False{}:
      None{}

def form_sss(ok: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  match ok:
    case True{}:
      Some{sss(s1, s2, s3)}
    case False{}:
      None{}

def form_p_p(point3: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  match point3:
    case True{}:
      form_ppp(VoronoiPredicates.exists_ppp(s1, s2, s3), s1, s2, s3)
    case False{}:
      form_pps(VoronoiPredicates.exists_pps(s1, s2, s3, 3), s1, s2, s3, 3)

def form_p_s(point3: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  match point3:
    case True{}:
      form_pps(VoronoiPredicates.exists_pps(s1, s3, s2, 2), s1, s3, s2, 2)
    case False{}:
      form_pss(VoronoiPredicates.exists_pss(s1, s2, s3, 1), s1, s2, s3, 1)

def form_s_p(point3: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  match point3:
    case True{}:
      form_pps(VoronoiPredicates.exists_pps(s2, s3, s1, 1), s2, s3, s1, 1)
    case False{}:
      form_pss(VoronoiPredicates.exists_pss(s2, s1, s3, 2), s2, s1, s3, 2)

def form_s_s(point3: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  match point3:
    case True{}:
      form_pss(VoronoiPredicates.exists_pss(s3, s1, s2, 3), s3, s1, s2, 3)
    case False{}:
      form_sss(VoronoiPredicates.exists_sss(s1, s2, s3), s1, s2, s3)

def form_p(point2: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  match point2:
    case True{}:
      form_p_p(VoronoiPredicates.is_point(s3), s1, s2, s3)
    case False{}:
      form_p_s(VoronoiPredicates.is_point(s3), s1, s2, s3)

def form_s(point2: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  match point2:
    case True{}:
      form_s_p(VoronoiPredicates.is_point(s3), s1, s2, s3)
    case False{}:
      form_s_s(VoronoiPredicates.is_point(s3), s1, s2, s3)

def form_route(point1: Bool, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  match point1:
    case True{}:
      form_p(VoronoiPredicates.is_point(s2), s1, s2, s3)
    case False{}:
      form_s(VoronoiPredicates.is_point(s2), s1, s2, s3)

# circle_formation_predicate(site1, site2, site3): the circle event of three consecutive arcs, if it exists.
def circle_formation(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site) -> Maybe<&2, VoronoiPredicates.Circle>:
  form_route(VoronoiPredicates.is_point(s1), s1, s2, s3)
