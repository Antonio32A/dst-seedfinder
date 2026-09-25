import Base
import ../../f32/ops.bend as FO
import ../../f64/repr.bend as FR
import ../../f64/arith.bend as FA
import ../grid.bend as GR
import ./groups.bend as TG
import ./lines.bend as TL
import ./topology.bend as TP
import ./world.bend as TW

# SeparateIslands (tiles.cpp): for every Voronoi edge of a painted cell, decides whether it becomes an impassable wall
# and rasterises the walls with DrawVoronoiEdge (5 parallel DrawTileLines per segment). Every wall paints the same
# tile and clears the line flag, so the walls can be drawn in any order.

def f32_of(+x: FR.F64) -> F32:
  FO.from_f64(x)

def dx_of(+p: TW.DPoint) -> FR.F64:
  match p:
    case TW.DPoint{+x, _}:
      x

def dy_of(+p: TW.DPoint) -> FR.F64:
  match p:
    case TW.DPoint{_, +y}:
      y

def vertex_distance(+v0: Maybe<&2, TW.DPoint>, +v1: Maybe<&2, TW.DPoint>) -> F32:
  +a = Maybe.default(&2, TW.DPoint, v0, TW.DPoint{FR.zero(), FR.zero()})
  +b = Maybe.default(&2, TW.DPoint, v1, TW.DPoint{FR.zero(), FR.zero()})
  +ey = (f32_of(dy_of(a)) - f32_of(dy_of(b)) : F32)
  +ex = (f32_of(dx_of(a)) - f32_of(dx_of(b)) : F32)
  F32.sqrt((ex * ex + ey * ey : F32))

def site_distance(+sa: TW.Site, +sb: TW.Site) -> F32:
  match sa:
    case TW.Site{_, +ax, +ay, _, _, _}:
      match sb:
        case TW.Site{_, +bx, +by, _, _, _}:
          +dy = (ay - by : F32)
          +dx = (ax - bx : F32)
          F32.sqrt((dx * dx + dy * dy : F32))

def is_room(+kind: U32) -> Bool:
  U32.is_eq(kind, 5) || U32.is_eq(kind, 6) || U32.is_eq(kind, 7)

def linked_if(on: Bool, +w: TW.World, +i: U32, +j: U32) -> Bool:
  match on:
    case True{}:
      TP.shares_task(w, i, j)
    case False{}:
      False{}

def short_edge(short: Bool, +w: TW.World, +i: U32, +j: U32) -> Bool:
  match short:
    case True{}:
      TP.shares_task(w, i, j)
    case False{}:
      True{}

def by_adjacency(adjacent: Bool, +w: TW.World, +i: U32, +j: U32, +v0: Maybe<&2, TW.DPoint>, +v1: Maybe<&2, TW.DPoint>) -> Bool:
  match adjacent:
    case True{}:
      short_edge((vertex_distance(v0, v1) <= 4.0 : F32), w, i, j)
    case False{}:
      linked_if(Bool.not(U32.is_eq(TP.kind_of(TW.node(w, i)), 4)) && Bool.not(U32.is_eq(TP.kind_of(TW.node(w, j)), 4)), w, i, j)

def near_enough(close: Bool, +w: TW.World, +i: U32, +j: U32, +v0: Maybe<&2, TW.DPoint>, +v1: Maybe<&2, TW.DPoint>) -> Bool:
  match close:
    case True{}:
      by_adjacency(TP.adjacent(w, i, j), w, i, j, v0, v1)
    case False{}:
      False{}

# Whether sites i and j count as connected across e: within 40 and joined by the edge (a short adjacent edge only
# when they share a task) or, apart from type-4 nodes, by a shared task.
def connected(+w: TW.World, +i: U32, +j: U32, +e: TW.VEdge) -> Bool:
  match e:
    case TW.VEdge{_, +v0, +v1, _}:
      near_enough(Bool.not((40.0 < site_distance(TW.site(w, i), TW.site(w, j)) : F32)), w, i, j, v0, v1)

def apart(to_site: Bool, +w: TW.World, +i: U32, +j: U32, +e: TW.VEdge) -> Bool:
  match to_site:
    case True{}:
      Bool.not(connected(w, i, j, e))
    case False{}:
      True{}

def wall_flag(free: Bool, +to_site: Bool, +w: TW.World, +i: U32, +j: U32, +e: TW.VEdge) -> Bool:
  match free:
    case True{}:
      apart(to_site, w, i, j, e)
    case False{}:
      False{}

def wall_room(room: Bool, +a: TW.Node, +to_site: Bool, +w: TW.World, +i: U32, +j: U32, +e: TW.VEdge) -> Bool:
  match room:
    case True{}:
      True{}
    case False{}:
      wall_flag(U32.is_zero((TP.flags_of(a) .&. 2 : U32)), to_site, w, i, j, e)

def room_of(to_site: Bool, +w: TW.World, +j: U32) -> Bool:
  match to_site:
    case True{}:
      is_room(TP.kind_of(TW.node(w, j)))
    case False{}:
      False{}

def wall_considered(considered: Bool, +a: TW.Node, +to_site: Bool, +w: TW.World, +i: U32, +j: U32, +e: TW.VEdge) -> Bool:
  match considered:
    case True{}:
      wall_room(is_room(TP.kind_of(a)) || room_of(to_site, w, j), a, to_site, w, i, j, e)
    case False{}:
      False{}

def considered_of(to_site: Bool, +w: TW.World, +j: U32) -> Bool:
  match to_site:
    case True{}:
      Bool.not(TP.is_blank_or_random(TW.node(w, j)))
    case False{}:
      True{}

# Whether the edge from cell i across `e` is drawn as a wall.
def is_wall(+w: TW.World, +i: U32, +e: TW.VEdge) -> Bool:
  match e:
    case TW.VEdge{+j, +v0, +v1, +points}:
      +to_site = (j < TW.count(w) : U32)
      wall_considered(considered_of(to_site, w, j), TW.node(w, i), to_site, w, i, j, TW.VEdge{j, v0, v1, points})

def wall_if(hit: Bool, +e: TW.VEdge, tail: List<&2, List<&2, TW.DPoint>>) -> List<&2, List<&2, TW.DPoint>>:
  match hit:
    case False{}:
      tail
    case True{}:
      match e:
        case TW.VEdge{_, _, _, +points}:
          points <> tail

def edge_walls(+w: TW.World, +i: U32, edges: List<&2, TW.VEdge>) -> List<&2, List<&2, TW.DPoint>>:
  match edges:
    case Nil{}:
      Nil{}
    case Con{+e, rest}:
      wall_if(is_wall(w, i, e), e, edge_walls(w, i, rest))

def cell_walls(skip: Bool, +w: TW.World, +c: TW.Cell) -> List<&2, List<&2, TW.DPoint>>:
  match skip:
    case True{}:
      Nil{}
    case False{}:
      match c:
        case TW.Cell{+src, +edges}:
          edge_walls(w, src, edges)

def cell_src(+c: TW.Cell) -> U32:
  match c:
    case TW.Cell{+src, _}:
      src

def cells_walls(+w: TW.World, cells: List<&2, TW.Cell>) -> List<&2, List<&2, TW.DPoint>>:
  match cells:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      List.append(&2, List<&2, TW.DPoint>, cell_walls(TP.is_blank_or_random(TW.node(w, cell_src(c))), w, c), cells_walls(w, rest))

def par_walls(+d: Nat, +w: TW.World, +cells: List<&2, TW.Cell>, +n: Nat) -> List<&2, List<&2, TW.DPoint>>:
  match d:
    case 0n:
      cells_walls(w, cells)
    case 1n+p:
      +half = Nat.div(n, 2n)
      a b = par_walls(p, w, List.take(&2, TW.Cell, cells, half), half) par_walls(p, w, List.drop(&2, TW.Cell, cells, half), Nat.sub(n, half))
      List.append(&2, List<&2, TW.DPoint>, a, b)

# The point lists of every wall, in cell and ring order (cells decided in parallel).
def walls(+w: TW.World) -> List<&2, List<&2, TW.DPoint>>:
  match w:
    case TW.World{_, _, _, _, _, _, _, +cells, _}:
      par_walls(4n, w, cells, List.length(&2, TW.Cell, cells))

def wall_pen() -> TL.Pen:
  TL.Pen{TG.impassable(), False{}, False{}}

def shifted(+v: FR.F64, +by: FR.F64) -> F32:
  f32_of(FA.add(v, by))

def draw_pair(g: GR.Grid, +a: TW.DPoint, +b: TW.DPoint) -> GR.Grid:
  match a:
    case TW.DPoint{+ax, +ay}:
      match b:
        case TW.DPoint{+bx, +by}:
          +pen = wall_pen()
          +one = FR.one()
          +minus = FR.neg(FR.one())
          g1 = TL.draw(g, pen, f32_of(ax), f32_of(ay), f32_of(bx), f32_of(by))
          g2 = TL.draw(g1, pen, shifted(ax, one), f32_of(ay), shifted(bx, one), f32_of(by))
          g3 = TL.draw(g2, pen, shifted(ax, minus), f32_of(ay), shifted(bx, minus), f32_of(by))
          g4 = TL.draw(g3, pen, f32_of(ax), shifted(ay, one), f32_of(bx), shifted(by, one))
          TL.draw(g4, pen, f32_of(ax), shifted(ay, minus), f32_of(bx), shifted(by, minus))

def draw_points(pts: List<&2, TW.DPoint>, g: GR.Grid, +prev: TW.DPoint) -> GR.Grid:
  match pts:
    case Nil{}:
      g
    case Con{+p, rest}:
      draw_points(rest, draw_pair(g, prev, p), p)

# DrawVoronoiEdge(edge, IMPASSABLE) over the edge's double points.
def draw_edge(g: GR.Grid, pts: List<&2, TW.DPoint>) -> GR.Grid:
  match pts:
    case Nil{}:
      g
    case Con{+p, rest}:
      draw_points(rest, g, p)

def draw_walls(ws: List<&2, List<&2, TW.DPoint>>, g: GR.Grid) -> GR.Grid:
  match ws:
    case Nil{}:
      g
    case Con{+pts, rest}:
      draw_walls(rest, draw_edge(g, pts))

# SeparateIslands on the ConvertToTileMap maps.
def separate(+w: TW.World, g: GR.Grid) -> GR.Grid:
  draw_walls(walls(w), g)
