import Base
import ./walk.bend as Walk
import ./world.bend as FilterWorld

# Multi-source Dijkstra over land tiles with exact walk lengths (metric.py WalkMetric.settle and single_source):
# 8 neighbours (diagonals cut corners), wormhole jumps, and per tile the first `needed` (1 or 2)
# labels with distinct seeds. Candidates pop in the order (exact length, tile, seed), as Python's heap orders
# (approx, WalkLength, tile, seed); a tile keeps at most two tentative candidates with distinct seeds (the others can
# never become labels), so every settled label equals Python's. The first label of a tile also keeps its
# predecessor tile and jump, for the wormhole hops of one shortest path.
#
# cells: 16 words per tile: flags (bit 0 land, bit 1 jump source, bit 2 target, bits 8..15 the valid moves), settled,
#   tentative count, T1 (q2 q1 q0 b seed), T2 (q2 q1 q0 b seed), predecessor tile, predecessor jump + 1.
# heap slots: 4 words (key hi, key lo, pool index); pool: 8 words per candidate (q2 q1 q0 b tile seed).

# A wormhole jump from one anchor tile to another, paying both anchors' offsets.
type Jump is Data:
  Jump{from: U32, to: U32, offset: Walk.Length}

# A source: its anchor tile, the length already paid there (cost plus offset), and its seed position.
type Start is Data:
  Start{tile: U32, length: Walk.Length, seed: U32}

type Cand is Data:
  Cand{length: Walk.Length, tile: U32, seed: U32}

def none() -> U32:
  4294967295

def at(+tile: U32, +field: U32) -> U32:
  (tile * 16 + field : U32)

def push_read(got: Array<U32> & U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  (a, v) = got
  (a, v <> acc)

def read_list(n: Nat, got: Array<U32> & List<&2, U32>, +i: U32) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      (a, acc) = got
      (a, List.reverse(&2, U32, acc))
    case 1n+k:
      (a, acc) = got
      read_list(k, push_read(a[i], acc), (i + 1 : U32))

# n consecutive words from i.
def read_words(a: Array<U32>, +i: U32, n: Nat) -> Array<U32> & List<&2, U32>:
  read_list(n, (a, Nil{}), i)

def write_list(words: List<&2, U32>, a: Array<U32>, +i: U32) -> Array<U32>:
  match words:
    case Nil{}:
      a
    case Con{+w, rest}:
      write_list(rest, a[i] <- w, (i + 1 : U32))

# The words written from i on.
def write_words(a: Array<U32>, +i: U32, words: List<&2, U32>) -> Array<U32>:
  write_list(words, a, i)

def cand_seed(+c: Cand) -> U32:
  match c:
    case Cand{_, _, +seed}:
      seed

def cand_tile(+c: Cand) -> U32:
  match c:
    case Cand{_, +tile, _}:
      tile

def cand_length(+c: Cand) -> Walk.Length:
  match c:
    case Cand{+l, _, _}:
      l

def label_5(got: Array<U32> & U32, +tile: U32, +q2: U32, +q1: U32, +q0: U32, +b: U32) -> Array<U32> & Cand:
  (a, +seed) = got
  (a, Cand{Walk.Length{q2, q1, q0, b}, tile, seed})

def label_4(got: Array<U32> & U32, +base: U32, +tile: U32, +q2: U32, +q1: U32, +q0: U32) -> Array<U32> & Cand:
  (a, +b) = got
  label_5(a[(base + 4 : U32)], tile, q2, q1, q0, b)

def label_3(got: Array<U32> & U32, +base: U32, +tile: U32, +q2: U32, +q1: U32) -> Array<U32> & Cand:
  (a, +q0) = got
  label_4(a[(base + 3 : U32)], base, tile, q2, q1, q0)

def label_2(got: Array<U32> & U32, +base: U32, +tile: U32, +q2: U32) -> Array<U32> & Cand:
  (a, +q1) = got
  label_3(a[(base + 2 : U32)], base, tile, q2, q1)

def label_1(got: Array<U32> & U32, +base: U32, +tile: U32) -> Array<U32> & Cand:
  (a, +q2) = got
  label_2(a[(base + 1 : U32)], base, tile, q2)

# The candidate stored as q2 q1 q0 b seed at base, of the given tile.
def read_label(a: Array<U32>, +base: U32, +tile: U32) -> Array<U32> & Cand:
  label_1(a[base], base, tile)

# Stores a candidate's length and seed as q2 q1 q0 b seed at base.
def write_label(a: Array<U32>, +base: U32, +c: Cand) -> Array<U32>:
  match c:
    case Cand{Walk.Length{+q2, +q1, +q0, +b}, _, +seed}:
      a[base] <- q2
      a[(base + 1 : U32)] <- q1
      a[(base + 2 : U32)] <- q0
      a[(base + 3 : U32)] <- b
      a[(base + 4 : U32)] <- seed

def pool_6(got: Array<U32> & U32, +tile: U32, +q2: U32, +q1: U32, +q0: U32, +b: U32) -> Array<U32> & Cand:
  (a, +seed) = got
  (a, Cand{Walk.Length{q2, q1, q0, b}, tile, seed})

def pool_5(got: Array<U32> & U32, +base: U32, +q2: U32, +q1: U32, +q0: U32, +b: U32) -> Array<U32> & Cand:
  (a, +tile) = got
  pool_6(a[(base + 5 : U32)], tile, q2, q1, q0, b)

def pool_4(got: Array<U32> & U32, +base: U32, +q2: U32, +q1: U32, +q0: U32) -> Array<U32> & Cand:
  (a, +b) = got
  pool_5(a[(base + 4 : U32)], base, q2, q1, q0, b)

def pool_3(got: Array<U32> & U32, +base: U32, +q2: U32, +q1: U32) -> Array<U32> & Cand:
  (a, +q0) = got
  pool_4(a[(base + 3 : U32)], base, q2, q1, q0)

def pool_2(got: Array<U32> & U32, +base: U32, +q2: U32) -> Array<U32> & Cand:
  (a, +q1) = got
  pool_3(a[(base + 2 : U32)], base, q2, q1)

def pool_1(got: Array<U32> & U32, +base: U32) -> Array<U32> & Cand:
  (a, +q2) = got
  pool_2(a[(base + 1 : U32)], base, q2)

def pool_cand(pool: Array<U32>, +index: U32) -> Array<U32> & Cand:
  pool_1(pool[(index * 8 : U32)], (index * 8 : U32))

def write_pool(pool: Array<U32>, +index: U32, +c: Cand) -> Array<U32>:
  match c:
    case Cand{Walk.Length{+q2, +q1, +q0, +b}, +tile, +seed}:
      +base = (index * 8 : U32)
      pool[base] <- q2
      pool[(base + 1 : U32)] <- q1
      pool[(base + 2 : U32)] <- q0
      pool[(base + 3 : U32)] <- b
      pool[(base + 4 : U32)] <- tile
      pool[(base + 5 : U32)] <- seed

# (length, seed) order of two candidates of one tile: 0 less, 1 equal, 2 greater.
def label_order(+a: Cand, +b: Cand) -> U32:
  match a b:
    case Cand{+la, _, +sa} Cand{+lb, _, +sb}:
      +order = Walk.compare(la, lb)
      Bool.pick(U32, U32.is_eq(order, 1), Bool.pick(U32, (sa < sb : U32), 0, Bool.pick(U32, (sa > sb : U32), 2, 1)), order)

# The heap order of two candidates: (length, tile, seed), with their keys.
def cand_less(+a: Cand, +b: Cand, +ka: Walk.Approx, +kb: Walk.Approx) -> Bool:
  match a b:
    case Cand{+la, +ta, +sa} Cand{+lb, +tb, +sb}:
      +order = Walk.compare_keyed(la, lb, ka, kb)
      U32.is_zero(order) || (U32.is_eq(order, 1) && ((ta < tb : U32) || (U32.is_eq(ta, tb) && (sa < sb : U32))))

def finish_compare(got: Array<U32> & Cand, +a: Cand, +ka: Walk.Approx, +kb: Walk.Approx) -> Array<U32> & Bool:
  (pool, +b) = got
  (pool, cand_less(a, b, ka, kb))

def compare_read(got: Array<U32> & Cand, +index_b: U32, +ka: Walk.Approx, +kb: Walk.Approx) -> Array<U32> & Bool:
  (pool, +a) = got
  finish_compare(pool_cand(pool, index_b), a, ka, kb)

def resolved(+decided: U32, pool: Array<U32>, +index_a: U32, +index_b: U32, +ka: Walk.Approx, +kb: Walk.Approx) -> Array<U32> & Bool:
  match decided:
    case 0:
      (pool, True{})
    case 2:
      (pool, False{})
    case _:
      compare_read(pool_cand(pool, index_a), index_b, ka, kb)

# Whether the candidate at pool index a (key ka) pops before the one at b (key kb).
def pooled_less(pool: Array<U32>, +index_a: U32, +ka: Walk.Approx, +index_b: U32, +kb: Walk.Approx) -> Array<U32> & Bool:
  resolved(Walk.keys_decide(ka, kb), pool, index_a, index_b, ka, kb)

type Slot is Data:
  Slot{kh: U32, kl: U32, idx: U32}

def slot_3(got: Array<U32> & U32, +kh: U32, +kl: U32) -> Array<U32> & Slot:
  (a, +idx) = got
  (a, Slot{kh, kl, idx})

def slot_2(got: Array<U32> & U32, +base: U32, +kh: U32) -> Array<U32> & Slot:
  (a, +kl) = got
  slot_3(a[(base + 2 : U32)], kh, kl)

def slot_1(got: Array<U32> & U32, +base: U32) -> Array<U32> & Slot:
  (a, +kh) = got
  slot_2(a[(base + 1 : U32)], base, kh)

def read_slot(slots: Array<U32>, +i: U32) -> Array<U32> & Slot:
  slot_1(slots[(i * 4 : U32)], (i * 4 : U32))

def write_slot(slots: Array<U32>, +i: U32, +s: Slot) -> Array<U32>:
  match s:
    case Slot{+kh, +kl, +idx}:
      +base = (i * 4 : U32)
      slots[base] <- kh
      slots[(base + 1 : U32)] <- kl
      slots[(base + 2 : U32)] <- idx

# The heap slots and the candidate pool, with room for `capacity` = 2^depth candidates.
type Heap is Type:
  Heap{slots: Array<U32>, pool: Array<U32>, size: U32, used: U32, depth: Nat, capacity: U32}

type Up is Type:
  Up{slots: Array<U32>, pool: Array<U32>, hole: U32, go: Bool}

def up_move(less: Bool, slots: Array<U32>, pool: Array<U32>, +hole: U32, +parent: U32, +p: Slot) -> Up:
  match less:
    case True{}:
      Up{write_slot(slots, hole, p), pool, parent, True{}}
    case False{}:
      Up{slots, pool, hole, False{}}

def up_decide(got: Array<U32> & Bool, slots: Array<U32>, +hole: U32, +parent: U32, +p: Slot) -> Up:
  (pool, +less) = got
  up_move(less, slots, pool, hole, parent, p)

def up_compare(+p: Slot, +e: Slot, slots: Array<U32>, pool: Array<U32>, +hole: U32, +parent: U32) -> Up:
  match p e:
    case Slot{+pkh, +pkl, +pidx} Slot{+kh, +kl, +idx}:
      up_decide(pooled_less(pool, idx, Walk.Approx{kh, kl}, pidx, Walk.Approx{pkh, pkl}), slots, hole, parent, p)

def up_parent(got: Array<U32> & Slot, pool: Array<U32>, +hole: U32, +parent: U32, +e: Slot) -> Up:
  (slots, +p) = got
  up_compare(p, e, slots, pool, hole, parent)

def up_step(at_root: Bool, slots: Array<U32>, pool: Array<U32>, +hole: U32, +e: Slot) -> Up:
  match at_root:
    case True{}:
      Up{slots, pool, hole, False{}}
    case False{}:
      up_parent(read_slot(slots, ((hole - 1) / 2 : U32)), pool, hole, ((hole - 1) / 2 : U32), e)

def sift_up(n: Nat, u: Up, +e: Slot) -> Array<U32> & Array<U32>:
  match n u:
    case 1n+k Up{slots, pool, +hole, True{}}:
      sift_up(k, up_step(U32.is_zero(hole), slots, pool, hole, e), e)
    case _ Up{slots, pool, +hole, _}:
      (write_slot(slots, hole, e), pool)

type Down is Type:
  Down{slots: Array<U32>, pool: Array<U32>, hole: U32, go: Bool}

def down_move(less: Bool, slots: Array<U32>, pool: Array<U32>, +hole: U32, +child: U32, +c: Slot) -> Down:
  match less:
    case True{}:
      Down{write_slot(slots, hole, c), pool, child, True{}}
    case False{}:
      Down{slots, pool, hole, False{}}

def down_decide(got: Array<U32> & Bool, slots: Array<U32>, +hole: U32, +child: U32, +c: Slot) -> Down:
  (pool, +less) = got
  down_move(less, slots, pool, hole, child, c)

def down_child(+c: Slot, +child: U32, pool: Array<U32>, slots: Array<U32>, +hole: U32, +e: Slot) -> Down:
  match c e:
    case Slot{+ckh, +ckl, +cidx} Slot{+kh, +kl, +idx}:
      down_decide(pooled_less(pool, cidx, Walk.Approx{ckh, ckl}, idx, Walk.Approx{kh, kl}), slots, hole, child, c)

def pick_child(got: Array<U32> & Bool, slots: Array<U32>, +hole: U32, +c1: U32, +a: Slot, +b: Slot, +e: Slot) -> Down:
  (pool, +second) = got
  down_child(Bool.pick(Slot, second, b, a), Bool.pick(U32, second, (c1 + 1 : U32), c1), pool, slots, hole, e)

def compare_children(+a: Slot, +b: Slot, slots: Array<U32>, pool: Array<U32>, +hole: U32, +c1: U32, +e: Slot) -> Down:
  match a b:
    case Slot{+kh1, +kl1, +i1} Slot{+kh2, +kl2, +i2}:
      pick_child(pooled_less(pool, i2, Walk.Approx{kh2, kl2}, i1, Walk.Approx{kh1, kl1}), slots, hole, c1, a, b, e)

def second_child(got: Array<U32> & Slot, pool: Array<U32>, +hole: U32, +c1: U32, +a: Slot, +e: Slot) -> Down:
  (slots, +b) = got
  compare_children(a, b, slots, pool, hole, c1, e)

def one_or_two(both: Bool, slots: Array<U32>, pool: Array<U32>, +hole: U32, +c1: U32, +a: Slot, +e: Slot) -> Down:
  match both:
    case True{}:
      second_child(read_slot(slots, (c1 + 1 : U32)), pool, hole, c1, a, e)
    case False{}:
      down_child(a, c1, pool, slots, hole, e)

def first_child(got: Array<U32> & Slot, pool: Array<U32>, +hole: U32, +c1: U32, +both: Bool, +e: Slot) -> Down:
  (slots, +a) = got
  one_or_two(both, slots, pool, hole, c1, a, e)

def down_step(+children: U32, slots: Array<U32>, pool: Array<U32>, +hole: U32, +e: Slot) -> Down:
  match children:
    case 0:
      Down{slots, pool, hole, False{}}
    case _:
      first_child(read_slot(slots, (hole * 2 + 1 : U32)), pool, hole, (hole * 2 + 1 : U32), U32.is_eq(children, 2), e)

def children_of(+hole: U32, +size: U32) -> U32:
  +c1 = (hole * 2 + 1 : U32)
  Bool.pick(U32, (c1 >= size : U32), 0, Bool.pick(U32, ((c1 + 1) >= size : U32), 1, 2))

def sift_down(n: Nat, d: Down, +size: U32, +e: Slot) -> Array<U32> & Array<U32>:
  match n d:
    case 1n+k Down{slots, pool, +hole, True{}}:
      sift_down(k, down_step(children_of(hole, size), slots, pool, hole, e), size, e)
    case _ Down{slots, pool, +hole, _}:
      (write_slot(slots, hole, e), pool)

def copy_step(got: Array<U32> & U32, dst: Array<U32>, +i: U32) -> Array<U32> & Array<U32>:
  (src, +v) = got
  (src, dst[i] <- v)

def copy_loop(n: Nat, pair: Array<U32> & Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      (src, dst) = pair
      dst
    case 1n+k:
      (src, dst) = pair
      copy_loop(k, copy_step(src[i], dst, i), (i + 1 : U32))

# A copy of the first n words of src in a new array of 2^depth words.
def grown(src: Array<U32>, n: Nat, +depth: Nat) -> Array<U32>:
  copy_loop(n, (src, [0 : U32^depth]), 0)

def room_for(full: Bool, h: Heap) -> Heap:
  match full h:
    case True{} Heap{slots, pool, +size, +used, +depth, +capacity}:
      Heap{grown(slots, Nat.mul(U32.to_nat(capacity), 4n), Nat.add(depth, 3n)), grown(pool, Nat.mul(U32.to_nat(capacity), 8n), Nat.add(depth, 4n)),
        size, used, Nat.add(depth, 1n), (capacity * 2 : U32)}
    case False{} other:
      other

def heap_of(got: Array<U32> & Array<U32>, +size: U32, +used: U32, +depth: Nat, +capacity: U32) -> Heap:
  (slots, pool) = got
  Heap{slots, pool, size, used, depth, capacity}

def pushed_keyed(h: Heap, +c: Cand, +key: Walk.Approx) -> Heap:
  match h key:
    case Heap{slots, pool, +size, +used, +depth, +capacity} Walk.Approx{+kh, +kl}:
      heap_of(sift_up(64n, Up{slots, write_pool(pool, used, c), size, True{}}, Slot{kh, kl, used}), (size + 1 : U32), (used + 1 : U32), depth, capacity)

def push(h: Heap, +c: Cand) -> Heap:
  match h:
    case Heap{slots, pool, +size, +used, +depth, +capacity}:
      pushed_keyed(room_for((used >= capacity : U32), Heap{slots, pool, size, used, depth, capacity}), c, Walk.key(cand_length(c)))

def empty_heap() -> Heap:
  Heap{[0 : U32^14n], [0 : U32^15n], 0, 0, 12n, 4096}

type Popped is Type:
  Popped{heap: Heap, cand: Cand, found: Bool}

def popped_cand(got: Array<U32> & Cand, slots: Array<U32>, +size: U32, +used: U32, +depth: Nat, +capacity: U32) -> Popped:
  (pool, +c) = got
  Popped{Heap{slots, pool, size, used, depth, capacity}, c, True{}}

def resettled(got: Array<U32> & Array<U32>, +top: U32, +size: U32, +used: U32, +depth: Nat, +capacity: U32) -> Popped:
  (slots, pool) = got
  popped_cand(pool_cand(pool, top), slots, size, used, depth, capacity)

def pop_last(got: Array<U32> & Slot, pool: Array<U32>, +top: U32, +size: U32, +used: U32, +depth: Nat, +capacity: U32) -> Popped:
  (slots, +last) = got
  resettled(sift_down(64n, Down{slots, pool, 0, Bool.not(U32.is_zero(size))}, size, last), top, size, used, depth, capacity)

def pop_top(got: Array<U32> & Slot, pool: Array<U32>, +size: U32, +used: U32, +depth: Nat, +capacity: U32) -> Popped:
  (slots, +root) = got
  match root:
    case Slot{_, _, +top}:
      pop_last(read_slot(slots, (size - 1 : U32)), pool, top, (size - 1 : U32), used, depth, capacity)

def pop_sized(empty: Bool, slots: Array<U32>, pool: Array<U32>, +size: U32, +used: U32, +depth: Nat, +capacity: U32) -> Popped:
  match empty:
    case True{}:
      Popped{Heap{slots, pool, size, used, depth, capacity}, Cand{Walk.zero(), 0, 0}, False{}}
    case False{}:
      pop_top(read_slot(slots, 0), pool, size, used, depth, capacity)

# The first candidate in heap order (found is False when the heap is empty).
def pop(h: Heap) -> Popped:
  match h:
    case Heap{slots, pool, +size, +used, +depth, +capacity}:
      pop_sized(U32.is_zero(size), slots, pool, size, used, depth, capacity)

type Grid is Type:
  Grid{cells: Array<U32>, heap: Heap}

def with_prev(cells: Array<U32>, +tile: U32, +prev: U32, +hop: U32) -> Array<U32>:
  cells[at(tile, 13)] <- prev
  cells[at(tile, 14)] <- hop

def take_first(cells: Array<U32>, heap: Heap, +c: Cand, +prev: U32, +hop: U32) -> Grid:
  Grid{with_prev(write_label(cells, at(cand_tile(c), 3), c), cand_tile(c), prev, hop), push(heap, c)}

def take_second(cells: Array<U32>, heap: Heap, +c: Cand) -> Grid:
  Grid{write_label(cells[at(cand_tile(c), 2)] <- 2, at(cand_tile(c), 8), c), push(heap, c)}

def second_better(better: Bool, cells: Array<U32>, heap: Heap, +c: Cand) -> Grid:
  match better:
    case True{}:
      take_second(cells, heap, c)
    case False{}:
      Grid{cells, heap}

def second_compare(got: Array<U32> & Cand, heap: Heap, +c: Cand) -> Grid:
  (cells, +t2) = got
  second_better(U32.is_zero(label_order(c, t2)), cells, heap, c)

def second_with(fresh: Bool, cells: Array<U32>, heap: Heap, +c: Cand) -> Grid:
  match fresh:
    case True{}:
      take_second(cells, heap, c)
    case False{}:
      second_compare(read_label(cells, at(cand_tile(c), 8), cand_tile(c)), heap, c)

def worse_first(skip: Bool, cells: Array<U32>, heap: Heap, +c: Cand, +n: U32) -> Grid:
  match skip:
    case True{}:
      Grid{cells, heap}
    case False{}:
      second_with(U32.is_eq(n, 1), cells, heap, c)

def first_replace(same: Bool, cells: Array<U32>, heap: Heap, +c: Cand, +t1: Cand, +prev: U32, +hop: U32) -> Grid:
  match same:
    case True{}:
      take_first(cells, heap, c, prev, hop)
    case False{}:
      take_first(write_label(cells[at(cand_tile(c), 2)] <- 2, at(cand_tile(c), 8), t1), heap, c, prev, hop)

def first_order(better: Bool, +same: Bool, cells: Array<U32>, heap: Heap, +c: Cand, +t1: Cand, +n: U32, +needed: U32, +prev: U32, +hop: U32) -> Grid:
  match better:
    case True{}:
      first_replace(same, cells, heap, c, t1, prev, hop)
    case False{}:
      worse_first(same || U32.is_eq(needed, 1), cells, heap, c, n)

def first_compare(got: Array<U32> & Cand, heap: Heap, +c: Cand, +n: U32, +needed: U32, +prev: U32, +hop: U32) -> Grid:
  (cells, +t1) = got
  first_order(U32.is_zero(label_order(c, t1)), U32.is_eq(cand_seed(c), cand_seed(t1)), cells, heap, c, t1, n, needed, prev, hop)

def first_with(empty: Bool, cells: Array<U32>, heap: Heap, +c: Cand, +n: U32, +needed: U32, +prev: U32, +hop: U32) -> Grid:
  match empty:
    case True{}:
      take_first(cells[at(cand_tile(c), 2)] <- 1, heap, c, prev, hop)
    case False{}:
      first_compare(read_label(cells, at(cand_tile(c), 3), cand_tile(c)), heap, c, n, needed, prev, hop)

def first_count(got: Array<U32> & U32, heap: Heap, +c: Cand, +needed: U32, +prev: U32, +hop: U32) -> Grid:
  (cells, +n) = got
  first_with(U32.is_zero(n), cells, heap, c, n, needed, prev, hop)

def second_count(got: Array<U32> & U32, heap: Heap, +c: Cand) -> Grid:
  (cells, +n) = got
  second_with(U32.is_eq(n, 1), cells, heap, c)

def second_open(same: Bool, cells: Array<U32>, heap: Heap, +c: Cand) -> Grid:
  match same:
    case True{}:
      Grid{cells, heap}
    case False{}:
      second_count(cells[at(cand_tile(c), 2)], heap, c)

def second_gate(got: Array<U32> & U32, heap: Heap, +c: Cand) -> Grid:
  (cells, +first_seed) = got
  second_open(U32.is_eq(first_seed, cand_seed(c)), cells, heap, c)

def offer_stage(+stage: U32, cells: Array<U32>, heap: Heap, +c: Cand, +needed: U32, +prev: U32, +hop: U32) -> Grid:
  match stage:
    case 0:
      Grid{cells, heap}
    case 1:
      second_gate(cells[at(cand_tile(c), 7)], heap, c)
    case _:
      first_count(cells[at(cand_tile(c), 2)], heap, c, needed, prev, hop)

# 0: the tile is full; 1: it has its first label (a second is wanted); 2: it has none yet.
def stage_of(+settled: U32, +needed: U32) -> U32:
  Bool.pick(U32, (settled >= needed : U32), 0, Bool.pick(U32, U32.is_eq(settled, 1), 1, 2))

def offer_settled(got: Array<U32> & U32, heap: Heap, +c: Cand, +needed: U32, +prev: U32, +hop: U32) -> Grid:
  (cells, +settled) = got
  offer_stage(stage_of(settled, needed), cells, heap, c, needed, prev, hop)

# Offers a candidate to its tile, reached from tile `prev` (by jump `hop` - 1 when hop > 0): it becomes a tentative
# label and is pushed only when it can still become one of the tile's labels.
def offer(g: Grid, +c: Cand, +needed: U32, +prev: U32, +hop: U32) -> Grid:
  match g:
    case Grid{cells, heap}:
      offer_settled(cells[at(cand_tile(c), 1)], heap, c, needed, prev, hop)

# The fixed data of one search: map width, labels needed per tile, the jumps, the bound.
type Ctx is Data:
  Ctx{width: U32, needed: U32, jumps: List<&2, Jump>, bound: Maybe<&2, Walk.Length>}

def ctx_needed(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{_, +needed, _, _}:
      needed

def ctx_bound(+ctx: Ctx) -> Maybe<&2, Walk.Length>:
  match ctx:
    case Ctx{_, _, _, +bound}:
      bound

def move_delta(+k: U32, +w: U32) -> U32:
  match k:
    case 0:
      1
    case 1:
      4294967295
    case 2:
      w
    case 3:
      (0 - w : U32)
    case 4:
      (w + 1 : U32)
    case 5:
      (1 - w : U32)
    case 6:
      (w - 1 : U32)
    case _:
      (0 - w - 1 : U32)

def moved(valid: Bool, g: Grid, +ctx: Ctx, +c: Cand, +k: U32) -> Grid:
  match valid ctx c:
    case True{} Ctx{+w, +needed, _, _} Cand{+l, +tile, +seed}:
      offer(g, Cand{Walk.stepped(l, Bool.to_u32((k < 4 : U32)), Bool.to_u32((k >= 4 : U32))), (tile + move_delta(k, w) : U32), seed}, needed, tile, 0)
    case _ _ _:
      g

def moves(n: Nat, g: Grid, +c: Cand, +flags: U32, +ctx: Ctx, +k: U32) -> Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      moves(p, moved(Bool.not(U32.is_zero(((flags >> U32.to_nat((k + 8 : U32))) .&. 1 : U32))), g, ctx, c, k), c, flags, ctx, (k + 1 : U32))

def jumped(valid: Bool, g: Grid, +c: Cand, +to: U32, +offset: Walk.Length, +needed: U32, +j: U32) -> Grid:
  match valid c:
    case True{} Cand{+l, +tile, +seed}:
      offer(g, Cand{Walk.plus(l, offset), to, seed}, needed, tile, (j + 1 : U32))
    case False{} _:
      g

def jumps_from(jumps: List<&2, Jump>, g: Grid, +c: Cand, +needed: U32, +j: U32) -> Grid:
  match jumps:
    case Nil{}:
      g
    case Con{Jump{+from, +to, +offset}, rest}:
      jumps_from(rest, jumped(U32.is_eq(from, cand_tile(c)), g, c, to, offset, needed, j), c, needed, (j + 1 : U32))

def jumps_gate(has_jumps: Bool, g: Grid, +c: Cand, +ctx: Ctx) -> Grid:
  match has_jumps ctx:
    case True{} Ctx{_, +needed, +jumps, _}:
      jumps_from(jumps, g, c, needed, 0)
    case False{} _:
      g

def expand(g: Grid, +c: Cand, +flags: U32, +ctx: Ctx) -> Grid:
  jumps_gate(U32.is_eq((flags .&. 2 : U32), 2), moves(8n, g, c, flags, ctx, 0), c, ctx)

type Search is Type:
  Search{cells: Array<U32>, heap: Heap, waiting: U32, live: Bool}

def expanded(g: Grid, +waiting: U32) -> Search:
  match g:
    case Grid{cells, heap}:
      Search{cells, heap, waiting, Bool.not(U32.is_zero(waiting))}

def settle_open(open: Bool, cells: Array<U32>, heap: Heap, +c: Cand, +flags: U32, +settled: U32, +waiting: U32, +ctx: Ctx) -> Search:
  match open:
    case False{}:
      Search{cells, heap, waiting, True{}}
    case True{}:
      +now = (settled + 1 : U32)
      +finished = U32.is_eq((flags .&. 4 : U32), 4) && U32.is_eq(now, ctx_needed(ctx))
      expanded(expand(Grid{cells[at(cand_tile(c), 1)] <- now, heap}, c, flags, ctx), (waiting - Bool.to_u32(finished) : U32))

def settle_seed(got: Array<U32> & U32, heap: Heap, +c: Cand, +flags: U32, +settled: U32, +waiting: U32, +ctx: Ctx) -> Search:
  (cells, +first_seed) = got
  settle_open(Bool.not(U32.is_eq(first_seed, cand_seed(c))), cells, heap, c, flags, settled, waiting, ctx)

def settle_stage(+stage: U32, cells: Array<U32>, heap: Heap, +c: Cand, +flags: U32, +settled: U32, +waiting: U32, +ctx: Ctx) -> Search:
  match stage:
    case 0:
      Search{cells, heap, waiting, True{}}
    case 1:
      settle_seed(cells[at(cand_tile(c), 7)], heap, c, flags, settled, waiting, ctx)
    case _:
      settle_open(True{}, cells, heap, c, flags, settled, waiting, ctx)

def settle_count(got: Array<U32> & U32, heap: Heap, +c: Cand, +flags: U32, +waiting: U32, +ctx: Ctx) -> Search:
  (cells, +settled) = got
  settle_stage(stage_of(settled, ctx_needed(ctx)), cells, heap, c, flags, settled, waiting, ctx)

def settle_flags(got: Array<U32> & U32, heap: Heap, +c: Cand, +waiting: U32, +ctx: Ctx) -> Search:
  (cells, +flags) = got
  settle_count(cells[at(cand_tile(c), 1)], heap, c, flags, waiting, ctx)

def beyond(+l: Walk.Length, bound: Maybe<&2, Walk.Length>) -> Bool:
  match bound:
    case None{}:
      False{}
    case Some{+b}:
      U32.is_eq(Walk.compare(l, b), 2)

def settle_within(past: Bool, cells: Array<U32>, heap: Heap, +c: Cand, +waiting: U32, +ctx: Ctx) -> Search:
  match past:
    case True{}:
      Search{cells, heap, waiting, False{}}
    case False{}:
      settle_flags(cells[at(cand_tile(c), 0)], heap, c, waiting, ctx)

def settle_popped(p: Popped, cells: Array<U32>, +waiting: U32, +ctx: Ctx) -> Search:
  match p:
    case Popped{heap, +c, True{}}:
      settle_within(beyond(cand_length(c), ctx_bound(ctx)), cells, heap, c, waiting, ctx)
    case Popped{heap, _, False{}}:
      Search{cells, heap, waiting, False{}}

def settle_loop(n: Nat, s: Search, +ctx: Ctx) -> Search:
  match n s:
    case 1n+k Search{cells, heap, +waiting, True{}}:
      settle_loop(k, settle_popped(pop(heap), cells, waiting, ctx), ctx)
    case _ other:
      other

def land_word(+tile: U32) -> U32:
  Bool.to_u32(FilterWorld.is_land_tile(tile))

def land_pair(cells: Array<U32>, +i: U32, +word: U32) -> Array<U32>:
  cells[at(i, 0)] <- land_word((word .&. 65535 : U32))
  cells[at((i + 1 : U32), 0)] <- land_word((word >> 16n : U32))

def land_cells(words: List<&2, U32>, cells: Array<U32>, +i: U32) -> Array<U32>:
  match words:
    case Nil{}:
      cells
    case Con{+word, rest}:
      land_cells(rest, land_pair(cells, i, word), (i + 2 : U32))

def offset_x(+k: U32) -> U32:
  match k:
    case 0:
      1
    case 1:
      4294967295
    case 4:
      1
    case 5:
      1
    case 6:
      4294967295
    case 7:
      4294967295
    case _:
      0

def offset_y(+k: U32) -> U32:
  match k:
    case 2:
      1
    case 3:
      4294967295
    case 4:
      1
    case 5:
      4294967295
    case 6:
      1
    case 7:
      4294967295
    case _:
      0

def neighbour_bit(got: Array<U32> & U32, +valid: Bool, +bits: U32, +k: U32) -> Array<U32> & U32:
  (cells, +flags) = got
  (cells, (bits .|. (Bool.to_u32(valid && U32.is_eq((flags .&. 1 : U32), 1)) << U32.to_nat(k)) : U32))

def neighbour_bits(n: Nat, got: Array<U32> & U32, +i: U32, +x: U32, +y: U32, +w: U32, +h: U32, +k: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, +bits) = got
      +nx = (x + offset_x(k) : U32)
      +ny = (y + offset_y(k) : U32)
      +valid = (nx < w : U32) && (ny < h : U32)
      neighbour_bits(p, neighbour_bit(cells[at(Bool.pick(U32, valid, (ny * w + nx : U32), i), 0)], valid, bits, k), i, x, y, w, h, (k + 1 : U32))

# The valid moves of a tile are its land neighbours e w s n se ne sw nw (bits 0..7): a diagonal cuts corners.
def masked_flags(got: Array<U32> & U32, +own: U32, +bits: U32) -> Array<U32>:
  (cells, +flags) = got
  cells[at(own, 0)] <- (flags .|. ((Bool.to_u32(U32.is_eq((flags .&. 1 : U32), 1)) * bits) << 8n) : U32)

def masked(got: Array<U32> & U32, +own: U32) -> Array<U32>:
  (cells, +bits) = got
  masked_flags(cells[at(own, 0)], own, bits)

def tile_mask(cells: Array<U32>, +i: U32, +w: U32, +h: U32) -> Array<U32>:
  masked(neighbour_bits(8n, (cells, 0), i, (i % w : U32), (i / w : U32), w, h, 0), i)

def all_masks(n: Nat, cells: Array<U32>, +i: U32, +w: U32, +h: U32) -> Array<U32>:
  match n:
    case 0n:
      cells
    case 1n+k:
      all_masks(k, tile_mask(cells, i, w, h), (i + 1 : U32), w, h)

def or_flag(got: Array<U32> & U32, +tile: U32, +bit: U32) -> Array<U32>:
  (cells, +flags) = got
  cells[at(tile, 0)] <- (flags .|. bit : U32)

def flag_jumps(jumps: List<&2, Jump>, cells: Array<U32>) -> Array<U32>:
  match jumps:
    case Nil{}:
      cells
    case Con{Jump{+from, _, _}, rest}:
      flag_jumps(rest, or_flag(cells[at(from, 0)], from, 2))

def flag_target(got: Array<U32> & U32, +tile: U32, +waiting: U32) -> Array<U32> & U32:
  (cells, +flags) = got
  +fresh = U32.is_zero((flags .&. 4 : U32))
  (cells[at(tile, 0)] <- (flags .|. 4 : U32), (waiting + Bool.to_u32(fresh) : U32))

def flag_targets(tiles: List<&2, U32>, got: Array<U32> & U32) -> Array<U32> & U32:
  match tiles:
    case Nil{}:
      got
    case Con{+tile, rest}:
      (cells, +waiting) = got
      flag_targets(rest, flag_target(cells[at(tile, 0)], tile, waiting))

def offer_starts(starts: List<&2, Start>, g: Grid, +needed: U32) -> Grid:
  match starts:
    case Nil{}:
      g
    case Con{Start{+tile, +length, +seed}, rest}:
      offer_starts(rest, offer(g, Cand{length, tile, seed}, needed, none(), 0), needed)

def search_of(g: Grid, +waiting: U32) -> Search:
  match g:
    case Grid{cells, heap}:
      Search{cells, heap, waiting, Bool.not(U32.is_zero(waiting))}

def cells_of(s: Search) -> Array<U32>:
  match s:
    case Search{cells, _, _, _}:
      cells

def started(got: Array<U32> & U32, starts: List<&2, Start>, +ctx: Ctx) -> Array<U32>:
  (cells, +waiting) = got
  cells_of(settle_loop(1073741824n, search_of(offer_starts(starts, Grid{cells, empty_heap()}, ctx_needed(ctx)), waiting), ctx))

# The cells after a search from the starts until every target tile has `needed` labels (or nothing is left); with a
# bound, the labels past it may stay unsettled.
def run(+world: FilterWorld.World, +depth: Nat, +jumps: List<&2, Jump>, starts: List<&2, Start>, targets: List<&2, U32>, +needed: U32, +bound: Maybe<&2, Walk.Length>) -> Array<U32>:
  match world:
    case FilterWorld.World{_, +w, +h, _, _, _, +tiles, _, _}:
      masked_cells = all_masks(U32.to_nat((w * h : U32)), land_cells(tiles, [0 : U32^(Nat.add(depth, 4n))], 0), 0, w, h)
      started(flag_targets(targets, (flag_jumps(jumps, masked_cells), 0)), starts, Ctx{w, needed, jumps, bound})

def second_label_of(got: Array<U32> & Cand, +first: Cand) -> Array<U32> & List<&2, Cand>:
  (cells, +second) = got
  (cells, [first, second])

def labels_after_first(two: Bool, got: Array<U32> & Cand, +tile: U32) -> Array<U32> & List<&2, Cand>:
  match two:
    case True{}:
      (cells, +first) = got
      second_label_of(read_label(cells, at(tile, 8), tile), first)
    case False{}:
      (cells, +first) = got
      (cells, [first])

def labels_by_count(empty: Bool, cells: Array<U32>, +tile: U32, +settled: U32) -> Array<U32> & List<&2, Cand>:
  match empty:
    case True{}:
      (cells, Nil{})
    case False{}:
      labels_after_first(U32.is_eq(settled, 2), read_label(cells, at(tile, 3), tile), tile)

def labels_settled(got: Array<U32> & U32, +tile: U32) -> Array<U32> & List<&2, Cand>:
  (cells, +settled) = got
  labels_by_count(U32.is_zero(settled), cells, tile, settled)

# The settled labels of a tile, in settle order.
def labels(cells: Array<U32>, +tile: U32) -> Array<U32> & List<&2, Cand>:
  labels_settled(cells[at(tile, 1)], tile)

type Chain is Type:
  Chain{cells: Array<U32>, hops: List<&2, U32>, tile: U32, go: Bool}

def chain_step(got: Array<U32> & List<&2, U32>, +acc: List<&2, U32>, +start: U32) -> Chain:
  (cells, words) = got
  match words:
    case Con{+prev, Con{+hop, _}}:
      Chain{cells, Bool.pick(List<&2, U32>, U32.is_zero(hop), acc, (hop - 1 : U32) <> acc), prev,
        Bool.not(U32.is_eq(prev, start) || U32.is_eq(prev, none()))}
    case _:
      Chain{cells, acc, none(), False{}}

def hop_chain(n: Nat, c: Chain, +start: U32) -> Chain:
  match n c:
    case 1n+k Chain{cells, +acc, +tile, True{}}:
      hop_chain(k, chain_step(read_words(cells, at(tile, 13), 2n), acc, start), start)
    case _ other:
      other

def chain_hops(c: Chain) -> Array<U32> & List<&2, U32>:
  match c:
    case Chain{cells, hops, _, _}:
      (cells, hops)

# The jumps (their positions in the jump list) on the recorded shortest path from start to goal, in path order.
def hops(cells: Array<U32>, +goal: U32, +start: U32) -> Array<U32> & List<&2, U32>:
  chain_hops(hop_chain(1048576n, Chain{cells, Nil{}, goal, Bool.not(U32.is_eq(goal, start))}, start))
