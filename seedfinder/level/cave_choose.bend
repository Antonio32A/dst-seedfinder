import Base
import ../rng/pcg.bend as Pcg
import ../rng/lua_random.bend as LuaRandom
import ../data/catalog.bend as Catalog
import ../data/cave_catalog.bend as CaveCatalog
import ./setpieces.bend as LevelSetpieces
import ./cave_prefix.bend as CavePrefix

# AddSetPeices and Level:ChooseSetPieces for DST_CAVE. Set piece keys are data/cave_catalog.bend key ids (0: none).

# level.set_pieces as a stock Lua 5.1 hash part (ltable.c): string keys only, never deleted. `nodes` holds the key of
# each node (0 = free); node positions only depend on occupancy, the occupants' main positions and lastfree, so chain
# pointers are not kept.
type Table is Type:
  Table{nodes: Array<U32>, size: U32, last_free: U32, count: U32}

def main_position(+key: U32, +size: U32) -> U32:
  (CaveCatalog.key_hash(key) .&. (size - 1) : U32)

# getfreepos: the first free node below lastfree, or table_slots() when there is none.
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

def resolve(found: Array<U32> & U32, +size: U32, +count: U32, +key: U32, +mp: U32, +occupant: U32) -> Table & Bool:
  (nodes, +free) = found
  match free:
    case 32:
      (Table{nodes, size, 0, count}, False{})
    case _:
      +moves = Bool.not(U32.is_eq(main_position(occupant, size), mp))
      nodes[free] <- Bool.pick(U32, moves, occupant, key)
      nodes[mp] <- Bool.pick(U32, moves, key, occupant)
      (Table{nodes, size, free, (count + 1 : U32)}, True{})

def place_at(got: Array<U32> & U32, +size: U32, +last_free: U32, +count: U32, +key: U32, +mp: U32) -> Table & Bool:
  (nodes, +occupant) = got
  match occupant:
    case 0:
      nodes[mp] <- key
      (Table{nodes, size, last_free, (count + 1 : U32)}, True{})
    case _:
      resolve(find_free(nodes, last_free), size, count, key, mp, occupant)

# luaH_set's newkey without the rehash; False when no free node is left.
def place(t: Table, +key: U32) -> Table & Bool:
  match t:
    case Table{nodes, +size, +last_free, +count}:
      +mp = main_position(key, size)
      place_at(nodes[mp], size, last_free, count, key, mp)

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

def at_least_pow2(+n: U32) -> U32:
  Bool.pick(U32, (n <= 1 : U32), 1, Bool.pick(U32, (n <= 2 : U32), 2, Bool.pick(U32, (n <= 4 : U32), 4,
    Bool.pick(U32, (n <= 8 : U32), 8, Bool.pick(U32, (n <= 16 : U32), 16, 32)))))

# luaH_resize to ceil_pow2(count + 1) nodes, re-inserting old nodes from the last one down.
def rehash(t: Table) -> Table:
  match t:
    case Table{nodes, +size, _, +count}:
      +grown = at_least_pow2((count + 1 : U32))
      reinsert(U32.to_nat(size), nodes[(size - 1 : U32)], (size - 1 : U32), Table{[0 : U32*32n], grown, grown, 0})

def retry(placed: Table & Bool, +key: U32) -> Table:
  (t, ok) = placed
  match ok:
    case True{}:
      t
    case False{}:
      Pair.fst(Table, Bool, place(rehash(t), key))

def insert(t: Table, +key: U32) -> Table:
  retry(place(t, key), key)

def insert_if(+key: U32, t: Table, first: Bool) -> Table:
  match first:
    case True{}:
      insert(t, key)
    case False{}:
      t

# The task set's set_pieces after tasksets.GetGenTasks' deepcopy.
def base_table() -> Table:
  Table{CaveCatalog.base_nodes([0 : U32*32n]), CaveCatalog.base_size(), CaveCatalog.base_last_free(), CaveCatalog.base_count()}

# AddSetPeices: the keys added to level.set_pieces, how many times, and for which area (the area code of the last
# add, which decides the tasks to choose from).
type Adding is Type:
  Adding{table: Table, counts: Array<U32>, areas: Array<U32>, rng: Pcg.Rng}

def sandbox_of(+kind: U32) -> Catalog.Sandbox:
  Bool.pick(Catalog.Sandbox, U32.is_eq(kind, 0), CaveCatalog.traps(),
    Bool.pick(Catalog.Sandbox, U32.is_eq(kind, 1), CaveCatalog.points_of_interest(),
      Bool.pick(Catalog.Sandbox, U32.is_eq(kind, 2), CaveCatalog.protected_resources(), CaveCatalog.boons())))

def info_of(+kind: U32, +id: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, 0), CaveCatalog.traps_info(id),
    Bool.pick(U32, U32.is_eq(kind, 1), CaveCatalog.points_of_interest_info(id),
      Bool.pick(U32, U32.is_eq(kind, 2), CaveCatalog.protected_resources_info(id), CaveCatalog.boons_info(id))))

def area_present(+areas: U32, +area: U32) -> Bool:
  U32.is_zero(area) || Bool.not(U32.is_zero(((areas >> U32.to_nat(area)) .&. 1 : U32)))

def counted(+key: U32, +area: U32, table: Table, got: Array<U32> & U32, areas: Array<U32>, rng: Pcg.Rng) -> Adding:
  (counts, +before) = got
  counts[key] <- (before + 1 : U32)
  areas[key] <- area
  Adding{insert_if(key, table, U32.is_zero(before)), counts, areas, rng}

def add_key(+key: U32, +area: U32, st: Adding) -> Adding:
  match st:
    case Adding{table, counts, areas, rng}:
      counted(key, area, table, counts[key], areas, rng)

def add_when(applies: Bool, +key: U32, +area: U32, st: Adding) -> Adding:
  match applies:
    case True{}:
      add_key(key, area, st)
    case False{}:
      st

def add_info(+info: U32, +present: U32, st: Adding) -> Adding:
  +key = (info .&. 255 : U32)
  +area = (info >> 8n : U32)
  add_when(Bool.not(U32.is_zero(key)) && area_present(present, area), key, area, st)

def picked_add(+kind: U32, +present: U32, picked: U32 & Pcg.Rng, table: Table, counts: Array<U32>, areas: Array<U32>) -> Adding:
  (+id, s) = picked
  add_info(info_of(kind, id), present, Adding{table, counts, areas, s})

def pick_add(+kind: U32, +present: U32, st: Adding) -> Adding:
  match st:
    case Adding{table, counts, areas, rng}:
      picked_add(kind, present, LevelSetpieces.pick(sandbox_of(kind), rng), table, counts, areas)

def trap_kind() -> U32:
  0

def poi_kind() -> U32:
  1

def protected_kind() -> U32:
  2

def boon_kind() -> U32:
  3

def boon_loop(n: Nat, +present: U32, st: Adding) -> Adding:
  match n:
    case 0n:
      st
    case 1n+p:
      boon_loop(p, present, pick_add(boon_kind(), present, st))

def with_boon_count(+present: U32, rolled: U32 & Pcg.Rng, table: Table, counts: Array<U32>, areas: Array<U32>) -> Adding:
  (count, s) = rolled
  boon_loop(U32.to_nat((count + LevelSetpieces.fewest_boons() : U32)), present, Adding{table, counts, areas, s})

def with_boons(+present: U32, st: Adding) -> Adding:
  match st:
    case Adding{table, counts, areas, rng}:
      with_boon_count(present, LevelSetpieces.roll_boon_count(rng), table, counts, areas)

# AddSetPeices: one trap, one point of interest, one protected resource and 3-8 boons, each added when a chosen task
# can host it; `present` holds the area codes of the chosen tasks.
def added(+present: U32, rng: Pcg.Rng) -> Adding:
  with_boons(present, pick_add(protected_kind(), present, pick_add(poi_kind(), present, pick_add(trap_kind(), present,
    Adding{base_table(), [0 : U32*64n], [0 : U32*64n], rng}))))

# A key of level.set_pieces in pairs() order: how often it is placed and its area code.
type Entry is Data:
  Entry{key: U32, count: U32, area: U32}

type Walk is Type:
  Walk{nodes: Array<U32>, counts: Array<U32>, areas: Array<U32>, entries: List<&2, Entry>}

def listed(+key: U32, +count: U32, +area: U32, +entries: List<&2, Entry>) -> List<&2, Entry>:
  +fixed = CaveCatalog.key_count_of(key)
  Bool.pick(List<&2, Entry>, U32.is_zero(key), entries, Entry{key, Bool.pick(U32, U32.is_zero(fixed), count, fixed), area} <> entries)

def walk_area(+key: U32, +count: U32, nodes: Array<U32>, counts: Array<U32>, got: Array<U32> & U32, entries: List<&2, Entry>) -> Walk:
  (areas, +area) = got
  Walk{nodes, counts, areas, listed(key, count, area, entries)}

def walk_count(+key: U32, nodes: Array<U32>, got: Array<U32> & U32, areas: Array<U32>, entries: List<&2, Entry>) -> Walk:
  (counts, +count) = got
  walk_area(key, count, nodes, counts, areas[key], entries)

def walk_node(got: Array<U32> & U32, counts: Array<U32>, areas: Array<U32>, entries: List<&2, Entry>) -> Walk:
  (nodes, +key) = got
  walk_count(key, nodes, counts[key], areas, entries)

def walk_step(w: Walk, +position: U32) -> Walk:
  match w:
    case Walk{nodes, counts, areas, entries}:
      walk_node(nodes[position], counts, areas, entries)

def walk_loop(n: Nat, w: Walk, +position: U32) -> Walk:
  match n:
    case 0n:
      w
    case 1n+p:
      walk_loop(p, walk_step(w, position), (position + 1 : U32))

def walked(w: Walk) -> List<&2, Entry>:
  match w:
    case Walk{nodes, counts, areas, entries}:
      List.reverse(&2, Entry, entries)

# level.set_pieces in pairs() order after AddSetPeices, and the PCG32 state there.
type Added is Data:
  Added{entries: List<&2, Entry>, rng: Pcg.Rng}

def added_from(a: Adding) -> Added:
  match a:
    case Adding{Table{nodes, +size, _, _}, counts, areas, rng}:
      Added{walked(walk_loop(U32.to_nat(size), Walk{nodes, counts, areas, Nil{}}, 0)), rng}

def added_of(c: CavePrefix.Chosen) -> Added:
  match c:
    case CavePrefix.Chosen{_, _, CavePrefix.Masks{_, _, +areas, _}, rng}:
      added_from(added(areas, rng))

def entries_added(a: Added) -> List<&2, Entry>:
  match a:
    case Added{entries, _}:
      entries

# The level.set_pieces entries a chosen set of tasks ends up with after AddSetPeices, in pairs() order.
def added_entries(c: CavePrefix.Chosen) -> List<&2, Entry>:
  entries_added(added_of(c))

# Where a set piece went: the tasks (two words, as CavePrefix's masks) that got a copy of it.
type Placed is Data:
  Placed{key: U32, lo: U32, hi: U32}

# How many copies of a key AddSetPeices asks for (0: it was not added).
def count_of(entries: List<&2, Entry>, +key: U32) -> U32:
  match entries:
    case Nil{}:
      0
    case Con{Entry{+added, +count, _}, rest}:
      Bool.pick(U32, U32.is_eq(added, key), count, count_of(rest, key))

def no_task() -> U32:
  4294967295

def filter_chosen(tasks: List<&2, U32>, +lo: U32, +hi: U32) -> List<&2, U32>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+task, rest}:
      +tail = filter_chosen(rest, lo, hi)
      Bool.pick(List<&2, U32>, CavePrefix.is_chosen(lo, hi, task), task <> tail, tail)

def filter_area(tasks: List<&2, U32>, +area: U32) -> List<&2, U32>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+task, rest}:
      +tail = filter_area(rest, area)
      Bool.pick(List<&2, U32>, U32.is_zero(area) || U32.is_eq(CaveCatalog.task_area(task), area), task <> tail, tail)

# table.remove(choices, idx_choice): the task at index r (no_task() past the end) and the list without it; `kept`
# holds the items before it, reversed.
def take_at(items: List<&2, U32>, +r: U32, kept: List<&2, U32>) -> U32 & List<&2, U32>:
  match items r:
    case Nil{} _:
      (no_task(), List.reverse(&2, U32, kept))
    case Con{+head, tail} 0:
      (head, List.append(&2, U32, List.reverse(&2, U32, kept), tail))
    case Con{+head, tail} _:
      take_at(tail, (r - 1 : U32), head <> kept)

# The copies of one set piece handed out so far: the tasks that have one, the tasks left to choose from, and whether
# math.random(#choices) ran past the end (the game then indexes nil and fails).
type Drawing is Data:
  Drawing{items: List<&2, U32>, lo: U32, hi: U32, rng: Pcg.Rng, crashed: Bool}

def drawn_task(got: U32 & List<&2, U32>, +lo: U32, +hi: U32, +crashed: Bool, rng: Pcg.Rng) -> Drawing:
  (+task, rest) = got
  +none = U32.is_eq(task, no_task())
  Drawing{rest, Bool.pick(U32, none, lo, (lo .|. CavePrefix.task_bit_lo(task) : U32)),
    Bool.pick(U32, none, hi, (hi .|. CavePrefix.task_bit_hi(task) : U32)), rng, crashed || none}

def drawn(rolled: U32 & Pcg.Rng, +items: List<&2, U32>, +lo: U32, +hi: U32, +crashed: Bool) -> Drawing:
  (+r, s) = rolled
  drawn_task(take_at(items, r, Nil{}), lo, hi, crashed, s)

def draw_sized(empty: Bool, +size: U32, items: List<&2, U32>, +lo: U32, +hi: U32, rng: Pcg.Rng, +crashed: Bool) -> Drawing:
  match empty:
    case True{}:
      Drawing{items, lo, hi, rng, crashed}
    case False{}:
      drawn(LuaRandom.roll(rng, size), items, lo, hi, crashed)

def draw_step(d: Drawing) -> Drawing:
  match d:
    case Drawing{+items, +lo, +hi, rng, +crashed}:
      +size = U32.from_nat(List.length(&2, U32, items))
      draw_sized(U32.is_zero(size), size, items, lo, hi, rng, crashed)

def draw_loop(n: Nat, d: Drawing) -> Drawing:
  match n:
    case 0n:
      d
    case 1n+p:
      draw_loop(p, draw_step(d))

# The tasks a key may go to: the task set's list restricted to the chosen tasks, or the chosen tasks whose area matches.
def choices_of(+e: Entry, +lo: U32, +hi: U32, chosen_order: List<&2, U32>) -> List<&2, U32>:
  match e:
    case Entry{+key, _, +area}:
      Bool.pick(List<&2, U32>, U32.is_zero(CaveCatalog.key_count_of(key)), filter_area(chosen_order, area),
        filter_chosen(CaveCatalog.fixed_tasks(key), lo, hi))

type Choosing is Data:
  Choosing{placed: List<&2, Placed>, rng: Pcg.Rng, crashed: Bool}

def placed_by(+key: U32, done: Drawing, placed: List<&2, Placed>) -> Choosing:
  match done:
    case Drawing{_, +lo, +hi, rng, +crashed}:
      Choosing{Placed{key, lo, hi} <> placed, rng, crashed}

def entry_step(st: Choosing, +e: Entry, +lo: U32, +hi: U32, chosen_order: List<&2, U32>) -> Choosing:
  match st:
    case Choosing{placed, rng, +crashed}:
      match e:
        case Entry{+key, +count, _}:
          +items = choices_of(e, lo, hi, chosen_order)
          placed_by(key, draw_loop(U32.to_nat(count), Drawing{items, 0, 0, rng, crashed || List.is_empty(&2, U32, items)}), placed)

def entry_loop(entries: List<&2, Entry>, st: Choosing, +lo: U32, +hi: U32, +chosen_order: List<&2, U32>) -> Choosing:
  match entries:
    case Nil{}:
      st
    case Con{+e, rest}:
      entry_loop(rest, entry_step(st, e, lo, hi, chosen_order), lo, hi, chosen_order)

# The caves level table of a seed: the prefab swaps, the picked optional tasks (indices, in chosen order), where each
# set piece went (in pairs() order of level.set_pieces) and whether the game's worldgen would raise a Lua error.
type World is Data:
  World{swaps: U32, picks: List<&2, U32>, placed: List<&2, Placed>, crashed: Bool}

def placed_world(+swaps: U32, +picks: List<&2, U32>, done: Choosing) -> World:
  match done:
    case Choosing{+placed, _, +crashed}:
      World{swaps, picks, List.reverse(&2, Placed, placed), crashed}

def world_of(+swaps: U32, +picks: List<&2, U32>, +lo: U32, +hi: U32, entries: List<&2, Entry>, rng: Pcg.Rng) -> World:
  placed_world(swaps, picks, entry_loop(entries, Choosing{Nil{}, rng, False{}}, lo, hi, CavePrefix.chosen_ids(picks)))

def choose_added(a: Added, +swaps: U32, +picks: List<&2, U32>, +lo: U32, +hi: U32) -> World:
  match a:
    case Added{entries, rng}:
      world_of(swaps, picks, lo, hi, entries, rng)

# Level:ChooseSetPieces on what AddSetPeices left.
def choose_from(c: CavePrefix.Chosen, a: Added) -> World:
  match c:
    case CavePrefix.Chosen{+swaps, +picks, CavePrefix.Masks{+lo, +hi, _, +crashed}, _}:
      Bool.pick(World, crashed, World{swaps, picks, Nil{}, True{}}, choose_added(a, swaps, picks, lo, hi))

# AddSetPeices and Level:ChooseSetPieces on the chosen tasks.
def choose(+c: CavePrefix.Chosen) -> World:
  choose_from(c, added_of(c))

def world(+seed: U32) -> World:
  choose(CavePrefix.chosen(seed))
