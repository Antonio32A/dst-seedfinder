import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../data/blob.bend as Blob
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../data/ocean_post.bend as OceanPostData
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/groups.bend as TileGroups
import ./ents.bend as OceanEnts
import ./state.bend as OceanState

# forest_map.Generate after the ocean: Graph:GlobalPostPopulate (wormhole pairing in marker order, the
# customization and randomization proxies), the impassable filter, and the required prefab check that decides the
# attempt (the bunch spawner runs in between: ocean/bunches.bend).

def pair_loop(markers: List<&2, OceanEnts.Ent>, +id: U32, acc: List<&2, OceanEnts.Ent>) -> List<&2, OceanEnts.Ent>:
  match markers:
    case Con{OceanEnts.Ent{_, +x1, +z1, _, _}, Con{OceanEnts.Ent{_, +x2, +z2, _, _}, rest}}:
      +first = {OceanEnts.Ent{OceanPostData.wormhole_prefab(), x1, z1, id, (id + 1 : U32)} : OceanEnts.Ent}
      +second = {OceanEnts.Ent{OceanPostData.wormhole_prefab(), x2, z2, (id + 1 : U32), id} : OceanEnts.Ent}
      pair_loop(rest, (id + 2 : U32), second <> first <> acc)
    case _:
      List.reverse(&2, OceanEnts.Ent, acc)

# SwapOutWormholeMarkers: consecutive markers become wormhole pairs (ids from MIN_WORMHOLE_ID, each targeting the
# other) at the end of savedata.ents.wormhole; an odd last marker is dropped, and so are the markers.
def swap_wormholes(+ents: List<&2, OceanEnts.Ent>) -> List<&2, OceanEnts.Ent>:
  +pairs = pair_loop(OceanEnts.of_prefab(ents, OceanPostData.wormhole_marker()), OceanPostData.min_wormhole_id(), Nil{})
  OceanEnts.appended(OceanEnts.without(ents, OceanPostData.wormhole_marker()), pairs, OceanPostData.wormhole_prefab())

def customization_loop(n: Nat, +ents: List<&2, OceanEnts.Ent>, +i: U32) -> List<&2, OceanEnts.Ent>:
  match n:
    case 0n:
      ents
    case 1n+p:
      +row = OceanPostData.customization_proxies(i)
      customization_loop(p, OceanEnts.moved(ents, Blob.at(row, 0), Blob.at(row, 1)), (i + 1 : U32))

def chosen(got: U32 & Pcg.Rng, +row: List<&2, U32>, +e: OceanEnts.Ent, +acc: List<&2, OceanEnts.Ent>) -> List<&2, OceanEnts.Ent> & Pcg.Rng:
  (+k, rng) = got
  (OceanEnts.relabeled(e, Blob.at(row, k)) <> acc, rng)

def random_loop(xs: List<&2, OceanEnts.Ent>, +row: List<&2, U32>, got: List<&2, OceanEnts.Ent> & Pcg.Rng) -> List<&2, OceanEnts.Ent> & Pcg.Rng:
  match xs:
    case Nil{}:
      got
    case Con{+e, rest}:
      (+acc, rng) = got
      random_loop(rest, row, chosen(MathRandom.random_upto(rng, (U32.from_nat(List.length(&2, U32, row)) - 1 : U32)), row, e, acc))

def randomization_loop(n: Nat, got: List<&2, OceanEnts.Ent> & Pcg.Rng, +i: U32) -> List<&2, OceanEnts.Ent> & Pcg.Rng:
  match n:
    case 0n:
      got
    case 1n+p:
      (+ents, rng) = got
      +row = OceanPostData.randomization_proxies(i)
      +proxy = Blob.at(row, 0)
      randomization_loop(p, random_loop(OceanEnts.of_prefab(ents, proxy), row, (OceanEnts.without(ents, proxy), rng)), (i + 1 : U32))

def post_done(got: List<&2, OceanEnts.Ent> & Pcg.Rng, +c: OceanState.Ctx, g: Grid.Grid, ids: Grid.Grid, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (+ents, rng) = got
  s = {OceanState.Sea{g, ids, rng, ents, topo, events} : OceanState.Sea}
  OceanState.noted(c, OceanState.digest(c, s, 8), OceanState.EWormholes{OceanEnts.of_prefab(ents, OceanPostData.wormhole_prefab())})

# Graph:GlobalPostPopulate(entities, width, height).
def post_populate(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      +swapped = customization_loop(U32.to_nat(OceanPostData.customization_proxies_count()), swap_wormholes(ents), 0)
      post_done(randomization_loop(U32.to_nat(OceanPostData.randomization_proxies_count()), (swapped, rng), 0), c, g, ids, topo, events)


def keep_step(got: Grid.Grid & U32, +e: OceanEnts.Ent, +acc: List<&2, OceanEnts.Ent>) -> Grid.Grid & List<&2, OceanEnts.Ent>:
  (g, +tile) = got
  (g, OceanEnts.keep_if(Bool.not(TileGroups.is_impassable(tile)), e, acc))

def visual_of(+v: F64Repr.F64, +size: U32) -> F64Repr.F64:
  F64Arith.add(F64Arith.div(v, F64Repr.from_u32(OceanPostData.tile_scale())), F64Arith.mul(F64Repr.from_u32(size), F64Repr.half()))

def visible_loop(xs: List<&2, OceanEnts.Ent>, got: Grid.Grid & List<&2, OceanEnts.Ent>, +c: OceanState.Ctx) -> Grid.Grid & List<&2, OceanEnts.Ent>:
  match xs:
    case Nil{}:
      (g, +acc) = got
      (g, List.reverse(&2, OceanEnts.Ent, acc))
    case Con{OceanEnts.Ent{+prefab, +x, +z, +id, +target}, rest}:
      (g, +acc) = got
      tile_at = Points.visual_tile(g, visual_of(x, OceanState.width_of(c)), visual_of(z, OceanState.height_of(c)))
      visible_loop(rest, keep_step(tile_at, OceanEnts.Ent{prefab, x, z, id, target}, acc), c)

def filtered(got: Grid.Grid & List<&2, OceanEnts.Ent>, +c: OceanState.Ctx, ids: Grid.Grid, rng: Pcg.Rng, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (g, +ents) = got
  OceanState.noted(c, OceanState.Sea{g, ids, rng, ents, topo, events}, OceanState.ECounts{1, ents})

# The impassable filter: every entity whose GetVisualTileAtPosition(x / 4 + width / 2, z / 4 + height / 2) is an
# impassable tile is removed.
def impassable_filter(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, rng, +ents, +topo, +events}:
      filtered(visible_loop(ents, (g, Nil{}), c), c, ids, rng, topo, events)

# A required prefab and its count (forest_map's double_check).
type Req is Data:
  Req{prefab: U32, count: U32}

def add_loop(reqs: List<&2, Req>, +prefab: U32, +count: U32, +done: Bool) -> List<&2, Req>:
  match reqs:
    case Nil{}:
      Bool.pick(List<&2, Req>, done, Nil{}, [Req{prefab, count}])
    case Con{Req{+p, +n}, rest}:
      +hit = U32.is_eq(p, prefab) && Bool.not(done)
      Req{p, Bool.pick(U32, hit, (n + count : U32), n)} <> add_loop(rest, prefab, count, done || hit)

# double_check[prefab] += count.
def add_required(+reqs: List<&2, Req>, +prefab: U32, +count: U32) -> List<&2, Req>:
  add_loop(reqs, prefab, count, False{})

def add_ones(xs: List<&2, U32>, +reqs: List<&2, Req>) -> List<&2, Req>:
  match xs:
    case Nil{}:
      reqs
    case Con{+prefab, rest}:
      add_ones(rest, add_required(reqs, prefab, 1))

def add_all(xs: List<&2, Req>, +reqs: List<&2, Req>) -> List<&2, Req>:
  match xs:
    case Nil{}:
      reqs
    case Con{Req{+prefab, +count}, rest}:
      add_all(rest, add_required(reqs, prefab, count))

def ocean_required(rooms: List<&2, U32>, +reqs: List<&2, Req>) -> List<&2, Req>:
  match rooms:
    case Nil{}:
      reqs
    case Con{+room, rest}:
      ocean_required(rest, add_ones(Rooms.room_required_prefabs(room), reqs))

# forest_map's double_check: level.required_prefabs, the root's GetRequiredPrefabs() and the ocean rooms'
# required_prefabs.
def double_check(+root: List<&2, Req>) -> List<&2, Req>:
  ocean_required(Tasks.lists(9), add_all(root, add_ones(OceanPostData.level_required_prefabs(0), Nil{})))

def check_loop(reqs: List<&2, Req>, +ents: List<&2, OceanEnts.Ent>, +c: OceanState.Ctx, s: OceanState.Sea, +missing: List<&2, U32>) -> OceanState.Sea & List<&2, U32>:
  match reqs:
    case Nil{}:
      (s, List.reverse(&2, U32, missing))
    case Con{Req{+prefab, +count}, rest}:
      +have = OceanEnts.count(ents, prefab)
      +short = (have < count : U32)
      check_loop(rest, ents, c, OceanState.noted(c, s, OceanState.EReq{prefab, count, have}), Bool.pick(List<&2, U32>, short, prefab <> missing, missing))

def checked(got: OceanState.Sea & List<&2, U32>, +c: OceanState.Ctx) -> OceanState.Sea & Bool:
  (s, +missing) = got
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      +ok = List.is_empty(&2, U32, missing)
      (OceanState.noted(c, OceanState.Sea{g, ids, rng, ents, topo, events}, OceanState.EStatus{ok, missing, rng}), ok)

# The required prefab check: true when every prefab has at least its count (else Generate returns nil).
def required(+reqs: List<&2, Req>, +c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea & Bool:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      checked(check_loop(reqs, ents, c, OceanState.Sea{g, ids, rng, ents, topo, events}, Nil{}), c)
