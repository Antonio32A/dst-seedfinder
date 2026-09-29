import Base
import ../tiles/sitetiles.bend as SiteTiles
import ../tiles/world.bend as TileWorld

# The tile points of a set of sites as the cave engines scan them (CA_CollectSiteTiles, Maze_ctor): x outer and y
# inner over the union bounding box less its last column and row, and for each tile every site within 20 whose
# polygon contains it, in site order. A tile in two polygons is listed twice. A tile is packed as x | y << 16.

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

def hit(+s: TileWorld.Site, +x: U32, +y: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case TileWorld.Site{_, +sx, +sy, _, _, +polygon}:
      SiteTiles.keep(SiteTiles.near(SiteTiles.Disk{sx, sy, 20.0}, x, y), SiteTiles.row_segs(polygon, U32.to_f32(y)), x, y, acc)

def hits(sites: List<&2, TileWorld.Site>, +x: U32, +y: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match sites:
    case Nil{}:
      acc
    case Con{+s, rest}:
      hits(rest, x, y, hit(s, x, y, acc))

def column(n: Nat, +sites: List<&2, TileWorld.Site>, +x: U32, +y: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      column(p, sites, x, (y + 1 : U32), hits(sites, x, y, acc))

def span(+from: U32, +to: U32) -> Nat:
  U32.to_nat(Bool.pick(U32, (from < to : U32), (to - from : U32), 0))

def columns(n: Nat, +sites: List<&2, TileWorld.Site>, +x: U32, +y0: U32, +yend: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      columns(p, sites, (x + 1 : U32), y0, yend, column(span(y0, yend), sites, x, y0, acc))

# The tile points of the sites within the box `b` (the union of their polygons' bounding boxes).
def tiles(+sites: List<&2, TileWorld.Site>, +b: SiteTiles.Box) -> List<&2, U32>:
  match b:
    case SiteTiles.Box{+minx, +maxx, +miny, +maxy}:
      +x0 = SiteTiles.trunc_wrap(minx)
      +xend = (SiteTiles.trunc_wrap(maxx) - 1 : U32)
      List.reverse(&2, U32, columns(span(x0, xend), sites, x0, SiteTiles.trunc_wrap(miny), (SiteTiles.trunc_wrap(maxy) - 1 : U32), Nil{}))
