import Base
import ../rng/pcg.bend as R
import ../lua/math_random.bend as LM
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ../f64/random.bend as FRN
import ../data/blob.bend as B
import ../data/enums.bend as EN
import ../data/ocean.bend as OC
import ../data/ocean_post.bend as OQ
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/groups.bend as TG
import ./ents.bend as OE
import ./state.bend as OS
import ./pow.bend as OW

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
  Spawner{B.at(row, 0), B.at(row, 1), B.at(row, 3), B.at(row, 4), B.at(row, 5), B.at(row, 6), B.drop(row, 8)}

# A placed item of the current batch.
type Item is Data:
  Item{prefab: U32, x: FR.F64, z: FR.F64}

def near(+x: FR.F64, +z: FR.F64, +limit: FR.F64, items: List<&2, Item>) -> Bool:
  match items:
    case Nil{}:
      False{}
    case Con{Item{_, +ix, +iz}, rest}:
      +dx = FR.abs(FA.sub(x, ix))
      +dz = FR.abs(FA.sub(z, iz))
      FC.lt(FA.add(FA.mul(dx, dx), FA.mul(dz, dz)), limit) || near(x, z, limit, rest)

# One try's position, whether to try again, and the RNG.
type Try is Data:
  Try{x: FR.F64, z: FR.F64, again: Bool, rng: R.Rng}

def signed(+v: FR.F64, +r: FR.F64) -> FR.F64:
  FR.pick(FC.gt(r, FR.half()), FR.neg(v), v)

def try_z(got: FR.F64 & R.Rng, +xd: FR.F64, +zd: FR.F64, +x1: FR.F64, +z1: FR.F64, +limit: FR.F64, +items: List<&2, Item>) -> Try:
  (+r, rng) = got
  +x = FA.add(x1, xd)
  +z = FA.add(z1, signed(zd, r))
  Try{x, z, near(x, z, limit, items), rng}

def try_x(got: FR.F64 & R.Rng, +xd: FR.F64, +zd: FR.F64, +x1: FR.F64, +z1: FR.F64, +limit: FR.F64, +items: List<&2, Item>) -> Try:
  (+r, rng) = got
  try_z(FRN.random(rng), signed(xd, r), zd, x1, z1, limit, items)

def try_diff(got: FR.F64 & R.Rng, +rad: FR.F64, +x1: FR.F64, +z1: FR.F64, +limit: FR.F64, +items: List<&2, Item>) -> Try:
  (+r, rng) = got
  +xd = FA.mul(r, rad)
  +zd = FA.sqrt(FA.sub(FA.mul(rad, rad), FA.mul(xd, xd)))
  try_x(FRN.random(rng), xd, zd, x1, z1, limit, items)

def try_radius(got: U32 & R.Rng, +windows: Bool, +range: U32, +x1: FR.F64, +z1: FR.F64, +limit: FR.F64, +items: List<&2, Item>) -> Try:
  (+x, rng) = got
  try_diff(FRN.random(rng), FA.mul(OW.pow_08_of_output(windows, x), FR.from_u32(range)), x1, z1, limit, items)

def tries(n: Nat, +t: Try, +windows: Bool, +range: U32, +x1: FR.F64, +z1: FR.F64, +limit: FR.F64, +items: List<&2, Item>) -> Try:
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
              tries(p, try_radius(R.draw(rng), windows, range, x1, z1, limit, items), windows, range, x1, z1, limit, items)

def ground_of(+v: FR.F64, +size: U32) -> FR.F64:
  +base = FA.add(FA.mul(FR.from_u32(size), FR.half()), FR.half())
  FR.floor(FA.add(base, FA.div(v, FR.from_u32(OQ.tile_scale()))))

def inside(+v: FR.F64, +size: U32) -> Bool:
  +edge = OQ.ocean_population_edge_dist()
  FC.gt(v, FR.from_u32(edge)) && FC.lt(v, FR.from_u32((size - edge : U32)))

def valid_tile(+tile: U32, valid: List<&2, U32>) -> Bool:
  match valid:
    case Nil{}:
      False{}
    case Con{+t, rest}:
      U32.is_eq(t, tile) || valid_tile(tile, rest)

def moon_beach(+tile: U32) -> Bool:
  U32.is_eq(tile, EN.tile_pebblebeach()) || U32.is_eq(tile, EN.tile_meteor()) || U32.is_eq(tile, EN.tile_shellbeach())

# One tile of the wobster closure: NONE to go on, else its prefab.
def wobster_tile(+tile: U32) -> U32:
  +usable = Bool.not(TG.is_invalid(tile)) && U32.is_ne(tile, EN.tile_rocky())
  +results = OQ.bunch_closure_results(0)
  Bool.pick(U32, usable && moon_beach(tile), B.at(results, 0),
    Bool.pick(U32, usable && Bool.not(TG.is_ocean(tile)), B.at(results, 1), B.none()))

def wobster_step(got: GR.Grid & U32, +found: U32) -> GR.Grid & U32:
  (g, +tile) = got
  (g, Bool.pick(U32, U32.is_eq(found, B.none()), wobster_tile(tile), found))

def wobster_offsets() -> List<&2, U32>:
  [4294967292, 4, 0, 4, 4, 4, 4294967292, 0, 0, 0, 4, 0, 4294967292, 4294967292, 0, 4294967292, 4, 4294967292]

def wobster_loop(offs: List<&2, U32>, got: GR.Grid & U32, +x: U32, +z: U32) -> GR.Grid & U32:
  match offs:
    case Con{+ox, Con{+oz, rest}}:
      (g, +found) = got
      wobster_loop(rest, wobster_step(PT.get_tile(g, (x + ox : U32), (z + oz : U32)), found), x, z)
    case _:
      got

# wobster_den_spawner_shore's prefab closure at the spawner tile: the first tile of the 3 x 3 (step 4, rows z + 4
# down to z - 4) that is neither invalid nor ROCKY decides (a moon beach: moonglass_wobster_den; not ocean:
# wobster_den; ocean: go on); NONE when none does.
def wobster(g: GR.Grid, +x: U32, +z: U32) -> GR.Grid & U32:
  wobster_loop(wobster_offsets(), (g, B.none()), x, z)

def item_prefab(closure: Bool, g: GR.Grid, +item: U32, +x: U32, +z: U32) -> GR.Grid & U32:
  match closure:
    case True{}:
      wobster(g, x, z)
    case False{}:
      (g, item)

# The bunch spawner's state: the tiles (read only), the RNG and the entities.
type Bun is Type:
  Bun{g: GR.Grid, rng: R.Rng, ents: List<&2, OE.Ent>}

def kept(got: GR.Grid & U32, +x: FR.F64, +z: FR.F64, rng: R.Rng, +ents: List<&2, OE.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  (g, +prefab) = got
  (Bun{g, rng, ents}, Bool.pick(List<&2, Item>, B.is_none(prefab), items, Item{prefab, x, z} <> items))

def place_ok(ok: Bool, g: GR.Grid, +item: U32, +tx: U32, +tz: U32, +x: FR.F64, +z: FR.F64, rng: R.Rng, +ents: List<&2, OE.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  match ok:
    case False{}:
      (Bun{g, rng, ents}, items)
    case True{}:
      kept(item_prefab(B.is_none(item), g, item, tx, tz), x, z, rng, ents, items)

def tile_checked(got: GR.Grid & U32, +sp: Spawner, +tx: U32, +tz: U32, +x: FR.F64, +z: FR.F64, rng: R.Rng, +ents: List<&2, OE.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  (g, +tile) = got
  match sp:
    case Spawner{_, +item, _, _, _, _, +valid}:
      +ok = Bool.not(TG.is_invalid(tile)) && valid_tile(tile, valid)
      place_ok(ok, g, item, tx, tz, x, z, rng, ents, items)

def ground_if(inside_map: Bool, g: GR.Grid, +sp: Spawner, +fx: FR.F64, +fz: FR.F64, +x: FR.F64, +z: FR.F64, rng: R.Rng, +ents: List<&2, OE.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  match inside_map:
    case False{}:
      (Bun{g, rng, ents}, items)
    case True{}:
      +tx = FR.to_i32(fx)
      +tz = FR.to_i32(fz)
      tile_checked(PT.get_tile(g, tx, tz), sp, tx, tz, x, z, rng, ents, items)

def placed(+t: Try, +c: OS.Ctx, +sp: Spawner, g: GR.Grid, +ents: List<&2, OE.Ent>, +items: List<&2, Item>) -> Bun & List<&2, Item>:
  match t:
    case Try{+x, +z, _, +rng}:
      +fx = ground_of(x, OS.width_of(c))
      +fz = ground_of(z, OS.height_of(c))
      ground_if(inside(fx, OS.width_of(c)) && inside(fz, OS.height_of(c)), g, sp, fx, fz, x, z, rng, ents, items)

# placeitemoffgrids: the tries, then the last try's position when its ground is valid.
def place_item(+c: OS.Ctx, +sp: Spawner, +x1: FR.F64, +z1: FR.F64, got: Bun & List<&2, Item>) -> Bun & List<&2, Item>:
  match sp:
    case Spawner{_, _, +range, _, _, +spacing, _}:
      (b, +items) = got
      match b:
        case Bun{g, +rng, +ents}:
          +limit = FR.from_u32((spacing * spacing : U32))
          +t = tries(U32.to_nat(20), Try{x1, z1, True{}, rng}, OS.windows_of(c), range, x1, z1, limit, items)
          placed(t, c, sp, g, ents, items)

def items_loop(n: Nat, +c: OS.Ctx, +sp: Spawner, +x1: FR.F64, +z1: FR.F64, got: Bun & List<&2, Item>) -> Bun & List<&2, Item>:
  match n:
    case 0n:
      got
    case 1n+p:
      items_loop(p, c, sp, x1, z1, place_item(c, sp, x1, z1, got))

def exported(items: List<&2, Item>, +ents: List<&2, OE.Ent>) -> List<&2, OE.Ent>:
  match items:
    case Nil{}:
      ents
    case Con{Item{+prefab, +x, +z}, rest}:
      exported(rest, OE.Ent{prefab, x, z, 0, 0} <> ents)

def batch_done(got: Bun & List<&2, Item>) -> Bun:
  (b, +items) = got
  match b:
    case Bun{g, +rng, +ents}:
      Bun{g, rng, exported(List.reverse(&2, Item, items), ents)}

def batch_counted(got: U32 & R.Rng, +c: OS.Ctx, +sp: Spawner, +x: FR.F64, +z: FR.F64, g: GR.Grid, +ents: List<&2, OE.Ent>) -> Bun:
  (+number, rng) = got
  batch_done(items_loop(U32.to_nat(number), c, sp, x, z, (Bun{g, rng, ents}, Nil{})))

# BunchSpawnerRunSingleBatchSpawner at a spawner entity.
def batch(+c: OS.Ctx, +sp: Spawner, +e: OE.Ent, b: Bun) -> Bun:
  match sp e b:
    case Spawner{_, _, _, +min, +max, _, _} OE.Ent{_, +x, +z, _, _} Bun{g, +rng, +ents}:
      batch_counted(LM.random_range(rng, min, max), c, sp, x, z, g, ents)

def spawners_loop(xs: List<&2, OE.Ent>, +c: OS.Ctx, +sp: Spawner, b: Bun) -> Bun:
  match xs:
    case Nil{}:
      b
    case Con{+e, rest}:
      spawners_loop(rest, c, sp, batch(c, sp, e, b))

def spawner_prefab(+sp: Spawner) -> U32:
  match sp:
    case Spawner{+spawner, _, _, _, _, _, _}:
      spawner

def kinds_loop(n: Nat, +c: OS.Ctx, +i: U32, b: Bun) -> Bun:
  match n:
    case 0n:
      b
    case 1n+p:
      match b:
        case Bun{g, +rng, +ents}:
          +sp = spawner_of(OC.bunches(i))
          +found = OE.of_prefab(ents, spawner_prefab(sp))
          kinds_loop(p, c, (i + 1 : U32), spawners_loop(found, c, sp, Bun{g, rng, ents}))

def bunches_done(b: Bun, +c: OS.Ctx, ids: GR.Grid, +topo: U32, +events: List<&2, OS.Ev>, +before: R.Rng, +count: U32) -> OS.Sea:
  match b:
    case Bun{g, +rng, +ents}:
      +added = (U32.from_nat(List.length(&2, OE.Ent, ents)) - count : U32)
      noted = OS.noted(c, OS.Sea{g, ids, rng, ents, topo, events}, OS.EBunches{before, rng, ents, added})
      OS.digest(c, OS.noted(c, noted, OS.EFinal{ents}), 9)

# BunchSpawnerRun(WorldSim) on savedata.ents.
def bunches(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      b = kinds_loop(U32.to_nat(OC.bunches_count()), c, 0, Bun{g, rng, ents})
      bunches_done(b, c, ids, topo, events, rng, U32.from_nat(List.length(&2, OE.Ent, ents)))
