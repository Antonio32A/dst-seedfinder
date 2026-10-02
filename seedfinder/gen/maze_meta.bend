import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../f32/ops.bend as F32Ops
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../data/enums.bend as Enums
import ../data/blob.bend as Blob
import ../data/cave_story.bend as CaveStory
import ../storygen/graph.bend as StoryGraph
import ../storygen/catalog.bend as StoryCatalog
import ../storygen/order.bend as StoryOrder
import ../populate/entities.bend as Entities
import ../worldsim/grid.bend as Grid
import ../worldsim/cave/maze.bend as WorldCaveMaze
import ../worldsim/tiles/world.bend as TileWorld
import ./maze_env.bend as MazeEnv
import ./maze_lines.bend as MazeLines
import ./maze_order.bend as MazeOrder
import ./maze_place.bend as MazePlace
import ./maze_tags.bend as MazeTags

# The Maze pass of forest_map.Generate: per task with the `Maze` global tag, GetPointsForMetaMaze over the tagged nodes,
# the cells sorted by their distance to the maze entrance, a layout placed on every cell (the archive's ends, key room
# and seal, the atrium's and military's start and finish, or rooms and bosses only), and the bridge lines from the
# entrance nodes.

# One maze: its caves task row, the cells (xs, ys, types), `distances` (the cells' idx nearest first), the site of
# the first MazeEntrance node and the MazeEntrance nodes.
type Maze is Data:
  Maze{task: U32, found: List<&2, WorldCaveMaze.Found>, order: List<&2, U32>, site: TileWorld.Site, entrances: List<&2, U32>}

def task_of(+m: Maze) -> U32:
  match m:
    case Maze{+task, _, _, _, _}:
      task

def found_of(+m: Maze) -> List<&2, WorldCaveMaze.Found>:
  match m:
    case Maze{_, +found, _, _, _}:
      found

def order_of(+m: Maze) -> List<&2, U32>:
  match m:
    case Maze{_, _, +order, _, _}:
      order

def site_of(+m: Maze) -> TileWorld.Site:
  match m:
    case Maze{_, _, _, +site, _}:
      site

def entrances_of(+m: Maze) -> List<&2, U32>:
  match m:
    case Maze{_, _, _, _, +entrances}:
      entrances

def with_found(+m: Maze, +found: List<&2, WorldCaveMaze.Found>) -> Maze:
  Maze{task_of(m), found, order_of(m), site_of(m), entrances_of(m)}

def count_of(+m: Maze) -> U32:
  U32.from_nat(List.length(&2, WorldCaveMaze.Found, found_of(m)))

def restored(l: MazePlace.Laid, +marks: List<&2, Pcg.Rng>) -> MazeEnv.Pass:
  match l:
    case MazePlace.Laid{g, rng, ents}:
      MazeEnv.Pass{g, rng, ents, marks}

# obj_layout.Place({xs[idx], ys[idx]}, MAZE_CELL_EXITS_INV[cell], add_fn, choices)
def place_cell(+e: MazeEnv.Env, +m: Maze, +idx: U32, +cell: U32, +choices: List<&2, U32>, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match p:
    case MazeEnv.Pass{g, rng, +ents, +marks}:
      restored(MazePlace.place(MazePlace.Spot{MazeEnv.swaps_of(e), MazeEnv.width_of(e), MazeOrder.x_of(MazeOrder.cell(found_of(m), idx)), MazeOrder.y_of(MazeOrder.cell(found_of(m), idx))},
        cell, choices, MazePlace.Laid{g, rng, ents}), marks)

# Place(..., MAZE_CELL_EXITS_INV[math.abs(types[idx])], ...)
def place_shape(+e: MazeEnv.Env, +m: Maze, +idx: U32, +choices: List<&2, U32>, p: MazeEnv.Pass) -> MazeEnv.Pass:
  place_cell(e, m, idx, MazeOrder.magnitude(MazeOrder.key_of(MazeOrder.cell(found_of(m), idx))), choices, p)

def room_placed(rooms: Bool, +e: MazeEnv.Env, +m: Maze, +idx: U32, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match rooms:
    case True{}:
      place_shape(e, m, idx, CaveStory.task_maze_rooms(task_of(m)), p)
    case False{}:
      place_shape(e, m, idx, CaveStory.task_maze_bosses(task_of(m)), p)

# A cell with types > 0 gets a `rooms` layout, one with types <= 0 a `bosses` layout.
def room_or_boss(+e: MazeEnv.Env, +m: Maze, +idx: U32, p: MazeEnv.Pass) -> MazeEnv.Pass:
  room_placed(MazeOrder.positive(MazeOrder.key_of(MazeOrder.cell(found_of(m), idx))), e, m, idx, p)

def room_if(on: Bool, +e: MazeEnv.Env, +m: Maze, +idx: U32, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match on:
    case True{}:
      room_or_boss(e, m, idx, p)
    case False{}:
      p

# `for idx = 1, #xs` placing rooms and bosses except at the skipped cells.
def rooms_loop(n: Nat, +e: MazeEnv.Env, +m: Maze, +idx: U32, +skips: List<&2, U32>, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match n:
    case 0n:
      p
    case 1n+q:
      rooms_loop(q, e, m, (idx + 1 : U32), skips, room_if(Bool.not(StoryOrder.contains(skips, idx)), e, m, idx, p))

def fi(+v: U32) -> F64Repr.F64:
  F64Repr.from_i32(v)

def seal_lines(g: Grid.Grid, +x: U32, +y: U32, +sx: F64Repr.F64, +sy: F64Repr.F64) -> Grid.Grid:
  MazeLines.ground_line(MazeLines.ground_line(MazeLines.ground_line(g, fi(x), fi(y), sx, sy, Enums.tile_dirt()), fi((x + 2 : U32)), fi((y + 2 : U32)),
    fi((x - 2 : U32)), fi((y - 2 : U32)), Enums.tile_dirt()), fi((x - 2 : U32)), fi((y + 2 : U32)), fi((x + 2 : U32)), fi((y - 2 : U32)), Enums.tile_dirt())

def raw_entity(+prefab: U32, +x: F64Repr.F64, +z: F64Repr.F64, +rng: Pcg.Rng) -> Entities.Ent:
  Entities.Ent{prefab, F64Repr.zero(), F64Repr.zero(), x, z, F64Repr.to_i32(Entities.floored_hundredths(x)), F64Repr.to_i32(Entities.floored_hundredths(z)), rng}

# newx = (x - width / 2) * 4 + ((sx - x) / 2 * 4) / 2, without the rounding to hundredths.
def seal_coordinate(+t: U32, +s: F64Repr.F64, +width: U32) -> F64Repr.F64:
  F64Arith.add(F64Arith.mul(F64Arith.sub(fi(t), F64Arith.div(F64Repr.from_u32(width), F64Repr.two())), Entities.tile_scale()),
    F64Arith.div(F64Arith.mul(F64Arith.div(F64Arith.sub(s, fi(t)), F64Repr.two()), Entities.tile_scale()), F64Repr.two()))

# The two archive seals: rubble1 and rubble2 half way between the cell and the entrance.
def seals(+e: MazeEnv.Env, +x: U32, +y: U32, +sx: F64Repr.F64, +sy: F64Repr.F64, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>) -> List<&2, Entities.Ent>:
  +px = seal_coordinate(x, sx, MazeEnv.width_of(e))
  +pz = seal_coordinate(y, sy, MazeEnv.width_of(e))
  raw_entity(MazeEnv.prefab("rubble2"), px, pz, rng) <> raw_entity(MazeEnv.prefab("rubble1"), px, pz, rng) <> ents

def site_x(+s: TileWorld.Site) -> F64Repr.F64:
  match s:
    case TileWorld.Site{_, +x, _, _, _, _}:
      F32Ops.to_f64(x)

def site_y(+s: TileWorld.Site) -> F64Repr.F64:
  match s:
    case TileWorld.Site{_, _, +y, _, _, _}:
      F32Ops.to_f64(y)

# The lines and seals from the cell nearest the entrance to the MazeEntrance site.
def sealed_at(p: MazeEnv.Pass, +e: MazeEnv.Env, +m: Maze, +c: WorldCaveMaze.Found) -> MazeEnv.Pass:
  match p:
    case MazeEnv.Pass{g, +rng, +ents, +marks}:
      MazeEnv.Pass{seal_lines(g, MazeOrder.x_of(c), MazeOrder.y_of(c), site_x(site_of(m)), site_y(site_of(m))), rng,
        seals(e, MazeOrder.x_of(c), MazeOrder.y_of(c), site_x(site_of(m)), site_y(site_of(m)), rng, ents), marks}

def sealed(p: MazeEnv.Pass, +e: MazeEnv.Env, +m: Maze) -> MazeEnv.Pass:
  sealed_at(p, e, m, MazeOrder.cell(found_of(m), StoryOrder.nth_or_last(order_of(m), 0, 0)))

def keyroom_placed(none: Bool, +e: MazeEnv.Env, +m: Maze, +idx: U32, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match none:
    case True{}:
      p
    case False{}:
      place_cell(e, m, idx, CaveStory.maze_cell_single_north(), CaveStory.task_maze_keyroom(task_of(m)), p)

def redraw(again: Bool, +r: U32, rng: Pcg.Rng, +n: U32) -> U32 & Pcg.Rng:
  match again:
    case True{}:
      MathRandom.random_range(rng, 1, n)
    case False{}:
      (r, rng)

# `while reservedindex == endidx or reservedindex == startidx do reservedindex = math.random(1, #xs) end`
def reserved_pick(fuel: Nat, got: U32 & Pcg.Rng, +endidx: U32, +startidx: U32, +n: U32) -> U32 & Pcg.Rng:
  match fuel:
    case 0n:
      got
    case 1n+f:
      (+r, rng) = got
      reserved_pick(f, redraw(U32.is_eq(r, endidx) || U32.is_eq(r, startidx), r, rng, n), endidx, startidx, n)

def reserved_done(got: U32 & Pcg.Rng, +e: MazeEnv.Env, +m: Maze, +endidx: U32, +startidx: U32, g: Grid.Grid, +ents: List<&2, Entities.Ent>, +marks: List<&2, Pcg.Rng>) -> MazeEnv.Pass:
  (+r, rng) = got
  sealed(keyroom_placed(List.is_empty(&2, U32, CaveStory.task_maze_keyroom(task_of(m))), e, m, r,
    rooms_loop(U32.to_nat(count_of(m)), e, m, 1, [r, endidx, startidx], MazeEnv.Pass{g, rng, ents, marks})), e, m)

def reserved_space(p: MazeEnv.Pass, +e: MazeEnv.Env, +m: Maze, +endidx: U32, +startidx: U32) -> MazeEnv.Pass:
  match p:
    case MazeEnv.Pass{g, rng, +ents, +marks}:
      reserved_done(reserved_pick(1024n, MathRandom.random_range(rng, 1, count_of(m)), endidx, startidx, count_of(m)), e, m, endidx, startidx, g, ents, marks)

def archive_rest(more: Bool, p: MazeEnv.Pass, +e: MazeEnv.Env, +m: Maze, +endidx: U32, +startidx: U32) -> MazeEnv.Pass:
  match more:
    case True{}:
      reserved_space(p, e, m, endidx, startidx)
    case False{}:
      p

def archive_started(got: U32 & Pcg.Rng, +e: MazeEnv.Env, +m: Maze, +ends: List<&2, U32>, +endidx: U32, g: Grid.Grid, +ents: List<&2, Entities.Ent>, +marks: List<&2, Pcg.Rng>) -> MazeEnv.Pass:
  (+i, rng) = got
  +startidx = StoryOrder.nth_or_last(ends, (i - 1 : U32), 0)
  archive_rest((2 < count_of(m) : U32), place_shape(e, m, startidx, CaveStory.task_maze_start(task_of(m)), MazeEnv.Pass{g, rng, ents, marks}), e, m, endidx, startidx)

def archive_start(p: MazeEnv.Pass, +e: MazeEnv.Env, +m: Maze, +ends: List<&2, U32>, +endidx: U32) -> MazeEnv.Pass:
  match p:
    case MazeEnv.Pass{g, rng, +ents, +marks}:
      archive_started(MathRandom.random_range(rng, 1, U32.from_nat(List.length(&2, U32, ends))), e, m, ends, endidx, g, ents, marks)

def archive_finished(got: U32 & Pcg.Rng, +e: MazeEnv.Env, +m: Maze, +ends: List<&2, U32>, g: Grid.Grid, +ents: List<&2, Entities.Ent>, +marks: List<&2, Pcg.Rng>) -> MazeEnv.Pass:
  (+i, rng) = got
  +endidx = StoryOrder.nth_or_last(ends, (i - 1 : U32), 0)
  archive_start(place_shape(e, m, endidx, CaveStory.task_maze_finish(task_of(m)), MazeEnv.Pass{g, rng, ents, marks}), e, m, MazeOrder.without_nth(ends, (i - 1 : U32)), endidx)

def archive_ends(p: MazeEnv.Pass, +e: MazeEnv.Env, +m: Maze, +ends: List<&2, U32>) -> MazeEnv.Pass:
  match p:
    case MazeEnv.Pass{g, rng, +ents, +marks}:
      archive_finished(MathRandom.random_range(rng, 1, U32.from_nat(List.length(&2, U32, ends))), e, m, ends, g, ents, marks)

# The archive: finish and start on two of the dead ends, the key room, rooms and bosses elsewhere, the seal.
def archive(+e: MazeEnv.Env, +m: Maze, p: MazeEnv.Pass) -> MazeEnv.Pass:
  archive_ends(p, e, m, MazeOrder.ends(order_of(m), found_of(m)))

def special_ends(p: MazeEnv.Pass, +e: MazeEnv.Env, +m: Maze, +first: U32, +last: U32) -> MazeEnv.Pass:
  place_shape(e, m, last, CaveStory.task_maze_finish(task_of(m)), place_shape(e, m, first, CaveStory.task_maze_start(task_of(m)), p))

def special_with(+e: MazeEnv.Env, +m: Maze, +ends: List<&2, U32>, p: MazeEnv.Pass) -> MazeEnv.Pass:
  special_ends(rooms_loop(U32.to_nat(count_of(m)), e, m, 1, [StoryOrder.nth_or_last(ends, 0, 0), MazeOrder.last_of(ends)], p), e, m, StoryOrder.nth_or_last(ends, 0, 0), MazeOrder.last_of(ends))

# The special mazes: start on the dead end nearest the entrance, finish on the farthest.
def special(+e: MazeEnv.Env, +m: Maze, p: MazeEnv.Pass) -> MazeEnv.Pass:
  special_with(e, m, MazeOrder.ends(order_of(m), found_of(m)), p)

def plain_with(+e: MazeEnv.Env, +m: Maze, p: MazeEnv.Pass) -> MazeEnv.Pass:
  rooms_loop(U32.to_nat(count_of(m)), e, m, 1, Nil{}, p)

# The plain mazes: the cell nearest the entrance becomes a FOUR_WAY.
def plain(+e: MazeEnv.Env, +m: Maze, p: MazeEnv.Pass) -> MazeEnv.Pass:
  plain_with(e, with_found(m, MazeOrder.keyed(found_of(m), StoryOrder.nth_or_last(order_of(m), 0, 0), CaveStory.maze_cell_four_way())), p)

def by_special(special_maze: Bool, +e: MazeEnv.Env, +m: Maze, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match special_maze:
    case True{}:
      special(e, m, p)
    case False{}:
      plain(e, m, p)

def by_kind(archive_maze: Bool, +e: MazeEnv.Env, +m: Maze, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match archive_maze:
    case True{}:
      archive(e, m, p)
    case False{}:
      by_special(U32.is_eq(CaveStory.task_maze_kind(task_of(m)), CaveStory.maze_kind_special()), e, m, p)

def bridge_tile(+task: U32) -> U32:
  Bool.pick(U32, Blob.is_none(CaveStory.task_maze_bridge_ground(task)), Enums.tile_brick(), CaveStory.task_maze_bridge_ground(task))

def bridged(p: MazeEnv.Pass, +e: MazeEnv.Env, +m: Maze) -> MazeEnv.Pass:
  match p:
    case MazeEnv.Pass{g, rng, ents, marks}:
      MazeEnv.Pass{MazeLines.bridge(entrances_of(m), g, e, bridge_tile(task_of(m))), rng, ents, marks}

def centred(+e: MazeEnv.Env, +task: U32, +found: List<&2, WorldCaveMaze.Found>, +entrances: List<&2, U32>, +site: TileWorld.Site, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match site:
    case TileWorld.Site{_, _, _, +cx, +cy, _}:
      +m = {Maze{task, found, MazeOrder.sorted(found, F32Ops.to_f64(cx), F32Ops.to_f64(cy)), site, entrances} : Maze}
      bridged(by_kind(U32.is_eq(CaveStory.task_maze_kind(task), CaveStory.maze_kind_archive()), e, m, p), e, m)

def measured(+e: MazeEnv.Env, +g: U32, +found: List<&2, WorldCaveMaze.Found>, p: MazeEnv.Pass) -> MazeEnv.Pass:
  +entrances = MazeTags.nodes(MazeEnv.story_of(e), "MazeEntrance", g)
  centred(e, StoryCatalog.cave_task(StoryGraph.gf(MazeEnv.story_of(e), g, StoryGraph.g_part())), found, entrances,
    MazeEnv.site_of(e, StoryOrder.nth_or_last(entrances, 0, StoryGraph.none())), p)

def found_pass(more: Bool, +e: MazeEnv.Env, +g: U32, +found: List<&2, WorldCaveMaze.Found>, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match more:
    case True{}:
      measured(e, g, found, p)
    case False{}:
      p

def mapped(m: WorldCaveMaze.Mapped, +e: MazeEnv.Env, +g: U32, grid: Grid.Grid, +before: Pcg.Rng, +ents: List<&2, Entities.Ent>, +marks: List<&2, Pcg.Rng>) -> MazeEnv.Pass:
  match m:
    case WorldCaveMaze.Mapped{+found, +rng}:
      found_pass(Bool.not(List.is_empty(&2, WorldCaveMaze.Found, found)), e, g, found, MazeEnv.Pass{grid, rng, ents, rng <> before <> marks})

def task_pass(+e: MazeEnv.Env, +g: U32, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match p:
    case MazeEnv.Pass{grid, +rng, +ents, +marks}:
      mapped(WorldCaveMaze.meta_maze(MazeEnv.windows_of(e), CaveStory.task_maze_size(StoryCatalog.cave_task(StoryGraph.gf(MazeEnv.story_of(e), g, StoryGraph.g_part()))),
        MazeEnv.node_sites(MazeTags.nodes(MazeEnv.story_of(e), "Maze", g), e), rng), e, g, grid, rng, ents, marks)

def tasks_loop(tasks: List<&2, U32>, +e: MazeEnv.Env, p: MazeEnv.Pass) -> MazeEnv.Pass:
  match tasks:
    case Nil{}:
      p
    case Con{+g, rest}:
      tasks_loop(rest, e, task_pass(e, g, p))

# `for task, nodes in pairs(GlobalTags["Maze"])`.
def run(+e: MazeEnv.Env, p: MazeEnv.Pass) -> MazeEnv.Pass:
  tasks_loop(MazeTags.tasks(MazeEnv.story_of(e), "Maze"), e, p)
