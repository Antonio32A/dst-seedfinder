import Base
import ../data/blob.bend as Blob
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../data/story.bend as StoryData
import ../data/enums.bend as Enums
import ./graph.bend as StoryGraph
import ./order.bend as StoryOrder
import ./nodes.bend as StoryNodes
import ./background.bend as Background

# Story:GenerateNodesForRegion with its two layout modes, LinkNodesByKeys (mainland) and RestrictNodesByKey (the moon
# island), Story:_FindStartingTask, Story:GetRandomNodeFromTasks and Story:_AddPlayerStartNode. Task tables keyed by
# task id (task_nodes / unusedTasks, usedTasks, unlockingNodes, candidateTasks) are replayed from their insertion
# and deletion history (lua/table.bend) whenever they are traversed.

def locks(+task: U32) -> List<&2, U32>:
  Blob.drop(Tasks.task_locks(task), 1)

def keys_given(+task: U32) -> List<&2, U32>:
  Blob.drop(Tasks.task_keys_given(task), 1)

def lock_keys(+lock: U32) -> List<&2, U32>:
  Blob.drop(Tasks.locks_keys(lock), 1)

def task_of(+s: StoryGraph.St, +g: U32) -> U32:
  StoryGraph.gf(s, g, StoryGraph.g_part())

def unused_order(+s: StoryGraph.St, +inserted: List<&2, U32>, +removed: List<&2, U32>) -> List<&2, U32>:
  StoryOrder.order_after(StoryGraph.graph_slots(s, inserted), StoryGraph.graph_slots(s, removed))

def any_in(xs: List<&2, U32>, +set: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, rest}:
      StoryOrder.contains(set, x) || any_in(rest, set)

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
def lock_order_of(+s: StoryGraph.St, +g: U32) -> List<&2, U32>:
  StoryOrder.int_order(locks(task_of(s, g)))

def unlocked_task(tasks: List<&2, U32>, done: Bool, +s: StoryGraph.St, +keys: List<&2, U32>, +found: U32) -> U32:
  match tasks:
    case Nil{}:
      found
    case Con{+g, rest}:
      match done:
        case True{}:
          found
        case False{}:
          +hit = all_unlocked(lock_order_of(s, g), keys)
          unlocked_task(rest, hit, s, keys, Bool.pick(U32, hit, g, StoryGraph.none()))

def unlocked_list(none: Bool, +g: U32, +s: StoryGraph.St, +keys: List<&2, U32>, +holders: List<&2, U32>) -> List<&2, U32>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      g <> StoryGraph.graph_table_order(s, unlocking_inserts(lock_order_of(s, g), keys, holders))

def first_unlocked(tasks: List<&2, U32>, +s: StoryGraph.St, +keys: List<&2, U32>, +holders: List<&2, U32>) -> List<&2, U32>:
  +g = unlocked_task(tasks, False{}, s, keys, StoryGraph.none())
  unlocked_list(U32.is_eq(g, StoryGraph.none()), g, s, keys, holders)

def item_of(+order: List<&2, U32>, +d: StoryGraph.Got) -> StoryGraph.Got:
  match d:
    case StoryGraph.Got{+k, +s}:
      StoryGraph.Got{StoryOrder.nth_or_last(order, (k - 1 : U32), StoryGraph.none()), s}

# GetRandomItem / GetRandomNodeFromTasks over a pairs() order: math.random(n), clamped to the last entry.
def random_item(+s: StoryGraph.St, +order: List<&2, U32>) -> StoryGraph.Got:
  item_of(order, StoryGraph.upto(s, StoryOrder.count(order, 0)))

def entrance_picked(random: Bool, +s: StoryGraph.St, +g: U32, +fixed: U32) -> StoryGraph.Got:
  match random:
    case True{}:
      StoryNodes.entrance_node(s, g)
    case False{}:
      StoryGraph.Got{fixed, s}

def entrance_or_random(+s: StoryGraph.St, +g: U32) -> StoryGraph.Got:
  +fixed = StoryGraph.gf(s, g, StoryGraph.g_entrance())
  entrance_picked(U32.is_eq(fixed, StoryGraph.none()), s, g, fixed)

def locked_to(+exit: U32, +entrance: StoryGraph.Got) -> StoryGraph.St:
  match entrance:
    case StoryGraph.Got{+n, +s}:
      StoryGraph.lock(s, exit, n)

def exit_locked(+current: U32, +exit: StoryGraph.Got) -> StoryGraph.St:
  match exit:
    case StoryGraph.Got{+x, +s}:
      locked_to(x, entrance_or_random(s, current))

# The LockGraph edge of a new connection: the parent's exit node to the task's entrance node.
def connected(+s: StoryGraph.St, +parent: U32, +current: U32, +depth: U32) -> StoryGraph.St:
  exit_locked(current, StoryNodes.exit_node(StoryGraph.set_gf(s, current, StoryGraph.g_depth(), depth), parent))

def new_keys(given: List<&2, U32>, +keys: List<&2, U32>) -> List<&2, U32>:
  match given:
    case Nil{}:
      keys
    case Con{+k, rest}:
      new_keys(rest, Bool.pick(List<&2, U32>, StoryOrder.contains(keys, k), keys, List.append(&2, U32, keys, [k])))

def new_holders(given: List<&2, U32>, +holders: List<&2, U32>, +g: U32) -> List<&2, U32>:
  match given:
    case Nil{}:
      holders
    case Con{+k, rest}:
      new_holders(rest, List.append(&2, U32, holders, [((k << 8n) .|. g : U32)]), g)

type Linking is Data:
  Linking{st: StoryGraph.St, inserted: List<&2, U32>, removed: List<&2, U32>, keys: List<&2, U32>, holders: List<&2, U32>, last: U32, depth: U32}

def linked(+l: Linking, +parent: U32, +current: U32, +s: StoryGraph.St) -> Linking:
  match l:
    case Linking{_, +inserted, +removed, +keys, +holders, _, +depth}:
      +given = keys_given(task_of(s, current))
      Linking{connected(s, parent, current, depth), inserted, List.append(&2, U32, removed, [current]), new_keys(given, keys),
        new_holders(given, holders, current), current, (depth + 1 : U32)}

def linked_pick(+l: Linking, +parent: U32, +picked: StoryGraph.Got) -> Linking:
  match picked:
    case StoryGraph.Got{+current, +s}:
      linked(l, parent, current, s)

def linked_parent(+l: Linking, +current: U32, +picked: StoryGraph.Got) -> Linking:
  match picked:
    case StoryGraph.Got{+parent, +s}:
      linked(l, parent, current, s)

def link_random(+l: Linking, +s: StoryGraph.St, +order: List<&2, U32>, +last: U32) -> Linking:
  linked_pick(l, last, random_item(s, order))

def link_unlocked(found: List<&2, U32>, +l: Linking, +s: StoryGraph.St, +order: List<&2, U32>, +last: U32) -> Linking:
  match found:
    case Nil{}:
      link_random(l, s, order, last)
    case Con{+current, parents}:
      linked_parent(l, current, random_item(s, parents))

def link_step(+l: Linking) -> Linking:
  match l:
    case Linking{+s, +inserted, +removed, +keys, +holders, +last, _}:
      +order = unused_order(s, inserted, removed)
      link_unlocked(first_unlocked(order, s, StoryOrder.int_order(keys), holders), l, s, order, last)

def link_loop(n: Nat, +l: Linking) -> Linking:
  match n:
    case 0n:
      l
    case 1n+p:
      link_loop(p, link_step(l))

def final_exit(+l: Linking) -> StoryGraph.Got:
  match l:
    case Linking{+s, _, _, _, _, +last, _}:
      StoryNodes.exit_node(s, last)

# Story:LinkNodesByKeys(start, unused): returns lastNode:GetRandomNodeForExit().
def link_by_keys(+s: StoryGraph.St, +start: U32, +inserted: List<&2, U32>) -> StoryGraph.Got:
  +given = keys_given(task_of(s, start))
  final_exit(link_loop(U32.to_nat((StoryOrder.count(inserted, 0) - 1 : U32)),
    Linking{StoryGraph.set_gf(s, start, StoryGraph.g_depth(), 0), inserted, [start], new_keys(given, Nil{}), new_holders(given, Nil{}, start), start, 1}))

def opens(+task: U32, +target: U32) -> Bool:
  all_unlocked(locks(task), keys_given(target))

def attach_nodes(+task: U32, +s: StoryGraph.St, used: List<&2, U32>) -> List<&2, U32>:
  match used:
    case Nil{}:
      Nil{}
    case Con{+target, rest}:
      +tail = attach_nodes(task, s, rest)
      Bool.pick(List<&2, U32>, opens(task, task_of(s, target)), target <> tail, tail)

type Restricting is Data:
  Restricting{st: StoryGraph.St, used: List<&2, U32>, inserted: List<&2, U32>, removed: List<&2, U32>, parent: U32, depth: U32, last: U32}

def appended(+r: Restricting, +current: U32, +parents: List<&2, U32>) -> Restricting:
  match r:
    case Restricting{+s, +used, +inserted, +removed, +parent, +depth, _}:
      +turn = (((parent - 1 : U32) % StoryOrder.count(parents, 0)) + 1 : U32)
      +chosen = StoryOrder.nth_or_last(parents, (turn - 1 : U32), StoryGraph.none())
      Restricting{connected(s, chosen, current, depth), List.append(&2, U32, used, [current]), inserted,
        List.append(&2, U32, removed, [current]), (turn + 1 : U32), (depth + 1 : U32), current}

def used_order_of(+r: Restricting) -> List<&2, U32>:
  match r:
    case Restricting{+s, +used, _, _, _, _, _}:
      StoryGraph.graph_table_order(s, used)

def st_of(+r: Restricting) -> StoryGraph.St:
  match r:
    case Restricting{+s, _, _, _, _, _, _}:
      s

def with_st(+r: Restricting, +s: StoryGraph.St) -> Restricting:
  match r:
    case Restricting{_, +used, +inserted, +removed, +parent, +depth, +last}:
      Restricting{s, used, inserted, removed, parent, depth, last}

type Candidate is Data:
  Candidate{task: U32, parents: List<&2, U32>}

def candidates(tasks: List<&2, U32>, +s: StoryGraph.St, +used: List<&2, U32>) -> List<&2, Candidate>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      +tail = candidates(rest, s, used)
      +parents = attach_nodes(task_of(s, g), s, used)
      Bool.pick(List<&2, Candidate>, List.is_empty(&2, U32, parents), tail, Candidate{g, StoryGraph.graph_table_order(s, parents)} <> tail)

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

def appended_pick(+r: Restricting, +parents: List<&2, U32>, +picked: StoryGraph.Got) -> Restricting:
  match picked:
    case StoryGraph.Got{+n, +s}:
      appended(with_st(r, s), n, parents)

def append_any(+cs: List<&2, Candidate>, +r: Restricting, +order: List<&2, U32>) -> Restricting:
  match cs:
    case Nil{}:
      appended_pick(r, used_order_of(r), random_item(st_of(r), order))
    case Con{_, _}:
      append_all(StoryGraph.graph_table_order(st_of(r), candidate_tasks(cs)), r, cs)

def restrict_step(+r: Restricting) -> Restricting:
  match r:
    case Restricting{+s, _, +inserted, +removed, _, _, _}:
      +order = unused_order(s, inserted, removed)
      append_any(candidates(order, s, used_order_of(r)), r, order)

def remaining(+r: Restricting) -> U32:
  match r:
    case Restricting{_, _, +inserted, +removed, _, _, _}:
      (StoryOrder.count(inserted, 0) - StoryOrder.count(removed, 0) : U32)

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

def last_exit(+r: Restricting) -> StoryGraph.Got:
  match r:
    case Restricting{+s, _, _, _, _, _, +last}:
      StoryNodes.exit_node(s, last)

# Story:RestrictNodesByKey(start, unused): each round appends every unlockable task, cycling through its parents.
def restrict_by_key(+s: StoryGraph.St, +start: U32, +inserted: List<&2, U32>) -> StoryGraph.Got:
  last_exit(restrict_loop(U32.to_nat(StoryOrder.count(inserted, 0)), U32.is_eq(StoryOrder.count(inserted, 0), 1),
    Restricting{StoryGraph.set_gf(s, start, StoryGraph.g_depth(), 0), [start], inserted, [start], 1, 1, start}))

def is_start_task(+s: StoryGraph.St, +g: U32) -> Bool:
  +row = Tasks.task_locks(task_of(s, g))
  U32.is_zero(Blob.at(row, 0)) || U32.is_eq(Blob.at(row, 1), Enums.lock_none())

def start_tasks(order: List<&2, U32>, +s: StoryGraph.St) -> List<&2, U32>:
  match order:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      +tail = start_tasks(rest, s)
      Bool.pick(List<&2, U32>, is_start_task(s, g), g <> tail, tail)

def start_within(inside: Bool, +k: U32, +s: StoryGraph.St, +starts: List<&2, U32>, +order: List<&2, U32>) -> StoryGraph.Got:
  match inside:
    case True{}:
      StoryGraph.Got{StoryOrder.nth_or_last(starts, (k - 1 : U32), StoryGraph.none()), s}
    case False{}:
      random_item(s, order)

def start_picked(+d: StoryGraph.Got, +starts: List<&2, U32>, +order: List<&2, U32>) -> StoryGraph.Got:
  match d:
    case StoryGraph.Got{+k, +s}:
      start_within((k <= StoryOrder.count(starts, 0) : U32), k, s, starts, order)

def start_of(empty: Bool, +s: StoryGraph.St, +starts: List<&2, U32>, +order: List<&2, U32>) -> StoryGraph.Got:
  match empty:
    case True{}:
      random_item(s, order)
    case False{}:
      start_picked(StoryGraph.upto(s, StoryOrder.count(starts, 0)), starts, order)

# Story:_FindStartingTask: startTasks[math.random(#startTasks)], or GetRandomItem(task_nodes) when that is nil.
def find_starting_task(+s: StoryGraph.St, +order: List<&2, U32>) -> StoryGraph.Got:
  +starts = start_tasks(order, s)
  start_of(List.is_empty(&2, U32, starts), s, starts, order)

type Region is Data:
  Region{st: StoryGraph.St, start: U32, entrance: U32, final: U32}

def region_st(+r: Region) -> StoryGraph.St:
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

def separated(split: Bool, +s: StoryGraph.St, +entrance: U32, +final: U32) -> StoryGraph.St:
  match split:
    case True{}:
      Background.separate_by_blanks(s, entrance, final)
    case False{}:
      s

def rolled(+roll: StoryGraph.Got, +entrance: U32, +final: U32) -> StoryGraph.St:
  match roll:
    case StoryGraph.Got{+r, +s}:
      separated(U32.is_eq(r, 1), s, entrance, final)

def looped(different: Bool, +s: StoryGraph.St, +entrance: U32, +final: U32) -> StoryGraph.St:
  match different:
    case True{}:
      rolled(StoryGraph.below(s, StoryData.half_threshold()), entrance, final)
    case False{}:
      s

def finished_at(+start: U32, +f: U32, +entrance: StoryGraph.Got) -> Region:
  match entrance:
    case StoryGraph.Got{+e, +s1}:
      Region{looped(U32.is_ne(StoryGraph.nf(s1, e, StoryGraph.f_task()), StoryGraph.nf(s1, f, StoryGraph.f_task())), s1, e, f), start, e, f}

def finished(+start: U32, +final: StoryGraph.Got) -> Region:
  match final:
    case StoryGraph.Got{+f, +s}:
      finished_at(start, f, StoryNodes.entrance_node(s, start))

def laid_out(restricted: Bool, +s: StoryGraph.St, +start: U32, +graphs: List<&2, U32>) -> StoryGraph.Got:
  match restricted:
    case True{}:
      +before = StoryGraph.rng_of(s)
      StoryGraph.returned_got(restrict_by_key(StoryGraph.say(s), start, graphs), StoryGraph.f_restrict_nodes_by_key(), before)
    case False{}:
      +before = StoryGraph.rng_of(s)
      StoryGraph.returned_got(link_by_keys(StoryGraph.say(s), start, graphs), StoryGraph.f_link_nodes_by_keys(), before)

def started(+found: StoryGraph.Got, +graphs: List<&2, U32>, +restricted: Bool) -> Region:
  match found:
    case StoryGraph.Got{+start, +s}:
      finished(start, laid_out(restricted, StoryGraph.say(s), start, graphs))

def generated(tasks: List<&2, U32>, +s: StoryGraph.St) -> StoryGraph.St:
  match tasks:
    case Nil{}:
      s
    case Con{+task, rest}:
      generated(rest, StoryGraph.st(StoryNodes.generate_task(s, task)))

def graphs_after(tasks: List<&2, U32>, +first: U32) -> List<&2, U32>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{_, rest}:
      first <> graphs_after(rest, (first + 1 : U32))

# Story:GenerateNodesForRegion(tasks in pairs() order, mode): every task's graph, the starting task, the layout, the
# entrance node and the loop blank (math.random() < 0.5) when entrance and final node are in different tasks.
def generate_region(+s: StoryGraph.St, +tasks: List<&2, U32>, +restricted: Bool) -> Region:
  +graphs = graphs_after(tasks, StoryGraph.get(s, StoryGraph.s_graphs()))
  +made = generated(tasks, s)
  started(find_starting_task(made, StoryGraph.graph_table_order(made, graphs)), graphs, restricted)

def start_room() -> StoryGraph.Info:
  +room = Rooms.start_room()
  StoryGraph.NodeData{StoryGraph.id_start(), 0, 0, room, StoryNodes.room_type(room), Rooms.value(room), StoryNodes.room_itype(room), 0,
    StoryNodes.optional(Rooms.random_node_exit_weight(room)), StoryNodes.optional(Rooms.random_node_entrance_weight(room)), StoryGraph.none(), room, 1, 0}

def graph_of_task(order: List<&2, U32>, +s: StoryGraph.St, +task: U32) -> U32:
  match order:
    case Nil{}:
      StoryGraph.none()
    case Con{+g, rest}:
      +hit = U32.is_eq(StoryGraph.gf(s, g, StoryGraph.g_kind()), StoryGraph.k_task()) && U32.is_eq(task_of(s, g), task)
      Bool.pick(U32, hit, g, graph_of_task(rest, s, task))

def start_joined(+entrance: U32, +added: StoryGraph.Got) -> StoryGraph.St:
  match added:
    case StoryGraph.Got{+n, +s}:
      StoryGraph.link(s, n, entrance)

def start_linked(+s: StoryGraph.St, +g: U32, +entry: StoryGraph.Got) -> StoryGraph.St:
  match entry:
    case StoryGraph.Got{+e, +es}:
      start_joined(e, StoryGraph.add_node(StoryGraph.say(es), g, start_room()))

def start_in(found: Bool, +s: StoryGraph.St, +g: U32, +fallback: U32) -> StoryGraph.St:
  match found:
    case True{}:
      start_linked(s, g, StoryNodes.entrance_node(StoryGraph.say(s), g))
    case False{}:
      start_linked(s, fallback, StoryNodes.entrance_node(StoryGraph.say(s), fallback))

def start_named(named: Bool, +s: StoryGraph.St, +task: U32, +fallback: U32) -> StoryGraph.St:
  match named:
    case True{}:
      +g = graph_of_task(StoryGraph.children_order(s), s, task)
      start_in(U32.is_ne(g, StoryGraph.none()), StoryGraph.say(s), g, fallback)
    case False{}:
      start_in(False{}, s, fallback, fallback)

# Story:_AddPlayerStartNode: valid_start_tasks[math.random(#valid_start_tasks)], the START node (the start_node room
# with AddStartingSetPiece's countstaticlayouts) linked to that task's entrance pick.
def start_drawn(+valid: List<&2, U32>, +fallback: U32, +d: StoryGraph.Got) -> StoryGraph.St:
  match d:
    case StoryGraph.Got{+k, +s}:
      start_named((k <= StoryOrder.count(valid, 0) : U32), s, StoryOrder.nth_or_last(valid, (k - 1 : U32), 0), fallback)

def add_start_node(+s: StoryGraph.St, +fallback: U32) -> StoryGraph.St:
  +valid = Tasks.lists(2)
  start_drawn(valid, fallback, StoryGraph.upto(s, StoryOrder.count(valid, 0)))
