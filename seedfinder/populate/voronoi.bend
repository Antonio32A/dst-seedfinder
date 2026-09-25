import Base
import ../rng/pcg.bend as R
import ../lua/math_random.bend as LM
import ../f64/repr.bend as FR
import ../data/blob.bend as B
import ../data/distribute.bend as DS
import ../data/rooms.bend as RM
import ../data/story.bend as SY
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/groups.bend as TG
import ../storygen/graph.bend as GG
import ./entities.bend as PE
import ./counts.bend as PC
import ./nodes.bend as PN
import ./state.bend as PS

# Node:PopulateVoronoi (graphnode.lua) and Graph:PopulateVoronoi's traversal: GetPointsForSite, the countprefabs,
# the map tag items, then the distributed prefabs, each through Node:AddEntity (dropped off land, else ReserveTile
# and a position with the random offset).

def found_kind(xs: List<&2, PN.Count>, found: Bool, +prefab: U32, +kind: U32) -> U32:
  match xs:
    case Nil{}:
      Bool.pick(U32, found, kind, 0)
    case Con{PN.Count{+k, +v, _}, rest}:
      match found:
        case True{}:
          kind
        case False{}:
          found_kind(rest, U32.is_eq(k, prefab), prefab, v)

# The prefabdata value kind for a prefab (1 = a closure to call), 0 when it has none.
def data_kind(+xs: List<&2, PN.Count>, +prefab: U32) -> U32:
  found_kind(xs, False{}, prefab, 0)

def placed(got: GR.Grid & Bool, +c: PS.Ctx, +prefab: U32, +p: PT.Pt, +kind: U32, +rng: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, PS.Ev>) -> PS.Land:
  (g, _) = got
  match p:
    case PT.Pt{+x, +y, _}:
      +e = PE.tile_entity(prefab, x, y, PS.width_of(c), PS.height_of(c), True{}, rng)
      PS.added_in(c, PS.Land{g, rng, ents, events}, PE.with_rng(e, PC.prefab_data_call(kind, PE.rng_of(e))))

def add_on(land: Bool, g: GR.Grid, +c: PS.Ctx, +prefab: U32, +p: PT.Pt, +kind: U32, rng: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, PS.Ev>) -> PS.Land:
  match land:
    case False{}:
      PS.Land{g, rng, ents, events}
    case True{}:
      match p:
        case PT.Pt{+x, +y, +t}:
          placed(PT.reserve_tile(g, x, y), c, prefab, PT.Pt{x, y, t}, kind, rng, ents, events)

def add_tile(got: GR.Grid & U32, +c: PS.Ctx, +prefab: U32, +p: PT.Pt, +kind: U32, rng: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, PS.Ev>) -> PS.Land:
  (g, +tile) = got
  add_on(TG.is_land(tile), g, c, prefab, p, kind, rng, ents, events)

# Node:AddEntity with rand_offset: GetTile, then PopulateWorld_AddEntity on land (`kind` 1: call the prefabdata
# closure after the offsets).
def add_entity(+c: PS.Ctx, +prefab: U32, +p: PT.Pt, +kind: U32, l: PS.Land) -> PS.Land:
  match p:
    case PT.Pt{+x, +y, +t}:
      match l:
        case PS.Land{g, +rng, +ents, +events}:
          add_tile(PT.get_tile(g, x, y), c, prefab, PT.Pt{x, y, t}, kind, rng, ents, events)

def point_tile(+p: PT.Pt) -> U32:
  match p:
    case PT.Pt{_, _, +t}:
      t

# A node's population in progress: the unused points, and false once PopulateVoronoi returned early.
type Walk is Type:
  Walk{land: PS.Land, pts: List<&2, PT.Pt>, alive: Bool}

def place_count(n: Nat, w: Walk, +c: PS.Ctx, +prefab: U32, +kind: U32) -> Walk:
  match n:
    case 0n:
      w
    case 1n+p:
      match w:
        case Walk{l, +pts, +alive}:
          match pts:
            case Nil{}:
              Walk{l, Nil{}, alive}
            case Con{+pt, rest}:
              place_count(p, Walk{add_entity(c, prefab, pt, kind, l), rest, alive}, c, prefab, kind)

def still(w: Walk) -> Walk:
  match w:
    case Walk{l, +pts, +alive}:
      Walk{l, pts, alive && Bool.not(List.is_empty(&2, PT.Pt, pts))}

type Counted is Data:
  Counted{key: U32, count: U32}

def found_count(xs: List<&2, Counted>, found: Bool, +key: U32, +count: U32) -> U32:
  match xs:
    case Nil{}:
      Bool.pick(U32, found, count, 0)
    case Con{Counted{+k, +n}, rest}:
      match found:
        case True{}:
          count
        case False{}:
          found_count(rest, U32.is_eq(k, key), key, n)

def place_counts(keys: List<&2, U32>, w: Walk, +counts: List<&2, Counted>, +data: List<&2, PN.Count>, +c: PS.Ctx) -> Walk:
  match keys:
    case Nil{}:
      w
    case Con{+key, rest}:
      match w:
        case Walk{l, +pts, +alive}:
          match alive:
            case False{}:
              Walk{l, pts, False{}}
            case True{}:
              +kind = data_kind(data, key)
              +n = found_count(counts, False{}, key, 0)
              place_counts(rest, still(place_count(U32.to_nat(n), Walk{l, pts, True{}}, c, key, kind)), counts, data, c)

type Evaluated is Data:
  Evaluated{counts: List<&2, Counted>, total: U32, rng: R.Rng}

def keep_counted(pending: Bool, +key: U32, +n: U32, +acc: List<&2, Counted>) -> List<&2, Counted>:
  match pending:
    case True{}:
      Counted{key, n} <> acc
    case False{}:
      acc

# The countprefabs values in pairs() order (closures called with the kept point count), and their sum.
def evaluate(xs: List<&2, PN.Count>, got: U32 & R.Rng, +key: U32, +pending: Bool, +area: U32, +width: U32, +acc: List<&2, Counted>, +total: U32) -> Evaluated:
  match xs:
    case Nil{}:
      (+n, rng) = got
      Evaluated{keep_counted(pending, key, n, acc), (total + n : U32), rng}
    case Con{PN.Count{+k, +kind, +v}, rest}:
      (+n, rng) = got
      evaluate(rest, PC.value_of(kind, v, area, width, rng), k, True{}, area, width, keep_counted(pending, key, n, acc), (total + n : U32))

def counts_if(enough: Bool, l: PS.Land, +pts: List<&2, PT.Pt>, +order: List<&2, U32>, +counts: List<&2, Counted>, +data: List<&2, PN.Count>, +c: PS.Ctx) -> Walk:
  match enough:
    case False{}:
      Walk{l, pts, False{}}
    case True{}:
      place_counts(order, Walk{l, pts, True{}}, counts, data, c)

def counted_walk(e: Evaluated, l: PS.Land, +pts: List<&2, PT.Pt>, +order: List<&2, U32>, +data: List<&2, PN.Count>, +c: PS.Ctx) -> Walk:
  match e:
    case Evaluated{+counts, +total, +rng}:
      +enough = Bool.not((U32.from_nat(List.length(&2, PT.Pt, pts)) < total : U32))
      counts_if(enough, PS.with_rng(l, rng), pts, order, counts, data, c)

def extra_step(alive: Bool, l: PS.Land, +pt: PT.Pt, +more: List<&2, PT.Pt>, +prefab: U32, +c: PS.Ctx) -> Walk:
  match alive:
    case False{}:
      Walk{l, pt <> more, False{}}
    case True{}:
      Walk{add_entity(c, prefab, pt, 0, l), more, True{}}

def place_extras(xs: List<&2, U32>, w: Walk, +c: PS.Ctx) -> Walk:
  match xs:
    case Nil{}:
      w
    case Con{+prefab, rest}:
      match w:
        case Walk{l, +pts, +alive}:
          match pts:
            case Nil{}:
              Walk{l, Nil{}, False{}}
            case Con{+pt, +more}:
              place_extras(rest, still(extra_step(alive, l, pt, more, prefab, c)), c)

def fold_choice(pending: Bool, +index: U32, +count: U32, +v: U32) -> U32:
  match pending:
    case False{}:
      index
    case True{}:
      ((index * count : U32) + (U32.min(v, count) - 1 : U32) : U32)

# resolveswappableprefabs: one GetRandomItem (math.random(n)) per swappable entry, in pairs() order, as the mixed
# radix case index (first entry most significant).
def resolve(n: Nat, +entries: List<&2, U32>, +index: U32, got: U32 & R.Rng, +count: U32, +pending: Bool) -> U32 & R.Rng:
  match n:
    case 0n:
      (+v, rng) = got
      (fold_choice(pending, index, count, v), rng)
    case 1n+p:
      (+v, rng) = got
      +next = B.at(entries, 1)
      resolve(p, B.drop(entries, 2), fold_choice(pending, index, count, v), LM.random_upto(rng, next), next, True{})

def distribute_add(skip: Bool, l: PS.Land, +c: PS.Ctx, +prefab: U32, +pt: PT.Pt, +data: List<&2, PN.Count>) -> PS.Land:
  match skip:
    case True{}:
      l
    case False{}:
      add_entity(c, prefab, pt, data_kind(data, prefab), l)

def distribute_pick(got: U32 & R.Rng, l: PS.Land, +c: PS.Ctx, +pt: PT.Pt, +kind_of: List<&2, PN.Count>) -> PS.Land:
  (+prefab, rng) = got
  distribute_add(U32.is_eq(prefab, 4294967295), PS.with_rng(l, rng), c, prefab, pt, kind_of)

# pickspawnprefab's prepared items per tile seen so far in the node (the variant is fixed per node).
type Cached is Data:
  Cached{tile: U32, items: PC.Prepared}

def cache_hit(xs: List<&2, Cached>, +tile: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{Cached{+t, _}, rest}:
      U32.is_eq(t, tile) || cache_hit(rest, tile)

def cache_get(xs: List<&2, Cached>, +tile: U32) -> PC.Prepared:
  match xs:
    case Nil{}:
      PC.Prepared{Nil{}, FR.zero()}
    case Con{Cached{+t, +p}, rest}:
      Bool.pick(PC.Prepared, U32.is_eq(t, tile), p, cache_get(rest, tile))

def cache_with(hit: Bool, +cache: List<&2, Cached>, +variant: U32, +tile: U32) -> List<&2, Cached>:
  match hit:
    case True{}:
      cache
    case False{}:
      Cached{tile, PC.prepare(variant, tile)} <> cache

type Spread is Type:
  Spread{land: PS.Land, cache: List<&2, Cached>}

def distribute_cached(l: PS.Land, +kept: List<&2, Cached>, +c: PS.Ctx, +pt: PT.Pt, +data: List<&2, PN.Count>) -> Spread:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      Spread{distribute_pick(PC.pick_prepared(cache_get(kept, point_tile(pt)), rng), PS.Land{g, rng, ents, events}, c, pt, data), kept}

def distribute_try(hit: Bool, l: PS.Land, +cache: List<&2, Cached>, +c: PS.Ctx, +variant: U32, +pt: PT.Pt, +data: List<&2, PN.Count>) -> Spread:
  match hit:
    case False{}:
      Spread{l, cache}
    case True{}:
      +tile = point_tile(pt)
      distribute_cached(l, cache_with(cache_hit(cache, tile), cache, variant, tile), c, pt, data)

def distribute_drawn(got: U32 & R.Rng, l: PS.Land, +cache: List<&2, Cached>, +c: PS.Ctx, +variant: U32, +threshold: U32, +pt: PT.Pt, +data: List<&2, PN.Count>) -> Spread:
  (+x, rng) = got
  distribute_try((x < threshold : U32), PS.with_rng(l, rng), cache, c, variant, pt, data)

def distribute_one(sp: Spread, +c: PS.Ctx, +variant: U32, +threshold: U32, +pt: PT.Pt, +data: List<&2, PN.Count>) -> Spread:
  match sp:
    case Spread{l, +cache}:
      match l:
        case PS.Land{g, +rng, +ents, +events}:
          distribute_drawn(R.draw(rng), PS.Land{g, rng, ents, events}, cache, c, variant, threshold, pt, data)

def distribute_loop(pts: List<&2, PT.Pt>, sp: Spread, +c: PS.Ctx, +variant: U32, +threshold: U32, +data: List<&2, PN.Count>) -> PS.Land:
  match pts:
    case Nil{}:
      match sp:
        case Spread{l, _}:
          l
    case Con{+pt, rest}:
      distribute_loop(rest, distribute_one(sp, c, variant, threshold, pt, data), c, variant, threshold, data)

def distribute_resolved(got: U32 & R.Rng, l: PS.Land, +c: PS.Ctx, +node: U32, +pts: List<&2, PT.Pt>) -> PS.Land:
  (+index, rng) = got
  +s = PS.story_of(c)
  +room = PN.room(s, node)
  +variant = DS.variant(room, GG.nf(s, node, GG.f_depth()), ((index * 8 : U32) + PS.swaps_of(c) : U32))
  distribute_loop(pts, Spread{PS.with_rng(l, rng), Nil{}}, c, variant, RM.distribute_threshold(room), PN.prefabdata(s, node))

def distribute_if(go: Bool, l: PS.Land, +pts: List<&2, PT.Pt>, +c: PS.Ctx, +node: U32) -> PS.Land:
  match go:
    case False{}:
      l
    case True{}:
      match l:
        case PS.Land{g, +rng, +ents, +events}:
          +row = DS.cases(PN.row(PS.story_of(c), node))
          distribute_resolved(resolve(U32.to_nat(B.at(row, 0)), B.drop(row, 1), 0, (0, rng), 0, False{}), PS.Land{g, rng, ents, events}, c, node, pts)

def distribute(on: Bool, w: Walk, +c: PS.Ctx, +node: U32) -> PS.Land:
  match w:
    case Walk{l, +pts, +alive}:
      distribute_if(on && alive, l, pts, c, node)

def counted_alive(alive: Bool, l: PS.Land, +pts: List<&2, PT.Pt>, +c: PS.Ctx, +node: U32) -> Walk:
  match alive:
    case False{}:
      Walk{l, pts, False{}}
    case True{}:
      match l:
        case PS.Land{g, +rng, +ents, +events}:
          +s = PS.story_of(c)
          +area = U32.from_nat(List.length(&2, PT.Pt, pts))
          counted_walk(evaluate(PN.countprefabs(s, node), (0, rng), 0, False{}, area, PS.width_of(c), Nil{}, 0),
            PS.Land{g, rng, ents, events}, pts, PN.generate_order(s, node), PN.prefabdata(s, node), c)

def counted(on: Bool, w: Walk, +c: PS.Ctx, +node: U32) -> Walk:
  match on:
    case False{}:
      w
    case True{}:
      match w:
        case Walk{l, +pts, +alive}:
          counted_alive(alive, l, pts, c, node)

def points_noted(tracing: Bool, +ev: PS.Ev, +events: List<&2, PS.Ev>) -> List<&2, PS.Ev>:
  match tracing:
    case True{}:
      ev <> events
    case False{}:
      events

def populate_points(p: PT.Picked, +c: PS.Ctx, +node: U32, +before: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, PS.Ev>) -> PS.Land:
  match p:
    case PT.Picked{g, +rng, +n, +shuffled, +kept}:
      +s = PS.story_of(c)
      +alive = Bool.not(List.is_empty(&2, PT.Pt, kept))
      +on = PN.has_distribute_percent(s, node) && PN.has_distribute(s, node)
      +noted = points_noted(PS.tracing_of(c), PS.EPoints{node, n, before, rng, shuffled, kept}, events)
      distribute(on, place_extras(PN.extra_prefabs(s, node), counted(PN.has_countprefabs(s, node),
        Walk{PS.Land{g, rng, ents, noted}, kept, alive}, c, node), c), c, node)

def populate_body(skip: Bool, l: PS.Land, +c: PS.Ctx, +node: U32) -> PS.Land:
  match skip:
    case True{}:
      l
    case False{}:
      match l:
        case PS.Land{g, +rng, +ents, +events}:
          populate_points(PT.points_for_site(PS.windows_of(c), PS.sites_of(c), PS.site_of(c, node), g, rng), c, node, rng, ents, events)

def skipped(+s: GG.St, +node: U32) -> Bool:
  +none = Bool.not(PN.has_countprefabs(s, node)) && Bool.not(PN.has_distribute(s, node))
  SY.is_impassable(PN.tile(s, node)) || Bool.not(PN.has_contents(s, node)) || none

def noted_node(got: PS.Land & R.Rng, +node: U32, +before: R.Rng) -> PS.Land:
  (l, +after) = got
  PS.noted(l, PS.EPopulateNode{node, before, after})

# Node:PopulateVoronoi for one story node.
def populate_node(+c: PS.Ctx, +node: U32, l: PS.Land) -> PS.Land:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      noted_node(PS.rng_of(populate_body(skipped(PS.story_of(c), node), PS.Land{g, rng, ents, events}, c, node)), node, rng)

def populate_loop(nodes: List<&2, U32>, l: PS.Land, +c: PS.Ctx) -> PS.Land:
  match nodes:
    case Nil{}:
      l
    case Con{+node, rest}:
      populate_loop(rest, populate_node(c, node, l), c)

def noted_land(got: PS.Land & R.Rng, +c: PS.Ctx, +before: R.Rng) -> PS.Land:
  (l, +after) = got
  PS.digest(PS.noted(l, PS.ELand{True{}, before, after}), c, 2)

# Graph:PopulateVoronoi on the root: every node of every child graph in traversal order.
def populate(+c: PS.Ctx, l: PS.Land) -> PS.Land:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      noted_land(PS.rng_of(populate_loop(PN.populate_order(PS.story_of(c)), PS.Land{g, rng, ents, events}, c)), c, rng)
