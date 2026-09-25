import Base
import ../../f64/word.bend as FW
import ../../f64/repr.bend as FR
import ../../f64/arith.bend as FA
import ./ctypes.bend as VT
import ./robust.bend as VR
import ./predicates.bend as VP

# Boost.Polygon 1.52 mp_circle_formation_functor: the exact recomputation of a circle event's centre x, centre y
# and lower x, each only when its flag is set (Boost's rules for which values are refreshed together), with
# extended_int expressions evaluated in Boost's operator order and the sqrt expressions of robust.bend.

def times(+a: VT.Big, +b: VT.Big) -> VT.Big:
  VT.big_mul(a, b)

def plus(+a: VT.Big, +b: VT.Big) -> VT.Big:
  VT.big_add(a, b)

def minus(+a: VT.Big, +b: VT.Big) -> VT.Big:
  VT.big_sub(a, b)

def int(+x: U32) -> VT.Big:
  VT.big_of_i32(x)

def wide(+x: FW.W64) -> VT.Big:
  VT.big_of_i64(x)

def dif(+a: U32, +b: U32) -> VT.Big:
  wide(VT.dif32(a, b))

def sum(+a: U32, +b: U32) -> VT.Big:
  wide(VT.add64(VT.widen(a), VT.widen(b)))

def fpt(+b: VT.Big) -> FR.F64:
  VT.big_to_f64(b)

def set_x(c: VP.Circle, +v: FR.F64) -> VP.Circle:
  match c:
    case VP.Circle{_, +y, +lx}:
      VP.Circle{v, y, lx}

def set_y(c: VP.Circle, +v: FR.F64) -> VP.Circle:
  match c:
    case VP.Circle{+x, _, +lx}:
      VP.Circle{x, v, lx}

def set_lx(c: VP.Circle, +v: FR.F64) -> VP.Circle:
  match c:
    case VP.Circle{+x, +y, _}:
      VP.Circle{x, y, v}

def is_neg(+x: FR.F64) -> Bool:
  VR.is_neg(x)

def sign_flip(c: Bool, +b: VT.Big) -> VT.Big:
  VT.big_negate_if(c, b)

def sqr_sum(+a: VT.Big, +b: VT.Big) -> VT.Big:
  plus(times(a, a), times(b, b))

type Ppp is Data:
  Ppp{dx0: VT.Big, dx1: VT.Big, dx2: VT.Big, dy0: VT.Big, dy1: VT.Big, dy2: VT.Big, n1: VT.Big, n2: VT.Big, inv: FR.F64}

def ppp_negative_lower(nonneg: Bool, +cx: VT.Big, +sqr_r: VT.Big, +x: FR.F64, +r: FR.F64, +inv: FR.F64) -> FR.F64:
  match nonneg:
    case True{}:
      FR.pick(is_neg(inv), FA.sub(x, FA.mul(r, inv)), FA.add(x, FA.mul(r, inv)))
    case False{}:
      FA.div(FA.mul(fpt(minus(times(cx, cx), sqr_r)), inv), FA.add(fpt(cx), r))

def ppp_lower(go: Bool, c: VP.Circle, +p: Ppp, +cx: VT.Big, +x: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      match p:
        case Ppp{+dx0, +dx1, +dx2, +dy0, +dy1, +dy2, _, _, +inv}:
          +sqr_r = times(times(sqr_sum(dx0, dy0), sqr_sum(dx1, dy1)), sqr_sum(dx2, dy2))
          +r = FA.sqrt(fpt(sqr_r))
          set_lx(c, ppp_negative_lower(Bool.not(is_neg(x)), cx, sqr_r, x, r, inv))
    case False{}:
      c

def ppp_x(go: Bool, c: VP.Circle, +p: Ppp, +rlx: Bool) -> VP.Circle:
  match go:
    case True{}:
      match p:
        case Ppp{_, _, _, +dy0, +dy1, _, +n1, +n2, +inv}:
          +cx = minus(times(n1, dy1), times(n2, dy0))
          +x = FA.mul(fpt(cx), inv)
          ppp_lower(rlx, set_x(c, x), p, cx, x)
    case False{}:
      c

def ppp_y(go: Bool, c: VP.Circle, +p: Ppp) -> VP.Circle:
  match go:
    case True{}:
      match p:
        case Ppp{+dx0, +dx1, _, _, _, _, +n1, +n2, +inv}:
          set_y(c, FA.mul(fpt(minus(times(n2, dx0), times(n1, dx1))), inv))
    case False{}:
      c

def ppp_terms(+x1: U32, +y1: U32, +x2: U32, +y2: U32, +x3: U32, +y3: U32) -> Ppp:
  +dx0 = dif(x1, x2)
  +dx1 = dif(x2, x3)
  +dy0 = dif(y1, y2)
  +dy1 = dif(y2, y3)
  +inv = FA.div(FR.half(), fpt(minus(times(dx0, dy1), times(dx1, dy0))))
  +n1 = plus(times(dx0, sum(x1, x2)), times(dy0, sum(y1, y2)))
  +n2 = plus(times(dx1, sum(x2, x3)), times(dy1, sum(y2, y3)))
  Ppp{dx0, dx1, dif(x1, x3), dy0, dy1, dif(y1, y3), n1, n2, inv}

# mp_circle_formation_functor::ppp.
def ppp(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, c: VP.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  +p = ppp_terms(VP.site_x0(s1), VP.site_y0(s1), VP.site_x0(s2), VP.site_y0(s2), VP.site_x0(s3), VP.site_y0(s3))
  ppp_y(rcy, ppp_x(rcx || rlx, c, p, rlx), p)

type Pps is Data:
  Pps{la: VT.Big, lb: VT.Big, seg: VT.Big, vx: VT.Big, vy: VT.Big, sx: VT.Big, sy: VT.Big, teta: VT.Big, denom: VT.Big, a: VT.Big, b: VT.Big}

def pps_terms(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site) -> Pps:
  +st = VP.start(s3)
  +en = VP.end(s3)
  +p1 = VP.point1(s3)
  +x1 = VP.site_x0(s1)
  +y1 = VP.site_y0(s1)
  +x2 = VP.site_x0(s2)
  +y2 = VP.site_y0(s2)
  +la = dif(VP.pt_y(en), VP.pt_y(st))
  +lb = dif(VP.pt_x(st), VP.pt_x(en))
  +vx = dif(y2, y1)
  +vy = dif(x1, x2)
  +a = minus(times(la, dif(x1, VP.pt_x(p1))), times(lb, dif(VP.pt_y(p1), y1)))
  +b = minus(times(la, dif(x2, VP.pt_x(p1))), times(lb, dif(VP.pt_y(p1), y2)))
  Pps{la, lb, sqr_sum(la, lb), vx, vy, sum(x1, x2), sum(y1, y2), plus(times(la, vx), times(lb, vy)), minus(times(vx, lb), times(vy, la)), a, b}

def quarter() -> FR.F64:
  FR.F64{1070596096, 0}

def pps_parallel_lower(go: Bool, c: VP.Circle, +a0: VT.Big, +a1: VT.Big, +seg: VT.Big, +inv: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      +e = VT.efpt_to_f64(VR.eval2(a0, a1, seg, int(1)))
      set_lx(c, FA.div(FA.mul(FA.mul(quarter(), e), inv), FA.sqrt(fpt(seg))))
    case False{}:
      c

def quarter_scaled(+a: VT.Big, +inv: FR.F64) -> FR.F64:
  FA.mul(FA.mul(quarter(), fpt(a)), inv)

def pps_parallel(+p: Pps, +c: VP.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match p:
    case Pps{_, _, +seg, +vx, +vy, +sx, +sy, +teta, _, +a, +b}:
      +ab = plus(a, b)
      +numer = minus(times(teta, teta), times(ab, ab))
      +den = times(teta, ab)
      +a0 = plus(VT.big_mul_i32(times(den, sx), 2), times(numer, vx))
      +a1 = plus(VT.big_mul_i32(times(den, ab), 2), times(numer, teta))
      +a2 = plus(VT.big_mul_i32(times(den, sy), 2), times(numer, vy))
      +inv = FA.div(FR.one(), fpt(den))
      +cx = FR.pick(rcx, quarter_scaled(a0, inv), VP.circle_x(c))
      +cy = FR.pick(rcy, quarter_scaled(a2, inv), VP.circle_y(c))
      pps_parallel_lower(rlx, VP.Circle{cx, cy, VP.circle_lx(c)}, a0, a1, seg, inv)

def half_scaled(+e: VT.Efpt, +inv: FR.F64) -> FR.F64:
  FA.mul(FA.mul(FR.half(), VT.efpt_to_f64(e)), inv)

def pps_x(go: Bool, c: VP.Circle, +a0: VT.Big, +a1: VT.Big, +det: VT.Big, +inv: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      set_x(c, half_scaled(VR.eval2(a0, a1, int(1), det), inv))
    case False{}:
      c

def pps_y(go: Bool, c: VP.Circle, +a2: VT.Big, +a3: VT.Big, +det: VT.Big, +inv: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      set_y(c, half_scaled(VR.eval2(a2, a3, int(1), det), inv))
    case False{}:
      c

def pps_lower(go: Bool, c: VP.Circle, +p: Pps, +a0: VT.Big, +a1: VT.Big, +det: VT.Big, +inv: FR.F64, +middle: Bool) -> VP.Circle:
  match go:
    case True{}:
      match p:
        case Pps{_, _, +seg, _, _, _, _, +teta, +denom, +a, +b}:
          +a2 = times(plus(a, b), plus(times(denom, denom), times(teta, teta)))
          +e = VR.eval4(a0, a1, a2, sign_flip(middle, teta), times(int(1), seg), times(det, seg), int(1), det)
          set_lx(c, FA.div(half_scaled(e, inv), FA.sqrt(fpt(seg))))
    case False{}:
      c

def pps_general(+p: Pps, c: VP.Circle, +middle: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match p:
    case Pps{_, _, _, +vx, +vy, +sx, +sy, +teta, +denom, +a, +b}:
      +det = VT.big_mul_i32(times(times(plus(times(teta, teta), times(denom, denom)), a), b), 4)
      +inv1 = FA.div(FR.one(), fpt(denom))
      +inv = FA.mul(inv1, inv1)
      +ab = plus(a, b)
      +a0 = plus(times(times(sx, denom), denom), times(times(teta, ab), vx))
      +a1 = sign_flip(middle, vx)
      +a2 = plus(times(times(sy, denom), denom), times(times(teta, ab), vy))
      +a3 = sign_flip(middle, vy)
      pps_lower(rlx, pps_y(rcy, pps_x(rcx, c, a0, a1, det, inv), a2, a3, det, inv), p, a0, a1, det, inv, middle)

def pps_route(parallel: Bool, +p: Pps, c: VP.Circle, +middle: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match parallel:
    case True{}:
      pps_parallel(p, c, rcx, rcy, rlx)
    case False{}:
      pps_general(p, c, middle, rcx, rcy, rlx)

def pps_denom(p: Pps) -> VT.Big:
  match p:
    case Pps{_, _, _, _, _, _, _, _, +denom, _, _}:
      denom

# mp_circle_formation_functor::pps(site1, site2, site3, segment_index).
def pps(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, c: VP.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  +p = pps_terms(s1, s2, s3)
  pps_route(VT.big_is_zero(pps_denom(p)), p, c, U32.is_eq(index, 2), rcx, rcy, rlx)

type Pss is Data:
  Pss{a0: VT.Big, b0: VT.Big, a1: VT.Big, b1: VT.Big, orientation: VT.Big}

def pss_terms(+st1: VP.Pt, +en1: VP.Pt, +st2: VP.Pt, +en2: VP.Pt) -> Pss:
  +a0 = dif(VP.pt_x(en1), VP.pt_x(st1))
  +b0 = dif(VP.pt_y(en1), VP.pt_y(st1))
  +a1 = dif(VP.pt_x(en2), VP.pt_x(st2))
  +b1 = dif(VP.pt_y(en2), VP.pt_y(st2))
  Pss{a0, b0, a1, b1, minus(times(a1, b0), times(a0, b1))}

def two_signed(+second: Bool) -> U32:
  FW.pick(second, 2, 4294967294)

def pss_parallel_y(go: Bool, c: VP.Circle, +a0: VT.Big, +b0: VT.Big, +cb0: VT.Big, +st1: VP.Pt, +st2: VP.Pt, +x: U32, +y: U32, +second: Bool, +denom: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      +ca0 = VT.big_mul_i32(b0, two_signed(second))
      +ya = times(times(a0, a0), sum(VP.pt_y(st1), VP.pt_y(st2)))
      +yb = times(times(a0, b0), wide(VT.sub64(VT.add64(VT.widen(VP.pt_x(st1)), VT.widen(VP.pt_x(st2))), VT.add64(VT.widen(x), VT.widen(x)))))
      +yc = times(times(b0, b0), wide(VT.add64(VT.widen(y), VT.widen(y))))
      set_y(c, FA.div(VT.efpt_to_f64(VR.eval2(ca0, plus(minus(ya, yb), yc), cb0, int(1))), denom))
    case False{}:
      c

def pss_parallel_x(go: Bool, c: VP.Circle, +ca0: VT.Big, +ca1: VT.Big, +cb0: VT.Big, +denom: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      set_x(c, FA.div(VT.efpt_to_f64(VR.eval2(ca0, ca1, cb0, int(1))), denom))
    case False{}:
      c

def pss_parallel_lower(go: Bool, c: VP.Circle, +ca0: VT.Big, +ca1: VT.Big, +c0: VT.Big, +cb0: VT.Big, +cb2: VT.Big, +denom: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      +ca2 = sign_flip(VT.big_is_neg(c0), c0)
      set_lx(c, FA.div(VT.efpt_to_f64(VR.eval3(ca0, ca1, ca2, cb0, int(1), cb2)), denom))
    case False{}:
      c

def pss_parallel_xl(go: Bool, c: VP.Circle, +a0: VT.Big, +b0: VT.Big, +c0: VT.Big, +cb0: VT.Big, +st1: VP.Pt, +st2: VP.Pt, +x: U32, +y: U32, +second: Bool, +denom: FR.F64, +rcx: Bool, +rlx: Bool) -> VP.Circle:
  match go:
    case True{}:
      +ca0 = VT.big_mul_i32(a0, two_signed(second))
      +xa = times(times(b0, b0), sum(VP.pt_x(st1), VP.pt_x(st2)))
      +xb = times(times(a0, b0), wide(VT.sub64(VT.add64(VT.widen(VP.pt_y(st1)), VT.widen(VP.pt_y(st2))), VT.add64(VT.widen(y), VT.widen(y)))))
      +xc = times(times(a0, a0), wide(VT.add64(VT.widen(x), VT.widen(x))))
      +ca1 = plus(minus(xa, xb), xc)
      pss_parallel_lower(rlx, pss_parallel_x(rcx, c, ca0, ca1, cb0, denom), ca0, ca1, c0, cb0, sqr_sum(a0, b0), denom)
    case False{}:
      c

def pss_parallel(+t: Pss, +st1: VP.Pt, +st2: VP.Pt, +s1: VP.Site, c: VP.Circle, +second: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match t:
    case Pss{+a0, +b0, _, _, _}:
      +x = VP.site_x0(s1)
      +y = VP.site_y0(s1)
      +denom = FA.mul(FR.two(), fpt(sqr_sum(a0, b0)))
      +c0 = minus(times(b0, dif(VP.pt_x(st2), VP.pt_x(st1))), times(a0, dif(VP.pt_y(st2), VP.pt_y(st1))))
      +dx = minus(times(a0, dif(y, VP.pt_y(st1))), times(b0, dif(x, VP.pt_x(st1))))
      +dy = minus(times(b0, dif(x, VP.pt_x(st2))), times(a0, dif(y, VP.pt_y(st2))))
      +cb0 = times(dx, dy)
      +cy = pss_parallel_y(rcy, c, a0, b0, cb0, st1, st2, x, y, second, denom)
      pss_parallel_xl(rcx || rlx, cy, a0, b0, c0, cb0, st1, st2, x, y, second, denom, rcx, rlx)

def pss4_first(same: Bool, +lh: VT.Efpt, +rh: VT.Efpt, +a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +b0: VT.Big, +b1: VT.Big, +b3: VT.Big, +b2: VT.Big) -> VT.Efpt:
  match same:
    case True{}:
      VT.efpt_add(lh, rh)
    case False{}:
      +c0 = minus(plus(times(times(a0, a0), b0), times(times(a1, a1), b1)), times(times(times(a2, a2), b3), b2))
      +c1 = minus(VT.big_mul_i32(times(a0, a1), 2), times(times(a2, a2), b3))
      VT.efpt_div(VR.eval2(c0, c1, int(1), times(b0, b1)), VT.efpt_sub(lh, rh))

def pss3_join(same: Bool, +lh: VT.Efpt, +rh: VT.Efpt, +a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +a3: VT.Big, +b0: VT.Big, +b1: VT.Big, +b3: VT.Big) -> VT.Efpt:
  match same:
    case True{}:
      VT.efpt_add(lh, rh)
    case False{}:
      +c0 = minus(minus(plus(times(times(a0, a0), b0), times(times(a1, a1), b1)), times(a2, a2)), times(times(times(a3, a3), b0), b1))
      +c1 = VT.big_mul_i32(minus(times(a0, a1), times(a2, a3)), 2)
      VT.efpt_div(VR.eval2(c0, c1, int(1), b3), VT.efpt_sub(lh, rh))

def pss3(+a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +a3: VT.Big, +b0: VT.Big, +b1: VT.Big, +b2: VT.Big, +b3: VT.Big) -> VT.Efpt:
  +lh = VR.eval2(a0, a1, b0, b1)
  +rh = VR.eval2(a2, a3, b2, b3)
  pss3_join(VR.same_sign_efpt(lh, rh), lh, rh, a0, a1, a2, a3, b0, b1, b3)

def pss4_second(same: Bool, +lh: VT.Efpt, +rh: VT.Efpt, +a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +a3: VT.Big, +b0: VT.Big, +b1: VT.Big, +b2: VT.Big, +b3: VT.Big) -> VT.Efpt:
  match same:
    case True{}:
      VT.efpt_add(lh, rh)
    case False{}:
      +c0 = VT.big_mul_i32(times(a3, a0), 2)
      +c1 = VT.big_mul_i32(times(a3, a1), 2)
      +c2 = minus(plus(plus(times(times(a0, a0), b0), times(times(a1, a1), b1)), times(a3, a3)), times(times(times(a2, a2), b2), b3))
      +c3 = minus(VT.big_mul_i32(times(a0, a1), 2), times(times(a2, a2), b3))
      VT.efpt_div(pss3(c0, c1, c2, c3, b0, b1, int(1), times(b0, b1)), VT.efpt_sub(lh, rh))

def pss4_route(zero: Bool, +a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +a3: VT.Big, +b0: VT.Big, +b1: VT.Big, +b2: VT.Big, +b3: VT.Big, +rh: VT.Efpt) -> VT.Efpt:
  match zero:
    case True{}:
      +lh = VR.eval2(a0, a1, b0, b1)
      pss4_first(VR.same_sign_efpt(lh, rh), lh, rh, a0, a1, a2, b0, b1, b3, b2)
    case False{}:
      +lh = VR.eval3(a0, a1, a3, b0, b1, int(1))
      pss4_second(VR.same_sign_efpt(lh, rh), lh, rh, a0, a1, a2, a3, b0, b1, b2, b3)

# sqrt_expr_evaluator_pss4.
def pss4(+a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +a3: VT.Big, +b0: VT.Big, +b1: VT.Big, +b2: VT.Big, +b3: VT.Big) -> VT.Efpt:
  +rh = VT.efpt_mul(VR.eval1(a2, b3), VT.efpt_sqrt(VR.eval2(int(1), b2, times(b0, b1), int(1))))
  pss4_route(VT.big_is_zero(a3), a0, a1, a2, a3, b0, b1, b2, b3, rh)

type Pss4 is Data:
  Pss4{b0: VT.Big, b1: VT.Big, b2: VT.Big, b3: VT.Big}

def pss4_with(+a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +a3: VT.Big, +bs: Pss4) -> FR.F64:
  match bs:
    case Pss4{+b0, +b1, +b2, +b3}:
      VT.efpt_to_f64(pss4(a0, a1, a2, a3, b0, b1, b2, b3))

type Meet is Data:
  Meet{ix: VT.Big, iy: VT.Big, dx: VT.Big, dy: VT.Big}

def pss_numer(+along: VT.Big, +i: VT.Big, +dx: VT.Big, +dy: VT.Big, +ea: VT.Big, +eb: VT.Big) -> VT.Big:
  minus(times(along, sqr_sum(dx, dy)), times(i, plus(times(dx, ea), times(dy, eb))))

def pss_general_y(go: Bool, c: VP.Circle, +t: Pss, +m: Meet, +sign: VT.Big, +bs: Pss4, +denom: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      match t:
        case Pss{+a0, +b0, +a1, +b1, _}:
          match m:
            case Meet{_, +iy, +dx, +dy}:
              +ca0 = pss_numer(b1, iy, dx, dy, a1, b1)
              +ca1 = pss_numer(b0, iy, dx, dy, a0, b0)
              set_y(c, FA.div(pss4_with(ca0, ca1, times(iy, sign), int(0), bs), denom))
    case False{}:
      c

def pss_general_lower(go: Bool, c: VP.Circle, +ca0: VT.Big, +ca1: VT.Big, +ca2: VT.Big, +orientation: VT.Big, +m: Meet, +bs: Pss4, +temp: FR.F64, +denom: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      match m:
        case Meet{_, _, +dx, +dy}:
          +ca3 = VT.big_mul_i32(times(orientation, sqr_sum(dx, dy)), FW.pick(is_neg(temp), 4294967295, 1))
          set_lx(c, FA.div(pss4_with(ca0, ca1, ca2, ca3, bs), denom))
    case False{}:
      c

def pss_general_x(go: Bool, c: VP.Circle, +ca0: VT.Big, +ca1: VT.Big, +ca2: VT.Big, +bs: Pss4, +denom: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      set_x(c, FA.div(pss4_with(ca0, ca1, ca2, int(0), bs), denom))
    case False{}:
      c

def pss_general_xl(go: Bool, c: VP.Circle, +t: Pss, +m: Meet, +sign: VT.Big, +bs: Pss4, +temp: FR.F64, +denom: FR.F64, +rcx: Bool, +rlx: Bool) -> VP.Circle:
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

def pss_sign(+second: Bool, +orientation: VT.Big) -> VT.Big:
  int((FW.pick(second, 1, 4294967295) * FW.pick(VT.big_is_neg(orientation), 1, 4294967295) : U32))

def pss_cross_terms(+t: Pss, +m: Meet) -> Pss4:
  match t:
    case Pss{+a0, +b0, +a1, +b1, _}:
      match m:
        case Meet{_, _, +dx, +dy}:
          +b3 = VT.big_mul_i32(times(minus(times(a0, dy), times(b0, dx)), minus(times(a1, dy), times(b1, dx))), 4294967294)
          Pss4{sqr_sum(a0, b0), sqr_sum(a1, b1), plus(times(a0, a1), times(b0, b1)), b3}

def pss_general(+t: Pss, +m: Meet, c: VP.Circle, +second: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match t:
    case Pss{+a0, +b0, +a1, +b1, +orientation}:
      match m:
        case Meet{_, _, +dx, +dy}:
          +sign = pss_sign(second, orientation)
          +bs = pss_cross_terms(t, m)
          +ca0 = plus(times(a1, VT.big_neg(dx)), times(b1, VT.big_neg(dy)))
          +ca1 = plus(times(a0, VT.big_neg(dx)), times(b0, VT.big_neg(dy)))
          +temp = pss4_with(ca0, ca1, sign, int(0), bs)
          +denom = FA.mul(temp, fpt(orientation))
          pss_general_xl(rcx || rlx, pss_general_y(rcy, c, t, m, sign, bs, denom), t, m, sign, bs, temp, denom, rcx, rlx)

def pss_meet_route(at_site: Bool, +t: Pss, +m: Meet, c: VP.Circle, +second: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match at_site:
    case True{}:
      match t:
        case Pss{_, _, _, _, +orientation}:
          match m:
            case Meet{+ix, +iy, _, _}:
              +denom = fpt(orientation)
              +cx = FA.div(fpt(ix), denom)
              VP.Circle{cx, FA.div(fpt(iy), denom), cx}
    case False{}:
      pss_general(t, m, c, second, rcx, rcy, rlx)

def meet_at_site(+m: Meet) -> Bool:
  match m:
    case Meet{_, _, +dx, +dy}:
      VT.big_is_zero(dx) && VT.big_is_zero(dy)

def pss_meet(+t: Pss, +en1: VP.Pt, +en2: VP.Pt, +s1: VP.Site) -> Meet:
  match t:
    case Pss{+a0, +b0, +a1, +b1, +orientation}:
      +c0 = minus(VT.big_mul_i32(b0, VP.pt_x(en1)), VT.big_mul_i32(a0, VP.pt_y(en1)))
      +c1 = minus(VT.big_mul_i32(a1, VP.pt_y(en2)), VT.big_mul_i32(b1, VP.pt_x(en2)))
      +ix = plus(times(a0, c1), times(a1, c0))
      +iy = plus(times(b0, c1), times(b1, c0))
      Meet{ix, iy, minus(ix, VT.big_mul_i32(orientation, VP.site_x0(s1))), minus(iy, VT.big_mul_i32(orientation, VP.site_y0(s1)))}

def pss_route(parallel: Bool, +t: Pss, +st1: VP.Pt, +en1: VP.Pt, +st2: VP.Pt, +en2: VP.Pt, +s1: VP.Site, c: VP.Circle, +second: Bool, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  match parallel:
    case True{}:
      pss_parallel(t, st1, st2, s1, c, second, rcx, rcy, rlx)
    case False{}:
      +m = pss_meet(t, en1, en2, s1)
      pss_meet_route(meet_at_site(m), t, m, c, second, rcx, rcy, rlx)

def pss_orientation(t: Pss) -> VT.Big:
  match t:
    case Pss{_, _, _, _, +o}:
      o

# mp_circle_formation_functor::pss(site1, site2, site3, point_index).
def pss(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +index: U32, c: VP.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  +st1 = VP.end(s2)
  +en1 = VP.start(s2)
  +st2 = VP.start(s3)
  +en2 = VP.end(s3)
  +t = pss_terms(st1, en1, st2, en2)
  pss_route(VT.big_is_zero(pss_orientation(t)), t, st1, en1, st2, en2, s1, c, U32.is_eq(index, 2), rcx, rcy, rlx)

type Line is Data:
  Line{a: VT.Big, b: VT.Big, c: VT.Big}

def sss_line(+s: VP.Site) -> Line:
  +st = VP.start(s)
  +en = VP.end(s)
  +c = VT.sub64(VT.mul64(VT.widen(VP.pt_x(st)), VT.widen(VP.pt_y(en))), VT.mul64(VT.widen(VP.pt_y(st)), VT.widen(VP.pt_x(en))))
  Line{dif(VP.pt_x(en), VP.pt_x(st)), dif(VP.pt_y(en), VP.pt_y(st)), wide(c)}

def line_a(l: Line) -> VT.Big:
  match l:
    case Line{+a, _, _}:
      a

def line_b(l: Line) -> VT.Big:
  match l:
    case Line{_, +b, _}:
      b

def line_c(l: Line) -> VT.Big:
  match l:
    case Line{_, _, +c}:
      c

def cross_ab(+j: Line, +k: Line) -> VT.Big:
  minus(times(line_a(j), line_b(k)), times(line_a(k), line_b(j)))

def cross_bc(+j: Line, +k: Line) -> VT.Big:
  minus(times(line_b(j), line_c(k)), times(line_b(k), line_c(j)))

def cross_ac(+j: Line, +k: Line) -> VT.Big:
  minus(times(line_a(j), line_c(k)), times(line_a(k), line_c(j)))

def line_len(+l: Line) -> VT.Big:
  sqr_sum(line_a(l), line_b(l))

def sss_y(go: Bool, c: VP.Circle, +l0: Line, +l1: Line, +l2: Line, +denom: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      +e = VR.eval3(cross_bc(l1, l2), cross_bc(l2, l0), cross_bc(l0, l1), line_len(l0), line_len(l1), line_len(l2))
      set_y(c, FA.div(VT.efpt_to_f64(e), denom))
    case False{}:
      c

def sss_x(go: Bool, c: VP.Circle, +a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +l0: Line, +l1: Line, +l2: Line, +denom: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      set_x(c, FA.div(VT.efpt_to_f64(VR.eval3(a0, a1, a2, line_len(l0), line_len(l1), line_len(l2))), denom))
    case False{}:
      c

def sss_lower(go: Bool, c: VP.Circle, +a0: VT.Big, +a1: VT.Big, +a2: VT.Big, +l0: Line, +l1: Line, +l2: Line, +denom: FR.F64) -> VP.Circle:
  match go:
    case True{}:
      +a3 = plus(plus(plus(int(0), times(a0, line_b(l0))), times(a1, line_b(l1))), times(a2, line_b(l2)))
      +e = VR.eval4(a0, a1, a2, a3, line_len(l0), line_len(l1), line_len(l2), int(1))
      set_lx(c, FA.div(VT.efpt_to_f64(e), denom))
    case False{}:
      c

def sss_xl(go: Bool, c: VP.Circle, +l0: Line, +l1: Line, +l2: Line, +denom: FR.F64, +rcx: Bool, +rlx: Bool) -> VP.Circle:
  match go:
    case True{}:
      +a0 = cross_ac(l1, l2)
      +a1 = cross_ac(l2, l0)
      +a2 = cross_ac(l0, l1)
      sss_lower(rlx, sss_x(rcx, c, a0, a1, a2, l0, l1, l2, denom), a0, a1, a2, l0, l1, l2, denom)
    case False{}:
      c

# mp_circle_formation_functor::sss.
def sss(+s1: VP.Site, +s2: VP.Site, +s3: VP.Site, c: VP.Circle, +rcx: Bool, +rcy: Bool, +rlx: Bool) -> VP.Circle:
  +l0 = sss_line(s1)
  +l1 = sss_line(s2)
  +l2 = sss_line(s3)
  +denom = VT.efpt_to_f64(VR.eval3(cross_ab(l1, l2), cross_ab(l2, l0), cross_ab(l0, l1), line_len(l0), line_len(l1), line_len(l2)))
  sss_xl(rcx || rlx, sss_y(rcy, c, l0, l1, l2, denom), l0, l1, l2, denom, rcx, rlx)
