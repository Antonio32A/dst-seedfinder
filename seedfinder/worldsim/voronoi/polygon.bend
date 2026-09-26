import Base
import ../../f64/repr.bend as F64Repr
import ../../f64/arith.bend as F64Arith
import ../../f64/cmp.bend as F64Cmp
import ../../f32/ops.bend as F32Ops
import ./predicates.bend as VoronoiPredicates
import ./diagram.bend as VoronoiDiagram
import ./builder.bend as VoronoiBuilder

# Klei's BuildVoronoi (boostmap.cpp, the Boost voronoi_visualizer loop): the voronoi of the float sites (truncated to
# int32) and the 4 frame segments of SetSize, each site's cell polygon (clip_infinite_edge, discretize of curved
# edges with the NaN/inf guards, "Infinite edge!" skips of vertices beyond 10000), its float centroid, its
# neighbours (nil = the boundary sentinel) and the node states (5 new, 1 blank/random, 4 on the boundary, then the
# 2 / 3 pass in site order).

# A site: float x, y bits, the node's type and the node's centroid before this build (kept by cell-less sites).
type SiteIn is Data:
  SiteIn{x: U32, y: U32, kind: U32, cx: U32, cy: U32}

type D2 is Data:
  D2{x: F64Repr.F64, y: F64Repr.F64}

type P32 is Data:
  P32{x: U32, y: U32}

# One site's result: polygon (float bits), centroid bits, neighbour sites (nil = boundary) and state.
type Poly is Data:
  Poly{points: List<&2, P32>, cx: U32, cy: U32, nbs: List<&2, U32>, state: U32}

type Frame is Data:
  Frame{w: F64Repr.F64, h: F64Repr.F64}

def nil() -> U32:
  VoronoiDiagram.nil()

def seg_start(+f: Frame, +k: U32) -> D2:
  match f:
    case Frame{+w, +h}:
      +z = F64Repr.zero()
      Bool.pick(D2, U32.is_zero(k), D2{z, z}, Bool.pick(D2, U32.is_eq(k, 1), D2{w, z}, Bool.pick(D2, U32.is_eq(k, 2), D2{w, h}, D2{z, h})))

def seg_end(+f: Frame, +k: U32) -> D2:
  seg_start(f, ((k + 1 : U32) .&. 3 : U32))

# BoostMap::SetSize(w, h): the frame segments (0,0)-(w,0), (w,0)-(w,h), (w,h)-(0,h), (0,h)-(0,0), as int32.
def frame_segments(+w: U32, +h: U32) -> List<&2, VoronoiBuilder.Segment>:
  [VoronoiBuilder.Segment{0, 0, w, 0}, VoronoiBuilder.Segment{w, 0, w, h}, VoronoiBuilder.Segment{w, h, 0, h}, VoronoiBuilder.Segment{0, h, 0, 0}]

def site_point(+s: SiteIn) -> D2:
  match s:
    case SiteIn{+x, +y, _, _, _}:
      D2{F64Repr.from_f32_bits(x), F64Repr.from_f32_bits(y)}

def d_x(p: D2) -> F64Repr.F64:
  match p:
    case D2{+x, _}:
      x

def d_y(p: D2) -> F64Repr.F64:
  match p:
    case D2{_, +y}:
      y

# (int)(double)x of a float site: cvttsd2si.
def site_pt(+s: SiteIn) -> VoronoiPredicates.Pt:
  VoronoiPredicates.Pt{F64Repr.to_i32(d_x(site_point(s))), F64Repr.to_i32(d_y(site_point(s)))}

def site_pts(l: List<&2, SiteIn>) -> List<&2, VoronoiPredicates.Pt>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      site_pt(s) <> site_pts(rest)

type Ctx is Type:
  Ctx{sites: Array<SiteIn>, n: U32, frame: Frame}

def ctx_site_got(got: Array<SiteIn> & SiteIn, +n: U32, +f: Frame) -> Ctx & SiteIn:
  (sites, +s) = got
  (Ctx{sites, n, f}, s)

def ctx_site(c: Ctx, +i: U32) -> Ctx & SiteIn:
  match c:
    case Ctx{sites, +n, +f}:
      ctx_site_got(Array.get(SiteIn, sites, i), n, f)

def point_of_site(got: Ctx & SiteIn) -> Ctx & D2:
  (c, +s) = got
  (c, site_point(s))

def retrieve_route(single: Bool, c: Ctx, +src: U32, +cat: U32, +n: U32, +f: Frame) -> Ctx & D2:
  match single:
    case True{}:
      point_of_site(ctx_site(c, src))
    case False{}:
      (c, Bool.pick(D2, U32.is_eq(cat, 1), seg_start(f, (src - n : U32)), seg_end(f, (src - n : U32))))

# BoostMap::RetrievePoint(cell): the double site for a point cell, the segment end for an end point cell.
def retrieve_point(c: Ctx, +cell: VoronoiDiagram.Cell) -> Ctx & D2:
  match c:
    case Ctx{sites, +n, +f}:
      match cell:
        case VoronoiDiagram.Cell{+src, +cat, _}:
          retrieve_route(U32.is_zero(cat), Ctx{sites, n, f}, src, cat, n, f)

def contains_point(+cell: VoronoiDiagram.Cell) -> Bool:
  match cell:
    case VoronoiDiagram.Cell{_, +cat, _}:
      (cat < 8 : U32)

def cell_seg(+cell: VoronoiDiagram.Cell, +n: U32) -> U32:
  match cell:
    case VoronoiDiagram.Cell{+src, _, _}:
      (src - n : U32)

def maxd(+a: F64Repr.F64, +b: F64Repr.F64) -> F64Repr.F64:
  F64Repr.pick(F64Cmp.lt(a, b), b, a)

type Ray is Data:
  Ray{o: D2, d: D2}

def clipped(+r: Ray, +has0: Bool, +has1: Bool, +v0: D2, +v1: D2, +side: F64Repr.F64) -> List<&2, D2>:
  match r:
    case Ray{+o, +d}:
      +koef = F64Arith.div(side, maxd(F64Repr.abs(d_x(d)), F64Repr.abs(d_y(d))))
      +back = {D2{F64Arith.sub(d_x(o), F64Arith.mul(d_x(d), koef)), F64Arith.sub(d_y(o), F64Arith.mul(d_y(d), koef))} : D2}
      +ahead = {D2{F64Arith.add(d_x(o), F64Arith.mul(d_x(d), koef)), F64Arith.add(d_y(o), F64Arith.mul(d_y(d), koef))} : D2}
      [Bool.pick(D2, has0, v0, back), Bool.pick(D2, has1, v1, ahead)]

def two_point_ray(+p1: D2, +p2: D2) -> Ray:
  Ray{D2{F64Arith.mul(F64Arith.add(d_x(p1), d_x(p2)), F64Repr.half()), F64Arith.mul(F64Arith.add(d_y(p1), d_y(p2)), F64Repr.half())},
    D2{F64Arith.sub(d_y(p1), d_y(p2)), F64Arith.sub(d_x(p2), d_x(p1))}}

def segment_ray(+origin: D2, +s0: D2, +s1: D2, +first_point: Bool) -> Ray:
  +dx = F64Arith.sub(d_x(s1), d_x(s0))
  +dy = F64Arith.sub(d_y(s1), d_y(s0))
  +low = F64Cmp.eq(d_x(s0), d_x(origin)) && F64Cmp.eq(d_y(s0), d_y(origin))
  Ray{origin, Bool.pick(D2, Bool.xor(low, first_point), D2{dy, F64Repr.neg(dx)}, D2{F64Repr.neg(dy), dx})}

def ray_second(got: Ctx & D2, +p1: D2, +both: Bool) -> Ctx & Ray:
  (c, +p2) = got
  (c, two_point_ray(p1, p2))

def ray_points(got: Ctx & D2, +second: VoronoiDiagram.Cell, +first_segment: Bool) -> Ctx & Ray:
  (c, +p1) = got
  ray_second(retrieve_point(c, second), p1, first_segment)

def ray_segment(got: Ctx & D2, +seg: U32, +first_point: Bool) -> Ctx & Ray:
  (c, +origin) = got
  match c:
    case Ctx{sites, +n, +f}:
      (Ctx{sites, n, f}, segment_ray(origin, seg_start(f, seg), seg_end(f, seg), first_point))

def clip_ray(both_points: Bool, c: Ctx, +cell1: VoronoiDiagram.Cell, +cell2: VoronoiDiagram.Cell, +n: U32) -> Ctx & Ray:
  match both_points:
    case True{}:
      ray_points(retrieve_point(c, cell1), cell2, False{})
    case False{}:
      +seg_first = Bool.not(contains_point(cell1))
      ray_segment(retrieve_point(c, Bool.pick(VoronoiDiagram.Cell, seg_first, cell2, cell1)), Bool.pick(U32, seg_first, cell_seg(cell1, n), cell_seg(cell2, n)), contains_point(cell1))

def ctx_n(c: Ctx) -> Ctx & U32:
  match c:
    case Ctx{sites, +n, +f}:
      (Ctx{sites, n, f}, n)

def ctx_side(c: Ctx) -> Ctx & F64Repr.F64:
  match c:
    case Ctx{sites, +n, +f}:
      match f:
        case Frame{+w, +h}:
          (Ctx{sites, n, Frame{w, h}}, w)

def clip_sided(got: Ctx & F64Repr.F64, +r: Ray, +h: VoronoiDiagram.Half) -> Ctx & List<&2, D2>:
  (c, +side) = got
  match h:
    case VoronoiDiagram.Half{_, +has0, +x0, +y0, +has1, +x1, +y1, _}:
      (c, clipped(r, has0, has1, D2{x0, y0}, D2{x1, y1}, side))

def clip_done(got: Ctx & Ray, +h: VoronoiDiagram.Half) -> Ctx & List<&2, D2>:
  (c, +r) = got
  clip_sided(ctx_side(c), r, h)

def clip_counted(got: Ctx & U32, +cell1: VoronoiDiagram.Cell, +cell2: VoronoiDiagram.Cell, +h: VoronoiDiagram.Half) -> Ctx & List<&2, D2>:
  (c, +n) = got
  clip_done(clip_ray(contains_point(cell1) && contains_point(cell2), c, cell1, cell2, n), h)

# BoostMap::ClipInfiniteEdge: the two end points of an edge with a missing vertex.
def clip_infinite(c: Ctx, +cell1: VoronoiDiagram.Cell, +cell2: VoronoiDiagram.Cell, +h: VoronoiDiagram.Half) -> Ctx & List<&2, D2>:
  clip_counted(ctx_n(c), cell1, cell2, h)

def parabola_y(+x: F64Repr.F64, +a: F64Repr.F64, +b: F64Repr.F64) -> F64Repr.F64:
  +t = F64Arith.sub(x, a)
  F64Arith.div(F64Arith.add(F64Arith.mul(t, t), F64Arith.mul(b, b)), F64Arith.add(b, b))

def projection(+p: D2, +s0: D2, +s1: D2) -> F64Repr.F64:
  +svx = F64Arith.sub(d_x(s1), d_x(s0))
  +svy = F64Arith.sub(d_y(s1), d_y(s0))
  +pvx = F64Arith.sub(d_x(p), d_x(s0))
  +pvy = F64Arith.sub(d_y(p), d_y(s0))
  F64Arith.div(F64Arith.add(F64Arith.mul(svx, pvx), F64Arith.mul(svy, pvy)), F64Arith.add(F64Arith.mul(svx, svx), F64Arith.mul(svy, svy)))

type Par is Data:
  Par{rot_x: F64Repr.F64, rot_y: F64Repr.F64, svx: F64Repr.F64, svy: F64Repr.F64, sqr: F64Repr.F64, x0: F64Repr.F64, y0: F64Repr.F64, limit: F64Repr.F64}

type Disc is Data:
  Disc{stack: List<&2, F64Repr.F64>, cur_x: F64Repr.F64, cur_y: F64Repr.F64, out: List<&2, D2>}

def finite(+x: F64Repr.F64) -> Bool:
  F64Cmp.le(F64Repr.abs(x), F64Repr.max_finite())

def disc_accept(+p: Par, +rest: List<&2, F64Repr.F64>, +nx: F64Repr.F64, +ny: F64Repr.F64, +out: List<&2, D2>) -> Disc:
  match p:
    case Par{_, _, +svx, +svy, +sqr, +x0, +y0, _}:
      +ix = F64Arith.add(F64Arith.div(F64Arith.sub(F64Arith.mul(svx, nx), F64Arith.mul(svy, ny)), sqr), x0)
      +iy = F64Arith.add(F64Arith.div(F64Arith.add(F64Arith.mul(svx, ny), F64Arith.mul(svy, nx)), sqr), y0)
      Disc{rest, nx, ny, D2{ix, iy} <> out}

def disc_measure(+p: Par, +d: Disc, +nx: F64Repr.F64, +ny: F64Repr.F64, +mx: F64Repr.F64, +my: F64Repr.F64, +rest: List<&2, F64Repr.F64>) -> Disc:
  match p:
    case Par{_, _, _, _, _, _, _, +limit}:
      match d:
        case Disc{+stack, +cx, +cy, +out}:
          +dy = F64Arith.sub(ny, cy)
          +dx = F64Arith.sub(nx, cx)
          +raw = F64Arith.sub(F64Arith.mul(dy, F64Arith.sub(mx, cx)), F64Arith.mul(dx, F64Arith.sub(my, cy)))
          +dist = F64Arith.div(F64Arith.mul(raw, raw), F64Arith.add(F64Arith.mul(dy, dy), F64Arith.mul(dx, dx)))
          Bool.pick(Disc, F64Cmp.le(dist, limit), disc_accept(p, rest, nx, ny, out), Disc{mx <> stack, cx, cy, out})

def disc_step(+p: Par, +d: Disc, +nx: F64Repr.F64, +rest: List<&2, F64Repr.F64>) -> Disc:
  match p:
    case Par{+rx, +ry, _, _, _, _, _, _}:
      match d:
        case Disc{+stack, +cx, +cy, +out}:
          +ny = parabola_y(nx, rx, ry)
          +mx = F64Arith.add(F64Arith.mul(F64Arith.div(F64Arith.sub(ny, cy), F64Arith.sub(nx, cx)), ry), rx)
          +my = parabola_y(mx, rx, ry)
          +popped = {Disc{rest, cx, cy, out} : Disc}
          Bool.pick(Disc, finite(mx), Bool.pick(Disc, finite(my), disc_measure(p, d, nx, ny, mx, my, rest), popped), popped)

def disc_loop(n: Nat, +p: Par, +d: Disc) -> Disc:
  match n:
    case 0n:
      d
    case 1n+k:
      match d:
        case Disc{+stack, +cx, +cy, +out}:
          match stack:
            case Nil{}:
              d
            case Con{+nx, +rest}:
              disc_loop(k, p, disc_step(p, d, nx, rest))

def replace_last(l: List<&2, D2>, +v: D2) -> List<&2, D2>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+h, +t}:
      Bool.pick(List<&2, D2>, List.is_empty(&2, D2, t), [v], h <> replace_last(t, v))

def disc_result(+d: Disc, +v1: D2) -> List<&2, D2>:
  match d:
    case Disc{_, _, _, +out}:
      replace_last(List.reverse(&2, D2, out), v1)

# voronoi_visual_utils::discretize (Klei's copy): the parabola arc between the edge's vertices, sampled until each
# chord is within max_dist.
def discretize(+point: D2, +s0: D2, +s1: D2, +max_dist: F64Repr.F64, +v0: D2, +v1: D2) -> List<&2, D2>:
  +svx = F64Arith.sub(d_x(s1), d_x(s0))
  +svy = F64Arith.sub(d_y(s1), d_y(s0))
  +sqr = F64Arith.add(F64Arith.mul(svx, svx), F64Arith.mul(svy, svy))
  +start = F64Arith.mul(sqr, projection(v0, s0, s1))
  +stop = F64Arith.mul(sqr, projection(v1, s0, s1))
  +pvx = F64Arith.sub(d_x(point), d_x(s0))
  +pvy = F64Arith.sub(d_y(point), d_y(s0))
  +rx = F64Arith.add(F64Arith.mul(svx, pvx), F64Arith.mul(svy, pvy))
  +ry = F64Arith.sub(F64Arith.mul(svx, pvy), F64Arith.mul(svy, pvx))
  +p = {Par{rx, ry, svx, svy, sqr, d_x(s0), d_y(s0), F64Arith.mul(F64Arith.mul(max_dist, max_dist), sqr)} : Par}
  disc_result(disc_loop(65536n, p, Disc{[stop], start, parabola_y(start, rx, ry), [v0]}), v1)

def sample_with(got: Ctx & D2, +segcell: VoronoiDiagram.Cell, +v0: D2, +v1: D2) -> Ctx & List<&2, D2>:
  (c, +point) = got
  match c:
    case Ctx{sites, +n, +f}:
      match f:
        case Frame{+w, +h}:
          +k = cell_seg(segcell, n)
          +fr = {Frame{w, h} : Frame}
          (Ctx{sites, n, fr}, discretize(point, seg_start(fr, k), seg_end(fr, k), F64Arith.mul(w, F64Repr.F64{1062232653, 3539053052}), v0, v1))

def sample_curved(c: Ctx, +cell1: VoronoiDiagram.Cell, +cell2: VoronoiDiagram.Cell, +v0: D2, +v1: D2) -> Ctx & List<&2, D2>:
  +point_first = contains_point(cell1)
  sample_with(retrieve_point(c, Bool.pick(VoronoiDiagram.Cell, point_first, cell1, cell2)), Bool.pick(VoronoiDiagram.Cell, point_first, cell2, cell1), v0, v1)

def within(+x: F64Repr.F64) -> Bool:
  finite(x) && F64Cmp.le(F64Repr.abs(x), F64Repr.F64{1086556160, 0})

def curved_if(curved: Bool, c: Ctx, +cell1: VoronoiDiagram.Cell, +cell2: VoronoiDiagram.Cell, +v0: D2, +v1: D2) -> Ctx & List<&2, D2>:
  match curved:
    case True{}:
      sample_curved(c, cell1, cell2, v0, v1)
    case False{}:
      (c, [v0, v1])

def finite_edge(usable: Bool, c: Ctx, +cell1: VoronoiDiagram.Cell, +cell2: VoronoiDiagram.Cell, +h: VoronoiDiagram.Half) -> Ctx & List<&2, D2>:
  match usable:
    case True{}:
      match h:
        case VoronoiDiagram.Half{_, _, +x0, +y0, _, +x1, +y1, +f}:
          curved_if(U32.is_zero((f .&. VoronoiDiagram.linear_bit() : U32)), c, cell1, cell2, D2{x0, y0}, D2{x1, y1})
    case False{}:
      (c, Nil{})

def edge_usable(+h: VoronoiDiagram.Half) -> Bool:
  match h:
    case VoronoiDiagram.Half{_, _, +x0, +y0, _, +x1, +y1, _}:
      within(x0) && within(y0) && within(x1) && within(y1)

def half_complete(+h: VoronoiDiagram.Half) -> Bool:
  match h:
    case VoronoiDiagram.Half{_, +has0, _, _, +has1, _, _, _}:
      has0 && has1

def edge_points(complete: Bool, c: Ctx, +cell1: VoronoiDiagram.Cell, +cell2: VoronoiDiagram.Cell, +h: VoronoiDiagram.Half) -> Ctx & List<&2, D2>:
  match complete:
    case True{}:
      finite_edge(edge_usable(h), c, cell1, cell2, h)
    case False{}:
      clip_infinite(c, cell1, cell2, h)

def to_p32(l: List<&2, D2>) -> List<&2, P32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      P32{F64Repr.to_f32_bits(d_x(p)), F64Repr.to_f32_bits(d_y(p))} <> to_p32(rest)

def half_twin(+h: VoronoiDiagram.Half) -> U32:
  match h:
    case VoronoiDiagram.Half{+t, _, _, _, _, _, _, _}:
      t

# One cell's walk: the diagram, the context, the polygon so far (reversed chunks) and the neighbours (reversed).
type Walk is Type:
  Walk{d: VoronoiDiagram.Diagram, c: Ctx, points: List<&2, List<&2, P32>>, nbs: List<&2, U32>, border: Bool}

def walk_nb(got: Ctx & U32, d: VoronoiDiagram.Diagram, +cell2: VoronoiDiagram.Cell, +pts: List<&2, List<&2, P32>>, +nbs: List<&2, U32>, +border: Bool) -> Walk:
  (c, +n) = got
  match cell2:
    case VoronoiDiagram.Cell{+src, _, _}:
      +inside = (src < n : U32)
      Walk{d, c, pts, Bool.pick(U32, inside, src, nil()) <> nbs, border || Bool.not(inside)}

def walk_points(got: Ctx & List<&2, D2>, d: VoronoiDiagram.Diagram, +cell2: VoronoiDiagram.Cell, +pts: List<&2, List<&2, P32>>, +nbs: List<&2, U32>, +border: Bool) -> Walk:
  (c, +ps) = got
  walk_nb(ctx_n(c), d, cell2, to_p32(ps) <> pts, nbs, border)

def walk_edge(got: VoronoiDiagram.Diagram & VoronoiDiagram.Cell, c: Ctx, +cell1: VoronoiDiagram.Cell, +h: VoronoiDiagram.Half, +pts: List<&2, List<&2, P32>>, +nbs: List<&2, U32>, +border: Bool) -> Walk:
  (d, +cell2) = got
  walk_points(edge_points(half_complete(h), c, cell1, cell2, h), d, cell2, pts, nbs, border)

def walk_halves(hs: List<&2, VoronoiDiagram.Half>, w: Walk, +cell1: VoronoiDiagram.Cell) -> Walk:
  match hs:
    case Nil{}:
      w
    case Con{+h, rest}:
      match w:
        case Walk{d, c, +pts, +nbs, +border}:
          walk_halves(rest, walk_edge(VoronoiDiagram.cell_info(d, half_twin(h)), c, cell1, h, pts, nbs, border), cell1)

type Acc is Data:
  Acc{a: F32, x: F32, y: F32}

def fx(+p: P32) -> F32:
  match p:
    case P32{+x, _}:
      F32Ops.from_bits(x)

def fy(+p: P32) -> F32:
  match p:
    case P32{_, +y}:
      F32Ops.from_bits(y)

def cross_term(+p: P32, +q: P32, +acc: Acc) -> Acc:
  match acc:
    case Acc{+a, +cx, +cy}:
      +c = F32Ops.sub(F32Ops.mul(fx(p), fy(q)), F32Ops.mul(fx(q), fy(p)))
      Acc{F32Ops.add(a, c), F32Ops.add(cx, F32Ops.mul(F32Ops.add(fx(p), fx(q)), c)), F32Ops.add(cy, F32Ops.mul(F32Ops.add(fy(p), fy(q)), c))}

def closing_term(+last: P32, +first: P32, +acc: Acc) -> Acc:
  match acc:
    case Acc{+a, +cx, +cy}:
      +c = F32Ops.sub(F32Ops.mul(fx(last), fy(first)), F32Ops.mul(fx(first), fy(last)))
      Acc{F32Ops.add(a, c), F32Ops.add(cx, F32Ops.mul(F32Ops.add(fx(first), fx(last)), c)), F32Ops.add(cy, F32Ops.mul(F32Ops.add(fy(first), fy(last)), c))}

def centroid_terms(l: List<&2, P32>, +prev: P32, +first: P32, +acc: Acc) -> Acc:
  match l:
    case Nil{}:
      closing_term(prev, first, acc)
    case Con{+q, rest}:
      centroid_terms(rest, q, first, cross_term(prev, q, acc))

def t_a(t: Acc) -> F32:
  match t:
    case Acc{+a, _, _}:
      a

def t_x(t: Acc) -> F32:
  match t:
    case Acc{_, +x, _}:
      x

def t_y(t: Acc) -> F32:
  match t:
    case Acc{_, _, +y}:
      y

def centroid_of(+acc: Acc) -> P32:
  match acc:
    case Acc{+a, +cx, +cy}:
      +a6 = F32Ops.mul(F32Ops.mul(a, 0.5), 6.0)
      P32{F32Ops.bits(F32Ops.div(cx, a6)), F32Ops.bits(F32Ops.div(cy, a6))}

# PolygonCentroid (float shoelace, closing edge last).
def centroid(+poly: List<&2, P32>) -> P32:
  match poly:
    case Nil{}:
      P32{0, 0}
    case Con{+first, rest}:
      centroid_of(centroid_terms(rest, first, first, Acc{0.0, 0.0, 0.0}))

def site_kind(+s: SiteIn) -> U32:
  match s:
    case SiteIn{_, _, +k, _, _}:
      k

def site_p32(+s: SiteIn) -> P32:
  match s:
    case SiteIn{+x, +y, _, _, _}:
      P32{x, y}

def start_state(+kind: U32, +border: Bool) -> U32:
  Bool.pick(U32, U32.is_eq((kind .&. 4294967293 : U32), 1), 1, Bool.pick(U32, border, 4, 5))

def poly_with(+c: P32, +pts: List<&2, P32>, +s: SiteIn, +nbs: List<&2, U32>, +border: Bool) -> Poly:
  match c:
    case P32{+cx, +cy}:
      Poly{pts, cx, cy, nbs, start_state(site_kind(s), border)}

def cell_poly(+pts: List<&2, P32>, +s: SiteIn, +nbs: List<&2, U32>, +border: Bool) -> Poly:
  poly_with(Bool.pick(P32, List.is_empty(&2, P32, pts), site_p32(s), centroid(pts)), pts, s, nbs, border)

def walked_site(got: Ctx & SiteIn, d: VoronoiDiagram.Diagram, +pts: List<&2, P32>, +nbs: List<&2, U32>, +border: Bool) -> VoronoiDiagram.Diagram & Ctx & Poly:
  (c, +s) = got
  (d, (c, cell_poly(pts, s, nbs, border)))

def walked(w: Walk, +src: U32) -> VoronoiDiagram.Diagram & Ctx & Poly:
  match w:
    case Walk{d, c, +pts, +nbs, +border}:
      walked_site(ctx_site(c, src), d, List.concat(&2, P32, List.reverse(&2, List<&2, P32>, pts)), List.reverse(&2, U32, nbs), border)

type Polys is Type:
  Polys{d: VoronoiDiagram.Diagram, c: Ctx, polys: Array<Poly>}

def store_rest(got: Ctx & Poly, d: VoronoiDiagram.Diagram, polys: Array<Poly>, +src: U32) -> Polys:
  (c, +p) = got
  Polys{d, c, Array.set(Poly, polys, src, p)}

def store_poly(got: VoronoiDiagram.Diagram & Ctx & Poly, polys: Array<Poly>, +src: U32) -> Polys:
  (d, rest) = got
  store_rest(rest, d, polys, src)

def cell_ringed(r: VoronoiDiagram.Ring, c: Ctx, polys: Array<Poly>, +cell: VoronoiDiagram.Cell) -> Polys:
  match r:
    case VoronoiDiagram.Ring{d, +hs}:
      match cell:
        case VoronoiDiagram.Cell{+src, +cat, +inc}:
          +cell1 = {VoronoiDiagram.Cell{src, cat, inc} : VoronoiDiagram.Cell}
          store_poly(walked(walk_halves(hs, Walk{d, c, Nil{}, Nil{}, False{}}, cell1), src), polys, src)

def site_cell(inside: Bool, got: VoronoiDiagram.Diagram & VoronoiDiagram.Cell, c: Ctx, polys: Array<Poly>, +k: U32) -> Polys:
  match inside:
    case True{}:
      (d, +cell) = got
      cell_ringed(VoronoiDiagram.cell_ring(d, k), c, polys, cell)
    case False{}:
      (d, _) = got
      Polys{d, c, polys}

def cell_src_of(got: VoronoiDiagram.Diagram & VoronoiDiagram.Cell) -> VoronoiDiagram.Diagram & VoronoiDiagram.Cell & U32:
  (d, +cell) = got
  match cell:
    case VoronoiDiagram.Cell{+src, _, _}:
      (d, (cell, src))

def one_cell_counted(got: Ctx & U32, d: VoronoiDiagram.Diagram, +cell: VoronoiDiagram.Cell, +src: U32, polys: Array<Poly>, +k: U32) -> Polys:
  (c, +n) = got
  site_cell((src < n : U32), (d, cell), c, polys, k)

def one_cell_rest(got: VoronoiDiagram.Cell & U32, d: VoronoiDiagram.Diagram, c: Ctx, polys: Array<Poly>, +k: U32) -> Polys:
  (+cell, +src) = got
  one_cell_counted(ctx_n(c), d, cell, src, polys, k)

def one_cell(got: VoronoiDiagram.Diagram & VoronoiDiagram.Cell & U32, c: Ctx, polys: Array<Poly>, +k: U32) -> Polys:
  (d, rest) = got
  one_cell_rest(rest, d, c, polys, k)

def cells_loop(n: Nat, ps: Polys, +k: U32) -> Polys:
  match n:
    case 0n:
      ps
    case 1n+p:
      match ps:
        case Polys{d, c, polys}:
          cells_loop(p, one_cell(cell_src_of(VoronoiDiagram.cell_info(d, k)), c, polys, k), (k + 1 : U32))

def poly_state(p: Poly) -> U32:
  match p:
    case Poly{_, _, _, _, +s}:
      s

def with_state(+s: U32, p: Poly) -> Poly:
  match p:
    case Poly{+pts, +cx, +cy, +nbs, _}:
      Poly{pts, cx, cy, nbs, s}

type Nb is Type:
  Nb{polys: Array<Poly>, states: List<&2, U32>}

def nb_got(got: Array<Poly> & Poly, +acc: List<&2, U32>) -> Nb:
  (polys, +p) = got
  Nb{polys, poly_state(p) <> acc}

def nb_read(boundary: Bool, polys: Array<Poly>, +j: U32, +acc: List<&2, U32>) -> Nb:
  match boundary:
    case True{}:
      Nb{polys, 0 <> acc}
    case False{}:
      nb_got(Array.get(Poly, polys, j), acc)

def nb_step(nb: Nb, +j: U32) -> Nb:
  match nb:
    case Nb{polys, +acc}:
      nb_read(U32.is_eq(j, nil()), polys, j, acc)

def states_of(nbs: List<&2, U32>, nb: Nb) -> Nb:
  match nbs:
    case Nil{}:
      nb
    case Con{+j, rest}:
      states_of(rest, nb_step(nb, j))

def all_above(l: List<&2, U32>) -> Bool:
  match l:
    case Nil{}:
      True{}
    case Con{+s, rest}:
      (2 < s : U32) && all_above(rest)

def any_blank(l: List<&2, U32>) -> Bool:
  match l:
    case Nil{}:
      False{}
    case Con{+s, rest}:
      U32.is_eq(s, 1) || any_blank(rest)

def next_state(+st: U32, +nb: List<&2, U32>) -> U32:
  Bool.pick(U32, (st < 4 : U32), Bool.pick(U32, U32.is_eq(st, 1) && all_above(nb), 2, st), Bool.pick(U32, any_blank(nb), 3, st))

def pass_site(nb: Nb, +i: U32, +p: Poly) -> Array<Poly>:
  match nb:
    case Nb{polys, +states}:
      Array.set(Poly, polys, i, with_state(next_state(poly_state(p), states), p))

def pass_read(got: Array<Poly> & Poly, +i: U32) -> Array<Poly>:
  (polys, +p) = got
  match p:
    case Poly{_, _, _, +nbs, _}:
      pass_site(states_of(nbs, Nb{polys, Nil{}}), i, p)

def state_pass(n: Nat, polys: Array<Poly>, +i: U32) -> Array<Poly>:
  match n:
    case 0n:
      polys
    case 1n+p:
      state_pass(p, pass_read(Array.get(Poly, polys, i), i), (i + 1 : U32))

def blank_poly(+s: SiteIn) -> Poly:
  match s:
    case SiteIn{_, _, _, +cx, +cy}:
      Poly{Nil{}, cx, cy, Nil{}, 5}

def fill_polys(l: List<&2, SiteIn>, sites: Array<SiteIn>, polys: Array<Poly>, +i: U32) -> Ctx & Array<Poly>:
  match l:
    case Nil{}:
      (Ctx{sites, i, Frame{F64Repr.zero(), F64Repr.zero()}}, polys)
    case Con{+s, rest}:
      fill_polys(rest, Array.set(SiteIn, sites, i, s), Array.set(Poly, polys, i, blank_poly(s)), (i + 1 : U32))

def with_frame(c: Ctx, +f: Frame) -> Ctx:
  match c:
    case Ctx{sites, +n, _}:
      Ctx{sites, n, f}

# The result of BuildVoronoi: the Boost build (its records) and one Poly per site, in site order.
type Cells is Type:
  Cells{built: VoronoiBuilder.Built, polys: Array<Poly>, n: U32}

def after_count(got: Ctx & U32, d: VoronoiDiagram.Diagram, polys: Array<Poly>, +vsites: List<&2, VoronoiPredicates.Site>, +events: List<&2, VoronoiPredicates.Circle>) -> Cells:
  (_, +n) = got
  Cells{VoronoiBuilder.Built{vsites, events, d}, state_pass(U32.to_nat(n), polys, 0), n}

def after_cells(ps: Polys, +sites: List<&2, VoronoiBuilder.Segment>, +events: List<&2, VoronoiPredicates.Circle>, +vsites: List<&2, VoronoiPredicates.Site>) -> Cells:
  match ps:
    case Polys{d, c, polys}:
      after_count(ctx_n(c), d, polys, vsites, events)

def run_cells(got: VoronoiDiagram.Diagram & U32, c: Ctx, polys: Array<Poly>, +vsites: List<&2, VoronoiPredicates.Site>, +events: List<&2, VoronoiPredicates.Circle>) -> Cells:
  (d, +nc) = got
  after_cells(cells_loop(U32.to_nat(nc), Polys{d, c, polys}, 0), Nil{}, events, vsites)

def run_built_ctx(got: Ctx & Array<Poly>, d: VoronoiDiagram.Diagram, +vsites: List<&2, VoronoiPredicates.Site>, +events: List<&2, VoronoiPredicates.Circle>) -> Cells:
  (c, polys) = got
  run_cells(VoronoiDiagram.cell_count(d), c, polys, vsites, events)

def run_built(b: VoronoiBuilder.Built, got: Ctx & Array<Poly>) -> Cells:
  match b:
    case VoronoiBuilder.Built{+vsites, +events, d}:
      run_built_ctx(got, d, vsites, events)

def depth_for(+n: U32) -> Nat:
  U32.to_nat((U32.from_nat(U32.log2((n + 1 : U32))) + 1 : U32))

def ctx_framed(got: Ctx & Array<Poly>, +f: Frame) -> Ctx & Array<Poly>:
  (c, polys) = got
  (with_frame(c, f), polys)

def count_sites(l: List<&2, SiteIn>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      count_sites(rest, (acc + 1 : U32))

# BoostMap::BuildVoronoi for the sites in site order, in the w x h frame of SetSize.
def build_voronoi(+windows: Bool, +w: U32, +h: U32, +sites: List<&2, SiteIn>) -> Cells:
  +depth = depth_for(count_sites(sites, 0))
  +f = {Frame{F64Repr.from_u32(w), F64Repr.from_u32(h)} : Frame}
  run_built(VoronoiBuilder.construct(windows, site_pts(sites), frame_segments(w, h)), ctx_framed(fill_polys(sites, Array.new(SiteIn, depth, SiteIn{0, 0, 0, 0, 0}), Array.new(Poly, depth, Poly{Nil{}, 0, 0, Nil{}, 5}), 0), f))
