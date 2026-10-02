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
# draws. Build 756039 generates the same caves worlds. The Windows variants differ by the RAND_MAX 0x7fff shuffle (VC9
# random_shuffle) and MSVCR90's powf.

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

# The growing tree (type 3, val 2, linux) over a 10 x 10 maze grid sampled to 5 x 5 cells; a cell is lo | hi << 8.
law growing_tree_linux:
  {grown_out(CaveGrowing.grow(False{}, grid([52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994], 10, 10), 10, 5, 5, 2, Powf.maze_exponent(2), True{}, Pcg.srandom(11)), 100) == Grown{[52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 36609, 36609, 36609, 36609, 36609, 36609, 52994, 52994, 52994, 52994, 36609, 36609, 36609, 36609, 36609, 36609, 52994, 52994, 52994, 52994, 36609, 36609, 36610, 36610, 36609, 36609, 52994, 52994, 52994, 52994, 36609, 36609, 36610, 36610, 36609, 36609, 52994, 52994, 52994, 52994, 36609, 36609, 36610, 36610, 36609, 36609, 52994, 52994, 52994, 52994, 36609, 36609, 36610, 36610, 36609, 36609, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994], [131074], Pcg.Rng{3787306261, 3936394155}} : Grown}

def growing_tree_linux():
  {==}

# The growing tree (type 3, val 2, windows) over a 10 x 10 maze grid sampled to 5 x 5 cells; a cell is lo | hi << 8.
law growing_tree_windows:
  {grown_out(CaveGrowing.grow(True{}, grid([52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 36612, 36612, 36612, 36612, 36612, 36612, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994], 10, 10), 10, 5, 5, 2, Powf.maze_exponent(2), True{}, Pcg.srandom(11)), 100) == Grown{[52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 36609, 36609, 36609, 36609, 36609, 36609, 52994, 52994, 52994, 52994, 36609, 36609, 36609, 36609, 36609, 36609, 52994, 52994, 52994, 52994, 36609, 36609, 36609, 36609, 36609, 36609, 52994, 52994, 52994, 52994, 36609, 36609, 36609, 36609, 36609, 36609, 52994, 52994, 52994, 52994, 36609, 36609, 36609, 36609, 36610, 36610, 52994, 52994, 52994, 52994, 36609, 36609, 36609, 36609, 36610, 36610, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994, 52994], [], Pcg.Rng{2932654950, 1425187230}} : Grown}

def growing_tree_windows():
  {==}

