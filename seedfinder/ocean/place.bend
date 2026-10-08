import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../lua/util.bend as LuaUtil
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../data/blob.bend as Blob
import ../data/layouts.bend as Layouts
import ../data/ocean_post.bend as OceanPostData
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../populate/entities.bend as Entities
import ../populate/layout.bend as PopulateLayout
import ../populate/place.bend as PopulatePlace
import ../populate/counts.bend as PopulateCounts
import ../populate/setpiece.bend as PopulateSetpiece
import ./ents.bend as OceanEnts
import ./state.bend as OceanState

# ocean_gen.lua's Ocean_PlaceSetPieces: every set piece's entity list (in pairs() order, its count after it), the
# shuffled placement list, and per piece PlaceOceanLayout: findLayoutPositions' wrapped scan, the random pick,
# ReserveAndPlaceLayout("POSITIONED") (transform, ground tiles, entities without offsets), AddSquareTopology and the
# reserved box.

# A set piece table entry: layout index and its count (kind 0 an integer, 1 a closure id).
type Spec is Data:
  Spec{layout: U32, kind: U32, value: U32}

type Piece is Data:
  Piece{v: U32, source: U32, items: List<&2, PopulateLayout.Item>}

def none() -> U32:
  4294967295

def copies(n: Nat, +p: Piece, acc: List<&2, Piece>) -> List<&2, Piece>:
  match n:
    case 0n:
      acc
    case 1n+k:
      copies(k, p, p <> acc)

def counted(got: U32 & Pcg.Rng, +p: Piece, +acc: List<&2, Piece>) -> List<&2, Piece> & Pcg.Rng:
  (+count, rng) = got
  (copies(U32.to_nat(count), p, acc), rng)

def converted(got: List<&2, PopulateLayout.Item> & Pcg.Rng, +v: U32, +source: U32, +kind: U32, +value: U32, +width: U32, +acc: List<&2, Piece>) -> List<&2, Piece> & Pcg.Rng:
  (+items, rng) = got
  counted(PopulateCounts.value_of(kind, value, 0, width, rng), Piece{v, source, items}, acc)

def collect_loop(specs: List<&2, Spec>, +c: OceanState.Ctx, +source: U32, got: List<&2, Piece> & Pcg.Rng) -> List<&2, Piece> & Pcg.Rng:
  match specs:
    case Nil{}:
      (+acc, rng) = got
      (List.reverse(&2, Piece, acc), rng)
    case Con{Spec{+layout, +kind, +value}, rest}:
      (+acc, rng) = got
      +swaps = OceanState.swaps_of(c)
      collect_loop(rest, c, source, converted(PopulateLayout.convert(swaps, layout, rng), Layouts.variant(layout, swaps), source, kind, value, OceanState.width_of(c), acc))

def fill_order(n: Nat, items: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      items[i] <- none()
    case 1n+p:
      items[i] <- i
      fill_order(p, items, (i + 1 : U32))

def order_loop(n: Nat, got: Array<U32> & U32, +i: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, acc)
    case 1n+p:
      (items, +v) = got
      order_loop(p, items[(i + 1 : U32)], (i + 1 : U32), v <> acc)

def until_none(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+v, rest}:
      Bool.pick(List<&2, U32>, U32.is_eq(v, none()), Nil{}, v <> until_none(rest))

def shuffled_order(sh: LuaUtil.Shuffled, +n: U32) -> List<&2, U32> & Pcg.Rng:
  match sh:
    case LuaUtil.Shuffled{items, rng}:
      (until_none(order_loop(U32.to_nat(n), items[0], 0, Nil{})), rng)

# shuffleArray over n pieces: the order of their indices (ipairs stops at a nil a 2^32 - 1 draw leaves).
def shuffle(+n: U32, rng: Pcg.Rng) -> List<&2, U32> & Pcg.Rng:
  shuffled_order(LuaUtil.shuffle_array(fill_order(U32.to_nat(n), [0 : U32^7n], 0), n, rng), n)

# Where findLayoutPositions scans: the start, the wrapped extents, the box size, the land distance and the tile.
type Scan is Data:
  Scan{sx: U32, sy: U32, w: U32, h: U32, size: U32, m: U32, tile: U32, edge: U32, cols: Nat, span: Nat}

def cell_ok(got: Grid.Grid & U32, +tile: U32) -> Grid.Grid & Bool:
  (g, +cell) = got
  (g, Bool.not(Points.is_reserved(cell)) && U32.is_eq(Grid.tile_of(cell), tile))

def check_at(inside: Bool, g: Grid.Grid, +x: U32, +y: U32, +tile: U32) -> Grid.Grid & Bool:
  match inside:
    case False{}:
      (g, False{})
    case True{}:
      match g:
        case Grid.Grid{cells, +w, +h}:
          cell_ok(Grid.get(Grid.Grid{cells, w, h}, Grid.index(x, y, w)), tile)

# checkTile: not reserved and the populating tile (false outside the map).
def check(g: Grid.Grid, +x: U32, +y: U32, +tile: U32) -> Grid.Grid & Bool:
  match g:
    case Grid.Grid{cells, +w, +h}:
      check_at(Points.contains(x, y, w, h), Grid.Grid{cells, w, h}, x, y, tile)

def both_second(got: Grid.Grid & Bool, +first: Bool) -> Grid.Grid & Bool:
  (g, +second) = got
  (g, first && second)

def both_first(got: Grid.Grid & Bool, +x2: U32, +y2: U32, +tile: U32) -> Grid.Grid & Bool:
  (g, +first) = got
  both_second(check(g, x2, y2, tile), first)

def check_two(g: Grid.Grid, +x1: U32, +y1: U32, +x2: U32, +y2: U32, +tile: U32) -> Grid.Grid & Bool:
  both_first(check(g, x1, y1, tile), x2, y2, tile)

# A scan in progress: the grid, the position index, the result (NONE until found) and whether to go on.
type Walk is Type:
  Walk{g: Grid.Grid, i: U32, found: U32, go: Bool}

def cell_walk(got: Grid.Grid & Bool, +x: U32) -> Walk:
  (g, +ok) = got
  Walk{g, (x + 1 : U32), Bool.pick(U32, ok, none(), x), ok}

def all_cols(n: Nat, w: Walk, +y: U32, +tile: U32) -> Walk:
  match n:
    case 0n:
      w
    case 1n+p:
      match w:
        case Walk{g, +x, +found, +go}:
          match go:
            case False{}:
              Walk{g, x, found, go}
            case True{}:
              all_cols(p, cell_walk(check(g, x, y, tile), x), y, tile)

type Box is Data:
  Box{x1: U32, y1: U32, x2: U32, y2: U32}

def row_walk(w: Walk, +y: U32) -> Walk:
  match w:
    case Walk{g, _, +found, +go}:
      Walk{g, (y + 1 : U32), found, go}

def all_rows(n: Nat, w: Walk, +b: Box, +tile: U32, +span: Nat) -> Walk:
  match n:
    case 0n:
      w
    case 1n+p:
      match w:
        case Walk{g, +y, +found, +go}:
          match go:
            case False{}:
              Walk{g, y, found, go}
            case True{}:
              match b:
                case Box{+x1, +y1, +x2, +y2}:
                  cols = all_cols(span, Walk{g, x1, none(), True{}}, y, tile)
                  all_rows(p, row_walk(cols, y), Box{x1, y1, x2, y2}, tile, span)

def all_done(w: Walk) -> Grid.Grid & U32:
  match w:
    case Walk{g, _, +found, _}:
      (g, found)

# checkAllTiles over the span x span box (rows outer): the x of the first failing tile, NONE when all pass.
def check_all(g: Grid.Grid, +b: Box, +tile: U32, +span: Nat) -> Grid.Grid & U32:
  match b:
    case Box{+x1, +y1, +x2, +y2}:
      all_done(all_rows(span, Walk{g, y1, none(), True{}}, Box{x1, y1, x2, y2}, tile, span))

def x_of(+s: Scan, +i: U32) -> U32:
  match s:
    case Scan{+sx, _, +w, _, _, _, _, +edge, _, _}:
      (((sx + i) % w) + edge : U32)

def advanced(g: Grid.Grid, +i: U32, +s: Scan) -> Walk:
  match s:
    case Scan{_, _, +w, _, _, _, _, _, _, _}:
      Walk{g, i, none(), (i < w : U32)}

def clamped(+v: U32, +lo: U32, +hi: U32) -> U32:
  Bool.pick(U32, (v <= lo : U32), lo, Bool.pick(U32, (v >= hi : U32), hi, v))

def full_result(clean: Bool, g: Grid.Grid, +bad: U32, +i: U32, +s: Scan, +x: U32) -> Walk:
  match clean:
    case True{}:
      Walk{g, i, x, False{}}
    case False{}:
      match s:
        case Scan{_, _, _, _, +size, _, _, _, _, _}:
          +skip = (clamped(bad, x, (x + size - 1 : U32)) - x + 1 : U32)
          advanced(g, (i + skip : U32), s)

def after_full(got: Grid.Grid & U32, +i: U32, +s: Scan, +x: U32) -> Walk:
  (g, +bad) = got
  full_result(U32.is_eq(bad, none()), g, bad, i, s, x)

def box_of(+s: Scan, +x: U32, +y: U32) -> Box:
  match s:
    case Scan{_, _, _, _, +size, +m, _, _, _, _}:
      Box{(x - m : U32), (y - m : U32), (x + size - 1 + m : U32), (y + size - 1 + m : U32)}

def corner_b(got: Grid.Grid & Bool, +i: U32, +s: Scan, +x: U32, +y: U32) -> Walk:
  (g, +ok) = got
  match ok:
    case False{}:
      advanced(g, (i + 1 : U32), s)
    case True{}:
      match s:
        case Scan{_, _, _, _, _, _, +tile, _, _, +span}:
          after_full(check_all(g, box_of(s, x, y), tile, span), i, s, x)

def size_of(+s: Scan) -> U32:
  match s:
    case Scan{_, _, _, _, +size, _, _, _, _, _}:
      size

def corner_a(got: Grid.Grid & Bool, +i: U32, +s: Scan, +x: U32, +y: U32) -> Walk:
  (g, +ok) = got
  match ok:
    case False{}:
      advanced(g, (i + size_of(s) + 1 : U32), s)
    case True{}:
      match s:
        case Scan{_, _, _, _, +size, +m, +tile, _, _, _}:
          corner_b(check_two(g, (x - m : U32), (y - m : U32), (x - m : U32), (y + size - 1 + m : U32), tile), i, s, x, y)

def col_step(g: Grid.Grid, +i: U32, +s: Scan, +y: U32) -> Walk:
  match s:
    case Scan{_, _, _, _, +size, +m, +tile, _, _, _}:
      +x = x_of(s, i)
      +x2 = (x + size - 1 + m : U32)
      corner_a(check_two(g, x2, (y - m : U32), x2, (y + size - 1 + m : U32), tile), i, s, x, y)

def cols(n: Nat, w: Walk, +s: Scan, +y: U32) -> Walk:
  match n:
    case 0n:
      w
    case 1n+p:
      match w:
        case Walk{g, +i, +found, +go}:
          match go:
            case False{}:
              Walk{g, i, found, go}
            case True{}:
              cols(p, col_step(g, i, s, y), s, y)

def y_of(+s: Scan, +j: U32) -> U32:
  match s:
    case Scan{_, +sy, _, +h, _, _, _, +edge, _, _}:
      (((sy + j) % h) + edge : U32)

# A row scan result: the grid, the next row index, the found position (x, y; NONE) and whether to go on.
type Rows is Type:
  Rows{g: Grid.Grid, j: U32, x: U32, y: U32, go: Bool}

def row_found(w: Walk, +s: Scan, +j: U32, +y: U32) -> Rows:
  match w:
    case Walk{g, _, +found, _}:
      match s:
        case Scan{_, _, _, +h, _, _, _, _, _, _}:
          +hit = U32.is_ne(found, none())
          Rows{g, (j + 1 : U32), found, Bool.pick(U32, hit, y, none()), Bool.not(hit) && ((j + 1 : U32) < h : U32)}

def row_step(g: Grid.Grid, +s: Scan, +j: U32) -> Rows:
  match s:
    case Scan{_, _, +w, _, _, _, _, _, +fuel, _}:
      +y = y_of(s, j)
      row_found(cols(fuel, Walk{g, 0, none(), (0 < w : U32)}, s, y), s, j, y)

def rows(n: Nat, r: Rows, +s: Scan) -> Rows:
  match n:
    case 0n:
      r
    case 1n+p:
      match r:
        case Rows{g, +j, +x, +y, +go}:
          match go:
            case False{}:
              Rows{g, j, x, y, go}
            case True{}:
              rows(p, row_step(g, s, j), s)

# The first position findLayoutPositions finds for a size x size box (count 1), after its two start draws.
type Found is Type:
  Found{g: Grid.Grid, x: U32, y: U32, rng: Pcg.Rng}

def found_of(r: Rows, rng: Pcg.Rng) -> Found:
  match r:
    case Rows{g, _, +x, +y, _}:
      Found{g, x, y, rng}

def scan_from_y(got: U32 & Pcg.Rng, g: Grid.Grid, +sx: U32, +w: U32, +h: U32, +size: U32, +m: U32, +tile: U32, +edge: U32) -> Found:
  (+sy, rng) = got
  +s = {Scan{sx, sy, w, h, size, m, tile, edge, U32.to_nat((w + 1 : U32)), U32.to_nat((size + 2 * m : U32))} : Scan}
  found_of(rows(U32.to_nat(h), Rows{g, 0, none(), none(), (0 < h : U32)}, s), rng)

def scan_from_x(got: U32 & Pcg.Rng, g: Grid.Grid, +w: U32, +h: U32, +size: U32, +m: U32, +tile: U32, +edge: U32) -> Found:
  (+sx, rng) = got
  scan_from_y(MathRandom.random_range(rng, 0, h), g, sx, w, h, size, m, tile, edge)

# findLayoutPositions(size, OCEAN_WATERFALL_MAX_DIST + 2, tile, 1, m) on a width x height map.
def find_position(g: Grid.Grid, +width: U32, +height: U32, +size: U32, +m: U32, +tile: U32, rng: Pcg.Rng) -> Found:
  +edge = (OceanPostData.ocean_waterfall_max_dist() + 2 : U32)
  +w = (width - 2 * edge - size : U32)
  +h = (height - 2 * edge - size : U32)
  scan_from_x(MathRandom.random_range(rng, 0, w), g, w, h, size, m, tile, edge)

def item_bounds(+items: List<&2, PopulateLayout.Item>) -> PopulatePlace.Box:
  PopulatePlace.bounds(items, PopulatePlace.Box{PopulatePlace.million(), F64Repr.neg(PopulatePlace.million()), PopulatePlace.million(), F64Repr.neg(PopulatePlace.million())})

def extent_size(+b: PopulatePlace.Box, +scale: F64Repr.F64) -> U32:
  match b:
    case PopulatePlace.Box{+xmin, +xmax, +ymin, +ymax}:
      +ew = F64Arith.sub(xmax, xmin)
      +eh = F64Arith.sub(ymax, ymin)
      F64Repr.to_i32(F64Repr.ceil(F64Arith.mul(scale, F64Repr.pick(F64Cmp.gt(eh, ew), eh, ew))))

# GetLayoutSize: the ground's side (at least 2), else ceil(scale * the larger entity extent).
def layout_size(+v: U32, +items: List<&2, PopulateLayout.Item>) -> U32:
  +n = Layouts.ground_size(v)
  Bool.pick(U32, U32.is_zero(n), extent_size(item_bounds(items), PopulatePlace.scale_of(Layouts.scale(v))), Bool.pick(U32, (n < 2 : U32), 2, n))

# The piece's min_dist_from_land, else the caller's.
def land_distance(+v: U32, +fallback: U32) -> U32:
  +m = Layouts.min_dist_from_land(v)
  Bool.pick(U32, Blob.is_none(m), fallback, m)

def positioned(+t: PopulatePlace.Turn) -> PopulatePlace.Turn:
  match t:
    case PopulatePlace.Turn{+switch, +fx, +fy}:
      PopulatePlace.Turn{switch, Bool.not(fx), Bool.not(fy)}

def ground_set(on: Bool, g: Grid.Grid, +x: U32, +y: U32, +tile: U32) -> Grid.Grid:
  match on:
    case False{}:
      g
    case True{}:
      Points.set_tile(g, x, y, tile, 1)

def ground_cells(cells: List<&2, U32>, g: Grid.Grid, +n: U32, +x: U32, +y: U32, +q: U32) -> Grid.Grid:
  match cells:
    case Nil{}:
      g
    case Con{+tile, rest}:
      +column = (q / n : U32)
      +row = (q % n : U32)
      ground_cells(rest, ground_set(U32.is_ne(tile, 0), g, (x + column + 1 : U32), (y + row + 1 : U32), tile), n, x, y, (q + 1 : U32))

# The layout's ground tiles at position + (column, row), 1-based, reserved (SetTile(x, y, tile, 1)).
def ground(g: Grid.Grid, +v: U32, +t: PopulatePlace.Turn, +x: U32, +y: U32) -> Grid.Grid:
  ground_cells(PopulatePlace.ground(v, t), g, Layouts.ground_size(v), x, y, 0)

# Where the entities go: rcx, rcy (position + size + 0.5), the transform and the scale.
type Frame is Data:
  Frame{cx: F64Repr.F64, cy: F64Repr.F64, turn: PopulatePlace.Turn, scale: F64Repr.F64}

def entity_added(got: Grid.Grid & Bool, +c: OceanState.Ctx, +e: Entities.Ent, +piece: U32, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (g, _) = got
  match e:
    case Entities.Ent{+prefab, +tx, +ty, +x, +z, _, _, +rng}:
      OceanState.noted(c, OceanState.Sea{g, ids, rng, OceanEnts.Ent{prefab, x, z, 0, 0, piece} <> ents, topo, events}, OceanState.EAdd{prefab, tx, ty, x, z, rng})

# The ocean phase's entity adds without offsets (forest_map's add_fn, PopulateWorld_AddEntity with rand_offset
# false): ReserveTile at the integer tile, then x = floor((tx - width / 2) * 4 * 100) / 100 and the same for z; the
# entity is a member of set piece `piece` (0 none).
def add_fixed(+c: OceanState.Ctx, +prefab: U32, +px: F64Repr.F64, +py: F64Repr.F64, +piece: U32, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      +e = Entities.entity(prefab, px, py, OceanState.width_of(c), OceanState.height_of(c), False{}, rng)
      entity_added(Points.reserve_tile(g, Points.lua_int(px), Points.lua_int(py)), c, e, piece, ids, ents, topo, events)

def place_items(items: List<&2, PopulateLayout.Item>, +f: Frame, +c: OceanState.Ctx, +piece: U32, s: OceanState.Sea) -> OceanState.Sea:
  match items:
    case Nil{}:
      s
    case Con{+i, rest}:
      match f:
        case Frame{+cx, +cy, +t, +scale}:
          +px = F64Arith.add(cx, F64Arith.mul(PopulatePlace.item_x(t, i), scale))
          +py = F64Arith.add(cy, F64Arith.mul(PopulatePlace.item_y(t, i), scale))
          place_items(rest, Frame{cx, cy, t, scale}, c, piece, add_fixed(c, PopulatePlace.item_prefab(i), px, py, piece, s))

def piece_number(on: Bool, +events: List<&2, OceanState.Ev>) -> U32:
  match on:
    case False{}:
      0
    case True{}:
      (OceanState.piece_count(events) + 1 : U32)

def turned_layout(got: PopulatePlace.Turn & Pcg.Rng, +c: OceanState.Ctx, +v: U32, +source: U32, +items: List<&2, PopulateLayout.Item>, +x: U32, +y: U32, g: Grid.Grid, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (+turn, +rng) = got
  +t = positioned(turn)
  +scale = PopulatePlace.scale_of(Layouts.scale(v))
  +size = PopulatePlace.ground_size(v, F64Arith.mul(scale, PopulatePlace.half_extent(item_bounds(items))))
  +cx = F64Arith.add(F64Arith.add(F64Repr.from_u32(x), size), F64Repr.half())
  +cy = F64Arith.add(F64Arith.add(F64Repr.from_u32(y), size), F64Repr.half())
  +on = OceanState.pieces_of(c)
  s = place_items(items, Frame{cx, cy, t, scale}, c, piece_number(on, events), OceanState.Sea{ground(g, v, t, x, y), ids, rng, ents, topo, events})
  OceanState.noted_if(on, s, OceanState.EPiece{PopulateSetpiece.Piece{Layouts.name(v), source, PopulatePlace.turn_bits(t), cx, cy, size, 0, 0}})

# ReserveAndPlaceLayout("POSITIONED", layout, prefabs, add_fn, {x, y}): the transform draws (flips negated for a
# position), the ground tiles, then every entity at rcx + x * scale, rcy + y * scale.
def place_layout(+c: OceanState.Ctx, +v: U32, +source: U32, +items: List<&2, PopulateLayout.Item>, +x: U32, +y: U32, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      turned_layout(PopulatePlace.turn(Layouts.has(v, Layouts.flag_disable_transform()), rng), c, v, source, items, x, y, g, ids, ents, topo, events)

def id_put(got: Grid.Grid & U32, +i: U32, +id: U32) -> Grid.Grid:
  (g, _) = got
  Grid.put(g, i, id)

def id_at(inside: Bool, g: Grid.Grid, +x: U32, +y: U32, +id: U32) -> Grid.Grid:
  match inside:
    case False{}:
      g
    case True{}:
      match g:
        case Grid.Grid{cells, +w, +h}:
          id_put(Grid.get(Grid.Grid{cells, w, h}, Grid.index(x, y, w)), Grid.index(x, y, w), id)

# SetTileNodeId(x, y, id) on the node-id map (ignored outside it).
def set_node_id(g: Grid.Grid, +x: U32, +y: U32, +id: U32) -> Grid.Grid:
  match g:
    case Grid.Grid{cells, +w, +h}:
      id_at(Points.contains(x, y, w, h), Grid.Grid{cells, w, h}, x, y, id)

def id_rows(n: Nat, g: Grid.Grid, +x: U32, +y: U32, +id: U32) -> Grid.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      id_rows(p, set_node_id(g, x, y, id), x, (y + 1 : U32), id)

def id_columns(n: Nat, g: Grid.Grid, +x: U32, +y: U32, +rows: U32, +id: U32) -> Grid.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      id_columns(p, id_rows(U32.to_nat(rows), g, x, y, id), (x + 1 : U32), y, rows, id)

def topology_if(on: Bool, s: OceanState.Sea, +x: U32, +y: U32, +size: U32) -> OceanState.Sea:
  match on:
    case False{}:
      s
    case True{}:
      match s:
        case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
          +id = (topo + 1 : U32)
          OceanState.Sea{g, id_columns(U32.to_nat((size + 1 : U32)), ids, x, y, (size + 1 : U32), id), rng, ents, id, events}

def reserve_rows(n: Nat, got: Grid.Grid & Bool, +x: U32, +y: U32) -> Grid.Grid:
  match n:
    case 0n:
      (g, _) = got
      g
    case 1n+p:
      (g, _) = got
      reserve_rows(p, Points.reserve_tile(g, x, y), x, (y + 1 : U32))

def reserve_columns(n: Nat, g: Grid.Grid, +x: U32, +y: U32, +size: U32) -> Grid.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      reserve_columns(p, reserve_rows(U32.to_nat(size), (g, False{}), x, y), (x + 1 : U32), y, size)

def reserve_box(s: OceanState.Sea, +x: U32, +y: U32, +size: U32) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      OceanState.Sea{reserve_columns(U32.to_nat(size), g, x, y, size), ids, rng, ents, topo, events}

def placed_at(got: U32 & Pcg.Rng, +c: OceanState.Ctx, +p: Piece, +x: U32, +y: U32, +size: U32, g: Grid.Grid, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (_, rng) = got
  match p:
    case Piece{+v, +source, +items}:
      s = place_layout(c, v, source, items, x, y, OceanState.Sea{g, ids, rng, ents, topo, events})
      reserve_box(topology_if(Layouts.has(v, Layouts.flag_topology()), s, x, y, size), x, y, size)

def place_if(missing: Bool, g: Grid.Grid, +x: U32, +y: U32, rng: Pcg.Rng, +c: OceanState.Ctx, +p: Piece, +size: U32, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  match missing:
    case True{}:
      OceanState.Sea{g, ids, rng, ents, topo, events}
    case False{}:
      placed_at(MathRandom.random_upto(rng, 1), c, p, x, y, size, g, ids, ents, topo, events)

def place_found(f: Found, +c: OceanState.Ctx, +p: Piece, +size: U32, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  match f:
    case Found{g, +x, +y, rng}:
      place_if(U32.is_eq(x, none()), g, x, y, rng, c, p, size, ids, ents, topo, events)

# PlaceOceanLayout for one piece on the populating tile.
def place_piece(+c: OceanState.Ctx, +tile: U32, +fallback: U32, +p: Piece, s: OceanState.Sea) -> OceanState.Sea:
  match p s:
    case Piece{+v, +source, +items} OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
          +size = layout_size(v, items)
          +m = land_distance(v, fallback)
          place_found(find_position(g, OceanState.width_of(c), OceanState.height_of(c), size, m, tile, rng), c, Piece{v, source, items}, size, ids, ents, topo, events)

def piece_at(+pieces: List<&2, Piece>, +i: U32) -> Piece:
  Maybe.default(&2, Piece, List.get(&2, Piece, pieces, U32.to_nat(i)), Piece{0, 0, Nil{}})

def place_all(order: List<&2, U32>, +pieces: List<&2, Piece>, +c: OceanState.Ctx, +tile: U32, +fallback: U32, s: OceanState.Sea) -> OceanState.Sea:
  match order:
    case Nil{}:
      s
    case Con{+i, rest}:
      place_all(rest, pieces, c, tile, fallback, place_piece(c, tile, fallback, piece_at(pieces, i), s))

def placed_order(got: List<&2, U32> & Pcg.Rng, +pieces: List<&2, Piece>, +c: OceanState.Ctx, +tile: U32, +fallback: U32, s: OceanState.Sea) -> OceanState.Sea:
  (+order, rng) = got
  place_all(order, pieces, c, tile, fallback, OceanState.with_rng(s, rng))

def pieces_noted(got: OceanState.Sea & Pcg.Rng, +c: OceanState.Ctx, +tile: U32, +total: U32, +before: Pcg.Rng) -> OceanState.Sea:
  (s, +after) = got
  OceanState.noted(c, s, OceanState.EPieces{tile, total, before, after})

def collected(got: List<&2, Piece> & Pcg.Rng, +c: OceanState.Ctx, +tile: U32, +fallback: U32, s: OceanState.Sea, +before: Pcg.Rng) -> OceanState.Sea:
  (+pieces, rng) = got
  +n = U32.from_nat(List.length(&2, Piece, pieces))
  pieces_noted(OceanState.rng_of(placed_order(shuffle(n, rng), pieces, c, tile, fallback, s)), c, tile, n, before)

# Ocean_PlaceSetPieces(set_pieces, add_fn, obj_layout, tile, min_dist_from_land) for the set piece table `specs`
# (from `source`, populate/setpiece.bend).
def place_set_pieces(+specs: List<&2, Spec>, +c: OceanState.Ctx, +tile: U32, +fallback: U32, +source: U32, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      collected(collect_loop(specs, c, source, (Nil{}, rng)), c, tile, fallback, OceanState.Sea{g, ids, rng, ents, topo, events}, rng)
