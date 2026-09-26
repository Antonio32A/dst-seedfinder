import Base
import ../data/blob.bend as B
import ../data/rooms.bend as RM
import ../data/tasks.bend as TK
import ../data/story.bend as SY
import ../data/enums.bend as EN
import ./graph.bend as GG
import ./order.bend as GO
import ./maptags.bend as GT

# Story:GenerateNodesFromTask (a task's rooms, chain edges, MakeLoop, CrosslinkRandom) and the Graph node pickers
# (GetRandomNode, GetRandomNodeForExit, GetRandomNodeForEntrance, network.lua).

def optional(+u: U32) -> U32:
  Bool.pick(U32, B.is_none(u), GG.none(), u)

# Story:GetRoom's `type or NODE_TYPE.Default`.
def room_type(+room: U32) -> U32:
  +t = RM.node_type(room)
  Bool.pick(U32, B.is_none(t), EN.node_type_default(), t)

# AddChild's `internal_type or NODE_INTERNAL_CONNECTION_TYPE.EdgeSite`.
def room_itype(+room: U32) -> U32:
  +t = RM.internal_type(room)
  Bool.pick(U32, B.is_none(t), EN.connection_edge_site(), t)

def task_room(+g: U32, +task: U32, +id: U32, +room: U32, +entrance: U32) -> GG.Info:
  +ntype = Bool.pick(U32, U32.is_eq(entrance, 1), EN.node_type_blocker(), room_type(room))
  GG.NodeData{GG.id_room(), task, id, room, ntype, RM.value(room), room_itype(room), entrance,
    optional(RM.random_node_exit_weight(room)), optional(RM.random_node_entrance_weight(room)), g, room, 1, 0}

def exit_candidate(+s: GG.St, +n: U32, +field: U32) -> Bool:
  Bool.not(GG.is_entrance(s, n)) && Bool.not(U32.is_zero(GG.nf(s, n, field)))

def candidates(+s: GG.St, nodes: List<&2, U32>, +field: U32) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      +tail = candidates(s, rest, field)
      Bool.pick(List<&2, U32>, exit_candidate(s, n, field), n <> tail, tail)

def picked_from(+picks: List<&2, U32>, +g: GG.Got) -> GG.Got:
  match g:
    case GG.Got{+x, +s}:
      GG.Got{GO.nth_or_last(picks, GO.unit_weight_pick(x, GO.count(picks, 0)), GG.none()), s}

def weighted_node(+s: GG.St, +g: U32, +field: U32) -> GG.Got:
  +picks = GG.node_table_order(s, candidates(s, GG.node_order(s, g), field))
  picked_from(picks, GG.draw(s))

# Graph:GetRandomNodeForExit
def exit_node(+s: GG.St, +g: U32) -> GG.Got:
  weighted_node(s, g, GG.f_exit_weight())

# Graph:GetRandomNodeForEntrance
def entrance_node(+s: GG.St, +g: U32) -> GG.Got:
  weighted_node(s, g, GG.f_entrance_weight())

# A random node pick in progress: the node so far, the state and whether it is no entrance.
type Picking is Data:
  Picking{node: U32, st: GG.St, done: Bool}

def picked_node(+order: List<&2, U32>, +d: GG.Got) -> Picking:
  match d:
    case GG.Got{+k, +s}:
      +node = GO.nth_or_last(order, (k - 1 : U32), GG.none())
      Picking{node, s, Bool.not(GG.is_entrance(s, node))}

def random_node_loop(n: Nat, +r: Picking, +order: List<&2, U32>, +size: U32) -> GG.Got:
  match n:
    case 0n:
      match r:
        case Picking{+node, +s, _}:
          GG.Got{node, s}
    case 1n+p:
      match r:
        case Picking{+node, +s, +done}:
          match done:
            case True{}:
              GG.Got{node, s}
            case False{}:
              random_node_loop(p, picked_node(order, GG.upto(s, size)), order, size)

# Graph:GetRandomNode over pairs(graph.nodes) = order: math.random(#nodes) until the pick is no entrance.
def random_node(+s: GG.St, +order: List<&2, U32>, +size: U32) -> GG.Got:
  random_node_loop(256n, Picking{GG.none(), s, False{}}, order, size)

# A crosslink try in progress: the state, the links still allowed and whether the tries are over.
type Cross is Data:
  Cross{st: GG.St, left: U32, done: Bool}

def crossed_to(+g: U32, +x: U32, +factor: U32, +b: GG.Got) -> Cross:
  match b:
    case GG.Got{+y, +s}:
      +linked = U32.is_ne(x, y) && Bool.not(GG.connected(s, g, x, y))
      +left = (factor - Bool.to_u32(linked) : U32)
      Cross{GG.link_if(linked, s, x, y), left, U32.is_zero(left)}

def crossed(+g: U32, +order: List<&2, U32>, +size: U32, +factor: U32, +a: GG.Got) -> Cross:
  match a:
    case GG.Got{+x, +s}:
      crossed_to(g, x, factor, random_node(s, order, size))

def cross_loop(n: Nat, +c: Cross, +g: U32, +order: List<&2, U32>, +size: U32) -> GG.St:
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
def crosslink(+s: GG.St, +g: U32, +factor: U32) -> GG.St:
  +order = GG.node_order(s, g)
  +size = GO.count(order, 0)
  cross_loop(20n, Cross{s, factor, (size <= 2 : U32) || U32.is_zero(factor)}, g, order, size)

def singles(+s: GG.St, order: List<&2, U32>) -> List<&2, U32>:
  match order:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      +tail = singles(s, rest)
      Bool.pick(List<&2, U32>, U32.is_eq(GG.nf(s, n, GG.f_edges()), 1), n <> tail, tail)

def loop_end(+s: GG.St, +n: U32) -> U32:
  Bool.pick(U32, GG.is_entrance(s, n), GG.nf(s, n, GG.f_first_other()), n)

def closed(ends: List<&2, U32>, +s: GG.St) -> GG.St:
  match ends:
    case Nil{}:
      GG.say(s)
    case Con{+first, rest}:
      match rest:
        case Nil{}:
          GG.say(s)
        case Con{+last, _}:
          GG.link(s, loop_end(s, first), loop_end(s, last))

# Graph:MakeLoop: links the first two nodes (pairs order) with one edge, stepping off entrance ends.
def make_loop(+s: GG.St, +g: U32) -> GG.St:
  closed(singles(s, GG.node_order(s, g)), s)

def repeat(n: Nat, +room: U32, +stack: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      stack
    case 1n+p:
      repeat(p, room, room <> stack)

def added_to(+add: U32, +random: GG.Got) -> GG.Got:
  match random:
    case GG.Got{+r, +s}:
      GG.Got{(add + r : U32), s}

def hit_count(+row: List<&2, U32>, +hit: GG.Got) -> GG.Got:
  match hit:
    case GG.Got{+h, +s}:
      GG.Got{Bool.pick(U32, U32.is_eq(h, 1), B.at(row, 3), B.at(row, 4)), s}

def counted_upto(fixed: Bool, +s: GG.St, +add: U32, +n: U32) -> GG.Got:
  match fixed:
    case True{}:
      GG.Got{add, s}
    case False{}:
      added_to(add, GG.upto(s, n))

def closure_count(shape: U32, +s: GG.St, +row: List<&2, U32>) -> GG.Got:
  match shape:
    case 0:
      +n = B.at(row, 2)
      counted_upto(U32.is_zero(n), s, (B.at(row, 1) - B.at(row, 3) : U32), n)
    case _:
      hit_count(row, GG.below(s, B.word(row, 1)))

def room_count(kind: U32, +s: GG.St, +value: U32) -> GG.Got:
  match kind:
    case 0:
      GG.Got{value, s}
    case _:
      +row = SY.count_closures(value)
      closure_count(B.at(row, 0), s, row)

type Pushed is Data:
  Pushed{stack: List<&2, U32>, st: GG.St}

def pushed_count(+room: U32, +stack: List<&2, U32>, +c: GG.Got) -> Pushed:
  match c:
    case GG.Got{+n, +s}:
      Pushed{repeat(U32.to_nat(n), room, stack), s}

def pushed_room(kind: U32, +room: U32, +value: U32, +p: Pushed) -> Pushed:
  match p:
    case Pushed{+stack, +s}:
      pushed_count(room, stack, room_count(kind, s, value))

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

def chained(+s: GG.St, +n: U32, +prev: U32) -> GG.St:
  GG.link_if(U32.is_ne(prev, GG.none()), s, n, prev)

def chained_added(+prev: U32, +added: GG.Got) -> GG.Got:
  match added:
    case GG.Got{+n, +s}:
      GG.Got{n, chained(s, n, prev)}

# The rooms on the stack as nodes of graph g, each linked to the one before; `walk` holds the last node and the state.
def pop_rooms(stack: List<&2, U32>, +walk: GG.Got, +g: U32, +task: U32, +id: U32) -> GG.St:
  match stack:
    case Nil{}:
      GG.st(walk)
    case Con{+entry, rest}:
      match walk:
        case GG.Got{+prev, +s}:
          +room = (entry .&. 65535 : U32)
          pop_rooms(rest, chained_added(prev, GG.add_node(GT.extras(s, room), g, task_room(g, task, id, room, (entry >> 16n : U32)))), g, task, (id + 1 : U32))

def entrance_drawn(has: Bool, +s: GG.St, +task: U32) -> Pushed:
  match has:
    case True{}:
      Pushed{[(TK.entrance_room(task) .|. entrance_bit() : U32)], GG.st(GG.draw(s))}
    case False{}:
      Pushed{Nil{}, s}

def looped_if(loop: Bool, +s: GG.St, +g: U32) -> GG.St:
  match loop:
    case True{}:
      make_loop(s, g)
    case False{}:
      s

def looped(+s: GG.St, +g: U32, +task: U32) -> GG.St:
  looped_if(U32.is_eq(TK.make_loop(task), 1), s, g)

def cross_factor(+task: U32) -> U32:
  +f = TK.crosslink_factor(task)
  Bool.pick(U32, B.is_none(f), 1, f)

def built(+task: U32, +stack: List<&2, U32>, +made: GG.Got) -> GG.Got:
  match made:
    case GG.Got{+g, +m}:
      +s = pop_rooms(stack, GG.Got{GG.none(), GG.graph_child(m, g)}, g, task, 0)
      GG.Got{g, crosslink(looped(s, g, task), g, cross_factor(task))}

def built_from(+task: U32, +p: Pushed) -> GG.Got:
  match p:
    case Pushed{+stack, +s}:
      built(task, stack, GG.new_graph(s, GG.k_task(), task, TK.room_bg(task), TK.background_room(task)))

# Story:GenerateNodesFromTask(task): the task's graph (the entrance room's math.random() is always drawn).
def generate_task(+s: GG.St, +task: U32) -> GG.Got:
  built_from(task, push_choices(TK.task_room_choices(task), entrance_drawn(Bool.not(B.is_none(TK.entrance_room(task))), s, task)))
