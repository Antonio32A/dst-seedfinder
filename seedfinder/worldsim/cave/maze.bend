import Base
import ../../f32/ops.bend as F32Ops
import ../../f32/powf.bend as Powf
import ../../rng/pcg.bend as Pcg
import ../grid.bend as Grid
import ../tiles/sitetiles.bend as SiteTiles
import ../tiles/world.bend as TileWorld
import ./cells.bend as CaveCells
import ./growing.bend as CaveGrowing
import ./meta.bend as CaveMeta
import ./sites.bend as CaveSites

# WorldSim:RunMaze (growing tree) and WorldSim:GetPointsForMetaMaze (Maze_ctor, Maze_Run, Maze_WriteTiles) on the site
# nodes' tile points. The maze grid covers the union bounding box of the sites' polygons; tiles inside a site (within 20
# of it) are the maze area. The results are the (x, y, key) points of the Lua wrapper: the float cell origin plus the box
# minimum, truncated to int, in ascending key order (key 0 for the growing tree's dead ends: the pandoraschest spots).

type Found is Data:
  Found{key: U32, x: U32, y: U32}

# RunMaze's result: the tile map with the maze written into it, the points and the PCG state.
type Ran is Type:
  Ran{grid: Grid.Grid, found: List<&2, Found>, rng: Pcg.Rng}

# GetPointsForMetaMaze's result.
type Mapped is Data:
  Mapped{found: List<&2, Found>, rng: Pcg.Rng}

# The maze grid's origin, float extent and size in tiles.
type Frame is Data:
  Frame{minx: F32, miny: F32, dx: F32, dy: F32, w: U32, h: U32}

def frame_of(b: SiteTiles.Box) -> Frame:
  match b:
    case SiteTiles.Box{+minx, +maxx, +miny, +maxy}:
      Frame{minx, miny, (maxx - minx : F32), (maxy - miny : F32), SiteTiles.trunc_wrap((maxx - minx : F32)), SiteTiles.trunc_wrap((maxy - miny : F32))}

def sampled(+extent: F32, +cs: U32) -> U32:
  SiteTiles.trunc_wrap((extent * F32Ops.div(1.0, U32.to_f32(cs)) : F32))

# The maze area written into a fresh grid: every cell a wall of value `lo` and flags 0xcf, and the site tiles a maze
# cell (value 4, "not maze" flag cleared).
def mark_area(pts: List<&2, U32>, cells: Array<U32>, +f: Frame) -> Array<U32>:
  match pts:
    case Nil{}:
      cells
    case Con{+p, rest}:
      match f:
        case Frame{+minx, +miny, _, _, +w, _}:
          cells[CaveCells.index(F32Ops.to_i32((U32.to_f32(SiteTiles.unpack_x(p)) - minx : F32)), F32Ops.to_i32((U32.to_f32(SiteTiles.unpack_y(p)) - miny : F32)), w)] <- 36612
          mark_area(rest, cells, f)

def area_fill(+mtype: U32) -> U32:
  Bool.pick(U32, (mtype < 3 : U32), 52996, 52994)

def area_of(pts: List<&2, U32>, +mtype: U32, +f: Frame) -> Array<U32>:
  match f:
    case Frame{_, _, _, _, +w, +h}:
      mark_area(pts, CaveCells.new(w, h, area_fill(mtype)), f)

def found_add(+key: U32, +p: U32, +cs: U32, +f: Frame, rest: List<&2, Found>) -> List<&2, Found>:
  match f:
    case Frame{+minx, +miny, _, _, _, _}:
      Found{key, F32Ops.to_i32((U32.to_f32((SiteTiles.unpack_x(p) * cs : U32)) + minx : F32)), F32Ops.to_i32((U32.to_f32((SiteTiles.unpack_y(p) * cs : U32)) + miny : F32))} <> rest

def dead_found(dead: List<&2, U32>, +cs: U32, +f: Frame) -> List<&2, Found>:
  match dead:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      found_add(0, p, cs, f, dead_found(rest, cs, f))

def k_cell(+k: CaveMeta.Keyed) -> U32:
  match k:
    case CaveMeta.Keyed{_, +cell}:
      cell

def keyed_found(points: List<&2, CaveMeta.Keyed>, +cs: U32, +f: Frame) -> List<&2, Found>:
  match points:
    case Nil{}:
      Nil{}
    case Con{+k, rest}:
      found_add(CaveMeta.key_of(k), k_cell(k), cs, f, keyed_found(rest, cs, f))

def put_tile(got: Grid.Grid & U32, +i: U32, +tile: U32) -> Grid.Grid:
  (g, +old) = got
  Grid.put(g, i, Grid.cell(tile, Grid.flags_of(old)))

def tile_for(+c: U32, +invert: Bool, +tile_a: U32, +tile_b: U32) -> U32:
  Bool.pick(U32, Bool.pick(Bool, invert, U32.is_eq(c, 1), U32.is_eq(c, 2)), tile_b, tile_a)

def write_tile(write: Bool, g: Grid.Grid, +p: U32, +tw: U32, +tile: U32) -> Grid.Grid:
  match write:
    case True{}:
      put_tile(Grid.get(g, Grid.index(SiteTiles.unpack_x(p), SiteTiles.unpack_y(p), tw)), Grid.index(SiteTiles.unpack_x(p), SiteTiles.unpack_y(p), tw), tile)
    case False{}:
      g

def write_cell(got: Array<U32> & U32, g: Grid.Grid, +inside: Bool, +p: U32, +tw: U32, +invert: Bool, +tile_a: U32, +tile_b: U32) -> Array<U32> & Grid.Grid:
  (cells, +c) = got
  (cells, write_tile(inside && Bool.not(U32.is_eq(CaveCells.lo_of(c), 4)), g, p, tw, tile_for(CaveCells.lo_of(c), invert, tile_a, tile_b)))

def in_range(+v: F32, +limit: U32) -> Bool:
  (0.0 <= v : F32) && (v < U32.to_f32(limit) : F32)

# Maze_WriteTiles for the tile point p: the maze cell's value picks the path tile (`tile_b`) or the wall tile.
def write_point(cells: Array<U32>, g: Grid.Grid, +p: U32, +f: Frame, +tw: U32, +th: U32, +invert: Bool, +tile_a: U32, +tile_b: U32) -> Array<U32> & Grid.Grid:
  match f:
    case Frame{+minx, +miny, _, _, +w, +h}:
      +fx = (U32.to_f32(SiteTiles.unpack_x(p)) - minx : F32)
      +fy = (U32.to_f32(SiteTiles.unpack_y(p)) - miny : F32)
      +inside = in_range(fx, w) && in_range(fy, h) && (SiteTiles.unpack_x(p) < tw : U32) && (SiteTiles.unpack_y(p) < th : U32)
      write_cell(cells[Bool.pick(U32, inside, CaveCells.index(F32Ops.to_i32(fx), F32Ops.to_i32(fy), w), 0)], g, inside, p, tw, invert, tile_a, tile_b)

def write_points(pts: List<&2, U32>, got: Array<U32> & Grid.Grid, +f: Frame, +tw: U32, +th: U32, +invert: Bool, +tile_a: U32, +tile_b: U32) -> Array<U32> & Grid.Grid:
  match pts:
    case Nil{}:
      got
    case Con{+p, rest}:
      (cells, g) = got
      write_points(rest, write_point(cells, g, p, f, tw, th, invert, tile_a, tile_b), f, tw, th, invert, tile_a, tile_b)

def written(got: Array<U32> & Grid.Grid) -> Grid.Grid:
  (_, g) = got
  g

# The RunMaze arguments: the maze type (3 = growing tree with the strict carve test), val (-3..7, as a two's complement U32),
# the wall tile and the path tile.
type Params is Data:
  Params{windows: Bool, mtype: U32, val: U32, tile_a: U32, tile_b: U32}

def ran_of(gr: CaveGrowing.Grown, world: Grid.Grid, pts: List<&2, U32>, +f: Frame, +p: Params) -> Ran:
  match gr:
    case CaveGrowing.Grown{cells, dead, rng}:
      match world:
        case Grid.Grid{wcells, +tw, +th}:
          match p:
            case Params{_, +mtype, _, +tile_a, +tile_b}:
              Ran{written(write_points(pts, (cells, Grid.Grid{wcells, tw, th}), f, tw, th, U32.is_eq(mtype, 5), tile_a, tile_b)), dead_found(dead, 2, f), rng}

def run_framed(+pts: List<&2, U32>, world: Grid.Grid, rng: Pcg.Rng, +f: Frame, +p: Params) -> Ran:
  match f:
    case Frame{_, _, +dx, +dy, +w, _}:
      match p:
        case Params{+windows, +mtype, +val, _, _}:
          ran_of(CaveGrowing.grow(windows, area_of(pts, mtype, f), w, sampled(dx, 2), sampled(dy, 2), 2, Powf.maze_exponent(val), U32.is_eq(mtype, 3), rng),
            world, pts, f, p)

def run_boxed(+b: SiteTiles.Box, +sites: List<&2, TileWorld.Site>, world: Grid.Grid, rng: Pcg.Rng, +p: Params) -> Ran:
  run_framed(CaveSites.tiles(sites, b), world, rng, frame_of(b), p)

# WorldSim:RunMaze(mazetype, val, tile_a, tile_b, nodes) for the growing-tree types (3..5) on the tile and flag map
# `world`, with `sites` the nodes' sites in table order (unknown node ids left out; at least one site). `windows` selects the Windows RAND_MAX,
# shuffle and powf. The DFS types (1, 2) no Lua caller uses are not implemented.
def run_maze(+p: Params, +sites: List<&2, TileWorld.Site>, world: Grid.Grid, rng: Pcg.Rng) -> Ran:
  run_boxed(CaveSites.box_of(sites, CaveSites.empty_box()), sites, world, rng, p)

def meta_found(m: CaveMeta.Meta, +cs: U32, +f: Frame) -> Mapped:
  match m:
    case CaveMeta.Meta{points, rng}:
      Mapped{keyed_found(points, cs, f), rng}

def mapped(+pts: List<&2, U32>, rng: Pcg.Rng, +windows: Bool, +cs: U32, +f: Frame) -> Mapped:
  match f:
    case Frame{_, _, +dx, +dy, +w, _}:
      meta_found(CaveMeta.meta_maze(windows, area_of(pts, 0, f), w, sampled(dx, cs), sampled(dy, cs), cs, rng), cs, f)

def meta_boxed(+b: SiteTiles.Box, +sites: List<&2, TileWorld.Site>, rng: Pcg.Rng, +windows: Bool, +cs: U32) -> Mapped:
  mapped(CaveSites.tiles(sites, b), rng, windows, cs, frame_of(b))

# WorldSim:GetPointsForMetaMaze(cell_size, nodes): the cells of the walk with their open sides as the key (negative for
# a surviving dead end). The tile map is not touched.
def meta_maze(+windows: Bool, +cs: U32, +sites: List<&2, TileWorld.Site>, rng: Pcg.Rng) -> Mapped:
  meta_boxed(CaveSites.box_of(sites, CaveSites.empty_box()), sites, rng, windows, cs)
