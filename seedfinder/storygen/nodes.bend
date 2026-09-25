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
  GG.Got{GO.nth_or_last(picks, GO.unit_weight_pick(GG.val(g), GO.count(picks, 0)), GG.none()), GG.st(g)}

def weighted_node(+s: GG.St, +g: U32, +field: U32) -> GG.Got:
  +picks = GG.node_table_order(s, candidates(s, GG.node_order(s, g), field))
  picked_from(picks, GG.draw(s))

# Graph:GetRandomNodeForExit
def exit_node(+s: GG.St, +g: U32) -> GG.Got:
  weighted_node(s, g, GG.f_exit_weight())

# Graph:GetRandomNodeForEntrance
def entrance_node(+s: GG.St, +g: U32) -> GG.Got:
  weighted_node(s, g, GG.f_entrance_weight())

def random_node_loop(n: Nat, done: Bool, +got: GG.Got, +order: List<&2, U32>, +size: U32) -> GG.Got:
  match n:
    case 0n:
      got
    case 1n+p:
      match done:
        case True{}:
          got
        case False{}:
          +d = GG.upto(GG.st(got), size)
          +node = GO.nth_or_last(order, (GG.val(d) - 1 : U32), GG.none())
          random_node_loop(p, Bool.not(GG.is_entrance(GG.st(d), node)), GG.Got{node, GG.st(d)}, order, size)

# Graph:GetRandomNode over pairs(graph.nodes) = order: math.random(#nodes) until the pick is no entrance.
def random_node(+s: GG.St, +order: List<&2, U32>, +size: U32) -> GG.Got:
  random_node_loop(256n, False{}, GG.Got{GG.none(), s}, order, size)

def cross_loop(n: Nat, done: Bool, +s: GG.St, +g: U32, +order: List<&2, U32>, +size: U32, +factor: U32) -> GG.St:
  match n:
    case 0n:
      s
    case 1n+p:
      match done:
        case True{}:
          s
        case False{}:
          +a = random_node(s, order, size)
          +b = random_node(GG.st(a), order, size)
          +x = GG.val(a)
          +y = GG.val(b)
          +linked = U32.is_ne(x, y) && Bool.not(GG.connected(GG.st(b), g, x, y))
          +left = (factor - Bool.to_u32(linked) : U32)
          cross_loop(p, U32.is_zero(left), GG.link_if(linked, GG.st(b), x, y), g, order, size, left)

# Graph:CrosslinkRandom(factor): up to 20 tries of two random nodes, linking unconnected pairs.
def crosslink(+s: GG.St, +g: U32, +factor: U32) -> GG.St:
  +order = GG.node_order(s, g)
  +size = GO.count(order, 0)
  cross_loop(20n, (size <= 2 : U32) || U32.is_zero(factor), s, g, order, size, factor)

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

def counted_upto(fixed: Bool, +s: GG.St, +add: U32, +n: U32) -> GG.Got:
  match fixed:
    case True{}:
      GG.Got{add, s}
    case False{}:
      +random = GG.upto(s, n)
      GG.Got{(add + GG.val(random) : U32), GG.st(random)}

def closure_count(shape: U32, +s: GG.St, +row: List<&2, U32>) -> GG.Got:
  match shape:
    case 0:
      +n = B.at(row, 2)
      counted_upto(U32.is_zero(n), s, (B.at(row, 1) - B.at(row, 3) : U32), n)
    case _:
      +hit = GG.below(s, B.word(row, 1))
      GG.Got{Bool.pick(U32, U32.is_eq(GG.val(hit), 1), B.at(row, 3), B.at(row, 4)), GG.st(hit)}

def room_count(kind: U32, +s: GG.St, +value: U32) -> GG.Got:
  match kind:
    case 0:
      GG.Got{value, s}
    case _:
      +row = SY.count_closures(value)
      closure_count(B.at(row, 0), s, row)

type Pushed is Data:
  Pushed{stack: List<&2, U32>, st: GG.St}

# room_choices in pairs() order: each count (a number or a count closure), then that many rooms on the stack.
def push_choices(triples: List<&2, U32>, +s: GG.St, +stack: List<&2, U32>) -> Pushed:
  match triples:
    case Nil{}:
      Pushed{stack, s}
    case Con{+room, rest}:
      match rest:
        case Nil{}:
          Pushed{stack, s}
        case Con{+kind, more}:
          match more:
            case Nil{}:
              Pushed{stack, s}
            case Con{+value, tail}:
              +c = room_count(kind, s, value)
              push_choices(tail, GG.st(c), repeat(U32.to_nat(GG.val(c)), room, stack))

def entrance_bit() -> U32:
  65536

def chained(+s: GG.St, +n: U32, +prev: U32) -> GG.St:
  GG.link_if(U32.is_ne(prev, GG.none()), s, n, prev)

def pop_rooms(stack: List<&2, U32>, +s: GG.St, +g: U32, +task: U32, +id: U32, +prev: U32) -> GG.St:
  match stack:
    case Nil{}:
      s
    case Con{+entry, rest}:
      +room = (entry .&. 65535 : U32)
      +added = GG.add_node(GT.extras(s, room), g, task_room(g, task, id, room, (entry >> 16n : U32)))
      +n = GG.val(added)
      pop_rooms(rest, chained(GG.st(added), n, prev), g, task, (id + 1 : U32), n)

def entrance_drawn(has: Bool, +s: GG.St, +task: U32) -> Pushed:
  match has:
    case True{}:
      Pushed{[(TK.entrance_room(task) .|. entrance_bit() : U32)], GG.st(GG.draw(s))}
    case False{}:
      Pushed{Nil{}, s}

def stack_of(+p: Pushed) -> List<&2, U32>:
  match p:
    case Pushed{+stack, _}:
      stack

def st_of(+p: Pushed) -> GG.St:
  match p:
    case Pushed{_, +s}:
      s

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
  +g = GG.val(made)
  +s = pop_rooms(stack, GG.graph_child(GG.st(made), g), g, task, 0, GG.none())
  GG.Got{g, crosslink(looped(s, g, task), g, cross_factor(task))}

# Story:GenerateNodesFromTask(task): the task's graph (the entrance room's math.random() is always drawn).
def generate_task(+s: GG.St, +task: U32) -> GG.Got:
  +entrance = entrance_drawn(Bool.not(B.is_none(TK.entrance_room(task))), s, task)
  +pushed = push_choices(TK.task_room_choices(task), st_of(entrance), stack_of(entrance))
  built(task, stack_of(pushed), GG.new_graph(st_of(pushed), GG.k_task(), task, TK.room_bg(task), TK.background_room(task)))
