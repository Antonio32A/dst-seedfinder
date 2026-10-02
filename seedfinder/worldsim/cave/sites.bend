import Base
import ../tiles/sitetiles.bend as SiteTiles
import ../tiles/world.bend as TileWorld

# The tile points of a set of sites as the cave engines scan them (CA_CollectSiteTiles, Maze_ctor): x outer and y
# inner over the union bounding box less its last column and row, and for each tile every site within 20 whose
# polygon contains it, in site order. A tile in two polygons is listed twice. A tile is packed as x | y << 16.
# Each site is scanned on its own, over the box's tiles within 21 of it (a superset of those within 20), and the
# sites' scans are merged stably in that order.

def empty_box() -> SiteTiles.Box:
  SiteTiles.Box{SiteTiles.max_float(), (0.0 - SiteTiles.max_float() : F32), SiteTiles.max_float(), (0.0 - SiteTiles.max_float() : F32)}

def site_polygon(s: TileWorld.Site) -> List<&2, TileWorld.Point>:
  match s:
    case TileWorld.Site{_, _, _, _, _, polygon}:
      polygon

# The float bounding box of all the sites' polygon vertices.
def box_of(sites: List<&2, TileWorld.Site>, b: SiteTiles.Box) -> SiteTiles.Box:
  match sites:
    case Nil{}:
      b
    case Con{+s, rest}:
      box_of(rest, SiteTiles.bounds(site_polygon(s), b))

def clamped(+edge: F32) -> U32:
  Bool.pick(U32, (edge < 0.0 : F32), 0, F32.to_u32(edge))

def larger(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a < b : U32), b, a)

def smaller(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a < b : U32), a, b)

# The tiles [lo, hi) of the box's columns or rows [from, to) within 21 of c.
def near_range(+from: U32, +to: U32, +c: F32) -> SiteTiles.Box:
  SiteTiles.Box{U32.to_f32(larger(from, clamped((c - 21.0 : F32)))), U32.to_f32(smaller(to, clamped((c + 22.0 : F32)))), 0.0, 0.0}

def clipped(+xs: SiteTiles.Box, +ys: SiteTiles.Box) -> SiteTiles.Box:
  match xs ys:
    case SiteTiles.Box{+x0, +x1, _, _} SiteTiles.Box{+y0, +y1, _, _}:
      SiteTiles.Box{x0, x1, y0, y1}

def site_scan(+s: TileWorld.Site, +x0: U32, +xend: U32, +y0: U32, +yend: U32) -> List<&2, U32>:
  match s:
    case TileWorld.Site{_, +sx, +sy, _, _, +polygon}:
      SiteTiles.tiles_of(SiteTiles.scan(polygon, SiteTiles.Disk{sx, sy, 20.0}, clipped(near_range(x0, xend, sx), near_range(y0, yend, sy))))

def scans(sites: List<&2, TileWorld.Site>, +x0: U32, +xend: U32, +y0: U32, +yend: U32) -> List<&2, List<&2, U32>>:
  match sites:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      site_scan(s, x0, xend, y0, yend) <> scans(rest, x0, xend, y0, yend)

def scan_le(a: U32, b: U32) -> Bool:
  +p = a
  +q = b
  +px = SiteTiles.unpack_x(p)
  +qx = SiteTiles.unpack_x(q)
  (px < qx : U32) || (U32.is_eq(px, qx) && (SiteTiles.unpack_y(p) <= SiteTiles.unpack_y(q) : U32))

# The tile points of the sites within the box `b` (the union of their polygons' bounding boxes).
def tiles(+sites: List<&2, TileWorld.Site>, +b: SiteTiles.Box) -> List<&2, U32>:
  match b:
    case SiteTiles.Box{+minx, +maxx, +miny, +maxy}:
      List.sort.go(~U32, ~scan_le, U32.to_nat(32), U32.to_nat(4294967295),
        scans(sites, SiteTiles.trunc_wrap(minx), (SiteTiles.trunc_wrap(maxx) - 1 : U32), SiteTiles.trunc_wrap(miny), (SiteTiles.trunc_wrap(maxy) - 1 : U32)))
