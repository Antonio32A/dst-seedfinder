import Base
import ../worldsim/grid.bend as Grid
import ../worldsim/tiles/groups.bend as TileGroups
import ../data/enums.bend as Enums
import ../data/ocean_convert.bend as OceanConvertData
import ./convert_plane.bend as ConvertPlane

# Ocean_ConvertImpassibleToWater's do_squarefill and do_groundfill (map/ocean_gen.lua), and the shared SetTile of the
# ocean passes. Both fills only write OCEAN_COASTAL onto non-land tiles, and land never changes, so the ground fill's
# reach and the set of land tiles that trigger a square fill follow from the input map. The square fill's trigger
# (an impassable or ocean tile on the ring at shallowRadius) could also see tiles an earlier square wrote, but only
# tiles that were neither land, impassable nor ocean change class that way; without such tiles the plane version is
# exact, with them the row-major Lua loop runs as written.

# SetTile(x, y, tile) with no reserve argument: the reserved flag (0x4000) is cleared.
def set_tile(+tile: U32, +cell: U32) -> U32:
  Grid.cell(tile, (Grid.flags_of(cell) .&. 49151 : U32))

def coastal(+cell: U32) -> U32:
  set_tile(Enums.tile_ocean_coastal(), cell)

def is_waterish(+t: U32) -> Bool:
  TileGroups.is_impassable(t) || TileGroups.is_ocean(t)

def fill_class(+cell: U32) -> U32:
  +t = Grid.tile_of(cell)
  +land = TileGroups.is_land(t)
  +near = is_waterish(t)
  (Bool.to_u32(land) .|. (Bool.to_u32(near) << 1n) .|. (Bool.to_u32(Bool.not(land || near)) << 2n) : U32)

def land() -> U32:
  0

def near() -> U32:
  1

def other() -> U32:
  2

def east_by(+s: U32) -> ConvertPlane.Shift:
  ConvertPlane.Shift{s, False{}, 0}

def west_by(+s: U32) -> ConvertPlane.Shift:
  ConvertPlane.Shift{s, True{}, 0}

def south_by(+d: U32) -> ConvertPlane.Shift:
  ConvertPlane.Shift{0, False{}, d}

def north_by(+d: U32) -> ConvertPlane.Shift:
  ConvertPlane.Shift{0, False{}, (0 - d : U32)}

def slot(+g: ConvertPlane.Geo, +k: U32) -> U32:
  ConvertPlane.base(g, k)

# dst = cells whose ring at distance r (the square's border) holds a src cell (dst, t1, t2 distinct from src).
def ring(a: Array<U32>, +g: ConvertPlane.Geo, +dst: U32, +src: U32, +t1: U32, +t2: U32, +r: U32) -> Array<U32>:
  rows = ConvertPlane.hwindow(a, g, t1, src, r)
  top = ConvertPlane.or_shift(ConvertPlane.or_shift(ConvertPlane.clear(rows, g, dst), g, dst, t1, south_by(r)), g, dst, t1, north_by(r))
  cols = ConvertPlane.vwindow(top, g, t2, src, (r - 1 : U32))
  ConvertPlane.or_shift(ConvertPlane.or_shift(cols, g, dst, t2, east_by(r)), g, dst, t2, west_by(r))

# Slot 6: the non-land cells within shallowRadius (Chebyshev) of a land cell whose ring holds an impassable or
# ocean tile (slots 4 and 5 scratch).
def square_cells(a: Array<U32>, +g: ConvertPlane.Geo) -> Array<U32>:
  +r = OceanConvertData.shallow_radius()
  +t = slot(g, 5)
  triggers = ConvertPlane.inter(ring(a, g, t, slot(g, near()), slot(g, 4), slot(g, 6), r), g, t, slot(g, land()))
  ConvertPlane.minus(ConvertPlane.square(triggers, g, slot(g, 6), t, slot(g, 4), r), g, slot(g, 6), slot(g, land()))

# dst |= src shifted by d in each of the four directions.
def step(a: Array<U32>, +g: ConvertPlane.Geo, +dst: U32, +src: U32, +d: U32) -> Array<U32>:
  horizontal = ConvertPlane.or_shift(ConvertPlane.or_shift(a, g, dst, src, east_by(d)), g, dst, src, west_by(d))
  ConvertPlane.or_shift(ConvertPlane.or_shift(horizontal, g, dst, src, south_by(d)), g, dst, src, north_by(d))

def spread(n: Nat, a: Array<U32>, +g: ConvertPlane.Geo) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      next = ConvertPlane.clear(a, g, slot(g, 5))
      reached = ConvertPlane.minus(step(next, g, slot(g, 5), slot(g, 4), OceanConvertData.fill_offset()), g, slot(g, 5), slot(g, land()))
      spread(p, ConvertPlane.union(reached, g, slot(g, 4), slot(g, 5)), g)

def ground_from(deep: Bool, a: Array<U32>, +g: ConvertPlane.Geo) -> Array<U32>:
  match deep:
    case True{}:
      first = ConvertPlane.minus(step(ConvertPlane.clear(a, g, slot(g, 4)), g, slot(g, 4), slot(g, land()), 1), g, slot(g, 4), slot(g, land()))
      spread(U32.to_nat((OceanConvertData.fill_depth() - 1 : U32)), first, g)
    case False{}:
      ConvertPlane.clear(a, g, slot(g, 4))

# Slot 4: the cells fillGroundType reaches from the 4-neighbours of every land tile, fillOffset steps through non-land
# cells, fillDepth cells deep (slot 5 scratch).
def ground_cells(a: Array<U32>, +g: ConvertPlane.Geo) -> Array<U32>:
  ground_from(U32.is_ne(OceanConvertData.fill_depth(), 0), a, g)

def in_map(+x: U32, +y: U32, +w: U32, +h: U32) -> Bool:
  (x < w : U32) && (y < h : U32)

def tile_seen(got: Array<U32> & U32, +inside: Bool) -> Array<U32> & U32:
  (cells, +v) = got
  (cells, Bool.pick(U32, inside, Grid.tile_of(v), TileGroups.invalid()))

def tile_at(cells: Array<U32>, +x: U32, +y: U32, +w: U32, +h: U32) -> Array<U32> & U32:
  tile_seen(cells[Grid.index(x, y, w)], in_map(x, y, w, h))

def on_ring(+dx: U32, +dy: U32, +r: U32) -> Bool:
  U32.is_eq(dx, 0) || U32.is_eq(dx, (2 * r : U32)) || U32.is_eq(dy, 0) || U32.is_eq(dy, (2 * r : U32))

def ring_seen(got: Array<U32> & U32, +counts: Bool, +hit: Bool) -> Array<U32> & Bool:
  (cells, +t) = got
  (cells, hit || (counts && is_waterish(t)))

def ring_go(n: Nat, got: Array<U32> & Bool, +x: U32, +y: U32, +k: U32, +r: U32, +w: U32, +h: U32) -> Array<U32> & Bool:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, +hit) = got
      +side = (2 * r + 1 : U32)
      +dx = (k % side : U32)
      +dy = (k / side : U32)
      seen = tile_at(cells, (x + dx - r : U32), (y + dy - r : U32), w, h)
      ring_go(p, ring_seen(seen, on_ring(dx, dy, r), hit), x, y, (k + 1 : U32), r, w, h)

def put_if(hit: Bool, cells: Array<U32>, +i: U32, +v: U32) -> Array<U32>:
  match hit:
    case True{}:
      cells[i] <- coastal(v)
    case False{}:
      cells

def square_cell(got: Array<U32> & U32, +inside: Bool, +i: U32) -> Array<U32>:
  (cells, +v) = got
  put_if(inside && Bool.not(TileGroups.is_land(Grid.tile_of(v))), cells, i, v)

def square_go(n: Nat, cells: Array<U32>, +x: U32, +y: U32, +k: U32, +r: U32, +w: U32, +h: U32) -> Array<U32>:
  match n:
    case 0n:
      cells
    case 1n+p:
      +side = (2 * r + 1 : U32)
      +xx = (x + (k % side) - r : U32)
      +yy = (y + (k / side) - r : U32)
      +i = Grid.index(xx, yy, w)
      square_go(p, square_cell(cells[i], in_map(xx, yy, w, h), i), x, y, (k + 1 : U32), r, w, h)

def fill_when(hit: Bool, cells: Array<U32>, +x: U32, +y: U32, +r: U32, +w: U32, +h: U32) -> Array<U32>:
  match hit:
    case True{}:
      square_go(U32.to_nat(((2 * r + 1) * (2 * r + 1) : U32)), cells, x, y, 0, r, w, h)
    case False{}:
      cells

def fill_if(got: Array<U32> & Bool, +x: U32, +y: U32, +r: U32, +w: U32, +h: U32) -> Array<U32>:
  (cells, +hit) = got
  fill_when(hit, cells, x, y, r, w, h)

def land_cell(land: Bool, cells: Array<U32>, +x: U32, +y: U32, +r: U32, +w: U32, +h: U32) -> Array<U32>:
  match land:
    case True{}:
      +n = U32.to_nat(((2 * r + 1) * (2 * r + 1) : U32))
      fill_if(ring_go(n, (cells, False{}), x, y, 0, r, w, h), x, y, r, w, h)
    case False{}:
      cells

def seq_cell(got: Array<U32> & U32, +x: U32, +y: U32, +r: U32, +w: U32, +h: U32) -> Array<U32>:
  (cells, +v) = got
  land_cell(TileGroups.is_land(Grid.tile_of(v)), cells, x, y, r, w, h)

def seq_go(n: Nat, cells: Array<U32>, +i: U32, +x: U32, +y: U32, +r: U32, +w: U32, +h: U32) -> Array<U32>:
  match n:
    case 0n:
      cells
    case 1n+p:
      next = seq_cell(cells[i], x, y, r, w, h)
      +last = U32.is_eq((x + 1 : U32), w)
      seq_go(p, next, (i + 1 : U32), Bool.pick(U32, last, 0, (x + 1 : U32)), Bool.pick(U32, last, (y + 1 : U32), y), r, w, h)

# do_squarefill as written: row-major, each land cell reading the map as the earlier squares left it.
def cells_of(g: Grid.Grid) -> Array<U32>:
  match g:
    case Grid.Grid{cells, _, _}:
      cells

def squarefill_sequential(g: Grid.Grid) -> Grid.Grid:
  match g:
    case Grid.Grid{cells, +w, +h}:
      Grid.Grid{seq_go(U32.to_nat((w * h : U32)), cells, 0, 0, 0, OceanConvertData.shallow_radius(), w, h), w, h}

def painted(got: Array<U32> & Array<U32>, +g: ConvertPlane.Geo) -> Grid.Grid:
  (_, cells) = got
  match g:
    case ConvertPlane.Geo{+w, +h, _, _}:
      Grid.Grid{cells, w, h}

def fills_route(sequential: Bool, a: Array<U32>, cells: Array<U32>, +g: ConvertPlane.Geo) -> Grid.Grid:
  match sequential:
    case True{}:
      match g:
        case ConvertPlane.Geo{+w, +h, _, _}:
          ground = ground_cells(a, g)
          painted(ConvertPlane.paint(~(c => coastal(c)), ground, cells_of(squarefill_sequential(Grid.Grid{cells, w, h})), g, slot(g, 4)), g)
    case False{}:
      both = ConvertPlane.union(ground_cells(square_cells(a, g), g), g, slot(g, 4), slot(g, 6))
      painted(ConvertPlane.paint(~(c => coastal(c)), both, cells, g, slot(g, 4)), g)

def fills_checked(got: Array<U32> & Bool, cells: Array<U32>, +g: ConvertPlane.Geo, +force_sequential: Bool) -> Grid.Grid:
  (a, +other_tiles) = got
  fills_route(force_sequential || other_tiles, a, cells, g)

def fills_classified(got: Array<U32> & Array<U32>, +g: ConvertPlane.Geo, +force_sequential: Bool) -> Grid.Grid:
  (cells, a) = got
  fills_checked(ConvertPlane.any(a, g, slot(g, other())), cells, g, force_sequential)

# do_squarefill(shallowRadius) then do_groundfill(OCEAN_COASTAL, fillOffset, fillDepth); force_sequential runs the
# square fill's row-major loop even when the planes are exact.
def fills_with(g: Grid.Grid, +force_sequential: Bool) -> Grid.Grid:
  match g:
    case Grid.Grid{cells, +w, +h}:
      +geo = ConvertPlane.geo(w, h)
      fills_classified(ConvertPlane.extract(~(c => fill_class(c)), cells, ConvertPlane.arena(geo, 8), geo, 0), geo, force_sequential)

def fills(g: Grid.Grid) -> Grid.Grid:
  fills_with(g, False{})
