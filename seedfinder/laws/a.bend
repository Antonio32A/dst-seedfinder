import Base
import ../f32/powf.bend as Powf
import ../rng/pcg.bend as Pcg
import ../worldsim/cave/automaton.bend as CaveAutomaton
import ../worldsim/cave/cells.bend as CaveCells
import ../worldsim/cave/growing.bend as CaveGrowing
import ../worldsim/cave/meta.bend as CaveMeta
import ../worldsim/cave/shuffle.bend as CaveShuffle

# Golden values of the cave engines' kernels (RunCA's automaton, the growing tree, the meta-maze walk and the C++ shuffle) on
# explicit grids, from a native reconstruction of WorldSim's RunCA, RunMaze and GetPointsForMetaMaze that reproduces the
# real dedicated server (build 747465) exactly on 948 real calls: the tile maps, the returned points and the number of PCG
# draws. The Windows variants differ by the RAND_MAX 0x7fff shuffle (VC9 random_shuffle) and MSVCR90's powf.

def load(xs: List<&2, U32>, a: Array<U32>, +k: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      a
    case Con{+x, rest}:
      a[k] <- x
      load(rest, a, (k + 1 : U32))

def read_loop(n: Nat, got: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      (_, _) = got
      acc
    case 1n+p:
      (cells, +v) = got
      read_loop(p, cells[(i - 1 : U32)], (i - 1 : U32), v <> acc)

def read(a: Array<U32>, +n: U32) -> List<&2, U32>:
  read_loop(U32.to_nat(n), a[(n - 1 : U32)], (n - 1 : U32), Nil{})

def grid(xs: List<&2, U32>, +w: U32, +h: U32) -> Array<U32>:
  load(xs, CaveCells.new(w, h, 0), 0)

# The first n cells of an array, the packed dead ends and the PCG state.
type Grown is Data:
  Grown{cells: List<&2, U32>, dead: List<&2, U32>, rng: Pcg.Rng}

def grown_out(g: CaveGrowing.Grown, +n: U32) -> Grown:
  match g:
    case CaveGrowing.Grown{cells, dead, rng}:
      Grown{read(cells, n), dead, rng}

type Evolved is Data:
  Evolved{cells: List<&2, U32>, rng: Pcg.Rng}

def evolved_out(ca: CaveAutomaton.Ca, +n: U32) -> Evolved:
  match ca:
    case CaveAutomaton.Ca{a, _, rng}:
      Evolved{read(a, n), rng}

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
  {evolved_out(CaveAutomaton.evolve(grid([0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 4, 0], 4, 3), 4, 3, 2, Pcg.srandom(7)), 12) == Evolved{[2, 1, 3, 4, 4, 4, 3, 4, 4, 4, 4, 3], Pcg.Rng{2029743146, 1121633581}} : Evolved}

def automaton_kernel():
  {==}

# The meta-maze walk (linux) over a 16 x 12 maze grid of 4 x 4 cells with the last cell blocked: keys are the open sides.
law meta_maze_linux:
  {CaveMeta.meta_maze(False{}, grid([36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994], 16, 12), 16, 4, 3, 4, Pcg.srandom(3)) == CaveMeta.Meta{[CaveMeta.Keyed{2, 0}, CaveMeta.Keyed{3, 65536}, CaveMeta.Keyed{3, 65538}, CaveMeta.Keyed{6, 131072}, CaveMeta.Keyed{8, 65537}, CaveMeta.Keyed{9, 3}, CaveMeta.Keyed{10, 1}, CaveMeta.Keyed{10, 2}, CaveMeta.Keyed{10, 131073}, CaveMeta.Keyed{12, 65539}, CaveMeta.Keyed{12, 131074}], Pcg.Rng{1744748392, 3616809994}} : CaveMeta.Meta}

def meta_maze_linux():
  {==}

# The meta-maze walk (windows) over a 16 x 12 maze grid of 4 x 4 cells with the last cell blocked: keys are the open sides.
law meta_maze_windows:
  {CaveMeta.meta_maze(True{}, grid([36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994], 16, 12), 16, 4, 3, 4, Pcg.srandom(3)) == CaveMeta.Meta{[CaveMeta.Keyed{3, 0}, CaveMeta.Keyed{3, 65537}, CaveMeta.Keyed{4, 65539}, CaveMeta.Keyed{5, 65536}, CaveMeta.Keyed{6, 131072}, CaveMeta.Keyed{8, 65538}, CaveMeta.Keyed{8, 131074}, CaveMeta.Keyed{9, 3}, CaveMeta.Keyed{10, 1}, CaveMeta.Keyed{10, 2}, CaveMeta.Keyed{14, 131073}], Pcg.Rng{3553389989, 2117075833}} : CaveMeta.Meta}

def meta_maze_windows():
  {==}

