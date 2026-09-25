import Base
import ../../f64/word.bend as FW
import ../../f64/repr.bend as FR
import ../../f64/arith.bend as FA
import ../../f64/cmp.bend as FC
import ./ctypes.bend as VT

# Boost.Polygon 1.52 voronoi_predicates.hpp, first half, and the site / circle event types of
# voronoi_structures.hpp: robust_cross_product, orientation_test, point_comparison_predicate,
# event_comparison_predicate, distance_predicate (pp, ps with fast_ps, ss), node_comparison_predicate and
# circle_existence_predicate. Coordinates are int32 in U32; orientations are RIGHT = -1, COLLINEAR = 0, LEFT = 1.

# site_event<int32>: the two end points (equal for a point site), sorted and initial index, and flags (the source
# category in the low five bits, 0x20 = inverse).
type Site is Data:
  Site{x0: U32, y0: U32, x1: U32, y1: U32, sorted: U32, initial: U32, flags: U32}

type Pt is Data:
  Pt{x: U32, y: U32}

# circle_event<double>: the centre and the x of its lowest point (lower_y is the centre's y).
type Circle is Data:
  Circle{x: FR.F64, y: FR.F64, lx: FR.F64}

def inverse_bit() -> U32:
  32

def right() -> U32:
  4294967295

def left() -> U32:
  1

def site_x0(s: Site) -> U32:
  match s:
    case Site{+x0, _, _, _, _, _, _}:
      x0

def site_y0(s: Site) -> U32:
  match s:
    case Site{_, +y0, _, _, _, _, _}:
      y0

def site_x1(s: Site) -> U32:
  match s:
    case Site{_, _, +x1, _, _, _, _}:
      x1

def site_y1(s: Site) -> U32:
  match s:
    case Site{_, _, _, +y1, _, _, _}:
      y1

def site_sorted(s: Site) -> U32:
  match s:
    case Site{_, _, _, _, +k, _, _}:
      k

def site_initial(s: Site) -> U32:
  match s:
    case Site{_, _, _, _, _, +i, _}:
      i

def site_flags(s: Site) -> U32:
  match s:
    case Site{_, _, _, _, _, _, +f}:
      f

def site_category(+s: Site) -> U32:
  (site_flags(s) .&. 31 : U32)

def is_inverse(+s: Site) -> Bool:
  Bool.not(U32.is_zero((site_flags(s) .&. inverse_bit() : U32)))

# site_event::inverse().
def inverse(s: Site) -> Site:
  match s:
    case Site{+x0, +y0, +x1, +y1, +k, +i, +f}:
      Site{x0, y0, x1, y1, k, i, (f .^. inverse_bit() : U32)}

def inverse_if(c: Bool, +s: Site) -> Site:
  Bool.pick(Site, c, inverse(s), s)

def is_segment(+s: Site) -> Bool:
  Bool.not(U32.is_eq(site_x0(s), site_x1(s))) || Bool.not(U32.is_eq(site_y0(s), site_y1(s)))

def is_point(+s: Site) -> Bool:
  Bool.not(is_segment(s))

def point0(+s: Site) -> Pt:
  Pt{site_x0(s), site_y0(s)}

def point1(+s: Site) -> Pt:
  Pt{site_x1(s), site_y1(s)}

# point0(true): the oriented start (point1 when inverse).
def start(+s: Site) -> Pt:
  Bool.pick(Pt, is_inverse(s), point1(s), point0(s))

# point1(true): the oriented end.
def end(+s: Site) -> Pt:
  Bool.pick(Pt, is_inverse(s), point0(s), point1(s))

def pt_x(p: Pt) -> U32:
  match p:
    case Pt{+x, _}:
      x

def pt_y(p: Pt) -> U32:
  match p:
    case Pt{_, +y}:
      y

def pt_eq(a: Pt, b: Pt) -> Bool:
  match a:
    case Pt{+ax, +ay}:
      match b:
        case Pt{+bx, +by}:
          U32.is_eq(ax, bx) && U32.is_eq(ay, by)

# site_event::operator== (both points).
def same_site(+a: Site, +b: Site) -> Bool:
  pt_eq(point0(a), point0(b)) && pt_eq(point1(a), point1(b))

# is_vertical(site): point0 and point1 share x (true for a point site).
def is_vertical(+s: Site) -> Bool:
  U32.is_eq(site_x0(s), site_x1(s))

def fpt(+x: U32) -> FR.F64:
  FR.from_i32(x)

def lt(+a: U32, +b: U32) -> Bool:
  VT.lt_i32(a, b)

def le(+a: U32, +b: U32) -> Bool:
  Bool.not(VT.lt_i32(b, a))

def neg_f64(c: Bool, +x: FR.F64) -> FR.F64:
  FR.pick(c, FR.neg(x), x)

def cross_mixed(both: Bool, +l: FW.W64, +r: FW.W64) -> FR.F64:
  match both:
    case True{}:
      +more = VT.lt_u64(r, l)
      neg_f64(more, VT.u64_to_f64(VT.pick64(more, VT.sub64(l, r), VT.sub64(r, l))))
    case False{}:
      FR.neg(VT.u64_to_f64(VT.add64(l, r)))

def cross_same(both: Bool, +l: FW.W64, +r: FW.W64) -> FR.F64:
  match both:
    case True{}:
      VT.u64_to_f64(VT.add64(l, r))
    case False{}:
      +less = VT.lt_u64(l, r)
      neg_f64(less, VT.u64_to_f64(VT.pick64(less, VT.sub64(r, l), VT.sub64(l, r))))

def cross_signed(first: Bool, +second: Bool, +l: FW.W64, +r: FW.W64) -> FR.F64:
  match first:
    case True{}:
      cross_mixed(second, l, r)
    case False{}:
      cross_same(second, l, r)

# robust_cross_product(a1, b1, a2, b2) = a1 * b2 - b1 * a2 on int64, as a double.
def cross(+a1: FW.W64, +b1: FW.W64, +a2: FW.W64, +b2: FW.W64) -> FR.F64:
  +l = VT.mul64(VT.abs64(a1), VT.abs64(b2))
  +r = VT.mul64(VT.abs64(b1), VT.abs64(a2))
  +first = Bool.xor(VT.is_neg64(a1), VT.is_neg64(b2))
  cross_signed(first, Bool.xor(VT.is_neg64(a2), VT.is_neg64(b1)), l, r)

# orientation_test::eval(value).
def orientation_of(+v: FR.F64) -> U32:
  FW.pick(FC.eq(v, FR.zero()), 0, FW.pick(FC.lt(v, FR.zero()), right(), left()))

# orientation_test::eval(dif_x1, dif_y1, dif_x2, dif_y2).
def orientation4(+dx1: FW.W64, +dy1: FW.W64, +dx2: FW.W64, +dy2: FW.W64) -> U32:
  orientation_of(cross(dx1, dy1, dx2, dy2))

# orientation_test::eval(point1, point2, point3).
def orientation(+p1: Pt, +p2: Pt, +p3: Pt) -> U32:
  +dx1 = VT.dif32(pt_x(p1), pt_x(p2))
  +dx2 = VT.dif32(pt_x(p2), pt_x(p3))
  +dy1 = VT.dif32(pt_y(p1), pt_y(p2))
  +dy2 = VT.dif32(pt_y(p2), pt_y(p3))
  orientation_of(cross(dx1, dy1, dx2, dy2))

# point_comparison_predicate.
def point_less(+a: Pt, +b: Pt) -> Bool:
  Bool.pick(Bool, U32.is_eq(pt_x(a), pt_x(b)), lt(pt_y(a), pt_y(b)), lt(pt_x(a), pt_x(b)))

def point_vs_site(+l: Site, +r: Site) -> Bool:
  Bool.pick(Bool, is_point(r), lt(site_y0(l), site_y0(r)), Bool.pick(Bool, is_vertical(r), le(site_y0(l), site_y0(r)), True{}))

def segment_vs_site(+l: Site, +r: Site) -> Bool:
  +by_y = Bool.pick(Bool, U32.is_eq(site_y0(l), site_y0(r)), U32.is_eq(orientation(point1(l), point0(l), point1(r)), left()), lt(site_y0(l), site_y0(r)))
  +rv = Bool.pick(Bool, is_vertical(l), lt(site_y0(l), site_y0(r)), False{})
  Bool.pick(Bool, is_vertical(r), rv, Bool.pick(Bool, is_vertical(l), True{}, by_y))

def same_x_less(point: Bool, +l: Site, +r: Site) -> Bool:
  match point:
    case True{}:
      point_vs_site(l, r)
    case False{}:
      segment_vs_site(l, r)

# event_comparison_predicate(site, site): the site event order of the sweep.
def site_less(+l: Site, +r: Site) -> Bool:
  Bool.pick(Bool, U32.is_eq(site_x0(l), site_x0(r)), same_x_less(is_point(l), l, r), lt(site_x0(l), site_x0(r)))

def circle_x(c: Circle) -> FR.F64:
  match c:
    case Circle{+x, _, _}:
      x

def circle_y(c: Circle) -> FR.F64:
  match c:
    case Circle{_, +y, _}:
      y

def circle_lx(c: Circle) -> FR.F64:
  match c:
    case Circle{_, _, +lx}:
      lx

def ulp_less(+x: Cmp, +y: Cmp) -> Bool:
  Bool.pick(Bool, Cmp.is_eq(x), Cmp.is_lt(y), Cmp.is_lt(x))

# event_comparison_predicate(site, circle), 64 ulps.
def site_before_circle(+s: Site, +c: Circle) -> Bool:
  ulp_less(FC.ulp_cmp(fpt(site_x0(s)), circle_lx(c), 64), FC.ulp_cmp(fpt(site_y0(s)), circle_y(c), 64))

# event_comparison_predicate(circle, circle), 128 ulps.
def circle_less(+a: Circle, +b: Circle) -> Bool:
  ulp_less(FC.ulp_cmp(circle_lx(a), circle_lx(b), 128), FC.ulp_cmp(circle_y(a), circle_y(b), 128))

def dist_point_arc(+s: Site, +p: Pt) -> FR.F64:
  +dx = FA.sub(fpt(site_x0(s)), fpt(pt_x(p)))
  +dy = FA.sub(fpt(site_y0(s)), fpt(pt_y(p)))
  FA.div(FA.add(FA.mul(dx, dx), FA.mul(dy, dy)), FA.mul(FR.two(), dx))

def segment_k(nonneg: Bool, +a1: FR.F64, +b1: FR.F64, +k: FR.F64) -> FR.F64:
  match nonneg:
    case True{}:
      FA.div(FR.one(), FA.add(b1, k))
    case False{}:
      FA.div(FA.sub(k, b1), FA.mul(a1, a1))

def dist_slanted_arc(+s0: Pt, +s1: Pt, +p: Pt) -> FR.F64:
  +a1 = FA.sub(fpt(pt_x(s1)), fpt(pt_x(s0)))
  +b1 = FA.sub(fpt(pt_y(s1)), fpt(pt_y(s0)))
  +k = FA.sqrt(FA.add(FA.mul(a1, a1), FA.mul(b1, b1)))
  +c = cross(VT.dif32(pt_x(s1), pt_x(s0)), VT.dif32(pt_y(s1), pt_y(s0)), VT.dif32(pt_x(p), pt_x(s0)), VT.dif32(pt_y(p), pt_y(s0)))
  FA.mul(segment_k(Bool.not(FC.lt(b1, FR.zero())), a1, b1, k), c)

def dist_segment_route(vertical: Bool, +s: Site, +p: Pt) -> FR.F64:
  match vertical:
    case True{}:
      FA.mul(FA.sub(fpt(site_x0(s)), fpt(pt_x(p))), FR.half())
    case False{}:
      dist_slanted_arc(start(s), end(s), p)

def dist_segment_arc(+s: Site, +p: Pt) -> FR.F64:
  dist_segment_route(is_vertical(s), s, p)

def undefined() -> U32:
  0

def more() -> U32:
  1

def less() -> U32:
  4294967295

def fast_ps_exprs(+reverse: Bool, +dif_x: FR.F64, +dif_y: FR.F64, +a: FR.F64, +b: FR.F64) -> U32:
  +left_expr = FA.mul(FA.mul(a, FA.add(dif_y, dif_x)), FA.sub(dif_y, dif_x))
  +right_expr = FA.mul(FA.mul(FA.mul(FR.two(), b), dif_x), dif_y)
  +c = FC.ulp_cmp(left_expr, right_expr, 4)
  FW.pick(Bool.not(Cmp.is_eq(c)) && Bool.xor(Cmp.is_gt(c), reverse), FW.pick(reverse, less(), more()), undefined())

def fast_ps_left(+inverse: Bool, +reverse: Bool) -> U32:
  FW.pick(inverse, FW.pick(reverse, undefined(), more()), FW.pick(reverse, less(), undefined()))

def fast_ps_slanted(+inverse: Bool, +reverse: Bool, +sp: Pt, +ss: Pt, +se: Pt, +np: Pt, +dif_x: FR.F64, +dif_y: FR.F64, +a: FR.F64, +b: FR.F64) -> U32:
  +o = orientation4(VT.dif32(pt_x(se), pt_x(ss)), VT.dif32(pt_y(se), pt_y(ss)), VT.dif32(pt_x(np), pt_x(sp)), VT.dif32(pt_y(np), pt_y(sp)))
  FW.pick(U32.is_eq(o, left()), fast_ps_left(inverse, reverse), fast_ps_exprs(reverse, dif_x, dif_y, a, b))

def fast_ps_vertical(+reverse: Bool, +sp: Pt, +np: Pt) -> U32:
  FW.pick(lt(pt_y(np), pt_y(sp)) && Bool.not(reverse), more(), FW.pick(lt(pt_y(sp), pt_y(np)) && reverse, less(), undefined()))

def fast_ps_right(vertical: Bool, +inverse: Bool, +reverse: Bool, +sp: Pt, +ss: Pt, +se: Pt, +np: Pt) -> U32:
  match vertical:
    case True{}:
      fast_ps_vertical(reverse, sp, np)
    case False{}:
      +dif_x = FA.sub(fpt(pt_x(np)), fpt(pt_x(sp)))
      +dif_y = FA.sub(fpt(pt_y(np)), fpt(pt_y(sp)))
      +a = FA.sub(fpt(pt_x(se)), fpt(pt_x(ss)))
      +b = FA.sub(fpt(pt_y(se)), fpt(pt_y(ss)))
      fast_ps_slanted(inverse, reverse, sp, ss, se, np, dif_x, dif_y, a, b)

def fast_ps_route(on_right: Bool, +left_site: Site, +right_site: Site, +new_site: Site, +reverse: Bool) -> U32:
  match on_right:
    case True{}:
      fast_ps_right(is_vertical(right_site), is_inverse(right_site), reverse, point0(left_site), start(right_site), end(right_site), point0(new_site))
    case False{}:
      FW.pick(is_inverse(right_site), more(), less())

# distance_predicate::fast_ps.
def fast_ps(+left_site: Site, +right_site: Site, +new_site: Site, +reverse: Bool) -> U32:
  +on_right = U32.is_eq(orientation(start(right_site), end(right_site), point0(new_site)), right())
  fast_ps_route(on_right, left_site, right_site, new_site, reverse)

def ps_decided(fast: U32, +left_site: Site, +right_site: Site, +new_site: Site, +reverse: Bool) -> Bool:
  match fast:
    case 0:
      Bool.xor(reverse, FC.lt(dist_point_arc(left_site, point0(new_site)), dist_segment_arc(right_site, point0(new_site))))
    case _:
      U32.is_eq(fast, less())

# distance_predicate::ps.
def ps(+left_site: Site, +right_site: Site, +new_site: Site, +reverse: Bool) -> Bool:
  ps_decided(fast_ps(left_site, right_site, new_site, reverse), left_site, right_site, new_site, reverse)

def pp_by_distance(+left_site: Site, +right_site: Site, +np: Pt) -> Bool:
  FC.lt(dist_point_arc(left_site, np), dist_point_arc(right_site, np))

def pp_same_x(+lp: Pt, +rp: Pt, +np: Pt) -> Bool:
  VT.lt_u64(VT.add64(VT.add64(VT.widen(pt_y(lp)), VT.widen(pt_y(rp))), FW.W64{2147483648, 0}), VT.add64(VT.add64(VT.widen(pt_y(np)), VT.widen(pt_y(np))), FW.W64{2147483648, 0}))

def pp_right_higher(stop: Bool, +left_site: Site, +right_site: Site, +np: Pt) -> Bool:
  match stop:
    case True{}:
      True{}
    case False{}:
      pp_by_distance(left_site, right_site, np)

def pp_left_higher(stop: Bool, +left_site: Site, +right_site: Site, +np: Pt) -> Bool:
  match stop:
    case True{}:
      False{}
    case False{}:
      pp_by_distance(left_site, right_site, np)

def pp_not_left(right: Bool, +left_site: Site, +right_site: Site, +lp: Pt, +rp: Pt, +np: Pt) -> Bool:
  match right:
    case True{}:
      pp_right_higher(le(pt_y(rp), pt_y(np)), left_site, right_site, np)
    case False{}:
      pp_same_x(lp, rp, np)

def pp_split(left: Bool, +left_site: Site, +right_site: Site, +lp: Pt, +rp: Pt, +np: Pt) -> Bool:
  match left:
    case True{}:
      pp_left_higher(le(pt_y(np), pt_y(lp)), left_site, right_site, np)
    case False{}:
      pp_not_left(lt(pt_x(lp), pt_x(rp)), left_site, right_site, lp, rp, np)

def pp_route(+left_site: Site, +right_site: Site, +lp: Pt, +rp: Pt, +np: Pt) -> Bool:
  pp_split(lt(pt_x(rp), pt_x(lp)), left_site, right_site, lp, rp, np)

# distance_predicate::pp.
def pp(+left_site: Site, +right_site: Site, +new_site: Site) -> Bool:
  pp_route(left_site, right_site, point0(left_site), point0(right_site), point0(new_site))

def ss_route(same: Bool, +left_site: Site, +right_site: Site, +new_site: Site) -> Bool:
  match same:
    case True{}:
      U32.is_eq(orientation(point0(left_site), point1(left_site), point0(new_site)), left())
    case False{}:
      FC.lt(dist_segment_arc(left_site, point0(new_site)), dist_segment_arc(right_site, point0(new_site)))

# distance_predicate::ss.
def ss(+left_site: Site, +right_site: Site, +new_site: Site) -> Bool:
  ss_route(same_site(left_site, right_site), left_site, right_site, new_site)

def distance_left_point(point_right: Bool, +left_site: Site, +right_site: Site, +new_site: Site) -> Bool:
  match point_right:
    case True{}:
      pp(left_site, right_site, new_site)
    case False{}:
      ps(left_site, right_site, new_site, False{})

def distance_left_segment(point_right: Bool, +left_site: Site, +right_site: Site, +new_site: Site) -> Bool:
  match point_right:
    case True{}:
      ps(right_site, left_site, new_site, True{})
    case False{}:
      ss(left_site, right_site, new_site)

def distance_route(point_left: Bool, +left_site: Site, +right_site: Site, +new_site: Site) -> Bool:
  match point_left:
    case True{}:
      distance_left_point(is_point(right_site), left_site, right_site, new_site)
    case False{}:
      distance_left_segment(is_point(right_site), left_site, right_site, new_site)

# distance_predicate(left_site, right_site, new_site): is the new site's point left of the breakpoint of the arcs?
def distance_less(+left_site: Site, +right_site: Site, +new_site: Site) -> Bool:
  distance_route(is_point(left_site), left_site, right_site, new_site)

def comparison_site(+l: Site, +r: Site) -> Site:
  Bool.pick(Site, lt(site_sorted(r), site_sorted(l)), l, r)

# get_comparison_y(node, is_new_node): (y, tag) with tag 0, 1 or -1.
type YTag is Data:
  YTag{y: U32, tag: U32}

def comparison_y(+l: Site, +r: Site, +is_new: Bool) -> YTag:
  +left_y = Bool.pick(U32, Bool.not(is_new) && is_segment(l) && is_vertical(l), site_y1(l), site_y0(l))
  Bool.pick(YTag, U32.is_eq(site_sorted(l), site_sorted(r)), YTag{site_y0(l), 0},
    Bool.pick(YTag, lt(site_sorted(r), site_sorted(l)), YTag{left_y, 1}, YTag{site_y0(r), 4294967295}))

def ytag_y(t: YTag) -> U32:
  match t:
    case YTag{+y, _}:
      y

def ytag_tag(t: YTag) -> U32:
  match t:
    case YTag{_, +g}:
      g

def pair_less(+a: YTag, +b: YTag) -> Bool:
  lt(ytag_y(a), ytag_y(b)) || (U32.is_eq(ytag_y(a), ytag_y(b)) && lt(ytag_tag(a), ytag_tag(b)))

def older_first(+y1: YTag, +y2: YTag, +site1: Site) -> Bool:
  Bool.pick(Bool, U32.is_eq(ytag_y(y1), ytag_y(y2)), is_point(site1) && lt(ytag_tag(y1), 0), lt(ytag_y(y1), ytag_y(y2)))

def newer_first(+y1: YTag, +y2: YTag, +site2: Site) -> Bool:
  Bool.pick(Bool, U32.is_eq(ytag_y(y1), ytag_y(y2)), Bool.not(is_point(site2)) || lt(0, ytag_tag(y2)), lt(ytag_y(y1), ytag_y(y2)))

def same_x_nodes(+l1: Site, +r1: Site, +l2: Site, +r2: Site, +site1: Site, +site2: Site) -> Bool:
  +k1 = site_sorted(site1)
  +k2 = site_sorted(site2)
  Bool.pick(Bool, U32.is_eq(k1, k2), pair_less(comparison_y(l1, r1, True{}), comparison_y(l2, r2, True{})),
    Bool.pick(Bool, lt(k1, k2), older_first(comparison_y(l1, r1, False{}), comparison_y(l2, r2, True{}), site1),
      newer_first(comparison_y(l1, r1, True{}), comparison_y(l2, r2, False{}), site2)))

def node_less_right(right: Bool, +l1: Site, +r1: Site, +l2: Site, +r2: Site, +site1: Site, +site2: Site) -> Bool:
  match right:
    case True{}:
      Bool.not(distance_less(l2, r2, site1))
    case False{}:
      same_x_nodes(l1, r1, l2, r2, site1, site2)

def node_less_route(left: Bool, +l1: Site, +r1: Site, +l2: Site, +r2: Site, +site1: Site, +site2: Site) -> Bool:
  match left:
    case True{}:
      distance_less(l1, r1, site2)
    case False{}:
      node_less_right(lt(site_x0(site2), site_x0(site1)), l1, r1, l2, r2, site1, site2)

def node_less_sites(+l1: Site, +r1: Site, +l2: Site, +r2: Site, +site1: Site, +site2: Site) -> Bool:
  node_less_route(lt(site_x0(site1), site_x0(site2)), l1, r1, l2, r2, site1, site2)

# node_comparison_predicate(node1, node2) on the beach line keys (left_site, right_site).
def node_less(+l1: Site, +r1: Site, +l2: Site, +r2: Site) -> Bool:
  node_less_sites(l1, r1, l2, r2, comparison_site(l1, r1), comparison_site(l2, r2))

# circle_existence_predicate::ppp.
def exists_ppp(+s1: Site, +s2: Site, +s3: Site) -> Bool:
  U32.is_eq(orientation(point0(s1), point0(s2), point0(s3)), right())

def pps_not_middle(+index: U32, +s1: Site, +s2: Site, +s3: Site) -> Bool:
  +o1 = orientation(point0(s1), point0(s2), start(s3))
  +o2 = orientation(point0(s1), point0(s2), end(s3))
  +first = U32.is_eq(index, 1) && le(site_x0(s2), site_x0(s1))
  +third = U32.is_eq(index, 3) && le(site_x0(s1), site_x0(s2))
  Bool.pick(Bool, first, U32.is_eq(o1, right()), Bool.pick(Bool, third, U32.is_eq(o2, right()), U32.is_eq(o1, right()) || U32.is_eq(o2, right())))

# circle_existence_predicate::pps(site1, site2, site3, segment_index).
def exists_pps(+s1: Site, +s2: Site, +s3: Site, +index: U32) -> Bool:
  +middle = Bool.not(pt_eq(start(s3), point0(s1)) && pt_eq(end(s3), point0(s2)))
  Bool.pick(Bool, U32.is_eq(index, 2), middle, pps_not_middle(index, s1, s2, s3))

def pss_middle(+s1: Site, +s2: Site, +s3: Site) -> Bool:
  +i2 = is_inverse(s2)
  +i3 = is_inverse(s3)
  +blocked = Bool.not(i2) && i3
  +turn = Bool.not(U32.is_eq(orientation(start(s2), point0(s1), end(s3)), right()))
  Bool.not(blocked) && Bool.not(Bool.and(Bool.not(Bool.xor(i2, i3)), turn))

# circle_existence_predicate::pss(site1, site2, site3, point_index).
def exists_pss(+s1: Site, +s2: Site, +s3: Site, +index: U32) -> Bool:
  Bool.not(same_site(s2, s3)) && Bool.pick(Bool, U32.is_eq(index, 2), pss_middle(s1, s2, s3), True{})

# circle_existence_predicate::sss.
def exists_sss(+s1: Site, +s2: Site, +s3: Site) -> Bool:
  Bool.not(same_site(s1, s2)) && Bool.not(same_site(s2, s3))
