import Base
import ../../rng/pcg.bend as Pcg
import ../../rng/crand.bend as CRand
import ../grid.bend as Grid

# std::random_shuffle of a list of packed values (Linux: libstdc++ with rand() % 0x7fffffff; Windows: VC9 with
# RAND_MAX 0x7fff), n - 1 rand() draws for n items.

type Shuffled is Data:
  Shuffled{items: List<&2, U32>, rng: Pcg.Rng}

def fill(xs: List<&2, U32>, items: Array<U32>, +k: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      items
    case Con{+x, rest}:
      items[k] <- x
      fill(rest, items, (k + 1 : U32))

def collect(n: Nat, got: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      (_, _) = got
      acc
    case 1n+p:
      (items, +v) = got
      collect(p, items[(i - 1 : U32)], (i - 1 : U32), v <> acc)

def read_back(sh: CRand.Shuffled, +n: U32) -> Shuffled:
  match sh:
    case CRand.Shuffled{items, s}:
      Shuffled{collect(U32.to_nat(n), items[(n - 1 : U32)], (n - 1 : U32), Nil{}), s}

def shuffle_in(+windows: Bool, items: Array<U32>, +n: U32, s: Pcg.Rng) -> Shuffled:
  read_back(CRand.random_shuffle(windows, items, n, s), n)

def empty_or(nonempty: Bool, xs: List<&2, U32>, s: Pcg.Rng, +windows: Bool, +n: U32, items: Array<U32>) -> Shuffled:
  match nonempty:
    case False{}:
      Shuffled{Nil{}, s}
    case True{}:
      shuffle_in(windows, fill(xs, items, 0), n, s)

# Up to four items (a maze cell's neighbours).
def small(+windows: Bool, +xs: List<&2, U32>, s: Pcg.Rng) -> Shuffled:
  empty_or(Bool.not(List.is_empty(&2, U32, xs)), xs, s, windows, U32.from_nat(List.length(&2, U32, xs)), [0 : U32^2n])

# Any number of items.
def large(+windows: Bool, +xs: List<&2, U32>, s: Pcg.Rng) -> Shuffled:
  +n = U32.from_nat(List.length(&2, U32, xs))
  empty_or(Bool.not(List.is_empty(&2, U32, xs)), xs, s, windows, n, Grid.alloc(Grid.depth_for(24n, n, 0n, 1), 0))
