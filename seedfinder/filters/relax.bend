import Base
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ./walk.bend as WL
import ./world.bend as WD
import ./anchor.bend as AN
import ./metric.bend as MT
import ./straight.bend as ST
import ./walking.bend as WK
import ./rules.bend as RU

# One (metric, wormholes) variant of a world (metric.py Metrics.get): the relaxation primitive and legs of either the
# straight or the walk metric, over instances as points (anchored for walk).

type Space is Data:
  Space{walk: Bool, ends: ST.Ends, walker: WK.Walker}

# A relaxation source: a point and the cost already paid.
type Src is Data:
  Src{point: AN.Point, cost: MT.Cost}

def no_ends() -> ST.Ends:
  ST.Ends{Nil{}, Nil{}, Nil{}, Nil{}}

def straight_links(+world: WD.World, +wormholes: Bool) -> List<&2, WD.Link>:
  match world:
    case WD.World{_, _, _, _, _, +links, _}:
      Bool.pick(List<&2, WD.Link>, wormholes, links, Nil{})

def space_of(walk: Bool, +world: WD.World, +wormholes: Bool) -> Space:
  match walk:
    case True{}:
      Space{True{}, no_ends(), WK.walker(world, wormholes)}
    case False{}:
      Space{False{}, ST.ends_of(straight_links(world, wormholes)), WK.Walker{world, 0n, Nil{}, Nil{}}}

# The metric of a rule in a world.
def space(+world: WD.World, +metric: RU.Metric) -> Space:
  match metric:
    case RU.Metric{+walk, +wormholes}:
      space_of(walk, world, wormholes)

def plain_points(insts: List<&2, WD.Inst>) -> List<&2, AN.Point>:
  match insts:
    case Nil{}:
      Nil{}
    case Con{+inst, rest}:
      AN.Point{inst, None{}} <> plain_points(rest)

def space_world(+s: Space) -> WD.World:
  match s:
    case Space{_, _, WK.Walker{+world, _, _, _}}:
      world

def points_with(walk: Bool, +s: Space, +insts: List<&2, WD.Inst>) -> List<&2, AN.Point>:
  match walk:
    case True{}:
      WK.anchored(space_world(s), insts)
    case False{}:
      plain_points(insts)

# The instances as points of this metric (with their walk anchors for walk).
def points(+s: Space, +insts: List<&2, WD.Inst>) -> List<&2, AN.Point>:
  match s:
    case Space{+walk, _, _}:
      points_with(walk, s, insts)

# The zero cost of this metric.
def zero(+s: Space) -> MT.Cost:
  match s:
    case Space{+walk, _, _}:
      Bool.pick(MT.Cost, walk, MT.Walk{WL.zero()}, MT.Straight{FR.zero()})

def zero_sources(+s: Space, points: List<&2, AN.Point>) -> List<&2, Src>:
  match points:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      Src{p, zero(s)} <> zero_sources(s, rest)

def straight_seeds(sources: List<&2, Src>) -> List<&2, MT.Seed>:
  match sources:
    case Nil{}:
      Nil{}
    case Con{Src{AN.Point{+inst, _}, +cost}, rest}:
      MT.Seed{inst, cost} <> straight_seeds(rest)

def length_of_cost(c: MT.Cost) -> WL.Length:
  match c:
    case MT.Walk{+l}:
      l
    case _:
      WL.zero()

def walk_seeds(sources: List<&2, Src>) -> List<&2, WK.WSeed>:
  match sources:
    case Nil{}:
      Nil{}
    case Con{Src{+point, +cost}, rest}:
      WK.WSeed{point, length_of_cost(cost)} <> walk_seeds(rest)

def insts_of(points: List<&2, AN.Point>) -> List<&2, WD.Inst>:
  match points:
    case Nil{}:
      Nil{}
    case Con{AN.Point{+inst, _}, rest}:
      inst <> insts_of(rest)

def relax_with(walk: Bool, +s: Space, +sources: List<&2, Src>, +targets: List<&2, AN.Point>, +exclude_self: Bool) -> List<&2, MT.Relaxed>:
  match walk s:
    case True{} Space{_, _, +walker}:
      WK.relax(walker, walk_seeds(sources), targets, exclude_self)
    case False{} Space{_, +ends, _}:
      ST.relax(ends, straight_seeds(sources), insts_of(targets), exclude_self)

# metric.py relax(seeds, targets, exclude_self): per target the least seed cost plus distance, and that seed.
def relax(+s: Space, +sources: List<&2, Src>, +targets: List<&2, AN.Point>, +exclude_self: Bool) -> List<&2, MT.Relaxed>:
  match s:
    case Space{+walk, _, _}:
      relax_with(walk, s, sources, targets, exclude_self)

def leg_with(walk: Bool, +s: Space, +a: AN.Point, +b: AN.Point) -> MT.Leg:
  match walk s a b:
    case True{} Space{_, _, +walker} _ _:
      WK.leg(walker, a, b)
    case False{} Space{_, +ends, _} AN.Point{+ia, _} AN.Point{+ib, _}:
      ST.leg(ends, ia, ib)

# metric.py leg(a, b): d(a, b) and the wormhole jumps of one shortest path.
def leg(+s: Space, +a: AN.Point, +b: AN.Point) -> MT.Leg:
  match s:
    case Space{+walk, _, _}:
      leg_with(walk, s, a, b)
