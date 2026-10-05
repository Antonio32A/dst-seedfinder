import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../worldsim/tiles/table.bend as TileTable
import ./dump.bend as FilterDump
import ./world.bend as FilterWorld
import ./metric.bend as Metric
import ./rules.bend as Rules
import ./checks.bend as Checks
import ./witness.bend as Witness

# The bridges rules (docs/config.md section 4 F). A bridge is a topology edge ForceConnectivity draws a site line along
# (its first node neither Blank nor SeparatedRoom, its second not Blank); its length is the distance between the
# nodes' savedata positions, and L is the longest one.

def blank() -> U32:
  1

def separated_room() -> U32:
  7

def far() -> U32:
  4294967295

def kind_of(+n: FilterDump.Node) -> U32:
  match n:
    case FilterDump.Node{_, +kind, _, _}:
      kind

def draws_line(+a: FilterDump.Node, +b: FilterDump.Node) -> Bool:
  Bool.not(U32.is_eq(kind_of(a), blank()) || U32.is_eq(kind_of(a), separated_room()) || U32.is_eq(kind_of(b), blank()))

def units_apart(+ak: U32, +bk: U32) -> U32:
  +d = (ak - bk : U32)
  (Bool.pick(U32, (d >= 2147483648 : U32), (0 - d : U32), d) / 100 : U32)

# The squared distance between two nodes, in world units.
def squared(+a: FilterDump.Node, +b: FilterDump.Node) -> U32:
  match a b:
    case FilterDump.Node{_, _, +ax, +az} FilterDump.Node{_, _, +bx, +bz}:
      +dx = units_apart(ax, bx)
      +dz = units_apart(az, bz)
      (dx * dx + dz * dz : U32)

type Longest is Data:
  Longest{squared: U32, n1: U32, n2: U32}

def beats(+d: U32, best: Maybe<&2, Longest>) -> Bool:
  match best:
    case None{}:
      True{}
    case Some{Longest{+top, _, _}}:
      (d > top : U32)

def node_at(+nodes: TileTable.Tree<FilterDump.Node>, +i: U32) -> FilterDump.Node:
  TileTable.at(~FilterDump.Node, nodes, i)

# The longest bridge, the first in edge order on a tie.
def longest(edges: List<&2, FilterDump.Edge>, +nodes: TileTable.Tree<FilterDump.Node>, +best: Maybe<&2, Longest>) -> Maybe<&2, Longest>:
  match edges:
    case Nil{}:
      best
    case Con{FilterDump.Edge{+n1, +n2}, rest}:
      +a = node_at(nodes, n1)
      +b = node_at(nodes, n2)
      +d = squared(a, b)
      longest(rest, nodes, Bool.pick(Maybe<&2, Longest>, draws_line(a, b) && beats(d, best), Some{Longest{d, n1, n2}}, best))

def neighbour_of(+n1: U32, +n2: U32, +x: U32) -> U32:
  Bool.pick(U32, U32.is_eq(n1, x), n2, Bool.pick(U32, U32.is_eq(n2, x), n1, far()))

# The squared distance from node x to its nearest graph neighbour that is neither Blank nor y (far() without one).
def nearest(edges: List<&2, FilterDump.Edge>, +nodes: TileTable.Tree<FilterDump.Node>, +x: U32, +y: U32, +best: U32) -> U32:
  match edges:
    case Nil{}:
      best
    case Con{FilterDump.Edge{+n1, +n2}, rest}:
      +c = neighbour_of(n1, n2, x)
      +counts = U32.is_ne(c, far()) && U32.is_ne(c, x) && U32.is_ne(c, y) && U32.is_ne(kind_of(node_at(nodes, c)), blank())
      nearest(rest, nodes, x, y, Bool.pick(U32, counts, U32.min(best, squared(node_at(nodes, x), node_at(nodes, c))), best))

def table_of(+nodes: List<&2, FilterDump.Node>) -> TileTable.Tree<FilterDump.Node>:
  TileTable.from_list(~FilterDump.Node, nodes, FilterDump.Node{"", 0, 0, 0})

def graph_of(+world: FilterWorld.World) -> FilterDump.Graph:
  match world:
    case FilterWorld.World{_, _, _, _, _, _, _, +graph}:
      Maybe.default(&2, FilterDump.Graph, graph, FilterDump.Graph{Nil{}, Nil{}})

def length_of(+d: U32) -> F64Repr.F64:
  F64Arith.sqrt(F64Repr.from_u32(d))

def within(longest: Maybe<&2, Longest>, +min: Maybe<&2, F64Repr.F64>, +max: Maybe<&2, F64Repr.F64>) -> Bool:
  match longest:
    case None{}:
      Maybe.is_none(&2, F64Repr.F64, min)
    case Some{Longest{+d, _, _}}:
      Metric.within(Metric.Straight{length_of(d)}, min, max)

def longest_in(+graph: FilterDump.Graph) -> Maybe<&2, Longest>:
  match graph:
    case FilterDump.Graph{+nodes, +edges}:
      longest(edges, table_of(nodes), None{})

def end_json(+n: FilterDump.Node) -> String:
  match n:
    case FilterDump.Node{+id, +kind, +xk, +zk}:
      "{\"node\":\"" ++ id ++ "\",\"type\":" ++ U32.show(kind) ++ ",\"x\":" ++ Witness.coordinate(xk, U32.is_eq(FilterWorld.whole_flag(xk), 1))
        ++ ",\"z\":" ++ Witness.coordinate(zk, U32.is_eq(FilterWorld.whole_flag(zk), 1)) ++ "}"

# The end of the bridge that lies farther from its nearest other neighbour (the node left behind); "from" on a tie.
def stray_of(+edges: List<&2, FilterDump.Edge>, +nodes: TileTable.Tree<FilterDump.Node>, +n1: U32, +n2: U32) -> String:
  Bool.pick(String, (nearest(edges, nodes, n2, n1, far()) > nearest(edges, nodes, n1, n2, far()) : U32), "to", "from")

def bridge_fields(longest: Maybe<&2, Longest>, +graph: FilterDump.Graph) -> String:
  match longest graph:
    case None{} _:
      ",\"length\":null"
    case Some{Longest{+d, +n1, +n2}} FilterDump.Graph{+nodes, +edges}:
      +table = table_of(nodes)
      ",\"length\":" ++ Witness.double_text(length_of(d)) ++ ",\"from\":" ++ end_json(node_at(table, n1)) ++ ",\"to\":" ++ end_json(node_at(table, n2))
        ++ ",\"stray\":\"" ++ stray_of(edges, table, n1, n2) ++ "\""

# Whether the rule holds and its witness fields: the longest bridge's length, its ends and the end left behind.
def check(+world: FilterWorld.World, rule: Rules.Bridge) -> Checks.Check:
  match rule:
    case Rules.Bridge{+min, +max}:
      +graph = graph_of(world)
      +found = longest_in(graph)
      Checks.Check{within(found, min, max), bridge_fields(found, graph)}

# Whether the rule holds, without its witness.
def holds(+world: FilterWorld.World, rule: Rules.Bridge) -> Bool:
  match rule:
    case Rules.Bridge{+min, +max}:
      within(longest_in(graph_of(world)), min, max)
