import Base
import ../rng/pcg.bend as Pcg
import ../data/cave_story.bend as CaveStory
import ../data/strings.bend as Strings
import ../gen/maze_place.bend as MazePlace
import ../populate/entities.bend as Entities
import ../storygen/graph.bend as StoryGraph
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../data/builds.bend as Builds

def choice_scan(+build: Builds.Build, n: Nat, +name: String, +i: U32, +found: U32) -> U32:
  match n:
    case 0n:
      found
    case 1n+p:
      choice_scan(build, p, name, (i + 1 : U32), Bool.pick(U32, String.eq(CaveStory.maze_choice_name(build, i), name), i, found))

def choices_named(+build: Builds.Build, names: List<&2, String>) -> List<&2, U32>:
  match names:
    case Nil{}:
      Nil{}
    case Con{+name, rest}:
      choice_scan(build, U32.to_nat(CaveStory.maze_choice_names_count(build)), name, 0, StoryGraph.none()) <> choices_named(build, rest)

def cell_scan(+build: Builds.Build, n: Nat, +name: String, +i: U32, +found: U32) -> U32:
  match n:
    case 0n:
      found
    case 1n+p:
      cell_scan(build, p, name, (i + 1 : U32), Bool.pick(U32, String.eq(CaveStory.maze_cell_name(build, i), name), i, found))

def window_words(n: Nat, got: Grid.Grid & U32, +x: U32, +y: U32, +i: U32, acc: List<&2, U32>) -> Grid.Grid & List<&2, U32>:
  match n:
    case 0n:
      (g, _) = got
      (g, List.reverse(&2, U32, acc))
    case 1n+p:
      (g, +tile) = got
      window_words(p, Points.get_tile(g, (x + ((i + 1 : U32) % 18 : U32) : U32), (y + ((i + 1 : U32) / 18 : U32) : U32)), x, y, (i + 1 : U32), tile <> acc)

def fnv_words(words: List<&2, U32>, +h: U32) -> U32:
  match words:
    case Nil{}:
      h
    case Con{+w, rest}:
      fnv_words(rest, ((h .^. w) * 16777619 : U32))

def entity_text(+build: Builds.Build, +e: Entities.Ent) -> String:
  match e:
    case Entities.Ent{+prefab, _, _, _, _, +xk, +zk, _}:
      Strings.name(build, prefab) ++ ":" ++ U32.show(xk) ++ ":" ++ U32.show(zk)

def entities_text(+build: Builds.Build, ents: List<&2, Entities.Ent>) -> List<&2, String>:
  match ents:
    case Nil{}:
      Nil{}
    case Con{+e, rest}:
      List.append(&2, String, entities_text(build, rest), [entity_text(build, e)])

def laid_text(+build: Builds.Build, got: Grid.Grid & List<&2, U32>, +ents: List<&2, Entities.Ent>, +draws: U32) -> String:
  (_, +words) = got
  U32.show(fnv_words(words, 2166136261)) ++ "|" ++ U32.show(U32.from_nat(List.length(&2, Entities.Ent, ents))) ++ "|" ++ String.join(entities_text(build, ents), ";") ++ "|" ++ U32.show(draws)

def laid_of(+build: Builds.Build, l: MazePlace.Laid, +seed: U32, +x: U32, +y: U32) -> String:
  match l:
    case MazePlace.Laid{g, +rng, +ents}:
      laid_text(build, window_words(324n, Points.get_tile(g, x, y), x, y, 0, Nil{}), ents, Pcg.counter(seed, rng))

# obj_layout.Place({x, y}, shape, add_fn, choices) on an empty 48 x 48 map for a 425 wide world, from the stream after
# `skip` draws of math.randomseed(seed): the tiles set (FNV-1a of the 18 x 18 window from the position), the entities and
# the draw count.
def case_string(+build: Builds.Build, +seed: U32, +skip: U32, +shape: String, choices: List<&2, String>, +x: U32, +y: U32) -> String:
  laid_of(build, MazePlace.place(build, MazePlace.Spot{0, 425, x, y}, cell_scan(build, U32.to_nat(CaveStory.maze_cell_type_count(build)), shape, 0, StoryGraph.none()), choices_named(build, choices),
    MazePlace.Laid{Grid.new(48, 48, 0), Pcg.at_counter(seed, skip), Nil{}}), seed, x, y)
