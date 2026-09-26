import Base
import ../../f64/word.bend as F64Word
import ../../f64/repr.bend as F64Repr
import ../../f64/cmp.bend as F64Cmp
import ./predicates.bend as VoronoiPredicates

# Boost.Polygon 1.52 voronoi_diagram<double>: cells, vertices and half-edges in arrays (edge i's twin is i ^ 1, as
# edges are always pushed in pairs), the builder's two _insert_new_edge forms, and _build() (degenerate edge removal
# with 128-ulp vertex equality, compaction with Boost's pointer fix-ups, incident edges, and closing of open cell
# chains). Missing links and vertices are `nil()`.

type Edge is Data:
  Edge{cell: U32, v0: U32, next: U32, prev: U32, flags: U32}

type Vertex is Data:
  Vertex{x: F64Repr.F64, y: F64Repr.F64, incident: U32}

type Cell is Data:
  Cell{src: U32, cat: U32, incident: U32}

type Diagram is Type:
  Diagram{edges: Array<Edge>, ne: U32, vertices: Array<Vertex>, nv: U32, cells: Array<Cell>, nc: U32}

def nil() -> U32:
  4294967295

def is_nil(+x: U32) -> Bool:
  U32.is_eq(x, nil())

def linear_bit() -> U32:
  1

def primary_bit() -> U32:
  2

def depth_for(+words: U32) -> Nat:
  U32.to_nat((U32.from_nat(U32.log2(words)) + 1 : U32))

# An empty diagram with room for the given number of site events.
def empty(+sites: U32) -> Diagram:
  +edge_depth = depth_for(((sites * 8 : U32) + 16 : U32))
  +site_depth = depth_for(((sites * 2 : U32) + 8 : U32))
  Diagram{Array.new(Edge, edge_depth, Edge{0, nil(), nil(), nil(), 0}), 0,
    Array.new(Vertex, site_depth, Vertex{F64Repr.zero(), F64Repr.zero(), nil()}), 0,
    Array.new(Cell, site_depth, Cell{0, 0, nil()}), 0}

# is_primary_edge(site1, site2).
def is_primary(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site) -> Bool:
  +f1 = VoronoiPredicates.is_segment(s1)
  +f2 = VoronoiPredicates.is_segment(s2)
  +one = Bool.not(VoronoiPredicates.pt_eq(VoronoiPredicates.point0(s1), VoronoiPredicates.point0(s2))) && Bool.not(VoronoiPredicates.pt_eq(VoronoiPredicates.point1(s1), VoronoiPredicates.point0(s2)))
  +two = Bool.not(VoronoiPredicates.pt_eq(VoronoiPredicates.point0(s2), VoronoiPredicates.point0(s1))) && Bool.not(VoronoiPredicates.pt_eq(VoronoiPredicates.point1(s2), VoronoiPredicates.point0(s1)))
  Bool.pick(Bool, f1 && Bool.not(f2), one, Bool.pick(Bool, Bool.not(f1) && f2, two, True{}))

def edge_flags(+s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site) -> U32:
  +primary = is_primary(s1, s2)
  +linear = Bool.not(primary) || Bool.not(Bool.xor(VoronoiPredicates.is_segment(s1), VoronoiPredicates.is_segment(s2)))
  ((Bool.to_u32(linear) * linear_bit()) + (Bool.to_u32(primary) * primary_bit()) : U32)

def cell_of(+s: VoronoiPredicates.Site) -> Cell:
  Cell{VoronoiPredicates.site_initial(s), VoronoiPredicates.site_category(s), nil()}

def push_cell(cells: Array<Cell>, +nc: U32, +s: VoronoiPredicates.Site) -> Array<Cell>:
  Array.set(Cell, cells, nc, cell_of(s))

def first_cell(first: Bool, cells: Array<Cell>, +nc: U32, +s: VoronoiPredicates.Site) -> Array<Cell>:
  match first:
    case True{}:
      push_cell(cells, nc, s)
    case False{}:
      cells

# _process_single_site(site).
def single_site(d: Diagram, +s: VoronoiPredicates.Site) -> Diagram:
  match d:
    case Diagram{edges, +ne, vertices, +nv, cells, +nc}:
      Diagram{edges, ne, vertices, nv, push_cell(cells, nc, s), (nc + 1 : U32)}

# _insert_new_edge(site1, site2): a new twin pair between the two sites' cells (site2's cell is pushed now).
# Returns the diagram and the index of the first edge.
def insert_edge(d: Diagram, +s1: VoronoiPredicates.Site, +s2: VoronoiPredicates.Site) -> Diagram & U32:
  match d:
    case Diagram{edges, +ne, vertices, +nv, cells, +nc}:
      +f = edge_flags(s1, s2)
      with_first = first_cell(U32.is_zero(nc), cells, nc, s1)
      +nc1 = (nc + Bool.to_u32(U32.is_zero(nc)) : U32)
      e1 = Array.set(Edge, edges, ne, Edge{VoronoiPredicates.site_sorted(s1), nil(), nil(), nil(), f})
      e2 = Array.set(Edge, e1, (ne + 1 : U32), Edge{VoronoiPredicates.site_sorted(s2), nil(), nil(), nil(), f})
      (Diagram{e2, (ne + 2 : U32), vertices, nv, push_cell(with_first, nc1, s2), (nc1 + 1 : U32)}, ne)

def with_v0(+v: U32, e: Edge) -> Edge:
  match e:
    case Edge{+c, _, +n, +p, +f}:
      Edge{c, v, n, p, f}

def with_next(+n: U32, e: Edge) -> Edge:
  match e:
    case Edge{+c, +v, _, +p, +f}:
      Edge{c, v, n, p, f}

def with_prev(+p: U32, e: Edge) -> Edge:
  match e:
    case Edge{+c, +v, +n, _, +f}:
      Edge{c, v, n, p, f}

def set_v0_got(got: Array<Edge> & Edge, +i: U32, +v: U32) -> Array<Edge>:
  (a, e) = got
  Array.set(Edge, a, i, with_v0(v, e))

def set_next_got(got: Array<Edge> & Edge, +i: U32, +n: U32) -> Array<Edge>:
  (a, e) = got
  Array.set(Edge, a, i, with_next(n, e))

def set_prev_got(got: Array<Edge> & Edge, +i: U32, +p: U32) -> Array<Edge>:
  (a, e) = got
  Array.set(Edge, a, i, with_prev(p, e))

def assign_v0(edges: Array<Edge>, +i: U32, +v: U32) -> Array<Edge>:
  set_v0_got(Array.get(Edge, edges, i), i, v)

def assign_next(edges: Array<Edge>, +i: U32, +n: U32) -> Array<Edge>:
  set_next_got(Array.get(Edge, edges, i), i, n)

def assign_prev(edges: Array<Edge>, +i: U32, +p: U32) -> Array<Edge>:
  set_prev_got(Array.get(Edge, edges, i), i, p)

def twin(+e: U32) -> U32:
  (e .^. 1 : U32)

# _insert_new_edge(site1, site3, circle, edge12, edge23): the circle event's vertex and the new twin pair.
# Returns the diagram and the index of the first new edge.
def insert_vertex(d: Diagram, +s1: VoronoiPredicates.Site, +s3: VoronoiPredicates.Site, +c: VoronoiPredicates.Circle, +e12: U32, +e23: U32) -> Diagram & U32:
  match d:
    case Diagram{edges, +ne, vertices, +nv, cells, +nc}:
      +f = edge_flags(s1, s3)
      v = Array.set(Vertex, vertices, nv, Vertex{VoronoiPredicates.circle_x(c), VoronoiPredicates.circle_y(c), nil()})
      a1 = assign_prev(assign_v0(edges, e12, nv), e12, ne)
      a2 = assign_prev(assign_v0(a1, e23, nv), e23, twin(e12))
      a3 = assign_next(assign_next(a2, twin(e12), e23), twin(e23), (ne + 1 : U32))
      a4 = Array.set(Edge, a3, ne, Edge{VoronoiPredicates.site_sorted(s1), nil(), e12, nil(), f})
      a5 = Array.set(Edge, a4, (ne + 1 : U32), Edge{VoronoiPredicates.site_sorted(s3), nv, nil(), twin(e23), f})
      (Diagram{a5, (ne + 2 : U32), v, (nv + 1 : U32), cells, nc}, ne)

def edge_prev(got: Array<Edge> & Edge) -> Array<Edge> & U32:
  (a, e) = got
  match e:
    case Edge{_, _, _, +p, _}:
      (a, p)

def edge_next(got: Array<Edge> & Edge) -> Array<Edge> & U32:
  (a, e) = got
  match e:
    case Edge{_, _, +n, _, _}:
      (a, n)

def edge_v0(got: Array<Edge> & Edge) -> Array<Edge> & U32:
  (a, e) = got
  match e:
    case Edge{_, +v, _, _, _}:
      (a, v)

def prev_of(edges: Array<Edge>, +i: U32) -> Array<Edge> & U32:
  edge_prev(Array.get(Edge, edges, i))

def next_of(edges: Array<Edge>, +i: U32) -> Array<Edge> & U32:
  edge_next(Array.get(Edge, edges, i))

def v0_of(edges: Array<Edge>, +i: U32) -> Array<Edge> & U32:
  edge_v0(Array.get(Edge, edges, i))

def rot_next_got(got: Array<Edge> & U32) -> Array<Edge> & U32:
  (a, p) = got
  (a, twin(p))

# rot_next(e) = e.prev.twin.
def rot_next(edges: Array<Edge>, +i: U32) -> Array<Edge> & U32:
  rot_next_got(prev_of(edges, i))

# An edge walk position: the arrays, the current edge and whether the walk is over.
type Walk is Type:
  Walk{a: Array<Edge>, e: U32, done: Bool}

def walk_until(got: Array<Edge> & U32, +stop: U32) -> Walk:
  (a, +e) = got
  Walk{a, e, U32.is_eq(e, stop)}

def walk_array(w: Walk) -> Array<Edge>:
  match w:
    case Walk{a, _, _}:
      a

def spread_loop(n: Nat, w: Walk, +stop: U32, +v: U32) -> Array<Edge>:
  match n:
    case 0n:
      walk_array(w)
    case 1n+p:
      match w:
        case Walk{a, +e, done}:
          match done:
            case True{}:
              a
            case False{}:
              spread_loop(p, walk_until(rot_next(assign_v0(a, e, v), e), stop), stop, v)

type Rot is Data:
  Rot{r1p: U32, r1n: U32, r2p: U32, r2n: U32}

def relink(a: Array<Edge>, +r: Rot) -> Array<Edge>:
  match r:
    case Rot{+r1p, +r1n, +r2p, +r2n}:
      b1 = assign_next(a, twin(r1n), r2p)
      b2 = assign_prev(b1, r2p, twin(r1n))
      b3 = assign_prev(b2, r1p, twin(r2n))
      assign_next(b3, twin(r2n), r1p)

def rot_r2n(got: Array<Edge> & U32, +r1p: U32, +r1n: U32, +r2p: U32) -> Array<Edge>:
  (a, +p2) = got
  relink(a, Rot{r1p, r1n, r2p, twin(p2)})

def rot_r2p(got: Array<Edge> & U32, +i: U32, +r1p: U32, +r1n: U32) -> Array<Edge>:
  (a, +r2p) = got
  rot_r2n(prev_of(a, twin(i)), r1p, r1n, r2p)

def rot_r1n(got: Array<Edge> & U32, +i: U32, +r1p: U32) -> Array<Edge>:
  (a, +p1) = got
  rot_r2p(next_of(a, i), i, r1p, twin(p1))

def rot_r1p(got: Array<Edge> & U32, +i: U32) -> Array<Edge>:
  (a, +r1p) = got
  rot_r1n(prev_of(a, i), i, r1p)

def remove_spread(got: Array<Edge> & U32, +i: U32, +fuel: U32) -> Array<Edge>:
  (a, +v) = got
  rot_r1p(next_of(spread_loop(U32.to_nat(fuel), walk_until(rot_next(a, twin(i)), twin(i)), twin(i), v), twin(i)), i)

# remove_edge(edge): vertex0 replaces vertex1 on the edges around vertex1, and the pair is unlinked.
def remove_edge(edges: Array<Edge>, +i: U32, +fuel: U32) -> Array<Edge>:
  remove_spread(v0_of(edges, i), i, fuel)

def ulp_same(+a: F64Repr.F64, +b: F64Repr.F64) -> Bool:
  Cmp.is_eq(F64Cmp.ulp_cmp(a, b, 128))

def vertex_pair_equal(got: Array<Vertex> & Vertex, +w: Vertex) -> Array<Vertex> & Bool:
  (vs, v) = got
  match v:
    case Vertex{+x, +y, _}:
      match w:
        case Vertex{+wx, +wy, _}:
          (vs, ulp_same(x, wx) && ulp_same(y, wy))

def vertex_second(got: Array<Vertex> & Vertex, +j: U32) -> Array<Vertex> & Bool:
  (vs, w) = got
  vertex_pair_equal(Array.get(Vertex, vs, j), w)

# vertex_equality_predicate (128 ulps on x and y) of two vertex indices.
def vertices_equal(vs: Array<Vertex>, +i: U32, +j: U32) -> Array<Vertex> & Bool:
  vertex_second(Array.get(Vertex, vs, i), j)

type Compact is Type:
  Compact{edges: Array<Edge>, vertices: Array<Vertex>, last: U32}

def fix_prev_links(has: Bool, a: Array<Edge>, +p1: U32, +e1: U32) -> Array<Edge>:
  match has:
    case True{}:
      assign_next(a, p1, e1)
    case False{}:
      a

def fix_twin_next(has: Bool, a: Array<Edge>, +n2: U32, +e1: U32) -> Array<Edge>:
  match has:
    case True{}:
      assign_prev(a, n2, twin(e1))
    case False{}:
      a

def fix_twin_links(has: Bool, a: Array<Edge>, +n1: U32, +p2: U32, +e1: U32) -> Array<Edge>:
  match has:
    case True{}:
      assign_next(assign_prev(a, n1, e1), p2, twin(e1))
    case False{}:
      a

def fix_twin(got: Array<Edge> & Edge, +e1: U32, +n1: U32, +has_p1: Bool) -> Array<Edge>:
  (a, e) = got
  match e:
    case Edge{_, _, +n2, +p2, _}:
      fix_twin_links(Bool.not(is_nil(p2)), fix_twin_next(has_p1, a, n2, e1), n1, p2, e1)

def fix_moved(got: Array<Edge> & Edge, +e1: U32) -> Array<Edge>:
  (a, e) = got
  match e:
    case Edge{_, _, +n1, +p1, _}:
      +has_p1 = Bool.not(is_nil(p1))
      fix_twin(Array.get(Edge, fix_prev_links(has_p1, a, p1, e1), twin(e1)), e1, n1, has_p1)

def move_second(got: Array<Edge> & Edge, +last: U32) -> Array<Edge>:
  (a, t) = got
  fix_moved(Array.get(Edge, Array.set(Edge, a, (last + 1 : U32), t), last), last)

def move_first(got: Array<Edge> & Edge, +i: U32, +last: U32) -> Array<Edge>:
  (a, e) = got
  move_second(Array.get(Edge, Array.set(Edge, a, last, e), (i + 1 : U32)), last)

def keep_pair(moved: Bool, edges: Array<Edge>, vs: Array<Vertex>, +last: U32, +i: U32) -> Compact:
  match moved:
    case True{}:
      Compact{move_first(Array.get(Edge, edges, i), i, last), vs, (last + 2 : U32)}
    case False{}:
      Compact{edges, vs, (last + 2 : U32)}

def degenerate_if(same: Bool, edges: Array<Edge>, vs: Array<Vertex>, +last: U32, +i: U32, +fuel: U32) -> Compact:
  match same:
    case True{}:
      Compact{remove_edge(edges, i, fuel), vs, last}
    case False{}:
      keep_pair(Bool.not(U32.is_eq(i, last)), edges, vs, last, i)

def degenerate_checked(got: Array<Vertex> & Bool, edges: Array<Edge>, +last: U32, +i: U32, +fuel: U32) -> Compact:
  (vs, +same) = got
  degenerate_if(same, edges, vs, last, i, fuel)

def pair_finite(finite: Bool, edges: Array<Edge>, vs: Array<Vertex>, +v1: U32, +v2: U32, +last: U32, +i: U32, +fuel: U32) -> Compact:
  match finite:
    case True{}:
      degenerate_checked(vertices_equal(vs, v1, v2), edges, last, i, fuel)
    case False{}:
      keep_pair(Bool.not(U32.is_eq(i, last)), edges, vs, last, i)

def pair_vertices(got: Array<Edge> & U32, +v1: U32, vs: Array<Vertex>, +last: U32, +i: U32, +fuel: U32) -> Compact:
  (edges, +v2) = got
  pair_finite(Bool.not(is_nil(v1)) && Bool.not(is_nil(v2)), edges, vs, v1, v2, last, i, fuel)

def pair_first(got: Array<Edge> & U32, vs: Array<Vertex>, +last: U32, +i: U32, +fuel: U32) -> Compact:
  (edges, +v1) = got
  pair_vertices(v0_of(edges, (i + 1 : U32)), v1, vs, last, i, fuel)

def compact_pair(c: Compact, +i: U32, +fuel: U32) -> Compact:
  match c:
    case Compact{edges, vs, +last}:
      pair_first(v0_of(edges, i), vs, last, i, fuel)

def compact_loop(n: Nat, go: Bool, c: Compact, +i: U32, +ne: U32) -> Compact:
  match n:
    case 0n:
      c
    case 1n+p:
      match go:
        case True{}:
          compact_loop(p, ((i + 2 : U32) < ne : U32), compact_pair(c, i, ne), (i + 2 : U32), ne)
        case False{}:
          c

def set_cell_incident(got: Array<Cell> & Cell, +c: U32, +e: U32) -> Array<Cell>:
  (a, cell) = got
  match cell:
    case Cell{+s, +k, _}:
      Array.set(Cell, a, c, Cell{s, k, e})

def set_vertex_incident(got: Array<Vertex> & Vertex, +v: U32, +e: U32) -> Array<Vertex>:
  (a, x) = got
  match x:
    case Vertex{+vx, +vy, _}:
      Array.set(Vertex, a, v, Vertex{vx, vy, e})

def vertex_incident_if(has: Bool, vs: Array<Vertex>, +v: U32, +e: U32) -> Array<Vertex>:
  match has:
    case True{}:
      set_vertex_incident(Array.get(Vertex, vs, v), v, e)
    case False{}:
      vs

def incident_one(got: Array<Edge> & Edge, cells: Array<Cell>, vs: Array<Vertex>, +i: U32) -> Compact & Array<Cell>:
  (edges, e) = got
  match e:
    case Edge{+c, +v, _, _, _}:
      (Compact{edges, vertex_incident_if(Bool.not(is_nil(v)), vs, v, i), 0}, set_cell_incident(Array.get(Cell, cells, c), c, i))

def incident_step(c: Compact, cells: Array<Cell>, +i: U32) -> Compact & Array<Cell>:
  match c:
    case Compact{edges, vs, _}:
      incident_one(Array.get(Edge, edges, i), cells, vs, i)

def incidents(n: Nat, go: Bool, got: Compact & Array<Cell>, +i: U32, +ne: U32) -> Compact & Array<Cell>:
  match n:
    case 0n:
      got
    case 1n+p:
      match go:
        case True{}:
          (c, cells) = got
          incidents(p, ((i + 1 : U32) < ne : U32), incident_step(c, cells, i), (i + 1 : U32), ne)
        case False{}:
          got

def retarget(n: Nat, w: Walk, +start: U32, +v: U32) -> Array<Edge>:
  match n:
    case 0n:
      walk_array(w)
    case 1n+p:
      match w:
        case Walk{a, +e, done}:
          match done:
            case True{}:
              a
            case False{}:
              retarget(p, walk_until(rot_next(assign_v0(a, e, v), e), start), start, v)

def squeeze_live(moved: Bool, vs: Array<Vertex>, +v: Vertex, +inc: U32, edges: Array<Edge>, +last: U32, +fuel: U32) -> Compact:
  match moved:
    case True{}:
      Compact{retarget(U32.to_nat(fuel), Walk{edges, inc, False{}}, inc, last), Array.set(Vertex, vs, last, v), (last + 1 : U32)}
    case False{}:
      Compact{edges, vs, (last + 1 : U32)}

def squeeze_kept(dead: Bool, vs: Array<Vertex>, +v: Vertex, +inc: U32, edges: Array<Edge>, +last: U32, +i: U32, +fuel: U32) -> Compact:
  match dead:
    case True{}:
      Compact{edges, vs, last}
    case False{}:
      squeeze_live(Bool.not(U32.is_eq(i, last)), vs, v, inc, edges, last, fuel)

def squeeze_one(got: Array<Vertex> & Vertex, edges: Array<Edge>, +last: U32, +i: U32, +fuel: U32) -> Compact:
  (vs, +v) = got
  match v:
    case Vertex{_, _, +inc}:
      squeeze_kept(is_nil(inc), vs, v, inc, edges, last, i, fuel)

def squeeze_step(c: Compact, +i: U32, +fuel: U32) -> Compact:
  match c:
    case Compact{edges, vs, +last}:
      squeeze_one(Array.get(Vertex, vs, i), edges, last, i, fuel)

def squeeze_vertices(n: Nat, go: Bool, c: Compact, +i: U32, +nv: U32, +fuel: U32) -> Compact:
  match n:
    case 0n:
      c
    case 1n+p:
      match go:
        case True{}:
          squeeze_vertices(p, ((i + 1 : U32) < nv : U32), squeeze_step(c, i, fuel), (i + 1 : U32), nv, fuel)
        case False{}:
          c

# A prev/next chase: the arrays, the edge reached, the candidate link and how it ends (0 go on, 1 stop at the
# edge reached, 2 stop at the candidate).
type Chase is Type:
  Chase{a: Array<Edge>, cur: U32, link: U32, code: U32}

def chase_prev(got: Array<Edge> & U32, +cur: U32, +start: U32) -> Chase:
  (a, +p) = got
  Chase{a, cur, p, F64Word.pick(is_nil(p), 1, F64Word.pick(U32.is_eq(p, start), 2, 0))}

def chase_next(got: Array<Edge> & U32, +cur: U32) -> Chase:
  (a, +x) = got
  Chase{a, cur, x, F64Word.pick(is_nil(x), 1, 0)}

def walk_prev(n: Nat, c: Chase, +start: U32) -> Array<Edge> & U32:
  match n:
    case 0n:
      match c:
        case Chase{a, +cur, _, _}:
          (a, cur)
    case 1n+k:
      match c:
        case Chase{a, +cur, +link, code}:
          match code:
            case 0:
              walk_prev(k, chase_prev(prev_of(a, link), link, start), start)
            case 1:
              (a, cur)
            case _:
              (a, link)

def walk_next(n: Nat, c: Chase) -> Array<Edge> & U32:
  match n:
    case 0n:
      match c:
        case Chase{a, +cur, _, _}:
          (a, cur)
    case 1n+k:
      match c:
        case Chase{a, +cur, +link, code}:
          match code:
            case 0:
              walk_next(k, chase_next(next_of(a, link), link))
            case _:
              (a, cur)

def close_chain(got: Array<Edge> & U32, +left: U32) -> Array<Edge>:
  (a, +right) = got
  assign_next(assign_prev(a, left, right), right, left)

def close_if(open: Bool, a: Array<Edge>, +left: U32, +start: U32, +fuel: U32) -> Array<Edge>:
  match open:
    case True{}:
      close_chain(walk_next(U32.to_nat(fuel), chase_next(next_of(a, start), start)), left)
    case False{}:
      a

def close_open(got: Array<Edge> & U32, +left: U32, +start: U32, +fuel: U32) -> Array<Edge>:
  (a, +p) = got
  close_if(is_nil(p), a, left, start, fuel)

def close_left(got: Array<Edge> & U32, +start: U32, +fuel: U32) -> Array<Edge>:
  (a, +left) = got
  close_open(prev_of(a, left), left, start, fuel)

def close_live(dead: Bool, cells: Array<Cell>, edges: Array<Edge>, +inc: U32, +fuel: U32) -> Array<Cell> & Array<Edge>:
  match dead:
    case True{}:
      (cells, edges)
    case False{}:
      (cells, close_left(walk_prev(U32.to_nat(fuel), chase_prev(prev_of(edges, inc), inc, inc), inc), inc, fuel))

def close_cell(got: Array<Cell> & Cell, edges: Array<Edge>, +fuel: U32) -> Array<Cell> & Array<Edge>:
  (cells, cell) = got
  match cell:
    case Cell{_, _, +inc}:
      close_live(is_nil(inc), cells, edges, inc, fuel)

def close_step(got: Array<Cell> & Array<Edge>, +c: U32, +fuel: U32) -> Array<Cell> & Array<Edge>:
  (cells, edges) = got
  close_cell(Array.get(Cell, cells, c), edges, fuel)

def close_cells(n: Nat, go: Bool, got: Array<Cell> & Array<Edge>, +c: U32, +nc: U32, +fuel: U32) -> Array<Cell> & Array<Edge>:
  match n:
    case 0n:
      got
    case 1n+p:
      match go:
        case True{}:
          close_cells(p, ((c + 1 : U32) < nc : U32), close_step(got, c, fuel), (c + 1 : U32), nc, fuel)
        case False{}:
          got

def closed(got: Array<Cell> & Array<Edge>, vs: Array<Vertex>, +ne: U32, +nv: U32, +nc: U32) -> Diagram:
  (cells, edges) = got
  Diagram{edges, ne, vs, nv, cells, nc}

def after_squeeze(c: Compact, cells: Array<Cell>, +ne: U32, +nc: U32) -> Diagram:
  match c:
    case Compact{edges, vs, +nv}:
      closed(close_cells(U32.to_nat(nc), (0 < nc : U32), (cells, edges), 0, nc, ne), vs, ne, nv, nc)

def after_incidents(got: Compact & Array<Cell>, +ne: U32, +nv: U32, +nc: U32) -> Diagram:
  (c, cells) = got
  match c:
    case Compact{edges, vs, _}:
      after_squeeze(squeeze_vertices(U32.to_nat(nv), (0 < nv : U32), Compact{edges, vs, 0}, 0, nv, ne), cells, ne, nc)

def after_compact(c: Compact, cells: Array<Cell>, +nv: U32, +nc: U32) -> Diagram:
  match c:
    case Compact{edges, vs, +ne}:
      after_incidents(incidents(U32.to_nat(ne), (0 < ne : U32), (Compact{edges, vs, 0}, cells), 0, ne), ne, nv, nc)

# voronoi_diagram::_build(). Its branch for a diagram without vertices is left out: the frame segments always
# produce vertices.
def build(d: Diagram) -> Diagram:
  match d:
    case Diagram{edges, +ne, vs, +nv, cells, +nc}:
      after_compact(compact_loop(U32.to_nat(ne), (0 < ne : U32), Compact{edges, vs, 0}, 0, ne), cells, nv, nc)

# One half-edge of a cell ring, resolved: the twin's cell, both vertices (when present) and the flags.
type Half is Data:
  Half{twin_cell: U32, has0: Bool, x0: F64Repr.F64, y0: F64Repr.F64, has1: Bool, x1: F64Repr.F64, y1: F64Repr.F64, flags: U32}

def vertex_get(has: Bool, vs: Array<Vertex>, +v: U32) -> Array<Vertex> & Vertex:
  match has:
    case True{}:
      Array.get(Vertex, vs, v)
    case False{}:
      (vs, Vertex{F64Repr.zero(), F64Repr.zero(), nil()})

def vertex_at(vs: Array<Vertex>, +v: U32) -> Array<Vertex> & Vertex:
  vertex_get(Bool.not(is_nil(v)), vs, v)

def half_of(got: Array<Vertex> & Vertex, +w: Vertex, +v0: U32, +v1: U32, +tc: U32, +f: U32) -> Array<Vertex> & Half:
  (vs, a) = got
  match a:
    case Vertex{+x0, +y0, _}:
      match w:
        case Vertex{+x1, +y1, _}:
          (vs, Half{tc, Bool.not(is_nil(v0)), x0, y0, Bool.not(is_nil(v1)), x1, y1, f})

def half_second(got: Array<Vertex> & Vertex, +v0: U32, +v1: U32, +tc: U32, +f: U32) -> Array<Vertex> & Half:
  (vs, w) = got
  half_of(vertex_at(vs, v0), w, v0, v1, tc, f)

type Ring is Type:
  Ring{d: Diagram, halves: List<&2, Half>}

def ring_add(got: Array<Vertex> & Half, edges: Array<Edge>, cells: Array<Cell>, +ne: U32, +nv: U32, +nc: U32, +acc: List<&2, Half>) -> Ring:
  (vs, h) = got
  Ring{Diagram{edges, ne, vs, nv, cells, nc}, h <> acc}

def ring_twin_edge(got: Array<Edge> & Edge, +v0: U32, cells: Array<Cell>, vs: Array<Vertex>, +ne: U32, +nv: U32, +nc: U32, +f: U32, +acc: List<&2, Half>) -> Ring:
  (edges, t) = got
  match t:
    case Edge{+tc, +v1, _, _, _}:
      ring_add(half_second(vertex_at(vs, v1), v0, v1, tc, f), edges, cells, ne, nv, nc, acc)

def ring_edge(got: Array<Edge> & Edge, cells: Array<Cell>, vs: Array<Vertex>, +ne: U32, +nv: U32, +nc: U32, +e: U32, +acc: List<&2, Half>) -> Ring & U32:
  (edges, x) = got
  match x:
    case Edge{_, +v0, +n, _, +f}:
      (ring_twin_edge(Array.get(Edge, edges, twin(e)), v0, cells, vs, ne, nv, nc, f, acc), n)

def ring_step(r: Ring, +e: U32) -> Ring & U32:
  match r:
    case Ring{d, +acc}:
      match d:
        case Diagram{edges, +ne, vs, +nv, cells, +nc}:
          ring_edge(Array.get(Edge, edges, e), cells, vs, ne, nv, nc, e, acc)

def ring_done(r: Ring) -> Ring:
  match r:
    case Ring{d, +acc}:
      Ring{d, List.reverse(&2, Half, acc)}

type RingAt is Type:
  RingAt{r: Ring, e: U32, done: Bool}

def ring_at(got: Ring & U32, +start: U32) -> RingAt:
  (r, +e) = got
  RingAt{r, e, U32.is_eq(e, start)}

def ring_walk(n: Nat, w: RingAt, +start: U32) -> Ring:
  match n:
    case 0n:
      match w:
        case RingAt{r, _, _}:
          ring_done(r)
    case 1n+p:
      match w:
        case RingAt{r, +e, done}:
          match done:
            case True{}:
              ring_done(r)
            case False{}:
              ring_walk(p, ring_at(ring_step(r, e), start), start)

def ring_live(dead: Bool, d: Diagram, +inc: U32, +ne: U32) -> Ring:
  match dead:
    case True{}:
      Ring{d, Nil{}}
    case False{}:
      ring_walk(U32.to_nat(ne), RingAt{Ring{d, Nil{}}, inc, False{}}, inc)

def ring_cell(got: Array<Cell> & Cell, edges: Array<Edge>, vs: Array<Vertex>, +ne: U32, +nv: U32, +nc: U32) -> Ring:
  (cells, cell) = got
  match cell:
    case Cell{_, _, +inc}:
      ring_live(is_nil(inc), Diagram{edges, ne, vs, nv, cells, nc}, inc, ne)

# The half-edges of cell c, from incident_edge along next until the ring closes (empty for a degenerate cell).
def cell_ring(d: Diagram, +c: U32) -> Ring:
  match d:
    case Diagram{edges, +ne, vs, +nv, cells, +nc}:
      ring_cell(Array.get(Cell, cells, c), edges, vs, ne, nv, nc)

def cell_info_got(got: Array<Cell> & Cell, edges: Array<Edge>, vs: Array<Vertex>, +ne: U32, +nv: U32, +nc: U32) -> Diagram & Cell:
  (cells, cell) = got
  (Diagram{edges, ne, vs, nv, cells, nc}, cell)

def cell_info(d: Diagram, +c: U32) -> Diagram & Cell:
  match d:
    case Diagram{edges, +ne, vs, +nv, cells, +nc}:
      cell_info_got(Array.get(Cell, cells, c), edges, vs, ne, nv, nc)

def cell_count(d: Diagram) -> Diagram & U32:
  match d:
    case Diagram{edges, +ne, vs, +nv, cells, +nc}:
      (Diagram{edges, ne, vs, nv, cells, nc}, nc)
