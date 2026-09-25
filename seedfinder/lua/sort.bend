import Base

# Lua 5.1.5 table.sort (ltablib.c auxsort) over items[1..n], with the same comparisons in the same order, the same
# swaps, and the same outcome for inconsistent comparators: an "invalid order function for sorting" error (status 1)
# after the same comparisons and writes, and the partition scans reading t[0] and t[n + 1] (nil in Lua, the `nil_value`
# given to `sort` here; a scan that stops on t[n + 1] makes auxsort write the pivot there). The comparator
# `lt(state, a, b)` answers a < b and may thread any state (a counter, the arrays it looks keys up in, an RNG).
# Status 2: the step budget ran out (only an inconsistent comparator that keeps auxsort from shrinking its range).

type Sorting<-S: Type> is Type:
  Sorting{state: S, items: Array<U32>, status: U32}

type Probe<-S: Type> is Type:
  Probe{state: S, items: Array<U32>, index: U32, value: U32, hit: Bool, status: U32, done: Bool}

type Part<-S: Type> is Type:
  Part{state: S, items: Array<U32>, i: U32, j: U32, pivot: U32, l: U32, u: U32, status: U32, done: Bool}

type Plan<-S: Type> is Type:
  Plan{work: Sorting<S>, rl: U32, ru: U32, nl: U32, nu: U32, done: Bool}

def probe_compared(~S: Type, got: S & Bool, items: Array<U32>, +index: U32, +value: U32) -> Probe<S>:
  (st, +hit) = got
  Probe{st, items, index, value, hit, 0, False{}}

def probe_read(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +index: U32, +pivot: U32, +up: Bool) -> Probe<S>:
  (items, +value) = got
  probe_compared(~S, lt(st, Bool.pick(U32, up, value, pivot), Bool.pick(U32, up, pivot, value)), items, index, value)

# Reads a[index] and compares a[index] < P (up) or P < a[index] (down).
def probe(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +index: U32, +pivot: U32, +up: Bool) -> Probe<S>:
  probe_read(~S, ~lt, items[index], st, index, pivot, up)

def probe_branch(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, more: Bool, st: S, items: Array<U32>, +index: U32, +value: U32, +overrun: Bool, +pivot: U32, +up: Bool) -> Probe<S>:
  match more:
    case True{}:
      probe(~S, ~lt, st, items, Bool.pick(U32, up, (index + 1 : U32), (index - 1 : U32)), pivot, up)
    case False{}:
      Probe{st, items, index, value, False{}, Bool.to_u32(overrun), True{}}

def probe_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, pr: Probe<S>, +bound: U32, +pivot: U32, +up: Bool) -> Probe<S>:
  match n:
    case 0n:
      match pr:
        case Probe{st, items, +index, +value, +hit, _, _}:
          Probe{st, items, index, value, hit, 2, True{}}
    case 1n+p:
      match pr:
        case Probe{st, items, +index, +value, +hit, +status, +done}:
          match done:
            case True{}:
              Probe{st, items, index, value, hit, status, True{}}
            case False{}:
              +overrun = Bool.and(hit, Bool.pick(Bool, up, (index > bound : U32), (index < bound : U32)))
              probe_loop(~S, ~lt, p, probe_branch(~S, ~lt, Bool.and(hit, Bool.not(overrun)), st, items, index, value, overrun, pivot, up), bound, pivot, up)

# One partition scan: `while a[++i] < P` (up, error past u) or `while P < a[--j]` (down, error below l).
def scan(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +start: U32, +bound: U32, +pivot: U32, +up: Bool, +fuel: Nat) -> Probe<S>:
  probe_loop(~S, ~lt, fuel, probe(~S, ~lt, st, items, start, pivot, up), bound, pivot, up)

def crossed(~S: Type, stop: Bool, st: S, items: Array<U32>, +i: U32, +j: U32, +ai: U32, +aj: U32, +pivot: U32, +l: U32, +u: U32) -> Part<S>:
  match stop:
    case True{}:
      Part{st, items, i, j, pivot, l, u, 0, True{}}
    case False{}:
      items[i] <- aj
      items[j] <- ai
      Part{st, items, i, j, pivot, l, u, 0, False{}}

def after_down(~S: Type, pr: Probe<S>, +i: U32, +ai: U32, +pivot: U32, +l: U32, +u: U32) -> Part<S>:
  match pr:
    case Probe{st, items, +j, +aj, _, +status, _}:
      match status:
        case 0:
          crossed(~S, (j < i : U32), st, items, i, j, ai, aj, pivot, l, u)
        case _:
          Part{st, items, i, j, pivot, l, u, status, True{}}

def after_up(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, pr: Probe<S>, +j: U32, +pivot: U32, +l: U32, +u: U32, +fuel: Nat) -> Part<S>:
  match pr:
    case Probe{st, items, +i, +ai, _, +status, _}:
      match status:
        case 0:
          after_down(~S, scan(~S, ~lt, st, items, (j - 1 : U32), l, pivot, False{}, fuel), i, ai, pivot, l, u)
        case _:
          Part{st, items, i, j, pivot, l, u, status, True{}}

def part_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, part: Part<S>, +fuel: Nat) -> Part<S>:
  match n:
    case 0n:
      match part:
        case Part{st, items, +i, +j, +pivot, +l, +u, _, _}:
          Part{st, items, i, j, pivot, l, u, 2, True{}}
    case 1n+p:
      match part:
        case Part{st, items, +i, +j, +pivot, +l, +u, +status, +done}:
          match done:
            case True{}:
              Part{st, items, i, j, pivot, l, u, status, True{}}
            case False{}:
              part_loop(~S, ~lt, p, after_up(~S, ~lt, scan(~S, ~lt, st, items, (i + 1 : U32), u, pivot, True{}, fuel), j, pivot, l, u, fuel), fuel)

def final_right(~S: Type, got: Array<U32> & U32, st: S, +i: U32, +l: U32, +u: U32, +last: U32) -> Plan<S>:
  (items, +ai) = got
  items[(u - 1 : U32)] <- ai
  items[i] <- last
  +left_smaller = ((i + i : U32) < (l + u : U32) : U32)
  Plan{Sorting{st, items, 0}, Bool.pick(U32, left_smaller, l, (i + 1 : U32)), Bool.pick(U32, left_smaller, (i - 1 : U32), u), Bool.pick(U32, left_smaller, (i + 1 : U32), l), Bool.pick(U32, left_smaller, u, (i - 1 : U32)), False{}}

def final_left(~S: Type, got: Array<U32> & U32, st: S, +i: U32, +l: U32, +u: U32) -> Plan<S>:
  (items, +last) = got
  final_right(~S, items[i], st, i, l, u, last)

# Swap the pivot (a[u - 1]) with a[i]; plan the smaller half first, then loop on the larger one.
def finish(~S: Type, part: Part<S>) -> Plan<S>:
  match part:
    case Part{st, items, +i, _, _, +l, +u, +status, _}:
      match status:
        case 0:
          final_left(~S, items[(u - 1 : U32)], st, i, l, u)
        case _:
          Plan{Sorting{st, items, status}, 1, 0, 1, 0, True{}}

def pivot_swap(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +l: U32, +u: U32, +pivot: U32) -> Plan<S>:
  (items, +before_last) = got
  items[((l + u : U32) >> 1n : U32)] <- before_last
  items[(u - 1 : U32)] <- pivot
  +fuel = U32.to_nat(((u - l : U32) + 4 : U32))
  finish(~S, part_loop(~S, ~lt, fuel, Part{st, items, l, (u - 1 : U32), pivot, l, u, 0, False{}}, fuel))

def pivot_read(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +l: U32, +u: U32) -> Plan<S>:
  (items, +pivot) = got
  pivot_swap(~S, ~lt, items[(u - 1 : U32)], st, l, u, pivot)

def three_done(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, three: Bool, st: S, items: Array<U32>, +l: U32, +u: U32) -> Plan<S>:
  match three:
    case True{}:
      Plan{Sorting{st, items, 0}, 1, 0, 1, 0, True{}}
    case False{}:
      pivot_read(~S, ~lt, items[((l + u : U32) >> 1n : U32)], st, l, u)

def mid_right_swap(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: S & Bool, items: Array<U32>, +l: U32, +u: U32, +ai: U32, +au: U32) -> Plan<S>:
  (st, +b) = got
  items[((l + u : U32) >> 1n : U32)] <- Bool.pick(U32, b, au, ai)
  items[u] <- Bool.pick(U32, b, ai, au)
  three_done(~S, ~lt, U32.is_eq((u - l : U32), 2), st, items, l, u)

def mid_right(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +l: U32, +u: U32, +ai: U32) -> Plan<S>:
  (items, +au) = got
  mid_right_swap(~S, ~lt, lt(st, au, ai), items, l, u, ai, au)

def mid_choose(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, b: Bool, st: S, items: Array<U32>, +l: U32, +u: U32, +ai: U32, +al: U32) -> Plan<S>:
  match b:
    case True{}:
      items[((l + u : U32) >> 1n : U32)] <- al
      items[l] <- ai
      three_done(~S, ~lt, U32.is_eq((u - l : U32), 2), st, items, l, u)
    case False{}:
      mid_right(~S, ~lt, items[u], st, l, u, ai)

def mid_swap(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: S & Bool, items: Array<U32>, +l: U32, +u: U32, +ai: U32, +al: U32) -> Plan<S>:
  (st, +b) = got
  mid_choose(~S, ~lt, b, st, items, l, u, ai, al)

def mid_left(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +l: U32, +u: U32, +ai: U32) -> Plan<S>:
  (items, +al) = got
  mid_swap(~S, ~lt, lt(st, ai, al), items, l, u, ai, al)

def mid_read(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +l: U32, +u: U32) -> Plan<S>:
  (items, +ai) = got
  mid_left(~S, ~lt, items[l], st, l, u, ai)

def two_done(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, two: Bool, st: S, items: Array<U32>, +l: U32, +u: U32) -> Plan<S>:
  match two:
    case True{}:
      Plan{Sorting{st, items, 0}, 1, 0, 1, 0, True{}}
    case False{}:
      mid_read(~S, ~lt, items[((l + u : U32) >> 1n : U32)], st, l, u)

def ends_swap(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: S & Bool, items: Array<U32>, +l: U32, +u: U32, +al: U32, +au: U32) -> Plan<S>:
  (st, +b) = got
  items[l] <- Bool.pick(U32, b, au, al)
  items[u] <- Bool.pick(U32, b, al, au)
  two_done(~S, ~lt, U32.is_eq((u - l : U32), 1), st, items, l, u)

def ends_compare(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +l: U32, +u: U32, +al: U32) -> Plan<S>:
  (items, +au) = got
  ends_swap(~S, ~lt, lt(st, au, al), items, l, u, al, au)

def ends_read(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +l: U32, +u: U32) -> Plan<S>:
  (items, +al) = got
  ends_compare(~S, ~lt, items[u], st, l, u, al)

def step_go(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, go: Bool, st: S, items: Array<U32>, +status: U32, +l: U32, +u: U32) -> Plan<S>:
  match go:
    case True{}:
      ends_read(~S, ~lt, items[l], st, l, u)
    case False{}:
      Plan{Sorting{st, items, status}, 1, 0, 1, 0, True{}}

# One pass of auxsort's loop over [l, u]: median of three, pivot, partition; the plan names both halves.
def step(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: Sorting<S>, +l: U32, +u: U32) -> Plan<S>:
  match w:
    case Sorting{st, items, +status}:
      step_go(~S, ~lt, Bool.and((l < u : U32), U32.is_zero(status)), st, items, status, l, u)

def exhausted(~S: Type, w: Sorting<S>) -> Sorting<S>:
  match w:
    case Sorting{st, items, +status}:
      Sorting{st, items, Bool.pick(U32, U32.is_zero(status), 2, status)}

def aux(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, +n: Nat, plan: Plan<S>) -> Sorting<S>:
  match n:
    case 0n:
      match plan:
        case Plan{w, _, _, _, _, _}:
          exhausted(~S, w)
    case 1n+p:
      match plan:
        case Plan{w, +rl, +ru, +nl, +nu, +done}:
          match done:
            case True{}:
              w
            case False{}:
              aux(~S, ~lt, p, step(~S, ~lt, aux(~S, ~lt, p, step(~S, ~lt, w, rl, ru)), nl, nu))

# table.sort(t, lt) with t[1..n] in items[1..n] (items needs room for n + 2 slots). Slots 0 and n + 1 are set to
# nil_value first; read them back afterwards: a scan that runs off the end makes auxsort store the pivot in t[n + 1].
def sort(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +n: U32, +nil_value: U32) -> Sorting<S>:
  items[0] <- nil_value
  items[(n + 1 : U32)] <- nil_value
  aux(~S, ~lt, U32.to_nat(((n << 2n) + 64 : U32)), step(~S, ~lt, Sorting{st, items, 0}, 1, n))

def fingerprint_loop(n: Nat, got: Array<U32> & U32, +i: U32, +h: U32) -> U32:
  match n:
    case 0n:
      h
    case 1n+p:
      (items, +v) = got
      fingerprint_loop(p, items[(i + 1 : U32)], (i + 1 : U32), ((h .^. v) * 16777619 : U32))

# FNV-1a (32-bit, one step per word) over the status and items[1 .. n + 1] of a finished sort, for laws.
def fingerprint(w: Sorting<Unit>, +n: U32) -> U32:
  match w:
    case Sorting{_, items, +status}:
      fingerprint_loop(U32.to_nat((n + 1 : U32)), items[1], 1, ((2166136261 .^. status) * 16777619 : U32))
