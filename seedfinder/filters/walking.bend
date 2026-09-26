import Base
import ./walk.bend as Walk
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ./world.bend as FilterWorld
import ./anchor.bend as Anchor
import ./dijkstra.bend as Dijkstra
import ./metric.bend as Metric

# The walk metric of .scratch/search/metric.py (WalkMetric): shortest paths over land tiles between anchors, exact
# lengths, and (with wormholes) the jumps of every link whose ends both have anchors.

# The world, its cell-array depth, the jumps and, per jump, its wormhole ends.
type Walker is Data:
  Walker{world: FilterWorld.World, depth: Nat, jumps: List<&2, Dijkstra.Jump>, hops: List<&2, Metric.Hop>}

# A walk source: an anchored instance and the length already paid.
type WSeed is Data:
  WSeed{point: Anchor.Point, cost: Walk.Length}

type Links is Data:
  Links{jumps: List<&2, Dijkstra.Jump>, hops: List<&2, Metric.Hop>}

def jump_of(a: Maybe<&2, Anchor.Anchor>, b: Maybe<&2, Anchor.Anchor>) -> Maybe<&2, Dijkstra.Jump>:
  match a b:
    case Some{Anchor.Anchor{+from, _, +la}} Some{Anchor.Anchor{+to, _, +lb}}:
      Some{Dijkstra.Jump{from, to, Walk.plus(la, lb)}}
    case _ _:
      None{}

def with_jump(found: Maybe<&2, Dijkstra.Jump>, +entry: FilterWorld.Inst, +exit: FilterWorld.Inst, links: Links) -> Links:
  match found links:
    case Some{jump} Links{jumps, hops}:
      Links{List.append(&2, Dijkstra.Jump, jumps, [jump]), List.append(&2, Metric.Hop, hops, [Metric.Hop{entry, exit}])}
    case None{} other:
      other

def links_of(points: List<&2, Anchor.Point>, links: Links) -> Links:
  match points:
    case Con{Anchor.Point{+entry, a}, Con{Anchor.Point{+exit, b}, rest}}:
      links_of(rest, with_jump(jump_of(a, b), entry, exit, links))
    case _:
      links

def link_insts(links: List<&2, FilterWorld.Link>) -> List<&2, FilterWorld.Inst>:
  match links:
    case Nil{}:
      Nil{}
    case Con{FilterWorld.Link{+entry, +exit}, rest}:
      entry <> exit <> link_insts(rest)

def world_size(+world: FilterWorld.World) -> U32:
  match world:
    case FilterWorld.World{_, +w, +h, _, _, _, _}:
      (w * h : U32)

def world_links(+world: FilterWorld.World) -> List<&2, FilterWorld.Link>:
  match world:
    case FilterWorld.World{_, _, _, _, _, +links, _}:
      links

def points_only(got: Array<U32> & List<&2, Anchor.Point>) -> List<&2, Anchor.Point>:
  (land, points) = got
  points

# The instances with their anchors in the world.
def anchored(+world: FilterWorld.World, insts: List<&2, FilterWorld.Inst>) -> List<&2, Anchor.Point>:
  match world:
    case FilterWorld.World{_, +w, +h, _, _, _, _}:
      points_only(Anchor.points(insts, Anchor.land_array(world, Anchor.depth_of((w * h : U32))), w, h))

def walker_of(+world: FilterWorld.World, +depth: Nat, links: Links) -> Walker:
  match links:
    case Links{jumps, hops}:
      Walker{world, depth, jumps, hops}

# The walk metric of a world, with or without its wormhole links.
def walker(+world: FilterWorld.World, +wormholes: Bool) -> Walker:
  +links = Bool.pick(List<&2, FilterWorld.Link>, wormholes, world_links(world), Nil{})
  walker_of(world, Anchor.depth_of(world_size(world)), links_of(anchored(world, link_insts(links)), Links{Nil{}, Nil{}}))

def starts(seeds: List<&2, WSeed>, +i: U32) -> List<&2, Dijkstra.Start>:
  match seeds:
    case Nil{}:
      Nil{}
    case Con{WSeed{Anchor.Point{_, Some{Anchor.Anchor{+tile, _, +offset}}}, +cost}, rest}:
      Dijkstra.Start{tile, Walk.plus(cost, offset), i} <> starts(rest, (i + 1 : U32))
    case Con{_, rest}:
      starts(rest, (i + 1 : U32))

def target_tiles(targets: List<&2, Anchor.Point>) -> List<&2, U32>:
  match targets:
    case Nil{}:
      Nil{}
    case Con{Anchor.Point{_, Some{Anchor.Anchor{+tile, _, _}}}, rest}:
      tile <> target_tiles(rest)
    case Con{_, rest}:
      target_tiles(rest)

def own_from(seeds: List<&2, WSeed>, +target: FilterWorld.Inst, +i: U32) -> U32:
  match seeds:
    case Nil{}:
      Dijkstra.none()
    case Con{WSeed{Anchor.Point{+inst, _}, _}, rest}:
      Bool.pick(U32, Metric.same_inst(inst, target), i, own_from(rest, target, (i + 1 : U32)))

def owns(+exclude_self: Bool, +seeds: List<&2, WSeed>, targets: List<&2, Anchor.Point>) -> List<&2, U32>:
  match targets:
    case Nil{}:
      Nil{}
    case Con{Anchor.Point{+inst, _}, rest}:
      Bool.pick(U32, exclude_self, own_from(seeds, inst, 0), Dijkstra.none()) <> owns(exclude_self, seeds, rest)

def any_own(owners: List<&2, U32>) -> Bool:
  match owners:
    case Nil{}:
      False{}
    case Con{+o, rest}:
      Bool.not(U32.is_eq(o, Dijkstra.none())) || any_own(rest)

def first_other(labels: List<&2, Dijkstra.Cand>, +own: U32, +offset: Walk.Length) -> Metric.Relaxed:
  match labels:
    case Nil{}:
      Metric.unreached()
    case Con{Dijkstra.Cand{+length, _, +seed}, rest}:
      Bool.pick(Metric.Relaxed, U32.is_eq(seed, own), first_other(rest, own, offset), Metric.Relaxed{Metric.Walk{Walk.plus(length, offset)}, seed})

def picked(got: Array<U32> & List<&2, Dijkstra.Cand>, +own: U32, +offset: Walk.Length) -> Array<U32> & Metric.Relaxed:
  (cells, labels) = got
  (cells, first_other(labels, own, offset))

def pick_target(cells: Array<U32>, +target: Anchor.Point, +own: U32) -> Array<U32> & Metric.Relaxed:
  match target:
    case Anchor.Point{_, Some{Anchor.Anchor{+tile, _, +offset}}}:
      picked(Dijkstra.labels(cells, tile), own, offset)
    case Anchor.Point{_, None{}}:
      (cells, Metric.unreached())

def collected(got: Array<U32> & Metric.Relaxed, acc: List<&2, Metric.Relaxed>) -> Array<U32> & List<&2, Metric.Relaxed>:
  (cells, r) = got
  (cells, r <> acc)

def pick_all(targets: List<&2, Anchor.Point>, owners: List<&2, U32>, got: Array<U32> & List<&2, Metric.Relaxed>) -> List<&2, Metric.Relaxed>:
  match targets owners:
    case Con{+target, ts} Con{+own, os}:
      (cells, acc) = got
      pick_all(ts, os, collected(pick_target(cells, target, own), acc))
    case _ _:
      (cells, acc) = got
      List.reverse(&2, Metric.Relaxed, acc)

# For every target, the least seed cost plus walk (metric.py WalkMetric.relax, one multi-source search).
def relax(+w: Walker, +seeds: List<&2, WSeed>, +targets: List<&2, Anchor.Point>, +exclude_self: Bool) -> List<&2, Metric.Relaxed>:
  match w:
    case Walker{+world, +depth, +jumps, _}:
      +owners = owns(exclude_self, seeds, targets)
      +needed = Bool.pick(U32, any_own(owners), 2, 1)
      pick_all(targets, owners, (Dijkstra.run(world, depth, jumps, starts(seeds, 0), target_tiles(targets), needed), Nil{}))

def hop_list(indices: List<&2, U32>, +hops: List<&2, Metric.Hop>) -> List<&2, Metric.Hop>:
  match indices:
    case Nil{}:
      Nil{}
    case Con{+i, rest}:
      +none = {Metric.Hop{FilterWorld.Inst{0, 0, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}, FilterWorld.Inst{0, 0, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}} : Metric.Hop}
      Maybe.default(&2, Metric.Hop, List.get(&2, Metric.Hop, hops, U32.to_nat(i)), none) <> hop_list(rest, hops)

def leg_hops(got: Array<U32> & List<&2, U32>, +length: Walk.Length, +hops: List<&2, Metric.Hop>) -> Metric.Leg:
  (cells, indices) = got
  Metric.Leg{Metric.Walk{length}, hop_list(indices, hops)}

def leg_labels(got: Array<U32> & List<&2, Dijkstra.Cand>, +goal: U32, +start: U32, +offset: Walk.Length, +hops: List<&2, Metric.Hop>) -> Metric.Leg:
  (cells, labels) = got
  match labels:
    case Con{Dijkstra.Cand{+length, _, _}, _}:
      leg_hops(Dijkstra.hops(cells, goal, start), Walk.plus(length, offset), hops)
    case Nil{}:
      Metric.Leg{Metric.Unreached{}, Nil{}}

# d(a, b) and the jumps of one shortest path (metric.py WalkMetric.leg).
def leg(+w: Walker, +a: Anchor.Point, +b: Anchor.Point) -> Metric.Leg:
  match w a b:
    case Walker{+world, +depth, +jumps, +hops} Anchor.Point{_, Some{Anchor.Anchor{+from, _, +la}}} Anchor.Point{_, Some{Anchor.Anchor{+to, _, +lb}}}:
      leg_labels(Dijkstra.labels(Dijkstra.run(world, depth, jumps, [Dijkstra.Start{from, la, 0}], [to], 1), to), to, from, lb, hops)
    case _ _ _:
      Metric.Leg{Metric.Unreached{}, Nil{}}
