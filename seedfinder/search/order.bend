import Base

# Scan order: a scan from `start` visits start, start + 1, ..., wrapping at 2^32, so a seed's place in it is
# seed - start (mod 2^32).

# The seed's position in the scan from start.
def position(+seed: U32, +start: U32) -> Nat:
  U32.to_nat((seed - start : U32))

def seed_itself(+seed: U32) -> U32:
  seed

# x inserted into a list sorted by scan position (after the items of the same position).
def inserted(~A: Data, ~seed_of: @+x:A -> U32, sorted: List<&2, A>, +x: A, +start: U32) -> List<&2, A>:
  match sorted:
    case Nil{}:
      [x]
    case Con{+head, +rest}:
      Bool.pick(List<&2, A>, Nat.is_lt(position(seed_of(x), start), position(seed_of(head), start)), x <> head <> rest,
        head <> inserted(~A, ~seed_of, rest, x, start))

# The items of `done` merged into `sorted`, in scan order.
def merged(~A: Data, ~seed_of: @+x:A -> U32, done: List<&2, A>, +sorted: List<&2, A>, +start: U32) -> List<&2, A>:
  match done:
    case Nil{}:
      sorted
    case Con{+x, rest}:
      merged(~A, ~seed_of, rest, inserted(~A, ~seed_of, sorted, x, start), start)
