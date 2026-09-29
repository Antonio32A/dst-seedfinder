import Base
import ../data/blob.bend as Blob
import ../data/enums.bend as Enums
import ./catalog.bend as StoryCatalog
import ./graph.bend as StoryGraph
import ./order.bend as StoryOrder
import ./maptags.bend as MapTags

# Story:GenerateNodesFromTask (a task's rooms, chain edges, MakeLoop, CrosslinkRandom) and the Graph node pickers
# (GetRandomNode, GetRandomNodeForExit, GetRandomNodeForEntrance, network.lua).

def optional(+u: U32) -> U32:
  Bool.pick(U32, Blob.is_none(u), StoryGraph.none(), u)

# Story:GetRoom's `type or NODE_TYPE.Default`.
def room_type(+room: U32) -> U32:
  +t = StoryCatalog.room_node_type(room)
  Bool.pick(U32, Blob.is_none(t), Enums.node_type_default(), t)

# AddChild's `internal_type or NODE_INTERNAL_CONNECTION_TYPE.EdgeSite`.
def room_itype(+room: U32) -> U32:
  +t = StoryCatalog.room_internal_type(room)
  Bool.pick(U32, Blob.is_none(t), Enums.connection_edge_site(), t)

def task_room(+g: U32, +task: U32, +id: U32, +room: U32, +entrance: U32) -> StoryGraph.Info:
  +ntype = Bool.pick(U32, U32.is_eq(entrance, 1), Enums.node_type_blocker(), room_type(room))
  StoryGraph.NodeData{StoryGraph.id_room(), task, id, room, ntype, StoryCatalog.room_value(room), room_itype(room), entrance,
    optional(StoryCatalog.room_exit_weight(room)), optional(StoryCatalog.room_entrance_weight(room)), g, room, 1, 0}

def exit_candidate(+s: StoryGraph.St, +n: U32, +field: U32) -> Bool:
  Bool.not(StoryGraph.is_entrance(s, n)) && Bool.not(U32.is_zero(StoryGraph.nf(s, n, field)))

def candidates(+s: StoryGraph.St, nodes: List<&2, U32>, +field: U32) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      +tail = candidates(s, rest, field)
      Bool.pick(List<&2, U32>, exit_candidate(s, n, field), n <> tail, tail)

def picked_from(+picks: List<&2, U32>, +g: StoryGraph.Got) -> StoryGraph.Got:
  match g:
    case StoryGraph.Got{+x, +s}:
      StoryGraph.Got{StoryOrder.nth_or_last(picks, StoryOrder.unit_weight_pick(x, StoryOrder.count(picks, 0)), StoryGraph.none()), s}

def weighted_node(+s: StoryGraph.St, +g: U32, +field: U32) -> StoryGraph.Got:
  +picks = StoryGraph.node_table_order(s, candidates(s, StoryGraph.node_order(s, g), field))
  picked_from(picks, StoryGraph.draw(s))

# Graph:GetRandomNodeForExit
def exit_node(+s: StoryGraph.St, +g: U32) -> StoryGraph.Got:
  weighted_node(s, g, StoryGraph.f_exit_weight())

# Graph:GetRandomNodeForEntrance
def entrance_node(+s: StoryGraph.St, +g: U32) -> StoryGraph.Got:
  weighted_node(s, g, StoryGraph.f_entrance_weight())

# A random node pick in progress: the node so far, the state and whether it is no entrance.
type Picking is Data:
  Picking{node: U32, st: StoryGraph.St, done: Bool}

def picked_node(+order: List<&2, U32>, +d: StoryGraph.Got) -> Picking:
  match d:
    case StoryGraph.Got{+k, +s}:
      +node = StoryOrder.nth_or_last(order, (k - 1 : U32), StoryGraph.none())
      Picking{node, s, Bool.not(StoryGraph.is_entrance(s, node))}

def random_node_loop(n: Nat, +r: Picking, +order: List<&2, U32>, +size: U32) -> StoryGraph.Got:
  match n:
    case 0n:
      match r:
        case Picking{+node, +s, _}:
          StoryGraph.Got{node, s}
    case 1n+p:
      match r:
        case Picking{+node, +s, +done}:
          match done:
            case True{}:
              StoryGraph.Got{node, s}
            case False{}:
              random_node_loop(p, picked_node(order, StoryGraph.upto(s, size)), order, size)

# Graph:GetRandomNode over pairs(graph.nodes) = order: math.random(#nodes) until the pick is no entrance.
def random_node(+s: StoryGraph.St, +order: List<&2, U32>, +size: U32) -> StoryGraph.Got:
  random_node_loop(256n, Picking{StoryGraph.none(), s, False{}}, order, size)

# A crosslink try in progress: the state, the links still allowed and whether the tries are over.
type Cross is Data:
  Cross{st: StoryGraph.St, left: U32, done: Bool}

def crossed_to(+g: U32, +x: U32, +factor: U32, +b: StoryGraph.Got) -> Cross:
  match b:
    case StoryGraph.Got{+y, +s}:
      +linked = U32.is_ne(x, y) && Bool.not(StoryGraph.connected(s, g, x, y))
      +left = (factor - Bool.to_u32(linked) : U32)
      Cross{StoryGraph.link_if(linked, s, x, y), left, U32.is_zero(left)}

def crossed(+g: U32, +order: List<&2, U32>, +size: U32, +factor: U32, +a: StoryGraph.Got) -> Cross:
  match a:
    case StoryGraph.Got{+x, +s}:
      crossed_to(g, x, factor, random_node(s, order, size))

def cross_loop(n: Nat, +c: Cross, +g: U32, +order: List<&2, U32>, +size: U32) -> StoryGraph.St:
  match n:
    case 0n:
      match c:
        case Cross{+s, _, _}:
          s
    case 1n+p:
      match c:
        case Cross{+s, +left, +done}:
          match done:
            case True{}:
              s
            case False{}:
              cross_loop(p, crossed(g, order, size, left, random_node(s, order, size)), g, order, size)

# Graph:CrosslinkRandom(factor): up to 20 tries of two random nodes, linking unconnected pairs.
def crosslink(+s: StoryGraph.St, +g: U32, +factor: U32) -> StoryGraph.St:
  +order = StoryGraph.node_order(s, g)
  +size = StoryOrder.count(order, 0)
  cross_loop(20n, Cross{s, factor, (size <= 2 : U32) || U32.is_zero(factor)}, g, order, size)

def singles(+s: StoryGraph.St, order: List<&2, U32>) -> List<&2, U32>:
  match order:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      +tail = singles(s, rest)
      Bool.pick(List<&2, U32>, U32.is_eq(StoryGraph.nf(s, n, StoryGraph.f_edges()), 1), n <> tail, tail)

def loop_end(+s: StoryGraph.St, +n: U32) -> U32:
  Bool.pick(U32, StoryGraph.is_entrance(s, n), StoryGraph.nf(s, n, StoryGraph.f_first_other()), n)

def closed(ends: List<&2, U32>, +s: StoryGraph.St) -> StoryGraph.St:
  match ends:
    case Nil{}:
      StoryGraph.say(s)
    case Con{+first, rest}:
      match rest:
        case Nil{}:
          StoryGraph.say(s)
        case Con{+last, _}:
          StoryGraph.link(s, loop_end(s, first), loop_end(s, last))

# Graph:MakeLoop: links the first two nodes (pairs order) with one edge, stepping off entrance ends.
def make_loop(+s: StoryGraph.St, +g: U32) -> StoryGraph.St:
  closed(singles(s, StoryGraph.node_order(s, g)), s)

def repeat(n: Nat, +room: U32, +stack: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      stack
    case 1n+p:
      repeat(p, room, room <> stack)

def added_to(+add: U32, +random: StoryGraph.Got) -> StoryGraph.Got:
  match random:
    case StoryGraph.Got{+r, +s}:
      StoryGraph.Got{(add + r : U32), s}

def hit_count(+row: List<&2, U32>, +hit: StoryGraph.Got) -> StoryGraph.Got:
  match hit:
    case StoryGraph.Got{+h, +s}:
      StoryGraph.Got{Bool.pick(U32, U32.is_eq(h, 1), Blob.at(row, 3), Blob.at(row, 4)), s}

def counted_upto(fixed: Bool, +s: StoryGraph.St, +add: U32, +n: U32) -> StoryGraph.Got:
  match fixed:
    case True{}:
      StoryGraph.Got{add, s}
    case False{}:
      added_to(add, StoryGraph.upto(s, n))

def closure_count(shape: U32, +s: StoryGraph.St, +row: List<&2, U32>) -> StoryGraph.Got:
  match shape:
    case 0:
      +n = Blob.at(row, 2)
      counted_upto(U32.is_zero(n), s, (Blob.at(row, 1) - Blob.at(row, 3) : U32), n)
    case _:
      hit_count(row, StoryGraph.below(s, Blob.word(row, 1)))

def room_count(kind: U32, +s: StoryGraph.St, +room: U32, +value: U32) -> StoryGraph.Got:
  match kind:
    case 0:
      StoryGraph.Got{value, s}
    case _:
      +row = StoryCatalog.count_closure(room, value)
      closure_count(Blob.at(row, 0), s, row)

type Pushed is Data:
  Pushed{stack: List<&2, U32>, st: StoryGraph.St}

def pushed_count(+room: U32, +stack: List<&2, U32>, +c: StoryGraph.Got) -> Pushed:
  match c:
    case StoryGraph.Got{+n, +s}:
      Pushed{repeat(U32.to_nat(n), room, stack), s}

def pushed_room(kind: U32, +room: U32, +value: U32, +p: Pushed) -> Pushed:
  match p:
    case Pushed{+stack, +s}:
      pushed_count(room, stack, room_count(kind, s, room, value))

# room_choices in pairs() order: each count (a number or a count closure), then that many rooms on the stack.
def push_choices(triples: List<&2, U32>, +p: Pushed) -> Pushed:
  match triples:
    case Nil{}:
      p
    case Con{+room, rest}:
      match rest:
        case Nil{}:
          p
        case Con{+kind, more}:
          match more:
            case Nil{}:
              p
            case Con{+value, tail}:
              push_choices(tail, pushed_room(kind, room, value, p))

def entrance_bit() -> U32:
  65536

def chained(+s: StoryGraph.St, +n: U32, +prev: U32) -> StoryGraph.St:
  StoryGraph.link_if(U32.is_ne(prev, StoryGraph.none()), s, n, prev)

def chained_added(+prev: U32, +added: StoryGraph.Got) -> StoryGraph.Got:
  match added:
    case StoryGraph.Got{+n, +s}:
      StoryGraph.Got{n, chained(s, n, prev)}

# The rooms on the stack as nodes of graph g, each linked to the one before; `walk` holds the last node and the state.
def pop_rooms(stack: List<&2, U32>, +walk: StoryGraph.Got, +g: U32, +task: U32, +id: U32) -> StoryGraph.St:
  match stack:
    case Nil{}:
      StoryGraph.st(walk)
    case Con{+entry, rest}:
      match walk:
        case StoryGraph.Got{+prev, +s}:
          +room = (entry .&. 65535 : U32)
          pop_rooms(rest, chained_added(prev, StoryGraph.add_node(MapTags.extras(s, room, g), g, task_room(g, task, id, room, (entry >> 16n : U32)))), g, task, (id + 1 : U32))

def entrance_entry(+room: U32) -> U32:
  (room .|. entrance_bit() : U32)

def entrance_chosen(+picked: StoryGraph.Got, +choices: List<&2, U32>) -> Pushed:
  match picked:
    case StoryGraph.Got{+k, +s}:
      Pushed{[entrance_entry(StoryOrder.nth_or_last(choices, (k - 1 : U32), StoryGraph.none()))], StoryGraph.put(s, StoryGraph.s_entrance(), k)}

def entrance_resolved(unresolved: Bool, +s: StoryGraph.St, +choices: List<&2, U32>, +pick: U32) -> Pushed:
  match unresolved:
    case True{}:
      entrance_chosen(StoryGraph.upto(s, StoryOrder.count(choices, 0)), choices)
    case False{}:
      Pushed{[entrance_entry(StoryOrder.nth_or_last(choices, (pick - 1 : U32), StoryGraph.none()))], s}

# An entrance_room list: GetRandomItem draws math.random(#list) the first time and overwrites the task's field, so the
# later attempts of the seed reuse that pick (StoryGraph.s_entrance()).
def entrance_listed(+s: StoryGraph.St, +task: U32) -> Pushed:
  entrance_resolved(U32.is_zero(StoryGraph.get(s, StoryGraph.s_entrance())), s, StoryCatalog.task_entrance_choices(task), StoryGraph.get(s, StoryGraph.s_entrance()))

def entrance_kind(list: Bool, +s: StoryGraph.St, +task: U32) -> Pushed:
  match list:
    case True{}:
      entrance_listed(s, task)
    case False{}:
      Pushed{[entrance_entry(StoryCatalog.task_entrance_room(task))], s}

def entrance_rolled(+s: StoryGraph.St, +task: U32) -> Pushed:
  entrance_kind(StoryCatalog.task_entrance_is_list(task), s, task)

def entrance_drawn(has: Bool, +s: StoryGraph.St, +task: U32) -> Pushed:
  match has:
    case True{}:
      entrance_rolled(StoryGraph.st(StoryGraph.draw(s)), task)
    case False{}:
      Pushed{Nil{}, s}

def looped_if(loop: Bool, +s: StoryGraph.St, +g: U32) -> StoryGraph.St:
  match loop:
    case True{}:
      make_loop(s, g)
    case False{}:
      s

def looped(+s: StoryGraph.St, +g: U32, +task: U32) -> StoryGraph.St:
  looped_if(U32.is_eq(StoryCatalog.task_make_loop(task), 1), s, g)

def cross_factor(+task: U32) -> U32:
  +f = StoryCatalog.task_crosslink_factor(task)
  Bool.pick(U32, Blob.is_none(f), 1, f)

def built(+task: U32, +stack: List<&2, U32>, +made: StoryGraph.Got) -> StoryGraph.Got:
  match made:
    case StoryGraph.Got{+g, +m}:
      +s = pop_rooms(stack, StoryGraph.Got{StoryGraph.none(), StoryGraph.graph_child(m, g)}, g, task, 0)
      StoryGraph.Got{g, crosslink(looped(s, g, task), g, cross_factor(task))}

def built_from(+task: U32, +p: Pushed) -> StoryGraph.Got:
  match p:
    case Pushed{+stack, +s}:
      built(task, stack, StoryGraph.new_graph(s, StoryGraph.k_task(), task, StoryCatalog.task_room_bg(task), StoryCatalog.task_background_room(task)))

# Story:GenerateNodesFromTask(task): the task's graph (the entrance room's math.random() is always drawn).
def generate_task(+s: StoryGraph.St, +task: U32) -> StoryGraph.Got:
  built_from(task, push_choices(StoryCatalog.task_room_choices(task), entrance_drawn(StoryCatalog.task_has_entrance(task), s, task)))
