import Base
import ../rng/pcg.bend as R
import ../lua/math_random.bend as LM
import ../lua/table.bend as LT
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ../f64/random.bend as FRN
import ../data/blob.bend as B
import ../data/enums.bend as EN
import ../data/ocean_post.bend as OQ
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/groups.bend as TG
import ./ents.bend as OE
import ./state.bend as OS

# monkeyisland_worldgen.lua's MonkeyIsland_GenerateDocks: per monkeyisland_center (with the direction and safe area
# entities of the same index), the starting points, every GenBranch (an explicit call stack, same draw order), then
# the posts and cannons over GENERATED_DOCK_LIST.grid in its Lua 5.1 pairs() order. TESTED_TILES caches the first
# GetTile of each position for the whole call, as the game does.

def quarter() -> FR.F64:
  FR.F64{1070596096, 0}

def twentieth() -> FR.F64:
  FR.F64{1068079513, 2576980378}

def variance() -> FR.F64:
  FR.F64{1073532108, 3435973837}

def fifth() -> FR.F64:
  FR.F64{1070176665, 2576980378}

def minus_one() -> U32:
  4294967295

# The dock generator's state: tiles, the TESTED_TILES cache (tile + 1, 0 = unset), GENERATED_DOCK_LIST.grid, the RNG
# and the entities.
type Dock is Type:
  Dock{g: GR.Grid, cache: GR.Grid, list: LT.Table, rng: R.Rng, ents: List<&2, OE.Ent>}

# The safe area (DOCK_SAFETY_MINX, MAXX, MINZ, MAXZ), the map size and the orientation (0 right, 1 left, 2 up, 3
# down).
type Area is Data:
  Area{min_x: FR.F64, max_x: FR.F64, min_z: FR.F64, max_z: FR.F64, w: U32, h: U32, orient: U32}

def tile_read(got: GR.Grid & U32, cache: GR.Grid, list: LT.Table, rng: R.Rng, +ents: List<&2, OE.Ent>) -> Dock & U32:
  (g, +tile) = got
  (Dock{g, cache, list, rng, ents}, tile)

def get_tile(d: Dock, +x: U32, +z: U32) -> Dock & U32:
  match d:
    case Dock{g, cache, list, rng, +ents}:
      tile_read(PT.get_tile(g, x, z), cache, list, rng, ents)

def set_dock(d: Dock, +x: U32, +z: U32) -> Dock:
  match d:
    case Dock{g, cache, list, rng, +ents}:
      Dock{PT.set_tile(g, x, z, EN.tile_monkey_dock(), 0), cache, list, rng, ents}

def world_of(+t: U32, +size: U32) -> FR.F64:
  FA.mul(FR.from_u32(OQ.tile_scale()), FA.sub(FR.from_u32(t), FA.mul(FR.from_u32(size), FR.half())))

def add_ent(d: Dock, +prefab: U32, +x: FR.F64, +z: FR.F64) -> Dock:
  match d:
    case Dock{g, cache, list, rng, +ents}:
      Dock{g, cache, list, rng, OE.Ent{prefab, x, z, 0, 0} <> ents}

def registrator(d: Dock, +a: Area, +x: U32, +z: U32) -> Dock:
  match a:
    case Area{_, _, _, _, +w, +h, _}:
      add_ent(d, OQ.dock_tile_registrator(), world_of(x, w), world_of(z, h))

def cached_land(+t: U32) -> Bool:
  U32.is_ne(t, EN.tile_monkey_dock()) && Bool.not(TG.is_ocean(t))

def cache_fill(got: Dock & U32, +i: U32) -> Dock & Bool:
  (d, +tile) = got
  match d:
    case Dock{g, cache, list, rng, +ents}:
      (Dock{g, GR.put(cache, i, (tile + 1 : U32)), list, rng, ents}, cached_land(tile))

def land_read(got: Dock & U32) -> Dock & Bool:
  (d, +tile) = got
  (d, cached_land(tile))

def cache_pick(unset: Bool, cache: GR.Grid, g: GR.Grid, list: LT.Table, rng: R.Rng, +ents: List<&2, OE.Ent>, +x: U32, +z: U32, +i: U32, +v: U32) -> Dock & Bool:
  match unset:
    case True{}:
      cache_fill(get_tile(Dock{g, cache, list, rng, ents}, x, z), i)
    case False{}:
      (Dock{g, cache, list, rng, ents}, cached_land((v - 1 : U32)))

def cache_hit(got: GR.Grid & U32, g: GR.Grid, list: LT.Table, rng: R.Rng, +ents: List<&2, OE.Ent>, +x: U32, +z: U32, +i: U32) -> Dock & Bool:
  (cache, +v) = got
  cache_pick(U32.is_zero(v), cache, g, list, rng, ents, x, z, i, v)

def tested_at(inside: Bool, d: Dock, +x: U32, +z: U32, +w: U32) -> Dock & Bool:
  match inside:
    case False{}:
      land_read(get_tile(d, x, z))
    case True{}:
      match d:
        case Dock{g, cache, list, rng, +ents}:
          cache_hit(GR.get(cache, GR.index(x, z, w)), g, list, rng, ents, x, z, GR.index(x, z, w))

# assign_and_test_tile: true when the (cached) tile is neither a dock nor ocean.
def tested(d: Dock, +a: Area, +x: U32, +z: U32) -> Dock & Bool:
  match a:
    case Area{_, _, _, _, +w, +h, _}:
      tested_at(PT.contains(x, z, w, h), d, x, z, w)

def land_read_not(got: Dock & Bool) -> Dock & Bool:
  (d, +land) = got
  (d, Bool.not(land))

# One neighbour of ValidateSurroundingTiles: skipped once a land tile was seen (the game returns there).
def validate_step(ok: Bool, d: Dock, +a: Area, +x: U32, +z: U32) -> Dock & Bool:
  match ok:
    case False{}:
      (d, False{})
    case True{}:
      land_read_not(tested(d, a, x, z))

def offsets() -> List<&2, U32>:
  [1, minus_one(), 1, 0, 1, 1, 0, minus_one(), 0, 1, minus_one(), minus_one(), minus_one(), 0, minus_one(), 1]

def validate_loop(offs: List<&2, U32>, got: Dock & Bool, +a: Area, +x: U32, +z: U32) -> Dock & Bool:
  match offs:
    case Con{+ox, Con{+oz, rest}}:
      (d, +ok) = got
      validate_loop(rest, validate_step(ok, d, a, (x + ox : U32), (z + oz : U32)), a, x, z)
    case _:
      got

# ValidateSurroundingTiles(x, z): no land (per the cache) among the 8 neighbours, tested x+1 column first.
def validate(d: Dock, +a: Area, +x: U32, +z: U32) -> Dock & Bool:
  validate_loop(offsets(), (d, True{}), a, x, z)

def in_safe(+a: Area, +x: U32, +z: U32) -> Bool:
  match a:
    case Area{+min_x, +max_x, +min_z, +max_z, _, _, _}:
      +fx = FR.from_u32(x)
      +fz = FR.from_u32(z)
      FC.gt(fx, min_x) && FC.lt(fx, max_x) && FC.gt(fz, min_z) && FC.lt(fz, max_z)

def drawn_f(got: FR.F64 & R.Rng, g: GR.Grid, cache: GR.Grid, list: LT.Table, +ents: List<&2, OE.Ent>) -> Dock & FR.F64:
  (+r, rng) = got
  (Dock{g, cache, list, rng, ents}, r)

# math.random() on the dock state.
def draw_f(d: Dock) -> Dock & FR.F64:
  match d:
    case Dock{g, cache, list, rng, +ents}:
      drawn_f(FRN.random(rng), g, cache, list, ents)

def drawn_range(got: U32 & R.Rng, g: GR.Grid, cache: GR.Grid, list: LT.Table, +ents: List<&2, OE.Ent>) -> Dock & U32:
  (+v, rng) = got
  (Dock{g, cache, list, rng, ents}, v)

# math.random(m, n) on the dock state (luaL_checkint truncation is the caller's).
def draw_range(d: Dock, +m: U32, +n: U32) -> Dock & U32:
  match d:
    case Dock{g, cache, list, rng, +ents}:
      drawn_range(LM.random_range(rng, m, n), g, cache, list, ents)

def list_set(d: Dock, +a: Area, +x: U32, +z: U32, +endpoint: Bool) -> Dock:
  match d a:
    case Dock{g, cache, list, rng, +ents} Area{_, _, _, _, +w, _, _}:
      Dock{g, cache, LT.set(list, LT.int_key((z * w + x : U32)), Bool.to_u32(endpoint)), rng, ents}

# One GenBranch call in progress: position, axis, direction (1 or 2^32 - 1), the length bounds and branch chances
# (doubles), the step i of `len`, and the phase within the step (0 move, 1 right branch, 2 left branch).
type Frame is Data:
  Frame{x: U32, z: U32, on_x: Bool, dir: U32, min: FR.F64, max: FR.F64, br: FR.F64, bl: FR.F64, i: U32, len: U32, phase: U32}

def two_thirds(+v: FR.F64) -> FR.F64:
  FA.sub(v, FA.div(v, FR.from_u32(3)))

def frame_started(got: Dock & U32, +x: U32, +z: U32, +on_x: Bool, +dir: U32, +min: FR.F64, +max: FR.F64, +br: FR.F64, +bl: FR.F64, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +len) = got
  (d, Frame{x, z, on_x, dir, min, max, br, bl, 1, len, 0} <> stack)

def call_if(short: Bool, d: Dock, +x: U32, +z: U32, +on_x: Bool, +dir: U32, +min: FR.F64, +max: FR.F64, +br: FR.F64, +bl: FR.F64, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match short:
    case True{}:
      (d, stack)
    case False{}:
      frame_started(draw_range(d, FR.to_i32(min), FR.to_i32(max)), x, z, on_x, dir, min, max, br, bl, stack)

# A GenBranch call: nothing when min_length < 1, else the dock length draw and a new frame on the stack.
def call(d: Dock, +x: U32, +z: U32, +on_x: Bool, +dir: U32, +min: FR.F64, +max: FR.F64, +br: FR.F64, +bl: FR.F64, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  call_if(FC.lt(min, FR.one()), d, x, z, on_x, dir, min, max, br, bl, stack)

def f64_of(got: U32 & U32) -> FR.F64:
  (+hi, +lo) = got
  FR.F64{hi, lo}

def chance_row(+row: List<&2, U32>) -> FR.F64:
  f64_of(B.f64(row, 1))

def dock_rows(n: Nat, +i: U32) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      OQ.dock_prefabs(i) <> dock_rows(p, (i + 1 : U32))

def endpoint_rows(n: Nat, +i: U32) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      OQ.endpoint_prefabs(i) <> endpoint_rows(p, (i + 1 : U32))

# The prefab a `prefab_rand - chance <= 0` walk over (prefab, chance) rows stops at (NONE past the last).
def pick_loop(rows: List<&2, List<&2, U32>>, +r: FR.F64, +found: U32) -> U32:
  match rows:
    case Nil{}:
      found
    case Con{+row, rest}:
      +left = FA.sub(r, chance_row(row))
      +hit = U32.is_eq(found, B.none()) && FC.le(left, FR.zero())
      pick_loop(rest, left, Bool.pick(U32, hit, B.at(row, 0), found))

def pick_dock(+r: FR.F64) -> U32:
  pick_loop(dock_rows(U32.to_nat(OQ.dock_prefabs_count()), 0), r, B.none())

def pick_endpoint(+r: FR.F64) -> U32:
  pick_loop(endpoint_rows(U32.to_nat(OQ.endpoint_prefabs_count()), 0), r, B.none())

# GetRandomWithVariance(base, 1.8): base + (math.random() * 2 * 1.8 - 1.8).
def varied(+base: FR.F64, +r: FR.F64) -> FR.F64:
  FA.add(base, FA.sub(FA.mul(FA.mul(r, FR.two()), variance()), variance()))

def varied_z(got: Dock & FR.F64, +prefab: U32, +x: FR.F64, +mid_z: FR.F64) -> Dock:
  (d, +r) = got
  add_ent(d, prefab, x, varied(mid_z, r))

def varied_x(got: Dock & FR.F64, +prefab: U32, +mid_x: FR.F64, +mid_z: FR.F64) -> Dock:
  (d, +r) = got
  varied_z(draw_f(d), prefab, varied(mid_x, r), mid_z)

def dock_prefab_if(some: Bool, d: Dock, +prefab: U32, +mid_x: FR.F64, +mid_z: FR.F64) -> Dock:
  match some:
    case False{}:
      d
    case True{}:
      varied_x(draw_f(d), prefab, mid_x, mid_z)

def dock_prefab_drawn(got: Dock & FR.F64, +a: Area, +x: U32, +z: U32) -> Dock:
  (d, +r) = got
  match a:
    case Area{_, _, _, _, +w, +h, _}:
      +prefab = pick_dock(r)
      dock_prefab_if(U32.is_ne(prefab, B.none()), d, prefab, world_of(x, w), world_of(z, h))

# RANDOM_DOCK_PREFABS on a new dock tile: one draw, then a prefab at the tile centre with the variance (2 draws).
def dock_prefab(d: Dock, +a: Area, +x: U32, +z: U32) -> Dock:
  dock_prefab_drawn(draw_f(d), a, x, z)

def blocked(+a: Area, +on_x: Bool, +dir: U32) -> Bool:
  match a:
    case Area{_, _, _, _, _, _, +o}:
      +back = U32.is_eq(dir, minus_one())
      Bool.pick(Bool, on_x, (U32.is_eq(o, 0) && back) || (U32.is_eq(o, 1) && Bool.not(back)),
        (U32.is_eq(o, 2) && back) || (U32.is_eq(o, 3) && Bool.not(back)))

def with_phase(+f: Frame, +x: U32, +z: U32, +br: FR.F64, +bl: FR.F64, +i: U32, +phase: U32) -> Frame:
  match f:
    case Frame{_, _, +on_x, +dir, +min, +max, _, _, _, +len, _}:
      Frame{x, z, on_x, dir, min, max, br, bl, i, len, phase}

def place_or_stop(ok: Bool, d: Dock, +a: Area, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match ok:
    case False{}:
      (d, stack)
    case True{}:
      match f:
        case Frame{+x, +z, _, _, _, _, +br, +bl, +i, _, _}:
          placed = dock_prefab(registrator(list_set(set_dock(d, x, z), a, x, z, False{}), a, x, z), a, x, z)
          (placed, with_phase(f, x, z, br, bl, i, 1) <> stack)

def validated(got: Dock & Bool, +a: Area, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +ok) = got
  place_or_stop(ok, d, a, f, stack)

def tile_ok(ok: Bool, d: Dock, +a: Area, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match ok:
    case False{}:
      (d, stack)
    case True{}:
      match f:
        case Frame{+x, +z, _, _, _, _, _, _, _, _, _}:
          validated(validate(d, a, x, z), a, f, stack)

def moved_tile(got: Dock & U32, +a: Area, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +tile) = got
  match f:
    case Frame{+x, +z, _, _, _, _, _, _, _, _, _}:
      tile_ok(in_safe(a, x, z) && TG.is_ocean(tile), d, a, f, stack)

def move_or_block(stop: Bool, d: Dock, +a: Area, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match stop:
    case True{}:
      (d, stack)
    case False{}:
      match f:
        case Frame{+x, +z, +on_x, +dir, _, _, +br, +bl, +i, _, _}:
          +nx = Bool.pick(U32, on_x, (x + dir : U32), x)
          +nz = Bool.pick(U32, on_x, z, (z + dir : U32))
          moved_tile(get_tile(d, nx, nz), a, with_phase(f, nx, nz, br, bl, i, 0), stack)

def move_or_end(done: Bool, d: Dock, +a: Area, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match done:
    case True{}:
      match f:
        case Frame{+x, +z, _, _, _, _, _, _, _, _, _}:
          (list_set(d, a, x, z, True{}), stack)
    case False{}:
      match f:
        case Frame{_, _, +on_x, +dir, _, _, _, _, _, _, _}:
          move_or_block(blocked(a, on_x, dir), d, a, f, stack)

# Phase 0 of a step: past the length, the endpoint mark and return; else the move and the checks (a failed one
# returns), the dock tile, its registrator and RANDOM_DOCK_PREFABS.
def move_step(d: Dock, +a: Area, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match f:
    case Frame{_, _, _, _, _, _, _, _, +i, +len, _}:
      move_or_end((i > len : U32), d, a, f, stack)

def half_of(+v: FR.F64) -> FR.F64:
  FA.mul(v, FR.half())

def right_branch(yes: Bool, d: Dock, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match yes:
    case False{}:
      match f:
        case Frame{+x, +z, _, _, _, _, +br, +bl, +i, _, _}:
          (d, with_phase(f, x, z, br, bl, i, 2) <> stack)
    case True{}:
      match f:
        case Frame{+x, +z, +on_x, _, +min, +max, +br, +bl, +i, _, _}:
          +parent = with_phase(f, x, z, FA.sub(br, twentieth()), bl, i, 2)
          call(d, x, z, Bool.not(on_x), 1, two_thirds(min), two_thirds(max), half_of(br), half_of(bl), parent <> stack)

def right_drawn(got: Dock & FR.F64, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +r) = got
  match f:
    case Frame{_, _, _, _, _, _, +br, _, _, _, _}:
      right_branch(FC.lt(r, br), d, f, stack)

def left_branch(yes: Bool, d: Dock, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match yes:
    case False{}:
      match f:
        case Frame{+x, +z, _, _, _, _, +br, +bl, +i, _, _}:
          (d, with_phase(f, x, z, br, bl, (i + 1 : U32), 0) <> stack)
    case True{}:
      match f:
        case Frame{+x, +z, +on_x, _, +min, +max, +br, +bl, +i, _, _}:
          +parent = with_phase(f, x, z, br, FA.sub(bl, twentieth()), (i + 1 : U32), 0)
          call(d, x, z, Bool.not(on_x), minus_one(), two_thirds(min), two_thirds(max), half_of(br), half_of(bl), parent <> stack)

def left_drawn(got: Dock & FR.F64, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +r) = got
  match f:
    case Frame{_, _, _, _, _, _, _, +bl, _, _, _}:
      left_branch(FC.lt(r, bl), d, f, stack)

def step(d: Dock, +a: Area, +f: Frame, +stack: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match f:
    case Frame{_, _, _, _, _, _, _, _, _, _, +phase}:
      match phase:
        case 0:
          move_step(d, a, f, stack)
        case 1:
          right_drawn(draw_f(d), f, stack)
        case _:
          left_drawn(draw_f(d), f, stack)

# Runs the GenBranch call stack until it is empty.
def run(n: Nat, got: Dock & List<&2, Frame>, +a: Area) -> Dock:
  match n:
    case 0n:
      (d, _) = got
      d
    case 1n+p:
      (d, +stack) = got
      match stack:
        case Nil{}:
          d
        case Con{+f, rest}:
          run(p, step(d, a, f, rest), a)

def run_fuel() -> Nat:
  U32.to_nat(50000)

def eight() -> FR.F64:
  FR.from_u32(OQ.dock_min_length())

def fourteen() -> FR.F64:
  FR.from_u32(OQ.dock_max_length())

# NewGen: GenBranch from each starting point in order (min/max length from the tuning, chances 0.25).
def new_gen(starts: List<&2, Frame>, d: Dock, +a: Area) -> Dock:
  match starts:
    case Nil{}:
      d
    case Con{Frame{+x, +z, +on_x, +dir, _, _, _, _, _, _, _}, rest}:
      new_gen(rest, run(run_fuel(), call(d, x, z, on_x, dir, eight(), fourteen(), quarter(), quarter(), Nil{}), a), a)

def reread(ocean: Bool, d: Dock, +tile: U32, +x: U32, +z: U32) -> Dock & U32:
  match ocean:
    case True{}:
      (d, tile)
    case False{}:
      get_tile(d, x, z)

type Spot is Data:
  Spot{x: U32, z: U32}

# "Keep moving until we find the ocean" along the start's axis and direction.
def walk(n: Nat, got: Dock & U32, +x: U32, +z: U32, +on_x: Bool, +dir: U32) -> Dock & Spot:
  match n:
    case 0n:
      (d, _) = got
      (d, Spot{x, z})
    case 1n+p:
      (d, +tile) = got
      +ocean = TG.is_ocean(tile)
      +nx = Bool.pick(U32, ocean || Bool.not(on_x), x, (x + dir : U32))
      +nz = Bool.pick(U32, ocean || on_x, z, (z + dir : U32))
      walk(p, reread(ocean, d, tile, nx, nz), nx, nz, on_x, dir)

def dock_count(got: Dock & U32, +n: U32) -> Dock & U32:
  (d, +tile) = got
  (d, (n + Bool.to_u32(U32.is_eq(tile, EN.tile_monkey_dock())) : U32))

def adjacent_last(got: Dock & U32, +x: U32, +z: U32) -> Dock & U32:
  (d, +n) = got
  dock_count(get_tile(d, x, (z - 1 : U32)), n)

def adjacent_up(got: Dock & U32, +x: U32, +z: U32) -> Dock & U32:
  (d, +n) = got
  adjacent_last(dock_count(get_tile(d, x, (z + 1 : U32)), n), x, z)

def adjacent_left(got: Dock & U32, +x: U32, +z: U32) -> Dock & U32:
  (d, +n) = got
  adjacent_up(dock_count(get_tile(d, (x - 1 : U32), z), n), x, z)

# How many of the 4 neighbours are MONKEY_DOCK.
def adjacent_docks(d: Dock, +x: U32, +z: U32) -> Dock & U32:
  adjacent_left(dock_count(get_tile(d, (x + 1 : U32), z), 0), x, z)

def start_frame(+x: U32, +z: U32, +on_x: Bool, +dir: U32) -> Frame:
  Frame{x, z, on_x, dir, FR.zero(), FR.zero(), FR.zero(), FR.zero(), 0, 0, 0}

def start_placed(adjacent: Bool, d: Dock, +a: Area, +x: U32, +z: U32, +on_x: Bool, +dir: U32, +starts: List<&2, Frame>) -> Dock & List<&2, Frame>:
  match adjacent:
    case True{}:
      (d, starts)
    case False{}:
      (registrator(set_dock(d, x, z), a, x, z), start_frame(x, z, on_x, dir) <> starts)

def start_adjacent(got: Dock & U32, +a: Area, +x: U32, +z: U32, +on_x: Bool, +dir: U32, +starts: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +n) = got
  start_placed(U32.is_ne(n, 0), d, a, x, z, on_x, dir, starts)

def start_walked(got: Dock & Spot, +a: Area, +on_x: Bool, +dir: U32, +starts: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +spot) = got
  match spot:
    case Spot{+x, +z}:
      start_adjacent(adjacent_docks(d, x, z), a, x, z, on_x, dir, starts)

def walk_fuel() -> Nat:
  U32.to_nat(1024)

def start_dir(got: Dock & FR.F64, +a: Area, +x: U32, +z: U32, +on_x: Bool, +starts: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +r) = got
  +dir = Bool.pick(U32, FC.gt(r, FR.half()), 1, minus_one())
  start_walked(walk(walk_fuel(), get_tile(d, x, z), x, z, on_x, dir), a, on_x, dir, starts)

def start_axis(got: Dock & FR.F64, +a: Area, +x: U32, +z: U32, +starts: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +r) = got
  start_dir(draw_f(d), a, x, z, FC.gt(r, FR.half()), starts)

def start_z(got: Dock & U32, +a: Area, +x: U32, +cz: U32, +starts: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +dz) = got
  start_axis(draw_f(d), a, x, (cz + dz : U32), starts)

def minus_four() -> U32:
  4294967292

def start_x(got: Dock & U32, +a: Area, +cx: U32, +cz: U32, +starts: List<&2, Frame>) -> Dock & List<&2, Frame>:
  (d, +dx) = got
  start_z(draw_range(d, minus_four(), 4), a, (cx + dx : U32), cz, starts)

# generate_starting_points: MONKEYISLANDGEN_DOCKAMOUNT tries (the Lua `i = i - 1` retry changes nothing), newest
# first.
def starting(n: Nat, got: Dock & List<&2, Frame>, +a: Area, +cx: U32, +cz: U32) -> Dock & List<&2, Frame>:
  match n:
    case 0n:
      got
    case 1n+p:
      (d, +starts) = got
      starting(p, start_x(draw_range(d, minus_four(), 4), a, cx, cz, starts), a, cx, cz)

def entry_done(got: LT.Table & LT.Step, g: GR.Grid, cache: GR.Grid, rng: R.Rng, +ents: List<&2, OE.Ent>) -> Dock & LT.Step:
  (list, +st) = got
  (Dock{g, cache, list, rng, ents}, st)

def next_entry(d: Dock, +k: LT.TKey) -> Dock & LT.Step:
  match d:
    case Dock{g, cache, list, rng, +ents}:
      entry_done(LT.next(list, k), g, cache, rng, ents)

def key_int(+k: LT.TKey) -> U32:
  match k:
    case LT.TKey{_, +hi, +lo}:
      FR.to_i32(FR.F64{hi, lo})

def post_offset() -> FR.F64:
  FA.sub(FA.mul(FR.from_u32(OQ.tile_scale()), FR.half()), fifth())

def post_add(ocean: Bool, d: Dock, +a: Area, +x: U32, +z: U32, +ox: U32, +oz: U32) -> Dock:
  match ocean:
    case False{}:
      d
    case True{}:
      match a:
        case Area{_, _, _, _, +w, +h, _}:
          +px = FA.add(world_of(x, w), FA.mul(FR.from_i32(ox), post_offset()))
          +pz = FA.add(world_of(z, h), FA.mul(FR.from_i32(oz), post_offset()))
          add_ent(d, OQ.dock_woodposts(), px, pz)

def post_tile(got: Dock & U32, +a: Area, +x: U32, +z: U32, +ox: U32, +oz: U32) -> Dock:
  (d, +tile) = got
  post_add(TG.is_ocean(tile), d, a, x, z, ox, oz)

def post_if(below: Bool, d: Dock, +a: Area, +x: U32, +z: U32, +ox: U32, +oz: U32) -> Dock:
  match below:
    case False{}:
      d
    case True{}:
      post_tile(get_tile(d, (x + ox : U32), (z + oz : U32)), a, x, z, ox, oz)

def post_drawn(got: Dock & FR.F64, +a: Area, +x: U32, +z: U32, +ox: U32, +oz: U32) -> Dock:
  (d, +r) = got
  post_if(FC.lt(r, f64_of(OQ.dock_post_chance())), d, a, x, z, ox, oz)

# try_make_post: one draw, then a post pulled inward from the tile centre when below the chance and the neighbour
# is ocean.
def try_post(d: Dock, +a: Area, +x: U32, +z: U32, +ox: U32, +oz: U32) -> Dock:
  post_drawn(draw_f(d), a, x, z, ox, oz)

def ocean_count(got: Dock & U32, +n: U32) -> Dock & U32:
  (d, +tile) = got
  (d, (n + Bool.to_u32(TG.is_ocean(tile)) : U32))

def around_loop(offs: List<&2, U32>, got: Dock & U32, +x: U32, +z: U32) -> Dock & U32:
  match offs:
    case Con{+ox, Con{+oz, rest}}:
      (d, +n) = got
      around_loop(rest, ocean_count(get_tile(d, (x + ox : U32), (z + oz : U32)), n), x, z)
    case _:
      got

def endpoint_add(yes: Bool, d: Dock, +a: Area, +x: U32, +z: U32, +prefab: U32) -> Dock:
  match yes:
    case False{}:
      d
    case True{}:
      match a:
        case Area{_, _, _, _, +w, +h, _}:
          add_ent(d, prefab, world_of(x, w), world_of(z, h))

def endpoint_counted(got: Dock & U32, +a: Area, +x: U32, +z: U32, +prefab: U32) -> Dock:
  (d, +n) = got
  endpoint_add((n >= 7 : U32), d, a, x, z, prefab)

def endpoint_if(some: Bool, d: Dock, +a: Area, +x: U32, +z: U32, +prefab: U32) -> Dock:
  match some:
    case False{}:
      d
    case True{}:
      endpoint_counted(around_loop(offsets(), (d, 0), x, z), a, x, z, prefab)

def endpoint_drawn(got: Dock & FR.F64, +a: Area, +x: U32, +z: U32) -> Dock:
  (d, +r) = got
  +prefab = pick_endpoint(r)
  endpoint_if(U32.is_ne(prefab, B.none()), d, a, x, z, prefab)

def endpoint_maybe(endpoint: Bool, d: Dock, +a: Area, +x: U32, +z: U32) -> Dock:
  match endpoint:
    case False{}:
      d
    case True{}:
      endpoint_drawn(draw_f(d), a, x, z)

# One GENERATED_DOCK_LIST.grid entry: the four post tries, then the endpoint prefab.
def entry_work(d: Dock, +a: Area, +index: U32, +endpoint: Bool) -> Dock:
  match a:
    case Area{_, _, _, _, +w, _, _}:
      +x = (index % w : U32)
      +z = (index / w : U32)
      posts = try_post(try_post(try_post(try_post(d, a, x, z, 1, 0), a, x, z, minus_one(), 0), a, x, z, 0, 1), a, x, z, 0, minus_one())
      endpoint_maybe(endpoint, posts, a, x, z)

def advance(on: Bool, d: Dock, +a: Area, +st: LT.Step) -> Dock & LT.Step:
  match on:
    case False{}:
      (d, st)
    case True{}:
      match st:
        case LT.Step{_, +k, +v}:
          next_entry(entry_work(d, a, key_int(k), U32.is_eq(v, 1)), k)

def posts_loop(n: Nat, got: Dock & LT.Step, +a: Area) -> Dock:
  match n:
    case 0n:
      (d, _) = got
      d
    case 1n+p:
      (d, +st) = got
      match st:
        case LT.Step{+status, +k, +v}:
          posts_loop(p, advance(U32.is_eq(status, 1), d, a, LT.Step{status, k, v}), a)

# A world coordinate's tile: floor(abs(((v + TILE_SCALE / 2) + (TILE_SCALE * size) / 2) / TILE_SCALE)).
def grid_of(+v: FR.F64, +size: U32) -> U32:
  +scale = FR.from_u32(OQ.tile_scale())
  +shifted = FA.add(FA.add(v, FA.mul(scale, FR.half())), FA.mul(FA.mul(scale, FR.from_u32(size)), FR.half()))
  FR.to_i32(FR.floor(FR.abs(FA.div(shifted, scale))))

def orientation(+c: OE.Ent, +b: OE.Ent) -> U32:
  match c b:
    case OE.Ent{_, +cx, +cz, _, _} OE.Ent{_, +bx, +bz, _, _}:
      +same = FC.eq(FR.floor(cx), FR.floor(bx))
      Bool.pick(U32, same, Bool.pick(U32, FC.gt(cz, bz), 2, 3), Bool.pick(U32, FC.gt(cx, bx), 0, 1))

def oriented(+a: Area, +o: U32) -> Area:
  match a:
    case Area{+min_x, +max_x, +min_z, +max_z, +w, +h, _}:
      Area{min_x, max_x, min_z, max_z, w, h, o}

def with_list(d: Dock) -> Dock:
  match d:
    case Dock{g, cache, _, rng, +ents}:
      Dock{g, cache, LT.new(0, 0), rng, ents}

def slots_done(got: LT.Table & U32, g: GR.Grid, cache: GR.Grid, rng: R.Rng, +ents: List<&2, OE.Ent>) -> Dock & U32:
  (list, +n) = got
  (Dock{g, cache, list, rng, ents}, n)

def slots_of(d: Dock) -> Dock & U32:
  match d:
    case Dock{g, cache, list, rng, +ents}:
      slots_done(LT.slot_count(list), g, cache, rng, ents)

def posts_from(got: Dock & U32, +a: Area) -> Dock:
  (d, +n) = got
  posts_loop(U32.to_nat((n + 1 : U32)), next_entry(d, LT.nil_key()), a)

def started(got: Dock & List<&2, Frame>, +a: Area) -> Dock:
  (d, +starts) = got
  built = new_gen(List.reverse(&2, Frame, starts), d, a)
  posts_from(slots_of(built), a)

def island_at(d: Dock, +o: Area, +c: OE.Ent) -> Dock:
  match o c:
    case Area{_, _, _, _, +w, +h, _} OE.Ent{_, +cx, +cz, _, _}:
      started(starting(U32.to_nat(OQ.dock_amount()), (with_list(d), Nil{}), o, grid_of(cx, w), grid_of(cz, h)), o)

# One island: orientation, the starting points, NewGen, then the posts and endpoints.
def island(d: Dock, +a: Area, +c: OE.Ent, +b: OE.Ent) -> Dock:
  island_at(d, oriented(a, orientation(c, b)), c)

def safe_area(+a: Area, +s: OE.Ent) -> Area:
  match a s:
    case Area{_, _, _, _, +w, +h, +o} OE.Ent{_, +sx, +sz, _, _}:
      +half_w = FA.mul(f64_of(OQ.dock_safe_width()), FR.half())
      +half_h = FA.mul(f64_of(OQ.dock_safe_height()), FR.half())
      +tx = FR.from_u32(grid_of(sx, w))
      +tz = FR.from_u32(grid_of(sz, h))
      Area{FA.sub(tx, half_w), FA.add(tx, half_w), FA.sub(tz, half_h), FA.add(tz, half_h), w, h, o}

def safety_of(safes: List<&2, OE.Ent>, +a: Area) -> Area:
  match safes:
    case Nil{}:
      a
    case Con{+s, _}:
      safe_area(a, s)

def centers_loop(cs: List<&2, OE.Ent>, +dirs: List<&2, OE.Ent>, +safes: List<&2, OE.Ent>, d: Dock, +a: Area) -> Dock:
  match cs:
    case Nil{}:
      d
    case Con{+c, rest}:
      +area = safety_of(safes, a)
      +b = Maybe.default(&2, OE.Ent, List.head(&2, OE.Ent, dirs), c)
      centers_loop(rest, List.tail(&2, OE.Ent, dirs), List.tail(&2, OE.Ent, safes), island(d, area, c, b), area)

def docks_done(d: Dock, +c: OS.Ctx, ids: GR.Grid, +topo: U32, +events: List<&2, OS.Ev>, +before: R.Rng, +count: U32) -> OS.Sea:
  match d:
    case Dock{g, _, _, +rng, +ents}:
      +added = (U32.from_nat(List.length(&2, OE.Ent, ents)) - count : U32)
      OS.noted(c, OS.Sea{g, ids, rng, ents, topo, events}, OS.EDocks{before, rng, ents, added})

# MonkeyIsland_GenerateDocks(WorldSim, entities, width, height).
def docks(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      +w = OS.width_of(c)
      +h = OS.height_of(c)
      +a = {Area{FR.zero(), FR.zero(), FR.zero(), FR.zero(), w, h, 0} : Area}
      +cs = OE.of_prefab(ents, OQ.dock_center_prefab())
      +dirs = OE.of_prefab(ents, OQ.dock_direction_prefab())
      +safes = OE.of_prefab(ents, OQ.dock_safety_prefab())
      d = centers_loop(cs, dirs, safes, Dock{g, GR.new(w, h, 0), LT.new(0, 0), rng, ents}, a)
      docks_done(d, c, ids, topo, events, rng, U32.from_nat(List.length(&2, OE.Ent, ents)))
