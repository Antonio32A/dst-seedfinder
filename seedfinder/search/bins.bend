import Base

# A round's CPU work in bins for the runtime's task cube. The search forks eight branches at the top, which start on
# eight rows of the cube, each with a balanced tree of eight bins below it, one bin per ring. A free thread takes the
# next ring in a fixed order (row after row, a row's rings by their index mod 8) and runs it to the end; work never
# moves between threads. So the bins are packed from the slots by estimated work (the heaviest slot first, to the
# least loaded bin) and laid out heaviest first in that order: a thread that finishes early takes a light bin while
# the heavy ones are still under way.

# The bins of a round: one slot each when they fit.
def leaves() -> Nat:
  64n

type Rank is Data:
  Rank{cost: U32, at: U32}

# Heavier first, then earlier.
def heavier(a: Rank, b: Rank) -> Bool:
  match a b:
    case Rank{+c, +i} Rank{+d, +j}:
      (c > d : U32) || (U32.is_eq(c, d) && (i <= j : U32))

def ranks(+costs: List<&2, U32>, +at: U32) -> List<&2, Rank>:
  match costs:
    case Nil{}:
      Nil{}
    case Con{+c, +rest}:
      Rank{c, at} <> ranks(rest, (at + 1 : U32))

# The index of the least loaded bin (the first of equals).
def lightest(+loads: List<&2, U32>, +i: Nat, +best: Nat, +low: U32) -> Nat:
  match loads:
    case Nil{}:
      best
    case Con{+l, +rest}:
      +under = (l < low : U32)
      lightest(rest, Nat.add(i, 1n), Bool.pick(Nat, under, i, best), Bool.pick(U32, under, l, low))

def loaded(+loads: List<&2, U32>, +bin: Nat, +cost: U32) -> List<&2, U32>:
  match loads bin:
    case Nil{} _:
      Nil{}
    case Con{+l, +rest} 0n:
      (l + cost : U32) <> rest
    case Con{+l, +rest} 1n+b:
      l <> loaded(rest, b, cost)

type Placed is Data:
  Placed{at: U32, bin: Nat}

def placed_le(a: Placed, b: Placed) -> Bool:
  match a b:
    case Placed{+i, _} Placed{+j, _}:
      (i <= j : U32)

def packed(+ranked: List<&2, Rank>, +loads: List<&2, U32>, +placed: List<&2, Placed>) -> List<&2, Placed>:
  match ranked:
    case Nil{}:
      placed
    case Con{Rank{+cost, +at}, +rest}:
      +bin = lightest(loads, 0n, 0n, 4294967295)
      packed(rest, loaded(loads, bin, cost), Placed{at, bin} <> placed)

def bins_of(+placed: List<&2, Placed>) -> List<&2, Nat>:
  match placed:
    case Nil{}:
      Nil{}
    case Con{Placed{_, +bin}, +rest}:
      bin <> bins_of(rest)

# The bin (of `bins`) of each slot of these costs, in slot order.
def assigned(+costs: List<&2, U32>, +bins: Nat) -> List<&2, Nat>:
  bins_of(List.sort(~Placed, ~placed_le, packed(List.sort(~Rank, ~heavier, ranks(costs, 0)), List.replicate(U32, bins, 0), Nil{})))

def unit_loads(+costs: List<&2, U32>, +bins: List<&2, Nat>, +loads: List<&2, U32>) -> List<&2, U32>:
  match costs bins:
    case Nil{} _:
      loads
    case Con{_, _} Nil{}:
      loads
    case Con{+c, +rest} Con{+b, +more}:
      unit_loads(rest, more, loaded(loads, b, c))

def numbered(+order: List<&2, Rank>, +k: Nat) -> List<&2, Placed>:
  match order:
    case Nil{}:
      Nil{}
    case Con{Rank{_, +at}, +rest}:
      Placed{at, k} <> numbered(rest, Nat.add(k, 1n))

# The cube's order of a row's leaves: a row's balanced tree of eight puts leaf i on the row's ring 7 + i, and the
# threads take the rings by their index mod 8, so leaf 1 first and leaf 0 last.
def leaf_at(+rank: Nat) -> Nat:
  +r = U32.from_nat(rank)
  +row = ((r >> 3n : U32) << 3n : U32)
  +q = (r - row : U32)
  U32.to_nat((row + Bool.pick(U32, U32.is_eq(q, 7), 0, (q + 1 : U32)) : U32))

def spots(+bins: List<&2, Nat>, +ranked: List<&2, Nat>) -> List<&2, Nat>:
  match bins:
    case Nil{}:
      Nil{}
    case Con{+b, +rest}:
      leaf_at(Maybe.default(&2, Nat, List.get(&2, Nat, ranked, b), 0n)) <> spots(rest, ranked)

# The leaf of each slot of these costs (slot order) among leaves(): its bin's place in the cube's order by estimated work.
def placed_leaves(+costs: List<&2, U32>) -> List<&2, Nat>:
  +n = List.length(&2, U32, costs)
  +bins = Bool.pick(Nat, Nat.is_lt(n, leaves()), n, leaves())
  +units = assigned(costs, bins)
  +loads = unit_loads(costs, units, List.replicate(U32, bins, 0))
  spots(units, bins_of(List.sort(~Placed, ~placed_le, numbered(List.sort(~Rank, ~heavier, ranks(loads, 0)), 0n))))

