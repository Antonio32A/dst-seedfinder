import Base
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ../f64/random.bend as FRN
import ../rng/pcg.bend as R
import ../data/enums.bend as EN
import ../data/ocean_convert.bend as OD
import ../worldsim/grid.bend as GR
import ../worldsim/tiles/groups.bend as TG
import ./convert_plane.bend as OP
import ./convert_fills.bend as OF
import ./convert_noise.bend as ON
import ./convert_blend.bend as OB

# Ocean_ConvertImpassibleToWater (map/ocean_gen.lua) for the default forest: do_squarefill, do_groundfill, do_noise,
# do_blend, AddShoreline, do_void_outline, on the map after Ocean_PlaceSetPieces. Only do_noise (six draws) and the
# void outline (one math.random per outline step) touch the RNG.

def shore_class(+cell: U32) -> U32:
  +t = GR.tile_of(cell)
  +candidate = TG.is_ocean(t) && Bool.not(U32.is_eq(t, EN.tile_ocean_brinepool()))
  +dry = Bool.not(TG.is_ocean(t) || TG.is_invalid(t))
  (Bool.to_u32(candidate) .|. (Bool.to_u32(dry) << 1n) : U32)

def shore(+cell: U32) -> U32:
  OF.set_tile(EN.tile_ocean_coastal_shore(), cell)

def shore_marked(got: Array<U32> & Array<U32>, +g: OP.Geo) -> GR.Grid:
  (cells, a) = got
  near = OP.square(a, g, OP.base(g, 4), OP.base(g, 1), OP.base(g, 5), 1)
  candidates = OP.inter(near, g, OP.base(g, 4), OP.base(g, 0))
  OF.painted(OP.paint(~(c => shore(c)), candidates, cells, g, OP.base(g, 4)), g)

# AddShoreline: every ocean tile but OCEAN_BRINEPOOL next to (8 neighbours) a tile that is neither ocean nor invalid
# becomes OCEAN_COASTAL_SHORE. The result is ocean again, so the test reads the same map throughout.
def shoreline(g: GR.Grid) -> GR.Grid:
  match g:
    case GR.Grid{cells, +w, +h}:
      +geo = OP.geo(w, h)
      shore_marked(OP.extract(~(c => shore_class(c)), cells, OP.arena(geo, 6), geo, 0), geo)

type Walk is Data:
  Walk{s1: U32, s2: U32, s3: U32}

type Tuning is Data:
  Tuning{max: U32, deeper: FR.F64, bound: FR.F64}

# One outline side: `size` is the side's length (the walk takes size + 1 steps), `across` the other dimension;
# `rows` when step i is a row (the left and right sides), `far` when the depth counts from the far edge.
type Side is Data:
  Side{size: U32, across: U32, rows: Bool, far: Bool, w: U32, h: U32}

def f64_of(bits: U32 & U32) -> FR.F64:
  (+hi, +lo) = bits
  FR.F64{hi, lo}

def tuning_of(+max: U32, +deeper: FR.F64, +shallower: FR.F64) -> Tuning:
  Tuning{max, deeper, FA.sub(FR.one(), shallower)}

def middle() -> Tuning:
  +max = FR.to_i32(FR.floor(FA.mul(FR.from_u32(OD.waterfall_max_dist()), f64_of(OD.middle_max_factor()))))
  tuning_of(max, f64_of(OD.middle_deeper()), f64_of(OD.middle_shallower()))

def corner() -> Tuning:
  tuning_of(OD.waterfall_max_dist(), f64_of(OD.corner_deeper()), f64_of(OD.corner_shallower()))

def is_corner(+i: U32, +size: U32) -> Bool:
  +offset = OD.waterfall_max_dist()
  (i <= offset : U32) || (i >= (size - offset - offset) : U32)

def tuning_at(corner_step: Bool) -> Tuning:
  match corner_step:
    case True{}:
      corner()
    case False{}:
      middle()

type Next is Data:
  Next{d: U32, walk: Walk}

def max1(+v: U32) -> U32:
  Bool.pick(U32, (v < 1 : U32), 1, v)

# calc_next(s, tunings) for the draw r.
def calc_next(+r: FR.F64, +s: Walk, +t: Tuning) -> Next:
  match s:
    case Walk{+s1, +s2, +s3}:
      match t:
        case Tuning{+max, +deeper, +bound}:
          +down = (s1 < max : U32) && FC.le(r, deeper)
          +up = FC.gt(r, bound)
          +v = max1(Bool.pick(U32, down, (s1 + 1 : U32), Bool.pick(U32, up, (s1 - 1 : U32), s1)))
          +d = Bool.pick(U32, U32.is_eq(v, s3) && Bool.not(U32.is_eq(v, s2)), s2, v)
          Next{d, Walk{d, d, s2}}

def along(+side: Side, +k: U32) -> U32:
  match side:
    case Side{_, +across, _, +far, _, _}:
      Bool.pick(U32, far, (across - k : U32), k)

def spot_x(+side: Side, +i: U32, +k: U32) -> U32:
  match side:
    case Side{_, _, +rows, _, _, _}:
      Bool.pick(U32, rows, along(side, k), i)

def spot_y(+side: Side, +i: U32, +k: U32) -> U32:
  match side:
    case Side{_, _, +rows, _, _, _}:
      Bool.pick(U32, rows, i, along(side, k))

def set_if(inside: Bool, got: Array<U32> & U32, +tile: U32, +i: U32) -> Array<U32>:
  match inside:
    case True{}:
      (cells, +v) = got
      cells[i] <- OF.set_tile(tile, v)
    case False{}:
      (cells, _) = got
      cells

def border_if(inside: Bool, got: Array<U32> & U32, +i: U32) -> Array<U32>:
  (cells, +v) = got
  +open = inside && Bool.not(U32.is_eq(GR.tile_of(v), EN.tile_impassable()))
  set_if(open, (cells, v), EN.tile_ocean_rough(), i)

def mark_at(border: Bool, +inside: Bool, got: Array<U32> & U32, +j: U32) -> Array<U32>:
  match border:
    case True{}:
      border_if(inside, got, j)
    case False{}:
      set_if(inside, got, EN.tile_impassable(), j)

def cell_at(cells: Array<U32>, +side: Side, +i: U32, +k: U32, +border: Bool) -> Array<U32>:
  match side:
    case Side{_, _, _, _, +w, +h}:
      +x = spot_x(side, i, k)
      +y = spot_y(side, i, k)
      +j = GR.index(x, y, w)
      +inside = OF.in_map(x, y, w, h)
      mark_at(border, inside, cells[j], j)

def depth_run(n: Nat, cells: Array<U32>, +side: Side, +i: U32, +k: U32) -> Array<U32>:
  match n:
    case 0n:
      cells
    case 1n+p:
      depth_run(p, cell_at(cells, side, i, k, False{}), side, i, (k + 1 : U32))

# One outline step: SetTile(.., IMPASSABLE) at depths 0..d, then add_boarder at d + 1 and d + 2.
def outline_step(cells: Array<U32>, +nx: Next, +side: Side, +i: U32) -> Array<U32>:
  match nx:
    case Next{+d, _}:
      run = depth_run(U32.to_nat((d + 1 : U32)), cells, side, i, 0)
      cell_at(cell_at(run, side, i, (d + 1 : U32), True{}), side, i, (d + 2 : U32), True{})

def walk_of(+nx: Next) -> Walk:
  match nx:
    case Next{_, +walk}:
      walk

def side_size(+side: Side) -> U32:
  match side:
    case Side{+size, _, _, _, _, _}:
      size

def next_at(+r: FR.F64, +walk: Walk, +side: Side, +i: U32) -> Next:
  calc_next(r, walk, tuning_at(is_corner(i, side_size(side))))

def side_go(n: Nat, got: FR.F64 & R.Rng, cells: Array<U32>, +walk: Walk, +side: Side, +i: U32) -> Array<U32> & R.Rng:
  match n:
    case 0n:
      (+r, rng) = got
      (outline_step(cells, next_at(r, walk, side, i), side, i), rng)
    case 1n+p:
      (+r, rng) = got
      +nx = next_at(r, walk, side, i)
      side_go(p, FRN.random(rng), outline_step(cells, nx, side, i), walk_of(nx), side, (i + 1 : U32))

def start() -> Walk:
  +d = OD.waterfall_max_dist()
  Walk{d, d, d}

def side_run(got: Array<U32> & R.Rng, +side: Side) -> Array<U32> & R.Rng:
  (cells, rng) = got
  side_go(U32.to_nat(side_size(side)), FRN.random(rng), cells, start(), side, 0)

def outlined(got: Array<U32> & R.Rng, +w: U32, +h: U32) -> GR.Grid & R.Rng:
  (cells, rng) = got
  (GR.Grid{cells, w, h}, rng)

# do_void_outline: the left, right, top and bottom walks (h + 1, h + 1, w + 1, w + 1 draws), each writing its
# impassable band and a two-tile OCEAN_ROUGH border (out-of-map coordinates are ignored, as SetTile does).
def void_outline(g: GR.Grid, rng: R.Rng) -> GR.Grid & R.Rng:
  match g:
    case GR.Grid{cells, +w, +h}:
      left = side_run((cells, rng), Side{h, w, True{}, False{}, w, h})
      right = side_run(left, Side{h, w, True{}, True{}, w, h})
      top = side_run(right, Side{w, h, False{}, False{}, w, h})
      outlined(side_run(top, Side{w, h, False{}, True{}, w, h}), w, h)

# The fills (do_squarefill, do_groundfill).
def fills(g: GR.Grid) -> GR.Grid:
  OF.fills(g)

# do_noise.
def noise(g: GR.Grid, rng: R.Rng) -> GR.Grid & R.Rng:
  ON.noise(g, rng)

# do_blend.
def blend(g: GR.Grid) -> GR.Grid:
  OB.blend(g)

def after_noise(got: GR.Grid & R.Rng) -> GR.Grid & R.Rng:
  (g, rng) = got
  void_outline(shoreline(blend(g)), rng)

# Ocean_ConvertImpassibleToWater(width, height, ocean_gen_config) on the map after the prefill; rng is the state at
# its first draw.
def convert(g: GR.Grid, rng: R.Rng) -> GR.Grid & R.Rng:
  after_noise(noise(fills(g), rng))
