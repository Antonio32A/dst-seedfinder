import Base
import ../../f32/ops.bend as F32Ops
import ./world.bend as TileWorld

# PolygonTilesWithinRadius (boostmap.cpp): the integer corners (x, y) of the polygon's float bounding box, x outer
# and y inner, with sqrtf((x - cx)^2 + (y - cy)^2) < radius and inside the polygon by the float winding number
# (per row, over the edges spanning it: the others add nothing).
# A tile is packed as x | y << 16.

def pack(+x: U32, +y: U32) -> U32:
  (x .|. (y << 16n) : U32)

def unpack_x(+p: U32) -> U32:
  (p .&. 65535 : U32)

def unpack_y(+p: U32) -> U32:
  (p >> 16n : U32)

def is_left(+px: F32, +py: F32, +ax: F32, +ay: F32, +bx: F32, +by: F32) -> F32:
  ((bx - ax) * (py - ay) - (px - ax) * (by - ay) : F32)

# A polygon edge that spans a scan row (ay <= py < by upward, by <= py < ay downward): the only edges the winding
# number of a point on that row can count.
type Seg is Data:
  Seg{ax: F32, ay: F32, bx: F32, by: F32, up: Bool}

def crossing(+s: Seg, +px: F32, +py: F32, +wn: U32) -> U32:
  match s:
    case Seg{+ax, +ay, +bx, +by, +up}:
      match up:
        case True{}:
          (wn + Bool.to_u32((is_left(px, py, ax, ay, bx, by) > 0.0 : F32)) : U32)
        case False{}:
          (wn - Bool.to_u32((is_left(px, py, ax, ay, bx, by) < 0.0 : F32)) : U32)

def winding(segs: List<&2, Seg>, +px: F32, +py: F32, +wn: U32) -> U32:
  match segs:
    case Nil{}:
      wn
    case Con{+s, rest}:
      winding(rest, px, py, crossing(s, px, py, wn))

def seg_keep(spans: Bool, +s: Seg, tail: List<&2, Seg>) -> List<&2, Seg>:
  match spans:
    case True{}:
      s <> tail
    case False{}:
      tail

def spanning(+py: F32, a: TileWorld.Point, b: TileWorld.Point, tail: List<&2, Seg>) -> List<&2, Seg>:
  match a:
    case TileWorld.Point{+ax, +ay}:
      match b:
        case TileWorld.Point{+bx, +by}:
          +below = (ay <= py : F32)
          +up = below && (py < by : F32)
          +down = Bool.not(below) && (by <= py : F32)
          seg_keep(up || down, Seg{ax, ay, bx, by, up}, tail)

def row_loop(poly: List<&2, TileWorld.Point>, +first: TileWorld.Point, +prev: TileWorld.Point, +py: F32) -> List<&2, Seg>:
  match poly:
    case Nil{}:
      spanning(py, prev, first, Nil{})
    case Con{+q, rest}:
      spanning(py, prev, q, row_loop(rest, first, q, py))

# The edges of the polygon (in ring order, the closing edge last) that span row py.
def row_segs(poly: List<&2, TileWorld.Point>, +py: F32) -> List<&2, Seg>:
  match poly:
    case Nil{}:
      Nil{}
    case Con{+first, rest}:
      row_loop(rest, first, first, py)

type Box is Data:
  Box{minx: F32, maxx: F32, miny: F32, maxy: F32}

def grow(b: Box, p: TileWorld.Point) -> Box:
  match b:
    case Box{+minx, +maxx, +miny, +maxy}:
      match p:
        case TileWorld.Point{+x, +y}:
          Box{Bool.pick(F32, (x < minx : F32), x, minx), Bool.pick(F32, (maxx < x : F32), x, maxx),
            Bool.pick(F32, (y < miny : F32), y, miny), Bool.pick(F32, (maxy < y : F32), y, maxy)}

def bounds(poly: List<&2, TileWorld.Point>, b: Box) -> Box:
  match poly:
    case Nil{}:
      b
    case Con{+p, rest}:
      bounds(rest, grow(b, p))

def max_float() -> F32:
  F32Ops.from_bits(2139095039)

# (uint32_t)(int64_t)v: truncation toward zero, modulo 2^32.
def trunc_wrap(+v: F32) -> U32:
  Bool.pick(U32, (v < 0.0 : F32), (0 - F32.to_u32((0.0 - v : F32)) : U32), F32.to_u32(v))

type Disk is Data:
  Disk{cx: F32, cy: F32, radius: F32}

def near(+d: Disk, +x: U32, +y: U32) -> Bool:
  match d:
    case Disk{+cx, +cy, +radius}:
      +dx = (U32.to_f32(x) - cx : F32)
      +dy = (U32.to_f32(y) - cy : F32)
      (F32.sqrt((dx * dx + dy * dy : F32)) < radius : F32)

def add_if(hit: Bool, +p: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case False{}:
      acc
    case True{}:
      p <> acc

def keep(close: Bool, +segs: List<&2, Seg>, +x: U32, +y: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match close:
    case False{}:
      acc
    case True{}:
      add_if(U32.is_ne(winding(segs, U32.to_f32(x), U32.to_f32(y), 0), 0), pack(x, y), acc)

def column(rows: List<&2, List<&2, Seg>>, go: Bool, +d: Disk, +maxy: F32, +x: U32, +y: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match rows:
    case Nil{}:
      acc
    case Con{+segs, rest}:
      match go:
        case False{}:
          acc
        case True{}:
          column(rest, (U32.to_f32((y + 1 : U32)) < maxy : F32), d, maxy, x, (y + 1 : U32), keep(near(d, x, y), segs, x, y, acc))

def columns(n: Nat, go: Bool, +rows: List<&2, List<&2, Seg>>, +d: Disk, +b: Box, +x: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      match go:
        case False{}:
          acc
        case True{}:
          match b:
            case Box{_, +maxx, +miny, +maxy}:
              +y0 = trunc_wrap(miny)
              columns(p, (U32.to_f32((x + 1 : U32)) < maxx : F32), rows, d, b, (x + 1 : U32),
                column(rows, (U32.to_f32(y0) < maxy : F32), d, maxy, x, y0, acc))

# Per scan row y0, y0 + 1, ... below maxy, the polygon edges spanning it.
def rows_of(n: Nat, go: Bool, +poly: List<&2, TileWorld.Point>, +maxy: F32, +y: U32) -> List<&2, List<&2, Seg>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      match go:
        case False{}:
          Nil{}
        case True{}:
          row_segs(poly, U32.to_f32(y)) <> rows_of(p, (U32.to_f32((y + 1 : U32)) < maxy : F32), poly, maxy, (y + 1 : U32))

# Packed tiles in scan order and their count.
type Counted is Data:
  Counted{tiles: List<&2, U32>, count: U32}

def tiles_of(c: Counted) -> List<&2, U32>:
  match c:
    case Counted{tiles, _}:
      tiles

def counted_reverse(xs: List<&2, U32>, acc: List<&2, U32>, +n: U32) -> Counted:
  match xs:
    case Nil{}:
      Counted{acc, n}
    case Con{+x, rest}:
      counted_reverse(rest, x <> acc, (n + 1 : U32))

def scan(+poly: List<&2, TileWorld.Point>, +d: Disk, b: Box) -> Counted:
  match b:
    case Box{+minx, +maxx, +miny, +maxy}:
      +x0 = trunc_wrap(minx)
      +y0 = trunc_wrap(miny)
      +rows = rows_of(U32.to_nat(65536), (U32.to_f32(y0) < maxy : F32), poly, maxy, y0)
      counted_reverse(columns(U32.to_nat(65536), (U32.to_f32(x0) < maxx : F32), rows, d, Box{minx, maxx, miny, maxy}, x0, Nil{}), Nil{}, 0)

# PolygonTilesWithinRadius(poly, (cx, cy), radius), packed tiles in scan order.
def within_radius(+poly: List<&2, TileWorld.Point>, +cx: F32, +cy: F32, +radius: F32) -> Counted:
  match poly:
    case Nil{}:
      Counted{Nil{}, 0}
    case Con{_, _}:
      scan(poly, Disk{cx, cy, radius}, bounds(poly, Box{max_float(), (0.0 - max_float() : F32), max_float(), (0.0 - max_float() : F32)}))

# SiteTiles / SitePoints with its size (GetSiteArea): the site's polygon within radius 20 of the site.
def counted_site_tiles(s: TileWorld.Site) -> Counted:
  match s:
    case TileWorld.Site{_, +x, +y, _, _, +polygon}:
      within_radius(polygon, x, y, 20.0)

# SiteTiles / SitePoints: the site's polygon within radius 20 of the site.
def site_tiles(s: TileWorld.Site) -> List<&2, U32>:
  tiles_of(counted_site_tiles(s))
