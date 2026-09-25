import Base

# A read-only table indexed by U32: a complete binary tree split on the low index bit first, so a lookup walks the
# index bits from the bottom. Reusable (Data), so lookups need no threading.
type Tree<-A: Data> is Data:
  Leaf{value: A}
  Fork{lo: Tree<A>, hi: Tree<A>}

def look(~A: Data, t: Tree<A>, +i: U32, b: Bool) -> A:
  match t:
    case Leaf{+v}:
      v
    case Fork{lo, hi}:
      match b:
        case True{}:
          look(~A, hi, (i >> 1n : U32), U32.is_eq((i .&. 1 : U32), 1))
        case False{}:
          look(~A, lo, (i >> 1n : U32), U32.is_eq((i .&. 1 : U32), 1))

# Entry i; an index past the built entries answers the fill value or an arbitrary entry.
def at(~A: Data, +t: Tree<A>, +i: U32) -> A:
  look(~A, t, (i >> 1n : U32), U32.is_eq((i .&. 1 : U32), 1))

def pick_loop(~A: Data, xs: List<&2, A>, take: Bool, acc: List<&2, A>) -> List<&2, A>:
  match xs:
    case Nil{}:
      List.reverse(&2, A, acc)
    case Con{+x, rest}:
      match take:
        case True{}:
          pick_loop(~A, rest, False{}, x <> acc)
        case False{}:
          pick_loop(~A, rest, True{}, acc)

def first_or(~A: Data, xs: List<&2, A>, +fill: A) -> A:
  match xs:
    case Nil{}:
      fill
    case Con{+x, _}:
      x

def build(~A: Data, +d: Nat, +xs: List<&2, A>, +fill: A) -> Tree<A>:
  match d:
    case 0n:
      Leaf{first_or(~A, xs, fill)}
    case 1n+p:
      Fork{build(~A, p, pick_loop(~A, xs, True{}, Nil{}), fill), build(~A, p, pick_loop(~A, xs, False{}, Nil{}), fill)}

def depth_loop(n: Nat, +count: Nat, +size: Nat, +d: Nat, big: Bool) -> Nat:
  match n:
    case 0n:
      d
    case 1n+p:
      match big:
        case True{}:
          d
        case False{}:
          depth_loop(p, count, Nat.mul(size, 2n), 1n+d, Nat.is_ge(Nat.mul(size, 2n), count))

# The table of xs (entry i = the i-th element).
def from_list(~A: Data, +xs: List<&2, A>, +fill: A) -> Tree<A>:
  +count = List.length(&2, A, xs)
  build(~A, depth_loop(32n, count, 1n, 0n, Nat.is_ge(1n, count)), xs, fill)
