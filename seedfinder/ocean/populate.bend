import Base
import ../rng/pcg.bend as R
import ../lua/math_random.bend as LM
import ../lua/util.bend as LU
import ../data/blob.bend as B
import ../data/rooms.bend as RM
import ../data/tasks.bend as TK
import ../data/distribute.bend as DS
import ../data/ocean.bend as OC
import ../data/ocean_post.bend as OQ
import ../f64/repr.bend as FR
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../populate/entities.bend as PE
import ../populate/counts.bend as PC
import ./ents.bend as OE
import ./state.bend as OS
import ./place.bend as OP

# ocean_gen.lua's PopulateOcean: for each ocean room of the level (Shore, Coastal, Swell, Rough, Hazardous) on its
# tile, PopulateWaterType: the room's set pieces (Ocean_PlaceSetPieces), the countprefabs point search
# (GetRandomWaterPoints; the default rooms' countprefabs are empty, so it only draws), and the distribute scan over
# the tiles at least OCEAN_POPULATION_EDGE_DIST from the edge: math.random() < distributepercent, pickspawnprefab,
# PopulateWorld_AddEntity with the random offset.

def specs_loop(xs: List<&2, U32>) -> List<&2, OP.Spec>:
  match xs:
    case Con{_, Con{+kind, Con{+value, Con{+layout, rest}}}}:
      OP.Spec{layout, kind, value} <> specs_loop(rest)
    case _:
      Nil{}

# A room's depth-1 countstaticlayouts as set piece entries.
def room_specs(+room: U32) -> List<&2, OP.Spec>:
  specs_loop(RM.room_countstaticlayouts((room * 2 : U32)))

def prefill_loop(xs: List<&2, U32>) -> List<&2, OP.Spec>:
  match xs:
    case Con{+layout, Con{+count, rest}}:
      OP.Spec{layout, 0, count} <> prefill_loop(rest)
    case _:
      Nil{}

# level.ocean_prefill_setpieces as set piece entries.
def prefill_specs() -> List<&2, OP.Spec>:
  prefill_loop(TK.lists(5))

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

def point_counted(got: GR.Grid & Bool, +p: Points) -> GR.Grid & Points:
  (g, +ok) = got
  (g, with_found(p, (found_of(p) + Bool.to_u32(ok) : U32)))

def point_step(go: Bool, g: GR.Grid, +x: U32, +y: U32, +p: Points) -> GR.Grid & Points:
  match go:
    case False{}:
      (g, p)
    case True{}:
      match p:
        case Points{_, _, _, _, _, _, _, +tile, _}:
          point_counted(OP.check(g, x, y, tile), p)

def point_cols(n: Nat, got: GR.Grid & Points, +y: U32, +i: U32) -> GR.Grid & Points:
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

def point_row(go: Bool, g: GR.Grid, +y: U32, +p: Points, +cols: Nat) -> GR.Grid & Points:
  match go:
    case False{}:
      (g, p)
    case True{}:
      point_cols(cols, (g, p), y, 0)

def point_rows(n: Nat, got: GR.Grid & Points, +j: U32, +cols: Nat) -> GR.Grid & Points:
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

def with_rng(got: GR.Grid & Points, rng: R.Rng) -> GR.Grid & Points & R.Rng:
  (g, +p) = got
  (g, p, rng)

def start_y(got: U32 & R.Rng, +sx: U32, g: GR.Grid, +p: Points) -> GR.Grid & Points & R.Rng:
  (+sy, rng) = got
  match p:
    case Points{+found, _, _, +w, +h, +inc, +edge, +tile, +needed}:
      +cols = U32.to_nat(((w + inc - 1) / inc : U32))
      with_rng(point_rows(U32.to_nat(((h + inc - 1) / inc : U32)), (g, Points{found, sx, sy, w, h, inc, edge, tile, needed}), 0, cols), rng)

def start_x(got: U32 & R.Rng, g: GR.Grid, +p: Points) -> GR.Grid & Points & R.Rng:
  (+sx, rng) = got
  match p:
    case Points{_, _, _, _, +h, _, _, _, _}:
      start_y(LM.random_range(rng, 0, h), sx, g, p)

def with_inc(+p: Points, +inc: U32) -> Points:
  match p:
    case Points{+found, +sx, +sy, +w, +h, _, +edge, +tile, +needed}:
      Points{found, sx, sy, w, h, inc, edge, tile, needed}

def inc_step(more: Bool, g: GR.Grid, +p: Points, +inc: U32, rng: R.Rng) -> GR.Grid & Points & R.Rng:
  match more:
    case False{}:
      (g, p, rng)
    case True{}:
      match p:
        case Points{_, _, _, +w, _, _, _, _, _}:
          start_x(LM.random_range(rng, 0, w), g, with_inc(p, inc))

def incs_loop(incs: List<&2, U32>, got: GR.Grid & Points & R.Rng) -> GR.Grid & Points & R.Rng:
  match incs:
    case Nil{}:
      got
    case Con{+inc, rest}:
      (g, +p, rng) = got
      match p:
        case Points{+found, _, _, _, _, _, _, _, +needed}:
          incs_loop(rest, inc_step((found < needed : U32), g, p, inc, rng))

def shuffle_rng(sh: LU.Shuffled) -> R.Rng:
  match sh:
    case LU.Shuffled{_, rng}:
      rng

def shuffled_points(got: GR.Grid & Points & R.Rng) -> GR.Grid & R.Rng:
  (g, +p, rng) = got
  +n = found_of(p)
  (g, shuffle_rng(LU.shuffle_array([0 : U32^6n], n, rng)))

# GetRandomWaterPoints(tile, width, height, edge, needed) as far as the draws go: the scans at each increment while
# fewer than `needed` points are found (2 draws each), then shuffleArray over the points.
def water_points(g: GR.Grid, +width: U32, +height: U32, +edge: U32, +tile: U32, +needed: U32, rng: R.Rng) -> GR.Grid & R.Rng:
  +w = (width - 2 * edge : U32)
  +h = (height - 2 * edge : U32)
  shuffled_points(incs_loop(OQ.water_point_incs(0), (g, Points{0, 0, 0, w, h, 1, edge, tile, needed}, rng)))

# The distribute scan's constants: the room's tile, the math.random() < distributepercent threshold and
# pickspawnprefab's items (data/distribute.bend ocean_picks units, in its order).
type Dist is Data:
  Dist{tile: U32, threshold: U32, units: List<&2, U32>}

def jittered(+c: OS.Ctx, +e: PE.Ent, g: GR.Grid, ids: GR.Grid, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  match e:
    case PE.Ent{+prefab, +tx, +ty, +x, +z, _, _, +rng}:
      OS.noted(c, OS.Sea{g, ids, rng, OE.Ent{prefab, x, z, 0, 0} <> ents, topo, events}, OS.EAdd{prefab, tx, ty, x, z, rng})

def reserved_add(got: GR.Grid & Bool, +c: OS.Ctx, +prefab: U32, +x: U32, +y: U32, ids: GR.Grid, rng: R.Rng, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  (g, _) = got
  jittered(c, PE.entity(prefab, FR.from_u32(x), FR.from_u32(y), OS.width_of(c), OS.height_of(c), True{}, rng), g, ids, ents, topo, events)

def add_if(some: Bool, g: GR.Grid, +c: OS.Ctx, +prefab: U32, +x: U32, +y: U32, ids: GR.Grid, rng: R.Rng, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  match some:
    case False{}:
      OS.Sea{g, ids, rng, ents, topo, events}
    case True{}:
      reserved_add(PT.reserve_tile(g, x, y), c, prefab, x, y, ids, rng, ents, topo, events)

def picked(got: U32 & R.Rng, g: GR.Grid, +c: OS.Ctx, +x: U32, +y: U32, ids: GR.Grid, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  (+prefab, rng) = got
  add_if(U32.is_ne(prefab, OP.none()), g, c, prefab, x, y, ids, rng, ents, topo, events)

def below(yes: Bool, g: GR.Grid, +c: OS.Ctx, +d: Dist, +x: U32, +y: U32, ids: GR.Grid, rng: R.Rng, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  match yes:
    case False{}:
      OS.Sea{g, ids, rng, ents, topo, events}
    case True{}:
      match d:
        case Dist{_, _, +units}:
          picked(PC.pick_units(units, rng), g, c, x, y, ids, ents, topo, events)

def drawn(got: U32 & R.Rng, g: GR.Grid, +c: OS.Ctx, +d: Dist, +x: U32, +y: U32, ids: GR.Grid, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  (+r, rng) = got
  match d:
    case Dist{+tile, +threshold, +units}:
      below((r < threshold : U32), g, c, Dist{tile, threshold, units}, x, y, ids, rng, ents, topo, events)

def keep_cell(hit: Bool, +p: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      p <> acc
    case False{}:
      acc

def cand_cols(n: Nat, got: Array<U32> & U32, +i: U32, +x: U32, +y: U32, +tile: U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      (cells, _) = got
      (cells, acc)
    case 1n+p:
      (cells, +v) = got
      +next = keep_cell(U32.is_eq(GR.tile_of(v), tile), (x .|. (y << 16n) : U32), acc)
      cand_cols(p, cells[(i + 1 : U32)], (i + 1 : U32), (x + 1 : U32), y, tile, next)

def cand_rows(n: Nat, got: Array<U32> & List<&2, U32>, +cols: Nat, +w: U32, +edge: U32, +y: U32, +tile: U32) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, acc) = got
      +start = (y * w + edge : U32)
      cand_rows(p, cand_cols(cols, cells[start], start, edge, y, tile, acc), cols, w, edge, (y + 1 : U32), tile)

def candidates_done(got: Array<U32> & List<&2, U32>, +w: U32, +h: U32) -> GR.Grid & List<&2, U32>:
  (cells, acc) = got
  (GR.Grid{cells, w, h}, List.reverse(&2, U32, acc))

# The tiles of the distribute window (edge .. size - edge - 1) holding `tile`, row-major, packed x | y << 16.
def candidates(g: GR.Grid, +edge: U32, +tile: U32) -> GR.Grid & List<&2, U32>:
  match g:
    case GR.Grid{cells, +w, +h}:
      +cols = U32.to_nat((w - 2 * edge : U32))
      candidates_done(cand_rows(U32.to_nat((h - 2 * edge : U32)), (cells, Nil{}), cols, w, edge, edge, tile), w, h)

def dist_at(+c: OS.Ctx, +d: Dist, +p: U32, s: OS.Sea) -> OS.Sea:
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      drawn(R.draw(rng), g, c, d, (p .&. 65535 : U32), (p >> 16n : U32), ids, ents, topo, events)

def dist_list(ps: List<&2, U32>, s: OS.Sea, +c: OS.Ctx, +d: Dist) -> OS.Sea:
  match ps:
    case Nil{}:
      s
    case Con{+p, rest}:
      dist_list(rest, dist_at(c, d, p, s), c, d)

def dist_found(got: GR.Grid & List<&2, U32>, ids: GR.Grid, +rng: R.Rng, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>, +c: OS.Ctx, +d: Dist) -> OS.Sea:
  (g, +ps) = got
  dist_list(ps, OS.Sea{g, ids, rng, ents, topo, events}, c, d)

# The distribute scan: y = edge .. height - edge - 1, x = edge .. width - edge - 1, row-major; ReserveTile does not
# change tiles, so the tiles to draw for are found first.
def distribute(+c: OS.Ctx, +d: Dist, s: OS.Sea) -> OS.Sea:
  match d s:
    case Dist{+tile, +threshold, +units} OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      found = candidates(g, OQ.ocean_population_edge_dist(), tile)
      dist_found(found, ids, rng, ents, topo, events, c, Dist{tile, threshold, units})

def distribute_if(on: Bool, +c: OS.Ctx, +d: Dist, s: OS.Sea) -> OS.Sea:
  match on:
    case False{}:
      s
    case True{}:
      distribute(c, d, s)

def count_sum(xs: List<&2, U32>, +acc: U32) -> U32:
  match xs:
    case Con{_, Con{_, Con{+value, rest}}}:
      count_sum(rest, (acc + value : U32))
    case _:
      acc

def points_done(got: GR.Grid & R.Rng, ids: GR.Grid, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  (g, +rng) = got
  OS.Sea{g, ids, rng, ents, topo, events}

def points_if(on: Bool, +c: OS.Ctx, +room: U32, +tile: U32, s: OS.Sea) -> OS.Sea:
  match on:
    case False{}:
      s
    case True{}:
      match s:
        case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
          +needed = (2 * count_sum(RM.room_countprefabs((room * 2 : U32)), 0) + 10 : U32)
          points_done(water_points(g, OS.width_of(c), OS.height_of(c), OQ.ocean_population_edge_dist(), tile, needed, rng), ids, ents, topo, events)

def pieces_if(some: Bool, +c: OS.Ctx, +specs: List<&2, OP.Spec>, +tile: U32, s: OS.Sea) -> OS.Sea:
  match some:
    case False{}:
      s
    case True{}:
      OP.place_set_pieces(specs, c, tile, OC.config_ocean_prefill_setpieces_min_land_dist(), s)

def picks_of(+i: U32) -> List<&2, U32>:
  B.drop(DS.ocean_picks(i), 2)

# PopulateWaterType for the i-th ocean room of the level.
def water_type(+c: OS.Ctx, +room: U32, +i: U32, s: OS.Sea) -> OS.Sea:
  +tile = RM.value(room)
  +specs = room_specs(room)
  placed = pieces_if(Bool.not(List.is_empty(&2, OP.Spec, specs)), c, specs, tile, s)
  pointed = points_if(RM.has(room, RM.flag_countprefabs()), c, room, tile, placed)
  +on = RM.has(room, RM.flag_distribute_percent()) && RM.has(room, RM.flag_distributeprefabs())
  distribute_if(on, c, Dist{tile, RM.distribute_threshold(room), picks_of(i)}, pointed)

def rooms_loop(rooms: List<&2, U32>, +c: OS.Ctx, +i: U32, s: OS.Sea) -> OS.Sea:
  match rooms:
    case Nil{}:
      s
    case Con{+room, rest}:
      rooms_loop(rest, c, (i + 1 : U32), water_type(c, room, i, s))

# PopulateOcean(SpawnFunctions, entities, width, height, storygen.ocean_population) for the level's ocean rooms.
def populate(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  rooms_loop(TK.lists(9), c, 0, s)
