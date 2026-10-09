import Base
import ../rng/pcg.bend as Pcg
import ../worldsim/cave/automaton.bend as CaveAutomaton
import ../worldsim/cave/meta.bend as CaveMeta
import ../worldsim/cave/shuffle.bend as CaveShuffle
import ../worldsim/tiles/world.bend as TileWorld
import ../lawkit/cave_grid.bend as CaveGrid

# Golden values of the cave engines' kernels (RunCA's automaton, the growing tree, the meta-maze walk and the C++ shuffle) on
# explicit grids, from a native reconstruction of WorldSim's RunCA, RunMaze and GetPointsForMetaMaze that reproduces the
# real dedicated server (build 747465) exactly on 948 real calls: the tile maps, the returned points and the number of PCG
# draws. Build 756039 generates the same caves worlds. The Windows variants differ by the RAND_MAX 0x7fff shuffle (VC9
# random_shuffle) and MSVCR90's powf.

type Evolved is Data:
  Evolved{cells: List<&2, U32>, rng: Pcg.Rng}

def evolved_out(ca: CaveAutomaton.Ca, +n: U32) -> Evolved:
  match ca:
    case CaveAutomaton.Ca{a, _, rng}:
      Evolved{CaveGrid.read(a, n), rng}

# std::random_shuffle of seven items, libstdc++ with rand() % 0x7fffffff.
law shuffle_linux:
  {CaveShuffle.large(False{}, [10, 20, 30, 40, 50, 60, 70], Pcg.srandom(5)) == CaveShuffle.Shuffled{[20, 30, 50, 70, 60, 40, 10], Pcg.Rng{3631917672, 912078273}} : CaveShuffle.Shuffled}

def shuffle_linux():
  {==}

# std::random_shuffle of seven items, VC9 with rand() % 0x7fff.
law shuffle_windows:
  {CaveShuffle.large(True{}, [10, 20, 30, 40, 50, 60, 70], Pcg.srandom(5)) == CaveShuffle.Shuffled{[40, 10, 60, 70, 20, 30, 50], Pcg.Rng{3631917672, 912078273}} : CaveShuffle.Shuffled}

def shuffle_windows():
  {==}

# The automaton on a 4 x 3 grid with two seeded cells, two passes.
law automaton_kernel:
  {evolved_out(CaveAutomaton.evolve(CaveGrid.grid([0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 4, 0], 4, 3), 4, 3, 2, Pcg.srandom(7)), 12) == Evolved{[2, 1, 3, 4, 4, 4, 3, 4, 4, 4, 4, 3], Pcg.Rng{2029743146, 1121633581}} : Evolved}

def automaton_kernel():
  {==}

# The meta-maze walk (linux) over a 16 x 12 maze grid of 4 x 4 cells with the last cell blocked: keys are the open sides.
law meta_maze_linux:
  {CaveMeta.meta_maze(False{}, CaveGrid.grid([36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994], 16, 12), 16, 4, 3, 4, Pcg.srandom(3)) == CaveMeta.Meta{[CaveMeta.Keyed{2, 0}, CaveMeta.Keyed{3, 65536}, CaveMeta.Keyed{3, 65538}, CaveMeta.Keyed{6, 131072}, CaveMeta.Keyed{8, 65537}, CaveMeta.Keyed{9, 3}, CaveMeta.Keyed{10, 1}, CaveMeta.Keyed{10, 2}, CaveMeta.Keyed{10, 131073}, CaveMeta.Keyed{12, 65539}, CaveMeta.Keyed{12, 131074}], Pcg.Rng{1744748392, 3616809994}} : CaveMeta.Meta}

def meta_maze_linux():
  {==}

# The meta-maze walk (windows) over a 16 x 12 maze grid of 4 x 4 cells with the last cell blocked: keys are the open sides.
law meta_maze_windows:
  {CaveMeta.meta_maze(True{}, CaveGrid.grid([36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994], 16, 12), 16, 4, 3, 4, Pcg.srandom(3)) == CaveMeta.Meta{[CaveMeta.Keyed{3, 0}, CaveMeta.Keyed{3, 65537}, CaveMeta.Keyed{4, 65539}, CaveMeta.Keyed{5, 65536}, CaveMeta.Keyed{6, 131072}, CaveMeta.Keyed{8, 65538}, CaveMeta.Keyed{8, 131074}, CaveMeta.Keyed{9, 3}, CaveMeta.Keyed{10, 1}, CaveMeta.Keyed{10, 2}, CaveMeta.Keyed{14, 131073}], Pcg.Rng{3553389989, 2117075833}} : CaveMeta.Meta}

def meta_maze_windows():
  {==}

def bare_site(polygon: List<&2, TileWorld.Point>) -> TileWorld.Site:
  TileWorld.Site{TileWorld.Node{37, 0, 0, 0, 0, 4294967295, 4294967295, 4294967295, 4294967295, 0}, 120.0, 130.0, 120.0, 130.0, polygon}

# RunCA on a site without polygon vertices segfaults the real server (caves seed 3026, attempt 1, node 37): CA_ctor keeps
# its empty box, and CA_CollectSiteTiles writes outside the 0 x 0 map while it scans 2^32 x 2^32 tiles.
law runca_crashes_without_polygon:
  {CaveAutomaton.crashes(bare_site(Nil{})) == True{} : Bool}

def runca_crashes_without_polygon():
  {==}

law runca_runs_with_polygon:
  {CaveAutomaton.crashes(bare_site([TileWorld.Point{110.0, 120.0}, TileWorld.Point{130.0, 120.0}, TileWorld.Point{120.0, 140.0}])) == False{} : Bool}

def runca_runs_with_polygon():
  {==}
