import Base
import ../../f32/ops.bend as F32Ops
import ../../rng/pcg.bend as Pcg
import ../../rng/crand.bend as CRand
import ../grid.bend as Grid
import ../tiles/sitetiles.bend as SiteTiles
import ../tiles/world.bend as TileWorld
import ./shuffle.bend as CaveShuffle
import ./sites.bend as CaveSites

# WorldSim:RunCA (CA_ctor, CA_Seed, CA_Iterate, CA_ApplyToWorld): a synchronous cellular automaton over the site's
# polygon bounding box that paints the custom tiles of a room. Values 0..4; the seeded 4s never change and every other
# cell next to a 3 or 4 becomes its neighbourhood maximum m minus pcg32_boundedrand(m). The final values 1..4 are
# written to the tile map as tile ids 2..5. The wall seed mode (3) is not implemented: no room uses it.

type Ca is Type:
  Ca{a: Array<U32>, b: Array<U32>, rng: Pcg.Rng}

# The state after RunCA: the tile/flag map and the PCG state.
type Painted is Type:
  Painted{grid: Grid.Grid, rng: Pcg.Rng}

def new_cells(+w: U32, +h: U32) -> Array<U32>:
  Grid.alloc(Grid.depth_for(24n, (w * h : U32), 0n, 1), 0)

def neighbour_step(ok: Bool, got: Array<U32> & U32, +m: U32) -> Array<U32> & U32:
  match ok:
    case False{}:
      (cells, _) = got
      (cells, m)
    case True{}:
      (cells, +v) = got
      (cells, Bool.pick(U32, (m < v : U32), v, m))

# The maximum over the eight neighbours of (x, y) that lie in the w x h grid (k walks the 3 x 3 block).
def neighbour_max(n: Nat, got: Array<U32> & U32, +w: U32, +h: U32, +x: U32, +y: U32, +k: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      got
    case 1n+p:
      (a, +m) = got
      +nx = (x + (k % 3) - 1 : U32)
      +ny = (y + (k / 3) - 1 : U32)
      +ok = (nx < w : U32) && (ny < h : U32) && Bool.not(U32.is_eq(k, 4))
      neighbour_max(p, neighbour_step(ok, a[Grid.index(Bool.pick(U32, ok, nx, 0), Bool.pick(U32, ok, ny, 0), w)], m), w, h, x, y, (k + 1 : U32))

def store(a: Array<U32>, b: Array<U32>, rng: Pcg.Rng, +c: U32, +w: U32, +x: U32, +y: U32) -> Ca:
  b[Grid.index(x, y, w)] <- c
  Ca{a, b, rng}

def store_drawn(a: Array<U32>, b: Array<U32>, drawn: U32 & Pcg.Rng, +m: U32, +w: U32, +x: U32, +y: U32) -> Ca:
  (+r, rng) = drawn
  store(a, b, rng, (m - r : U32), w, x, y)

def cell_draw(rule: Bool, a: Array<U32>, b: Array<U32>, rng: Pcg.Rng, +c: U32, +m: U32, +w: U32, +x: U32, +y: U32) -> Ca:
  match rule:
    case True{}:
      store_drawn(a, b, CRand.bounded(rng, m), m, w, x, y)
    case False{}:
      store(a, b, rng, c, w, x, y)

def cell_rule(got: Array<U32> & U32, b: Array<U32>, rng: Pcg.Rng, +c: U32, +w: U32, +x: U32, +y: U32) -> Ca:
  (a, +m) = got
  cell_draw((m > 2 : U32), a, b, rng, c, m, w, x, y)

def cell_state(seeded: Bool, a: Array<U32>, b: Array<U32>, rng: Pcg.Rng, +c: U32, +w: U32, +h: U32, +x: U32, +y: U32) -> Ca:
  match seeded:
    case True{}:
      store(a, b, rng, c, w, x, y)
    case False{}:
      cell_rule(neighbour_max(9n, (a, 0), w, h, x, y, 0), b, rng, c, w, x, y)

def cell_read(got: Array<U32> & U32, b: Array<U32>, rng: Pcg.Rng, +w: U32, +h: U32, +x: U32, +y: U32) -> Ca:
  (a, +c) = got
  cell_state(U32.is_eq(c, 4), a, b, rng, c, w, h, x, y)

def cell_at(ca: Ca, +w: U32, +h: U32, +x: U32, +y: U32) -> Ca:
  match ca:
    case Ca{a, b, rng}:
      cell_read(a[Grid.index(x, y, w)], b, rng, w, h, x, y)

def column(n: Nat, ca: Ca, +w: U32, +h: U32, +x: U32, +y: U32) -> Ca:
  match n:
    case 0n:
      ca
    case 1n+p:
      column(p, cell_at(ca, w, h, x, y), w, h, x, (y + 1 : U32))

def pass_over(n: Nat, ca: Ca, +w: U32, +h: U32, +x: U32) -> Ca:
  match n:
    case 0n:
      ca
    case 1n+p:
      pass_over(p, column(U32.to_nat(h), ca, w, h, x, 0), w, h, (x + 1 : U32))

def swapped(ca: Ca) -> Ca:
  match ca:
    case Ca{a, b, rng}:
      Ca{b, a, rng}

def iterate(n: Nat, ca: Ca, +w: U32, +h: U32) -> Ca:
  match n:
    case 0n:
      ca
    case 1n+p:
      iterate(p, swapped(pass_over(U32.to_nat(w), ca, w, h, 0)), w, h)

# The automaton's cells after `iterations` passes over the w x h grid `a` (values 0..4, row stride w) and the PCG state.
def evolve(a: Array<U32>, +w: U32, +h: U32, +iterations: U32, rng: Pcg.Rng) -> Ca:
  iterate(U32.to_nat(iterations), Ca{a, new_cells(w, h), rng}, w, h)

# The box the automaton runs over: its minimum corner and size.
type Dim is Data:
  Dim{minx: F32, miny: F32, w: U32, h: U32}

def dim_of(b: SiteTiles.Box) -> Dim:
  match b:
    case SiteTiles.Box{+minx, +maxx, +miny, +maxy}:
      Dim{minx, miny, SiteTiles.trunc_wrap((maxx - minx : F32)), SiteTiles.trunc_wrap((maxy - miny : F32))}

def fresh(+d: Dim) -> Array<U32>:
  match d:
    case Dim{_, _, +w, +h}:
      new_cells(w, h)

# The automaton cell of a position: (int)(x - minx) + (int)(y - miny) * w.
def cell_of(+x: F32, +y: F32, +d: Dim) -> U32:
  match d:
    case Dim{+minx, +miny, +w, _}:
      (F32Ops.to_i32((x - minx : F32)) + F32Ops.to_i32((y - miny : F32)) * w : U32)

def tile_cell(+p: U32, +d: Dim) -> U32:
  cell_of(U32.to_f32(SiteTiles.unpack_x(p)), U32.to_f32(SiteTiles.unpack_y(p)), d)

def seed_list(n: Nat, pts: List<&2, U32>, a: Array<U32>, +d: Dim) -> Array<U32>:
  match n pts:
    case 0n _:
      a
    case 1n+p Nil{}:
      a
    case 1n+p Con{+q, rest}:
      a[tile_cell(q, d)] <- 4
      seed_list(p, rest, a, d)

# The automaton's initial cells, the tile points in the order ApplyToWorld visits them, and the PCG state.
type Seeded is Type:
  Seeded{a: Array<U32>, order: List<&2, U32>, rng: Pcg.Rng}

def seed_at(a: Array<U32>, pt: TileWorld.Point, +d: Dim, order: List<&2, U32>, rng: Pcg.Rng) -> Seeded:
  match pt:
    case TileWorld.Point{+x, +y}:
      a[cell_of(x, y, d)] <- 4
      Seeded{a, order, rng}

def centroid_of(s: TileWorld.Site) -> TileWorld.Point:
  match s:
    case TileWorld.Site{_, _, _, +cx, +cy, _}:
      TileWorld.Point{cx, cy}

def position_of(s: TileWorld.Site) -> TileWorld.Point:
  match s:
    case TileWorld.Site{_, +x, +y, _, _, _}:
      TileWorld.Point{x, y}

def min_count(+n: U32, +len: U32) -> U32:
  Bool.pick(U32, (len < n : U32), len, n)

def seed_shuffled(sh: CaveShuffle.Shuffled, +n: U32, +d: Dim) -> Seeded:
  match sh:
    case CaveShuffle.Shuffled{+pts, rng}:
      Seeded{seed_list(U32.to_nat(min_count(n, U32.from_nat(List.length(&2, U32, pts)))), pts, fresh(d), d), pts, rng}

def seed_by_mode(+mode: U32, +windows: Bool, s: TileWorld.Site, cand: List<&2, U32>, rng: Pcg.Rng, +n: U32, +d: Dim) -> Seeded:
  match mode:
    case 1:
      seed_at(fresh(d), centroid_of(s), d, cand, rng)
    case 2:
      seed_at(fresh(d), position_of(s), d, cand, rng)
    case 3:
      Seeded{fresh(d), cand, rng}
    case _:
      seed_shuffled(CaveShuffle.large(windows, cand, rng), n, d)

def paint_cell(got: Grid.Grid & U32, +v: U32, +i: U32) -> Grid.Grid:
  (g, +old) = got
  Grid.put(g, i, Grid.cell((v + 1 : U32), (Grid.flags_of(old) .&. 49151 : U32)))

def paint(write: Bool, g: Grid.Grid, +v: U32, +p: U32, +tw: U32) -> Grid.Grid:
  match write:
    case False{}:
      g
    case True{}:
      paint_cell(Grid.get(g, Grid.index(SiteTiles.unpack_x(p), SiteTiles.unpack_y(p), tw)), v, Grid.index(SiteTiles.unpack_x(p), SiteTiles.unpack_y(p), tw))

def apply_cell(got: Array<U32> & U32, g: Grid.Grid, +write: Bool, +p: U32, +tw: U32) -> Array<U32> & Grid.Grid:
  (a, +v) = got
  (a, paint(write && Bool.not(U32.is_zero(v)), g, v, p, tw))

def in_range(+v: F32, +limit: U32) -> Bool:
  (0.0 <= v : F32) && (v < U32.to_f32(limit) : F32)

def apply_point(a: Array<U32>, g: Grid.Grid, +p: U32, +d: Dim, +tw: U32, +th: U32) -> Array<U32> & Grid.Grid:
  match d:
    case Dim{+minx, +miny, +w, +h}:
      +fx = (U32.to_f32(SiteTiles.unpack_x(p)) - minx : F32)
      +fy = (U32.to_f32(SiteTiles.unpack_y(p)) - miny : F32)
      +inside = in_range(fx, w) && in_range(fy, h)
      apply_cell(a[Bool.pick(U32, inside, cell_of(U32.to_f32(SiteTiles.unpack_x(p)), U32.to_f32(SiteTiles.unpack_y(p)), d), 0)], g, inside
        && (SiteTiles.unpack_x(p) < tw : U32) && (SiteTiles.unpack_y(p) < th : U32), p, tw)

def apply_list(order: List<&2, U32>, got: Array<U32> & Grid.Grid, +d: Dim, +tw: U32, +th: U32) -> Array<U32> & Grid.Grid:
  match order:
    case Nil{}:
      got
    case Con{+p, rest}:
      (a, g) = got
      apply_list(rest, apply_point(a, g, p, d, tw, th), d, tw, th)

def applied(got: Array<U32> & Grid.Grid) -> Grid.Grid:
  (_, g) = got
  g

def finish(ca: Ca, order: List<&2, U32>, g: Grid.Grid, +d: Dim, +tw: U32, +th: U32) -> Painted:
  match ca:
    case Ca{a, _, rng}:
      Painted{applied(apply_list(order, (a, g), d, tw, th)), rng}

def iterated(sd: Seeded, +iterations: U32, +d: Dim, g: Grid.Grid, +tw: U32, +th: U32) -> Painted:
  match sd:
    case Seeded{a, order, rng}:
      match d:
        case Dim{_, _, +w, +h}:
          finish(evolve(a, w, h, iterations, rng), order, g, d, tw, th)

def run_in(+windows: Bool, +s: TileWorld.Site, +iterations: U32, +mode: U32, +n: U32, g: Grid.Grid, rng: Pcg.Rng, +b: SiteTiles.Box, +tw: U32, +th: U32) -> Painted:
  iterated(seed_by_mode(mode, windows, s, CaveSites.tiles([s], b), rng, n, dim_of(b)), iterations, dim_of(b), g, tw, th)

def run_sized(+windows: Bool, +s: TileWorld.Site, +iterations: U32, +mode: U32, +n: U32, g: Grid.Grid, rng: Pcg.Rng) -> Painted:
  match g:
    case Grid.Grid{cells, +tw, +th}:
      run_in(windows, s, iterations, mode, n, Grid.Grid{cells, tw, th}, rng, CaveSites.box_of([s], CaveSites.empty_box()), tw, th)

# WorldSim:RunCA(site, iterations, seed_mode, n) on the tile and flag map `g` (`windows` selects the Windows RAND_MAX and
# shuffle). seed_mode 0 seeds n random tile points (one shuffle of the site's tile list), 1 the centroid, 2 the site.
def run(+windows: Bool, +s: TileWorld.Site, +iterations: U32, +mode: U32, +n: U32, g: Grid.Grid, rng: Pcg.Rng) -> Painted:
  run_sized(windows, s, iterations, mode, n, g, rng)
