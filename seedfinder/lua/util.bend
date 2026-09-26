import Base
import ../rng/pcg.bend as Pcg
import ./math_random.bend as MathRandom
import ./table.bend as LuaTable

# The game's util.lua helpers on the worldgen path, with the same math.random draws: shuffleArray, shuffledKeys,
# GetTableSize, GetRandomItem(WithIndex), GetRandomKey, weighted_random_choice (integer weights), PickSome,
# PickSomeWithDups, ArrayIntersection, deepcopy (its insertion order). Lua arrays t[1..n] are items[0..n-1] here.
# `nil_value` stands for a Lua nil read from an array slot.

type Shuffled is Type:
  Shuffled{items: Array<U32>, rng: Pcg.Rng}

type Chosen is Type:
  Chosen{table: LuaTable.Table, step: LuaTable.Step, rng: Pcg.Rng}

type Picked is Type:
  Picked{items: Array<U32>, count: U32, picked: List<&2, U32>, rng: Pcg.Rng, status: U32}

def swap_second(got: Array<U32> & U32, +i: U32, +j: U32, +vi: U32) -> Array<U32>:
  (items, +vj) = got
  items[i] <- vj
  items[j] <- vi

def swap_first(got: Array<U32> & U32, +i: U32, +j: U32) -> Array<U32>:
  (items, +vi) = got
  swap_second(items[j], i, j, vi)

def swap(items: Array<U32>, +i: U32, +j: U32) -> Array<U32>:
  swap_first(items[i], i, j)

def shuffle_step(got: U32 & Pcg.Rng, items: Array<U32>, +i: U32) -> Shuffled:
  (j, s) = got
  Shuffled{swap(items, (i - 1 : U32), (j - 1 : U32)), s}

def shuffle_loop(n: Nat, sh: Shuffled, +i: U32) -> Shuffled:
  match n:
    case 0n:
      sh
    case 1n+p:
      match sh:
        case Shuffled{items, s}:
          shuffle_loop(p, shuffle_step(MathRandom.random_range(s, 1, i), items, i), (i - 1 : U32))

# shuffleArray(array) for #array = n: for i = n down to 2, swap array[i] with array[math.random(1, i)] (n - 1 draws).
# A draw of 2^32 - 1 picks i + 1, as in the game: keep items[n] = nil_value for it.
def shuffle_array(items: Array<U32>, +n: U32, s: Pcg.Rng) -> Shuffled:
  shuffle_loop(U32.to_nat(Bool.pick(U32, (n >= 2 : U32), (n - 1 : U32), 0)), Shuffled{items, s}, n)

# The array of a shuffle result.
def items_of(sh: Shuffled) -> Array<U32>:
  match sh:
    case Shuffled{items, _}:
      items

def count_loop(n: Nat, got: LuaTable.Table & U32, +count: U32, +total: U32) -> LuaTable.Table & U32:
  match n:
    case 0n:
      (t, _) = got
      (t, count)
    case 1n+p:
      (t, +pos) = got
      +more = (pos < total : U32)
      count_loop(p, LuaTable.scan(t, Bool.pick(U32, more, (pos + 1 : U32), pos)), (count + Bool.to_u32(more) : U32), total)

def count_counted(got: LuaTable.Table & U32) -> LuaTable.Table & U32:
  (t, +total) = got
  count_loop(U32.to_nat((total + 1 : U32)), LuaTable.scan(t, 0), 0, total)

# GetTableSize(t): the number of pairs() entries.
def size(t: LuaTable.Table) -> LuaTable.Table & U32:
  count_counted(LuaTable.slot_count(t))

def nth_loop(n: Nat, got: LuaTable.Table & U32) -> LuaTable.Table & U32:
  match n:
    case 0n:
      got
    case 1n+p:
      (t, +pos) = got
      nth_loop(p, LuaTable.scan(t, (pos + 1 : U32)))

# The traversal position of the k-th pairs() entry (0-based).
def nth_position(t: LuaTable.Table, +k: U32) -> LuaTable.Table & U32:
  nth_loop(U32.to_nat(k), LuaTable.scan(t, 0))

def chosen_entry(got: LuaTable.Table & LuaTable.Step, s: Pcg.Rng) -> Chosen:
  (t, +step) = got
  Chosen{t, step, s}

def chosen_at(got: LuaTable.Table & U32, s: Pcg.Rng) -> Chosen:
  (t, +pos) = got
  chosen_entry(LuaTable.entry(t, pos), s)

def pick_drawn(got: U32 & Pcg.Rng, t: LuaTable.Table, +n: U32) -> Chosen:
  (+choice, s) = got
  chosen_at(nth_position(t, U32.min((choice - 1 : U32), (n - 1 : U32))), s)

def pick_sized(some: Bool, t: LuaTable.Table, +n: U32, s: Pcg.Rng) -> Chosen:
  match some:
    case True{}:
      pick_drawn(MathRandom.random_upto(s, n), t, n)
    case False{}:
      Chosen{t, LuaTable.Step{0, LuaTable.nil_key(), 0}, s}

def pick_counted(got: LuaTable.Table & U32, s: Pcg.Rng) -> Chosen:
  (t, +n) = got
  pick_sized(Bool.not(U32.is_zero(n)), t, n, s)

# GetRandomItem / GetRandomItemWithIndex(t): the entry at math.random(size) - 1 in pairs() order; no draw (status 0)
# when t is empty.
def random_entry(t: LuaTable.Table, s: Pcg.Rng) -> Chosen:
  pick_counted(size(t), s)

def empty_key(got: U32 & Pcg.Rng, t: LuaTable.Table) -> Chosen:
  (_, s) = got
  Chosen{t, LuaTable.Step{2, LuaTable.nil_key(), 0}, s}

def falsy_checked(c: Chosen) -> Chosen:
  match c:
    case Chosen{t, step, s}:
      match step:
        case LuaTable.Step{+status, +key, +value}:
          Chosen{t, LuaTable.Step{Bool.pick(U32, LuaTable.same_key(key, 3, 0, 0), 2, status), key, value}, s}

def key_choose(some: Bool, t: LuaTable.Table, +n: U32, s: Pcg.Rng) -> Chosen:
  match some:
    case True{}:
      falsy_checked(pick_drawn(MathRandom.random_upto(s, n), t, n))
    case False{}:
      empty_key(Pcg.draw(s), t)

def key_counted(got: LuaTable.Table & U32, s: Pcg.Rng) -> Chosen:
  (t, +n) = got
  key_choose(Bool.not(U32.is_zero(n)), t, n, s)

# GetRandomKey(t): like random_entry, but an empty t still draws and fails ("interval is empty", status 2), and so
# does picking the key false (its assert).
def random_key(t: LuaTable.Table, s: Pcg.Rng) -> Chosen:
  key_counted(size(t), s)

def weighted_loop(n: Nat, done: Bool, got: LuaTable.Table & LuaTable.Step, +prefix: U32, +target: U32, +last: LuaTable.Step) -> LuaTable.Table & LuaTable.Step:
  match n:
    case 0n:
      (t, _) = got
      (t, last)
    case 1n+p:
      match done:
        case True{}:
          (t, _) = got
          (t, last)
        case False{}:
          (t, +step) = got
          match step:
            case LuaTable.Step{+status, +key, +value}:
              +more = U32.is_eq(status, 1)
              +sum = (prefix + value : U32)
              weighted_loop(p, Bool.or(Bool.not(more), (sum >= target : U32)), LuaTable.next(t, Bool.pick(LuaTable.TKey, more, key, LuaTable.nil_key())), sum, target, Bool.pick(LuaTable.Step, more, LuaTable.Step{status, key, value}, last))

def total_loop(n: Nat, done: Bool, got: LuaTable.Table & LuaTable.Step, +sum: U32) -> LuaTable.Table & U32:
  match n:
    case 0n:
      (t, _) = got
      (t, sum)
    case 1n+p:
      match done:
        case True{}:
          (t, _) = got
          (t, sum)
        case False{}:
          (t, +step) = got
          match step:
            case LuaTable.Step{+status, +key, +value}:
              +more = U32.is_eq(status, 1)
              total_loop(p, Bool.not(more), LuaTable.next(t, Bool.pick(LuaTable.TKey, more, key, LuaTable.nil_key())), Bool.pick(U32, more, (sum + value : U32), sum))

def weighted_chosen(got: LuaTable.Table & LuaTable.Step, s: Pcg.Rng) -> Chosen:
  (t, +step) = got
  Chosen{t, step, s}

def weighted_found(got: LuaTable.Table & U32, +x: U32, s: Pcg.Rng, +scaled: MathRandom.Scaled) -> Chosen:
  (t, +total) = got
  match scaled:
    case MathRandom.Scaled{+f, +exact}:
      weighted_chosen(weighted_loop(U32.to_nat((total + 1 : U32)), False{}, LuaTable.next(t, LuaTable.nil_key()), 0, (f + Bool.to_u32(Bool.not(exact)) : U32), LuaTable.Step{0, LuaTable.nil_key(), 0}), s)

def weighted_scaled(got: LuaTable.Table & U32, +x: U32, s: Pcg.Rng) -> Chosen:
  (t, +total) = got
  weighted_found((t, total), x, s, MathRandom.scale(x, total))

def weighted_drawn(got: U32 & Pcg.Rng, t: LuaTable.Table) -> Chosen:
  (x, s) = got
  weighted_scaled(total_loop(4096n, False{}, LuaTable.next(t, LuaTable.nil_key()), 0), x, s)

# weighted_random_choice(t) for integer weights (the values): threshold = math.random() * total, then the first
# pairs() entry whose running weight sum reaches it (exact: every subtraction before the stop is exact). Status 0
# when t is empty.
def weighted_choice(t: LuaTable.Table, s: Pcg.Rng) -> Chosen:
  weighted_drawn(Pcg.draw(s), t)

def shift_one(got: Array<U32> & U32, +i: U32) -> Array<U32>:
  (items, +v) = got
  items[i] <- v

def shift_down(n: Nat, items: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      items
    case 1n+p:
      shift_down(p, shift_one(items[(i + 1 : U32)], i), (i + 1 : U32))

def remove_slot(remove: Bool, items: Array<U32>, +index: U32, +count: U32) -> Array<U32>:
  match remove:
    case True{}:
      shift_down(U32.to_nat(((count - index : U32) - 1 : U32)), items, index)
    case False{}:
      items

def picked_value(got: Array<U32> & U32, +count: U32, +choice: U32, +picked: List<&2, U32>, s: Pcg.Rng, +remove: Bool) -> Picked:
  (items, +value) = got
  Picked{remove_slot(remove, items, (choice - 1 : U32), count), Bool.pick(U32, remove, (count - 1 : U32), count), value <> picked, s, 0}

def pick_one(inside: Bool, items: Array<U32>, +count: U32, +choice: U32, +picked: List<&2, U32>, s: Pcg.Rng, +remove: Bool) -> Picked:
  match inside:
    case True{}:
      picked_value(items[(choice - 1 : U32)], count, choice, picked, s, remove)
    case False{}:
      Picked{items, count, picked, s, 0}

def pick_drawn_slot(got: U32 & Pcg.Rng, items: Array<U32>, +count: U32, +picked: List<&2, U32>, +remove: Bool) -> Picked:
  (+choice, s) = got
  pick_one((choice <= count : U32), items, count, choice, picked, s, remove)

def pick_empty(got: U32 & Pcg.Rng, items: Array<U32>, +picked: List<&2, U32>) -> Picked:
  (_, s) = got
  Picked{items, 0, picked, s, 2}

def pick_step(nonempty: Bool, items: Array<U32>, +count: U32, +picked: List<&2, U32>, s: Pcg.Rng, +remove: Bool) -> Picked:
  match nonempty:
    case True{}:
      pick_drawn_slot(MathRandom.random_upto(s, count), items, count, picked, remove)
    case False{}:
      pick_empty(Pcg.draw(s), items, picked)

def pick_loop(n: Nat, p: Picked, +remove: Bool) -> Picked:
  match n:
    case 0n:
      p
    case 1n+k:
      match p:
        case Picked{items, +count, +picked, s, +status}:
          match status:
            case 0:
              pick_loop(k, pick_step(Bool.not(U32.is_zero(count)), items, count, picked, s, remove), remove)
            case _:
              Picked{items, count, picked, s, status}

def reversed(p: Picked) -> Picked:
  match p:
    case Picked{items, +count, +picked, s, +status}:
      Picked{items, count, List.reverse(&2, U32, picked), s, status}

# PickSome(num, choices) on items[0..count-1]: num times math.random(#choices), take and remove that element.
# Status 2: choices ran out (math.random(0) fails after its draw). A 2^32 - 1 draw picks nothing, like Lua's nil.
def pick_some(+num: U32, items: Array<U32>, +count: U32, s: Pcg.Rng) -> Picked:
  reversed(pick_loop(U32.to_nat(num), Picked{items, count, Nil{}, s, 0}, True{}))

# PickSomeWithDups(num, choices): num times math.random(#choices), keeping the choices (num = floor of Lua's limit).
def pick_some_with_dups(+num: U32, items: Array<U32>, +count: U32, s: Pcg.Rng) -> Picked:
  reversed(pick_loop(U32.to_nat(num), Picked{items, count, Nil{}, s, 0}, False{}))

def contains(xs: List<&2, U32>, +v: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, rest}:
      Bool.or(U32.is_eq(x, v), contains(rest, v))

def in_all(lists: List<&2, List<&2, U32>>, +v: U32) -> Bool:
  match lists:
    case Nil{}:
      True{}
    case Con{+xs, rest}:
      Bool.and(contains(xs, v), in_all(rest, v))

def keep_if(keep: Bool, +v: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{}:
      v <> rest
    case False{}:
      rest

# ArrayIntersection(first, others...): the elements of first (in order, duplicates kept) found in every other array.
def array_intersection(first: List<&2, U32>, +others: List<&2, List<&2, U32>>) -> List<&2, U32>:
  match first:
    case Nil{}:
      Nil{}
    case Con{+v, rest}:
      keep_if(in_all(others, v), v, array_intersection(rest, others))

def set_if(more: Bool, fresh: LuaTable.Table, +key: LuaTable.TKey, +value: U32) -> LuaTable.Table:
  match more:
    case True{}:
      LuaTable.set(fresh, key, value)
    case False{}:
      fresh

def copy_loop(n: Nat, done: Bool, got: LuaTable.Table & LuaTable.Step, fresh: LuaTable.Table) -> LuaTable.Table & LuaTable.Table:
  match n:
    case 0n:
      (t, _) = got
      (t, fresh)
    case 1n+p:
      match done:
        case True{}:
          (t, _) = got
          (t, fresh)
        case False{}:
          (t, +step) = got
          match step:
            case LuaTable.Step{+status, +key, +value}:
              +more = U32.is_eq(status, 1)
              copy_loop(p, Bool.not(more), LuaTable.next(t, Bool.pick(LuaTable.TKey, more, key, LuaTable.nil_key())), set_if(more, fresh, key, value))

def copy_counted(got: LuaTable.Table & U32) -> LuaTable.Table & LuaTable.Table:
  (t, +n) = got
  copy_loop(U32.to_nat((n + 2 : U32)), False{}, LuaTable.next(t, LuaTable.nil_key()), LuaTable.new(0, 0))

# deepcopy(t)'s table shape: a new table ({}) with every pairs() entry of t set in traversal order.
def copy(t: LuaTable.Table) -> LuaTable.Table & LuaTable.Table:
  copy_counted(size(t))

type Keyed is Type:
  Keyed{table: LuaTable.Table, items: Array<U32>, count: U32, rng: Pcg.Rng}

def positions_loop(n: Nat, got: LuaTable.Table & U32, items: Array<U32>, +i: U32, +total: U32) -> LuaTable.Table & Array<U32> & U32:
  match n:
    case 0n:
      (t, _) = got
      (t, (items, i))
    case 1n+p:
      (t, +pos) = got
      +more = (pos < total : U32)
      items[i] <- Bool.pick(U32, more, pos, 4294967295)
      positions_loop(p, LuaTable.scan(t, Bool.pick(U32, more, (pos + 1 : U32), pos)), items, (i + Bool.to_u32(more) : U32), total)

def keyed_shuffled(sh: Shuffled, t: LuaTable.Table, +n: U32) -> Keyed:
  match sh:
    case Shuffled{items, s}:
      Keyed{t, items, n, s}

def keyed_counted(got: Array<U32> & U32, t: LuaTable.Table, s: Pcg.Rng) -> Keyed:
  (items, +n) = got
  keyed_shuffled(shuffle_array(items, n, s), t, n)

def keyed_positions(got: LuaTable.Table & Array<U32> & U32, s: Pcg.Rng) -> Keyed:
  (t, rest) = got
  keyed_counted(rest, t, s)

def keyed_total(got: LuaTable.Table & U32, s: Pcg.Rng) -> Keyed:
  (t, +total) = got
  keyed_positions(positions_loop(U32.to_nat((total + 1 : U32)), LuaTable.scan(t, 0), Array.new(U32, U32.to_nat((LuaTable.ceil_log2((total + 2 : U32)) : U32)), 4294967295), 0, total), s)

# shuffledKeys(t): t's keys in pairs() order, shuffled with shuffleArray. items[0..count-1] are traversal positions
# of t (LuaTable.entry gives the key); a 4294967295 slot is a Lua nil (only after a 2^32 - 1 draw).
def shuffled_keys(t: LuaTable.Table, s: Pcg.Rng) -> Keyed:
  keyed_total(LuaTable.slot_count(t), s)
