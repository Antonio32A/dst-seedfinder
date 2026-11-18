import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../lua/util.bend as LuaUtil
import ../data/blob.bend as Blob
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../data/distribute.bend as Distribute
import ../data/ocean.bend as OceanData
import ../data/ocean_post.bend as OceanPostData
import ../f64/repr.bend as F64Repr
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../populate/entities.bend as Entities
import ../populate/counts.bend as PopulateCounts
import ../populate/setpiece.bend as PopulateSetpiece
import ./ents.bend as OceanEnts
import ./state.bend as OceanState
import ./place.bend as OceanPlace
import ../data/builds.bend as Builds

# ocean_gen.lua's PopulateOcean: for each ocean room of the level (Shore, Coastal, Swell, Rough, Hazardous) on its
# tile, PopulateWaterType: the room's set pieces (Ocean_PlaceSetPieces), the countprefabs point search
# (GetRandomWaterPoints; the default rooms' countprefabs are empty, so it only draws), and the distribute scan over
# the tiles at least OCEAN_POPULATION_EDGE_DIST from the edge: math.random() < distributepercent, pickspawnprefab,
# PopulateWorld_AddEntity with the random offset.

def specs_loop(xs: List<&2, U32>) -> List<&2, OceanPlace.Spec>:
  match xs:
    case Con{_, Con{+kind, Con{+value, Con{+layout, rest}}}}:
      OceanPlace.Spec{layout, kind, value} <> specs_loop(rest)
    case _:
      Nil{}

# A room's depth-1 countstaticlayouts as set piece entries.
def room_specs(+build: Builds.Build, +room: U32) -> List<&2, OceanPlace.Spec>:
  specs_loop(Rooms.room_countstaticlayouts(build, (room * 2 : U32)))

def prefill_loop(xs: List<&2, U32>) -> List<&2, OceanPlace.Spec>:
  match xs:
    case Con{+layout, Con{+count, rest}}:
      OceanPlace.Spec{layout, 0, count} <> prefill_loop(rest)
    case _:
      Nil{}

# level.ocean_prefill_setpieces as set piece entries.
def prefill_specs(+build: Builds.Build) -> List<&2, OceanPlace.Spec>:
  prefill_loop(Tasks.lists(build, 5))

# GetRandomWaterPoints' scan state: points found so far, the wrapped start and extents, the step and the tile.
type Points is Data:
  Points{found: U32, sx: U32, sy: U32, w: U32, h: U32, inc: U32, edge: U32, tile: U32, needed: U32}

def found_of(+p: Points) -> U32:
  match p:
    case Points{+found, _, _, _, _, _, _, _, _}:
      found

def with_found(+p: Points, +found: U32) -> Points:
  match p:
    case Points{_, +sx, +sy, +w, +h, +inc, +edge, +tile, +needed}:
      Points{found, sx, sy, w, h, inc, edge, tile, needed}

def point_counted(got: Grid.Grid & Bool, +p: Points) -> Grid.Grid & Points:
  (g, +ok) = got
  (g, with_found(p, (found_of(p) + Bool.to_u32(ok) : U32)))

def point_step(go: Bool, g: Grid.Grid, +x: U32, +y: U32, +p: Points) -> Grid.Grid & Points:
  match go:
    case False{}:
      (g, p)
    case True{}:
      match p:
        case Points{_, _, _, _, _, _, _, +tile, _}:
          point_counted(OceanPlace.check(g, x, y, tile), p)

def point_cols(n: Nat, got: Grid.Grid & Points, +y: U32, +i: U32) -> Grid.Grid & Points:
  match n:
    case 0n:
      got
    case 1n+k:
      (g, +p) = got
      match p:
        case Points{+found, +sx, +sy, +w, +h, +inc, +edge, +tile, +needed}:
          +go = (i < w : U32) && (found < needed : U32)
          +x = (((sx + i) % w) + edge : U32)
          point_cols(k, point_step(go, g, x, y, p), y, (i + inc : U32))

def point_row(go: Bool, g: Grid.Grid, +y: U32, +p: Points, +cols: Nat) -> Grid.Grid & Points:
  match go:
    case False{}:
      (g, p)
    case True{}:
      point_cols(cols, (g, p), y, 0)

def point_rows(n: Nat, got: Grid.Grid & Points, +j: U32, +cols: Nat) -> Grid.Grid & Points:
  match n:
    case 0n:
      got
    case 1n+k:
      (g, +p) = got
      match p:
        case Points{+found, +sx, +sy, +w, +h, +inc, +edge, +tile, +needed}:
          +go = (j < h : U32) && (found < needed : U32)
          +y = (((sy + j) % h) + edge : U32)
          point_rows(k, point_row(go, g, y, p, cols), (j + inc : U32), cols)

def with_rng(got: Grid.Grid & Points, rng: Pcg.Rng) -> Grid.Grid & Points & Pcg.Rng:
  (g, +p) = got
  (g, p, rng)

def start_y(got: U32 & Pcg.Rng, +sx: U32, g: Grid.Grid, +p: Points) -> Grid.Grid & Points & Pcg.Rng:
  (+sy, rng) = got
  match p:
    case Points{+found, _, _, +w, +h, +inc, +edge, +tile, +needed}:
      +cols = U32.to_nat(((w + inc - 1) / inc : U32))
      with_rng(point_rows(U32.to_nat(((h + inc - 1) / inc : U32)), (g, Points{found, sx, sy, w, h, inc, edge, tile, needed}), 0, cols), rng)

def start_x(got: U32 & Pcg.Rng, g: Grid.Grid, +p: Points) -> Grid.Grid & Points & Pcg.Rng:
  (+sx, rng) = got
  match p:
    case Points{_, _, _, _, +h, _, _, _, _}:
      start_y(MathRandom.random_range(rng, 0, h), sx, g, p)

def with_inc(+p: Points, +inc: U32) -> Points:
  match p:
    case Points{+found, +sx, +sy, +w, +h, _, +edge, +tile, +needed}:
      Points{found, sx, sy, w, h, inc, edge, tile, needed}

def inc_step(more: Bool, g: Grid.Grid, +p: Points, +inc: U32, rng: Pcg.Rng) -> Grid.Grid & Points & Pcg.Rng:
  match more:
    case False{}:
      (g, p, rng)
    case True{}:
      match p:
        case Points{_, _, _, +w, _, _, _, _, _}:
          start_x(MathRandom.random_range(rng, 0, w), g, with_inc(p, inc))

def incs_loop(incs: List<&2, U32>, got: Grid.Grid & Points & Pcg.Rng) -> Grid.Grid & Points & Pcg.Rng:
  match incs:
    case Nil{}:
      got
    case Con{+inc, rest}:
      (g, +p, rng) = got
      match p:
        case Points{+found, _, _, _, _, _, _, _, +needed}:
          incs_loop(rest, inc_step((found < needed : U32), g, p, inc, rng))

def shuffle_rng(sh: LuaUtil.Shuffled) -> Pcg.Rng:
  match sh:
    case LuaUtil.Shuffled{_, rng}:
      rng

def shuffled_points(got: Grid.Grid & Points & Pcg.Rng) -> Grid.Grid & Pcg.Rng:
  (g, +p, rng) = got
  +n = found_of(p)
  (g, shuffle_rng(LuaUtil.shuffle_array([0 : U32^6n], n, rng)))

# GetRandomWaterPoints(tile, width, height, edge, needed) as far as the draws go: the scans at each increment while
# fewer than `needed` points are found (2 draws each), then shuffleArray over the points.
def water_points(+build: Builds.Build, g: Grid.Grid, +width: U32, +height: U32, +edge: U32, +tile: U32, +needed: U32, rng: Pcg.Rng) -> Grid.Grid & Pcg.Rng:
  +w = (width - 2 * edge : U32)
  +h = (height - 2 * edge : U32)
  shuffled_points(incs_loop(OceanPostData.water_point_incs(build, 0), (g, Points{0, 0, 0, w, h, 1, edge, tile, needed}, rng)))

# The distribute scan's constants: the room's tile, the math.random() < distributepercent threshold and
# pickspawnprefab's items (data/distribute.bend ocean_picks units, in its order).
type Dist is Data:
  Dist{tile: U32, threshold: U32, units: List<&2, U32>}

def jittered(+c: OceanState.Ctx, +e: Entities.Ent, g: Grid.Grid, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  match e:
    case Entities.Ent{+prefab, +tx, +ty, +x, +z, _, _, +rng}:
      OceanState.noted(c, OceanState.Sea{g, ids, rng, OceanEnts.Ent{prefab, x, z, 0, 0, 0} <> ents, topo, events}, OceanState.EAdd{prefab, tx, ty, x, z, rng})

def reserved_add(got: Grid.Grid & Bool, +c: OceanState.Ctx, +prefab: U32, +x: U32, +y: U32, ids: Grid.Grid, rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (g, _) = got
  jittered(c, Entities.entity(prefab, F64Repr.from_u32(x), F64Repr.from_u32(y), OceanState.width_of(c), OceanState.height_of(c), True{}, rng), g, ids, ents, topo, events)

def add_if(some: Bool, g: Grid.Grid, +c: OceanState.Ctx, +prefab: U32, +x: U32, +y: U32, ids: Grid.Grid, rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  match some:
    case False{}:
      OceanState.Sea{g, ids, rng, ents, topo, events}
    case True{}:
      reserved_add(Points.reserve_tile(g, x, y), c, prefab, x, y, ids, rng, ents, topo, events)

def picked(got: U32 & Pcg.Rng, g: Grid.Grid, +c: OceanState.Ctx, +x: U32, +y: U32, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (+prefab, rng) = got
  add_if(U32.is_ne(prefab, OceanPlace.none()), g, c, prefab, x, y, ids, rng, ents, topo, events)

def below(+build: Builds.Build, yes: Bool, g: Grid.Grid, +c: OceanState.Ctx, +d: Dist, +x: U32, +y: U32, ids: Grid.Grid, rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  match yes:
    case False{}:
      OceanState.Sea{g, ids, rng, ents, topo, events}
    case True{}:
      match d:
        case Dist{_, _, +units}:
          picked(PopulateCounts.pick_units(build, units, rng), g, c, x, y, ids, ents, topo, events)

def drawn(+build: Builds.Build, got: U32 & Pcg.Rng, g: Grid.Grid, +c: OceanState.Ctx, +d: Dist, +x: U32, +y: U32, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (+r, rng) = got
  match d:
    case Dist{+tile, +threshold, +units}:
      below(build, (r < threshold : U32), g, c, Dist{tile, threshold, units}, x, y, ids, rng, ents, topo, events)

def lo_after(cand: Bool, +lo: U32) -> U32:
  match cand:
    case True{}:
      Pcg.step_lo(lo)
    case False{}:
      lo

def hi_after(cand: Bool, +hi: U32, +lo: U32) -> U32:
  match cand:
    case True{}:
      Pcg.step_hi(hi, lo)
    case False{}:
      hi

def below_threshold(cand: Bool, +hi: U32, +lo: U32, +threshold: U32) -> Bool:
  match cand:
    case True{}:
      (Pcg.output(hi, lo) < threshold : U32)
    case False{}:
      False{}

# Where a row scan stopped: the next cell to scan and the cells left in the row, the RNG words, and whether it
# stopped at a hit (the cell before `at`) rather than the row's end.
type Seek is Data:
  Seek{at: U32, left: U32, hi: U32, lo: U32, hit: Bool}

# The row scan from cell `at` (got holds its value) over `n` cells: each cell holding `tile` takes one draw, and the
# scan stops after the first draw below the threshold (`hit`).
def seek_cols(n: Nat, +hit: Bool, got: Array<U32> & U32, +at: U32, +hi: U32, +lo: U32, +tile: U32, +threshold: U32) -> Array<U32> & Seek:
  match n:
    case 0n:
      (cells, _) = got
      (cells, Seek{at, 0, hi, lo, hit})
    case 1n+p:
      match hit:
        case True{}:
          (cells, _) = got
          (cells, Seek{at, (U32.from_nat(p) + 1 : U32), hi, lo, True{}})
        case False{}:
          (cells, +v) = got
          +cand = U32.is_eq(Grid.tile_of(v), tile)
          seek_cols(p, below_threshold(cand, hi, lo, threshold), cells[(at + 1 : U32)], (at + 1 : U32), hi_after(cand, hi, lo), lo_after(cand, lo), tile, threshold)

# The distribute scan's position: the row y, the next cell and the cells left in that row, and whether the window
# is done.
type Scan is Data:
  Scan{y: U32, at: U32, left: U32, done: Bool}

# The window's columns and last row.
type DistWindow is Data:
  DistWindow{edge: U32, cols: U32, last: U32}

def row_start(+y: U32, +w: U32, +win: DistWindow) -> Scan:
  match win:
    case DistWindow{+edge, +cols, +last}:
      Scan{y, (y * w + edge : U32), cols, (y > last : U32)}

def sought(+build: Builds.Build, got: Array<U32> & Seek, +w: U32, +h: U32, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>, +c: OceanState.Ctx, +d: Dist, +y: U32, +win: DistWindow) -> OceanState.Sea & Scan:
  (cells, sk) = got
  match sk:
    case Seek{+at, +left, +hi, +lo, +hit}:
      match hit:
        case True{}:
          +x = ((at - 1 : U32) - y * w : U32)
          (below(build, True{}, Grid.Grid{cells, w, h}, c, d, x, y, ids, Pcg.Rng{hi, lo}, ents, topo, events), Scan{y, at, left, False{}})
        case False{}:
          (OceanState.Sea{Grid.Grid{cells, w, h}, ids, Pcg.Rng{hi, lo}, ents, topo, events}, row_start((y + 1 : U32), w, win))

def dist_cells(+build: Builds.Build, g: Grid.Grid, ids: Grid.Grid, +hi: U32, +lo: U32, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>, +sc: Scan, +c: OceanState.Ctx, +d: Dist, +win: DistWindow) -> OceanState.Sea & Scan:
  match g:
    case Grid.Grid{cells, +w, +h}:
      match sc:
        case Scan{+y, +at, +left, _}:
          match d:
            case Dist{+tile, +threshold, +units}:
              sought(build, seek_cols(U32.to_nat(left), False{}, cells[at], at, hi, lo, tile, threshold), w, h, ids, ents, topo, events, c, Dist{tile, threshold, units}, y, win)

def dist_step(+build: Builds.Build, s: OceanState.Sea, +sc: Scan, +c: OceanState.Ctx, +d: Dist, +win: DistWindow) -> OceanState.Sea & Scan:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      match rng:
        case Pcg.Rng{+hi, +lo}:
          dist_cells(build, g, ids, hi, lo, ents, topo, events, sc, c, d, win)

def dist_loop(+build: Builds.Build, n: Nat, got: OceanState.Sea & Scan, +c: OceanState.Ctx, +d: Dist, +win: DistWindow) -> OceanState.Sea:
  match n:
    case 0n:
      (s, _) = got
      s
    case 1n+p:
      (s, +sc) = got
      match sc:
        case Scan{+y, +at, +left, +done}:
          match done:
            case True{}:
              s
            case False{}:
              dist_loop(build, p, dist_step(build, s, Scan{y, at, left, done}, c, d, win), c, d, win)

def dist_start(+build: Builds.Build, +w: U32, +h: U32, s: OceanState.Sea, +c: OceanState.Ctx, +d: Dist) -> OceanState.Sea:
  +edge = OceanPostData.ocean_population_edge_dist(build)
  +cols = (w - 2 * edge : U32)
  +rows = (h - 2 * edge : U32)
  +win = {DistWindow{edge, cols, (h - edge - 1 : U32)} : DistWindow}
  dist_loop(build, U32.to_nat((rows * (cols + 1) + 1 : U32)), (s, Scan{edge, (edge * w + edge : U32), cols, U32.is_zero(rows)}), c, d, win)

# The distribute scan: y = edge .. height - edge - 1, x = edge .. width - edge - 1, row-major, one draw per tile
# holding the room's tile; ReserveTile does not change tiles, so the scan reads the map the draws update.
def distribute(+build: Builds.Build, +c: OceanState.Ctx, +d: Dist, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      match g:
        case Grid.Grid{cells, +w, +h}:
          dist_start(build, w, h, OceanState.Sea{Grid.Grid{cells, w, h}, ids, rng, ents, topo, events}, c, d)

def distribute_if(+build: Builds.Build, on: Bool, +c: OceanState.Ctx, +d: Dist, s: OceanState.Sea) -> OceanState.Sea:
  match on:
    case False{}:
      s
    case True{}:
      distribute(build, c, d, s)

def count_sum(xs: List<&2, U32>, +acc: U32) -> U32:
  match xs:
    case Con{_, Con{_, Con{+value, rest}}}:
      count_sum(rest, (acc + value : U32))
    case _:
      acc

def points_done(got: Grid.Grid & Pcg.Rng, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (g, +rng) = got
  OceanState.Sea{g, ids, rng, ents, topo, events}

def points_if(+build: Builds.Build, on: Bool, +c: OceanState.Ctx, +room: U32, +tile: U32, s: OceanState.Sea) -> OceanState.Sea:
  match on:
    case False{}:
      s
    case True{}:
      match s:
        case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
          +needed = (2 * count_sum(Rooms.room_countprefabs(build, (room * 2 : U32)), 0) + 10 : U32)
          points_done(water_points(build, g, OceanState.width_of(c), OceanState.height_of(c), OceanPostData.ocean_population_edge_dist(build), tile, needed, rng), ids, ents, topo, events)

def pieces_if(+build: Builds.Build, some: Bool, +c: OceanState.Ctx, +specs: List<&2, OceanPlace.Spec>, +tile: U32, s: OceanState.Sea) -> OceanState.Sea:
  match some:
    case False{}:
      s
    case True{}:
      OceanPlace.place_set_pieces(build, specs, c, tile, OceanData.config_ocean_prefill_setpieces_min_land_dist(), PopulateSetpiece.ocean_room(), s)

def picks_of(+build: Builds.Build, +i: U32) -> List<&2, U32>:
  Blob.drop(Distribute.ocean_picks(build, i), 2)

# PopulateWaterType for the i-th ocean room of the level.
def water_type(+build: Builds.Build, +c: OceanState.Ctx, +room: U32, +i: U32, s: OceanState.Sea) -> OceanState.Sea:
  +tile = Rooms.value(build, room)
  +specs = room_specs(build, room)
  placed = pieces_if(build, Bool.not(List.is_empty(&2, OceanPlace.Spec, specs)), c, specs, tile, s)
  pointed = points_if(build, Rooms.has(build, room, Rooms.flag_countprefabs(build)), c, room, tile, placed)
  +on = Rooms.has(build, room, Rooms.flag_distribute_percent(build)) && Rooms.has(build, room, Rooms.flag_distributeprefabs(build))
  distribute_if(build, on, c, Dist{tile, Rooms.distribute_threshold(build, room), picks_of(build, i)}, pointed)

def rooms_loop(+build: Builds.Build, rooms: List<&2, U32>, +c: OceanState.Ctx, +i: U32, s: OceanState.Sea) -> OceanState.Sea:
  match rooms:
    case Nil{}:
      s
    case Con{+room, rest}:
      rooms_loop(build, rest, c, (i + 1 : U32), water_type(build, c, room, i, s))

# PopulateOcean(SpawnFunctions, entities, width, height, storygen.ocean_population) for the level's ocean rooms.
def populate(+build: Builds.Build, +c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  rooms_loop(build, Tasks.lists(build, 9), c, 0, s)
