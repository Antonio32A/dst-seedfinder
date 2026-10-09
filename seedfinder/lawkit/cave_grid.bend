import Base
import ../worldsim/cave/cells.bend as CaveCells

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
