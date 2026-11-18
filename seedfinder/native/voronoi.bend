import Base
import ../worldsim/layout/space.bend as LayoutSpace
import ../worldsim/voronoi/polygon.bend as VoronoiPolygon
import ../worldsim/tiles/world.bend as TileWorld

# BuildVoronoi (worldsim/voronoi with gen/world.bend's tile cells, bit for bit) as native C (voronoi.c) on an IO helper
# thread, right after the native KK pass in the same effect (NativeKK.native_layout): the pass's build, and after the
# last pass also the builds of Commit and ConvertToTileMap, which follow from the pass alone. Here: the effect's plan
# words and the decoding of its answer.

def sites_into(sites: List<&2, VoronoiPolygon.SiteIn>, +at: U32, ws: Array<U32>) -> Array<U32>:
  match sites:
    case Nil{}:
      ws
    case Con{VoronoiPolygon.SiteIn{_, _, +kind, +cx, +cy}, rest}:
      ws[at] <- kind
      ws[(at + 1 : U32)] <- cx
      ws[(at + 2 : U32)] <- cy
      sites_into(rest, (at + 3 : U32), ws)

# The plan words of a pass: windows, the world size, whether it is the last pass, then each site's kind and the
# centroid it keeps without a cell (the sites' positions come from the KK pass).
def plan(+windows: Bool, +world: U32, +last: Bool, +sites: List<&2, VoronoiPolygon.SiteIn>) -> Array<U32>:
  +size = (3 + U32.from_nat(List.length(&2, VoronoiPolygon.SiteIn, sites)) * 3 : U32)
  ws = Array.new(U32, Nat.add(U32.log2((size - 1 : U32)), 1n), 0)
  ws[0] <- Bool.to_u32(windows)
  ws[1] <- world
  ws[2] <- Bool.to_u32(last)
  sites_into(sites, 3, ws)

# The builds that ride on a native answer after the last pass: Commit's polygons and ConvertToTileMap's polygons and
# cells.
type Ahead is Data:
  Ahead{commit: List<&2, VoronoiPolygon.Poly>, tile: List<&2, VoronoiPolygon.Poly>, cells: List<&2, TileWorld.Cell>}

# A native answer, decoded: the KK positions, the pass's polygons and the builds ahead (after the last pass).
type Answer is Data:
  Answer{ps: List<&2, LayoutSpace.Vec>, polys: List<&2, VoronoiPolygon.Poly>, ahead: Maybe<&2, Ahead>}

# Decoding: each step reads the answer's words from a cursor and gives what it read with the cursor after it. Lists of
# fixed-size items are read from their last word, so they need no reversal.
type Cursor is Type:
  Cursor{ws: Array<U32>, at: U32}

def cons(-A: Data, +x: A, got: List<&2, A> & Cursor) -> List<&2, A> & Cursor:
  (+xs, rest) = got
  (x <> xs, rest)

def word_cons(got: Array<U32> & U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  (ws, +w) = got
  (ws, w <> acc)

# The `n` words before `end`.
def words_before(n: Nat, +end: U32, got: Array<U32> & List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      got
    case 1n+p:
      (ws, acc) = got
      words_before(p, (end - 1 : U32), word_cons(ws[(end - 1 : U32)], acc))

def p32_cons(got: Array<U32> & U32, +x: U32, acc: List<&2, VoronoiPolygon.P32>) -> Array<U32> & List<&2, VoronoiPolygon.P32>:
  (ws, +y) = got
  (ws, VoronoiPolygon.P32{x, y} <> acc)

def p32_read(got: Array<U32> & U32, +at: U32, acc: List<&2, VoronoiPolygon.P32>) -> Array<U32> & List<&2, VoronoiPolygon.P32>:
  (ws, +x) = got
  p32_cons(ws[(at + 1 : U32)], x, acc)

# The `n` points (x, y) before `end`.
def p32s_before(n: Nat, +end: U32, got: Array<U32> & List<&2, VoronoiPolygon.P32>) -> Array<U32> & List<&2, VoronoiPolygon.P32>:
  match n:
    case 0n:
      got
    case 1n+p:
      (ws, acc) = got
      p32s_before(p, (end - 2 : U32), p32_read(ws[(end - 2 : U32)], (end - 2 : U32), acc))

def vec_cons(got: Array<U32> & LayoutSpace.Vec, acc: List<&2, LayoutSpace.Vec>) -> Array<U32> & List<&2, LayoutSpace.Vec>:
  (ws, v) = got
  (ws, v <> acc)

# The `n` vectors (x hi, x lo, y hi, y lo) before `end`.
def vecs_before(n: Nat, +end: U32, got: Array<U32> & List<&2, LayoutSpace.Vec>) -> Array<U32> & List<&2, LayoutSpace.Vec>:
  match n:
    case 0n:
      got
    case 1n+p:
      (ws, acc) = got
      vecs_before(p, (end - 4 : U32), vec_cons(LayoutSpace.get_vec(ws, (end - 4 : U32)), acc))

def dpoint(v: LayoutSpace.Vec) -> TileWorld.DPoint:
  match v:
    case LayoutSpace.Vec{x, y}:
      TileWorld.DPoint{x, y}

def dpoint_cons(got: Array<U32> & LayoutSpace.Vec, acc: List<&2, TileWorld.DPoint>) -> Array<U32> & List<&2, TileWorld.DPoint>:
  (ws, v) = got
  (ws, dpoint(v) <> acc)

# The `n` points (x hi, x lo, y hi, y lo) before `end`.
def dpoints_before(n: Nat, +end: U32, got: Array<U32> & List<&2, TileWorld.DPoint>) -> Array<U32> & List<&2, TileWorld.DPoint>:
  match n:
    case 0n:
      got
    case 1n+p:
      (ws, acc) = got
      dpoints_before(p, (end - 4 : U32), dpoint_cons(LayoutSpace.get_vec(ws, (end - 4 : U32)), acc))

def poly_state(got: Array<U32> & U32, +pts: List<&2, VoronoiPolygon.P32>, +cx: U32, +cy: U32, +nbs: List<&2, U32>, +at: U32) -> VoronoiPolygon.Poly & Cursor:
  (ws, +state) = got
  (VoronoiPolygon.Poly{pts, cx, cy, nbs, state}, Cursor{ws, (at + 1 : U32)})

def poly_nbs(got: Array<U32> & List<&2, U32>, +pts: List<&2, VoronoiPolygon.P32>, +cx: U32, +cy: U32, +at: U32) -> VoronoiPolygon.Poly & Cursor:
  (ws, +nbs) = got
  poly_state(ws[at], pts, cx, cy, nbs, at)

def poly_nn(got: Array<U32> & U32, +pts: List<&2, VoronoiPolygon.P32>, +cx: U32, +cy: U32, +at: U32) -> VoronoiPolygon.Poly & Cursor:
  (ws, +nn) = got
  +end = (at + 1 + nn : U32)
  poly_nbs(words_before(U32.to_nat(nn), end, (ws, Nil{})), pts, cx, cy, end)

def poly_cy(got: Array<U32> & U32, +pts: List<&2, VoronoiPolygon.P32>, +cx: U32, +at: U32) -> VoronoiPolygon.Poly & Cursor:
  (ws, +cy) = got
  poly_nn(ws[(at + 1 : U32)], pts, cx, cy, (at + 1 : U32))

def poly_cx(got: Array<U32> & U32, +pts: List<&2, VoronoiPolygon.P32>, +at: U32) -> VoronoiPolygon.Poly & Cursor:
  (ws, +cx) = got
  poly_cy(ws[(at + 1 : U32)], pts, cx, (at + 1 : U32))

def poly_points(got: Array<U32> & List<&2, VoronoiPolygon.P32>, +at: U32) -> VoronoiPolygon.Poly & Cursor:
  (ws, +pts) = got
  poly_cx(ws[at], pts, at)

def poly_counted(got: Array<U32> & U32, +at: U32) -> VoronoiPolygon.Poly & Cursor:
  (ws, +npts) = got
  +end = (at + 1 + npts * 2 : U32)
  poly_points(p32s_before(U32.to_nat(npts), end, (ws, Nil{})), end)

# A polygon: its point count, points, centroid, neighbour count, neighbours and state; with `n` 0, none.
def poly(n: Nat, cur: Cursor) -> VoronoiPolygon.Poly & Cursor:
  match n:
    case 0n:
      (VoronoiPolygon.Poly{Nil{}, 0, 0, Nil{}, 0}, cur)
    case 1n+_:
      match cur:
        case Cursor{ws, +at}:
          poly_counted(ws[at], at)

# `n` polygons, the first one read in `got`.
def polys_read(n: Nat, got: VoronoiPolygon.Poly & Cursor) -> List<&2, VoronoiPolygon.Poly> & Cursor:
  match n:
    case 0n:
      (_, rest) = got
      (Nil{}, rest)
    case 1n+(+p):
      (+first, rest) = got
      cons(VoronoiPolygon.Poly, first, polys_read(p, poly(p, rest)))

def polys(+n: Nat, cur: Cursor) -> List<&2, VoronoiPolygon.Poly> & Cursor:
  polys_read(n, poly(n, cur))

def vertex(has: Bool, v: LayoutSpace.Vec) -> Maybe<&2, TileWorld.DPoint>:
  match has:
    case True{}:
      Some{dpoint(v)}
    case False{}:
      None{}

def vedge_points(got: Array<U32> & List<&2, TileWorld.DPoint>, +twin: U32, +v0: Maybe<&2, TileWorld.DPoint>, +v1: Maybe<&2, TileWorld.DPoint>, +end: U32) -> TileWorld.VEdge & Cursor:
  (ws, +pts) = got
  (TileWorld.VEdge{twin, v0, v1, pts}, Cursor{ws, end})

def vedge_counted(got: Array<U32> & U32, +twin: U32, +v0: Maybe<&2, TileWorld.DPoint>, +v1: Maybe<&2, TileWorld.DPoint>, +at: U32) -> TileWorld.VEdge & Cursor:
  (ws, +npts) = got
  +end = (at + 1 + npts * 4 : U32)
  vedge_points(dpoints_before(U32.to_nat(npts), end, (ws, Nil{})), twin, v0, v1, end)

def vedge_v1(got: Array<U32> & LayoutSpace.Vec, +twin: U32, +flags: U32, +v0: Maybe<&2, TileWorld.DPoint>, +at: U32) -> TileWorld.VEdge & Cursor:
  (ws, v) = got
  vedge_counted(ws[(at + 10 : U32)], twin, v0, vertex(U32.is_eq((flags .&. 2 : U32), 2), v), (at + 10 : U32))

def vedge_v0(got: Array<U32> & LayoutSpace.Vec, +twin: U32, +flags: U32, +at: U32) -> TileWorld.VEdge & Cursor:
  (ws, v) = got
  vedge_v1(LayoutSpace.get_vec(ws, (at + 6 : U32)), twin, flags, vertex(U32.is_eq((flags .&. 1 : U32), 1), v), at)

def vedge_flags(got: Array<U32> & U32, +twin: U32, +at: U32) -> TileWorld.VEdge & Cursor:
  (ws, +flags) = got
  vedge_v0(LayoutSpace.get_vec(ws, (at + 2 : U32)), twin, flags, at)

def vedge_twin(got: Array<U32> & U32, +at: U32) -> TileWorld.VEdge & Cursor:
  (ws, +twin) = got
  vedge_flags(ws[(at + 1 : U32)], twin, at)

# A half-edge: its twin cell's source, vertex flags, both vertices, point count and points; with `n` 0, none.
def vedge(n: Nat, cur: Cursor) -> TileWorld.VEdge & Cursor:
  match n:
    case 0n:
      (TileWorld.VEdge{0, None{}, None{}, Nil{}}, cur)
    case 1n+_:
      match cur:
        case Cursor{ws, +at}:
          vedge_twin(ws[at], at)

def vedges_read(n: Nat, got: TileWorld.VEdge & Cursor) -> List<&2, TileWorld.VEdge> & Cursor:
  match n:
    case 0n:
      (_, rest) = got
      (Nil{}, rest)
    case 1n+(+p):
      (+first, rest) = got
      cons(TileWorld.VEdge, first, vedges_read(p, vedge(p, rest)))

def cell_edges(+src: U32, got: List<&2, TileWorld.VEdge> & Cursor) -> TileWorld.Cell & Cursor:
  (+edges, rest) = got
  (TileWorld.Cell{src, edges}, rest)

def cell_counted(got: Array<U32> & U32, +src: U32, +at: U32) -> TileWorld.Cell & Cursor:
  (ws, +count) = got
  +edges = U32.to_nat(count)
  cell_edges(src, vedges_read(edges, vedge(edges, Cursor{ws, (at + 1 : U32)})))

def cell_src(got: Array<U32> & U32, +at: U32) -> TileWorld.Cell & Cursor:
  (ws, +src) = got
  cell_counted(ws[(at + 1 : U32)], src, (at + 1 : U32))

# A tile cell: its source, edge count and edges; with `n` 0, none.
def cell(n: Nat, cur: Cursor) -> TileWorld.Cell & Cursor:
  match n:
    case 0n:
      (TileWorld.Cell{0, Nil{}}, cur)
    case 1n+_:
      match cur:
        case Cursor{ws, +at}:
          cell_src(ws[at], at)

def cells(n: Nat, got: TileWorld.Cell & Cursor) -> List<&2, TileWorld.Cell>:
  match n:
    case 0n:
      Nil{}
    case 1n+(+p):
      (+first, rest) = got
      first <> cells(p, cell(p, rest))

def counted_cells(got: Array<U32> & U32, +at: U32) -> List<&2, TileWorld.Cell>:
  (ws, +count) = got
  +n = U32.to_nat(count)
  cells(n, cell(n, Cursor{ws, (at + 1 : U32)}))

def ahead_tile(+commit: List<&2, VoronoiPolygon.Poly>, got: List<&2, VoronoiPolygon.Poly> & Cursor) -> Ahead:
  (+tile, rest) = got
  match rest:
    case Cursor{ws, +at}:
      Ahead{commit, tile, counted_cells(ws[at], at)}

def ahead_commit(+n: Nat, got: List<&2, VoronoiPolygon.Poly> & Cursor) -> Ahead:
  (+commit, rest) = got
  ahead_tile(commit, polys(n, rest))

def ahead(last: Bool, +n: Nat, cur: Cursor) -> Maybe<&2, Ahead>:
  match last:
    case True{}:
      Some{ahead_commit(n, polys(n, cur))}
    case False{}:
      None{}

def answer_polys(+ps: List<&2, LayoutSpace.Vec>, +last: U32, +n: Nat, got: List<&2, VoronoiPolygon.Poly> & Cursor) -> Answer:
  (+polys, rest) = got
  Answer{ps, polys, ahead(U32.is_eq(last, 1), n, rest)}

def answer_flag(got: Array<U32> & U32, +ps: List<&2, LayoutSpace.Vec>, +n: Nat, +at: U32) -> Answer:
  (ws, +last) = got
  answer_polys(ps, last, n, polys(n, Cursor{ws, (at + 1 : U32)}))

def answer_vecs(got: Array<U32> & List<&2, LayoutSpace.Vec>, +n: Nat, +at: U32) -> Answer:
  (ws, +ps) = got
  answer_flag(ws[at], ps, n, at)

def answer_counted(got: Array<U32> & U32) -> Answer:
  (ws, +count) = got
  +end = (2 + count * 4 : U32)
  answer_vecs(vecs_before(U32.to_nat(count), end, (ws, Nil{})), U32.to_nat(count), end)

# The answer's words decoded (read on this thread, the effect's thread only copies them): word 0 holds the word count,
# word 1 the KK's vertex count.
def answer(ws: Array<U32>) -> Answer:
  answer_counted(ws[1])
