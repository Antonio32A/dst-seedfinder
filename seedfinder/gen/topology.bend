import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f32/ops.bend as F32Ops
import ../storygen/graph.bend as StoryGraph
import ../worldsim/tiles/world.bend as TileWorld
import ../worldsim/tiles/table.bend as TileTable
import ../worldsim/tiles/topology.bend as TileTopology
import ../filters/dump.bend as FilterDump
import ./graph.bend as GenGraph

# The world's topology as the GRPH section holds it (filters/dump.bend Graph): savedata.map.topology's nodes
# (Node:SaveEncode's id, type and position) and the graph edges ForceConnectivity sees (after ApplyPoisonTag).

# A node with its vertex number, before the nodes are put in id order.
type Keyed is Data:
  Keyed{vertex: U32, node: FilterDump.Node}

# floor((p - size / 2) * TILE_SCALE) of a site coordinate, in double like Node:SaveEncode, in hundredths.
def saved_units(+p: F32, +w: U32) -> U32:
  +half = F64Arith.mul(F64Repr.from_u32(w), F64Repr.half())
  (F64Repr.to_i32(F64Repr.floor(F64Arith.mul(F64Arith.sub(F32Ops.to_f64(p), half), F64Repr.from_u32(4)))) * 100 : U32)

def keyed_of(+s: StoryGraph.St, +w: U32, +vertex: U32, +story: U32, site: TileWorld.Site) -> Keyed:
  match site:
    case TileWorld.Site{+node, +x, +y, _, _, _}:
      Keyed{vertex, FilterDump.Node{StoryGraph.node_name(s, story), TileTopology.kind_of(node), saved_units(x, w), saved_units(y, w)}}

def keyed_loop(stories: List<&2, U32>, sites: List<&2, TileWorld.Site>, +s: StoryGraph.St, +w: U32, +vertex: U32) -> List<&2, Keyed>:
  match stories sites:
    case Con{+story, more} Con{site, rest}:
      keyed_of(s, w, vertex, story, site) <> keyed_loop(more, rest, s, w, (vertex + 1 : U32))
    case _ _:
      Nil{}

def id_le(a: Keyed, b: Keyed) -> Bool:
  match a b:
    case Keyed{_, FilterDump.Node{x, _, _, _}} Keyed{_, FilterDump.Node{y, _, _, _}}:
      String.is_le(x, y)

# A vertex and its node's position in id order.
type Rank is Data:
  Rank{vertex: U32, rank: U32}

def vertex_le(a: Rank, b: Rank) -> Bool:
  match a b:
    case Rank{+x, _} Rank{+y, _}:
      (x <= y : U32)

def ranked(sorted: List<&2, Keyed>, +rank: U32) -> List<&2, Rank>:
  match sorted:
    case Nil{}:
      Nil{}
    case Con{Keyed{+vertex, _}, rest}:
      Rank{vertex, rank} <> ranked(rest, (rank + 1 : U32))

def ranks(pairs: List<&2, Rank>) -> List<&2, U32>:
  match pairs:
    case Nil{}:
      Nil{}
    case Con{Rank{_, +rank}, rest}:
      rank <> ranks(rest)

def nodes_of(sorted: List<&2, Keyed>) -> List<&2, FilterDump.Node>:
  match sorted:
    case Nil{}:
      Nil{}
    case Con{Keyed{_, +node}, rest}:
      node <> nodes_of(rest)

def edge_le(a: FilterDump.Edge, b: FilterDump.Edge) -> Bool:
  match a b:
    case FilterDump.Edge{+a1, +a2} FilterDump.Edge{+b1, +b2}:
      (a1 < b1 : U32) || (U32.is_eq(a1, b1) && (a2 <= b2 : U32))

def renumbered(edges: List<&2, TileWorld.Edge>, +rank: TileTable.Tree<U32>) -> List<&2, FilterDump.Edge>:
  match edges:
    case Nil{}:
      Nil{}
    case Con{TileWorld.Edge{+a, +b}, rest}:
      FilterDump.Edge{TileTable.at(~U32, rank, a), TileTable.at(~U32, rank, b)} <> renumbered(rest, rank)

def graph_of(+sorted: List<&2, Keyed>, edges: List<&2, TileWorld.Edge>) -> FilterDump.Graph:
  +rank = TileTable.from_list(~U32, ranks(List.sort(~Rank, ~vertex_le, ranked(sorted, 0))), 0)
  FilterDump.Graph{nodes_of(sorted), List.sort(~FilterDump.Edge, ~edge_le, renumbered(edges, rank))}

# The topology of story s laid out as the tile world (sites in vertex order, the edges left after ApplyPoisonTag).
def graph(+s: StoryGraph.St, +k: GenGraph.Klei, world: TileWorld.World) -> FilterDump.Graph:
  match world:
    case TileWorld.World{+w, _, _, +sites, _, _, +edges, _, _}:
      graph_of(List.sort(~Keyed, ~id_le, keyed_loop(GenGraph.vertices_of(k), sites, s, w, 0)), edges)
