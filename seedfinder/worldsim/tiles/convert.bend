import Base
import ../../f64/repr.bend as F64Repr
import ../../f64/cmp.bend as F64Cmp
import ../../data/blob.bend as Blob
import ../../data/ocean.bend as OceanData
import ../grid.bend as Grid
import ../noise/perlin.bend as Perlin
import ./groups.bend as TileGroups
import ./table.bend as TileTable
import ./world.bend as TileWorld
import ./sitetiles.bend as SiteTiles

# ConvertToTileMap (tiles.cpp) after its Voronoi rebuild: every cell impassable with flags 0x90ff (the variant nibble
# is drawn, W * H bounded(16) draws, but not stored: see Grid), then each painted site's SiteTiles in site order, later
# sites overwriting earlier ones. Noise tiles resolve through forest_map.lua's GetTileForNoiseTile at
# ImprovedNoise(x / 8, y / 8, 0).

type Step is Data:
  Step{threshold: F64Repr.F64, above: U32}

# A noise tile's threshold table: `first` below the first threshold, then each step's tile from its threshold on.
type Resolver is Data:
  Resolver{first: U32, steps: List<&2, Step>}

def step_of(bits: U32 & U32, +above: U32) -> Step:
  (+hi, +lo) = bits
  Step{F64Repr.F64{hi, lo}, above}

def steps_of(n: Nat, +row: List<&2, U32>) -> List<&2, Step>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      step_of(Blob.f64(row, 0), Blob.at(row, 4)) <> steps_of(p, Blob.drop(row, 5))

def resolver_of(+row: List<&2, U32>) -> Resolver:
  Resolver{Blob.at(row, 1), steps_of(U32.to_nat(Blob.at(row, 2)), Blob.drop(row, 3))}

def row_for(n: Nat, +tile: U32, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      OceanData.noise_functions(i)
    case 1n+p:
      +row = OceanData.noise_functions(i)
      +head = Blob.at(row, 0)
      Bool.pick(List<&2, U32>, U32.is_eq(head, tile) || Blob.is_none(head), row, row_for(p, tile, (i + 1 : U32)))

# The table GetTileForNoiseTile uses for `tile` (NoiseTileFunctions[tile] or the default).
def resolver(+tile: U32) -> Resolver:
  resolver_of(row_for(U32.to_nat(OceanData.noise_functions_count()), tile, 0))

# GetTileForNoiseTile(tile, noise) for the resolver of `tile`.
def resolve_steps(steps: List<&2, Step>, +noise: F64Repr.F64, +tile: U32) -> U32:
  match steps:
    case Nil{}:
      tile
    case Con{Step{+threshold, +above}, rest}:
      Bool.pick(U32, F64Cmp.lt(noise, threshold), tile, resolve_steps(rest, noise, above))

def resolve(r: Resolver, +noise: F64Repr.F64) -> U32:
  match r:
    case Resolver{+first, +steps}:
      resolve_steps(steps, noise, first)

def initial_cell() -> U32:
  Grid.cell(TileGroups.impassable(), 37119)

# One painted site: its tile (INVALID mapped to IMPASSABLE), the noise resolver when that tile is a noise tile.
type Brush is Data:
  Solid{tile: U32}
  Noisy{resolver: Resolver}

def brush_pick(noise: Bool, +t: U32) -> Brush:
  match noise:
    case True{}:
      Noisy{resolver(t)}
    case False{}:
      Solid{t}

def brush_of(+tile: U32) -> Brush:
  +t = Bool.pick(U32, U32.is_eq(tile, TileGroups.invalid()), TileGroups.impassable(), tile)
  brush_pick(TileGroups.is_noise(t), t)

# Whether ConvertToTileMap paints the site: not a Blank/Random node, and not a root.
def painted(n: TileWorld.Node) -> Bool:
  match n:
    case TileWorld.Node{_, +kind, _, _, _, +parent, _, _, _, _}:
      Bool.not(U32.is_eq((kind .&. 4294967293 : U32), 1)) && Bool.not(TileWorld.is_none(parent))

def write_got(got: Array<U32> & U32, +i: U32, +tile: U32) -> Array<U32>:
  (cells, +old) = got
  cells[i] <- Grid.cell(tile, (Grid.flags_of(old) .&. 49151 : U32))

def write(cells: Array<U32>, +i: U32, +tile: U32) -> Array<U32>:
  write_got(cells[i], i, tile)

def cell_index(+p: U32, +w: U32) -> U32:
  Grid.index(SiteTiles.unpack_x(p), SiteTiles.unpack_y(p), w)

# One painted cell: flat index and tile.
type Stroke is Data:
  Stroke{index: U32, tile: U32}

def stroke_if(pending: Bool, +i: U32, +tile: U32, acc: List<&2, Stroke>) -> List<&2, Stroke>:
  match pending:
    case True{}:
      Stroke{i, tile} <> acc
    case False{}:
      acc

def noisy_strokes(pts: List<&2, U32>, got: Array<U32> & F64Repr.F64, +prev: U32, +pending: Bool, +w: U32, +r: Resolver, acc: List<&2, Stroke>) -> Array<U32> & List<&2, Stroke>:
  match pts:
    case Nil{}:
      (perm, +n) = got
      (perm, List.reverse(&2, Stroke, stroke_if(pending, prev, resolve(r, n), acc)))
    case Con{+p, rest}:
      (perm, +n) = got
      noisy_strokes(rest, Perlin.noise_eighths(perm, SiteTiles.unpack_x(p), SiteTiles.unpack_y(p)),
        cell_index(p, w), True{}, w, r, stroke_if(pending, prev, resolve(r, n), acc))

# A site's paint: a solid site writes its points straight to the tile map, a noisy site's cells are resolved first.
type Run is Data:
  Direct{tile: U32, pts: List<&2, U32>}
  Strokes{strokes: List<&2, Stroke>}

def stroked(got: Array<U32> & List<&2, Stroke>) -> Array<U32> & Run:
  (perm, +strokes) = got
  (perm, Strokes{strokes})

def brush_run(b: Brush, +pts: List<&2, U32>, perm: Array<U32>, +w: U32) -> Array<U32> & Run:
  match b:
    case Solid{+tile}:
      (perm, Direct{tile, pts})
    case Noisy{+r}:
      stroked(noisy_strokes(pts, (perm, F64Repr.zero()), 0, False{}, w, r, Nil{}))

def site_run(on: Bool, +n: TileWorld.Node, +pts: List<&2, U32>, perm: Array<U32>, +w: U32) -> Array<U32> & Run:
  match on:
    case False{}:
      (perm, Strokes{Nil{}})
    case True{}:
      match n:
        case TileWorld.Node{_, _, _, +tile, _, _, _, _, _, _}:
          brush_run(brush_of(tile), pts, perm, w)

type Job is Data:
  Job{site: TileWorld.Site, tiles: List<&2, U32>}

def jobs_of(sites: List<&2, TileWorld.Site>, lists: List<&2, List<&2, U32>>) -> List<&2, Job>:
  match sites:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      match lists:
        case Nil{}:
          Nil{}
        case Con{+pts, more}:
          Job{s, pts} <> jobs_of(rest, more)

def keep_last(pending: Bool, +last: Run, acc: List<&2, Run>) -> List<&2, Run>:
  match pending:
    case True{}:
      last <> acc
    case False{}:
      acc

def leaf_loop(jobs: List<&2, Job>, got: Array<U32> & Run, +pending: Bool, +w: U32, acc: List<&2, Run>) -> List<&2, Run>:
  match jobs:
    case Nil{}:
      (_, +last) = got
      List.reverse(&2, Run, keep_last(pending, last, acc))
    case Con{Job{+s, +pts}, rest}:
      (perm, +last) = got
      leaf_loop(rest, site_run(painted(TileWorld.node_of(s)), TileWorld.node_of(s), pts, perm, w), True{}, w,
        keep_last(pending, last, acc))

def par_runs(+d: Nat, +jobs: List<&2, Job>, +n: Nat, +w: U32) -> List<&2, Run>:
  match d:
    case 0n:
      leaf_loop(jobs, (Perlin.permutation(), Strokes{Nil{}}), False{}, w, Nil{})
    case 1n+p:
      +half = Nat.div(n, 2n)
      a b = par_runs(p, List.take(&2, Job, jobs, half), half, w) par_runs(p, List.drop(&2, Job, jobs, half), Nat.sub(n, half), w)
      List.append(&2, Run, a, b)

def write_strokes(ss: List<&2, Stroke>, cells: Array<U32>) -> Array<U32>:
  match ss:
    case Nil{}:
      cells
    case Con{Stroke{+i, +tile}, rest}:
      write_strokes(rest, write(cells, i, tile))

def write_points(pts: List<&2, U32>, cells: Array<U32>, +w: U32, +tile: U32) -> Array<U32>:
  match pts:
    case Nil{}:
      cells
    case Con{+p, rest}:
      write_points(rest, write(cells, cell_index(p, w), tile), w, tile)

def write_run(run: Run, cells: Array<U32>, +w: U32) -> Array<U32>:
  match run:
    case Direct{+tile, pts}:
      write_points(pts, cells, w, tile)
    case Strokes{ss}:
      write_strokes(ss, cells)

def write_all(runs: List<&2, Run>, cells: Array<U32>, +w: U32) -> Array<U32>:
  match runs:
    case Nil{}:
      cells
    case Con{+run, rest}:
      write_all(rest, write_run(run, cells, w), w)

def site_tiles_list(sites: List<&2, TileWorld.Site>) -> List<&2, SiteTiles.Counted>:
  match sites:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      SiteTiles.counted_site_tiles(s) <> site_tiles_list(rest)

def par_tiles(+d: Nat, +sites: List<&2, TileWorld.Site>, +n: Nat) -> List<&2, SiteTiles.Counted>:
  match d:
    case 0n:
      site_tiles_list(sites)
    case 1n+p:
      +half = Nat.div(n, 2n)
      a b = par_tiles(p, List.take(&2, TileWorld.Site, sites, half), half) par_tiles(p, List.drop(&2, TileWorld.Site, sites, half), Nat.sub(n, half))
      List.append(&2, SiteTiles.Counted, a, b)

def fresh_cells(g: Grid.Grid) -> Array<U32>:
  match g:
    case Grid.Grid{cells, _, _}:
      cells

def fork_depth() -> Nat:
  4n

# ConvertToTileMap's tile and flag maps, from each site's SiteTiles (site order): the painted cells of each site are
# resolved in parallel (noise included), then written in site order.
def paint(w: TileWorld.World, +lists: List<&2, List<&2, U32>>) -> Grid.Grid:
  match w:
    case TileWorld.World{+width, +height, _, +sites, _, _, _, _, _}:
      +jobs = jobs_of(sites, lists)
      Grid.Grid{write_all(par_runs(fork_depth(), jobs, List.length(&2, Job, jobs), width), fresh_cells(Grid.new(width, height, initial_cell())), width), width, height}

# The SiteTiles of every site with its size, in site order (computed in parallel).
def counted_site_tiles(w: TileWorld.World) -> List<&2, SiteTiles.Counted>:
  match w:
    case TileWorld.World{_, _, _, +sites, _, _, _, _, _}:
      par_tiles(fork_depth(), sites, List.length(&2, TileWorld.Site, sites))

def lists_of(counted: List<&2, SiteTiles.Counted>) -> List<&2, List<&2, U32>>:
  match counted:
    case Nil{}:
      Nil{}
    case Con{SiteTiles.Counted{+tiles, _}, rest}:
      tiles <> lists_of(rest)

def sizes_of(counted: List<&2, SiteTiles.Counted>) -> List<&2, U32>:
  match counted:
    case Nil{}:
      Nil{}
    case Con{SiteTiles.Counted{_, +count}, rest}:
      count <> sizes_of(rest)

# The SiteTiles of every site, in site order (computed in parallel).
def site_tiles(w: TileWorld.World) -> List<&2, List<&2, U32>>:
  lists_of(counted_site_tiles(w))

def convert(+w: TileWorld.World) -> Grid.Grid:
  paint(w, site_tiles(w))
