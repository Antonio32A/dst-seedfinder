import Base
import ../f64/repr.bend as F64Repr
import ../filters/dump.bend as FilterDump
import ../filters/world.bend as FilterWorld
import ../filters/rules.bend as Rules
import ../filters/checks.bend as Checks
import ../filters/bridges.bend as Bridges
import ../filters/config.bend as Config
import ../filters/cave_config.bend as CaveConfig

# Turf bridges laws: the GRPH section and the bridges rules. Golden bytes: Python struct.pack.

def two_nodes() -> FilterDump.Graph:
  FilterDump.Graph{[FilterDump.Node{"ab", 5, 100, 4294967096}, FilterDump.Node{"c", 1, 0, 300}], [FilterDump.Edge{1, 0}]}

law dump_writes_graph:
  {FilterDump.graph_section(two_nodes()) == [71, 82, 80, 72, 56, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 97, 98, 0, 0, 5, 0, 0, 0, 100, 0, 0, 0, 56, 255, 255, 255, 1, 0, 0, 0, 99, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 44, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0] : List<&2, U32>}

def dump_writes_graph():
  {==}

def caves_dump(+graph: Maybe<&2, FilterDump.Graph>) -> FilterDump.Dump:
  FilterDump.Generated{7, 1, 1, 756039, 3, 1, [FilterDump.TileName{6, "GRASS"}], [393222], [], [], [], None{}, Some{[]}, graph}

# A dump with a GRPH section reads back with its topology, and one without it has none.
law dump_round_trip_graph:
  {(FilterDump.of_bytes(FilterDump.bytes(caves_dump(Some{two_nodes()}))), FilterDump.of_bytes(FilterDump.bytes(caves_dump(None{}))))
    == (Done{caves_dump(Some{two_nodes()})}, Done{caves_dump(None{})}) : Result<&1, &1, U32 & String, FilterDump.Dump> & Result<&1, &1, U32 & String, FilterDump.Dump>}

def dump_round_trip_graph():
  {==}

def loaded_has_graph(loaded: Result<&1, &1, U32 & String, FilterWorld.Loaded>) -> Bool:
  match loaded:
    case Done{FilterWorld.Generated{+world, _}}:
      FilterWorld.has_graph(world)
    case _:
      False{}

law world_has_graph_of_its_dump:
  {(loaded_has_graph(FilterWorld.of_bytes_in(FilterDump.bytes(caves_dump(Some{two_nodes()})), True{})), loaded_has_graph(FilterWorld.of_bytes_in(FilterDump.bytes(caves_dump(None{})), True{})))
    == (True{}, False{}) : Bool & Bool}

def world_has_graph_of_its_dump():
  {==}

# Room A at (0, 0); Blank B 1000 east of it; SeparatedRoom C 800 south; Background D at (300, 400). A->B has a Blank end
# and C->A a SeparatedRoom first node, so neither is a bridge; D->A and D->C are both 500 long, and the first wins. D's
# nearest other neighbour (C) is 500 away and A's (C) 800, so A is the stray end.
def toy(+edges: List<&2, FilterDump.Edge>) -> FilterWorld.World:
  +nodes = {[FilterDump.Node{"A", 5, 0, 0}, FilterDump.Node{"B", 1, 100000, 0}, FilterDump.Node{"C", 7, 0, 80000}, FilterDump.Node{"D", 2, 30000, 40000}] : List<&2, FilterDump.Node>}
  FilterWorld.World{1, 2, 2, Nil{}, Nil{}, Nil{}, Nil{}, Some{FilterDump.Graph{nodes, edges}}}

def toy_edges() -> List<&2, FilterDump.Edge>:
  [FilterDump.Edge{0, 1}, FilterDump.Edge{2, 0}, FilterDump.Edge{3, 0}, FilterDump.Edge{3, 2}]

law longest_bridge_skips_blank_and_separated_ends:
  {Bridges.check(toy(toy_edges()), Rules.Bridge{Some{F64Repr.from_u32(500)}, Some{F64Repr.from_u32(500)}})
    == Checks.Check{True{}, ",\"length\":500.0,\"from\":{\"node\":\"D\",\"type\":2,\"x\":300,\"z\":400},\"to\":{\"node\":\"A\",\"type\":5,\"x\":0,\"z\":0},\"stray\":\"to\""} : Checks.Check}

def longest_bridge_skips_blank_and_separated_ends():
  {==}

law bridge_bounds_are_inclusive:
  {(Bridges.holds(toy(toy_edges()), Rules.Bridge{Some{F64Repr.from_u32(501)}, None{}}), Bridges.holds(toy(toy_edges()), Rules.Bridge{None{}, Some{F64Repr.from_u32(499)}}))
    == (False{}, False{}) : Bool & Bool}

def bridge_bounds_are_inclusive():
  {==}

# Without a bridge L is null: a min fails, a max holds.
law no_bridge_is_null:
  {(Bridges.check(toy([FilterDump.Edge{0, 1}, FilterDump.Edge{2, 0}]), Rules.Bridge{Some{F64Repr.from_u32(1)}, None{}}), Bridges.holds(toy(Nil{}), Rules.Bridge{None{}, Some{F64Repr.from_u32(0)}}))
    == (Checks.Check{False{}, ",\"length\":null"}, True{}) : Checks.Check & Bool}

def no_bridge_is_null():
  {==}

def later_of(compiled: Result<&1, &1, U32 & String, CaveConfig.Config>) -> Result<&1, &1, U32 & String, List<&2, Rules.Later>>:
  match compiled:
    case Done{CaveConfig.Config{_, _, +later, _}}:
      Done{later}
    case Fail{failure}:
      Fail{failure}

law cave_config_reads_bridges:
  {later_of(CaveConfig.config_of("{\"shard\": \"caves\", \"criteria\": [{\"bridges\": [{\"min\": 1000}, {\"max\": 200.5}]}]}"))
    == Done{[Rules.Later{[], [], [], [Rules.Bridge{Some{F64Repr.from_u32(1000)}, None{}}, Rules.Bridge{None{}, Some{F64Repr.F64{1080627200, 0}}}], []}]} : Result<&1, &1, U32 & String, List<&2, Rules.Later>>}

def cave_config_reads_bridges():
  {==}

def error_of(compiled: Result<&1, &1, U32 & String, Config.Config>) -> String:
  match compiled:
    case Fail{(_, message)}:
      message
    case Done{_}:
      ""

law bridges_config_errors:
  {(error_of(Config.config_of("{\"criteria\": [{\"bridges\": [{\"min\": -1}]}]}")), error_of(Config.config_of("{\"criteria\": [{\"bridges\": [{\"length\": 3}]}]}")),
    error_of(Config.config_of("{\"criteria\": [{\"bridges\": {\"min\": 3}}]}")))
    == ("config: criteria[0].bridges[0].min must be a number in 0..1000000", "config: unknown key \"length\" in criteria[0].bridges[0]",
      "config: criteria[0].bridges must be a list") : String & String & String}

def bridges_config_errors():
  {==}
