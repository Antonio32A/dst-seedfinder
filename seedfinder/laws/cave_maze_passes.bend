import Base
import ../gen/maze_labyrinth.bend as MazeLabyrinth
import ../gen/maze_meta.bend as MazeMeta
import ../gen/maze_order.bend as MazeOrder
import ../f64/random.bend as F64Random
import ../f64/repr.bend as F64Repr
import ../worldsim/cave/maze.bend as WorldCaveMaze

# The maze passes against the real game: the Lua 5.1 table.sort of forest_map.Generate over the meta maze cells and the
# doubles of the pass.

# table.sort(distances, ...) over the meta maze cells of a real world (seed 1, the AtriumMaze) by the squared distance to the entrance centroid.
law maze_atrium_cells_sort_like_table_sort:
  {MazeOrder.sorted([WorldCaveMaze.Found{4294967294, 158, 353}, WorldCaveMaze.Found{4294967295, 150, 369}, WorldCaveMaze.Found{1, 142, 337}, WorldCaveMaze.Found{3, 150, 337}, WorldCaveMaze.Found{3, 166, 337}, WorldCaveMaze.Found{3, 134, 353}, WorldCaveMaze.Found{3, 142, 361}, WorldCaveMaze.Found{3, 166, 361}, WorldCaveMaze.Found{4, 174, 345}, WorldCaveMaze.Found{4, 166, 393}, WorldCaveMaze.Found{5, 142, 345}, WorldCaveMaze.Found{5, 150, 345}, WorldCaveMaze.Found{5, 134, 361}, WorldCaveMaze.Found{6, 158, 345}, WorldCaveMaze.Found{6, 134, 369}, WorldCaveMaze.Found{6, 158, 369}, WorldCaveMaze.Found{6, 150, 377}, WorldCaveMaze.Found{7, 166, 385}, WorldCaveMaze.Found{8, 174, 385}, WorldCaveMaze.Found{9, 158, 337}, WorldCaveMaze.Found{9, 174, 337}, WorldCaveMaze.Found{9, 174, 353}, WorldCaveMaze.Found{9, 158, 361}, WorldCaveMaze.Found{10, 166, 353}, WorldCaveMaze.Found{10, 150, 361}, WorldCaveMaze.Found{10, 158, 377}, WorldCaveMaze.Found{12, 166, 345}, WorldCaveMaze.Found{12, 150, 353}, WorldCaveMaze.Found{12, 174, 361}, WorldCaveMaze.Found{12, 142, 369}, WorldCaveMaze.Found{13, 166, 369}, WorldCaveMaze.Found{13, 166, 377}, WorldCaveMaze.Found{14, 142, 353}], F64Repr.F64{1080456569, 3221225472}, F64Repr.F64{1081355657, 2147483648}) == [21, 5, 9, 20, 27, 22, 14, 4, 24, 12, 1, 29, 3, 8, 28, 11, 23, 31, 33, 25, 16, 7, 6, 2, 32, 26, 13, 30, 17, 19, 18, 15, 10] : List<&2, U32>}

def maze_atrium_cells_sort_like_table_sort():
  {==}

# table.sort(distances, ...) over the meta maze cells of a real world (seed 1, the ArchiveMaze) by the squared distance to the entrance centroid.
law maze_archive_cells_sort_like_table_sort:
  {MazeOrder.sorted([WorldCaveMaze.Found{4294967294, 312, 81}, WorldCaveMaze.Found{2, 296, 65}, WorldCaveMaze.Found{4, 328, 97}, WorldCaveMaze.Found{4, 320, 105}, WorldCaveMaze.Found{5, 304, 81}, WorldCaveMaze.Found{5, 320, 97}, WorldCaveMaze.Found{6, 304, 89}, WorldCaveMaze.Found{7, 304, 73}, WorldCaveMaze.Found{9, 304, 65}, WorldCaveMaze.Found{9, 320, 73}, WorldCaveMaze.Found{9, 328, 89}, WorldCaveMaze.Found{10, 312, 73}, WorldCaveMaze.Found{10, 312, 89}, WorldCaveMaze.Found{11, 320, 89}, WorldCaveMaze.Found{12, 320, 81}], F64Repr.F64{1081236049, 1073741824}, F64Repr.F64{1079628126, 1073741824}) == [7, 13, 5, 4, 6, 1, 14, 8, 15, 3, 12, 11, 2, 9, 10] : List<&2, U32>}

def maze_archive_cells_sort_like_table_sort():
  {==}

# table.sort(distances, ...) over the meta maze cells of a real world (seed 9, the Military) by the squared distance to the entrance centroid.
law maze_military_cells_sort_like_table_sort:
  {MazeOrder.sorted([WorldCaveMaze.Found{1, 140, 268}, WorldCaveMaze.Found{1, 148, 268}, WorldCaveMaze.Found{4, 140, 284}, WorldCaveMaze.Found{7, 140, 276}, WorldCaveMaze.Found{12, 148, 276}], F64Repr.F64{1080466199, 0}, F64Repr.F64{1081208370, 0}) == [5, 2, 3, 4, 1] : List<&2, U32>}

def maze_military_cells_sort_like_table_sort():
  {==}

# val = math.floor(math.random() * 10.0 - 2.5) for the PCG32 outputs [0, 1, 429496729, 429496730, 858993459, 1073741823, 2147483647, 2147483648, 3000000000, 3865470565, 4294967294, 4294967295].
law labyrinth_val_from_the_draw:
  {[MazeLabyrinth.val_of(F64Random.from_output(0)), MazeLabyrinth.val_of(F64Random.from_output(1)), MazeLabyrinth.val_of(F64Random.from_output(429496729)), MazeLabyrinth.val_of(F64Random.from_output(429496730)), MazeLabyrinth.val_of(F64Random.from_output(858993459)), MazeLabyrinth.val_of(F64Random.from_output(1073741823)), MazeLabyrinth.val_of(F64Random.from_output(2147483647)), MazeLabyrinth.val_of(F64Random.from_output(2147483648)), MazeLabyrinth.val_of(F64Random.from_output(3000000000)), MazeLabyrinth.val_of(F64Random.from_output(3865470565)), MazeLabyrinth.val_of(F64Random.from_output(4294967294)), MazeLabyrinth.val_of(F64Random.from_output(4294967295))] == [4294967293, 4294967293, 4294967294, 4294967294, 4294967295, 4294967295, 2, 2, 4, 6, 7, 7] : List<&2, U32>}

def labyrinth_val_from_the_draw():
  {==}

# The archive seal: (x - width / 2) * 4 + ((site.x - x) / 2 * 4) / 2 for (x, site.x, width) = [(373, 360.607666015625, 425), (100, 110.25, 425), (250, 12.5, 430), (81, 406.75, 425)].
law archive_seal_coordinate:
  {[MazeMeta.seal_coordinate(373, F64Repr.F64{1081510329, 0}, 425), MazeMeta.seal_coordinate(100, F64Repr.F64{1079742464, 0}, 425), MazeMeta.seal_coordinate(250, F64Repr.F64{1076428800, 0}, 430), MazeMeta.seal_coordinate(81, F64Repr.F64{1081699328, 0}, 425)] == [F64Repr.F64{1082371292, 2147483648}, F64Repr.F64{3229318144, 0}, F64Repr.F64{3227017216, 0}, F64Repr.F64{3228108800, 0}] : List<&2, F64Repr.F64>}

def archive_seal_coordinate():
  {==}
