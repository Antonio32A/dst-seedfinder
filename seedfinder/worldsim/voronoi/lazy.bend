import Base
import ../../f64/word.bend as FW
import ../../f64/repr.bend as FR
import ../../f64/arith.bend as FA
import ./ctypes.bend as VT
import ./robust.bend as VR
import ./predicates.bend as VP
import ./exact.bend as VE

# Boost.Polygon 1.52 lazy_circle_formation_functor and circle_formation_predicate: each circle event is first
# computed in robust_fpt arithmetic, and a coordinate whose relative error exceeds 64 ulps is recomputed by the
# exact functor (exact.bend).

def rf(+v: FR.F64) -> VR.RF:
  VR.rf(v)

def rfe(+v: FR.F64, +e: FR.F64) -> VR.RF:
  VR.rf_err(v, e)

def num(+x: U32) -> FR.F64:
  FR.from_i32(x)

def err(+k: U32) -> FR.F64:
  FR.from_u32(k)

def cross(+a1: FW.W64, +b1: FW.W64, +a2: FW.W64, +b2: FW.W64) -> FR.F64:
  VP.cross(a1, b1, a2, b2)

def d(+a: U32, +b: U32) -> FW.W64:
  VT.dif32(a, b)

def w(+a: U32) -> FW.W64:
  VT.widen(a)

def triple(+a: FR.F64, +b: FR.F64, +c: FR.F64) -> FR.F64:
  FA.mul(FA.mul(a, b), c)

def sqr_sum(+a: FR.F64, +b: FR.F64) -> FR.F64:
  FA.add(FA.mul(a, a), FA.mul(b, b))

def rd_value(+x: VR.RD) -> FR.F64:
  VR.rf_value(VR.rd_dif(x))

def rd_exact(+x: VR.RD) -> Bool:
  VR.rf_needs_exact(VR.rd_dif(x))

def recompute_ppp(go: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +c: VP.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match go:
    case True{}:
      VE.ppp(s1, s2, s3, c, rcx, rcy, rlx)
    case False{}:
      c

def ppp_sums(+dx1: FR.F64, +dy1: FR.F64, +dx2: FR.F64, +dy2: FR.F64, +sx1: FR.F64, +sy1: FR.F64, +sx2: FR.F64, +sy2: FR.F64) -> VR.RD:
  +two = err(2)
  +c1 = VR.rd_add_rf(VR.rd_zero(), rfe(triple(dx1, sx1, dy2), two))
  +c2 = VR.rd_add_rf(c1, rfe(triple(dy1, sy1, dy2), two))
  +c3 = VR.rd_sub_rf(c2, rfe(triple(dx2, sx2, dy1), two))
  VR.rd_sub_rf(c3, rfe(triple(dy2, sy2, dy1), two))

def ppp_sums_y(+dx1: FR.F64, +dy1: FR.F64, +dx2: FR.F64, +dy2: FR.F64, +sx1: FR.F64, +sy1: FR.F64, +sx2: FR.F64, +sy2: FR.F64) -> VR.RD:
  +two = err(2)
  +c1 = VR.rd_add_rf(VR.rd_zero(), rfe(triple(dx2, sx2, dx1), two))
  +c2 = VR.rd_add_rf(c1, rfe(triple(dy2, sy2, dx1), two))
  +c3 = VR.rd_sub_rf(c2, rfe(triple(dx1, sx1, dx2), two))
  VR.rd_sub_rf(c3, rfe(triple(dy1, sy1, dx2), two))

def unscaled(+cx: VR.RD, +cy: VR.RD, +lx: VR.RD) -> VP.Circle:
  VP.Circle{rd_value(cx), rd_value(cy), rd_value(lx)}

def scaled(+cx: VR.RD, +cy: VR.RD, +lx: VR.RD, +inv: FR.F64) -> VP.Circle:
  VP.Circle{FA.mul(rd_value(cx), inv), FA.mul(rd_value(cy), inv), FA.mul(rd_value(lx), inv)}

def ppp_finish(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +cx: VR.RD, +cy: VR.RD, +lx: VR.RD, +inv: FR.F64) -> VP.Circle:
  +rcx = rd_exact(cx)
  +rcy = rd_exact(cy)
  +rlx = rd_exact(lx)
  recompute_ppp(rcx || rcy || rlx, s1, s2, s3, scaled(cx, cy, lx, inv), rcx, rcy, rlx)

# lazy_circle_formation_functor::ppp.
def ppp(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> VP.Circle:
  +x1 = VP.site_x0(s1)
  +y1 = VP.site_y0(s1)
  +x2 = VP.site_x0(s2)
  +y2 = VP.site_y0(s2)
  +x3 = VP.site_x0(s3)
  +y3 = VP.site_y0(s3)
  +dx1 = FA.sub(num(x1), num(x2))
  +dx2 = FA.sub(num(x2), num(x3))
  +dy1 = FA.sub(num(y1), num(y2))
  +dy2 = FA.sub(num(y2), num(y3))
  +inv = VR.rf_value(rfe(FA.div(FR.half(), cross(d(x1, x2), d(x2, x3), d(y1, y2), d(y2, y3))), err(2)))
  +sx1 = FA.add(num(x1), num(x2))
  +sx2 = FA.add(num(x2), num(x3))
  +sy1 = FA.add(num(y1), num(y2))
  +sy2 = FA.add(num(y2), num(y3))
  +dx3 = FA.sub(num(x1), num(x3))
  +dy3 = FA.sub(num(y1), num(y3))
  +cx = ppp_sums(dx1, dy1, dx2, dy2, sx1, sy1, sx2, sy2)
  +cy = ppp_sums_y(dx1, dy1, dx2, dy2, sx1, sy1, sx2, sy2)
  +lx = VR.rd_sub_rf(cx, rfe(FA.sqrt(triple(sqr_sum(dx1, dy1), sqr_sum(dx2, dy2), sqr_sum(dx3, dy3))), err(5)))
  ppp_finish(s1, s2, s3, cx, cy, lx, inv)

def pps_t_collinear(+teta: VR.RF, +a: VR.RF) -> VR.RD:
  +t1 = VR.rd_add_rf(VR.rd_zero(), VR.rf_div(teta, VR.rf_mul(rf(err(8)), a)))
  VR.rd_sub_rf(t1, VR.rf_div(a, VR.rf_mul(rf(err(2)), teta)))

def pps_t_general(+teta: VR.RF, +a: VR.RF, +b: VR.RF, +denom: VR.RF, +middle: Bool) -> VR.RD:
  +det = VR.rf_sqrt(VR.rf_mul(VR.rf_mul(VR.rf_add(VR.rf_mul(teta, teta), VR.rf_mul(denom, denom)), a), b))
  +q = VR.rf_div(det, VR.rf_mul(denom, denom))
  +t1 = Bool.pick(VR.RD, middle, VR.rd_sub_rf(VR.rd_zero(), q), VR.rd_add_rf(VR.rd_zero(), q))
  VR.rd_add_rf(t1, VR.rf_div(VR.rf_mul(teta, VR.rf_add(a, b)), VR.rf_mul(VR.rf_mul(rf(err(2)), denom), denom)))

def pps_t(collinear: Bool, +teta: VR.RF, +a: VR.RF, +b: VR.RF, +denom: VR.RF, +middle: Bool) -> VR.RD:
  match collinear:
    case True{}:
      pps_t_collinear(teta, a)
    case False{}:
      pps_t_general(teta, a, b, denom, middle)

def recompute_pps(go: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, +c: VP.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match go:
    case True{}:
      VE.pps(s1, s2, s3, index, c, rcx, rcy, rlx)
    case False{}:
      c

def pps_finish(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, +cx: VR.RD, +cy: VR.RD, +lx: VR.RD) -> VP.Circle:
  +c = unscaled(cx, cy, lx)
  +rcx = rd_exact(cx)
  +rcy = rd_exact(cy)
  +rlx = rd_exact(lx)
  recompute_pps(rcx || rcy || rlx, s1, s2, s3, index, c, rcx, rcy, rlx)

def pps_lower(+s3: VP.Site, +la: FR.F64, +lb: FR.F64, +cx: VR.RD, +cy: VR.RD, +inv_len: VR.RF) -> VR.RD:
  +r1 = VR.rd_sub_rf(VR.rd_zero(), VR.rf_mul(rf(la), rf(num(VP.site_x0(s3)))))
  +r2 = VR.rd_sub_rf(r1, VR.rf_mul(rf(lb), rf(num(VP.site_y0(s3)))))
  +r3 = VR.rd_add(r2, VR.rf_mul_rd(rf(la), cx))
  +r = VR.rd_make_positive(VR.rd_add(r3, VR.rf_mul_rd(rf(lb), cy)))
  VR.rd_add(cx, VR.rd_mul_rf(r, inv_len))

# lazy_circle_formation_functor::pps(site1, site2, site3, segment_index).
def pps(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32) -> VP.Circle:
  +st = VP.start(s3)
  +en = VP.end(s3)
  +p1 = VP.point1(s3)
  +x1 = VP.site_x0(s1)
  +y1 = VP.site_y0(s1)
  +x2 = VP.site_x0(s2)
  +y2 = VP.site_y0(s2)
  +la = FA.sub(num(VP.pt_y(en)), num(VP.pt_y(st)))
  +lb = FA.sub(num(VP.pt_x(st)), num(VP.pt_x(en)))
  +vx = FA.sub(num(y2), num(y1))
  +vy = FA.sub(num(x1), num(x2))
  +ila = d(VP.pt_y(en), VP.pt_y(st))
  +ilb = d(VP.pt_x(st), VP.pt_x(en))
  +teta = rfe(cross(ila, ilb, d(x2, x1), d(y2, y1)), FR.one())
  +a = rfe(cross(ila, ilb, d(VP.pt_y(p1), y1), d(x1, VP.pt_x(p1))), FR.one())
  +b = rfe(cross(ila, ilb, d(VP.pt_y(p1), y2), d(x2, VP.pt_x(p1))), FR.one())
  +denom = rfe(cross(d(y2, y1), d(x1, x2), ila, ilb), FR.one())
  +inv_len = rfe(FA.div(FR.one(), FA.sqrt(sqr_sum(la, lb))), err(3))
  +t = pps_t(VR.rf_is_zero(denom), teta, a, b, denom, U32.is_eq(index, 2))
  +cx = VR.rd_add(VR.rd_add_rf(VR.rd_zero(), rf(FA.mul(FR.half(), FA.add(num(x1), num(x2))))), VR.rf_mul_rd(rf(vx), t))
  +cy = VR.rd_add(VR.rd_add_rf(VR.rd_zero(), rf(FA.mul(FR.half(), FA.add(num(y1), num(y2))))), VR.rf_mul_rd(rf(vy), t))
  pps_finish(s1, s2, s3, index, cx, cy, pps_lower(s3, la, lb, cx, cy, inv_len))

def recompute_pss(go: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, +c: VP.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match go:
    case True{}:
      VE.pss(s1, s2, s3, index, c, rcx, rcy, rlx)
    case False{}:
      c

def pss_finish(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, +cx: VR.RD, +cy: VR.RD, +lx: VR.RD) -> VP.Circle:
  +c = unscaled(cx, cy, lx)
  +rcx = rd_exact(cx)
  +rcy = rd_exact(cy)
  +rlx = rd_exact(lx)
  recompute_pss(rcx || rcy || rlx, s1, s2, s3, index, c, rcx, rcy, rlx)

def with_det(+t: VR.RD, +det: VR.RF, +second: Bool) -> VR.RD:
  Bool.pick(VR.RD, second, VR.rd_add_rf(t, VR.rf_sqrt(det)), VR.rd_sub_rf(t, VR.rf_sqrt(det)))

def half_sum(+a: U32, +b: U32) -> FR.F64:
  FA.mul(FR.half(), FA.add(num(a), num(b)))

def pss_collinear(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, +st1: VP.Pt, +en1: VP.Pt, +st2: VP.Pt, +a1: FR.F64, +b1: FR.F64) -> VP.Circle:
  +x = VP.site_x0(s1)
  +y = VP.site_y0(s1)
  +e1x = d(VP.pt_x(en1), VP.pt_x(st1))
  +e1y = d(VP.pt_y(en1), VP.pt_y(st1))
  +a = rfe(sqr_sum(a1, b1), err(2))
  +c = rfe(cross(e1y, e1x, d(VP.pt_y(st2), VP.pt_y(st1)), d(VP.pt_x(st2), VP.pt_x(st1))), FR.one())
  +det = rfe(FA.mul(cross(e1x, e1y, d(x, VP.pt_x(st1)), d(y, VP.pt_y(st1))), cross(e1y, e1x, d(y, VP.pt_y(st2)), d(x, VP.pt_x(st2)))), err(3))
  +mx = FA.sub(FA.mul(FA.add(num(VP.pt_x(st1)), num(VP.pt_x(st2))), FR.half()), num(x))
  +my = FA.sub(FA.mul(FA.add(num(VP.pt_y(st1)), num(VP.pt_y(st2))), FR.half()), num(y))
  +t1 = VR.rd_sub_rf(VR.rd_sub_rf(VR.rd_zero(), VR.rf_mul(rf(a1), rf(mx))), VR.rf_mul(rf(b1), rf(my)))
  +t = VR.rd_div_assign(with_det(t1, det, U32.is_eq(index, 2)), a)
  +cx = VR.rd_add(VR.rd_add_rf(VR.rd_zero(), rf(half_sum(VP.pt_x(st1), VP.pt_x(st2)))), VR.rf_mul_rd(rf(a1), t))
  +cy = VR.rd_add(VR.rd_add_rf(VR.rd_zero(), rf(half_sum(VP.pt_y(st1), VP.pt_y(st2)))), VR.rf_mul_rd(rf(b1), t))
  +shift = VR.rf_div(VR.rf_mul(rf(FR.half()), c), VR.rf_sqrt(a))
  +lx = Bool.pick(VR.RD, VR.rf_is_neg(c), VR.rd_sub_rf(cx, shift), VR.rd_add_rf(cx, shift))
  pss_finish(s1, s2, s3, index, cx, cy, lx)

def pss_a(nonneg: Bool, +a: VR.RF, +orientation: VR.RF, +q1: VR.RF, +q2: VR.RF) -> VR.RF:
  match nonneg:
    case True{}:
      VR.rf_add(a, VR.rf_mul(q1, q2))
    case False{}:
      VR.rf_div(VR.rf_mul(orientation, orientation), VR.rf_sub(VR.rf_mul(q1, q2), a))

type Lines is Data:
  Lines{a1: FR.F64, b1: FR.F64, a2: FR.F64, b2: FR.F64, q1: VR.RF, q2: VR.RF}

def pss_b(+ix: VR.RD, +iy: VR.RD, +l: Lines, +c1: VR.RF, +c2: VR.RF) -> VR.RD:
  match l:
    case Lines{+a1, +b1, +a2, +b2, +q1, +q2}:
      +b1s = VR.rd_add(VR.rd_zero(), VR.rd_mul_rf(ix, VR.rf_mul(rf(a1), q2)))
      +b2s = VR.rd_add(b1s, VR.rd_mul_rf(ix, VR.rf_mul(rf(a2), q1)))
      +b3s = VR.rd_add(b2s, VR.rd_mul_rf(iy, VR.rf_mul(rf(b1), q2)))
      +b4s = VR.rd_add(b3s, VR.rd_mul_rf(iy, VR.rf_mul(rf(b2), q1)))
      VR.rd_sub_rf(VR.rd_sub_rf(b4s, VR.rf_mul(q1, c1)), VR.rf_mul(q2, c2))

def pss_centre(+i: VR.RD, +t: VR.RD, +f1: FR.F64, +f2: FR.F64, +q1: VR.RF, +q2: VR.RF) -> VR.RD:
  VR.rd_add(VR.rd_add(i, VR.rd_mul_rf(t, VR.rf_mul(rf(f1), q2))), VR.rd_mul_rf(t, VR.rf_mul(rf(f2), q1)))

def pss_slanted_finish(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, +l: Lines, +ix: VR.RD, +iy: VR.RD, +t: VR.RD, +orientation: VR.RF) -> VP.Circle:
  match l:
    case Lines{+a1, +b1, +a2, +b2, +q1, +q2}:
      +cx = pss_centre(ix, t, a1, a2, q1, q2)
      +cy = pss_centre(iy, t, b1, b2, q1, q2)
      +tp = VR.rd_make_positive(t)
      +lx = Bool.pick(VR.RD, VR.rf_is_neg(orientation), VR.rd_sub(cx, VR.rd_mul_rf(tp, orientation)), VR.rd_add(cx, VR.rd_mul_rf(tp, orientation)))
      pss_finish(s1, s2, s3, index, cx, cy, lx)

def pss_slanted(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, +st1: VP.Pt, +en1: VP.Pt, +st2: VP.Pt, +en2: VP.Pt, +a1: FR.F64, +b1: FR.F64, +a2: FR.F64, +b2: FR.F64, +orientation: VR.RF) -> VP.Circle:
  +x = VP.site_x0(s1)
  +y = VP.site_y0(s1)
  +e1x = d(VP.pt_x(en1), VP.pt_x(st1))
  +e1y = d(VP.pt_y(en1), VP.pt_y(st1))
  +e2x = d(VP.pt_x(en2), VP.pt_x(st2))
  +e2y = d(VP.pt_y(en2), VP.pt_y(st2))
  +q1 = rfe(FA.sqrt(sqr_sum(a1, b1)), err(2))
  +q2 = rfe(FA.sqrt(sqr_sum(a2, b2)), err(2))
  +a0 = rfe(cross(e1x, e1y, d(VP.pt_y(st2), VP.pt_y(en2)), e2x), FR.one())
  +a = pss_a(Bool.not(VR.rf_is_neg(a0)), a0, orientation, q1, q2)
  +or1 = rfe(cross(e1y, e1x, d(VP.pt_y(en1), y), d(VP.pt_x(en1), x)), FR.one())
  +or2 = rfe(cross(e2x, e2y, d(VP.pt_x(en2), x), d(VP.pt_y(en2), y)), FR.one())
  +det = VR.rf_mul(VR.rf_mul(VR.rf_mul(rf(FR.two()), a), or1), or2)
  +c1 = rfe(cross(e1y, e1x, w(VP.pt_y(en1)), w(VP.pt_x(en1))), FR.one())
  +c2 = rfe(cross(e2x, e2y, w(VP.pt_x(en2)), w(VP.pt_y(en2))), FR.one())
  +inv = VR.rf_div(rf(FR.one()), orientation)
  +ix = VR.rd_add_rf(VR.rd_add_rf(VR.rd_zero(), VR.rf_mul(VR.rf_mul(rf(a2), c1), inv)), VR.rf_mul(VR.rf_mul(rf(a1), c2), inv))
  +iy = VR.rd_add_rf(VR.rd_add_rf(VR.rd_zero(), VR.rf_mul(VR.rf_mul(rf(b1), c2), inv)), VR.rf_mul(VR.rf_mul(rf(b2), c1), inv))
  +l = {Lines{a1, b1, a2, b2, q1, q2} : Lines}
  +k1 = rfe(cross(e2x, e2y, w((0 - y : U32)), w(x)), FR.one())
  +k2 = rfe(cross(e1x, e1y, w((0 - y : U32)), w(x)), FR.one())
  +b = pss_b(ix, iy, l, k1, k2)
  +t = VR.rd_div_assign(with_det(VR.rd_sub(VR.rd_zero(), b), det, U32.is_eq(index, 2)), VR.rf_mul(a, a))
  pss_slanted_finish(s1, s2, s3, index, l, ix, iy, t, orientation)

def delta_x(+p: VP.Pt, +q: VP.Pt) -> FR.F64:
  FA.sub(num(VP.pt_x(p)), num(VP.pt_x(q)))

def delta_y(+p: VP.Pt, +q: VP.Pt) -> FR.F64:
  FA.sub(num(VP.pt_y(p)), num(VP.pt_y(q)))

def pss_route(collinear: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, +st1: VP.Pt, +en1: VP.Pt, +st2: VP.Pt, +en2: VP.Pt, +orientation: VR.RF) -> VP.Circle:
  match collinear:
    case True{}:
      pss_collinear(s1, s2, s3, index, st1, en1, st2, delta_x(en1, st1), delta_y(en1, st1))
    case False{}:
      pss_slanted(s1, s2, s3, index, st1, en1, st2, en2, delta_x(en1, st1), delta_y(en1, st1), delta_x(en2, st2), delta_y(en2, st2), orientation)

# lazy_circle_formation_functor::pss(site1, site2, site3, point_index).
def pss(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32) -> VP.Circle:
  +st1 = VP.end(s2)
  +en1 = VP.start(s2)
  +st2 = VP.start(s3)
  +en2 = VP.end(s3)
  +orientation = rfe(cross(d(VP.pt_y(en1), VP.pt_y(st1)), d(VP.pt_x(en1), VP.pt_x(st1)), d(VP.pt_y(en2), VP.pt_y(st2)), d(VP.pt_x(en2), VP.pt_x(st2))), FR.one())
  pss_route(VR.rf_is_zero(orientation), s1, s2, s3, index, st1, en1, st2, en2, orientation)

type Seg is Data:
  Seg{a: VR.RF, b: VR.RF, c: VR.RF, len: VR.RF, dx: FW.W64, dy: FW.W64}

def sss_seg(+s: VP.Site) -> Seg:
  +st = VP.start(s)
  +en = VP.end(s)
  +a = rf(FA.sub(num(VP.pt_x(en)), num(VP.pt_x(st))))
  +b = rf(FA.sub(num(VP.pt_y(en)), num(VP.pt_y(st))))
  +c = rfe(cross(w(VP.pt_x(st)), w(VP.pt_y(st)), w(VP.pt_x(en)), w(VP.pt_y(en))), FR.one())
  Seg{a, b, c, VR.rf_sqrt(VR.rf_add(VR.rf_mul(a, a), VR.rf_mul(b, b))), d(VP.pt_x(en), VP.pt_x(st)), d(VP.pt_y(en), VP.pt_y(st))}

def seg_cross(p: Seg, q: Seg) -> VR.RF:
  match p:
    case Seg{_, _, _, _, +pdx, +pdy}:
      match q:
        case Seg{_, _, _, _, +qdx, +qdy}:
          rfe(cross(pdx, pdy, qdx, qdy), FR.one())

def seg_a(p: Seg) -> VR.RF:
  match p:
    case Seg{+a, _, _, _, _, _}:
      a

def seg_b(p: Seg) -> VR.RF:
  match p:
    case Seg{_, +b, _, _, _, _}:
      b

def seg_c(p: Seg) -> VR.RF:
  match p:
    case Seg{_, _, +c, _, _, _}:
      c

def seg_len(p: Seg) -> VR.RF:
  match p:
    case Seg{_, _, _, +l, _, _}:
      l

def term(+x: VR.RF, +y: VR.RF, +z: VR.RF) -> VR.RF:
  VR.rf_mul(VR.rf_mul(x, y), z)

def sss_centre(+f1: VR.RF, +f2: VR.RF, +f3: VR.RF, +p1: Seg, +p2: Seg, +p3: Seg) -> VR.RD:
  +s1 = VR.rd_add_rf(VR.rd_zero(), term(f1, seg_c(p2), seg_len(p3)))
  +s2 = VR.rd_sub_rf(s1, term(f2, seg_c(p1), seg_len(p3)))
  +s3 = VR.rd_add_rf(s2, term(f2, seg_c(p3), seg_len(p1)))
  +s4 = VR.rd_sub_rf(s3, term(f3, seg_c(p2), seg_len(p1)))
  +s5 = VR.rd_add_rf(s4, term(f3, seg_c(p1), seg_len(p2)))
  VR.rd_sub_rf(s5, term(f1, seg_c(p3), seg_len(p2)))

def recompute_sss(go: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +c: VP.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match go:
    case True{}:
      VE.sss(s1, s2, s3, c, rcx, rcy, rlx)
    case False{}:
      c

# lazy_circle_formation_functor::sss.
def sss(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> VP.Circle:
  +p1 = sss_seg(s1)
  +p2 = sss_seg(s2)
  +p3 = sss_seg(s3)
  +x12 = seg_cross(p1, p2)
  +x23 = seg_cross(p2, p3)
  +x31 = seg_cross(p3, p1)
  +denom = VR.rd_add_rf(VR.rd_add_rf(VR.rd_add_rf(VR.rd_zero(), VR.rf_mul(x12, seg_len(p3))), VR.rf_mul(x23, seg_len(p1))), VR.rf_mul(x31, seg_len(p2)))
  +r = VR.rd_sub_rf(VR.rd_sub_rf(VR.rd_sub_rf(VR.rd_zero(), VR.rf_mul(x12, seg_c(p3))), VR.rf_mul(x23, seg_c(p1))), VR.rf_mul(x31, seg_c(p2)))
  +cx = sss_centre(seg_a(p1), seg_a(p2), seg_a(p3), p1, p2, p3)
  +cy = sss_centre(seg_b(p1), seg_b(p2), seg_b(p3), p1, p2, p3)
  +dd = VR.rd_dif(denom)
  +cxd = VR.rf_div(VR.rd_dif(cx), dd)
  +cyd = VR.rf_div(VR.rd_dif(cy), dd)
  +lxd = VR.rf_div(VR.rd_dif(VR.rd_add(cx, r)), dd)
  +rcx = VR.rf_needs_exact(cxd)
  +rcy = VR.rf_needs_exact(cyd)
  +rlx = VR.rf_needs_exact(lxd)
  recompute_sss(rcx || rcy || rlx, s1, s2, s3, VP.Circle{VR.rf_value(cxd), VR.rf_value(cyd), VR.rf_value(lxd)}, rcx, rcy, rlx)

def formed(ok: Bool, +c: VP.Circle) -> Maybe<&2, VP.Circle>:
  match ok:
    case True{}:
      Some{c}
    case False{}:
      None{}

def form_pps(ok: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32) -> Maybe<&2, VP.Circle>:
  match ok:
    case True{}:
      Some{pps(s1, s2, s3, index)}
    case False{}:
      None{}

def form_pss(ok: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32) -> Maybe<&2, VP.Circle>:
  match ok:
    case True{}:
      Some{pss(s1, s2, s3, index)}
    case False{}:
      None{}

def form_ppp(ok: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  match ok:
    case True{}:
      Some{ppp(s1, s2, s3)}
    case False{}:
      None{}

def form_sss(ok: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  match ok:
    case True{}:
      Some{sss(s1, s2, s3)}
    case False{}:
      None{}

def form_p_p(point3: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  match point3:
    case True{}:
      form_ppp(VP.exists_ppp(s1, s2, s3), s1, s2, s3)
    case False{}:
      form_pps(VP.exists_pps(s1, s2, s3, 3), s1, s2, s3, 3)

def form_p_s(point3: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  match point3:
    case True{}:
      form_pps(VP.exists_pps(s1, s3, s2, 2), s1, s3, s2, 2)
    case False{}:
      form_pss(VP.exists_pss(s1, s2, s3, 1), s1, s2, s3, 1)

def form_s_p(point3: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  match point3:
    case True{}:
      form_pps(VP.exists_pps(s2, s3, s1, 1), s2, s3, s1, 1)
    case False{}:
      form_pss(VP.exists_pss(s2, s1, s3, 2), s2, s1, s3, 2)

def form_s_s(point3: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  match point3:
    case True{}:
      form_pss(VP.exists_pss(s3, s1, s2, 3), s3, s1, s2, 3)
    case False{}:
      form_sss(VP.exists_sss(s1, s2, s3), s1, s2, s3)

def form_p(point2: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  match point2:
    case True{}:
      form_p_p(VP.is_point(s3), s1, s2, s3)
    case False{}:
      form_p_s(VP.is_point(s3), s1, s2, s3)

def form_s(point2: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  match point2:
    case True{}:
      form_s_p(VP.is_point(s3), s1, s2, s3)
    case False{}:
      form_s_s(VP.is_point(s3), s1, s2, s3)

def form_route(point1: Bool, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  match point1:
    case True{}:
      form_p(VP.is_point(s2), s1, s2, s3)
    case False{}:
      form_s(VP.is_point(s2), s1, s2, s3)

# circle_formation_predicate(site1, site2, site3): the circle event of three consecutive arcs, if it exists.
def circle_formation(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Maybe<&2, VP.Circle>:
  form_route(VP.is_point(s1), s1, s2, s3)
