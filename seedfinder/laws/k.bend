import Base
import ../filters/world.bend as FilterWorld
import ../filters/walk.bend as Walk
import ../filters/metric.bend as Metric
import ../filters/walking.bend as Walking
import ../filters/anchor.bend as Anchor

# Bounded walk relaxations (Walking.relax) on a 6 x 4 world, land (6) but for the water (1):
#   y0  L L L L L L
#   y1  L W W W W L
#   y2  L L L W L L
#   y3  W W L L L W
# Prefab 0 on (0, 0) and in the water of (2, 1); prefab 1 on (5, 2) and (2, 3); prefab 2 a link pair on (0, 2) and
# (5, 0). Prefab 1 is 4 + 12 + 4*sqrt(2) and 4 + 2 * 4*sqrt(2) away (diagonals cut corners), and (5, 2) 16 with the
# links.

def world() -> FilterWorld.World:
  +a = FilterWorld.inst_of(2, 0, 4294966096, 0)
  +b = FilterWorld.inst_of(2, 1, 800, 4294966496)
  FilterWorld.World{1, 6, 4, Nil{}, [[FilterWorld.inst_of(0, 0, 4294966096, 4294966496), FilterWorld.inst_of(0, 1, 4294966896, 4294966896)],
    [FilterWorld.inst_of(1, 0, 800, 0), FilterWorld.inst_of(1, 1, 4294966946, 420)], [a, b]], [FilterWorld.Link{a, b}, FilterWorld.Link{b, a}],
    [393222, 393222, 393222, 65542, 65537, 393217, 393222, 65542, 393222, 65537, 393222, 65542], None{}}

def seeds(points: List<&2, Anchor.Point>) -> List<&2, Walking.WSeed>:
  match points:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      Walking.WSeed{p, Walk.zero()} <> seeds(rest)

def relaxed(+w: FilterWorld.World, +links: Bool, +bound: Maybe<&2, Walk.Length>) -> List<&2, Metric.Relaxed>:
  Walking.relax(Walking.walker(w, links), seeds(Walking.anchored(w, FilterWorld.instances(w, [0]))), Walking.anchored(w, FilterWorld.instances(w, [1])), True{}, bound)

def walked(+units: U32, +diagonals: U32) -> Metric.Relaxed:
  Metric.Relaxed{Metric.Walk{Walk.Length{units, 0, 0, diagonals}}, 0}

law bounded_relax_keeps_reached:
  {(relaxed(world(), True{}, None{}), relaxed(world(), True{}, Some{Walk.Length{4, 0, 0, 2}})) == ([walked(16, 0), walked(4, 2)], [Metric.unreached(), walked(4, 2)]) : List<&2, Metric.Relaxed> & List<&2, Metric.Relaxed>}

def bounded_relax_keeps_reached():
  {==}

law bounded_relax_skips_far_pairs:
  {relaxed(world(), False{}, Some{Walk.Length{5, 0, 0, 0}}) == [Metric.unreached(), Metric.unreached()] : List<&2, Metric.Relaxed>}

def bounded_relax_skips_far_pairs():
  {==}

# A diagonal step past two water tiles: on a 2 x 2 world with land only on (0, 0) and (1, 1), prefab 0 on (0, 0) is one
# diagonal from prefab 1 on (1, 1).
def corner_world() -> FilterWorld.World:
  FilterWorld.World{1, 2, 2, Nil{}, [[FilterWorld.inst_of(0, 0, 4294966896, 4294966896)], [FilterWorld.inst_of(1, 0, 0, 0)]], Nil{}, [65542, 393217], None{}}

law walk_diagonal_between_water:
  {relaxed(corner_world(), False{}, None{}) == [walked(0, 1)] : List<&2, Metric.Relaxed>}

def walk_diagonal_between_water():
  {==}
