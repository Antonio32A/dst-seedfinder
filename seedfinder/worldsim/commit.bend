import Base
import ../f64/repr.bend as FR
import ../f32/ops.bend as FO
import ./voronoi/polygon.bend as VG

# BoostMap::Commit (the layout extent becomes the square world size, ScaleAndCenter(1, 1) rebuilds the Voronoi,
# CheckForValidCells), ScaleAndCenter itself (also used by ConvertToTileMap) and the extent helpers, all in float
# as the game computes them. Sites are VG.SiteIn records (float bits) in site order.

def flt_max() -> F32:
  FO.from_bits(2139095039)

def flt_min() -> F32:
  FO.from_bits(8388608)

def no_site_centre() -> F32:
  FO.from_bits(2130706431)

# min_float / max_float of boostmap.cpp: `current <= v ? current : v` and `v <= current ? current : v`.
def min_float(+current: F32, +v: F32) -> F32:
  Bool.pick(F32, FO.le(current, v), current, v)

def max_float(+current: F32, +v: F32) -> F32:
  Bool.pick(F32, FO.le(v, current), current, v)

def site_x(+s: VG.SiteIn) -> F32:
  match s:
    case VG.SiteIn{+x, _, _, _, _}:
      FO.from_bits(x)

def site_y(+s: VG.SiteIn) -> F32:
  match s:
    case VG.SiteIn{_, +y, _, _, _}:
      FO.from_bits(y)

type Box is Data:
  Box{lox: F32, hix: F32, loy: F32, hiy: F32}

def box_of(l: List<&2, VG.SiteIn>, +b: Box) -> Box:
  match l:
    case Nil{}:
      b
    case Con{+s, rest}:
      match b:
        case Box{+lox, +hix, +loy, +hiy}:
          box_of(rest, Box{min_float(lox, site_x(s)), max_float(hix, site_x(s)), min_float(loy, site_y(s)), max_float(hiy, site_y(s))})

def site_box(+l: List<&2, VG.SiteIn>) -> Box:
  box_of(l, Box{flt_max(), flt_min(), flt_max(), flt_min()})

def extent(+lo: F32, +hi: F32, +margin: U32, +empty: Bool) -> U32:
  Bool.pick(U32, empty, (2147483648 + (margin * 2 : U32) : U32), (FO.to_i32(FO.sub(hi, lo)) + (margin * 2 : U32) : U32))

def size_of_box(+b: Box, +margin: U32, +empty: Bool) -> U32:
  match b:
    case Box{+lox, +hix, +loy, +hiy}:
      +sx = extent(lox, hix, margin, empty)
      +sy = extent(loy, hiy, margin, empty)
      Bool.pick(U32, (sy <= sx : U32), sx, sy)

# The new square size of Commit: max(SiteExtentY, SiteExtentX) as unsigned, margin 20 (0 for a 1 x 1 world).
def commit_size(+sites: List<&2, VG.SiteIn>, +w: U32, +h: U32) -> U32:
  +margin = Bool.pick(U32, U32.is_eq(w, 1) && U32.is_eq(h, 1), 0, 20)
  size_of_box(site_box(sites), margin, List.is_empty(&2, VG.SiteIn, sites))

def scaled(l: List<&2, VG.SiteIn>, +fx: F32, +fy: F32) -> List<&2, VG.SiteIn>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      match s:
        case VG.SiteIn{+x, +y, +k, +cx, +cy}:
          VG.SiteIn{FO.bits(FO.mul(FO.from_bits(x), fx)), FO.bits(FO.mul(FO.from_bits(y), fy)), k, cx, cy} <> scaled(rest, fx, fy)

def centre(+lo: F32, +hi: F32, +empty: Bool) -> F32:
  Bool.pick(F32, empty, no_site_centre(), FO.add(FO.mul(FO.sub(hi, lo), 0.5), lo))

def frame_centre(+size: U32) -> F32:
  +hi = FO.from_f64(FR.from_u32(size))
  +lo = FO.from_f64(FR.zero())
  FO.add(FO.mul(FO.sub(hi, lo), 0.5), lo)

# A ScaleAndCenter: the moved sites and whether the offset was (0, 0), in which case BuildVoronoi also ran before
# the (zero) move.
type Centred is Data:
  Centred{sites: List<&2, VG.SiteIn>, still: Bool}

def moved(l: List<&2, VG.SiteIn>, +ox: F32, +oy: F32) -> List<&2, VG.SiteIn>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      match s:
        case VG.SiteIn{+x, +y, +k, +cx, +cy}:
          VG.SiteIn{FO.bits(FO.add(FO.from_bits(x), ox)), FO.bits(FO.add(FO.from_bits(y), oy)), k, cx, cy} <> moved(rest, ox, oy)

def centred_by(+l: List<&2, VG.SiteIn>, +ox: F32, +oy: F32) -> Centred:
  Centred{moved(l, ox, oy), FO.eq(oy, 0.0) && FO.eq(ox, 0.0)}

def centred_box(+b: Box, +l: List<&2, VG.SiteIn>, +w: U32, +h: U32) -> Centred:
  match b:
    case Box{+lox, +hix, +loy, +hiy}:
      +empty = List.is_empty(&2, VG.SiteIn, l)
      centred_by(l, FO.sub(frame_centre(w), centre(lox, hix, empty)), FO.sub(frame_centre(h), centre(loy, hiy, empty)))

# BoostMap::ScaleAndCenter(fx, fy) in the w x h frame (without the Voronoi rebuilds).
def scale_and_center(+sites: List<&2, VG.SiteIn>, +fx: F32, +fy: F32, +w: U32, +h: U32) -> Centred:
  +s = scaled(sites, fx, fy)
  centred_box(site_box(s), s, w, h)

# A node for CheckForValidCells: its type, whether it has a parent, and its polygon's point count.
type NodeCheck is Data:
  NodeCheck{kind: U32, has_parent: Bool, points: U32}

def node_ok(+n: NodeCheck) -> Bool:
  match n:
    case NodeCheck{+kind, +parent, +points}:
      U32.is_eq(kind, 1) || Bool.not(parent) || (2 < points : U32)

# CheckForValidCells over every node of the map (the order does not change the answer).
def valid_cells(l: List<&2, NodeCheck>) -> Bool:
  match l:
    case Nil{}:
      True{}
    case Con{+n, rest}:
      node_ok(n) && valid_cells(rest)

# Commit's outcome before CheckForValidCells: the new size, the centred sites, whether BuildVoronoi ran twice, and
# the final BuildVoronoi.
type Committed is Type:
  Committed{size: U32, sites: List<&2, VG.SiteIn>, twice: Bool, cells: VG.Cells}

def committed(+c: Centred, +windows: Bool, +size: U32) -> Committed:
  match c:
    case Centred{+sites, +still}:
      Committed{size, sites, still, VG.build_voronoi(windows, size, size, sites)}

# BoostMap::Commit for sites laid out in a w x h world: SetSize(s, s) and ScaleAndCenter(1, 1).
def commit(+windows: Bool, +w: U32, +h: U32, +sites: List<&2, VG.SiteIn>) -> Committed:
  +size = commit_size(sites, w, h)
  committed(scale_and_center(sites, 1.0, 1.0, size, size), windows, size)

# ConvertToTileMap's resize: size = max(min_size, w, h) as float, SetSize(size, size), then
# ScaleAndCenter(size / w0, size / h0). Returns the new size and the centred sites.
def tile_map_size(+min_size: U32, +w: U32, +h: U32) -> U32:
  +s0 = FO.from_f64(FR.from_i32(min_size))
  +s1 = Bool.pick(F32, FO.le(s0, FO.from_f64(FR.from_i32(w))), FO.from_f64(FR.from_i32(w)), s0)
  +s2 = Bool.pick(F32, FO.le(s1, FO.from_f64(FR.from_i32(h))), FO.from_f64(FR.from_i32(h)), s1)
  FO.to_i32(s2)

def tile_map_centre(+sites: List<&2, VG.SiteIn>, +size: U32, +w: U32, +h: U32) -> Centred:
  +fs = FO.from_f64(FR.from_u32(size))
  scale_and_center(sites, FO.div(fs, FO.from_f64(FR.from_i32(w))), FO.div(fs, FO.from_f64(FR.from_i32(h))), size, size)
