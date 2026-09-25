import Base

# Lua 5.1.5 tables (ltable.c, lvm.c luaV_settable, ltablib.c insert/remove), key kinds number, string and boolean.
# Array part `cells` (slot i: full flag at 2i, value at 2i + 1) and hash part `nodes` (node i at 8i: key tag, key a,
# key b, next + 1, full flag, value). Keys: number = f64 bits (a = hi, b = lo); string = (a = luaS_hash, b = id),
# equal iff ids are equal; boolean = (a = 0 or 1). Tag 4 is a string key turned into a dead key by `collect`.
# Values are one U32 plus presence. Assigning nil to an absent key runs newkey, exactly like the VM.
# Traversal positions: 0 .. asize - 1 are array slots, asize + i is node i (luaH_next order).

type TKey is Data:
  TKey{tag: U32, a: U32, b: U32}

type Node is Data:
  Node{tag: U32, a: U32, b: U32, next: U32, full: U32, value: U32}

type Table is Type:
  Table{nodes: Array<U32>, cells: Array<U32>, lsize: U32, dummy: Bool, asize: U32, acap: U32, lastfree: U32}

type Where is Data:
  Missing{}
  InArray{index: U32}
  InNode{index: U32}

type Found is Data:
  Found{full: Bool, value: U32}

# status: 0 = no more entries, 1 = an entry, 2 = "invalid key to 'next'".
type Step is Data:
  Step{status: U32, key: TKey, value: U32}

type Census is Type:
  Census{nums: Array<U32>, total: U32, ints: U32}

type Sizes is Data:
  Sizes{a: U32, na: U32, n: U32}

type Cells is Type:
  Cells{cells: Array<U32>, cap: U32}

type Bounds is Data:
  Bounds{i: U32, j: U32}

def nil_key() -> TKey:
  TKey{0, 0, 0}

def number_key(+hi: U32, +lo: U32) -> TKey:
  TKey{1, hi, lo}

def string_key(+hash: U32, +id: U32) -> TKey:
  TKey{2, hash, id}

def boolean_key(+b: Bool) -> TKey:
  TKey{3, Bool.to_u32(b), 0}

def shl(+x: U32, +k: U32) -> U32:
  (x << U32.to_nat((k .&. 31 : U32)) : U32)

def shr(+x: U32, +k: U32) -> U32:
  (x >> U32.to_nat((k .&. 31 : U32)) : U32)

def floor_log2_loop(n: Nat, +x: U32, +e: U32) -> U32:
  match n:
    case 0n:
      e
    case 1n+p:
      floor_log2_loop(p, (x >> 1n : U32), (e + Bool.to_u32((x >= 2 : U32)) : U32))

def floor_log2(+x: U32) -> U32:
  floor_log2_loop(32n, x, 0)

# ceillog2 of ltable.c: 0 for x <= 1.
def ceil_log2(+x: U32) -> U32:
  Bool.pick(U32, (x <= 1 : U32), 0, (floor_log2((x - 1 : U32)) + 1 : U32))

# The number key of an unsigned integer k (its exact f64 bits).
def int_key(+k: U32) -> TKey:
  +e = floor_log2(k)
  +mant = (k .^. shl(1, e) : U32)
  +small = (e <= 20 : U32)
  +hi = (shl((1023 + e : U32), 20) .|. Bool.pick(U32, small, shl(mant, (20 - e : U32)), shr(mant, (e - 20 : U32))) : U32)
  +lo = Bool.pick(U32, small, 0, shl(mant, (52 - e : U32)))
  Bool.pick(TKey, U32.is_zero(k), TKey{1, 0, 0}, TKey{1, hi, lo})

def int_value(+hi: U32, +lo: U32, +shift: U32) -> U32:
  +mhi = (hi .&. 1048575 : U32)
  +low = Bool.pick(U32, (shift <= 20 : U32), shr(mhi, (20 - shift : U32)), (shl(mhi, (shift - 20 : U32)) .|. shr(lo, (52 - shift : U32)) : U32))
  (shl(1, shift) .|. low : U32)

def fraction_zero(+hi: U32, +lo: U32, +shift: U32) -> Bool:
  +hi_rest = ((hi .&. 1048575 : U32) .&. (shl(1, (20 - shift : U32)) - 1 : U32) : U32)
  +lo_rest = (lo .&. (shl(1, (52 - shift : U32)) - 1 : U32) : U32)
  Bool.pick(Bool, (shift <= 20 : U32), Bool.and(U32.is_zero(lo), U32.is_zero(hi_rest)), U32.is_zero(lo_rest))

# arrayindex restricted to 1 .. 2^31 - 1 (0 for every other key).
def positive_int(+k: TKey) -> U32:
  match k:
    case TKey{+tag, +hi, +lo}:
      +e = ((hi >> 20n) .&. 2047 : U32)
      +shift = (e - 1023 : U32)
      +valid = Bool.and(Bool.and(U32.is_eq(tag, 1), (hi < 2147483648 : U32)), Bool.and((e >= 1023 : U32), (e <= 1053 : U32)))
      Bool.pick(U32, Bool.and(valid, fraction_zero(hi, lo, shift)), int_value(hi, lo, shift), 0)

def is_zero_number(+hi: U32, +lo: U32) -> Bool:
  Bool.and(U32.is_zero((hi .&. 2147483647 : U32)), U32.is_zero(lo))

# mainposition: hashnum ((lo + hi) % ((size - 1) | 1), 0 for +-0), string hash & (size - 1), boolean & (size - 1).
def main_position(+k: TKey, +lsize: U32) -> U32:
  match k:
    case TKey{+tag, +a, +b}:
      +mask = (shl(1, lsize) - 1 : U32)
      +number = Bool.pick(U32, is_zero_number(a, b), 0, ((a + b : U32) % (mask .|. 1) : U32))
      Bool.pick(U32, U32.is_eq(tag, 1), number, (a .&. mask : U32))

def same_key(+k: TKey, +tag: U32, +a: U32, +b: U32) -> Bool:
  match k:
    case TKey{+ktag, +ka, +kb}:
      +bits = Bool.and(U32.is_eq(ka, a), U32.is_eq(kb, b))
      +zeros = Bool.and(U32.is_eq(tag, 1), Bool.and(is_zero_number(ka, kb), is_zero_number(a, b)))
      +ids = Bool.and(U32.is_eq(tag, 2), U32.is_eq(kb, b))
      Bool.and(U32.is_eq(ktag, tag), Bool.or(bits, Bool.or(zeros, ids)))

def dead_match(+k: TKey, +tag: U32, +b: U32) -> Bool:
  match k:
    case TKey{+ktag, _, +kb}:
      Bool.and(Bool.and(U32.is_eq(tag, 4), U32.is_eq(ktag, 2)), U32.is_eq(kb, b))

def node_key(+node: Node) -> TKey:
  match node:
    case Node{+tag, +a, +b, _, _, _}:
      TKey{tag, a, b}

def node_next(+node: Node) -> U32:
  match node:
    case Node{_, _, _, +next, _, _}:
      next

def node_full(+node: Node) -> U32:
  match node:
    case Node{_, _, _, _, +full, _}:
      full

def node_value(+node: Node) -> U32:
  match node:
    case Node{_, _, _, _, _, +value}:
      value

def node_hits(+k: TKey, +node: Node, +dead_ok: Bool) -> Bool:
  match node:
    case Node{+tag, +a, +b, _, _, _}:
      Bool.or(same_key(k, tag, a, b), Bool.and(dead_ok, dead_match(k, tag, b)))

def keyed(+k: TKey, +next: U32) -> Node:
  match k:
    case TKey{+tag, +a, +b}:
      Node{tag, a, b, next, 0, 0}

def with_next(+node: Node, +next: U32) -> Node:
  match node:
    case Node{+tag, +a, +b, _, +full, +value}:
      Node{tag, a, b, next, full, value}

def node_base(+i: U32) -> U32:
  (i << 3n : U32)

def read_value(got: Array<U32> & U32, +tag: U32, +a: U32, +b: U32, +next: U32, +full: U32) -> Array<U32> & Node:
  (nodes, +value) = got
  (nodes, Node{tag, a, b, next, full, value})

def read_full(got: Array<U32> & U32, +base: U32, +tag: U32, +a: U32, +b: U32, +next: U32) -> Array<U32> & Node:
  (nodes, +full) = got
  read_value(nodes[(base + 5 : U32)], tag, a, b, next, full)

def read_next(got: Array<U32> & U32, +base: U32, +tag: U32, +a: U32, +b: U32) -> Array<U32> & Node:
  (nodes, +next) = got
  read_full(nodes[(base + 4 : U32)], base, tag, a, b, next)

def read_b(got: Array<U32> & U32, +base: U32, +tag: U32, +a: U32) -> Array<U32> & Node:
  (nodes, +b) = got
  read_next(nodes[(base + 3 : U32)], base, tag, a, b)

def read_a(got: Array<U32> & U32, +base: U32, +tag: U32) -> Array<U32> & Node:
  (nodes, +a) = got
  read_b(nodes[(base + 2 : U32)], base, tag, a)

def read_tag(got: Array<U32> & U32, +base: U32) -> Array<U32> & Node:
  (nodes, +tag) = got
  read_a(nodes[(base + 1 : U32)], base, tag)

def read_node(nodes: Array<U32>, +i: U32) -> Array<U32> & Node:
  read_tag(nodes[node_base(i)], node_base(i))

def write_node(nodes: Array<U32>, +i: U32, +node: Node) -> Array<U32>:
  match node:
    case Node{+tag, +a, +b, +next, +full, +value}:
      +base = node_base(i)
      nodes[base] <- tag
      nodes[(base + 1 : U32)] <- a
      nodes[(base + 2 : U32)] <- b
      nodes[(base + 3 : U32)] <- next
      nodes[(base + 4 : U32)] <- full
      nodes[(base + 5 : U32)] <- value

def empty_nodes(+lsize: U32) -> Array<U32>:
  Array.new(U32, U32.to_nat((lsize + 3 : U32)), 0)

def new_cells(+cap: U32) -> Array<U32>:
  Array.new(U32, U32.to_nat((ceil_log2(cap) + 1 : U32)), 0)

def cell_capacity(+n: U32) -> U32:
  shl(1, ceil_log2(n))

# luaH_new(narray, nhash).
def new(+narray: U32, +nhash: U32) -> Table:
  +lsize = ceil_log2(nhash)
  +dummy = U32.is_zero(nhash)
  Table{empty_nodes(lsize), new_cells(cell_capacity(narray)), lsize, dummy, narray, cell_capacity(narray), Bool.pick(U32, dummy, 0, shl(1, lsize))}

def fb_loop(n: Nat, +x: U32, +e: U32) -> U32:
  match n:
    case 0n:
      shl(x, e)
    case 1n+p:
      +big = (x >= 16 : U32)
      fb_loop(p, Bool.pick(U32, big, ((x + 1 : U32) >> 1n : U32), x), (e + Bool.to_u32(big) : U32))

# luaO_fb2int(luaO_int2fb(x)): the size OP_NEWTABLE really allocates for a constructor with x items.
def fb_round(+x: U32) -> U32:
  fb_loop(32n, x, 0)

# A table built by a constructor with `narray` positional and `nhash` keyed fields.
def constructed(+narray: U32, +nhash: U32) -> Table:
  new(fb_round(narray), fb_round(nhash))

def find_loop(n: Nat, done: Bool, got: Array<U32> & Node, +i: U32, +found: U32, +k: TKey, +dead_ok: Bool) -> Array<U32> & U32:
  match n:
    case 0n:
      (nodes, _) = got
      (nodes, found)
    case 1n+p:
      match done:
        case True{}:
          (nodes, _) = got
          (nodes, found)
        case False{}:
          (nodes, +node) = got
          +hit = node_hits(k, node, dead_ok)
          +next = node_next(node)
          find_loop(p, Bool.or(hit, U32.is_zero(next)), read_node(nodes, (next - 1 : U32)), (next - 1 : U32), Bool.pick(U32, hit, (i + 1 : U32), 0), k, dead_ok)

# The chain walk from k's main position: node index + 1, or 0.
def find_node(nodes: Array<U32>, +lsize: U32, +k: TKey, +dead_ok: Bool) -> Array<U32> & U32:
  find_loop(U32.to_nat((shl(1, lsize) + 1 : U32)), False{}, read_node(nodes, main_position(k, lsize)), main_position(k, lsize), 0, k, dead_ok)

def found_where(got: Array<U32> & U32, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32) -> Table & Where:
  (nodes, +hit) = got
  (Table{nodes, cells, lsize, dummy, asize, acap, lastfree}, Bool.pick(Where, U32.is_zero(hit), Missing{}, InNode{(hit - 1 : U32)}))

def find_hashed(t: Table, +k: TKey) -> Table & Where:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      found_where(find_node(nodes, lsize, k, False{}), cells, lsize, dummy, asize, acap, lastfree)

def find_in(in_array: Bool, t: Table, +index: U32, +k: TKey) -> Table & Where:
  match in_array:
    case True{}:
      (t, InArray{(index - 1 : U32)})
    case False{}:
      find_hashed(t, k)

def asize_of(t: Table) -> Table & U32:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      (Table{nodes, cells, lsize, dummy, asize, acap, lastfree}, asize)

def find_sized(got: Table & U32, +k: TKey) -> Table & Where:
  (t, +asize) = got
  +index = positive_int(k)
  find_in(Bool.and((index >= 1 : U32), (index <= asize : U32)), t, index, k)

# luaH_get: the slot holding k (its value may be nil), or Missing.
def find(t: Table, +k: TKey) -> Table & Where:
  find_sized(asize_of(t), k)

def free_loop(n: Nat, done: Bool, got: Array<U32> & U32, +pos: U32, +found: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      (nodes, _) = got
      (nodes, found)
    case 1n+p:
      match done:
        case True{}:
          (nodes, _) = got
          (nodes, found)
        case False{}:
          (nodes, +tag) = got
          +free = U32.is_zero(tag)
          free_loop(p, Bool.or(free, U32.is_zero(pos)), nodes[node_base((pos - 1 : U32))], (pos - 1 : U32), Bool.pick(U32, free, (pos + 1 : U32), 0))

# getfreepos: the highest node below lastfree whose key is nil (index + 1), or 0.
def free_position(nodes: Array<U32>, +lastfree: U32) -> Array<U32> & U32:
  free_loop(U32.to_nat(lastfree), U32.is_zero(lastfree), nodes[node_base((lastfree - 1 : U32))], (lastfree - 1 : U32), 0)

def relink_loop(n: Nat, done: Bool, got: Array<U32> & U32, +i: U32, +mp: U32, +free: U32) -> Array<U32>:
  match n:
    case 0n:
      (nodes, _) = got
      nodes
    case 1n+p:
      match done:
        case True{}:
          (nodes, _) = got
          nodes
        case False{}:
          (nodes, +next) = got
          +hit = U32.is_eq(next, (mp + 1 : U32))
          nodes[(node_base(i) + 3 : U32)] <- Bool.pick(U32, hit, (free + 1 : U32), next)
          relink_loop(p, Bool.or(hit, U32.is_zero(next)), nodes[(node_base((next - 1 : U32)) + 3 : U32)], (next - 1 : U32), mp, free)

# Redo the chain through `other` with the free node in place of mp.
def relink_previous(nodes: Array<U32>, +lsize: U32, +other: U32, +mp: U32, +free: U32) -> Array<U32>:
  relink_loop(U32.to_nat((shl(1, lsize) + 1 : U32)), False{}, nodes[(node_base(other) + 3 : U32)], other, mp, free)

def settle(home: Bool, nodes: Array<U32>, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +k: TKey, +mp: U32, +occupant: Node, +free: U32, +other: U32) -> Table & Where:
  match home:
    case True{}:
      linked = write_node(nodes, free, keyed(k, node_next(occupant)))
      (Table{write_node(linked, mp, with_next(occupant, (free + 1 : U32))), cells, lsize, dummy, asize, acap, free}, InNode{free})
    case False{}:
      moved = write_node(relink_previous(nodes, lsize, other, mp, free), free, occupant)
      (Table{write_node(moved, mp, keyed(k, 0)), cells, lsize, dummy, asize, acap, free}, InNode{mp})

def collide_with(exhausted: Bool, nodes: Array<U32>, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +k: TKey, +mp: U32, +occupant: Node, +free: U32) -> Table & Where:
  match exhausted:
    case True{}:
      (Table{nodes, cells, lsize, dummy, asize, acap, 0}, Missing{})
    case False{}:
      +other = main_position(node_key(occupant), lsize)
      settle(U32.is_eq(other, mp), nodes, cells, lsize, dummy, asize, acap, k, mp, occupant, free, other)

def collide(got: Array<U32> & U32, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +k: TKey, +mp: U32, +occupant: Node) -> Table & Where:
  (nodes, +free) = got
  collide_with(U32.is_zero(free), nodes, cells, lsize, dummy, asize, acap, k, mp, occupant, (free - 1 : U32))

def newkey_choose(taken: Bool, nodes: Array<U32>, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32, +k: TKey, +mp: U32, +occupant: Node) -> Table & Where:
  match taken:
    case False{}:
      (Table{write_node(nodes, mp, keyed(k, node_next(occupant))), cells, lsize, dummy, asize, acap, lastfree}, InNode{mp})
    case True{}:
      collide(free_position(nodes, lastfree), cells, lsize, dummy, asize, acap, k, mp, occupant)

def newkey_at(got: Array<U32> & Node, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32, +k: TKey, +mp: U32) -> Table & Where:
  (nodes, +occupant) = got
  newkey_choose(Bool.or(Bool.not(U32.is_zero(node_full(occupant))), dummy), nodes, cells, lsize, dummy, asize, acap, lastfree, k, mp, occupant)

# newkey without the rehash: Missing when no free node is left.
def newkey(t: Table, +k: TKey) -> Table & Where:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      newkey_at(read_node(nodes, main_position(k, lsize)), cells, lsize, dummy, asize, acap, lastfree, k, main_position(k, lsize))

def place_found(found: Table & Where, +k: TKey) -> Table & Where:
  (t, +w) = found
  match w:
    case Missing{}:
      newkey(t, k)
    case InArray{+index}:
      (t, InArray{index})
    case InNode{+index}:
      (t, InNode{index})

# luaH_set without the rehash.
def place(t: Table, +k: TKey) -> Table & Where:
  place_found(find(t, k), k)

def write_cell(t: Table, +index: U32, +full: Bool, +value: U32) -> Table:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      cells[(index << 1n : U32)] <- Bool.to_u32(full)
      cells[((index << 1n) + 1 : U32)] <- value
      Table{nodes, cells, lsize, dummy, asize, acap, lastfree}

def write_value(t: Table, +index: U32, +full: Bool, +value: U32) -> Table:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      nodes[(node_base(index) + 4 : U32)] <- Bool.to_u32(full)
      nodes[(node_base(index) + 5 : U32)] <- value
      Table{nodes, cells, lsize, dummy, asize, acap, lastfree}

def store(placed: Table & Where, +full: Bool, +value: U32) -> Table:
  (t, +w) = placed
  match w:
    case Missing{}:
      t
    case InArray{+index}:
      write_cell(t, index, full, value)
    case InNode{+index}:
      write_value(t, index, full, value)

def put(t: Table, +k: TKey, +full: Bool, +value: U32) -> Table:
  store(place(t, k), full, value)

def bump(got: Array<U32> & U32, +slot: U32, +delta: U32) -> Array<U32>:
  (nums, +old) = got
  nums[slot] <- (old + delta : U32)

def census_add(c: Census, +slot: U32, +total: U32, +ints: U32) -> Census:
  match c:
    case Census{nums, +t, +n}:
      Census{bump(nums[slot], slot, ints), (t + total : U32), (n + ints : U32)}

def count_cells(n: Nat, got: Array<U32> & U32, +i: U32, c: Census) -> Array<U32> & Census:
  match n:
    case 0n:
      (cells, _) = got
      (cells, c)
    case 1n+p:
      (cells, +full) = got
      count_cells(p, cells[((i + 1 : U32) << 1n : U32)], (i + 1 : U32), census_add(c, ceil_log2((i + 1 : U32)), full, full))

def countable(+index: U32) -> U32:
  Bool.to_u32(Bool.and((index >= 1 : U32), (index <= 67108864 : U32)))

def count_nodes(n: Nat, got: Array<U32> & Node, +i: U32, c: Census) -> Array<U32> & Census:
  match n:
    case 0n:
      (nodes, _) = got
      (nodes, c)
    case 1n+p:
      (nodes, +node) = got
      +index = positive_int(node_key(node))
      count_nodes(p, read_node(nodes, (i + 1 : U32)), (i + 1 : U32), census_add(c, ceil_log2(index), node_full(node), (node_full(node) .&. countable(index) : U32)))

def census_nodes(got: Array<U32> & Census, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32) -> Table & Census:
  (nodes, c) = got
  (Table{nodes, cells, lsize, dummy, asize, acap, lastfree}, c)

def census_cells(got: Array<U32> & Census, nodes: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32) -> Table & Census:
  (cells, c) = got
  census_nodes(count_nodes(U32.to_nat(shl(1, lsize)), read_node(nodes, 0), 0, c), cells, lsize, dummy, asize, acap, lastfree)

# numusearray + numusehash.
def census_of(t: Table) -> Table & Census:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      census_cells(count_cells(U32.to_nat(asize), cells[0], 0, Census{[0 : U32*32n], 0, 0}), nodes, lsize, dummy, asize, acap, lastfree)

def sizes_loop(n: Nat, done: Bool, got: Array<U32> & U32, +i: U32, +twotoi: U32, +narray: U32, +s: Sizes) -> Array<U32> & Sizes:
  match n:
    case 0n:
      (nums, _) = got
      (nums, s)
    case 1n+p:
      match done:
        case True{}:
          (nums, _) = got
          (nums, s)
        case False{}:
          (nums, +count) = got
          match s:
            case Sizes{+a, +na, +size}:
              +sum = (a + count : U32)
              +better = Bool.and(Bool.not(U32.is_zero(count)), (sum > (twotoi >> 1n) : U32))
              +stop = Bool.or(U32.is_eq(sum, narray), (twotoi >= narray : U32))
              sizes_loop(p, stop, nums[(i + 1 : U32)], (i + 1 : U32), (twotoi << 1n : U32), narray, Sizes{sum, Bool.pick(U32, better, sum, na), Bool.pick(U32, better, twotoi, size)})

# computesizes: Sizes{_, na, optimal array size}.
def compute_sizes(nums: Array<U32>, +narray: U32) -> Array<U32> & Sizes:
  sizes_loop(28n, U32.is_zero(narray), nums[0], 0, 1, narray, Sizes{0, 0, 0})

def copy_words(n: Nat, got: Array<U32> & U32, +i: U32, fresh: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      fresh
    case 1n+p:
      (old, +w) = got
      fresh[i] <- w
      copy_words(p, old[(i + 1 : U32)], (i + 1 : U32), fresh)

def clear_words(n: Nat, cells: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      cells
    case 1n+p:
      cells[i] <- 0
      clear_words(p, cells, (i + 1 : U32))

# setarrayvector: cells 0 .. target - 1 with the new ones nil.
def grow(fresh: Bool, cells: Array<U32>, +asize: U32, +acap: U32, +target: U32) -> Cells:
  match fresh:
    case True{}:
      Cells{copy_words(U32.to_nat((asize << 1n : U32)), cells[0], 0, new_cells(cell_capacity(target))), cell_capacity(target)}
    case False{}:
      Cells{clear_words(U32.to_nat(((target - asize : U32) << 1n : U32)), cells, (asize << 1n : U32)), acap}

def cell_value(got: Array<U32> & U32, nodes: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32, +full: U32) -> Table & Found:
  (cells, +value) = got
  (Table{nodes, cells, lsize, dummy, asize, acap, lastfree}, Found{Bool.not(U32.is_zero(full)), value})

def cell_full(got: Array<U32> & U32, nodes: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32, +i: U32) -> Table & Found:
  (cells, +full) = got
  cell_value(cells[((i << 1n) + 1 : U32)], nodes, lsize, dummy, asize, acap, lastfree, full)

def cell_of(t: Table, +i: U32) -> Table & Found:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      cell_full(cells[(i << 1n : U32)], nodes, lsize, dummy, asize, acap, lastfree, i)

def put_if(full: Bool, t: Table, +k: TKey, +value: U32) -> Table:
  match full:
    case True{}:
      put(t, k, True{}, value)
    case False{}:
      t

def slice_one(got: Table & Found, +i: U32) -> Table:
  (t, +f) = got
  match f:
    case Found{+full, +value}:
      put_if(full, t, int_key((i + 1 : U32)), value)

def slice_loop(n: Nat, t: Table, +i: U32) -> Table:
  match n:
    case 0n:
      t
    case 1n+p:
      slice_loop(p, slice_one(cell_of(t, i), i), (i + 1 : U32))

def reinsert_loop(n: Nat, got: Array<U32> & Node, +i: U32, t: Table) -> Table:
  match n:
    case 0n:
      t
    case 1n+p:
      (old, +node) = got
      reinsert_loop(p, read_node(old, (i - 1 : U32)), (i - 1 : U32), put_if(Bool.not(U32.is_zero(node_full(node))), t, node_key(node), node_value(node)))

def resize_fill(c: Cells, old: Array<U32>, +old_lsize: U32, +old_asize: U32, +nasize: U32, +lsize: U32, +dummy: Bool) -> Table:
  match c:
    case Cells{cells, +cap}:
      +vanishing = Bool.pick(U32, (old_asize > nasize : U32), (old_asize - nasize : U32), 0)
      +old_size = shl(1, old_lsize)
      reinsert_loop(U32.to_nat(old_size), read_node(old, (old_size - 1 : U32)), (old_size - 1 : U32), slice_loop(U32.to_nat(vanishing), Table{empty_nodes(lsize), cells, lsize, dummy, nasize, cap, Bool.pick(U32, dummy, 0, shl(1, lsize))}, nasize))

# resize (ltable.c): array part to nasize, hash part to ceil_pow2(nhsize) nodes; the vanishing array slice, then the
# old nodes from the last one down, are re-inserted.
def resize(t: Table, +nasize: U32, +nhsize: U32) -> Table:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, _}:
      +grown = (nasize > asize : U32)
      resize_fill(grow(Bool.and(grown, (nasize > acap : U32)), cells, asize, acap, Bool.pick(U32, grown, nasize, asize)), nodes, lsize, asize, nasize, ceil_log2(nhsize), U32.is_zero(nhsize))

def resize_computed(t: Table, +total: U32, got: Array<U32> & Sizes) -> Table:
  (nums, +s) = got
  match s:
    case Sizes{_, +na, +size}:
      resize(t, size, (total - na : U32))

def resize_census(t: Table, c: Census) -> Table:
  match c:
    case Census{nums, +total, +ints}:
      resize_computed(t, total, compute_sizes(nums, ints))

def rehash_with(got: Table & Census, +k: TKey) -> Table:
  (t, c) = got
  +index = positive_int(k)
  resize_census(t, census_add(c, ceil_log2(index), 1, countable(index)))

# rehash for the key k that found no free node.
def rehash(t: Table, +k: TKey) -> Table:
  rehash_with(census_of(t), k)

def assign_placed(placed: Table & Where, +k: TKey, +full: Bool, +value: U32) -> Table:
  (t, +w) = placed
  match w:
    case Missing{}:
      put(rehash(t, k), k, full, value)
    case InArray{+index}:
      write_cell(t, index, full, value)
    case InNode{+index}:
      write_value(t, index, full, value)

# t[k] = value (full) or t[k] = nil (not full): luaH_set, newkey, rehash.
def assign(t: Table, +k: TKey, +full: Bool, +value: U32) -> Table:
  assign_placed(place(t, k), k, full, value)

# t[k] = value
def set(t: Table, +k: TKey, +value: U32) -> Table:
  assign(t, k, True{}, value)

# t[k] = nil
def remove(t: Table, +k: TKey) -> Table:
  assign(t, k, False{}, 0)

def node_found_read(got: Array<U32> & Node, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32) -> Table & Found:
  (nodes, +node) = got
  (Table{nodes, cells, lsize, dummy, asize, acap, lastfree}, Found{Bool.not(U32.is_zero(node_full(node))), node_value(node)})

def node_found(t: Table, +index: U32) -> Table & Found:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      node_found_read(read_node(nodes, index), cells, lsize, dummy, asize, acap, lastfree)

def read_where(got: Table & Where) -> Table & Found:
  (t, +w) = got
  match w:
    case Missing{}:
      (t, Found{False{}, 0})
    case InArray{+index}:
      cell_of(t, index)
    case InNode{+index}:
      node_found(t, index)

# t[k]
def get(t: Table, +k: TKey) -> Table & Found:
  read_where(find(t, k))

def present_of(got: Table & Found) -> Table & Bool:
  (t, +f) = got
  match f:
    case Found{+full, _}:
      (t, full)

def present_int(t: Table, +k: U32) -> Table & Bool:
  present_of(get(t, int_key(k)))

def array_search(n: Nat, done: Bool, got: Table & Bool, +i: U32, +j: U32, +m: U32) -> Table & U32:
  match n:
    case 0n:
      (t, _) = got
      (t, i)
    case 1n+p:
      match done:
        case True{}:
          (t, _) = got
          (t, i)
        case False{}:
          (t, +full) = got
          +i2 = Bool.pick(U32, full, m, i)
          +j2 = Bool.pick(U32, full, j, m)
          array_search(p, ((j2 - i2 : U32) <= 1 : U32), present_of(cell_of(t, (((i2 + j2 : U32) >> 1n) - 1 : U32))), i2, j2, ((i2 + j2 : U32) >> 1n : U32))

def hash_search(n: Nat, done: Bool, got: Table & Bool, +i: U32, +j: U32, +m: U32) -> Table & U32:
  match n:
    case 0n:
      (t, _) = got
      (t, i)
    case 1n+p:
      match done:
        case True{}:
          (t, _) = got
          (t, i)
        case False{}:
          (t, +full) = got
          +i2 = Bool.pick(U32, full, m, i)
          +j2 = Bool.pick(U32, full, j, m)
          hash_search(p, ((j2 - i2 : U32) <= 1 : U32), present_int(t, ((i2 + j2 : U32) >> 1n : U32)), i2, j2, ((i2 + j2 : U32) >> 1n : U32))

def unbound_grow(n: Nat, done: Bool, got: Table & Bool, +i: U32, +j: U32) -> Table & Bounds:
  match n:
    case 0n:
      (t, _) = got
      (t, Bounds{i, j})
    case 1n+p:
      match done:
        case True{}:
          (t, _) = got
          (t, Bounds{i, j})
        case False{}:
          (t, +present) = got
          +i2 = Bool.pick(U32, present, j, i)
          +j2 = Bool.pick(U32, present, (j << 1n : U32), j)
          unbound_grow(p, Bool.not(present), present_int(t, j2), i2, j2)

def unbound_bisect(got: Table & Bounds) -> Table & U32:
  (t, +b) = got
  match b:
    case Bounds{+i, +j}:
      hash_search(34n, ((j - i : U32) <= 1 : U32), present_int(t, ((i + j : U32) >> 1n : U32)), i, j, ((i + j : U32) >> 1n : U32))

def length_hashed(dummy: Bool, t: Table, +j: U32) -> Table & U32:
  match dummy:
    case True{}:
      (t, j)
    case False{}:
      unbound_bisect(unbound_grow(33n, False{}, present_int(t, (j + 1 : U32)), j, (j + 1 : U32)))

def length_array(border: Bool, t: Table, +dummy: Bool, +j: U32) -> Table & U32:
  match border:
    case True{}:
      array_search(34n, (j <= 1 : U32), present_of(cell_of(t, ((j >> 1n) - 1 : U32))), 0, j, (j >> 1n : U32))
    case False{}:
      length_hashed(dummy, t, j)

def length_last(got: Table & Bool, +dummy: Bool, +j: U32) -> Table & U32:
  (t, +last_full) = got
  length_array(Bool.and(Bool.not(U32.is_zero(j)), Bool.not(last_full)), t, dummy, j)

# #t (luaH_getn): a border, by binary search in the array part or unbound_search in the hash part.
def length(t: Table) -> Table & U32:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      length_last(present_of(cell_of(Table{nodes, cells, lsize, dummy, asize, acap, lastfree}, (asize - 1 : U32))), dummy, asize)

def slot_count(t: Table) -> Table & U32:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      (Table{nodes, cells, lsize, dummy, asize, acap, lastfree}, (asize + shl(1, lsize) : U32))

def full_at_part(in_array: Bool, t: Table, +pos: U32, +asize: U32) -> Table & Bool:
  match in_array:
    case True{}:
      present_of(cell_of(t, pos))
    case False{}:
      present_of(node_found(t, (pos - asize : U32)))

def full_at_split(got: Table & U32, +pos: U32) -> Table & Bool:
  (t, +asize) = got
  full_at_part((pos < asize : U32), t, pos, asize)

def full_at(t: Table, +pos: U32) -> Table & Bool:
  full_at_split(asize_of(t), pos)

def scan_loop(n: Nat, done: Bool, got: Table & Bool, +pos: U32, +total: U32) -> Table & U32:
  match n:
    case 0n:
      (t, _) = got
      (t, total)
    case 1n+p:
      match done:
        case True{}:
          (t, _) = got
          (t, pos)
        case False{}:
          (t, +full) = got
          +stop = Bool.or(full, ((pos + 1 : U32) >= total : U32))
          scan_loop(p, stop, full_at(t, (pos + 1 : U32)), Bool.pick(U32, full, pos, (pos + 1 : U32)), total)

def scan_counted(got: Table & U32, +from: U32) -> Table & U32:
  (t, +total) = got
  scan_loop(U32.to_nat(((total - from : U32) + 1 : U32)), (from >= total : U32), full_at(t, from), Bool.pick(U32, (from >= total : U32), total, from), total)

# The first traversal position >= from holding a value, or slot_count(t) when there is none.
def scan(t: Table, +from: U32) -> Table & U32:
  scan_counted(slot_count(t), from)

def entry_from_node(got: Array<U32> & Node, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32) -> Table & Step:
  (nodes, +node) = got
  (Table{nodes, cells, lsize, dummy, asize, acap, lastfree}, Step{Bool.to_u32(Bool.not(U32.is_zero(node_full(node)))), node_key(node), node_value(node)})

def entry_node(got: Table & U32, +pos: U32) -> Table & Step:
  (t, +asize) = got
  match t:
    case Table{nodes, cells, +lsize, +dummy, +size, +acap, +lastfree}:
      entry_from_node(read_node(nodes, (pos - asize : U32)), cells, lsize, dummy, size, acap, lastfree)

def entry_cell(got: Table & Found, +pos: U32) -> Table & Step:
  (t, +f) = got
  match f:
    case Found{+full, +value}:
      (t, Step{Bool.to_u32(full), int_key((pos + 1 : U32)), value})

def entry_part(in_array: Bool, t: Table, +pos: U32, +asize: U32) -> Table & Step:
  match in_array:
    case True{}:
      entry_cell(cell_of(t, pos), pos)
    case False{}:
      entry_node((t, asize), pos)

def entry_split(got: Table & U32, +pos: U32) -> Table & Step:
  (t, +asize) = got
  entry_part((pos < asize : U32), t, pos, asize)

# The key and value at a traversal position (status 1 when it holds a value, 0 otherwise).
def entry(t: Table, +pos: U32) -> Table & Step:
  entry_split(asize_of(t), pos)

def entry_or_stop(at_end: Bool, t: Table, +pos: U32) -> Table & Step:
  match at_end:
    case True{}:
      (t, Step{0, nil_key(), 0})
    case False{}:
      entry(t, pos)

def entry_bounded(got: Table & U32, +pos: U32) -> Table & Step:
  (t, +total) = got
  entry_or_stop((pos >= total : U32), t, pos)

def entry_or_end(got: Table & U32) -> Table & Step:
  (t, +pos) = got
  entry_bounded(slot_count(t), pos)

def index_found(got: Array<U32> & U32, cells: Array<U32>, +lsize: U32, +dummy: Bool, +asize: U32, +acap: U32, +lastfree: U32) -> Table & U32:
  (nodes, +hit) = got
  (Table{nodes, cells, lsize, dummy, asize, acap, lastfree}, Bool.pick(U32, U32.is_zero(hit), 4294967295, (asize + hit : U32)))

def index_hashed(t: Table, +k: TKey) -> Table & U32:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      index_found(find_node(nodes, lsize, k, True{}), cells, lsize, dummy, asize, acap, lastfree)

def index_in(in_array: Bool, t: Table, +index: U32, +k: TKey) -> Table & U32:
  match in_array:
    case True{}:
      (t, index)
    case False{}:
      index_hashed(t, k)

def index_sized(got: Table & U32, +k: TKey) -> Table & U32:
  (t, +asize) = got
  +index = positive_int(k)
  index_in(Bool.and((index >= 1 : U32), (index <= asize : U32)), t, index, k)

def index_start(start: Bool, t: Table, +k: TKey) -> Table & U32:
  match start:
    case True{}:
      (t, 0)
    case False{}:
      index_sized(asize_of(t), k)

# findindex + 1: the position a traversal resumes from after key k (nil starts), 4294967295 for an unknown key.
def resume_position(t: Table, +k: TKey) -> Table & U32:
  match k:
    case TKey{+tag, +a, +b}:
      index_start(U32.is_zero(tag), t, TKey{tag, a, b})

def next_valid(invalid: Bool, t: Table, +from: U32) -> Table & Step:
  match invalid:
    case True{}:
      (t, Step{2, nil_key(), 0})
    case False{}:
      entry_or_end(scan(t, from))

def next_from(got: Table & U32) -> Table & Step:
  (t, +from) = got
  next_valid(U32.is_eq(from, 4294967295), t, from)

# next(t, k) (luaH_next): the entry after k in pairs() order; nil_key() starts the traversal.
def next(t: Table, +k: TKey) -> Table & Step:
  next_from(resume_position(t, k))

def node_tag_of(+node: Node) -> U32:
  match node:
    case Node{+tag, _, _, _, _, _}:
      tag

def collect_loop(n: Nat, got: Array<U32> & Node, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      (nodes, _) = got
      nodes
    case 1n+p:
      (nodes, +node) = got
      +dies = Bool.and(U32.is_zero(node_full(node)), U32.is_eq(node_tag_of(node), 2))
      nodes[node_base(i)] <- Bool.pick(U32, dies, 4, node_tag_of(node))
      collect_loop(p, read_node(nodes, (i + 1 : U32)), (i + 1 : U32))

# A garbage collector traversal of the table (lgc.c traversetable/removeentry): every string key with a nil value
# becomes a dead key, which lookups no longer find and getfreepos does not reuse.
def collect(t: Table) -> Table:
  match t:
    case Table{nodes, cells, +lsize, +dummy, +asize, +acap, +lastfree}:
      Table{collect_loop(U32.to_nat(shl(1, lsize)), read_node(nodes, 0), 0), cells, lsize, dummy, asize, acap, lastfree}

def append_at(got: Table & U32, +value: U32) -> Table:
  (t, +n) = got
  set(t, int_key((n + 1 : U32)), value)

# table.insert(t, value)
def append(t: Table, +value: U32) -> Table:
  append_at(length(t), value)

def move_to(got: Table & Found, +i: U32) -> Table:
  (t, +f) = got
  match f:
    case Found{+full, +value}:
      assign(t, int_key(i), full, value)

def shift_up(n: Nat, t: Table, +i: U32) -> Table:
  match n:
    case 0n:
      t
    case 1n+p:
      shift_up(p, move_to(get(t, int_key((i - 1 : U32))), i), (i - 1 : U32))

def insert_sized(got: Table & U32, +pos: U32, +value: U32) -> Table:
  (t, +n) = got
  +e = U32.max((n + 1 : U32), pos)
  set(shift_up(U32.to_nat((e - pos : U32)), t, e), int_key(pos), value)

# table.insert(t, pos, value) for pos >= 1.
def insert(t: Table, +pos: U32, +value: U32) -> Table:
  insert_sized(length(t), pos, value)

def shift_down(n: Nat, t: Table, +i: U32) -> Table:
  match n:
    case 0n:
      t
    case 1n+p:
      shift_down(p, move_to(get(t, int_key((i + 1 : U32))), i), (i + 1 : U32))

def remove_shifted(got: Table & Found, +pos: U32, +e: U32) -> Table & Found:
  (t, +f) = got
  (remove(shift_down(U32.to_nat((e - pos : U32)), t, pos), int_key(e)), f)

def remove_in(inside: Bool, t: Table, +pos: U32, +e: U32) -> Table & Found:
  match inside:
    case True{}:
      remove_shifted(get(t, int_key(pos)), pos, e)
    case False{}:
      (t, Found{False{}, 0})

def remove_sized(got: Table & U32, +pos: U32) -> Table & Found:
  (t, +e) = got
  remove_in(Bool.and((pos >= 1 : U32), (pos <= e : U32)), t, pos, e)

# table.remove(t, pos): the removed value (not full when pos is outside 1 .. #t).
def remove_at(t: Table, +pos: U32) -> Table & Found:
  remove_sized(length(t), pos)

def remove_last_sized(got: Table & U32) -> Table & Found:
  (t, +e) = got
  remove_in(Bool.not(U32.is_zero(e)), t, e, e)

# table.remove(t)
def remove_last(t: Table) -> Table & Found:
  remove_last_sized(length(t))

def fold(+h: U32, +w: U32) -> U32:
  ((h .^. w) * 16777619 : U32)

def fingerprint_loop(n: Nat, done: Bool, got: Table & Step, +h: U32) -> Table & U32:
  match n:
    case 0n:
      (t, _) = got
      (t, h)
    case 1n+p:
      match done:
        case True{}:
          (t, _) = got
          (t, h)
        case False{}:
          (t, +step) = got
          match step:
            case Step{+status, +key, +value}:
              match key:
                case TKey{+tag, +a, +b}:
                  +more = U32.is_eq(status, 1)
                  fingerprint_loop(p, Bool.not(more), next(t, Bool.pick(TKey, more, TKey{tag, a, b}, nil_key())), Bool.pick(U32, more, fold(fold(fold(fold(h, tag), a), b), value), h))

def fingerprint_counted(got: Table & U32) -> Table & U32:
  (t, +total) = got
  fingerprint_loop(U32.to_nat((total + 2 : U32)), False{}, next(t, nil_key()), 2166136261)

# FNV-1a (32-bit, one step per word) over key tag, key a, key b and value of every pairs() entry in order, for laws
# and traces.
def fingerprint(t: Table) -> Table & U32:
  fingerprint_counted(slot_count(t))
