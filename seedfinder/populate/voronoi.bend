import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../f64/repr.bend as F64Repr
import ../data/blob.bend as Blob
import ../data/distribute.bend as Distribute
import ../data/rooms.bend as Rooms
import ../data/story.bend as StoryData
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/groups.bend as TileGroups
import ../storygen/graph.bend as StoryGraph
import ./entities.bend as Entities
import ./counts.bend as PopulateCounts
import ./nodes.bend as PopulateNodes
import ./state.bend as PopulateState

# Node:PopulateVoronoi (graphnode.lua) and Graph:PopulateVoronoi's traversal: GetPointsForSite, the countprefabs,
# the map tag items, then the distributed prefabs, each through Node:AddEntity (dropped off land, else ReserveTile
# and a position with the random offset).

def closure_of(+kind: U32, +value: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, 1), value, 0)

def found_data(xs: List<&2, PopulateNodes.Count>, found: Bool, +prefab: U32, +closure: U32) -> U32:
  match xs:
    case Nil{}:
      Bool.pick(U32, found, closure, 0)
    case Con{PopulateNodes.Count{+k, +kind, +v}, rest}:
      match found:
        case True{}:
          closure
        case False{}:
          found_data(rest, U32.is_eq(k, prefab), prefab, closure_of(kind, v))

# The prefabdata closure (data/closures.bend id) for a prefab, 0 when it has none.
def data_closure(+xs: List<&2, PopulateNodes.Count>, +prefab: U32) -> U32:
  found_data(xs, False{}, prefab, 0)

def placed(got: Grid.Grid & Bool, +c: PopulateState.Ctx, +prefab: U32, +p: Points.Pt, +closure: U32, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>) -> PopulateState.Land:
  (g, _) = got
  match p:
    case Points.Pt{+x, +y, _}:
      +e = Entities.tile_entity(prefab, x, y, PopulateState.width_of(c), PopulateState.height_of(c), True{}, rng)
      PopulateState.added_in(c, PopulateState.Land{g, rng, ents, events}, Entities.with_rng(e, PopulateCounts.prefab_data_call(closure, Entities.rng_of(e))))

def add_on(land: Bool, g: Grid.Grid, +c: PopulateState.Ctx, +prefab: U32, +p: Points.Pt, +closure: U32, rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>) -> PopulateState.Land:
  match land:
    case False{}:
      PopulateState.Land{g, rng, ents, events}
    case True{}:
      match p:
        case Points.Pt{+x, +y, +t}:
          placed(Points.reserve_tile(g, x, y), c, prefab, Points.Pt{x, y, t}, closure, rng, ents, events)

def add_tile(got: Grid.Grid & U32, +c: PopulateState.Ctx, +prefab: U32, +p: Points.Pt, +closure: U32, rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>) -> PopulateState.Land:
  (g, +tile) = got
  add_on(TileGroups.is_land(tile), g, c, prefab, p, closure, rng, ents, events)

# Node:AddEntity with rand_offset: GetTile, then PopulateWorld_AddEntity on land (a prefabdata `closure` is called after the
# offsets).
def add_entity(+c: PopulateState.Ctx, +prefab: U32, +p: Points.Pt, +closure: U32, l: PopulateState.Land) -> PopulateState.Land:
  match p:
    case Points.Pt{+x, +y, +t}:
      match l:
        case PopulateState.Land{g, +rng, +ents, +events}:
          add_tile(Points.get_tile(g, x, y), c, prefab, Points.Pt{x, y, t}, closure, rng, ents, events)

def point_tile(+p: Points.Pt) -> U32:
  match p:
    case Points.Pt{_, _, +t}:
      t

# A node's population in progress: the unused points, and false once PopulateVoronoi returned early.
type Walk is Type:
  Walk{land: PopulateState.Land, pts: List<&2, Points.Pt>, alive: Bool}

def place_count(n: Nat, w: Walk, +c: PopulateState.Ctx, +prefab: U32, +closure: U32) -> Walk:
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
              place_count(p, Walk{add_entity(c, prefab, pt, closure, l), rest, alive}, c, prefab, closure)

def still(w: Walk) -> Walk:
  match w:
    case Walk{l, +pts, +alive}:
      Walk{l, pts, alive && Bool.not(List.is_empty(&2, Points.Pt, pts))}

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

def place_counts(keys: List<&2, U32>, w: Walk, +counts: List<&2, Counted>, +data: List<&2, PopulateNodes.Count>, +c: PopulateState.Ctx) -> Walk:
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
              +closure = data_closure(data, key)
              +n = found_count(counts, False{}, key, 0)
              place_counts(rest, still(place_count(U32.to_nat(n), Walk{l, pts, True{}}, c, key, closure)), counts, data, c)

type Evaluated is Data:
  Evaluated{counts: List<&2, Counted>, total: U32, rng: Pcg.Rng}

def keep_counted(pending: Bool, +key: U32, +n: U32, +acc: List<&2, Counted>) -> List<&2, Counted>:
  match pending:
    case True{}:
      Counted{key, n} <> acc
    case False{}:
      acc

# The countprefabs values in pairs() order (closures called with the kept point count), and their sum.
def evaluate(xs: List<&2, PopulateNodes.Count>, got: U32 & Pcg.Rng, +key: U32, +pending: Bool, +area: U32, +width: U32, +acc: List<&2, Counted>, +total: U32) -> Evaluated:
  match xs:
    case Nil{}:
      (+n, rng) = got
      Evaluated{keep_counted(pending, key, n, acc), (total + n : U32), rng}
    case Con{PopulateNodes.Count{+k, +kind, +v}, rest}:
      (+n, rng) = got
      evaluate(rest, PopulateCounts.value_of(kind, v, area, width, rng), k, True{}, area, width, keep_counted(pending, key, n, acc), (total + n : U32))

def counts_if(enough: Bool, l: PopulateState.Land, +pts: List<&2, Points.Pt>, +order: List<&2, U32>, +counts: List<&2, Counted>, +data: List<&2, PopulateNodes.Count>, +c: PopulateState.Ctx) -> Walk:
  match enough:
    case False{}:
      Walk{l, pts, False{}}
    case True{}:
      place_counts(order, Walk{l, pts, True{}}, counts, data, c)

def counted_walk(e: Evaluated, l: PopulateState.Land, +pts: List<&2, Points.Pt>, +order: List<&2, U32>, +data: List<&2, PopulateNodes.Count>, +c: PopulateState.Ctx) -> Walk:
  match e:
    case Evaluated{+counts, +total, +rng}:
      +enough = Bool.not((U32.from_nat(List.length(&2, Points.Pt, pts)) < total : U32))
      counts_if(enough, PopulateState.with_rng(l, rng), pts, order, counts, data, c)

def extra_step(alive: Bool, l: PopulateState.Land, +pt: Points.Pt, +more: List<&2, Points.Pt>, +prefab: U32, +c: PopulateState.Ctx) -> Walk:
  match alive:
    case False{}:
      Walk{l, pt <> more, False{}}
    case True{}:
      Walk{add_entity(c, prefab, pt, 0, l), more, True{}}

def place_extras(xs: List<&2, U32>, w: Walk, +c: PopulateState.Ctx) -> Walk:
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
def resolve(n: Nat, +entries: List<&2, U32>, +index: U32, got: U32 & Pcg.Rng, +count: U32, +pending: Bool) -> U32 & Pcg.Rng:
  match n:
    case 0n:
      (+v, rng) = got
      (fold_choice(pending, index, count, v), rng)
    case 1n+p:
      (+v, rng) = got
      +next = Blob.at(entries, 1)
      resolve(p, Blob.drop(entries, 2), fold_choice(pending, index, count, v), MathRandom.random_upto(rng, next), next, True{})

def distribute_add(skip: Bool, l: PopulateState.Land, +c: PopulateState.Ctx, +prefab: U32, +pt: Points.Pt, +data: List<&2, PopulateNodes.Count>) -> PopulateState.Land:
  match skip:
    case True{}:
      l
    case False{}:
      add_entity(c, prefab, pt, data_closure(data, prefab), l)

def distribute_pick(got: U32 & Pcg.Rng, l: PopulateState.Land, +c: PopulateState.Ctx, +pt: Points.Pt, +data_of: List<&2, PopulateNodes.Count>) -> PopulateState.Land:
  (+prefab, rng) = got
  distribute_add(U32.is_eq(prefab, 4294967295), PopulateState.with_rng(l, rng), c, prefab, pt, data_of)

# pickspawnprefab's prepared items per tile seen so far in the node (the variant is fixed per node).
type Cached is Data:
  Cached{tile: U32, items: PopulateCounts.Prepared}

def cache_hit(xs: List<&2, Cached>, +tile: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{Cached{+t, _}, rest}:
      U32.is_eq(t, tile) || cache_hit(rest, tile)

def cache_get(xs: List<&2, Cached>, +tile: U32) -> PopulateCounts.Prepared:
  match xs:
    case Nil{}:
      PopulateCounts.Prepared{Nil{}, F64Repr.zero()}
    case Con{Cached{+t, +p}, rest}:
      Bool.pick(PopulateCounts.Prepared, U32.is_eq(t, tile), p, cache_get(rest, tile))

def cache_with(hit: Bool, +cache: List<&2, Cached>, +variant: U32, +tile: U32) -> List<&2, Cached>:
  match hit:
    case True{}:
      cache
    case False{}:
      Cached{tile, PopulateCounts.prepare(variant, tile)} <> cache

type Spread is Type:
  Spread{land: PopulateState.Land, cache: List<&2, Cached>}

def distribute_cached(l: PopulateState.Land, +kept: List<&2, Cached>, +c: PopulateState.Ctx, +pt: Points.Pt, +data: List<&2, PopulateNodes.Count>) -> Spread:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      Spread{distribute_pick(PopulateCounts.pick_prepared(cache_get(kept, point_tile(pt)), rng), PopulateState.Land{g, rng, ents, events}, c, pt, data), kept}

def distribute_try(hit: Bool, l: PopulateState.Land, +cache: List<&2, Cached>, +c: PopulateState.Ctx, +variant: U32, +pt: Points.Pt, +data: List<&2, PopulateNodes.Count>) -> Spread:
  match hit:
    case False{}:
      Spread{l, cache}
    case True{}:
      +tile = point_tile(pt)
      distribute_cached(l, cache_with(cache_hit(cache, tile), cache, variant, tile), c, pt, data)

def distribute_drawn(got: U32 & Pcg.Rng, l: PopulateState.Land, +cache: List<&2, Cached>, +c: PopulateState.Ctx, +variant: U32, +threshold: U32, +pt: Points.Pt, +data: List<&2, PopulateNodes.Count>) -> Spread:
  (+x, rng) = got
  distribute_try((x < threshold : U32), PopulateState.with_rng(l, rng), cache, c, variant, pt, data)

def distribute_one(sp: Spread, +c: PopulateState.Ctx, +variant: U32, +threshold: U32, +pt: Points.Pt, +data: List<&2, PopulateNodes.Count>) -> Spread:
  match sp:
    case Spread{l, +cache}:
      match l:
        case PopulateState.Land{g, +rng, +ents, +events}:
          distribute_drawn(Pcg.draw(rng), PopulateState.Land{g, rng, ents, events}, cache, c, variant, threshold, pt, data)

def distribute_loop(pts: List<&2, Points.Pt>, sp: Spread, +c: PopulateState.Ctx, +variant: U32, +threshold: U32, +data: List<&2, PopulateNodes.Count>) -> PopulateState.Land:
  match pts:
    case Nil{}:
      match sp:
        case Spread{l, _}:
          l
    case Con{+pt, rest}:
      distribute_loop(rest, distribute_one(sp, c, variant, threshold, pt, data), c, variant, threshold, data)

def distribute_resolved(got: U32 & Pcg.Rng, l: PopulateState.Land, +c: PopulateState.Ctx, +node: U32, +pts: List<&2, Points.Pt>) -> PopulateState.Land:
  (+index, rng) = got
  +s = PopulateState.story_of(c)
  +room = PopulateNodes.room(s, node)
  +variant = Distribute.variant(room, StoryGraph.nf(s, node, StoryGraph.f_depth()), ((index * 8 : U32) + PopulateState.swaps_of(c) : U32))
  distribute_loop(pts, Spread{PopulateState.with_rng(l, rng), Nil{}}, c, variant, Rooms.distribute_threshold(room), PopulateNodes.prefabdata(s, node))

def distribute_if(go: Bool, l: PopulateState.Land, +pts: List<&2, Points.Pt>, +c: PopulateState.Ctx, +node: U32) -> PopulateState.Land:
  match go:
    case False{}:
      l
    case True{}:
      match l:
        case PopulateState.Land{g, +rng, +ents, +events}:
          +row = Distribute.cases(PopulateNodes.row(PopulateState.story_of(c), node))
          distribute_resolved(resolve(U32.to_nat(Blob.at(row, 0)), Blob.drop(row, 1), 0, (0, rng), 0, False{}), PopulateState.Land{g, rng, ents, events}, c, node, pts)

def distribute(on: Bool, w: Walk, +c: PopulateState.Ctx, +node: U32) -> PopulateState.Land:
  match w:
    case Walk{l, +pts, +alive}:
      distribute_if(on && alive, l, pts, c, node)

def counted_alive(alive: Bool, l: PopulateState.Land, +pts: List<&2, Points.Pt>, +c: PopulateState.Ctx, +node: U32) -> Walk:
  match alive:
    case False{}:
      Walk{l, pts, False{}}
    case True{}:
      match l:
        case PopulateState.Land{g, +rng, +ents, +events}:
          +s = PopulateState.story_of(c)
          +area = U32.from_nat(List.length(&2, Points.Pt, pts))
          counted_walk(evaluate(PopulateNodes.countprefabs(s, node), (0, rng), 0, False{}, area, PopulateState.width_of(c), Nil{}, 0),
            PopulateState.Land{g, rng, ents, events}, pts, PopulateNodes.generate_order(s, node), PopulateNodes.prefabdata(s, node), c)

def counted(on: Bool, w: Walk, +c: PopulateState.Ctx, +node: U32) -> Walk:
  match on:
    case False{}:
      w
    case True{}:
      match w:
        case Walk{l, +pts, +alive}:
          counted_alive(alive, l, pts, c, node)

def points_noted(tracing: Bool, +ev: PopulateState.Ev, +events: List<&2, PopulateState.Ev>) -> List<&2, PopulateState.Ev>:
  match tracing:
    case True{}:
      ev <> events
    case False{}:
      events

def populate_points(p: Points.Picked, +c: PopulateState.Ctx, +node: U32, +before: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>) -> PopulateState.Land:
  match p:
    case Points.Picked{g, +rng, +n, +shuffled, +kept}:
      +s = PopulateState.story_of(c)
      +alive = Bool.not(List.is_empty(&2, Points.Pt, kept))
      +on = PopulateNodes.has_distribute_percent(s, node) && PopulateNodes.has_distribute(s, node)
      +noted = points_noted(PopulateState.tracing_of(c), PopulateState.EPoints{node, n, before, rng, shuffled, kept}, events)
      distribute(on, place_extras(PopulateNodes.extra_prefabs(s, node), counted(PopulateNodes.has_countprefabs(s, node),
        Walk{PopulateState.Land{g, rng, ents, noted}, kept, alive}, c, node), c), c, node)

def populate_body(skip: Bool, l: PopulateState.Land, +c: PopulateState.Ctx, +node: U32) -> PopulateState.Land:
  match skip:
    case True{}:
      l
    case False{}:
      match l:
        case PopulateState.Land{g, +rng, +ents, +events}:
          populate_points(Points.points_for_site(PopulateState.windows_of(c), PopulateState.sites_of(c), PopulateState.site_of(c, node), g, rng), c, node, rng, ents, events)

def contentless(+s: StoryGraph.St, +node: U32) -> Bool:
  +none = Bool.not(PopulateNodes.has_countprefabs(s, node)) && Bool.not(PopulateNodes.has_distribute(s, node))
  StoryData.is_impassable(PopulateNodes.tile(s, node)) || Bool.not(PopulateNodes.has_contents(s, node)) || none

def skipped(+s: StoryGraph.St, +node: U32) -> Bool:
  PopulateNodes.has_custom_tiles(s, node) || contentless(s, node)

def noted_node(got: PopulateState.Land & Pcg.Rng, +node: U32, +before: Pcg.Rng) -> PopulateState.Land:
  (l, +after) = got
  PopulateState.noted(l, PopulateState.EPopulateNode{node, before, after})

# Node:PopulateVoronoi for one story node.
def populate_node(+c: PopulateState.Ctx, +node: U32, l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      noted_node(PopulateState.rng_of(populate_body(skipped(PopulateState.story_of(c), node), PopulateState.Land{g, rng, ents, events}, c, node)), node, rng)

def populate_loop(nodes: List<&2, U32>, l: PopulateState.Land, +c: PopulateState.Ctx) -> PopulateState.Land:
  match nodes:
    case Nil{}:
      l
    case Con{+node, rest}:
      populate_loop(rest, populate_node(c, node, l), c)

def noted_land(got: PopulateState.Land & Pcg.Rng, +c: PopulateState.Ctx, +before: Pcg.Rng) -> PopulateState.Land:
  (l, +after) = got
  PopulateState.digest(PopulateState.noted(l, PopulateState.ELand{True{}, before, after}), c, 2)

# Graph:PopulateVoronoi on the root: every node of every child graph in traversal order.
def populate(+c: PopulateState.Ctx, l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      noted_land(PopulateState.rng_of(populate_loop(PopulateNodes.populate_order(PopulateState.story_of(c)), PopulateState.Land{g, rng, ents, events}, c)), c, rng)
