import Base
import ../data/blob.bend as B
import ../data/rooms.bend as RM
import ../data/tasks.bend as TK
import ../data/story.bend as SY
import ../data/enums.bend as EN
import ./graph.bend as GG
import ./order.bend as GO
import ./nodes.bend as GN
import ./background.bend as GB

# Story:GenerateNodesForRegion with its two layout modes, LinkNodesByKeys (mainland) and RestrictNodesByKey (the moon
# island), Story:_FindStartingTask, Story:GetRandomNodeFromTasks and Story:_AddPlayerStartNode. Task tables keyed by
# task id (task_nodes / unusedTasks, usedTasks, unlockingNodes, candidateTasks) are replayed from their insertion
# and deletion history (lua/table.bend) whenever they are traversed.

def locks(+task: U32) -> List<&2, U32>:
  B.drop(TK.task_locks(task), 1)

def keys_given(+task: U32) -> List<&2, U32>:
  B.drop(TK.task_keys_given(task), 1)

def lock_keys(+lock: U32) -> List<&2, U32>:
  B.drop(TK.locks_keys(lock), 1)

def task_of(+s: GG.St, +g: U32) -> U32:
  GG.gf(s, g, GG.g_part())

def unused_order(+s: GG.St, +inserted: List<&2, U32>, +removed: List<&2, U32>) -> List<&2, U32>:
  GO.order_after(GG.graph_slots(s, inserted), GG.graph_slots(s, removed))

def any_in(xs: List<&2, U32>, +set: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, rest}:
      GO.contains(set, x) || any_in(rest, set)

def all_unlocked(ls: List<&2, U32>, +keys: List<&2, U32>) -> Bool:
  match ls:
    case Nil{}:
      True{}
    case Con{+lock, rest}:
      any_in(lock_keys(lock), keys) && all_unlocked(rest, keys)

# key << 8 | graph entries: the task graphs holding each available key, in insertion order.
def holders_of(holders: List<&2, U32>, +key: U32) -> List<&2, U32>:
  match holders:
    case Nil{}:
      Nil{}
    case Con{+h, rest}:
      +tail = holders_of(rest, key)
      Bool.pick(List<&2, U32>, U32.is_eq((h >> 8n : U32), key), (h .&. 255 : U32) <> tail, tail)

def matching_holders(reqs: List<&2, U32>, +key: U32, +holders: List<&2, U32>) -> List<&2, U32>:
  match reqs:
    case Nil{}:
      Nil{}
    case Con{+req, rest}:
      +tail = matching_holders(rest, key, holders)
      Bool.pick(List<&2, U32>, U32.is_eq(req, key), List.append(&2, U32, holders_of(holders, key), tail), tail)

def lock_holders(+lock: U32, keys: List<&2, U32>, +holders: List<&2, U32>) -> List<&2, U32>:
  match keys:
    case Nil{}:
      Nil{}
    case Con{+key, rest}:
      List.append(&2, U32, matching_holders(lock_keys(lock), key, holders), lock_holders(lock, rest, holders))

def unlocking_inserts(ls: List<&2, U32>, +keys: List<&2, U32>, +holders: List<&2, U32>) -> List<&2, U32>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{+lock, rest}:
      List.append(&2, U32, lock_holders(lock, keys, holders), unlocking_inserts(rest, keys, holders))

# LinkNodesByKeys' search: the first task of `tasks` whose locks are all opened by the available keys, followed by its
# unlockingNodes in pairs() order; empty when none is.
def lock_order_of(+s: GG.St, +g: U32) -> List<&2, U32>:
  GO.int_order(locks(task_of(s, g)))

def unlocked_task(tasks: List<&2, U32>, done: Bool, +s: GG.St, +keys: List<&2, U32>, +found: U32) -> U32:
  match tasks:
    case Nil{}:
      found
    case Con{+g, rest}:
      match done:
        case True{}:
          found
        case False{}:
          +hit = all_unlocked(lock_order_of(s, g), keys)
          unlocked_task(rest, hit, s, keys, Bool.pick(U32, hit, g, GG.none()))

def unlocked_list(none: Bool, +g: U32, +s: GG.St, +keys: List<&2, U32>, +holders: List<&2, U32>) -> List<&2, U32>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      g <> GG.graph_table_order(s, unlocking_inserts(lock_order_of(s, g), keys, holders))

def first_unlocked(tasks: List<&2, U32>, +s: GG.St, +keys: List<&2, U32>, +holders: List<&2, U32>) -> List<&2, U32>:
  +g = unlocked_task(tasks, False{}, s, keys, GG.none())
  unlocked_list(U32.is_eq(g, GG.none()), g, s, keys, holders)

# GetRandomItem / GetRandomNodeFromTasks over a pairs() order: math.random(n), clamped to the last entry.
def random_item(+s: GG.St, +order: List<&2, U32>) -> GG.Got:
  +d = GG.upto(s, GO.count(order, 0))
  GG.Got{GO.nth_or_last(order, (GG.val(d) - 1 : U32), GG.none()), GG.st(d)}

def entrance_picked(random: Bool, +s: GG.St, +g: U32, +fixed: U32) -> GG.Got:
  match random:
    case True{}:
      GN.entrance_node(s, g)
    case False{}:
      GG.Got{fixed, s}

def entrance_or_random(+s: GG.St, +g: U32) -> GG.Got:
  +fixed = GG.gf(s, g, GG.g_entrance())
  entrance_picked(U32.is_eq(fixed, GG.none()), s, g, fixed)

# The LockGraph edge of a new connection: the parent's exit node to the task's entrance node.
def connected(+s: GG.St, +parent: U32, +current: U32, +depth: U32) -> GG.St:
  +exit = GN.exit_node(GG.set_gf(s, current, GG.g_depth(), depth), parent)
  +entrance = entrance_or_random(GG.st(exit), current)
  GG.lock(GG.st(entrance), GG.val(exit), GG.val(entrance))

def new_keys(given: List<&2, U32>, +keys: List<&2, U32>) -> List<&2, U32>:
  match given:
    case Nil{}:
      keys
    case Con{+k, rest}:
      new_keys(rest, Bool.pick(List<&2, U32>, GO.contains(keys, k), keys, List.append(&2, U32, keys, [k])))

def new_holders(given: List<&2, U32>, +holders: List<&2, U32>, +g: U32) -> List<&2, U32>:
  match given:
    case Nil{}:
      holders
    case Con{+k, rest}:
      new_holders(rest, List.append(&2, U32, holders, [((k << 8n) .|. g : U32)]), g)

type Linking is Data:
  Linking{st: GG.St, inserted: List<&2, U32>, removed: List<&2, U32>, keys: List<&2, U32>, holders: List<&2, U32>, last: U32, depth: U32}

def linked(+l: Linking, +parent: U32, +current: U32, +s: GG.St) -> Linking:
  match l:
    case Linking{_, +inserted, +removed, +keys, +holders, _, +depth}:
      +given = keys_given(task_of(s, current))
      Linking{connected(s, parent, current, depth), inserted, List.append(&2, U32, removed, [current]), new_keys(given, keys),
        new_holders(given, holders, current), current, (depth + 1 : U32)}

def link_random(+l: Linking, +s: GG.St, +order: List<&2, U32>, +last: U32) -> Linking:
  +picked = random_item(s, order)
  linked(l, last, GG.val(picked), GG.st(picked))

def link_unlocked(found: List<&2, U32>, +l: Linking, +s: GG.St, +order: List<&2, U32>, +last: U32) -> Linking:
  match found:
    case Nil{}:
      link_random(l, s, order, last)
    case Con{+current, parents}:
      +parent = random_item(s, parents)
      linked(l, GG.val(parent), current, GG.st(parent))

def link_step(+l: Linking) -> Linking:
  match l:
    case Linking{+s, +inserted, +removed, +keys, +holders, +last, _}:
      +order = unused_order(s, inserted, removed)
      link_unlocked(first_unlocked(order, s, GO.int_order(keys), holders), l, s, order, last)

def link_loop(n: Nat, +l: Linking) -> Linking:
  match n:
    case 0n:
      l
    case 1n+p:
      link_loop(p, link_step(l))

def final_exit(+l: Linking) -> GG.Got:
  match l:
    case Linking{+s, _, _, _, _, +last, _}:
      GN.exit_node(s, last)

# Story:LinkNodesByKeys(start, unused): returns lastNode:GetRandomNodeForExit().
def link_by_keys(+s: GG.St, +start: U32, +inserted: List<&2, U32>) -> GG.Got:
  +given = keys_given(task_of(s, start))
  final_exit(link_loop(U32.to_nat((GO.count(inserted, 0) - 1 : U32)),
    Linking{GG.set_gf(s, start, GG.g_depth(), 0), inserted, [start], new_keys(given, Nil{}), new_holders(given, Nil{}, start), start, 1}))

def opens(+task: U32, +target: U32) -> Bool:
  all_unlocked(locks(task), keys_given(target))

def attach_nodes(+task: U32, +s: GG.St, used: List<&2, U32>) -> List<&2, U32>:
  match used:
    case Nil{}:
      Nil{}
    case Con{+target, rest}:
      +tail = attach_nodes(task, s, rest)
      Bool.pick(List<&2, U32>, opens(task, task_of(s, target)), target <> tail, tail)

type Restricting is Data:
  Restricting{st: GG.St, used: List<&2, U32>, inserted: List<&2, U32>, removed: List<&2, U32>, parent: U32, depth: U32, last: U32}

def appended(+r: Restricting, +current: U32, +parents: List<&2, U32>) -> Restricting:
  match r:
    case Restricting{+s, +used, +inserted, +removed, +parent, +depth, _}:
      +turn = (((parent - 1 : U32) % GO.count(parents, 0)) + 1 : U32)
      +chosen = GO.nth_or_last(parents, (turn - 1 : U32), GG.none())
      Restricting{connected(s, chosen, current, depth), List.append(&2, U32, used, [current]), inserted,
        List.append(&2, U32, removed, [current]), (turn + 1 : U32), (depth + 1 : U32), current}

def used_order_of(+r: Restricting) -> List<&2, U32>:
  match r:
    case Restricting{+s, +used, _, _, _, _, _}:
      GG.graph_table_order(s, used)

def st_of(+r: Restricting) -> GG.St:
  match r:
    case Restricting{+s, _, _, _, _, _, _}:
      s

def with_st(+r: Restricting, +s: GG.St) -> Restricting:
  match r:
    case Restricting{_, +used, +inserted, +removed, +parent, +depth, +last}:
      Restricting{s, used, inserted, removed, parent, depth, last}

type Candidate is Data:
  Candidate{task: U32, parents: List<&2, U32>}

def candidates(tasks: List<&2, U32>, +s: GG.St, +used: List<&2, U32>) -> List<&2, Candidate>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      +tail = candidates(rest, s, used)
      +parents = attach_nodes(task_of(s, g), s, used)
      Bool.pick(List<&2, Candidate>, List.is_empty(&2, U32, parents), tail, Candidate{g, GG.graph_table_order(s, parents)} <> tail)

def candidate_tasks(cs: List<&2, Candidate>) -> List<&2, U32>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      match c:
        case Candidate{+task, _}:
          task <> candidate_tasks(rest)

def parents_of(cs: List<&2, Candidate>, +task: U32) -> List<&2, U32>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      match c:
        case Candidate{+t, +parents}:
          Bool.pick(List<&2, U32>, U32.is_eq(t, task), parents, parents_of(rest, task))

def append_all(order: List<&2, U32>, +r: Restricting, +cs: List<&2, Candidate>) -> Restricting:
  match order:
    case Nil{}:
      r
    case Con{+task, rest}:
      append_all(rest, appended(r, task, parents_of(cs, task)), cs)

def append_any(+cs: List<&2, Candidate>, +r: Restricting, +order: List<&2, U32>) -> Restricting:
  match cs:
    case Nil{}:
      +picked = random_item(st_of(r), order)
      appended(with_st(r, GG.st(picked)), GG.val(picked), used_order_of(r))
    case Con{_, _}:
      append_all(GG.graph_table_order(st_of(r), candidate_tasks(cs)), r, cs)

def restrict_step(+r: Restricting) -> Restricting:
  match r:
    case Restricting{+s, _, +inserted, +removed, _, _, _}:
      +order = unused_order(s, inserted, removed)
      append_any(candidates(order, s, used_order_of(r)), r, order)

def remaining(+r: Restricting) -> U32:
  match r:
    case Restricting{_, _, +inserted, +removed, _, _, _}:
      (GO.count(inserted, 0) - GO.count(removed, 0) : U32)

def restrict_loop(n: Nat, done: Bool, +r: Restricting) -> Restricting:
  match n:
    case 0n:
      r
    case 1n+p:
      match done:
        case True{}:
          r
        case False{}:
          +next = restrict_step(r)
          restrict_loop(p, U32.is_zero(remaining(next)), next)

def last_exit(+r: Restricting) -> GG.Got:
  match r:
    case Restricting{+s, _, _, _, _, _, +last}:
      GN.exit_node(s, last)

# Story:RestrictNodesByKey(start, unused): each round appends every unlockable task, cycling through its parents.
def restrict_by_key(+s: GG.St, +start: U32, +inserted: List<&2, U32>) -> GG.Got:
  last_exit(restrict_loop(U32.to_nat(GO.count(inserted, 0)), U32.is_eq(GO.count(inserted, 0), 1),
    Restricting{GG.set_gf(s, start, GG.g_depth(), 0), [start], inserted, [start], 1, 1, start}))

def is_start_task(+s: GG.St, +g: U32) -> Bool:
  +row = TK.task_locks(task_of(s, g))
  U32.is_zero(B.at(row, 0)) || U32.is_eq(B.at(row, 1), EN.lock_none())

def start_tasks(order: List<&2, U32>, +s: GG.St) -> List<&2, U32>:
  match order:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      +tail = start_tasks(rest, s)
      Bool.pick(List<&2, U32>, is_start_task(s, g), g <> tail, tail)

def start_within(inside: Bool, +k: U32, +s: GG.St, +starts: List<&2, U32>, +order: List<&2, U32>) -> GG.Got:
  match inside:
    case True{}:
      GG.Got{GO.nth_or_last(starts, (k - 1 : U32), GG.none()), s}
    case False{}:
      random_item(s, order)

def start_picked(+d: GG.Got, +starts: List<&2, U32>, +order: List<&2, U32>) -> GG.Got:
  +k = GG.val(d)
  start_within((k <= GO.count(starts, 0) : U32), k, GG.st(d), starts, order)

def start_of(empty: Bool, +s: GG.St, +starts: List<&2, U32>, +order: List<&2, U32>) -> GG.Got:
  match empty:
    case True{}:
      random_item(s, order)
    case False{}:
      start_picked(GG.upto(s, GO.count(starts, 0)), starts, order)

# Story:_FindStartingTask: startTasks[math.random(#startTasks)], or GetRandomItem(task_nodes) when that is nil.
def find_starting_task(+s: GG.St, +order: List<&2, U32>) -> GG.Got:
  +starts = start_tasks(order, s)
  start_of(List.is_empty(&2, U32, starts), s, starts, order)

type Region is Data:
  Region{st: GG.St, start: U32, entrance: U32, final: U32}

def region_st(+r: Region) -> GG.St:
  match r:
    case Region{+s, _, _, _}:
      s

def region_start(+r: Region) -> U32:
  match r:
    case Region{_, +start, _, _}:
      start

def region_entrance(+r: Region) -> U32:
  match r:
    case Region{_, _, +entrance, _}:
      entrance

def region_final(+r: Region) -> U32:
  match r:
    case Region{_, _, _, +final}:
      final

def separated(split: Bool, +s: GG.St, +entrance: U32, +final: U32) -> GG.St:
  match split:
    case True{}:
      GB.separate_by_blanks(s, entrance, final)
    case False{}:
      s

def looped(different: Bool, +s: GG.St, +entrance: U32, +final: U32) -> GG.St:
  match different:
    case True{}:
      +roll = GG.below(s, SY.half_threshold())
      separated(U32.is_eq(GG.val(roll), 1), GG.st(roll), entrance, final)
    case False{}:
      s

def finished(+start: U32, +final: GG.Got) -> Region:
  +s = GG.st(final)
  +entrance = GN.entrance_node(s, start)
  +e = GG.val(entrance)
  +f = GG.val(final)
  +s1 = GG.st(entrance)
  Region{looped(U32.is_ne(GG.nf(s1, e, GG.f_task()), GG.nf(s1, f, GG.f_task())), s1, e, f), start, e, f}

def laid_out(restricted: Bool, +s: GG.St, +start: U32, +graphs: List<&2, U32>) -> GG.Got:
  match restricted:
    case True{}:
      +before = GG.rng_of(s)
      +final = restrict_by_key(GG.say(s), start, graphs)
      GG.Got{GG.val(final), GG.returned(GG.st(final), GG.f_restrict_nodes_by_key(), before)}
    case False{}:
      +before = GG.rng_of(s)
      +final = link_by_keys(GG.say(s), start, graphs)
      GG.Got{GG.val(final), GG.returned(GG.st(final), GG.f_link_nodes_by_keys(), before)}

def started(+found: GG.Got, +graphs: List<&2, U32>, +restricted: Bool) -> Region:
  +start = GG.val(found)
  finished(start, laid_out(restricted, GG.say(GG.st(found)), start, graphs))

def generated(tasks: List<&2, U32>, +s: GG.St, +graphs: List<&2, U32>) -> GG.Got:
  match tasks:
    case Nil{}:
      GG.Got{0, s}
    case Con{+task, rest}:
      +made = GN.generate_task(s, task)
      generated(rest, GG.st(made), List.append(&2, U32, graphs, [GG.val(made)]))

def graphs_after(tasks: List<&2, U32>, +first: U32) -> List<&2, U32>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{_, rest}:
      first <> graphs_after(rest, (first + 1 : U32))

# Story:GenerateNodesForRegion(tasks in pairs() order, mode): every task's graph, the starting task, the layout, the
# entrance node and the loop blank (math.random() < 0.5) when entrance and final node are in different tasks.
def generate_region(+s: GG.St, +tasks: List<&2, U32>, +restricted: Bool) -> Region:
  +graphs = graphs_after(tasks, GG.get(s, GG.s_graphs()))
  +made = GG.st(generated(tasks, s, Nil{}))
  started(find_starting_task(made, GG.graph_table_order(made, graphs)), graphs, restricted)

def start_room() -> GG.Info:
  +room = RM.start_room()
  GG.NodeData{GG.id_start(), 0, 0, room, GN.room_type(room), RM.value(room), GN.room_itype(room), 0,
    GN.optional(RM.random_node_exit_weight(room)), GN.optional(RM.random_node_entrance_weight(room)), GG.none(), room, 1, 0}

def graph_of_task(order: List<&2, U32>, +s: GG.St, +task: U32) -> U32:
  match order:
    case Nil{}:
      GG.none()
    case Con{+g, rest}:
      +hit = U32.is_eq(GG.gf(s, g, GG.g_kind()), GG.k_task()) && U32.is_eq(task_of(s, g), task)
      Bool.pick(U32, hit, g, graph_of_task(rest, s, task))

def start_linked(+s: GG.St, +g: U32, +entry: GG.Got) -> GG.St:
  +added = GG.add_node(GG.say(GG.st(entry)), g, start_room())
  GG.link(GG.st(added), GG.val(added), GG.val(entry))

def start_in(found: Bool, +s: GG.St, +g: U32, +fallback: U32) -> GG.St:
  match found:
    case True{}:
      start_linked(s, g, GN.entrance_node(GG.say(s), g))
    case False{}:
      start_linked(s, fallback, GN.entrance_node(GG.say(s), fallback))

def start_named(named: Bool, +s: GG.St, +task: U32, +fallback: U32) -> GG.St:
  match named:
    case True{}:
      +g = graph_of_task(GG.children_order(s), s, task)
      start_in(U32.is_ne(g, GG.none()), GG.say(s), g, fallback)
    case False{}:
      start_in(False{}, s, fallback, fallback)

# Story:_AddPlayerStartNode: valid_start_tasks[math.random(#valid_start_tasks)], the START node (the start_node room
# with AddStartingSetPiece's countstaticlayouts) linked to that task's entrance pick.
def add_start_node(+s: GG.St, +fallback: U32) -> GG.St:
  +valid = TK.lists(2)
  +d = GG.upto(s, GO.count(valid, 0))
  +k = GG.val(d)
  start_named((k <= GO.count(valid, 0) : U32), GG.st(d), GO.nth_or_last(valid, (k - 1 : U32), 0), fallback)
