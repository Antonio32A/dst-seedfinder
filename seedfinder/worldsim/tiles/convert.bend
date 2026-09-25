import Base
import ../../f64/repr.bend as FR
import ../../f64/cmp.bend as FC
import ../../data/blob.bend as B
import ../../data/ocean.bend as OC
import ../grid.bend as GR
import ../noise/perlin.bend as NP
import ./groups.bend as TG
import ./table.bend as TB
import ./world.bend as TW
import ./sitetiles.bend as TT

# ConvertToTileMap (tiles.cpp) after its Voronoi rebuild: every cell impassable with flags 0x90ff (the variant nibble
# is drawn, W * H bounded(16) draws, but not stored: see GR), then each painted site's SiteTiles in site order, later
# sites overwriting earlier ones. Noise tiles resolve through forest_map.lua's GetTileForNoiseTile at
# ImprovedNoise(x / 8, y / 8, 0).

type Step is Data:
  Step{threshold: FR.F64, above: U32}

# A noise tile's threshold table: `first` below the first threshold, then each step's tile from its threshold on.
type Resolver is Data:
  Resolver{first: U32, steps: List<&2, Step>}

def step_of(bits: U32 & U32, +above: U32) -> Step:
  (+hi, +lo) = bits
  Step{FR.F64{hi, lo}, above}

def steps_of(n: Nat, +row: List<&2, U32>) -> List<&2, Step>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      step_of(B.f64(row, 0), B.at(row, 4)) <> steps_of(p, B.drop(row, 5))

def resolver_of(+row: List<&2, U32>) -> Resolver:
  Resolver{B.at(row, 1), steps_of(U32.to_nat(B.at(row, 2)), B.drop(row, 3))}

def row_for(n: Nat, +tile: U32, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      OC.noise_functions(i)
    case 1n+p:
      +row = OC.noise_functions(i)
      +head = B.at(row, 0)
      Bool.pick(List<&2, U32>, U32.is_eq(head, tile) || B.is_none(head), row, row_for(p, tile, (i + 1 : U32)))

# The table GetTileForNoiseTile uses for `tile` (NoiseTileFunctions[tile] or the default).
def resolver(+tile: U32) -> Resolver:
  resolver_of(row_for(U32.to_nat(OC.noise_functions_count()), tile, 0))

# GetTileForNoiseTile(tile, noise) for the resolver of `tile`.
def resolve_steps(steps: List<&2, Step>, +noise: FR.F64, +tile: U32) -> U32:
  match steps:
    case Nil{}:
      tile
    case Con{Step{+threshold, +above}, rest}:
      Bool.pick(U32, FC.lt(noise, threshold), tile, resolve_steps(rest, noise, above))

def resolve(r: Resolver, +noise: FR.F64) -> U32:
  match r:
    case Resolver{+first, +steps}:
      resolve_steps(steps, noise, first)

def initial_cell() -> U32:
  GR.cell(TG.impassable(), 37119)

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
  +t = Bool.pick(U32, U32.is_eq(tile, TG.invalid()), TG.impassable(), tile)
  brush_pick(TG.is_noise(t), t)

# Whether ConvertToTileMap paints the site: not a Blank/Random node, and not a root.
def painted(n: TW.Node) -> Bool:
  match n:
    case TW.Node{_, +kind, _, _, _, +parent, _, _, _, _}:
      Bool.not(U32.is_eq((kind .&. 4294967293 : U32), 1)) && Bool.not(TW.is_none(parent))

def write_got(got: Array<U32> & U32, +i: U32, +tile: U32) -> Array<U32>:
  (cells, +old) = got
  cells[i] <- GR.cell(tile, (GR.flags_of(old) .&. 49151 : U32))

def write(cells: Array<U32>, +i: U32, +tile: U32) -> Array<U32>:
  write_got(cells[i], i, tile)

def cell_index(+p: U32, +w: U32) -> U32:
  GR.index(TT.unpack_x(p), TT.unpack_y(p), w)

# One painted cell: flat index and tile.
type Stroke is Data:
  Stroke{index: U32, tile: U32}

def solid_strokes(pts: List<&2, U32>, +w: U32, +tile: U32) -> List<&2, Stroke>:
  match pts:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      Stroke{cell_index(p, w), tile} <> solid_strokes(rest, w, tile)

def stroke_if(pending: Bool, +i: U32, +tile: U32, acc: List<&2, Stroke>) -> List<&2, Stroke>:
  match pending:
    case True{}:
      Stroke{i, tile} <> acc
    case False{}:
      acc

def noisy_strokes(pts: List<&2, U32>, got: Array<U32> & FR.F64, +prev: U32, +pending: Bool, +w: U32, +r: Resolver, acc: List<&2, Stroke>) -> Array<U32> & List<&2, Stroke>:
  match pts:
    case Nil{}:
      (perm, +n) = got
      (perm, List.reverse(&2, Stroke, stroke_if(pending, prev, resolve(r, n), acc)))
    case Con{+p, rest}:
      (perm, +n) = got
      noisy_strokes(rest, NP.noise_eighths(perm, TT.unpack_x(p), TT.unpack_y(p)),
        cell_index(p, w), True{}, w, r, stroke_if(pending, prev, resolve(r, n), acc))

def brush_strokes(b: Brush, +pts: List<&2, U32>, perm: Array<U32>, +w: U32) -> Array<U32> & List<&2, Stroke>:
  match b:
    case Solid{+tile}:
      (perm, solid_strokes(pts, w, tile))
    case Noisy{+r}:
      noisy_strokes(pts, (perm, FR.zero()), 0, False{}, w, r, Nil{})

def site_strokes(on: Bool, +n: TW.Node, +pts: List<&2, U32>, perm: Array<U32>, +w: U32) -> Array<U32> & List<&2, Stroke>:
  match on:
    case False{}:
      (perm, Nil{})
    case True{}:
      match n:
        case TW.Node{_, _, _, +tile, _, _, _, _, _, _}:
          brush_strokes(brush_of(tile), pts, perm, w)

type Job is Data:
  Job{site: TW.Site, tiles: List<&2, U32>}

def jobs_of(sites: List<&2, TW.Site>, lists: List<&2, List<&2, U32>>) -> List<&2, Job>:
  match sites:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      match lists:
        case Nil{}:
          Nil{}
        case Con{+pts, more}:
          Job{s, pts} <> jobs_of(rest, more)

def keep_last(pending: Bool, +last: List<&2, Stroke>, acc: List<&2, List<&2, Stroke>>) -> List<&2, List<&2, Stroke>>:
  match pending:
    case True{}:
      last <> acc
    case False{}:
      acc

def leaf_loop(jobs: List<&2, Job>, got: Array<U32> & List<&2, Stroke>, +pending: Bool, +w: U32, acc: List<&2, List<&2, Stroke>>) -> List<&2, List<&2, Stroke>>:
  match jobs:
    case Nil{}:
      (_, +last) = got
      List.reverse(&2, List<&2, Stroke>, keep_last(pending, last, acc))
    case Con{Job{+s, +pts}, rest}:
      (perm, +last) = got
      leaf_loop(rest, site_strokes(painted(TW.node_of(s)), TW.node_of(s), pts, perm, w), True{}, w,
        keep_last(pending, last, acc))

def par_strokes(+d: Nat, +jobs: List<&2, Job>, +n: Nat, +w: U32) -> List<&2, List<&2, Stroke>>:
  match d:
    case 0n:
      leaf_loop(jobs, (NP.permutation(), Nil{}), False{}, w, Nil{})
    case 1n+p:
      +half = Nat.div(n, 2n)
      a b = par_strokes(p, List.take(&2, Job, jobs, half), half, w) par_strokes(p, List.drop(&2, Job, jobs, half), Nat.sub(n, half), w)
      List.append(&2, List<&2, Stroke>, a, b)

def write_strokes(ss: List<&2, Stroke>, cells: Array<U32>) -> Array<U32>:
  match ss:
    case Nil{}:
      cells
    case Con{Stroke{+i, +tile}, rest}:
      write_strokes(rest, write(cells, i, tile))

def write_all(sss: List<&2, List<&2, Stroke>>, cells: Array<U32>) -> Array<U32>:
  match sss:
    case Nil{}:
      cells
    case Con{+ss, rest}:
      write_all(rest, write_strokes(ss, cells))

def site_tiles_list(sites: List<&2, TW.Site>) -> List<&2, List<&2, U32>>:
  match sites:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      TT.site_tiles(s) <> site_tiles_list(rest)

def par_tiles(+d: Nat, +sites: List<&2, TW.Site>, +n: Nat) -> List<&2, List<&2, U32>>:
  match d:
    case 0n:
      site_tiles_list(sites)
    case 1n+p:
      +half = Nat.div(n, 2n)
      a b = par_tiles(p, List.take(&2, TW.Site, sites, half), half) par_tiles(p, List.drop(&2, TW.Site, sites, half), Nat.sub(n, half))
      List.append(&2, List<&2, U32>, a, b)

def fresh_cells(g: GR.Grid) -> Array<U32>:
  match g:
    case GR.Grid{cells, _, _}:
      cells

def fork_depth() -> Nat:
  4n

# ConvertToTileMap's tile and flag maps, from each site's SiteTiles (site order): the painted cells of each site are
# resolved in parallel (noise included), then written in site order.
def paint(w: TW.World, +lists: List<&2, List<&2, U32>>) -> GR.Grid:
  match w:
    case TW.World{+width, +height, _, +sites, _, _, _, _, _}:
      +jobs = jobs_of(sites, lists)
      GR.Grid{write_all(par_strokes(fork_depth(), jobs, List.length(&2, Job, jobs), width), fresh_cells(GR.new(width, height, initial_cell()))), width, height}

# The SiteTiles of every site, in site order (computed in parallel).
def site_tiles(w: TW.World) -> List<&2, List<&2, U32>>:
  match w:
    case TW.World{_, _, _, +sites, _, _, _, _, _}:
      par_tiles(fork_depth(), sites, List.length(&2, TW.Site, sites))

def convert(+w: TW.World) -> GR.Grid:
  paint(w, site_tiles(w))
