import Base
import ./heap.bend as SH

# std::sort over items[first, last) with the comparisons, in order, and the moves of the game's two C++ libraries:
# `sort` is libstdc++ (GCC >= 4.9, the Linux build: introsort, threshold 16, __move_median_to_first(first + 1, mid,
# last - 1), unguarded partition, heap fallback at depth 2 lg n, final insertion sort); `msvc_sort` is VC9 (the Windows
# build: _Sort with _ISORT_MAX 32 and _Ideal 1.5 lg n, _Median with the ninther above 40, the fat _Unguarded_partition,
# make_heap + sort_heap fallback, _Insertion_sort). lt(state, a, b) answers a < b and may thread any state.
# With a comparator that is not a strict weak order the C++ scans are unguarded (undefined behaviour); here they
# stop when their budget runs out.

type Compared<-S: Type> is Type:
  Compared{state: S, items: Array<U32>, x: U32, y: U32, less: Bool}

type Scan<-S: Type> is Type:
  Scan{state: S, items: Array<U32>, index: U32, value: U32, hit: Bool, done: Bool}

type Cut<-S: Type> is Type:
  Cut{state: S, items: Array<U32>, lo: U32, hi: U32, done: Bool}

type Plan<-S: Type> is Type:
  Plan{work: SH.Work<S>, rf: U32, rl: U32, rd: U32, nf: U32, nl: U32, nd: U32, done: Bool}

type Fat<-S: Type> is Type:
  Fat{state: S, items: Array<U32>, pf: U32, pl: U32, gf: U32, gl: U32, done: Bool}

def floor_log2_loop(n: Nat, +x: U32, +e: U32) -> U32:
  match n:
    case 0n:
      e
    case 1n+p:
      floor_log2_loop(p, (x >> 1n : U32), (e + Bool.to_u32((x >= 2 : U32)) : U32))

# floor(log2 x) for x >= 1 (std::__lg), 0 for x = 0.
def floor_log2(+x: U32) -> U32:
  floor_log2_loop(32n, x, 0)

def cmp_done(~S: Type, got: S & Bool, items: Array<U32>, +x: U32, +y: U32) -> Compared<S>:
  (st, +less) = got
  Compared{st, items, x, y, less}

def cmp_second(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +x: U32) -> Compared<S>:
  (items, +y) = got
  cmp_done(~S, lt(st, x, y), items, x, y)

def cmp_first(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +j: U32) -> Compared<S>:
  (items, +x) = got
  cmp_second(~S, ~lt, items[j], st, x)

# a[i] < a[j], with both values.
def compare_at(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +i: U32, +j: U32) -> Compared<S>:
  cmp_first(~S, ~lt, items[i], st, j)

def swap_second(got: Array<U32> & U32, +i: U32, +j: U32, +vi: U32) -> Array<U32>:
  (items, +vj) = got
  items[i] <- vj
  items[j] <- vi

def swap_first(got: Array<U32> & U32, +i: U32, +j: U32) -> Array<U32>:
  (items, +vi) = got
  swap_second(items[j], i, j, vi)

# std::iter_swap
def swap(items: Array<U32>, +i: U32, +j: U32) -> Array<U32>:
  swap_first(items[i], i, j)

def scan_compared(~S: Type, got: S & Bool, items: Array<U32>, +index: U32, +value: U32) -> Scan<S>:
  (st, +hit) = got
  Scan{st, items, index, value, hit, Bool.not(hit)}

def scan_read(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +index: U32, +pivot: U32, +up: Bool) -> Scan<S>:
  (items, +value) = got
  scan_compared(~S, lt(st, Bool.pick(U32, up, value, pivot), Bool.pick(U32, up, pivot, value)), items, index, value)

# Reads a[index] and compares a[index] < pivot (up) or pivot < a[index] (down); done when it is not less.
def scan_probe(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +index: U32, +pivot: U32, +up: Bool) -> Scan<S>:
  scan_read(~S, ~lt, items[index], st, index, pivot, up)

def scan_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, sc: Scan<S>, +pivot: U32, +up: Bool) -> Scan<S>:
  match n:
    case 0n:
      sc
    case 1n+p:
      match sc:
        case Scan{st, items, +index, +value, +hit, +done}:
          match done:
            case True{}:
              Scan{st, items, index, value, hit, True{}}
            case False{}:
              scan_loop(~S, ~lt, p, scan_probe(~S, ~lt, st, items, Bool.pick(U32, up, (index + 1 : U32), (index - 1 : U32)), pivot, up), pivot, up)

# The unguarded scans `while (a[i] < pivot) ++i` (up) and `while (pivot < a[i]) --i` (down), from start.
def scan(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +start: U32, +pivot: U32, +up: Bool, +fuel: Nat) -> Scan<S>:
  scan_loop(~S, ~lt, fuel, scan_probe(~S, ~lt, st, items, start, pivot, up), pivot, up)

def sink_write(~S: Type, hit: Bool, st: S, items: Array<U32>, +hole: U32, +below: U32) -> SH.Hole<S>:
  match hit:
    case True{}:
      items[hole] <- below
      SH.Hole{st, items, (hole - 1 : U32), False{}}
    case False{}:
      SH.Hole{st, items, hole, True{}}

def sink_decided(~S: Type, sc: Scan<S>, +hole: U32) -> SH.Hole<S>:
  match sc:
    case Scan{st, items, _, +below, +hit, _}:
      sink_write(~S, hit, st, items, hole, below)

def insert_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, h: SH.Hole<S>, +value: U32) -> SH.Work<S>:
  match n:
    case 0n:
      match h:
        case SH.Hole{st, items, +hole, _}:
          items[hole] <- value
          SH.Work{st, items}
    case 1n+p:
      match h:
        case SH.Hole{st, items, +hole, +done}:
          match done:
            case True{}:
              items[hole] <- value
              SH.Work{st, items}
            case False{}:
              insert_loop(~S, ~lt, p, sink_decided(~S, scan_probe(~S, ~lt, st, items, (hole - 1 : U32), value, False{}), hole), value)

# __unguarded_linear_insert: while value < a[hole - 1], shift it up; then value goes into the hole.
def linear_insert(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +hole: U32, +value: U32, +fuel: Nat) -> SH.Work<S>:
  insert_loop(~S, ~lt, fuel, SH.Hole{st, items, hole, False{}}, value)

def shift_up(n: Nat, got: Array<U32> & U32, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      (items, _) = got
      items
    case 1n+p:
      (items, +v) = got
      items[(i + 1 : U32)] <- v
      shift_up(p, items[(i - 1 : U32)], (i - 1 : U32))

def front_choose(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, less: Bool, st: S, items: Array<U32>, +first: U32, +i: U32, +value: U32, +fuel: Nat) -> SH.Work<S>:
  match less:
    case True{}:
      moved = shift_up(U32.to_nat((i - first : U32)), items[(i - 1 : U32)], (i - 1 : U32))
      moved[first] <- value
      SH.Work{st, moved}
    case False{}:
      linear_insert(~S, ~lt, st, items, i, value, fuel)

def front_insert(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, c: Compared<S>, +first: U32, +i: U32, +fuel: Nat) -> SH.Work<S>:
  match c:
    case Compared{st, items, +value, _, +less}:
      front_choose(~S, ~lt, less, st, items, first, i, value, fuel)

def insertion_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, w: SH.Work<S>, +first: U32, +i: U32, +fuel: Nat) -> SH.Work<S>:
  match n:
    case 0n:
      w
    case 1n+p:
      match w:
        case SH.Work{st, items}:
          insertion_loop(~S, ~lt, p, front_insert(~S, ~lt, compare_at(~S, ~lt, st, items, i, first), first, i, fuel), first, (i + 1 : U32), fuel)

# __insertion_sort / VC9 _Insertion_sort: a[i] < a[first] moves a[i] to the front, else an unguarded linear insert.
def insertion_sort(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> SH.Work<S>:
  +count = (last - first : U32)
  insertion_loop(~S, ~lt, U32.to_nat(Bool.pick(U32, (count >= 2 : U32), (count - 1 : U32), 0)), SH.Work{st, items}, first, (first + 1 : U32), U32.to_nat((count + 2 : U32)))

def value_insert(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +i: U32, +fuel: Nat) -> SH.Work<S>:
  (items, +value) = got
  linear_insert(~S, ~lt, st, items, i, value, fuel)

def unguarded_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, w: SH.Work<S>, +i: U32, +fuel: Nat) -> SH.Work<S>:
  match n:
    case 0n:
      w
    case 1n+p:
      match w:
        case SH.Work{st, items}:
          unguarded_loop(~S, ~lt, p, value_insert(~S, ~lt, items[i], st, i, fuel), (i + 1 : U32), fuel)

# __unguarded_insertion_sort: a linear insert of every element of [from, last).
def unguarded_insertion_sort(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +from: U32, +last: U32, +fuel: Nat) -> SH.Work<S>:
  unguarded_loop(~S, ~lt, U32.to_nat((last - from : U32)), SH.Work{st, items}, from, fuel)

def final_after_head(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: SH.Work<S>, +first: U32, +last: U32) -> SH.Work<S>:
  match w:
    case SH.Work{st, items}:
      unguarded_insertion_sort(~S, ~lt, st, items, (first + 16 : U32), last, U32.to_nat(((last - first : U32) + 2 : U32)))

def final_split(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, long: Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> SH.Work<S>:
  match long:
    case True{}:
      final_after_head(~S, ~lt, insertion_sort(~S, ~lt, st, items, first, (first + 16 : U32)), first, last)
    case False{}:
      insertion_sort(~S, ~lt, st, items, first, last)

# __final_insertion_sort
def final_insertion_sort(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> SH.Work<S>:
  final_split(~S, ~lt, ((last - first : U32) > 16 : U32), st, items, first, last)

def median_swap(~S: Type, c: Compared<S>, +first: U32, +chosen: U32) -> SH.Work<S>:
  match c:
    case Compared{st, items, _, _, _}:
      SH.Work{st, swap(items, first, chosen)}

def median_last(~S: Type, c: Compared<S>, +first: U32, +if_less: U32, +otherwise: U32) -> SH.Work<S>:
  match c:
    case Compared{st, items, _, _, +less}:
      SH.Work{st, swap(items, first, Bool.pick(U32, less, if_less, otherwise))}

def median_low_pick(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, a_less_c: Bool, st: S, items: Array<U32>, +first: U32, +a: U32, +b: U32, +cc: U32) -> SH.Work<S>:
  match a_less_c:
    case True{}:
      SH.Work{st, swap(items, first, a)}
    case False{}:
      median_last(~S, compare_at(~S, ~lt, st, items, b, cc), first, cc, b)

def median_low(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, c: Compared<S>, +first: U32, +a: U32, +b: U32, +cc: U32) -> SH.Work<S>:
  match c:
    case Compared{st, items, _, _, +a_less_c}:
      median_low_pick(~S, ~lt, a_less_c, st, items, first, a, b, cc)

def median_high_pick(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, b_less_c: Bool, st: S, items: Array<U32>, +first: U32, +a: U32, +b: U32, +cc: U32) -> SH.Work<S>:
  match b_less_c:
    case True{}:
      SH.Work{st, swap(items, first, b)}
    case False{}:
      median_last(~S, compare_at(~S, ~lt, st, items, a, cc), first, cc, a)

def median_high(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, c: Compared<S>, +first: U32, +a: U32, +b: U32, +cc: U32) -> SH.Work<S>:
  match c:
    case Compared{st, items, _, _, +b_less_c}:
      median_high_pick(~S, ~lt, b_less_c, st, items, first, a, b, cc)

def median_branch(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, a_less_b: Bool, st: S, items: Array<U32>, +first: U32, +a: U32, +b: U32, +cc: U32) -> SH.Work<S>:
  match a_less_b:
    case True{}:
      median_high(~S, ~lt, compare_at(~S, ~lt, st, items, b, cc), first, a, b, cc)
    case False{}:
      median_low(~S, ~lt, compare_at(~S, ~lt, st, items, a, cc), first, a, b, cc)

def median_start(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, c: Compared<S>, +first: U32, +a: U32, +b: U32, +cc: U32) -> SH.Work<S>:
  match c:
    case Compared{st, items, _, _, +a_less_b}:
      median_branch(~S, ~lt, a_less_b, st, items, first, a, b, cc)

# __move_median_to_first(result, a, b, c)
def move_median_to_first(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +a: U32, +b: U32, +cc: U32) -> SH.Work<S>:
  median_start(~S, ~lt, compare_at(~S, ~lt, st, items, a, b), first, a, b, cc)

def cut_settle(~S: Type, crossing: Bool, st: S, items: Array<U32>, +lo: U32, +hi: U32, +low_value: U32, +high_value: U32) -> Cut<S>:
  match crossing:
    case True{}:
      items[lo] <- high_value
      items[hi] <- low_value
      Cut{st, items, (lo + 1 : U32), hi, False{}}
    case False{}:
      Cut{st, items, lo, hi, True{}}

def cut_swap(~S: Type, sc: Scan<S>, +lo: U32, +low_value: U32) -> Cut<S>:
  match sc:
    case Scan{st, items, +hi, +high_value, _, _}:
      cut_settle(~S, (lo < hi : U32), st, items, lo, hi, low_value, high_value)

def cut_down(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, sc: Scan<S>, +hi: U32, +pivot: U32, +fuel: Nat) -> Cut<S>:
  match sc:
    case Scan{st, items, +lo, +low_value, _, _}:
      cut_swap(~S, scan(~S, ~lt, st, items, (hi - 1 : U32), pivot, False{}, fuel), lo, low_value)

def cut_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, c: Cut<S>, +pivot: U32, +fuel: Nat) -> Cut<S>:
  match n:
    case 0n:
      c
    case 1n+p:
      match c:
        case Cut{st, items, +lo, +hi, +done}:
          match done:
            case True{}:
              Cut{st, items, lo, hi, True{}}
            case False{}:
              cut_loop(~S, ~lt, p, cut_down(~S, ~lt, scan(~S, ~lt, st, items, lo, pivot, True{}, fuel), hi, pivot, fuel), pivot, fuel)

def cut_pivot(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +first: U32, +last: U32) -> Cut<S>:
  (items, +pivot) = got
  +fuel = U32.to_nat(((last - first : U32) + 2 : U32))
  cut_loop(~S, ~lt, fuel, Cut{st, items, (first + 1 : U32), last, False{}}, pivot, fuel)

def cut_median(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: SH.Work<S>, +first: U32, +last: U32) -> Cut<S>:
  match w:
    case SH.Work{st, items}:
      cut_pivot(~S, ~lt, items[first], st, first, last)

# __unguarded_partition_pivot: median of a[first + 1], a[mid], a[last - 1] to first, then partition [first + 1, last).
def partition_pivot(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> Cut<S>:
  cut_median(~S, ~lt, move_median_to_first(~S, ~lt, st, items, first, (first + 1 : U32), (first + ((last - first : U32) >> 1n) : U32), (last - 1 : U32)), first, last)

def intro_cut(~S: Type, c: Cut<S>, +first: U32, +last: U32, +depth: U32) -> Plan<S>:
  match c:
    case Cut{st, items, +cut, _, _}:
      Plan{SH.Work{st, items}, cut, last, depth, first, cut, depth, False{}}

def intro_heap(~S: Type, w: SH.Work<S>) -> Plan<S>:
  Plan{w, 0, 0, 0, 0, 0, 0, True{}}

def intro_depth(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, exhausted: Bool, st: S, items: Array<U32>, +first: U32, +last: U32, +depth: U32) -> Plan<S>:
  match exhausted:
    case True{}:
      intro_heap(~S, SH.heap_sort(~S, ~lt, st, items, first, last))
    case False{}:
      intro_cut(~S, partition_pivot(~S, ~lt, st, items, first, last), first, last, (depth - 1 : U32))

def intro_size(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, big: Bool, st: S, items: Array<U32>, +first: U32, +last: U32, +depth: U32) -> Plan<S>:
  match big:
    case True{}:
      intro_depth(~S, ~lt, U32.is_zero(depth), st, items, first, last, depth)
    case False{}:
      Plan{SH.Work{st, items}, 0, 0, 0, 0, 0, 0, True{}}

# One pass of __introsort_loop over [first, last): the plan recurses on [cut, last) and continues with [first, cut).
def intro_step(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: SH.Work<S>, +first: U32, +last: U32, +depth: U32) -> Plan<S>:
  match w:
    case SH.Work{st, items}:
      intro_size(~S, ~lt, ((last - first : U32) > 16 : U32), st, items, first, last, depth)

def intro(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, +n: Nat, plan: Plan<S>) -> SH.Work<S>:
  match n:
    case 0n:
      match plan:
        case Plan{w, _, _, _, _, _, _, _}:
          w
    case 1n+p:
      match plan:
        case Plan{w, +rf, +rl, +rd, +nf, +nl, +nd, +done}:
          match done:
            case True{}:
              w
            case False{}:
              intro(~S, ~lt, p, intro_step(~S, ~lt, intro(~S, ~lt, p, intro_step(~S, ~lt, w, rf, rl, rd)), nf, nl, nd))

def sort_final(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: SH.Work<S>, +first: U32, +last: U32) -> SH.Work<S>:
  match w:
    case SH.Work{st, items}:
      final_insertion_sort(~S, ~lt, st, items, first, last)

# libstdc++ std::sort(first, last, lt) (the Linux build).
def sort(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> SH.Work<S>:
  +depth = (floor_log2((last - first : U32)) << 1n : U32)
  sort_final(~S, ~lt, intro(~S, ~lt, U32.to_nat((depth + 4 : U32)), intro_step(~S, ~lt, SH.Work{st, items}, first, last, depth)), first, last)

def ordered(~S: Type, c: Compared<S>, +i: U32, +j: U32) -> SH.Work<S>:
  match c:
    case Compared{st, items, +xj, +yi, +less}:
      items[i] <- Bool.pick(U32, less, xj, yi)
      items[j] <- Bool.pick(U32, less, yi, xj)
      SH.Work{st, items}

# if a[j] < a[i]: swap them (one step of VC9 _Med3).
def order_pair(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: SH.Work<S>, +i: U32, +j: U32) -> SH.Work<S>:
  match w:
    case SH.Work{st, items}:
      ordered(~S, compare_at(~S, ~lt, st, items, j, i), i, j)

# VC9 _Med3(a, b, c): sorts the three so that the median is at b.
def med3(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: SH.Work<S>, +a: U32, +b: U32, +c: U32) -> SH.Work<S>:
  order_pair(~S, ~lt, order_pair(~S, ~lt, order_pair(~S, ~lt, w, a, b), b, c), a, b)

def median_ninther(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, nine: Bool, w: SH.Work<S>, +first: U32, +mid: U32, +last: U32) -> SH.Work<S>:
  match nine:
    case True{}:
      +step = (((last - first : U32) + 1 : U32) >> 3n : U32)
      +two = (step << 1n : U32)
      med3(~S, ~lt, med3(~S, ~lt, med3(~S, ~lt, med3(~S, ~lt, w, first, (first + step : U32), (first + two : U32)), (mid - step : U32), mid, (mid + step : U32)), (last - two : U32), (last - step : U32), last), (first + step : U32), mid, (last - step : U32))
    case False{}:
      med3(~S, ~lt, w, first, mid, last)

# VC9 _Median(first, mid, last) (last inclusive): median of three, or of nine when last - first > 40.
def median(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: SH.Work<S>, +first: U32, +mid: U32, +last: U32) -> SH.Work<S>:
  median_ninther(~S, ~lt, ((last - first : U32) > 40 : U32), w, first, mid, last)

def expand_settle(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, less: Bool, st: S, items: Array<U32>, +x: U32, +pf: U32, +pl: U32, +gf: U32, +gl: U32, +down: Bool) -> Fat<S>:
  match less:
    case True{}:
      Fat{st, items, pf, pl, gf, gl, True{}}
    case False{}:
      Fat{st, items, Bool.pick(U32, down, (pf - 1 : U32), pf), Bool.pick(U32, down, pl, (pl + 1 : U32)), gf, gl, False{}}

def expand_equal(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, c: Compared<S>, +x: U32, +pf: U32, +pl: U32, +gf: U32, +gl: U32, +down: Bool) -> Fat<S>:
  match c:
    case Compared{st, items, _, _, +less}:
      expand_settle(~S, ~lt, less, st, items, x, pf, pl, gf, gl, down)

def expand_second(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, less: Bool, st: S, items: Array<U32>, +x: U32, +pf: U32, +pl: U32, +gf: U32, +gl: U32, +down: Bool) -> Fat<S>:
  match less:
    case True{}:
      Fat{st, items, pf, pl, gf, gl, True{}}
    case False{}:
      expand_equal(~S, ~lt, compare_at(~S, ~lt, st, items, pf, x), x, pf, pl, gf, gl, down)

def expand_first(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, c: Compared<S>, +x: U32, +pf: U32, +pl: U32, +gf: U32, +gl: U32, +down: Bool) -> Fat<S>:
  match c:
    case Compared{st, items, _, _, +less}:
      expand_second(~S, ~lt, less, st, items, x, pf, pl, gf, gl, down)

def expand_step(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, inside: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32, +down: Bool) -> Fat<S>:
  match inside:
    case True{}:
      +x = Bool.pick(U32, down, (pf - 1 : U32), pl)
      expand_first(~S, ~lt, compare_at(~S, ~lt, st, items, x, pf), x, pf, pl, gf, gl, down)
    case False{}:
      Fat{st, items, pf, pl, gf, gl, True{}}

def expand_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, f: Fat<S>, +first: U32, +last: U32, +down: Bool) -> Fat<S>:
  match n:
    case 0n:
      f
    case 1n+p:
      match f:
        case Fat{st, items, +pf, +pl, +gf, +gl, +done}:
          match done:
            case True{}:
              Fat{st, items, pf, pl, gf, gl, False{}}
            case False{}:
              +inside = Bool.pick(Bool, down, (first < pf : U32), (pl < last : U32))
              expand_loop(~S, ~lt, p, expand_step(~S, ~lt, inside, st, items, pf, pl, gf, gl, down), first, last, down)

def upper_settle(~S: Type, less: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match less:
    case True{}:
      Fat{st, items, pf, pl, gf, gl, True{}}
    case False{}:
      Fat{st, swap(items, pl, gf), pf, (pl + 1 : U32), (gf + 1 : U32), gl, False{}}

def upper_equal(~S: Type, c: Compared<S>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match c:
    case Compared{st, items, _, _, +less}:
      upper_settle(~S, less, st, items, pf, pl, gf, gl)

def upper_second(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, less: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match less:
    case True{}:
      Fat{st, items, pf, pl, (gf + 1 : U32), gl, False{}}
    case False{}:
      upper_equal(~S, compare_at(~S, ~lt, st, items, gf, pf), pf, pl, gf, gl)

def upper_first(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, c: Compared<S>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match c:
    case Compared{st, items, _, _, +less}:
      upper_second(~S, ~lt, less, st, items, pf, pl, gf, gl)

def upper_step(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, inside: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match inside:
    case True{}:
      upper_first(~S, ~lt, compare_at(~S, ~lt, st, items, pf, gf), pf, pl, gf, gl)
    case False{}:
      Fat{st, items, pf, pl, gf, gl, True{}}

# for (; gfirst < last; ++gfirst): skip greater, stop on less, gather equal ones after the pivots.
def upper_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, f: Fat<S>, +last: U32) -> Fat<S>:
  match n:
    case 0n:
      f
    case 1n+p:
      match f:
        case Fat{st, items, +pf, +pl, +gf, +gl, +done}:
          match done:
            case True{}:
              Fat{st, items, pf, pl, gf, gl, False{}}
            case False{}:
              upper_loop(~S, ~lt, p, upper_step(~S, ~lt, (gf < last : U32), st, items, pf, pl, gf, gl), last)

def lower_settle(~S: Type, less: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match less:
    case True{}:
      Fat{st, items, pf, pl, gf, gl, True{}}
    case False{}:
      Fat{st, swap(items, (pf - 1 : U32), (gl - 1 : U32)), (pf - 1 : U32), pl, gf, (gl - 1 : U32), False{}}

def lower_equal(~S: Type, c: Compared<S>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match c:
    case Compared{st, items, _, _, +less}:
      lower_settle(~S, less, st, items, pf, pl, gf, gl)

def lower_second(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, less: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match less:
    case True{}:
      Fat{st, items, pf, pl, gf, (gl - 1 : U32), False{}}
    case False{}:
      lower_equal(~S, compare_at(~S, ~lt, st, items, pf, (gl - 1 : U32)), pf, pl, gf, gl)

def lower_first(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, c: Compared<S>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match c:
    case Compared{st, items, _, _, +less}:
      lower_second(~S, ~lt, less, st, items, pf, pl, gf, gl)

def lower_step(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, inside: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match inside:
    case True{}:
      lower_first(~S, ~lt, compare_at(~S, ~lt, st, items, (gl - 1 : U32), pf), pf, pl, gf, gl)
    case False{}:
      Fat{st, items, pf, pl, gf, gl, True{}}

# for (; first < glast; --glast): skip less, stop on greater, gather equal ones before the pivots.
def lower_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, f: Fat<S>, +first: U32) -> Fat<S>:
  match n:
    case 0n:
      f
    case 1n+p:
      match f:
        case Fat{st, items, +pf, +pl, +gf, +gl, +done}:
          match done:
            case True{}:
              Fat{st, items, pf, pl, gf, gl, False{}}
            case False{}:
              lower_loop(~S, ~lt, p, lower_step(~S, ~lt, (first < gl : U32), st, items, pf, pl, gf, gl), first)

def swap_unless(same: Bool, items: Array<U32>, +i: U32, +j: U32) -> Array<U32>:
  match same:
    case True{}:
      items
    case False{}:
      swap(items, i, j)

def rotate_up(items: Array<U32>, +pf: U32, +pl: U32, +gf: U32) -> Array<U32>:
  swap(swap_unless(U32.is_eq(pl, gf), items, pf, pl), pf, gf)

def rotate_down(items: Array<U32>, +pf: U32, +pl: U32, +gl: U32) -> Array<U32>:
  swap(swap(items, (gl - 1 : U32), (pf - 1 : U32)), (pf - 1 : U32), (pl - 1 : U32))

def settle_top(~S: Type, top: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match top:
    case True{}:
      Fat{st, rotate_down(items, pf, pl, gl), (pf - 1 : U32), (pl - 1 : U32), gf, (gl - 1 : U32), False{}}
    case False{}:
      Fat{st, swap(items, gf, (gl - 1 : U32)), pf, pl, (gf + 1 : U32), (gl - 1 : U32), False{}}

def settle_inner(~S: Type, bottom: Bool, top: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match bottom:
    case True{}:
      Fat{st, rotate_up(items, pf, pl, gf), (pf + 1 : U32), (pl + 1 : U32), (gf + 1 : U32), gl, False{}}
    case False{}:
      settle_top(~S, top, st, items, pf, pl, gf, gl)

def settle_finished(~S: Type, finished: Bool, bottom: Bool, top: Bool, st: S, items: Array<U32>, +pf: U32, +pl: U32, +gf: U32, +gl: U32) -> Fat<S>:
  match finished:
    case True{}:
      Fat{st, items, pf, pl, gf, gl, True{}}
    case False{}:
      settle_inner(~S, bottom, top, st, items, pf, pl, gf, gl)

# After both scans: finished, or rotate the pivot run up/down, or swap the two stoppers.
def settle(~S: Type, f: Fat<S>, +first: U32, +last: U32) -> Fat<S>:
  match f:
    case Fat{st, items, +pf, +pl, +gf, +gl, _}:
      +bottom = U32.is_eq(gl, first)
      +top = U32.is_eq(gf, last)
      settle_finished(~S, Bool.and(bottom, top), bottom, top, st, items, pf, pl, gf, gl)

def fat_round(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, f: Fat<S>, +first: U32, +last: U32, +fuel: Nat) -> Fat<S>:
  settle(~S, lower_loop(~S, ~lt, fuel, upper_loop(~S, ~lt, fuel, f, last), first), first, last)

def fat_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, f: Fat<S>, +first: U32, +last: U32, +fuel: Nat) -> Fat<S>:
  match n:
    case 0n:
      f
    case 1n+p:
      match f:
        case Fat{st, items, +pf, +pl, +gf, +gl, +done}:
          match done:
            case True{}:
              Fat{st, items, pf, pl, gf, gl, True{}}
            case False{}:
              fat_loop(~S, ~lt, p, fat_round(~S, ~lt, Fat{st, items, pf, pl, gf, gl, False{}}, first, last, fuel), first, last, fuel)

def fat_start(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, f: Fat<S>, +first: U32, +last: U32, +fuel: Nat) -> Fat<S>:
  match f:
    case Fat{st, items, +pf, +pl, _, _, _}:
      fat_loop(~S, ~lt, fuel, Fat{st, items, pf, pl, pl, pf, False{}}, first, last, fuel)

def fat_median(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: SH.Work<S>, +first: U32, +last: U32, +mid: U32, +fuel: Nat) -> Fat<S>:
  match w:
    case SH.Work{st, items}:
      fat_start(~S, ~lt, expand_loop(~S, ~lt, fuel, expand_loop(~S, ~lt, fuel, Fat{st, items, mid, (mid + 1 : U32), 0, 0, False{}}, first, last, True{}), first, last, False{}), first, last, fuel)

# VC9 _Unguarded_partition(first, last): Fat{.., pf, pl, ..} with [pf, pl) the elements equivalent to the pivot.
def fat_partition(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> Fat<S>:
  +mid = (first + ((last - first : U32) >> 1n) : U32)
  fat_median(~S, ~lt, median(~S, ~lt, SH.Work{st, items}, first, mid, (last - 1 : U32)), first, last, mid, U32.to_nat(((last - first : U32) + 2 : U32)))

def msvc_cut(~S: Type, f: Fat<S>, +first: U32, +last: U32, +ideal: U32) -> Plan<S>:
  match f:
    case Fat{st, items, +pf, +pl, _, _, _}:
      +next = ((ideal >> 1n) + (ideal >> 2n) : U32)
      +low = ((pf - first : U32) < (last - pl : U32) : U32)
      Plan{SH.Work{st, items}, Bool.pick(U32, low, first, pl), Bool.pick(U32, low, pf, last), next, Bool.pick(U32, low, pl, first), Bool.pick(U32, low, last, pf), next, False{}}

def msvc_ideal(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, spent: Bool, st: S, items: Array<U32>, +first: U32, +last: U32, +ideal: U32) -> Plan<S>:
  match spent:
    case True{}:
      intro_heap(~S, SH.heap_sort(~S, ~lt, st, items, first, last))
    case False{}:
      msvc_cut(~S, fat_partition(~S, ~lt, st, items, first, last), first, last, ideal)

def msvc_size(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, big: Bool, st: S, items: Array<U32>, +first: U32, +last: U32, +ideal: U32) -> Plan<S>:
  match big:
    case True{}:
      msvc_ideal(~S, ~lt, U32.is_zero(ideal), st, items, first, last, ideal)
    case False{}:
      intro_heap(~S, insertion_sort(~S, ~lt, st, items, first, last))

# One pass of VC9 _Sort's loop: the plan recurses on the smaller part and continues with the larger one.
def msvc_step(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: SH.Work<S>, +first: U32, +last: U32, +ideal: U32) -> Plan<S>:
  match w:
    case SH.Work{st, items}:
      msvc_size(~S, ~lt, ((last - first : U32) > 32 : U32), st, items, first, last, ideal)

def msvc_drive(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, +n: Nat, plan: Plan<S>) -> SH.Work<S>:
  match n:
    case 0n:
      match plan:
        case Plan{w, _, _, _, _, _, _, _}:
          w
    case 1n+p:
      match plan:
        case Plan{w, +rf, +rl, +rd, +nf, +nl, +nd, +done}:
          match done:
            case True{}:
              w
            case False{}:
              msvc_drive(~S, ~lt, p, msvc_step(~S, ~lt, msvc_drive(~S, ~lt, p, msvc_step(~S, ~lt, w, rf, rl, rd)), nf, nl, nd))

# VC9 std::sort(first, last, lt) (the Windows build).
def msvc_sort(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> SH.Work<S>:
  +count = (last - first : U32)
  msvc_drive(~S, ~lt, U32.to_nat((((floor_log2(count) + 2 : U32) * 3 : U32) + 8 : U32)), msvc_step(~S, ~lt, SH.Work{st, items}, first, last, count))

# VC9 _Sort(first, last, ideal) with an explicit ideal (0 = straight to the heap sort), for tests.
def msvc_sort_ideal(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32, +ideal: U32) -> SH.Work<S>:
  +count = (last - first : U32)
  msvc_drive(~S, ~lt, U32.to_nat((((floor_log2(count) + 2 : U32) * 3 : U32) + 8 : U32)), msvc_step(~S, ~lt, SH.Work{st, items}, first, last, ideal))

def platform_sort(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, windows: Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> SH.Work<S>:
  match windows:
    case True{}:
      msvc_sort(~S, ~lt, st, items, first, last)
    case False{}:
      sort(~S, ~lt, st, items, first, last)

# std::sort of the platform's C++ library: VC9 on Windows, libstdc++ on Linux.
def sort_for(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, +windows: Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> SH.Work<S>:
  platform_sort(~S, ~lt, windows, st, items, first, last)

# libstdc++ std::sort with an explicit depth limit (0 = straight to the heap sort), for tests.
def sort_depth(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32, +depth: U32) -> SH.Work<S>:
  sort_final(~S, ~lt, intro(~S, ~lt, U32.to_nat((depth + 4 : U32)), intro_step(~S, ~lt, SH.Work{st, items}, first, last, depth)), first, last)
