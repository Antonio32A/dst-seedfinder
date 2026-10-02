import Base
import ../rng/pcg.bend as Pcg
import ../storygen/graph.bend as StoryGraph
import ../worldsim/grid.bend as Grid
import ../worldsim/tiles/world.bend as TileWorld
import ../populate/entities.bend as Entities
import ../populate/names.bend as PopulateNames
import ./graph.bend as GenGraph

# What the caves' maze passes run on: the attempt's platform and prefab swap state, its story and graph, the map size and
# the tile world, and the state they thread through (the tile map, the PCG32 stream, the entities added to `entities`
# newest first, and the stream just before and just after each maze engine call, newest first).

type Env is Data:
  Env{windows: Bool, swaps: U32, s: StoryGraph.St, k: GenGraph.Klei, w: U32, world: TileWorld.World}

type Pass is Type:
  Pass{grid: Grid.Grid, rng: Pcg.Rng, ents: List<&2, Entities.Ent>, marks: List<&2, Pcg.Rng>}

# A maze or labyrinth a pass built: the string id of its name and the entries it added to the pass's entity list (the
# oldest `from` entries came before it, `to` after it).
type Built is Data:
  Built{name: U32, from: U32, to: U32}

# The pass and how many entities it holds.
def counted(p: Pass) -> Pass & U32:
  match p:
    case Pass{g, rng, +ents, marks}:
      (Pass{g, rng, ents, marks}, U32.from_nat(List.length(&2, Entities.Ent, ents)))

# `built` with what `name` added between the two entity counts, when it added anything.
def built_with(+name: U32, +from: U32, +to: U32, +built: List<&2, Built>) -> List<&2, Built>:
  Bool.pick(List<&2, Built>, (from < to : U32), Built{name, from, to} <> built, built)

# The string id of a prefab name.
def prefab(+name: String) -> U32:
  PopulateNames.string_id(name)

def windows_of(+e: Env) -> Bool:
  match e:
    case Env{+windows, _, _, _, _, _}:
      windows

def swaps_of(+e: Env) -> U32:
  match e:
    case Env{_, +swaps, _, _, _, _}:
      swaps

def story_of(+e: Env) -> StoryGraph.St:
  match e:
    case Env{_, _, +s, _, _, _}:
      s

def klei_of(+e: Env) -> GenGraph.Klei:
  match e:
    case Env{_, _, _, +k, _, _}:
      k

def width_of(+e: Env) -> U32:
  match e:
    case Env{_, _, _, _, +w, _}:
      w

def world_of(+e: Env) -> TileWorld.World:
  match e:
    case Env{_, _, _, _, _, +world}:
      world

def site_cons(none: Bool, +world: TileWorld.World, +v: U32, sites: List<&2, TileWorld.Site>) -> List<&2, TileWorld.Site>:
  match none:
    case True{}:
      sites
    case False{}:
      TileWorld.site(world, v) <> sites

# The sites of the nodes in the given order; a node without a site is left out.
def node_sites(nodes: List<&2, U32>, +e: Env) -> List<&2, TileWorld.Site>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      +v = GenGraph.vertex_of(klei_of(e), n)
      site_cons(TileWorld.is_none(v), world_of(e), v, node_sites(rest, e))

def site_of(+e: Env, +n: U32) -> TileWorld.Site:
  TileWorld.site(world_of(e), GenGraph.vertex_of(klei_of(e), n))
