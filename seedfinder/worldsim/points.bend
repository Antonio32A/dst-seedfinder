import Base
import ../rng/pcg.bend as R
import ../rng/crand.bend as CR
import ../f32/ops.bend as FO
import ../f64/repr.bend as FR
import ./grid.bend as GR
import ./tiles/groups.bend as TG
import ./tiles/table.bend as TB
import ./tiles/world.bend as TW
import ./tiles/sitetiles.bend as TT
import ../data/tile_groups.bend as TD

# The WorldSim point and tile queries of points.cpp / tiles.cpp on the committed map: every site's SitePoints list
# (SiteTiles of ConvertToTileMap's build, computed once), GetPointsForSite, ReserveSpace, GetSiteArea, GetTile, SetTile,
# ReserveTile, IsTileReserved, GetVisualTileAtPosition and ReplaceSingleNonLandTiles.

# The site point lists (packed x | y << 16, scan order) and the sites' float positions, by site index.
type Sites is Data:
  Sites{lists: TB.Tree<List<&2, U32>>, world: TW.World}

# A GetPointsForSite point: tile coordinates and the reported tile type.
type Pt is Data:
  Pt{x: U32, y: U32, t: U32}

# GetPointsForSite's result: the full list's size, the shuffled list (x | y << 10 | source index << 20) and the
# kept points in shuffled order.
type Picked is Type:
  Picked{grid: GR.Grid, rng: R.Rng, n: U32, shuffled: List<&2, U32>, kept: List<&2, Pt>}

# ReserveSpace's result: ok with the reserved square's bottom-left tile, and the candidate count.
type Reserved is Type:
  Reserved{grid: GR.Grid, rng: R.Rng, ok: Bool, x: U32, y: U32, n: U32}

def sites(+w: TW.World, +lists: List<&2, List<&2, U32>>) -> Sites:
  Sites{TB.from_list(~List<&2, U32>, lists, Nil{}), w}

def site_list(+s: Sites, +site: U32) -> List<&2, U32>:
  match s:
    case Sites{+lists, _}:
      Bool.pick(List<&2, U32>, TW.is_none(site), Nil{}, TB.at(~List<&2, U32>, lists, site))

# GetSiteArea: the size of the site's point list.
def site_area(+s: Sites, +site: U32) -> U32:
  U32.from_nat(List.length(&2, U32, site_list(s, site)))

def barren() -> U32:
  TD.tile_road()

def packed(+p: U32, +k: U32) -> U32:
  (TT.unpack_x(p) .|. (TT.unpack_y(p) << 10n) .|. (k << 20n) : U32)

def shuffled_x(+v: U32) -> U32:
  (v .&. 1023 : U32)

def shuffled_y(+v: U32) -> U32:
  ((v >> 10n) .&. 1023 : U32)

def shuffled_src(+v: U32) -> U32:
  (v >> 20n : U32)

def fill(pts: List<&2, U32>, items: Array<U32>, +k: U32) -> Array<U32>:
  match pts:
    case Nil{}:
      items
    case Con{+p, rest}:
      items[k] <- packed(p, k)
      fill(rest, items, (k + 1 : U32))

def scratch() -> Array<U32>:
  [0 : U32^11n]

def collect_loop(n: Nat, got: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      (items, _) = got
      (items, acc)
    case 1n+p:
      (items, +v) = got
      collect_loop(p, items[(i - 1 : U32)], (i - 1 : U32), v <> acc)

def collected_of(got: Array<U32> & List<&2, U32>) -> List<&2, U32>:
  (_, +xs) = got
  xs

# The first n items, in order.
def collected(items: Array<U32>, +n: U32) -> List<&2, U32>:
  collected_of(collect_loop(U32.to_nat(n), items[(n - 1 : U32)], (n - 1 : U32), Nil{}))

def shuffled_of(sh: CR.Shuffled, +n: U32) -> List<&2, U32> & R.Rng:
  match sh:
    case CR.Shuffled{items, s}:
      (collected(items, n), s)

def shuffled_list(+windows: Bool, +pts: List<&2, U32>, +n: U32, rng: R.Rng) -> List<&2, U32> & R.Rng:
  shuffled_of(CR.random_shuffle(windows, fill(pts, scratch(), 0), n, rng), n)

def fill_counted(pts: List<&2, U32>, items: Array<U32>, +k: U32) -> Array<U32> & U32:
  match pts:
    case Nil{}:
      (items, k)
    case Con{+p, rest}:
      items[k] <- packed(p, k)
      fill_counted(rest, items, (k + 1 : U32))

def shuffled_filled(+windows: Bool, got: Array<U32> & U32, rng: R.Rng) -> (List<&2, U32> & R.Rng) & U32:
  (items, +n) = got
  (shuffled_of(CR.random_shuffle(windows, items, n, rng), n), n)

def in_bounds(+x: U32, +y: U32, +w: U32, +h: U32) -> Bool:
  (x < w : U32) && (y < h : U32)

def is_reserved(+cell: U32) -> Bool:
  U32.is_ne((GR.flags_of(cell) .&. GR.reserved_flag() : U32), 0)

def is_marked(+cell: U32) -> Bool:
  U32.is_ne((GR.flags_of(cell) .&. (GR.reserved_flag() + GR.disconnected_flag()) : U32), 0)

def usable(+cell: U32) -> Bool:
  Bool.not(is_reserved(cell)) && Bool.not(TG.is_invalid(GR.tile_of(cell)))

def reported(+cell: U32) -> U32:
  Bool.pick(U32, is_marked(cell), barren(), GR.tile_of(cell))

def keep_point(ok: Bool, +x: U32, +y: U32, +cell: U32, acc: List<&2, Pt>) -> List<&2, Pt>:
  match ok:
    case True{}:
      Pt{x, y, reported(cell)} <> acc
    case False{}:
      acc

def point_at(inside: Bool, g: GR.Grid, +x: U32, +y: U32, +w: U32) -> GR.Grid & U32:
  match inside:
    case True{}:
      GR.get(g, GR.index(x, y, w))
    case False{}:
      (g, GR.cell(TG.invalid(), 0))

def filter_loop(pts: List<&2, U32>, got: GR.Grid & U32, +x: U32, +y: U32, +pending: Bool, +w: U32, +h: U32, acc: List<&2, Pt>) -> GR.Grid & List<&2, Pt>:
  match pts:
    case Nil{}:
      (g, +cell) = got
      (g, List.reverse(&2, Pt, keep_point(pending && usable(cell), x, y, cell, acc)))
    case Con{+v, rest}:
      (g, +cell) = got
      +vx = shuffled_x(v)
      +vy = shuffled_y(v)
      filter_loop(rest, point_at(in_bounds(vx, vy, w, h), g, vx, vy, w), vx, vy, True{}, w, h,
        keep_point(pending && usable(cell), x, y, cell, acc))

def picked_of(got: GR.Grid & List<&2, Pt>, rng: R.Rng, +n: U32, +order: List<&2, U32>) -> Picked:
  (g, +kept) = got
  Picked{g, rng, n, order, kept}

def filtered(g: GR.Grid, got: (List<&2, U32> & R.Rng) & U32) -> Picked:
  match g:
    case GR.Grid{cells, +w, +h}:
      (sh, +n) = got
      (+order, rng) = sh
      picked_of(filter_loop(order, (GR.Grid{cells, w, h}, 0), 0, 0, False{}, w, h, Nil{}), rng, n, order)

# GetPointsForSite: the site's points shuffled (n - 1 rand() calls), then those inside the map, not reserved and
# not IMPASSABLE/INVALID, typed by their tile (the barren tile when reserved or disconnected).
def points_for_site(+windows: Bool, +s: Sites, +site: U32, g: GR.Grid, rng: R.Rng) -> Picked:
  filtered(g, shuffled_filled(windows, fill_counted(site_list(s, site), scratch(), 0), rng))

# (int)x for a Lua number (lua_tointeger: truncation toward zero), as two's complement.
def lua_int(+x: FR.F64) -> U32:
  FR.to_i32(x)

def contains(+x: U32, +y: U32, +w: U32, +h: U32) -> Bool:
  (x < w : U32) && (y < h : U32)

def tile_of_got(got: GR.Grid & U32) -> GR.Grid & U32:
  (g, +cell) = got
  (g, GR.tile_of(cell))

def tile_at(inside: Bool, g: GR.Grid, +x: U32, +y: U32) -> GR.Grid & U32:
  match inside:
    case False{}:
      (g, TG.invalid())
    case True{}:
      match g:
        case GR.Grid{cells, +w, +h}:
          tile_of_got(GR.get(GR.Grid{cells, w, h}, GR.index(x, y, w)))


# GetTile(x, y) for integer coordinates (INVALID outside the map).
def get_tile(g: GR.Grid, +x: U32, +y: U32) -> GR.Grid & U32:
  match g:
    case GR.Grid{cells, +w, +h}:
      tile_at(contains(x, y, w, h), GR.Grid{cells, w, h}, x, y)

def reserve_got(got: GR.Grid & U32, +i: U32) -> GR.Grid & Bool:
  (g, +cell) = got
  +fresh = Bool.not(is_reserved(cell))
  +marked = GR.cell(GR.tile_of(cell), (GR.flags_of(cell) .|. GR.reserved_flag() : U32))
  (GR.put(g, i, Bool.pick(U32, fresh, marked, cell)), fresh)

def reserve_at(inside: Bool, g: GR.Grid, +x: U32, +y: U32) -> GR.Grid & Bool:
  match inside:
    case False{}:
      (g, False{})
    case True{}:
      match g:
        case GR.Grid{cells, +w, +h}:
          reserve_got(GR.get(GR.Grid{cells, w, h}, GR.index(x, y, w)), GR.index(x, y, w))

# ReserveTile(x, y): sets the reserved flag; true when it was clear.
def reserve_tile(g: GR.Grid, +x: U32, +y: U32) -> GR.Grid & Bool:
  match g:
    case GR.Grid{cells, +w, +h}:
      reserve_at(contains(x, y, w, h), GR.Grid{cells, w, h}, x, y)

def set_got(got: GR.Grid & U32, +i: U32, +tile: U32, +reserve: U32) -> GR.Grid:
  (g, +cell) = got
  GR.put(g, i, GR.cell(tile, ((GR.flags_of(cell) .&. 49151) .|. ((reserve .&. 1) << 14n) : U32)))

def set_at(inside: Bool, g: GR.Grid, +x: U32, +y: U32, +tile: U32, +reserve: U32) -> GR.Grid:
  match inside:
    case False{}:
      g
    case True{}:
      match g:
        case GR.Grid{cells, +w, +h}:
          set_got(GR.get(GR.Grid{cells, w, h}, GR.index(x, y, w)), GR.index(x, y, w), tile, reserve)

# SetTile(x, y, tile, reserve): the tile and the reserved flag (reserve & 1).
def set_tile(g: GR.Grid, +x: U32, +y: U32, +tile: U32, +reserve: U32) -> GR.Grid:
  match g:
    case GR.Grid{cells, +w, +h}:
      set_at(contains(x, y, w, h), GR.Grid{cells, w, h}, x, y, tile, reserve)

def reserved_got(got: GR.Grid & U32) -> GR.Grid & Bool:
  (g, +cell) = got
  (g, is_reserved(cell))

def reserved_at(inside: Bool, g: GR.Grid, +x: U32, +y: U32) -> GR.Grid & Bool:
  match inside:
    case False{}:
      (g, True{})
    case True{}:
      match g:
        case GR.Grid{cells, +w, +h}:
          reserved_got(GR.get(GR.Grid{cells, w, h}, GR.index(x, y, w)))

# IsTileReserved(x, y) (true outside the map).
def is_tile_reserved(g: GR.Grid, +x: U32, +y: U32) -> GR.Grid & Bool:
  match g:
    case GR.Grid{cells, +w, +h}:
      reserved_at(contains(x, y, w, h), GR.Grid{cells, w, h}, x, y)

def visual_offset(+frac: F32) -> U32:
  Bool.pick(U32, (frac < 0.24 : F32), 4294967295, Bool.pick(U32, (0.76 < frac : F32), 1, 0))

def visual_other(got: GR.Grid & U32, +tile: U32) -> GR.Grid & U32:
  (g, +cell) = got
  +other = GR.tile_of(cell)
  (g, Bool.pick(U32, (tile < other : U32), other, tile))

def visual_pick(impassable: Bool, g: GR.Grid, +tile: U32, +fx: F32, +fy: F32, +ix: U32, +iy: U32, +w: U32) -> GR.Grid & U32:
  match impassable:
    case False{}:
      (g, tile)
    case True{}:
      +ox = visual_offset((fx - FO.from_u32(ix) : F32))
      +oy = visual_offset((fy - FO.from_u32(iy) : F32))
      visual_other(GR.get(g, (ix + ox + (iy + oy) * w : U32)), tile)

def visual_cell(got: GR.Grid & U32, +fx: F32, +fy: F32, +ix: U32, +iy: U32, +w: U32) -> GR.Grid & U32:
  (g, +cell) = got
  visual_pick(TG.is_impassable(GR.tile_of(cell)), g, GR.tile_of(cell), fx, fy, ix, iy, w)

def visual_at(g: GR.Grid, +fx: F32, +fy: F32) -> GR.Grid & U32:
  match g:
    case GR.Grid{cells, +w, +h}:
      +ix = FO.to_i32(fx)
      +iy = FO.to_i32(fy)
      visual_cell(GR.get(GR.Grid{cells, w, h}, (w * iy + ix : U32)), fx, fy, ix, iy, w)

# GetVisualTileAtPosition(x, y) for Lua numbers: the tile under ((float)x + 0.5, (float)y + 0.5), or for an
# impassable tile the larger of it and the neighbour its fractional position leans to (below 0.24 / above 0.76).
def visual_tile(g: GR.Grid, +x: FR.F64, +y: FR.F64) -> GR.Grid & U32:
  visual_at(g, (FO.from_f64(x) + 0.5 : F32), (FO.from_f64(y) + 0.5 : F32))

type Around is Data:
  Around{c: U32, l: U32, r: U32, d: U32, u: U32}

def around_u(got: GR.Grid & U32, +c: U32, +l: U32, +r: U32, +d: U32) -> GR.Grid & Around:
  (g, +u) = got
  (g, Around{c, l, r, d, u})

def around_d(got: GR.Grid & U32, +i: U32, +w: U32, +c: U32, +l: U32, +r: U32) -> GR.Grid & Around:
  (g, +d) = got
  around_u(GR.get(g, (i + w : U32)), c, l, r, d)

def around_r(got: GR.Grid & U32, +i: U32, +w: U32, +c: U32, +l: U32) -> GR.Grid & Around:
  (g, +r) = got
  around_d(GR.get(g, (i - w : U32)), i, w, c, l, r)

def around_l(got: GR.Grid & U32, +i: U32, +w: U32, +c: U32) -> GR.Grid & Around:
  (g, +l) = got
  around_r(GR.get(g, (i + 1 : U32)), i, w, c, l)

def around_c(got: GR.Grid & U32, +i: U32, +w: U32) -> GR.Grid & Around:
  (g, +c) = got
  around_l(GR.get(g, (i - 1 : U32)), i, w, c)

def land(+cell: U32) -> Bool:
  TG.is_land(GR.tile_of(cell))

def replaced(+a: Around) -> Bool:
  match a:
    case Around{+c, +l, +r, +d, +u}:
      +none = Bool.not(land(l)) && Bool.not(land(r)) && Bool.not(land(d)) && Bool.not(land(u))
      +all = land(l) && land(r) && land(d) && land(u)
      (land(c) && none) || (Bool.not(land(c)) && all)

def replace_if(hit: Bool, g: GR.Grid, +i: U32, +a: Around) -> GR.Grid:
  match hit:
    case False{}:
      g
    case True{}:
      match a:
        case Around{+c, +l, _, _, _}:
          GR.put(g, i, GR.cell(GR.tile_of(l), GR.flags_of(c)))

def replace_cell(got: GR.Grid & Around, +i: U32) -> GR.Grid:
  (g, +a) = got
  replace_if(replaced(a), g, i, a)

def replace_column(n: Nat, g: GR.Grid, +i: U32, +w: U32) -> GR.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      replace_column(p, replace_cell(around_c(GR.get(g, i), i, w), i), (i + w : U32), w)

def replace_columns(n: Nat, g: GR.Grid, +x: U32, +w: U32, +h: U32) -> GR.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      replace_columns(p, replace_column(U32.to_nat((h - 2 : U32)), g, (w + x : U32), w), (x + 1 : U32), w, h)

def replace_sized(big: Bool, g: GR.Grid) -> GR.Grid:
  match big:
    case False{}:
      g
    case True{}:
      match g:
        case GR.Grid{cells, +w, +h}:
          replace_columns(U32.to_nat((w - 2 : U32)), GR.Grid{cells, w, h}, 1, w, h)

# ReplaceSingleNonLandTiles: x outer, y inner over the interior, in place, a land tile with no land neighbour or a
# non-land tile with four land neighbours takes its left neighbour's tile.
def replace_single_non_land(g: GR.Grid) -> GR.Grid:
  match g:
    case GR.Grid{cells, +w, +h}:
      replace_sized((w >= 3 : U32), GR.Grid{cells, w, h})

type Try is Type:
  Try{grid: GR.Grid, done: Bool, x: U32, y: U32}

# A ReserveSpace request: size (float), start and fill masks.
type Ask is Data:
  Ask{size: F32, start: U32, fill: U32}

def negative(+v: U32) -> Bool:
  (v >= 2147483648 : U32)

def at_most_zero(+v: U32) -> Bool:
  U32.is_zero(v) || negative(v)

def at_least(+v: U32, +bound: U32) -> Bool:
  Bool.not(negative(v)) && (v >= bound : U32)

def corner(+c: U32, +size: F32) -> U32:
  FO.to_i32(FO.floor(((FO.from_u32(c) - size) + 0.5 : F32)))

def far_corner(+c: U32, +size: F32) -> U32:
  FO.to_i32(FO.floor(((FO.from_u32(c) + size) + 0.5 : F32)))

def blocks(+cell: U32, +fill: U32) -> Bool:
  +invalid = U32.is_zero((fill .&. 1 : U32)) && TG.is_invalid(GR.tile_of(cell))
  +disconnected = U32.is_zero((fill .&. 2 : U32)) && U32.is_ne((GR.flags_of(cell) .&. GR.disconnected_flag() : U32), 0)
  invalid || disconnected || (U32.is_zero((fill .&. 4 : U32)) && is_reserved(cell))

def free_cell(got: GR.Grid & U32, +fill: U32) -> GR.Grid & Bool:
  (g, +cell) = got
  (g, Bool.not(blocks(cell, fill)))

def free_column(n: Nat, got: GR.Grid & Bool, +i: U32, +w: U32, +fill: U32) -> GR.Grid & Bool:
  match n:
    case 0n:
      got
    case 1n+p:
      (g, +ok) = got
      match ok:
        case False{}:
          (g, False{})
        case True{}:
          free_column(p, free_cell(GR.get(g, i), fill), (i + w : U32), w, fill)

def free_columns(n: Nat, got: GR.Grid & Bool, +i: U32, +rows: U32, +w: U32, +fill: U32) -> GR.Grid & Bool:
  match n:
    case 0n:
      got
    case 1n+p:
      (g, +ok) = got
      match ok:
        case False{}:
          (g, False{})
        case True{}:
          free_columns(p, free_column(U32.to_nat(rows), (g, True{}), i, w, fill), (i + 1 : U32), rows, w, fill)

def stamp_cell(got: GR.Grid & U32, +i: U32, +ground: U32) -> GR.Grid:
  (g, +cell) = got
  +tile = Bool.pick(U32, U32.is_zero(ground), GR.tile_of(cell), ground)
  GR.put(g, i, GR.cell(tile, (GR.flags_of(cell) .|. GR.reserved_flag() : U32)))

def head_or_zero(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{+x, _}:
      x

def stamp_column(n: Nat, got: GR.Grid & List<&2, U32>, +i: U32, +w: U32) -> GR.Grid & List<&2, U32>:
  match n:
    case 0n:
      got
    case 1n+p:
      (g, +ground) = got
      stamp_column(p, (stamp_cell(GR.get(g, i), i, head_or_zero(ground)), List.drop(&2, U32, ground, 1n)), (i + w : U32), w)

def stamp_columns(n: Nat, got: GR.Grid & List<&2, U32>, +i: U32, +rows: U32, +w: U32) -> GR.Grid:
  match n:
    case 0n:
      (g, _) = got
      g
    case 1n+p:
      stamp_columns(p, stamp_column(U32.to_nat(rows), got, i, w), (i + 1 : U32), rows, w)

type Square is Data:
  Square{x0: U32, x1: U32, y0: U32, y1: U32}

def square_of(+v: U32, +size: F32) -> Square:
  +x = shuffled_x(v)
  +y = shuffled_y(v)
  Square{corner(x, size), far_corner(x, size), corner(y, size), far_corner(y, size)}

def outside(+q: Square, +w: U32, +h: U32) -> Bool:
  match q:
    case Square{+x0, +x1, +y0, +y1}:
      at_most_zero(x0) || at_least(x1, (w - 1 : U32)) || at_most_zero(y0) || at_least(y1, (h - 1 : U32))

def stamp_if(free: Bool, g: GR.Grid, +q: Square, +w: U32, +ground: List<&2, U32>) -> Try:
  match free:
    case False{}:
      Try{g, False{}, 0, 0}
    case True{}:
      match q:
        case Square{+x0, +x1, +y0, +y1}:
          Try{stamp_columns(U32.to_nat((x1 - x0 : U32)), (g, ground), GR.index(x0, y0, w), (y1 - y0 : U32), w), True{}, x0, y0}

def stamped(got: GR.Grid & Bool, +q: Square, +w: U32, +ground: List<&2, U32>) -> Try:
  (g, +free) = got
  stamp_if(free, g, q, w, ground)

def claim(nonempty: Bool, g: GR.Grid, +q: Square, +ask: Ask, +ground: List<&2, U32>) -> Try:
  match nonempty:
    case False{}:
      match q:
        case Square{+x0, _, +y0, _}:
          Try{g, True{}, x0, y0}
    case True{}:
      match g:
        case GR.Grid{cells, +w, +h}:
          match q:
            case Square{+x0, +x1, +y0, +y1}:
              match ask:
                case Ask{_, _, +fill}:
                  stamped(free_columns(U32.to_nat((x1 - x0 : U32)), (GR.Grid{cells, w, h}, True{}), GR.index(x0, y0, w), (y1 - y0 : U32), w, fill),
                    Square{x0, x1, y0, y1}, w, ground)

def place_square(skip: Bool, g: GR.Grid, +q: Square, +ask: Ask, +ground: List<&2, U32>) -> Try:
  match skip:
    case True{}:
      Try{g, False{}, 0, 0}
    case False{}:
      match q:
        case Square{+x0, +x1, +y0, +y1}:
          claim((x0 < x1 : U32), g, Square{x0, x1, y0, y1}, ask, ground)

def start_ok(got: GR.Grid & U32, +ask: Ask) -> GR.Grid & Bool:
  (g, +cell) = got
  match ask:
    case Ask{_, +start, _}:
      (g, U32.is_ne((start .&. 1 : U32), 0) || Bool.not(TG.is_invalid(GR.tile_of(cell))))

def candidate_checked(ok: Bool, g: GR.Grid, +v: U32, +ask: Ask, +ground: List<&2, U32>) -> Try:
  match ok:
    case False{}:
      Try{g, False{}, 0, 0}
    case True{}:
      match g:
        case GR.Grid{cells, +w, +h}:
          match ask:
            case Ask{+size, +start, +fill}:
              +q = square_of(v, size)
              place_square(outside(q, w, h), GR.Grid{cells, w, h}, q, Ask{size, start, fill}, ground)

def candidate_started(got: GR.Grid & Bool, +v: U32, +ask: Ask, +ground: List<&2, U32>) -> Try:
  (g, +ok) = got
  candidate_checked(ok, g, v, ask, ground)

def candidate(g: GR.Grid, +v: U32, +ask: Ask, +ground: List<&2, U32>) -> Try:
  match g:
    case GR.Grid{cells, +w, +h}:
      candidate_started(start_ok(GR.get(GR.Grid{cells, w, h}, GR.index(shuffled_x(v), shuffled_y(v), w)), ask), v, ask, ground)

def reserve_loop(cands: List<&2, U32>, t: Try, +ask: Ask, +ground: List<&2, U32>) -> Try:
  match cands:
    case Nil{}:
      t
    case Con{+v, rest}:
      match t:
        case Try{g, +done, +x, +y}:
          match done:
            case True{}:
              Try{g, True{}, x, y}
            case False{}:
              reserve_loop(rest, candidate(g, v, ask, ground), ask, ground)

def centre_of(pts: List<&2, U32>, +sx: U32, +sy: U32) -> List<&2, U32>:
  match pts:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      Bool.pick(List<&2, U32>, U32.is_eq(TT.unpack_x(p), sx) && U32.is_eq(TT.unpack_y(p), sy), [p], centre_of(rest, sx, sy))

def centre_in(+t: TW.Site, +pts: List<&2, U32>) -> List<&2, U32>:
  match t:
    case TW.Site{_, +x, +y, _, _, _}:
      centre_of(pts, FO.to_i32(x), FO.to_i32(y))

def candidates(centre: Bool, +s: Sites, +site: U32) -> List<&2, U32>:
  match centre:
    case False{}:
      site_list(s, site)
    case True{}:
      match s:
        case Sites{_, +w}:
          centre_in(TW.site(w, site), site_list(s, site))

def reserved_of(t: Try, rng: R.Rng, +n: U32) -> Reserved:
  match t:
    case Try{g, +ok, +x, +y}:
      Reserved{g, rng, ok, x, y, n}

def reserve_shuffled(got: List<&2, U32> & R.Rng, g: GR.Grid, +ask: Ask, +ground: List<&2, U32>, +n: U32) -> Reserved:
  (+order, rng) = got
  reserved_of(reserve_loop(order, Try{g, False{}, 0, 0}, ask, ground), rng, n)

# ReserveSpace(node, size, start_mask, fill_mask, layout_position, ground): the site's points (only the one on the
# site's own tile for LAYOUT_POSITION.CENTER) shuffled (n - 1 rand() calls), then the first whose square
# [floor(c - size + 0.5), floor(c + size + 0.5)) lies strictly inside the map, starts on a valid tile (start_mask 1
# skips that) and is free (fill_mask 1/2/4 allow invalid, disconnected, reserved tiles) is reserved and painted with
# the ground tiles (x outer, y inner; 0 keeps the tile). `n` is the site's full point count.
def reserve_space(+windows: Bool, +s: Sites, +site: U32, +ask: Ask, +position: U32, +ground: List<&2, U32>, g: GR.Grid, rng: R.Rng) -> Reserved:
  +cands = candidates(U32.is_eq(position, 1), s, site)
  +count = U32.from_nat(List.length(&2, U32, cands))
  reserve_shuffled(shuffled_list(windows, cands, count, rng), g, ask, ground, site_area(s, site))
