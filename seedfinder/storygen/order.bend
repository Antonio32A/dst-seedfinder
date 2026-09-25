import Base
import ../lua/table.bend as LT
import ../lua/math_random.bend as LM

# pairs() orders of the Lua tables storygen builds: a table is replayed from its insertion history into lua/table.bend
# (a fresh `{}` and one t[k] = v per insertion), and read back in traversal order. Keys are strings (hash, id) or
# integers; each entry's value is its id.

type Slot is Data:
  Slot{hash: U32, id: U32}

def fill(keys: List<&2, Slot>, t: LT.Table) -> LT.Table:
  match keys:
    case Nil{}:
      t
    case Con{+k, rest}:
      match k:
        case Slot{+hash, +id}:
          fill(rest, LT.set(t, LT.string_key(hash, id), id))

def fill_ints(keys: List<&2, U32>, t: LT.Table) -> LT.Table:
  match keys:
    case Nil{}:
      t
    case Con{+k, rest}:
      fill_ints(rest, LT.set(t, LT.int_key(k), k))

def values_loop(n: Nat, got: LT.Table & LT.Step, +pos: U32, +acc: List<&2, U32>) -> LT.Table & List<&2, U32>:
  match n:
    case 0n:
      (t, _) = got
      (t, List.reverse(&2, U32, acc))
    case 1n+p:
      (t, +step) = got
      match step:
        case LT.Step{+status, _, +value}:
          +next = (pos + 1 : U32)
          values_loop(p, LT.entry(t, next), next, Bool.pick(List<&2, U32>, U32.is_eq(status, 1), value <> acc, acc))

def values_counted(got: LT.Table & U32) -> LT.Table & List<&2, U32>:
  (t, +total) = got
  values_loop(U32.to_nat(total), LT.entry(t, 0), 0, Nil{})

# The values of t in pairs() order.
def values(t: LT.Table) -> LT.Table & List<&2, U32>:
  values_counted(LT.slot_count(t))

def values_only(got: LT.Table & List<&2, U32>) -> List<&2, U32>:
  (_, +vs) = got
  vs

# The ids of a fresh table after t[key] = id for each key in turn, in pairs() order.
def order(keys: List<&2, Slot>) -> List<&2, U32>:
  values_only(values(fill(keys, LT.new(0, 0))))

# The same for integer keys (each key is its own value).
def int_order(keys: List<&2, U32>) -> List<&2, U32>:
  values_only(values(fill_ints(keys, LT.new(0, 0))))

def count(xs: List<&2, U32>, +n: U32) -> U32:
  match xs:
    case Nil{}:
      n
    case Con{_, rest}:
      count(rest, (n + 1 : U32))

# The element at 0-based index k, or the last one when k is past the end (Lua's pairs() walks that stop at the end).
def nth_or_last(xs: List<&2, U32>, +k: U32, +last: U32) -> U32:
  match xs:
    case Nil{}:
      last
    case Con{+x, rest}:
      Bool.pick(U32, U32.is_zero(k), x, nth_or_last(rest, (k - 1 : U32), x))

def contains(xs: List<&2, U32>, +v: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, rest}:
      U32.is_eq(x, v) || contains(rest, v)

def without(xs: List<&2, U32>, +v: U32) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, +rest}:
      Bool.pick(List<&2, U32>, U32.is_eq(x, v), rest, x <> without(rest, v))

def remove_all(keys: List<&2, Slot>, t: LT.Table) -> LT.Table:
  match keys:
    case Nil{}:
      t
    case Con{+k, rest}:
      match k:
        case Slot{+hash, +id}:
          remove_all(rest, LT.remove(t, LT.string_key(hash, id)))

# The same after t[key] = nil for each of `removed` in turn.
def order_after(keys: List<&2, Slot>, removed: List<&2, Slot>) -> List<&2, U32>:
  values_only(values(remove_all(removed, fill(keys, LT.new(0, 0)))))

# weighted_random_choice over n unit weights (0-weight entries are never candidates): the 0-based pick for draw x.
def scaled_pick(+scaled: LM.Scaled, +n: U32) -> U32:
  match scaled:
    case LM.Scaled{+f, +exact}:
      +k = (f + Bool.to_u32(Bool.not(exact)) : U32)
      U32.min((U32.max(k, 1) - 1 : U32), (n - 1 : U32))

def unit_weight_pick(+x: U32, +n: U32) -> U32:
  scaled_pick(LM.scale(x, n), n)
