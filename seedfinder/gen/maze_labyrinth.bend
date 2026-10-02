import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/random.bend as F64Random
import ../data/enums.bend as Enums
import ../populate/entities.bend as Entities
import ../rng/pcg.bend as Pcg
import ../worldsim/grid.bend as Grid
import ../worldsim/cave/maze.bend as WorldCaveMaze
import ../worldsim/tiles/lines.bend as TileLines
import ./maze_env.bend as MazeEnv
import ./maze_lines.bend as MazeLines
import ./maze_tags.bend as MazeTags

# The Labyrinth pass of forest_map.Generate: per task with the `Labyrinth` global tag a growing-tree maze over the tagged
# nodes, a pandoraschest on every dead end, and BRICK lines from the entrance nodes and around the maze's nodes.

def half_up() -> F64Repr.F64:
  F64Arith.div(F64Repr.from_u32(3), F64Repr.two())

def chest_add(on: Bool, +chest: U32, +x: U32, +y: U32, +w: U32, rng: Pcg.Rng, +ents: List<&2, Entities.Ent>) -> List<&2, Entities.Ent>:
  match on:
    case True{}:
      Entities.entity(chest, F64Arith.add(F64Repr.from_i32(x), half_up()), F64Arith.add(F64Repr.from_i32(y), half_up()), w, w, False{}, rng) <> ents
    case False{}:
      ents

# A pandoraschest at (xs + 1.5, ys + 1.5) for every point of type 0, in the order RunMaze returned them.
def chests(found: List<&2, WorldCaveMaze.Found>, +chest: U32, +w: U32, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>) -> List<&2, Entities.Ent>:
  match found:
    case Nil{}:
      ents
    case Con{WorldCaveMaze.Found{+key, +x, +y}, rest}:
      chests(rest, chest, w, rng, chest_add(U32.is_zero(key), chest, x, y, w, rng, ents))

def brick() -> TileLines.Pen:
  TileLines.Pen{Enums.tile_brick(), False{}, False{}}

def ran_lines(ran: WorldCaveMaze.Ran, +e: MazeEnv.Env, +members: List<&2, U32>, +entrances: List<&2, U32>, +before: Pcg.Rng, +ents: List<&2, Entities.Ent>, +marks: List<&2, Pcg.Rng>) -> MazeEnv.Pass:
  match ran:
    case WorldCaveMaze.Ran{g, +found, +rng}:
      MazeEnv.Pass{MazeLines.boundary(members, MazeLines.entrance_edges(entrances, g, e, brick()), e, members, brick()), rng,
        chests(found, MazeEnv.prefab("pandoraschest"), MazeEnv.width_of(e), rng, ents), rng <> before <> marks}

# val = math.floor(math.random() * 10.0 - 2.5)
def val_of(+r: F64Repr.F64) -> U32:
  F64Repr.to_i32(F64Repr.floor(F64Arith.sub(F64Arith.mul(r, F64Repr.from_u32(10)), F64Arith.div(F64Repr.from_u32(5), F64Repr.two()))))

def drawn(got: F64Repr.F64 & Pcg.Rng, +e: MazeEnv.Env, +members: List<&2, U32>, +entrances: List<&2, U32>, g: Grid.Grid, +ents: List<&2, Entities.Ent>, +marks: List<&2, Pcg.Rng>) -> MazeEnv.Pass:
  (+r, +rng) = got
  ran_lines(WorldCaveMaze.run_maze(WorldCaveMaze.Params{MazeEnv.windows_of(e), 3, val_of(r), Enums.tile_impassable(), Enums.tile_brick()},
    MazeEnv.node_sites(members, e), g, rng), e, members, entrances, rng, ents, marks)

def task_pass(+e: MazeEnv.Env, +task: U32, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match p:
    case MazeEnv.Pass{g, rng, +ents, +marks}:
      drawn(F64Random.random(rng), e, MazeTags.nodes(MazeEnv.story_of(e), "Labyrinth", task), MazeTags.nodes(MazeEnv.story_of(e), "LabyrinthEntrance", task), g, ents, marks)

def tasks_loop(tasks: List<&2, U32>, +e: MazeEnv.Env, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match tasks:
    case Nil{}:
      p
    case Con{+task, rest}:
      tasks_loop(rest, e, task_pass(e, task, p))

# `for task, labyrinth_nodes in pairs(GlobalTags["Labyrinth"])`.
def run(+e: MazeEnv.Env, p: MazeEnv.Pass) -> MazeEnv.Pass:
  tasks_loop(MazeTags.tasks(MazeEnv.story_of(e), "Labyrinth"), e, p)
