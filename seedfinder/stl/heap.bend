import Base

# libstdc++ heap algorithms (stl_heap.h: __push_heap, __adjust_heap, __pop_heap, make_heap, sort_heap) over items[first,
# last), with the same comparisons in the same order and the same moves. VC9's _Push_heap / _Adjust_heap / _Pop_heap
# make exactly the same comparisons and moves (checked in the Windows exe), so these serve both platforms.
# lt(state, a, b) answers a < b and may thread any state; the heap keeps the largest element at `first`.

type Work<-S: Type> is Type:
  Work{state: S, items: Array<U32>}

type Hole<-S: Type> is Type:
  Hole{state: S, items: Array<U32>, hole: U32, done: Bool}

def rise_settled(~S: Type, up: Bool, st: S, items: Array<U32>, +first: U32, +hole: U32, +parent: U32, +above: U32) -> Hole<S>:
  match up:
    case True{}:
      items[(first + hole : U32)] <- above
      Hole{st, items, parent, False{}}
    case False{}:
      Hole{st, items, hole, True{}}

def rise_compared(~S: Type, got: S & Bool, items: Array<U32>, +first: U32, +hole: U32, +parent: U32, +above: U32) -> Hole<S>:
  (st, +up) = got
  rise_settled(~S, up, st, items, first, hole, parent, above)

def rise_read(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +first: U32, +hole: U32, +parent: U32, +value: U32) -> Hole<S>:
  (items, +above) = got
  rise_compared(~S, lt(st, above, value), items, first, hole, parent, above)

def rise_step(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, go: Bool, st: S, items: Array<U32>, +first: U32, +hole: U32, +value: U32) -> Hole<S>:
  match go:
    case True{}:
      rise_read(~S, ~lt, items[(first + ((hole - 1 : U32) >> 1n) : U32)], st, first, hole, ((hole - 1 : U32) >> 1n : U32), value)
    case False{}:
      Hole{st, items, hole, True{}}

def rise_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, h: Hole<S>, +first: U32, +top: U32, +value: U32) -> Work<S>:
  match n:
    case 0n:
      match h:
        case Hole{st, items, +hole, _}:
          items[(first + hole : U32)] <- value
          Work{st, items}
    case 1n+p:
      match h:
        case Hole{st, items, +hole, +done}:
          match done:
            case True{}:
              items[(first + hole : U32)] <- value
              Work{st, items}
            case False{}:
              rise_loop(~S, ~lt, p, rise_step(~S, ~lt, (hole > top : U32), st, items, first, hole, value), first, top, value)

# __push_heap(first, hole, top, value): move value up from hole while its parent compares less than it.
def push_hole(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +hole: U32, +top: U32, +value: U32) -> Work<S>:
  rise_loop(~S, ~lt, 34n, Hole{st, items, hole, False{}}, first, top, value)

def sink_moved(~S: Type, got: S & Bool, items: Array<U32>, +first: U32, +hole: U32, +child: U32, +right: U32, +left: U32, +limit: U32) -> Hole<S>:
  (st, +take_left) = got
  +next = Bool.pick(U32, take_left, (child - 1 : U32), child)
  items[(first + hole : U32)] <- Bool.pick(U32, take_left, left, right)
  Hole{st, items, next, (next >= limit : U32)}

def sink_left(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +first: U32, +hole: U32, +child: U32, +right: U32, +limit: U32) -> Hole<S>:
  (items, +left) = got
  sink_moved(~S, lt(st, right, left), items, first, hole, child, right, left, limit)

def sink_right(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +first: U32, +hole: U32, +child: U32, +limit: U32) -> Hole<S>:
  (items, +right) = got
  sink_left(~S, ~lt, items[((first + child : U32) - 1 : U32)], st, first, hole, child, right, limit)

def sink_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, h: Hole<S>, +first: U32, +limit: U32) -> Hole<S>:
  match n:
    case 0n:
      h
    case 1n+p:
      match h:
        case Hole{st, items, +hole, +done}:
          match done:
            case True{}:
              Hole{st, items, hole, True{}}
            case False{}:
              +child = ((hole + 1 : U32) << 1n : U32)
              sink_loop(~S, ~lt, p, sink_right(~S, ~lt, items[(first + child : U32)], st, first, hole, child, limit), first, limit)

def last_child(~S: Type, got: Array<U32> & U32, st: S, +first: U32, +hole: U32, +top: U32, +value: U32) -> Hole<S>:
  (items, +left) = got
  items[(first + hole : U32)] <- left
  Hole{st, items, ((hole << 1n) + 1 : U32), False{}}

def after_lone(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, h: Hole<S>, +first: U32, +top: U32, +value: U32) -> Work<S>:
  match h:
    case Hole{st, items, +hole, _}:
      push_hole(~S, ~lt, st, items, first, hole, top, value)

def after_sink(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, lone: Bool, h: Hole<S>, +first: U32, +top: U32, +value: U32) -> Work<S>:
  match lone:
    case True{}:
      match h:
        case Hole{st, items, +hole, _}:
          after_lone(~S, ~lt, last_child(~S, items[(first + ((hole << 1n) + 1 : U32) : U32)], st, first, hole, top, value), first, top, value)
    case False{}:
      match h:
        case Hole{st, items, +hole, _}:
          push_hole(~S, ~lt, st, items, first, hole, top, value)

def lone_check(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, h: Hole<S>, +first: U32, +len: U32, +top: U32, +value: U32) -> Work<S>:
  match h:
    case Hole{st, items, +hole, +done}:
      +lone = Bool.and(U32.is_zero((len .&. 1 : U32)), U32.is_eq(hole, ((len - 2 : U32) >> 1n : U32)))
      after_sink(~S, ~lt, lone, Hole{st, items, hole, done}, first, top, value)

# __adjust_heap(first, hole, len, value): sink the hole to a leaf through the larger children, then push value up.
def adjust(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +hole: U32, +len: U32, +value: U32) -> Work<S>:
  +limit = ((len - 1 : U32) >> 1n : U32)
  lone_check(~S, ~lt, sink_loop(~S, ~lt, 34n, Hole{st, items, hole, (hole >= limit : U32)}, first, limit), first, len, hole, value)

def push_read(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +first: U32, +last: U32) -> Work<S>:
  (items, +value) = got
  push_hole(~S, ~lt, st, items, first, ((last - first : U32) - 1 : U32), 0, value)

# std::push_heap(first, last): items[last - 1] joins the heap [first, last - 1).
def push_heap(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> Work<S>:
  push_read(~S, ~lt, items[(last - 1 : U32)], st, first, last)

def pop_top(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +first: U32, +result: U32, +value: U32) -> Work<S>:
  (items, +top) = got
  items[result] <- top
  adjust(~S, ~lt, st, items, first, 0, (result - first : U32), value)

def pop_value(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +first: U32, +result: U32) -> Work<S>:
  (items, +value) = got
  pop_top(~S, ~lt, items[first], st, first, result, value)

def pop_some(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, more: Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> Work<S>:
  match more:
    case True{}:
      pop_value(~S, ~lt, items[(last - 1 : U32)], st, first, (last - 1 : U32))
    case False{}:
      Work{st, items}

# std::pop_heap(first, last): the largest element moves to last - 1, [first, last - 1) stays a heap.
def pop_heap(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> Work<S>:
  pop_some(~S, ~lt, ((last - first : U32) > 1 : U32), st, items, first, last)

def make_read(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, got: Array<U32> & U32, st: S, +first: U32, +parent: U32, +len: U32) -> Work<S>:
  (items, +value) = got
  adjust(~S, ~lt, st, items, first, parent, len, value)

def make_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, w: Work<S>, +first: U32, +parent: U32, +len: U32) -> Work<S>:
  match n:
    case 0n:
      w
    case 1n+p:
      match w:
        case Work{st, items}:
          make_loop(~S, ~lt, p, make_read(~S, ~lt, items[(first + parent : U32)], st, first, parent, len), first, (parent - 1 : U32), len)

# std::make_heap(first, last): __adjust_heap from parent (len - 2) / 2 down to 0.
def make_heap(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> Work<S>:
  +len = (last - first : U32)
  +parents = Bool.pick(U32, (len >= 2 : U32), (((len - 2 : U32) >> 1n) + 1 : U32), 0)
  make_loop(~S, ~lt, U32.to_nat(parents), Work{st, items}, first, (parents - 1 : U32), len)

def sort_loop(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, n: Nat, w: Work<S>, +first: U32, +last: U32) -> Work<S>:
  match n:
    case 0n:
      w
    case 1n+p:
      match w:
        case Work{st, items}:
          sort_loop(~S, ~lt, p, pop_heap(~S, ~lt, st, items, first, last), first, (last - 1 : U32))

# std::sort_heap(first, last): pop_heap until one element is left.
def sort_heap(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> Work<S>:
  +len = (last - first : U32)
  sort_loop(~S, ~lt, U32.to_nat(Bool.pick(U32, (len >= 2 : U32), (len - 1 : U32), 0)), Work{st, items}, first, last)

def sort_made(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: Work<S>, +first: U32, +last: U32) -> Work<S>:
  match w:
    case Work{st, items}:
      sort_heap(~S, ~lt, st, items, first, last)

# __partial_sort(first, last, last) as introsort's depth fallback and VC9's heap sort use it: make_heap, sort_heap.
def heap_sort(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, st: S, items: Array<U32>, +first: U32, +last: U32) -> Work<S>:
  sort_made(~S, ~lt, make_heap(~S, ~lt, st, items, first, last), first, last)

def fill_list(xs: List<&2, U32>, items: Array<U32>, +i: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      items
    case Con{+x, rest}:
      items[i] <- x
      fill_list(rest, items, (i + 1 : U32))

# An array of 2^depth slots holding xs from slot 0 (for laws and tests).
def from_list(+depth: Nat, xs: List<&2, U32>) -> Array<U32>:
  fill_list(xs, Array.new(U32, depth, 0), 0)

def fingerprint_loop(n: Nat, got: Array<U32> & U32, +i: U32, +h: U32) -> U32:
  match n:
    case 0n:
      h
    case 1n+p:
      (items, +v) = got
      fingerprint_loop(p, items[(i + 1 : U32)], (i + 1 : U32), ((h .^. v) * 16777619 : U32))

# FNV-1a (32-bit, one step per word) over items[first, last).
def fingerprint(items: Array<U32>, +first: U32, +last: U32) -> U32:
  fingerprint_loop(U32.to_nat((last - first : U32)), items[first], first, 2166136261)

def work_fingerprint(w: Work<Unit>, +first: U32, +last: U32) -> U32:
  match w:
    case Work{_, items}:
      fingerprint(items, first, last)

# Orders handles packed as key << 16 | payload by key alone (equal keys are ties).
def key_less(st: Unit, a: U32, b: U32) -> Unit & Bool:
  (st, ((a >> 16n) < (b >> 16n) : U32))

# push_heap / pop_heap on a Work (for chaining in laws).
def push_work(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: Work<S>, +first: U32, +last: U32) -> Work<S>:
  match w:
    case Work{st, items}:
      push_heap(~S, ~lt, st, items, first, last)

def pop_work(~S: Type, ~lt: S -> U32 -> U32 -> S & Bool, w: Work<S>, +first: U32, +last: U32) -> Work<S>:
  match w:
    case Work{st, items}:
      pop_heap(~S, ~lt, st, items, first, last)
