import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../f64/random.bend as F64Random
import ../data/blob.bend as Blob
import ../data/enums.bend as Enums
import ../data/ocean.bend as OceanData
import ../data/ocean_post.bend as OceanPostData
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/groups.bend as TileGroups
import ./ents.bend as OceanEnts
import ./state.bend as OceanState
import ./pow.bend as OceanPow

# bunch_spawner.lua's BunchSpawnerRun: for each spawner kind in pairs(Bunches) order and each of its entities in
# order, math.random(min, max) items, each placed by up to 20 tries (rad = pow(math.random(), 0.8) * range, xdiff,
# zdiff, two sign draws) until no item of this batch is within min_spacing, then kept when its tile (floor of
# width / 2 + 0.5 + x / 4) is inside the population edge and a valid tile; the batch goes to the end of savedata.ents
# in order, positions unrounded.

# A spawner row: spawner prefab, item prefab (NONE: the wobster closure picks it), range, min, max, min_spacing,
# valid tiles.
type Spawner is Data:
  Spawner{spawner: U32, item: U32, range: U32, min: U32, max: U32, spacing: U32, valid: List<&2, U32>}

def spawner_of(+row: List<&2, U32>) -> Spawner:
  Spawner{Blob.at(row, 0), Blob.at(row, 1), Blob.at(row, 3), Blob.at(row, 4), Blob.at(row, 5), Blob.at(row, 6), Blob.drop(row, 8)}

# A placed item of the current batch.
type Item is Data:
  Item{prefab: U32, x: F64Repr.F64, z: F64Repr.F64}

def near(+x: F64Repr.F64, +z: F64Repr.F64, +limit: F64Repr.F64, items: List<&2, Item>) -> Bool:
  match items:
    case Nil{}:
      False{}
    case Con{Item{_, +ix, +iz}, rest}:
      +dx = F64Repr.abs(F64Arith.sub(x, ix))
      +dz = F64Repr.abs(F64Arith.sub(z, iz))
      F64Cmp.lt(F64Arith.add(F64Arith.mul(dx, dx), F64Arith.mul(dz, dz)), limit) || near(x, z, limit, rest)

# One try's position, whether to try again, and the RNG.
type Try is Data:
  Try{x: F64Repr.F64, z: F64Repr.F64, again: Bool, rng: Pcg.Rng}

def signed(+v: F64Repr.F64, +r: F64Repr.F64) -> F64Repr.F64:
  F64Repr.pick(F64Cmp.gt(r, F64Repr.half()), F64Repr.neg(v), v)

def try_z(got: F64Repr.F64 & Pcg.Rng, +xd: F64Repr.F64, +zd: F64Repr.F64, +x1: F64Repr.F64, +z1: F64Repr.F64, +limit: F64Repr.F64, +items: List<&2, Item>) -> Try:
  (+r, rng) = got
  +x = F64Arith.add(x1, xd)
  +z = F64Arith.add(z1, signed(zd, r))
  Try{x, z, near(x, z, limit, items), rng}

def try_x(got: F64Repr.F64 & Pcg.Rng, +xd: F64Repr.F64, +zd: F64Repr.F64, +x1: F64Repr.F64, +z1: F64Repr.F64, +limit: F64Repr.F64, +items: List<&2, Item>) -> Try:
  (+r, rng) = got
  try_z(F64Random.random(rng), signed(xd, r), zd, x1, z1, limit, items)

def try_diff(got: F64Repr.F64 & Pcg.Rng, +rad: F64Repr.F64, +x1: F64Repr.F64, +z1: F64Repr.F64, +limit: F64Repr.F64, +items: List<&2, Item>) -> Try:
  (+r, rng) = got
  +xd = F64Arith.mul(r, rad)
  +zd = F64Arith.sqrt(F64Arith.sub(F64Arith.mul(rad, rad), F64Arith.mul(xd, xd)))
  try_x(F64Random.random(rng), xd, zd, x1, z1, limit, items)

def try_radius(got: U32 & Pcg.Rng, +windows: Bool, +range: U32, +x1: F64Repr.F64, +z1: F64Repr.F64, +limit: F64Repr.F64, +items: List<&2, Item>) -> Try:
  (+x, rng) = got
  try_diff(F64Random.random(rng), F64Arith.mul(OceanPow.pow_08_of_output(windows, x), F64Repr.from_u32(range)), x1, z1, limit, items)

def tries(n: Nat, +t: Try, +windows: Bool, +range: U32, +x1: F64Repr.F64, +z1: F64Repr.F64, +limit: F64Repr.F64, +items: List<&2, Item>) -> Try:
  match n:
    case 0n:
      t
    case 1n+p:
      match t:
        case Try{+x, +z, +again, +rng}:
          match again:
            case False{}:
              Try{x, z, again, rng}
            case True{}:
              tries(p, try_radius(Pcg.draw(rng), windows, range, x1, z1, limit, items), windows, range, x1, z1, limit, items)

def ground_of(+v: F64Repr.F64, +size: U32) -> F64Repr.F64:
  +base = F64Arith.add(F64Arith.mul(F64Repr.from_u32(size), F64Repr.half()), F64Repr.half())
  F64Repr.floor(F64Arith.add(base, F64Arith.div(v, F64Repr.from_u32(OceanPostData.tile_scale()))))

def inside(+v: F64Repr.F64, +size: U32) -> Bool:
  +edge = OceanPostData.ocean_population_edge_dist()
  F64Cmp.gt(v, F64Repr.from_u32(edge)) && F64Cmp.lt(v, F64Repr.from_u32((size - edge : U32)))

def valid_tile(+tile: U32, valid: List<&2, U32>) -> Bool:
  match valid:
    case Nil{}:
      False{}
    case Con{+t, rest}:
      U32.is_eq(t, tile) || valid_tile(tile, rest)

def moon_beach(+tile: U32) -> Bool:
  U32.is_eq(tile, Enums.tile_pebblebeach()) || U32.is_eq(tile, Enums.tile_meteor()) || U32.is_eq(tile, Enums.tile_shellbeach())

# One tile of the wobster closure: NONE to go on, else its prefab.
def wobster_tile(+tile: U32) -> U32:
  +usable = Bool.not(TileGroups.is_invalid(tile)) && U32.is_ne(tile, Enums.tile_rocky())
  +results = OceanPostData.bunch_closure_results(0)
  Bool.pick(U32, usable && moon_beach(tile), Blob.at(results, 0),
    Bool.pick(U32, usable && Bool.not(TileGroups.is_ocean(tile)), Blob.at(results, 1), Blob.none()))

def wobster_step(got: Grid.Grid & U32, +found: U32) -> Grid.Grid & U32:
  (g, +tile) = got
  (g, Bool.pick(U32, U32.is_eq(found, Blob.none()), wobster_tile(tile), found))

def wobster_offsets() -> List<&2, U32>:
  [4294967292, 4, 0, 4, 4, 4, 4294967292, 0, 0, 0, 4, 0, 4294967292, 4294967292, 0, 4294967292, 4, 4294967292]

def wobster_loop(offs: List<&2, U32>, got: Grid.Grid & U32, +x: U32, +z: U32) -> Grid.Grid & U32:
  match offs:
    case Con{+ox, Con{+oz, rest}}:
      (g, +found) = got
      wobster_loop(rest, wobster_step(Points.get_tile(g, (x + ox : U32), (z + oz : U32)), found), x, z)
    case _:
      got

# wobster_den_spawner_shore's prefab closure at the spawner tile: the first tile of the 3 x 3 (step 4, rows z + 4
# down to z - 4) that is neither invalid nor ROCKY decides (a moon beach: moonglass_wobster_den; not ocean:
# wobster_den; ocean: go on); NONE when none does.
def wobster(g: Grid.Grid, +x: U32, +z: U32) -> Grid.Grid & U32:
  wobster_loop(wobster_offsets(), (g, Blob.none()), x, z)

def item_prefab(closure: Bool, g: Grid.Grid, +item: U32, +x: U32, +z: U32) -> Grid.Grid & U32:
  match closure:
    case True{}:
      wobster(g, x, z)
    case False{}:
      (g, item)

# The bunch spawner's state: the tiles (read only), the RNG and the entities.
type Bun is Type:
  Bun{g: Grid.Grid, rng: Pcg.Rng, ents: List<&2, OceanEnts.Ent>}

def kept(got: Grid.Grid & U32, +x: F64Repr.F64, +z: F64Repr.F64, rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  (g, +prefab) = got
  (Bun{g, rng, ents}, Bool.pick(List<&2, Item>, Blob.is_none(prefab), items, Item{prefab, x, z} <> items))

def place_ok(ok: Bool, g: Grid.Grid, +item: U32, +tx: U32, +tz: U32, +x: F64Repr.F64, +z: F64Repr.F64, rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  match ok:
    case False{}:
      (Bun{g, rng, ents}, items)
    case True{}:
      kept(item_prefab(Blob.is_none(item), g, item, tx, tz), x, z, rng, ents, items)

def tile_checked(got: Grid.Grid & U32, +sp: Spawner, +tx: U32, +tz: U32, +x: F64Repr.F64, +z: F64Repr.F64, rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  (g, +tile) = got
  match sp:
    case Spawner{_, +item, _, _, _, _, +valid}:
      +ok = Bool.not(TileGroups.is_invalid(tile)) && valid_tile(tile, valid)
      place_ok(ok, g, item, tx, tz, x, z, rng, ents, items)

def ground_if(inside_map: Bool, g: Grid.Grid, +sp: Spawner, +fx: F64Repr.F64, +fz: F64Repr.F64, +x: F64Repr.F64, +z: F64Repr.F64, rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  match inside_map:
    case False{}:
      (Bun{g, rng, ents}, items)
    case True{}:
      +tx = F64Repr.to_i32(fx)
      +tz = F64Repr.to_i32(fz)
      tile_checked(Points.get_tile(g, tx, tz), sp, tx, tz, x, z, rng, ents, items)

def placed(+t: Try, +c: OceanState.Ctx, +sp: Spawner, g: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  match t:
    case Try{+x, +z, _, +rng}:
      +fx = ground_of(x, OceanState.width_of(c))
      +fz = ground_of(z, OceanState.height_of(c))
      ground_if(inside(fx, OceanState.width_of(c)) && inside(fz, OceanState.height_of(c)), g, sp, fx, fz, x, z, rng, ents, items)

# placeitemoffgrids: the tries, then the last try's position when its ground is valid.
def place_item(+c: OceanState.Ctx, +sp: Spawner, +x1: F64Repr.F64, +z1: F64Repr.F64, got: Bun & List<&2, Item>) -> Bun & List<&2, Item>:
  match sp:
    case Spawner{_, _, +range, _, _, +spacing, _}:
      (b, +items) = got
      match b:
        case Bun{g, +rng, +ents}:
          +limit = F64Repr.from_u32((spacing * spacing : U32))
          +t = tries(U32.to_nat(20), Try{x1, z1, True{}, rng}, OceanState.windows_of(c), range, x1, z1, limit, items)
          placed(t, c, sp, g, ents, items)

def items_loop(n: Nat, +c: OceanState.Ctx, +sp: Spawner, +x1: F64Repr.F64, +z1: F64Repr.F64, got: Bun & List<&2, Item>) -> Bun & List<&2, Item>:
  match n:
    case 0n:
      got
    case 1n+p:
      items_loop(p, c, sp, x1, z1, place_item(c, sp, x1, z1, got))

def exported(items: List<&2, Item>, +ents: List<&2, OceanEnts.Ent>) -> List<&2, OceanEnts.Ent>:
  match items:
    case Nil{}:
      ents
    case Con{Item{+prefab, +x, +z}, rest}:
      exported(rest, OceanEnts.Ent{prefab, x, z, 0, 0} <> ents)

def batch_done(got: Bun & List<&2, Item>) -> Bun:
  (b, +items) = got
  match b:
    case Bun{g, +rng, +ents}:
      Bun{g, rng, exported(List.reverse(&2, Item, items), ents)}

def batch_counted(got: U32 & Pcg.Rng, +c: OceanState.Ctx, +sp: Spawner, +x: F64Repr.F64, +z: F64Repr.F64, g: Grid.Grid, +ents: List<&2, OceanEnts.Ent>) -> Bun:
  (+number, rng) = got
  batch_done(items_loop(U32.to_nat(number), c, sp, x, z, (Bun{g, rng, ents}, Nil{})))

# BunchSpawnerRunSingleBatchSpawner at a spawner entity.
def batch(+c: OceanState.Ctx, +sp: Spawner, +e: OceanEnts.Ent, b: Bun) -> Bun:
  match sp e b:
    case Spawner{_, _, _, +min, +max, _, _} OceanEnts.Ent{_, +x, +z, _, _} Bun{g, +rng, +ents}:
      batch_counted(MathRandom.random_range(rng, min, max), c, sp, x, z, g, ents)

def spawners_loop(xs: List<&2, OceanEnts.Ent>, +c: OceanState.Ctx, +sp: Spawner, b: Bun) -> Bun:
  match xs:
    case Nil{}:
      b
    case Con{+e, rest}:
      spawners_loop(rest, c, sp, batch(c, sp, e, b))

def spawner_prefab(+sp: Spawner) -> U32:
  match sp:
    case Spawner{+spawner, _, _, _, _, _, _}:
      spawner

def kinds_loop(n: Nat, +c: OceanState.Ctx, +i: U32, b: Bun) -> Bun:
  match n:
    case 0n:
      b
    case 1n+p:
      match b:
        case Bun{g, +rng, +ents}:
          +sp = spawner_of(OceanData.bunches(i))
          +found = OceanEnts.of_prefab(ents, spawner_prefab(sp))
          kinds_loop(p, c, (i + 1 : U32), spawners_loop(found, c, sp, Bun{g, rng, ents}))

def bunches_done(b: Bun, +c: OceanState.Ctx, ids: Grid.Grid, +topo: U32, +events: List<&2, OceanState.Ev>, +before: Pcg.Rng, +count: U32) -> OceanState.Sea:
  match b:
    case Bun{g, +rng, +ents}:
      +added = (U32.from_nat(List.length(&2, OceanEnts.Ent, ents)) - count : U32)
      noted = OceanState.noted(c, OceanState.Sea{g, ids, rng, ents, topo, events}, OceanState.EBunches{before, rng, ents, added})
      OceanState.digest(c, OceanState.noted(c, noted, OceanState.EFinal{ents}), 9)

# BunchSpawnerRun(WorldSim) on savedata.ents.
def bunches(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      b = kinds_loop(U32.to_nat(OceanData.bunches_count()), c, 0, Bun{g, rng, ents})
      bunches_done(b, c, ids, topo, events, rng, U32.from_nat(List.length(&2, OceanEnts.Ent, ents)))
