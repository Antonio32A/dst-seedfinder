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

def walk_tiles() -> List<&2, U32>:
  [393222, 393222, 393222, 65542, 65537, 393217, 393222, 65542, 393222, 65537, 393222, 65542]

def world() -> FilterWorld.World:
  +a = FilterWorld.inst_of(2, 0, 4294966096, 0)
  +b = FilterWorld.inst_of(2, 1, 800, 4294966496)
  FilterWorld.World{1, 6, 4, Nil{}, [[FilterWorld.inst_of(0, 0, 4294966096, 4294966496), FilterWorld.inst_of(0, 1, 4294966896, 4294966896)],
    [FilterWorld.inst_of(1, 0, 800, 0), FilterWorld.inst_of(1, 1, 4294966946, 420)], [a, b]], [FilterWorld.Link{a, b}, FilterWorld.Link{b, a}],
    walk_tiles(), None{}, None{}, FilterWorld.land_bits(walk_tiles(), 0n, 0)}

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
  FilterWorld.World{1, 2, 2, Nil{}, [[FilterWorld.inst_of(0, 0, 4294966896, 4294966896)], [FilterWorld.inst_of(1, 0, 0, 0)]], Nil{}, [65542, 393217], None{}, None{}, FilterWorld.land_bits([65542, 393217], 0n, 0)}

law walk_diagonal_between_water:
  {relaxed(corner_world(), False{}, None{}) == [walked(0, 1)] : List<&2, Metric.Relaxed>}

def walk_diagonal_between_water():
  {==}

# Land bits, 32 tiles to a word with tile 32j + b on bit b of word j: the tile ids 1 2 127 128 255 256 10497 10498 65535
# 0 (land is 2 to 127 and 256 to 10497), twenty land tiles, then 1 6 (tile 31, the top bit of word 0) 6 127.
def edge_tiles() -> List<&2, U32>:
  [131073, 8388735, 16777471, 688007425, 65535, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393217, 8323078]

law land_bits_edges_and_word_boundary:
  {FilterWorld.land_bits(edge_tiles(), 0n, 0) == [3221224550, 3] : List<&2, U32>}

def land_bits_edges_and_word_boundary():
  {==}

law land_bits_full_word_then_empty:
  {FilterWorld.land_bits([393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222, 393222], 0n, 0)
    == [4294967295, 0] : List<&2, U32>}

def land_bits_full_word_then_empty():
  {==}

def listed(xs: List<&1, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      x <> listed(rest)

# The cell array filled from the bits is 1 on the land tiles and 0 on the other tiles and past the last tile.
law land_array_matches_tiles:
  {listed(Array.to_list(~U32, Anchor.land_array(FilterWorld.World{1, 34, 1, Nil{}, Nil{}, Nil{}, edge_tiles(), None{}, None{}, FilterWorld.land_bits(edge_tiles(), 0n, 0)}, 6n)))
    == List.concat(&2, U32, [[0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1], List.replicate(U32, 30n, 0)]) : List<&2, U32>}

def land_array_matches_tiles():
  {==}
