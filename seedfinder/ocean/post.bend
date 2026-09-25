import Base
import ../rng/pcg.bend as R
import ../lua/math_random.bend as LM
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../data/blob.bend as B
import ../data/rooms.bend as RM
import ../data/tasks.bend as TK
import ../data/ocean_post.bend as OQ
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/groups.bend as TG
import ./ents.bend as OE
import ./state.bend as OS

# forest_map.Generate after the ocean: Graph:GlobalPostPopulate (wormhole pairing in marker order, the
# customization and randomization proxies), the impassable filter, and the required prefab check that decides the
# attempt (the bunch spawner runs in between: ocean/bunches.bend).

def pair_loop(markers: List<&2, OE.Ent>, +id: U32, acc: List<&2, OE.Ent>) -> List<&2, OE.Ent>:
  match markers:
    case Con{OE.Ent{_, +x1, +z1, _, _}, Con{OE.Ent{_, +x2, +z2, _, _}, rest}}:
      +first = {OE.Ent{OQ.wormhole_prefab(), x1, z1, id, (id + 1 : U32)} : OE.Ent}
      +second = {OE.Ent{OQ.wormhole_prefab(), x2, z2, (id + 1 : U32), id} : OE.Ent}
      pair_loop(rest, (id + 2 : U32), second <> first <> acc)
    case _:
      List.reverse(&2, OE.Ent, acc)

# SwapOutWormholeMarkers: consecutive markers become wormhole pairs (ids from MIN_WORMHOLE_ID, each targeting the
# other) at the end of savedata.ents.wormhole; an odd last marker is dropped, and so are the markers.
def swap_wormholes(+ents: List<&2, OE.Ent>) -> List<&2, OE.Ent>:
  +pairs = pair_loop(OE.of_prefab(ents, OQ.wormhole_marker()), OQ.min_wormhole_id(), Nil{})
  OE.appended(OE.without(ents, OQ.wormhole_marker()), pairs, OQ.wormhole_prefab())

def customization_loop(n: Nat, +ents: List<&2, OE.Ent>, +i: U32) -> List<&2, OE.Ent>:
  match n:
    case 0n:
      ents
    case 1n+p:
      +row = OQ.customization_proxies(i)
      customization_loop(p, OE.moved(ents, B.at(row, 0), B.at(row, 1)), (i + 1 : U32))

def chosen(got: U32 & R.Rng, +row: List<&2, U32>, +e: OE.Ent, +acc: List<&2, OE.Ent>) -> List<&2, OE.Ent> & R.Rng:
  (+k, rng) = got
  (OE.relabeled(e, B.at(row, k)) <> acc, rng)

def random_loop(xs: List<&2, OE.Ent>, +row: List<&2, U32>, got: List<&2, OE.Ent> & R.Rng) -> List<&2, OE.Ent> & R.Rng:
  match xs:
    case Nil{}:
      got
    case Con{+e, rest}:
      (+acc, rng) = got
      random_loop(rest, row, chosen(LM.random_upto(rng, (U32.from_nat(List.length(&2, U32, row)) - 1 : U32)), row, e, acc))

def randomization_loop(n: Nat, got: List<&2, OE.Ent> & R.Rng, +i: U32) -> List<&2, OE.Ent> & R.Rng:
  match n:
    case 0n:
      got
    case 1n+p:
      (+ents, rng) = got
      +row = OQ.randomization_proxies(i)
      +proxy = B.at(row, 0)
      randomization_loop(p, random_loop(OE.of_prefab(ents, proxy), row, (OE.without(ents, proxy), rng)), (i + 1 : U32))

def post_done(got: List<&2, OE.Ent> & R.Rng, +c: OS.Ctx, g: GR.Grid, ids: GR.Grid, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  (+ents, rng) = got
  s = {OS.Sea{g, ids, rng, ents, topo, events} : OS.Sea}
  OS.noted(c, OS.digest(c, s, 8), OS.EWormholes{OE.of_prefab(ents, OQ.wormhole_prefab())})

# Graph:GlobalPostPopulate(entities, width, height).
def post_populate(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      +swapped = customization_loop(U32.to_nat(OQ.customization_proxies_count()), swap_wormholes(ents), 0)
      post_done(randomization_loop(U32.to_nat(OQ.randomization_proxies_count()), (swapped, rng), 0), c, g, ids, topo, events)


def keep_step(got: GR.Grid & U32, +e: OE.Ent, +acc: List<&2, OE.Ent>) -> GR.Grid & List<&2, OE.Ent>:
  (g, +tile) = got
  (g, OE.keep_if(Bool.not(TG.is_impassable(tile)), e, acc))

def visual_of(+v: FR.F64, +size: U32) -> FR.F64:
  FA.add(FA.div(v, FR.from_u32(OQ.tile_scale())), FA.mul(FR.from_u32(size), FR.half()))

def visible_loop(xs: List<&2, OE.Ent>, got: GR.Grid & List<&2, OE.Ent>, +c: OS.Ctx) -> GR.Grid & List<&2, OE.Ent>:
  match xs:
    case Nil{}:
      (g, +acc) = got
      (g, List.reverse(&2, OE.Ent, acc))
    case Con{OE.Ent{+prefab, +x, +z, +id, +target}, rest}:
      (g, +acc) = got
      tile_at = PT.visual_tile(g, visual_of(x, OS.width_of(c)), visual_of(z, OS.height_of(c)))
      visible_loop(rest, keep_step(tile_at, OE.Ent{prefab, x, z, id, target}, acc), c)

def filtered(got: GR.Grid & List<&2, OE.Ent>, +c: OS.Ctx, ids: GR.Grid, rng: R.Rng, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  (g, +ents) = got
  OS.noted(c, OS.Sea{g, ids, rng, ents, topo, events}, OS.ECounts{1, ents})

# The impassable filter: every entity whose GetVisualTileAtPosition(x / 4 + width / 2, z / 4 + height / 2) is an
# impassable tile is removed.
def impassable_filter(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match s:
    case OS.Sea{g, ids, rng, +ents, +topo, +events}:
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
      ocean_required(rest, add_ones(RM.room_required_prefabs(room), reqs))

# forest_map's double_check: level.required_prefabs, the root's GetRequiredPrefabs() and the ocean rooms'
# required_prefabs.
def double_check(+root: List<&2, Req>) -> List<&2, Req>:
  ocean_required(TK.lists(9), add_all(root, add_ones(OQ.level_required_prefabs(0), Nil{})))

def check_loop(reqs: List<&2, Req>, +ents: List<&2, OE.Ent>, +c: OS.Ctx, s: OS.Sea, +missing: List<&2, U32>) -> OS.Sea & List<&2, U32>:
  match reqs:
    case Nil{}:
      (s, List.reverse(&2, U32, missing))
    case Con{Req{+prefab, +count}, rest}:
      +have = OE.count(ents, prefab)
      +short = (have < count : U32)
      check_loop(rest, ents, c, OS.noted(c, s, OS.EReq{prefab, count, have}), Bool.pick(List<&2, U32>, short, prefab <> missing, missing))

def checked(got: OS.Sea & List<&2, U32>, +c: OS.Ctx) -> OS.Sea & Bool:
  (s, +missing) = got
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      +ok = List.is_empty(&2, U32, missing)
      (OS.noted(c, OS.Sea{g, ids, rng, ents, topo, events}, OS.EStatus{ok, missing, rng}), ok)

# The required prefab check: true when every prefab has at least its count (else Generate returns nil).
def required(+reqs: List<&2, Req>, +c: OS.Ctx, s: OS.Sea) -> OS.Sea & Bool:
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      checked(check_loop(reqs, ents, c, OS.Sea{g, ids, rng, ents, topo, events}, Nil{}), c)
