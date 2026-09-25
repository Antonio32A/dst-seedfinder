import Base
import ./walk.bend as WL
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ./world.bend as WD
import ./anchor.bend as AN
import ./dijkstra.bend as DJ
import ./metric.bend as MT

# The walk metric of .scratch/search/metric.py (WalkMetric): shortest paths over land tiles between anchors, exact
# lengths, and (with wormholes) the jumps of every link whose ends both have anchors.

# The world, its cell-array depth, the jumps and, per jump, its wormhole ends.
type Walker is Data:
  Walker{world: WD.World, depth: Nat, jumps: List<&2, DJ.Jump>, hops: List<&2, MT.Hop>}

# A walk source: an anchored instance and the length already paid.
type WSeed is Data:
  WSeed{point: AN.Point, cost: WL.Length}

type Links is Data:
  Links{jumps: List<&2, DJ.Jump>, hops: List<&2, MT.Hop>}

def jump_of(a: Maybe<&2, AN.Anchor>, b: Maybe<&2, AN.Anchor>) -> Maybe<&2, DJ.Jump>:
  match a b:
    case Some{AN.Anchor{+from, _, +la}} Some{AN.Anchor{+to, _, +lb}}:
      Some{DJ.Jump{from, to, WL.plus(la, lb)}}
    case _ _:
      None{}

def with_jump(found: Maybe<&2, DJ.Jump>, +entry: WD.Inst, +exit: WD.Inst, links: Links) -> Links:
  match found links:
    case Some{jump} Links{jumps, hops}:
      Links{List.append(&2, DJ.Jump, jumps, [jump]), List.append(&2, MT.Hop, hops, [MT.Hop{entry, exit}])}
    case None{} other:
      other

def links_of(points: List<&2, AN.Point>, links: Links) -> Links:
  match points:
    case Con{AN.Point{+entry, a}, Con{AN.Point{+exit, b}, rest}}:
      links_of(rest, with_jump(jump_of(a, b), entry, exit, links))
    case _:
      links

def link_insts(links: List<&2, WD.Link>) -> List<&2, WD.Inst>:
  match links:
    case Nil{}:
      Nil{}
    case Con{WD.Link{+entry, +exit}, rest}:
      entry <> exit <> link_insts(rest)

def world_size(+world: WD.World) -> U32:
  match world:
    case WD.World{_, +w, +h, _, _, _, _}:
      (w * h : U32)

def world_links(+world: WD.World) -> List<&2, WD.Link>:
  match world:
    case WD.World{_, _, _, _, _, +links, _}:
      links

def points_only(got: Array<U32> & List<&2, AN.Point>) -> List<&2, AN.Point>:
  (land, points) = got
  points

# The instances with their anchors in the world.
def anchored(+world: WD.World, insts: List<&2, WD.Inst>) -> List<&2, AN.Point>:
  match world:
    case WD.World{_, +w, +h, _, _, _, _}:
      points_only(AN.points(insts, AN.land_array(world, AN.depth_of((w * h : U32))), w, h))

def walker_of(+world: WD.World, +depth: Nat, links: Links) -> Walker:
  match links:
    case Links{jumps, hops}:
      Walker{world, depth, jumps, hops}

# The walk metric of a world, with or without its wormhole links.
def walker(+world: WD.World, +wormholes: Bool) -> Walker:
  +links = Bool.pick(List<&2, WD.Link>, wormholes, world_links(world), Nil{})
  walker_of(world, AN.depth_of(world_size(world)), links_of(anchored(world, link_insts(links)), Links{Nil{}, Nil{}}))

def starts(seeds: List<&2, WSeed>, +i: U32) -> List<&2, DJ.Start>:
  match seeds:
    case Nil{}:
      Nil{}
    case Con{WSeed{AN.Point{_, Some{AN.Anchor{+tile, _, +offset}}}, +cost}, rest}:
      DJ.Start{tile, WL.plus(cost, offset), i} <> starts(rest, (i + 1 : U32))
    case Con{_, rest}:
      starts(rest, (i + 1 : U32))

def target_tiles(targets: List<&2, AN.Point>) -> List<&2, U32>:
  match targets:
    case Nil{}:
      Nil{}
    case Con{AN.Point{_, Some{AN.Anchor{+tile, _, _}}}, rest}:
      tile <> target_tiles(rest)
    case Con{_, rest}:
      target_tiles(rest)

def own_from(seeds: List<&2, WSeed>, +target: WD.Inst, +i: U32) -> U32:
  match seeds:
    case Nil{}:
      DJ.none()
    case Con{WSeed{AN.Point{+inst, _}, _}, rest}:
      Bool.pick(U32, MT.same_inst(inst, target), i, own_from(rest, target, (i + 1 : U32)))

def owns(+exclude_self: Bool, +seeds: List<&2, WSeed>, targets: List<&2, AN.Point>) -> List<&2, U32>:
  match targets:
    case Nil{}:
      Nil{}
    case Con{AN.Point{+inst, _}, rest}:
      Bool.pick(U32, exclude_self, own_from(seeds, inst, 0), DJ.none()) <> owns(exclude_self, seeds, rest)

def any_own(owners: List<&2, U32>) -> Bool:
  match owners:
    case Nil{}:
      False{}
    case Con{+o, rest}:
      Bool.not(U32.is_eq(o, DJ.none())) || any_own(rest)

def first_other(labels: List<&2, DJ.Cand>, +own: U32, +offset: WL.Length) -> MT.Relaxed:
  match labels:
    case Nil{}:
      MT.unreached()
    case Con{DJ.Cand{+length, _, +seed}, rest}:
      Bool.pick(MT.Relaxed, U32.is_eq(seed, own), first_other(rest, own, offset), MT.Relaxed{MT.Walk{WL.plus(length, offset)}, seed})

def picked(got: Array<U32> & List<&2, DJ.Cand>, +own: U32, +offset: WL.Length) -> Array<U32> & MT.Relaxed:
  (cells, labels) = got
  (cells, first_other(labels, own, offset))

def pick_target(cells: Array<U32>, +target: AN.Point, +own: U32) -> Array<U32> & MT.Relaxed:
  match target:
    case AN.Point{_, Some{AN.Anchor{+tile, _, +offset}}}:
      picked(DJ.labels(cells, tile), own, offset)
    case AN.Point{_, None{}}:
      (cells, MT.unreached())

def collected(got: Array<U32> & MT.Relaxed, acc: List<&2, MT.Relaxed>) -> Array<U32> & List<&2, MT.Relaxed>:
  (cells, r) = got
  (cells, r <> acc)

def pick_all(targets: List<&2, AN.Point>, owners: List<&2, U32>, got: Array<U32> & List<&2, MT.Relaxed>) -> List<&2, MT.Relaxed>:
  match targets owners:
    case Con{+target, ts} Con{+own, os}:
      (cells, acc) = got
      pick_all(ts, os, collected(pick_target(cells, target, own), acc))
    case _ _:
      (cells, acc) = got
      List.reverse(&2, MT.Relaxed, acc)

# For every target, the least seed cost plus walk (metric.py WalkMetric.relax, one multi-source search).
def relax(+w: Walker, +seeds: List<&2, WSeed>, +targets: List<&2, AN.Point>, +exclude_self: Bool) -> List<&2, MT.Relaxed>:
  match w:
    case Walker{+world, +depth, +jumps, _}:
      +owners = owns(exclude_self, seeds, targets)
      +needed = Bool.pick(U32, any_own(owners), 2, 1)
      pick_all(targets, owners, (DJ.run(world, depth, jumps, starts(seeds, 0), target_tiles(targets), needed), Nil{}))

def hop_list(indices: List<&2, U32>, +hops: List<&2, MT.Hop>) -> List<&2, MT.Hop>:
  match indices:
    case Nil{}:
      Nil{}
    case Con{+i, rest}:
      +none = {MT.Hop{WD.Inst{0, 0, FR.zero(), FR.zero(), 0, 0, 0}, WD.Inst{0, 0, FR.zero(), FR.zero(), 0, 0, 0}} : MT.Hop}
      Maybe.default(&2, MT.Hop, List.get(&2, MT.Hop, hops, U32.to_nat(i)), none) <> hop_list(rest, hops)

def leg_hops(got: Array<U32> & List<&2, U32>, +length: WL.Length, +hops: List<&2, MT.Hop>) -> MT.Leg:
  (cells, indices) = got
  MT.Leg{MT.Walk{length}, hop_list(indices, hops)}

def leg_labels(got: Array<U32> & List<&2, DJ.Cand>, +goal: U32, +start: U32, +offset: WL.Length, +hops: List<&2, MT.Hop>) -> MT.Leg:
  (cells, labels) = got
  match labels:
    case Con{DJ.Cand{+length, _, _}, _}:
      leg_hops(DJ.hops(cells, goal, start), WL.plus(length, offset), hops)
    case Nil{}:
      MT.Leg{MT.Unreached{}, Nil{}}

# d(a, b) and the jumps of one shortest path (metric.py WalkMetric.leg).
def leg(+w: Walker, +a: AN.Point, +b: AN.Point) -> MT.Leg:
  match w a b:
    case Walker{+world, +depth, +jumps, +hops} AN.Point{_, Some{AN.Anchor{+from, _, +la}}} AN.Point{_, Some{AN.Anchor{+to, _, +lb}}}:
      leg_labels(DJ.labels(DJ.run(world, depth, jumps, [DJ.Start{from, la, 0}], [to], 1), to), to, from, lb, hops)
    case _ _ _:
      MT.Leg{MT.Unreached{}, Nil{}}
