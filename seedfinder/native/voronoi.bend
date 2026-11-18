import Base
import ../f64/repr.bend as F64Repr
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

# Decoding: each step takes the answer's words and gives what it read with the words after it.

def cons(-A: Data, +x: A, got: List<&2, A> & List<&2, U32>) -> List<&2, A> & List<&2, U32>:
  (+xs, +rest) = got
  (x <> xs, rest)

def words(n: Nat, +ws: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match n:
    case 0n:
      (Nil{}, ws)
    case 1n+p:
      match ws:
        case Con{+w, +rest}:
          cons(U32, w, words(p, rest))
        case Nil{}:
          (Nil{}, Nil{})

def vecs(n: Nat, +ws: List<&2, U32>) -> List<&2, LayoutSpace.Vec> & List<&2, U32>:
  match n:
    case 0n:
      (Nil{}, ws)
    case 1n+p:
      match ws:
        case Con{+a, Con{+b, Con{+c, Con{+d, +rest}}}}:
          cons(LayoutSpace.Vec, LayoutSpace.Vec{F64Repr.F64{a, b}, F64Repr.F64{c, d}}, vecs(p, rest))
        case _:
          (Nil{}, Nil{})

def p32s(n: Nat, +ws: List<&2, U32>) -> List<&2, VoronoiPolygon.P32> & List<&2, U32>:
  match n:
    case 0n:
      (Nil{}, ws)
    case 1n+p:
      match ws:
        case Con{+x, Con{+y, +rest}}:
          cons(VoronoiPolygon.P32, VoronoiPolygon.P32{x, y}, p32s(p, rest))
        case _:
          (Nil{}, Nil{})

def poly_state(+pts: List<&2, VoronoiPolygon.P32>, +cx: U32, +cy: U32, +nbs: List<&2, U32>, +ws: List<&2, U32>) -> VoronoiPolygon.Poly & List<&2, U32>:
  match ws:
    case Con{+state, +rest}:
      (VoronoiPolygon.Poly{pts, cx, cy, nbs, state}, rest)
    case Nil{}:
      (VoronoiPolygon.Poly{pts, cx, cy, nbs, 0}, Nil{})

def poly_nbs(+pts: List<&2, VoronoiPolygon.P32>, +cx: U32, +cy: U32, got: List<&2, U32> & List<&2, U32>) -> VoronoiPolygon.Poly & List<&2, U32>:
  (+nbs, +rest) = got
  poly_state(pts, cx, cy, nbs, rest)

def poly_centroid(+pts: List<&2, VoronoiPolygon.P32>, +ws: List<&2, U32>) -> VoronoiPolygon.Poly & List<&2, U32>:
  match ws:
    case Con{+cx, Con{+cy, Con{+nn, +rest}}}:
      poly_nbs(pts, cx, cy, words(U32.to_nat(nn), rest))
    case _:
      (VoronoiPolygon.Poly{pts, 0, 0, Nil{}, 0}, Nil{})

def poly_points(got: List<&2, VoronoiPolygon.P32> & List<&2, U32>) -> VoronoiPolygon.Poly & List<&2, U32>:
  (+pts, +rest) = got
  poly_centroid(pts, rest)

# A polygon: its point count, points, centroid, neighbour count, neighbours and state; with `n` 0, none.
def poly(n: Nat, +ws: List<&2, U32>) -> VoronoiPolygon.Poly & List<&2, U32>:
  match n:
    case 0n:
      (VoronoiPolygon.Poly{Nil{}, 0, 0, Nil{}, 0}, ws)
    case 1n+_:
      match ws:
        case Con{+npts, +rest}:
          poly_points(p32s(U32.to_nat(npts), rest))
        case Nil{}:
          (VoronoiPolygon.Poly{Nil{}, 0, 0, Nil{}, 0}, Nil{})

# `n` polygons, the first one read in `got`.
def polys_read(n: Nat, got: VoronoiPolygon.Poly & List<&2, U32>) -> List<&2, VoronoiPolygon.Poly> & List<&2, U32>:
  match n:
    case 0n:
      (_, +rest) = got
      (Nil{}, rest)
    case 1n+(+p):
      (+first, +rest) = got
      cons(VoronoiPolygon.Poly, first, polys_read(p, poly(p, rest)))

def polys(+n: Nat, +ws: List<&2, U32>) -> List<&2, VoronoiPolygon.Poly> & List<&2, U32>:
  polys_read(n, poly(n, ws))

def dpoints(n: Nat, +ws: List<&2, U32>) -> List<&2, TileWorld.DPoint> & List<&2, U32>:
  match n:
    case 0n:
      (Nil{}, ws)
    case 1n+p:
      match ws:
        case Con{+a, Con{+b, Con{+c, Con{+d, +rest}}}}:
          cons(TileWorld.DPoint, TileWorld.DPoint{F64Repr.F64{a, b}, F64Repr.F64{c, d}}, dpoints(p, rest))
        case _:
          (Nil{}, Nil{})

def vertex(has: Bool, +x: F64Repr.F64, +y: F64Repr.F64) -> Maybe<&2, TileWorld.DPoint>:
  match has:
    case True{}:
      Some{TileWorld.DPoint{x, y}}
    case False{}:
      None{}

def vedge_points(+twin: U32, +v0: Maybe<&2, TileWorld.DPoint>, +v1: Maybe<&2, TileWorld.DPoint>, got: List<&2, TileWorld.DPoint> & List<&2, U32>) -> TileWorld.VEdge & List<&2, U32>:
  (+pts, +rest) = got
  (TileWorld.VEdge{twin, v0, v1, pts}, rest)

# A half-edge: its twin cell's source, vertex flags, both vertices, point count and points.
def vedge_words(+ws: List<&2, U32>) -> TileWorld.VEdge & List<&2, U32>:
  match ws:
    case Con{+twin, Con{+flags, Con{+a, Con{+b, Con{+c, Con{+d, Con{+e, Con{+f, Con{+g, Con{+h, Con{+npts, +rest}}}}}}}}}}}:
      +v0 = vertex(U32.is_eq((flags .&. 1 : U32), 1), F64Repr.F64{a, b}, F64Repr.F64{c, d})
      +v1 = vertex(U32.is_eq((flags .&. 2 : U32), 2), F64Repr.F64{e, f}, F64Repr.F64{g, h})
      vedge_points(twin, v0, v1, dpoints(U32.to_nat(npts), rest))
    case _:
      (TileWorld.VEdge{0, None{}, None{}, Nil{}}, Nil{})

# The next half-edge; with `n` 0, none.
def vedge(n: Nat, +ws: List<&2, U32>) -> TileWorld.VEdge & List<&2, U32>:
  match n:
    case 0n:
      (TileWorld.VEdge{0, None{}, None{}, Nil{}}, ws)
    case 1n+_:
      vedge_words(ws)

def vedges_read(n: Nat, got: TileWorld.VEdge & List<&2, U32>) -> List<&2, TileWorld.VEdge> & List<&2, U32>:
  match n:
    case 0n:
      (_, +rest) = got
      (Nil{}, rest)
    case 1n+(+p):
      (+first, +rest) = got
      cons(TileWorld.VEdge, first, vedges_read(p, vedge(p, rest)))

def cell_edges(+src: U32, got: List<&2, TileWorld.VEdge> & List<&2, U32>) -> TileWorld.Cell & List<&2, U32>:
  (+edges, +rest) = got
  (TileWorld.Cell{src, edges}, rest)

# A tile cell: its source, edge count and edges; with `n` 0, none.
def cell(n: Nat, +ws: List<&2, U32>) -> TileWorld.Cell & List<&2, U32>:
  match n:
    case 0n:
      (TileWorld.Cell{0, Nil{}}, ws)
    case 1n+_:
      match ws:
        case Con{+src, Con{+count, +rest}}:
          +edges = U32.to_nat(count)
          cell_edges(src, vedges_read(edges, vedge(edges, rest)))
        case _:
          (TileWorld.Cell{0, Nil{}}, Nil{})

def cells(n: Nat, got: TileWorld.Cell & List<&2, U32>) -> List<&2, TileWorld.Cell>:
  match n:
    case 0n:
      Nil{}
    case 1n+(+p):
      (+first, +rest) = got
      first <> cells(p, cell(p, rest))

def counted_cells(+ws: List<&2, U32>) -> List<&2, TileWorld.Cell>:
  match ws:
    case Con{+count, +rest}:
      +n = U32.to_nat(count)
      cells(n, cell(n, rest))
    case Nil{}:
      Nil{}

def ahead_tile(+commit: List<&2, VoronoiPolygon.Poly>, got: List<&2, VoronoiPolygon.Poly> & List<&2, U32>) -> Ahead:
  (+tile, +rest) = got
  Ahead{commit, tile, counted_cells(rest)}

def ahead_commit(+n: Nat, got: List<&2, VoronoiPolygon.Poly> & List<&2, U32>) -> Ahead:
  (+commit, +rest) = got
  ahead_tile(commit, polys(n, rest))

def ahead(last: Bool, +n: Nat, +ws: List<&2, U32>) -> Maybe<&2, Ahead>:
  match last:
    case True{}:
      Some{ahead_commit(n, polys(n, ws))}
    case False{}:
      None{}

def answer_polys(+ps: List<&2, LayoutSpace.Vec>, +last: U32, +n: Nat, got: List<&2, VoronoiPolygon.Poly> & List<&2, U32>) -> Answer:
  (+polys, +rest) = got
  Answer{ps, polys, ahead(U32.is_eq(last, 1), n, rest)}

def answer_flag(+ps: List<&2, LayoutSpace.Vec>, +n: Nat, +ws: List<&2, U32>) -> Answer:
  match ws:
    case Con{+last, +rest}:
      answer_polys(ps, last, n, polys(n, rest))
    case Nil{}:
      Answer{ps, Nil{}, None{}}

def answer_vecs(+n: Nat, got: List<&2, LayoutSpace.Vec> & List<&2, U32>) -> Answer:
  (+ps, +rest) = got
  answer_flag(ps, n, rest)

def answer_words(+ws: List<&2, U32>) -> Answer:
  match ws:
    case Con{+n, +rest}:
      +count = U32.to_nat(n)
      answer_vecs(count, vecs(count, rest))
    case Nil{}:
      Answer{Nil{}, Nil{}, None{}}

# The words 1..at of an array, `got` holding word `at`, before `acc`; `n` is at - 1.
def listed(n: Nat, got: Array<U32> & U32, +at: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      (_, +w) = got
      w <> acc
    case 1n+p:
      (ws, +w) = got
      listed(p, ws[(at - 1 : U32)], (at - 1 : U32), w <> acc)

def counted(got: Array<U32> & U32) -> Answer:
  (ws, +count) = got
  +last = (count - 1 : U32)
  answer_words(listed(U32.to_nat((last - 1 : U32)), ws[last], last, Nil{}))

# The answer's words decoded (read on this thread, the effect's thread only copies them).
def answer(ws: Array<U32>) -> Answer:
  counted(ws[0])
