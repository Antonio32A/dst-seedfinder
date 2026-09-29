import Base
import ../../f32/ops.bend as F32Ops
import ../../f64/repr.bend as F64Repr
import ../grid.bend as Grid
import ./lines.bend as TileLines
import ./world.bend as TileWorld

# WorldSim:DrawCellLine and WorldSim:DrawGroundLine: DrawTileLine between two nodes' points, or between two world
# positions given as Lua numbers.

def segment(g: Grid.Grid, +pen: TileLines.Pen, p: TileWorld.Point, q: TileWorld.Point) -> Grid.Grid:
  match p:
    case TileWorld.Point{+x0, +y0}:
      match q:
        case TileWorld.Point{+x1, +y1}:
          TileLines.draw(g, pen, x0, y0, x1, y1)

def end_of(+centroid: Bool, s: TileWorld.Site) -> TileWorld.Point:
  match s:
    case TileWorld.Site{_, +x, +y, +cx, +cy, _}:
      Bool.pick(TileWorld.Point, centroid, TileWorld.Point{cx, cy}, TileWorld.Point{x, y})

# DrawCellLine(a, b, kind, tile, flag, only_invalid): from node a's point to node b's; kind 0 is the polygon centroid,
# any other kind the site position.
def draw_cell_line(g: Grid.Grid, a: TileWorld.Site, b: TileWorld.Site, +kind: U32, +pen: TileLines.Pen) -> Grid.Grid:
  segment(g, pen, end_of(U32.is_zero(kind), a), end_of(U32.is_zero(kind), b))

# DrawGroundLine(x0, y0, x1, y1, tile, flag, only_invalid): the coordinates are rounded to float first.
def draw_ground_line(g: Grid.Grid, +x0: F64Repr.F64, +y0: F64Repr.F64, +x1: F64Repr.F64, +y1: F64Repr.F64, +pen: TileLines.Pen) -> Grid.Grid:
  TileLines.draw(g, pen, F32Ops.from_f64(x0), F32Ops.from_f64(y0), F32Ops.from_f64(x1), F32Ops.from_f64(y1))
