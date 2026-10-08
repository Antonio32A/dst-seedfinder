import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ./walk.bend as Walk
import ./world.bend as FilterWorld
import ./anchor.bend as Anchor
import ./metric.bend as Metric
import ./straight.bend as Straight
import ./walking.bend as Walking
import ./rules.bend as Rules

# One (metric, wormholes) variant of a world (metric.py Metrics.get): the relaxation primitive and legs of either the
# straight or the walk metric, over instances as points (anchored for walk).

type Space is Data:
  Space{walk: Bool, ends: Straight.Ends, walker: Walking.Walker}

# A relaxation source: a point and the cost already paid.
type Src is Data:
  Src{point: Anchor.Point, cost: Metric.Cost}

def no_ends() -> Straight.Ends:
  Straight.Ends{Nil{}, Nil{}, Nil{}, Nil{}}

def straight_links(+world: FilterWorld.World, +wormholes: Bool) -> List<&2, FilterWorld.Link>:
  match world:
    case FilterWorld.World{_, _, _, _, _, +links, _, _, _, _}:
      Bool.pick(List<&2, FilterWorld.Link>, wormholes, links, Nil{})

def space_of(walk: Bool, +world: FilterWorld.World, +wormholes: Bool) -> Space:
  match walk:
    case True{}:
      Space{True{}, no_ends(), Walking.walker(world, wormholes)}
    case False{}:
      Space{False{}, Straight.ends_of(straight_links(world, wormholes)), Walking.Walker{world, 0n, Nil{}, Nil{}}}

# The metric of a rule in a world.
def space(+world: FilterWorld.World, +metric: Rules.Metric) -> Space:
  match metric:
    case Rules.Metric{+walk, +wormholes, _}:
      space_of(walk, world, wormholes)

def plain_points(insts: List<&2, FilterWorld.Inst>) -> List<&2, Anchor.Point>:
  match insts:
    case Nil{}:
      Nil{}
    case Con{+inst, rest}:
      Anchor.Point{inst, None{}} <> plain_points(rest)

def space_world(+s: Space) -> FilterWorld.World:
  match s:
    case Space{_, _, Walking.Walker{+world, _, _, _}}:
      world

def points_with(walk: Bool, +s: Space, +insts: List<&2, FilterWorld.Inst>) -> List<&2, Anchor.Point>:
  match walk:
    case True{}:
      Walking.anchored(space_world(s), insts)
    case False{}:
      plain_points(insts)

# The instances as points of this metric (with their walk anchors for walk).
def points(+s: Space, +insts: List<&2, FilterWorld.Inst>) -> List<&2, Anchor.Point>:
  match s:
    case Space{+walk, _, _}:
      points_with(walk, s, insts)

# The zero cost of this metric.
def zero(+s: Space) -> Metric.Cost:
  match s:
    case Space{+walk, _, _}:
      Bool.pick(Metric.Cost, walk, Metric.Walk{Walk.zero()}, Metric.Straight{F64Repr.zero()})

def zero_sources(+s: Space, points: List<&2, Anchor.Point>) -> List<&2, Src>:
  match points:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      Src{p, zero(s)} <> zero_sources(s, rest)

def straight_seeds(sources: List<&2, Src>) -> List<&2, Metric.Seed>:
  match sources:
    case Nil{}:
      Nil{}
    case Con{Src{Anchor.Point{+inst, _}, +cost}, rest}:
      Metric.Seed{inst, cost} <> straight_seeds(rest)

def length_of_cost(c: Metric.Cost) -> Walk.Length:
  match c:
    case Metric.Walk{+l}:
      l
    case _:
      Walk.zero()

def walk_seeds(sources: List<&2, Src>) -> List<&2, Walking.WSeed>:
  match sources:
    case Nil{}:
      Nil{}
    case Con{Src{+point, +cost}, rest}:
      Walking.WSeed{point, length_of_cost(cost)} <> walk_seeds(rest)

def insts_of(points: List<&2, Anchor.Point>) -> List<&2, FilterWorld.Inst>:
  match points:
    case Nil{}:
      Nil{}
    case Con{Anchor.Point{+inst, _}, rest}:
      inst <> insts_of(rest)

def relax_with(walk: Bool, +s: Space, +sources: List<&2, Src>, +targets: List<&2, Anchor.Point>, +exclude_self: Bool, +bound: Maybe<&2, Walk.Length>) -> List<&2, Metric.Relaxed>:
  match walk s:
    case True{} Space{_, _, +walker}:
      Walking.relax(walker, walk_seeds(sources), targets, exclude_self, bound)
    case False{} Space{_, +ends, _}:
      Straight.relax(ends, straight_seeds(sources), insts_of(targets), exclude_self)

# metric.py relax(seeds, targets, exclude_self): per target the least seed cost plus distance, and that seed; with a
# bound, walk targets past it may come out unreached.
def relax(+s: Space, +sources: List<&2, Src>, +targets: List<&2, Anchor.Point>, +exclude_self: Bool, +bound: Maybe<&2, Walk.Length>) -> List<&2, Metric.Relaxed>:
  match s:
    case Space{+walk, _, _}:
      relax_with(walk, s, sources, targets, exclude_self, bound)

def leg_with(walk: Bool, +s: Space, +a: Anchor.Point, +b: Anchor.Point) -> Metric.Leg:
  match walk s a b:
    case True{} Space{_, _, +walker} _ _:
      Walking.leg(walker, a, b)
    case False{} Space{_, +ends, _} Anchor.Point{+ia, _} Anchor.Point{+ib, _}:
      Straight.leg(ends, ia, ib)

# metric.py leg(a, b): d(a, b) and the wormhole jumps of one shortest path.
def leg(+s: Space, +a: Anchor.Point, +b: Anchor.Point) -> Metric.Leg:
  match s:
    case Space{+walk, _, _}:
      leg_with(walk, s, a, b)
