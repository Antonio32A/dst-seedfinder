import Base
import ../rng/pcg.bend as Pcg
import ../storygen/graph.bend as StoryGraph
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../populate/entities.bend as Entities
import ./generate.bend as Generate
import ./graph.bend as GenGraph
import ./cave_custom.bend as CaveCustom
import ./maze_env.bend as MazeEnv
import ./maze_labyrinth.bend as MazeLabyrinth
import ./maze_meta.bend as MazeMeta

# The caves' maze passes of forest_map.Generate, between the custom tile pass and Graph:GlobalPrePopulate: the Labyrinth
# (RunMaze per `Labyrinth` tag, pandoraschest, DrawCellLine BRICK lines) and the Maze (GetPointsForMetaMaze, the maze
# layouts, DrawGroundLine, DrawCellLine, the rubble spawners).

# The tile map and RNG after both passes and the entities they added to savedata.ents (newest first; not the custom tile
# pass's items).
type Mazed is Type:
  Mazed{grid: Grid.Grid, rng: Pcg.Rng, ents: List<&2, Entities.Ent>}

# The same with the stream just before and just after each maze engine call in call order (before, after, before, after,
# ...; the Lua side's own draws lie between an after and the next before).
type Marked is Type:
  Marked{mazed: Mazed, marks: List<&2, Pcg.Rng>}

def finished(p: MazeEnv.Pass) -> Marked:
  match p:
    case MazeEnv.Pass{g, rng, ents, marks}:
      Marked{Mazed{g, rng, ents}, List.reverse(&2, Pcg.Rng, marks)}

def unmarked(m: Marked) -> Mazed:
  match m:
    case Marked{mazed, _}:
      mazed

def run_marked(+c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, g: Grid.Grid, +rng: Pcg.Rng, +placed: List<&2, CaveCustom.Placed>, +sites: Points.Sites) -> Marked:
  +e = {MazeEnv.Env{Generate.windows_of(c), Generate.swaps_of(c), s, k, w, CaveCustom.world_of(sites)} : MazeEnv.Env}
  finished(MazeMeta.run(e, MazeLabyrinth.run(e, MazeEnv.Pass{g, rng, Nil{}, Nil{}})))

def run(+c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, g: Grid.Grid, +rng: Pcg.Rng, +placed: List<&2, CaveCustom.Placed>, +sites: Points.Sites) -> Mazed:
  unmarked(run_marked(c, s, k, w, g, rng, placed, sites))
