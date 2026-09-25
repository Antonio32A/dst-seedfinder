import Base
import ../rng/pcg.bend as R
import ../rng/lua_random.bend as LR
import ../data/catalog.bend as C
import ./setpieces.bend as S
import ../data/world_catalog.bend as K
import ./prefix.bend as P

# AddSetPeices, like S.generate, but also keeping the RNG and the order in which boon names first
# appear (4-bit boon indices, 8 per word), which decides their insertion order in level.set_pieces.
type Added is Data:
  Added{pieces: S.Pieces, order_lo: U32, order_hi: U32, distinct: U32, rng: R.Rng}

type Boons is Data:
  Boons{a: U32, b: U32, c: U32, d: U32, order_lo: U32, order_hi: U32, distinct: U32, rng: R.Rng}

def lane(+a: U32, +b: U32, +c: U32, +d: U32, +index: U32) -> U32:
  +word = Bool.pick(U32, (index < 4 : U32), a, Bool.pick(U32, (index < 8 : U32), b, Bool.pick(U32, (index < 12 : U32), c, d)))
  ((word >> U32.to_nat(((index % 4) * 8 : U32))) .&. 255 : U32)

def with_boon(+a: U32, +b: U32, +c: U32, +d: U32, +lo: U32, +hi: U32, +distinct: U32, picked: U32 & R.Rng) -> Boons:
  (+id, s) = picked
  +index = (id - 1 : U32)
  +first = Bool.to_u32(Bool.not(U32.is_zero(id)) && U32.is_zero(lane(a, b, c, d, index)))
  +shift = (distinct * 4 : U32)
  Boons{
    S.add_boon(id, 0, a), S.add_boon(id, 4, b), S.add_boon(id, 8, c), S.add_boon(id, 12, d),
    (lo .|. (first * (index << U32.to_nat(shift) : U32) : U32) : U32),
    (hi .|. (first * (index << U32.to_nat((shift - 32 : U32)) : U32) : U32) : U32),
    (distinct + first : U32), s
  }

def boon_step(st: Boons) -> Boons:
  match st:
    case Boons{+a, +b, +c, +d, +lo, +hi, +distinct, rng}:
      with_boon(a, b, c, d, lo, hi, distinct, S.pick(C.boons(), rng))

def boon_loop(n: Nat, st: Boons) -> Boons:
  match n:
    case 0n:
      st
    case 1n+p:
      boon_loop(p, boon_step(st))

def finish_added(+trap: U32, +poi: U32, +protected: U32, st: Boons) -> Added:
  match st:
    case Boons{+a, +b, +c, +d, +lo, +hi, +distinct, rng}:
      Added{S.Pieces{trap, poi, protected, a, b, c, d}, lo, hi, distinct, rng}

def after_boon_count(+trap: U32, +poi: U32, +protected: U32, rolled: U32 & R.Rng) -> Added:
  (count, s) = rolled
  finish_added(trap, poi, protected, boon_loop(U32.to_nat((count + S.fewest_boons() : U32)), Boons{0, 0, 0, 0, 0, 0, 0, s}))

def after_protected(+trap: U32, +poi: U32, picked: U32 & R.Rng) -> Added:
  (protected, s) = picked
  after_boon_count(trap, poi, protected, S.roll_boon_count(s))

def after_poi(+trap: U32, picked: U32 & R.Rng) -> Added:
  (poi, s) = picked
  after_protected(trap, poi, S.pick(C.protected_resources(), s))

def after_trap(picked: U32 & R.Rng) -> Added:
  (trap, s) = picked
  after_poi(trap, S.pick(C.points_of_interest(), s))

def added(rng: R.Rng) -> Added:
  after_trap(S.pick(C.traps(), rng))

# level.set_pieces as a stock Lua 5.1 hash part (ltable.c): string keys only, never deleted.
# Slots 0-31 hold nodes (key id | hash mod 32 << 8, 0 = free); slot 64 + key later gets the key's
# assigned task mask. Node positions only depend on occupancy, the occupants' main positions and
# lastfree, so chain pointers are not kept.
type Table is Type:
  Table{nodes: Array<U32>, size: U32, last_free: U32, count: U32}

def mask_slot() -> U32:
  64

def node_of(+key: U32) -> U32:
  (key .|. ((K.key_info(key) .&. 31) << 8n) : U32)

def main_position(+node: U32, +size: U32) -> U32:
  ((node >> 8n) .&. (size - 1) : U32)

# getfreepos: the first free node below lastfree, or 32 when there is none.
def scan_free(n: Nat, got: Array<U32> & U32, +position: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      (nodes, occupant) = got
      match occupant:
        case 0:
          (nodes, position)
        case _:
          (nodes, 32)
    case 1n+p:
      (nodes, occupant) = got
      match occupant:
        case 0:
          (nodes, position)
        case _:
          scan_free(p, nodes[(position - 1 : U32)], (position - 1 : U32))

def find_free(nodes: Array<U32>, +last_free: U32) -> Array<U32> & U32:
  match last_free:
    case 0:
      (nodes, 32)
    case _:
      scan_free(U32.to_nat((last_free - 1 : U32)), nodes[(last_free - 1 : U32)], (last_free - 1 : U32))

def resolve(found: Array<U32> & U32, +size: U32, +count: U32, +node: U32, +mp: U32, +occupant: U32) -> Table & Bool:
  (nodes, +free) = found
  match free:
    case 32:
      (Table{nodes, size, 0, count}, False{})
    case _:
      +moves = Bool.not(U32.is_eq(main_position(occupant, size), mp))
      nodes[free] <- Bool.pick(U32, moves, occupant, node)
      nodes[mp] <- Bool.pick(U32, moves, node, occupant)
      (Table{nodes, size, free, (count + 1 : U32)}, True{})

def place_at(got: Array<U32> & U32, +size: U32, +last_free: U32, +count: U32, +node: U32, +mp: U32) -> Table & Bool:
  (nodes, +occupant) = got
  match occupant:
    case 0:
      nodes[mp] <- node
      (Table{nodes, size, last_free, (count + 1 : U32)}, True{})
    case _:
      resolve(find_free(nodes, last_free), size, count, node, mp, occupant)

# luaH_set's newkey without the rehash; False when no free node is left.
def place(t: Table, +node: U32) -> Table & Bool:
  match t:
    case Table{nodes, +size, +last_free, +count}:
      +mp = main_position(node, size)
      place_at(nodes[mp], size, last_free, count, node, mp)

def place_occupant(+occupant: U32, t: Table) -> Table:
  match occupant:
    case 0:
      t
    case _:
      Pair.fst(Table, Bool, place(t, occupant))

def reinsert(n: Nat, got: Array<U32> & U32, +position: U32, fresh: Table) -> Table:
  match n:
    case 0n:
      fresh
    case 1n+p:
      (old, +occupant) = got
      reinsert(p, old[(position - 1 : U32)], (position - 1 : U32), place_occupant(occupant, fresh))

# luaH_resize to ceil_pow2(count + 1) nodes, re-inserting old nodes from the last one down.
def rehash(t: Table) -> Table:
  match t:
    case Table{nodes, +size, _, +count}:
      +grown = Bool.pick(U32, (count < 16 : U32), 16, 32)
      reinsert(U32.to_nat(size), nodes[(size - 1 : U32)], (size - 1 : U32), Table{[0 : U32*128n], grown, grown, 0})

def retry(placed: Table & Bool, +node: U32) -> Table:
  (t, ok) = placed
  match ok:
    case True{}:
      t
    case False{}:
      Pair.fst(Table, Bool, place(rehash(t), node))

def insert(t: Table, +node: U32) -> Table:
  retry(place(t, node), node)

def insert_if(+key: U32, t: Table, +present: Bool) -> Table:
  match present:
    case True{}:
      insert(t, node_of(key))
    case False{}:
      t

# The task set's set_pieces after tasksets.GetGenTasks' deepcopy.
def base_table() -> Table:
  Table{K.base_nodes([0 : U32*128n]), 16, K.base_last_free(), K.base_count()}

def insert_boons(n: Nat, t: Table, +lo: U32, +hi: U32, +k: U32) -> Table:
  match n:
    case 0n:
      t
    case 1n+p:
      +index = P.slot(lo, hi, k)
      insert_boons(p, insert(t, node_of((K.first_boon_key() + index : U32))), lo, hi, (k + 1 : U32))

def optional_key(+first: U32, +id: U32) -> U32:
  (first + id : U32)

# level.set_pieces after AddSetPeices: trap, point of interest and protected resource, then new boons.
def level_table(+pieces: S.Pieces, +lo: U32, +hi: U32, +distinct: U32) -> Table:
  match pieces:
    case S.Pieces{+trap, +poi, +protected, _, _, _, _}:
      with_trap = insert_if(optional_key(K.first_trap_key(), trap), base_table(), Bool.not(U32.is_zero(trap)))
      with_poi = insert_if(optional_key(K.first_poi_key(), poi), with_trap, Bool.not(U32.is_zero(poi)))
      with_protected = insert_if(optional_key(K.first_protected_key(), protected), with_poi, Bool.not(U32.is_zero(protected)))
      insert_boons(U32.to_nat(distinct), with_protected, lo, hi, 0)

# ChooseSetPieces part 1: required_setpieces plus 4 random_set_pieces (codes 5 bits each, in order;
# math.random(19) returning 20 inserts nil, which drops that entry), each put in a random placeable task.
type Specials is Data:
  Specials{codes: U32, tasks: U32, count: U32, crashed: U32, rng: R.Rng}

def with_special(+codes: U32, +tasks: U32, +count: U32, +crashed: U32, rolled: U32 & R.Rng) -> Specials:
  (+r, s) = rolled
  +kept = Bool.to_u32((r < 19 : U32))
  Specials{(codes .|. (kept * ((r + 2) << U32.to_nat((count * 5 : U32)) : U32) : U32) : U32), tasks, (count + kept : U32), crashed, s}

def special_step(st: Specials) -> Specials:
  match st:
    case Specials{+codes, +tasks, +count, +crashed, rng}:
      with_special(codes, tasks, count, crashed, LR.roll(rng, 19))

def special_loop(n: Nat, st: Specials) -> Specials:
  match n:
    case 0n:
      st
    case 1n+p:
      special_loop(p, special_step(st))

def with_special_task(+lo: U32, +k: U32, +codes: U32, +tasks: U32, +count: U32, +crashed: U32, rolled: U32 & R.Rng) -> Specials:
  (+p, s) = rolled
  +task = P.placeable_task(lo, p)
  Specials{codes, (tasks .|. (task << U32.to_nat((k * 5 : U32))) : U32), count, (crashed .|. Bool.to_u32((p >= 15 : U32)) : U32), s}

def special_task_step(st: Specials, +lo: U32, +k: U32) -> Specials:
  match st:
    case Specials{+codes, +tasks, +count, +crashed, rng}:
      with_special_task(lo, k, codes, tasks, count, crashed, LR.roll(rng, 15))

def special_task_loop(n: Nat, st: Specials, +lo: U32, +k: U32) -> Specials:
  match n:
    case 0n:
      st
    case 1n+p:
      special_task_loop(p, special_task_step(st, lo, k), lo, (k + 1 : U32))

def special_tasks(st: Specials, +lo: U32) -> Specials:
  match st:
    case Specials{+codes, +tasks, +count, +crashed, rng}:
      special_task_loop(U32.to_nat(count), Specials{codes, tasks, count, crashed, rng}, lo, 0)

def specials(+lo: U32, rng: R.Rng) -> Specials:
  special_tasks(special_loop(4n, Specials{32, 0, 2, 0, rng}), lo)

def popcount(+x: U32) -> U32:
  +a = (x - ((x >> 1n) .&. 1431655765) : U32)
  +b = ((a .&. 858993459) + ((a >> 2n) .&. 858993459) : U32)
  ((((b + (b >> 4n)) .&. 252645135) * 16843009) >> 24n : U32)

def drop_lowest(n: Nat, +m: U32) -> U32:
  match n:
    case 0n:
      m
    case 1n+p:
      drop_lowest(p, (m .&. (m - 1) : U32))

def lowest(+m: U32) -> U32:
  (m .&. (0 - m) : U32)

# ChooseSetPieces part 2, per level.set_pieces entry: math.random(#choices) picks a task among the
# remaining choices (a mask over task ids, or over placeable indices for AddSetPeices entries).
type Copies is Data:
  Copies{choices: U32, tasks: U32, crashed: U32, rng: R.Rng}

def kth_bit(+k: U32, +choices: U32) -> U32:
  lowest(drop_lowest(U32.to_nat(k), choices))

def with_task_copy(+choices: U32, +tasks: U32, +crashed: U32, rolled: U32 & R.Rng) -> Copies:
  (+k, s) = rolled
  +bit = kth_bit(k, choices)
  Copies{(choices .^. bit : U32), (tasks .|. bit : U32), (crashed .|. Bool.to_u32(U32.is_zero(bit)) : U32), s}

def task_copy_step(st: Copies) -> Copies:
  match st:
    case Copies{+choices, +tasks, +crashed, rng}:
      with_task_copy(choices, tasks, crashed, LR.roll(rng, popcount(choices)))

def task_copy_loop(n: Nat, st: Copies) -> Copies:
  match n:
    case 0n:
      st
    case 1n+p:
      task_copy_loop(p, task_copy_step(st))

def with_placeable_copy(+lo: U32, +choices: U32, +tasks: U32, +crashed: U32, rolled: U32 & R.Rng) -> Copies:
  (+k, s) = rolled
  +bit = kth_bit(k, choices)
  +task = Bool.pick(U32, U32.is_zero(bit), 0, P.task_bit(P.placeable_task(lo, popcount((bit - 1 : U32)))))
  Copies{(choices .^. bit : U32), (tasks .|. task : U32), (crashed .|. Bool.to_u32(U32.is_zero(bit)) : U32), s}

def placeable_copy_step(st: Copies, +lo: U32) -> Copies:
  match st:
    case Copies{+choices, +tasks, +crashed, rng}:
      with_placeable_copy(lo, choices, tasks, crashed, LR.roll(rng, popcount(choices)))

def placeable_copy_loop(n: Nat, st: Copies, +lo: U32) -> Copies:
  match n:
    case 0n:
      st
    case 1n+p:
      placeable_copy_loop(p, placeable_copy_step(st, lo), lo)

def draws(+count: U32, +choices: U32) -> Nat:
  U32.to_nat(U32.min(count, popcount(choices)))

type Choosing is Type:
  Choosing{table: Array<U32>, crashed: U32, rng: R.Rng}

def record_tasks(+key: U32, table: Array<U32>, done: Copies) -> Choosing:
  match done:
    case Copies{_, +tasks, +crashed, rng}:
      table[(mask_slot() + key : U32)] <- tasks
      Choosing{table, crashed, rng}

def assign_fixed(+key: U32, table: Array<U32>, +crashed: U32, rng: R.Rng, +chosen: U32) -> Choosing:
  +choices = (K.fixed_tasks(key) .&. chosen : U32)
  +count = ((K.key_info(key) >> 8n) .&. 15 : U32)
  record_tasks(key, table, task_copy_loop(draws(count, choices), Copies{choices, 0, crashed, rng}))

def assign_added(+key: U32, table: Array<U32>, +crashed: U32, rng: R.Rng, +lo: U32, +pieces: S.Pieces) -> Choosing:
  +boon = (key <= K.first_trap_key() : U32)
  +count = Bool.pick(U32, boon, S.boon_count(pieces, (key - K.first_boon_key() : U32)), 1)
  +choices = P.area_choices(((K.key_info(key) >> 5n) .&. 7 : U32), lo)
  record_tasks(key, table, placeable_copy_loop(draws(count, choices), Copies{choices, 0, crashed, rng}, lo))

def assign(fixed: Bool, +key: U32, table: Array<U32>, +crashed: U32, rng: R.Rng, +chosen: U32, +lo: U32, +pieces: S.Pieces) -> Choosing:
  match fixed:
    case True{}:
      assign_fixed(key, table, crashed, rng, chosen)
    case False{}:
      assign_added(key, table, crashed, rng, lo, pieces)

def entry_at(got: Array<U32> & U32, +crashed: U32, rng: R.Rng, +chosen: U32, +lo: U32, +pieces: S.Pieces) -> Choosing:
  (table, +node) = got
  match node:
    case 0:
      Choosing{table, crashed, rng}
    case _:
      assign(((node .&. 63) < K.first_boon_key() : U32), (node .&. 63 : U32), table, crashed, rng, chosen, lo, pieces)

def entry_step(st: Choosing, +position: U32, +chosen: U32, +lo: U32, +pieces: S.Pieces) -> Choosing:
  match st:
    case Choosing{table, +crashed, rng}:
      entry_at(table[position], crashed, rng, chosen, lo, pieces)

def entry_loop(n: Nat, st: Choosing, +position: U32, +chosen: U32, +lo: U32, +pieces: S.Pieces) -> Choosing:
  match n:
    case 0n:
      st
    case 1n+p:
      entry_loop(p, entry_step(st, position, chosen, lo, pieces), (position + 1 : U32), chosen, lo, pieces)

# The level table of a seed. table holds the final level.set_pieces nodes (slots below size, in
# pairs() order) and each key's task mask at mask_slot() + key; special_* are the random set pieces.
# crashed: the game's worldgen would raise a Lua error (math.random(n) returned n + 1).
type World is Type:
  World{
    swaps: U32, lo: U32, chosen: U32, pieces: S.Pieces, table: Array<U32>, size: U32,
    special_codes: U32, special_tasks: U32, special_count: U32, crashed: Bool
  }

def finish_world(+swaps: U32, +lo: U32, +chosen: U32, +pieces: S.Pieces, +size: U32, sp: Specials, done: Choosing) -> World:
  match sp done:
    case Specials{+codes, +tasks, +count, +special_crashed, _} Choosing{table, +crashed, _}:
      +failed = Bool.not(U32.is_zero((crashed .|. special_crashed : U32))) || P.has_nil_task(lo)
      World{swaps, lo, chosen, pieces, table, size, codes, tasks, count, failed}

def choose_entries(+swaps: U32, +lo: U32, +chosen: U32, +pieces: S.Pieces, +size: U32, nodes: Array<U32>, sp: Specials) -> World:
  match sp:
    case Specials{+codes, +tasks, +count, +crashed, rng}:
      finish_world(swaps, lo, chosen, pieces, size, Specials{codes, tasks, count, crashed, R.Rng{0, 0}},
        entry_loop(U32.to_nat(size), Choosing{nodes, 0, rng}, 0, chosen, lo, pieces))

def choose_in(+swaps: U32, +lo: U32, +chosen: U32, +pieces: S.Pieces, t: Table, sp: Specials) -> World:
  match t:
    case Table{nodes, +size, _, _}:
      choose_entries(swaps, lo, chosen, pieces, size, nodes, sp)

# Level:ChooseSetPieces on the table left by AddSetPeices.
def choose(+swaps: U32, +lo: U32, +chosen: U32, a: Added) -> World:
  match a:
    case Added{+pieces, +order_lo, +order_hi, +distinct, rng}:
      choose_in(swaps, lo, chosen, pieces, level_table(pieces, order_lo, order_hi, distinct), specials(lo, rng))

def world_of(p: P.Prefix) -> World:
  match p:
    case P.Prefix{+swaps, +lo, _, rng}:
      choose(swaps, lo, P.chosen_tasks(lo), added(rng))

def world(+seed: U32) -> World:
  world_of(P.prefix(seed))


def choosing_rng(done: Choosing) -> R.Rng:
  match done:
    case Choosing{_, _, rng}:
      rng

def rng_entries(+lo: U32, +chosen: U32, +pieces: S.Pieces, +size: U32, nodes: Array<U32>, sp: Specials) -> R.Rng:
  match sp:
    case Specials{_, _, _, _, rng}:
      choosing_rng(entry_loop(U32.to_nat(size), Choosing{nodes, 0, rng}, 0, chosen, lo, pieces))

def rng_in(+lo: U32, +chosen: U32, +pieces: S.Pieces, t: Table, sp: Specials) -> R.Rng:
  match t:
    case Table{nodes, +size, _, _}:
      rng_entries(lo, chosen, pieces, size, nodes, sp)

def rng_after(+lo: U32, +chosen: U32, a: Added) -> R.Rng:
  match a:
    case Added{+pieces, +order_lo, +order_hi, +distinct, rng}:
      rng_in(lo, chosen, pieces, level_table(pieces, order_lo, order_hi, distinct), specials(lo, rng))

def rng_of_prefix(p: P.Prefix) -> R.Rng:
  match p:
    case P.Prefix{_, +lo, _, rng}:
      rng_after(lo, P.chosen_tasks(lo), added(rng))

# The RNG right after Level:ChooseSetPieces, i.e. at forest_map.Generate's first attempt.
def generate_rng(+seed: U32) -> R.Rng:
  rng_of_prefix(P.prefix(seed))
