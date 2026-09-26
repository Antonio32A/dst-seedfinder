import Base
import ../data/blob.bend as B
import ../data/rooms.bend as RM
import ../data/tasks.bend as TK
import ../data/story.bend as SY
import ../data/enums.bend as EN
import ./graph.bend as GG
import ./order.bend as GO
import ./maptags.bend as GT
import ./nodes.bend as GN

# Story:AddBGNodes, Story:AddCoveNodes and Story:SeperateStoryByBlanks.

# A background or cove node's type: Room becomes BackgroundRoom, Default becomes Background.
def background_type(+room: U32) -> U32:
  +t = GN.room_type(room)
  Bool.pick(U32, U32.is_eq(t, EN.node_type_room()), EN.node_type_background_room(),
    Bool.pick(U32, U32.is_eq(t, EN.node_type_default()), EN.node_type_background(), t))

def background_room(+kind: U32, +g: U32, +idx: U32, +room: U32) -> GG.Info:
  GG.NodeData{kind, g, idx, room, background_type(room), RM.value(room), GN.room_itype(room), 0, GG.none(), GG.none(), g, room, 2, 0}

def blocker(+g: U32, +entrance: U32, +i: U32) -> GG.Info:
  GG.NodeData{GG.id_blocker(), entrance, i, GG.none(), EN.node_type_blank(), SY.impassable_value(), EN.connection_edge_site(),
    0, GG.none(), GG.none(), g, GG.none(), 0, 1}

def attached(+added: GG.Got, +node: U32) -> GG.St:
  match added:
    case GG.Got{+n, +s}:
      GG.link(s, n, node)

def bg_loop(n: Nat, +s: GG.St, +g: U32, +node: U32, +room: U32, +idx: U32) -> GG.Got:
  match n:
    case 0n:
      GG.Got{idx, s}
    case 1n+p:
      +added = GG.add_node(GT.extras(s, room), g, background_room(GG.id_bg(), g, idx, room))
      bg_loop(p, attached(added, node), g, node, room, (idx + 1 : U32))

def blocker_linked(+node: U32, +added: GG.Got) -> GG.St:
  match added:
    case GG.Got{+n, +s}:
      GG.link(s, node, n)

def blocked(+s: GG.St, +g: U32, +node: U32, +i: U32) -> GG.St:
  blocker_linked(node, GG.add_node(s, g, blocker(g, node, i)))

def bg_counted(+count: GG.Got, +g: U32, +node: U32, +room: U32, +idx: U32) -> GG.Got:
  match count:
    case GG.Got{+n, +s}:
      bg_loop(U32.to_nat(n), s, g, node, room, idx)

def background_of(entrance: Bool, +s: GG.St, +g: U32, +node: U32, +room: U32, +idx: U32) -> GG.Got:
  match entrance:
    case True{}:
      GG.Got{idx, blocked(blocked(s, g, node, 1), g, node, 2)}
    case False{}:
      bg_counted(GG.range(s, 0, 2), g, node, room, idx)

def bg_nodes(nodes: List<&2, U32>, +walk: GG.Got, +g: U32, +room: U32) -> GG.Got:
  match nodes:
    case Nil{}:
      walk
    case Con{+node, rest}:
      match walk:
        case GG.Got{+idx, +s}:
          bg_nodes(rest, background_of(GG.is_entrance(s, node), s, g, node, room, idx), g, room)

def bg_graphs(graphs: List<&2, U32>, +walk: GG.Got) -> GG.Got:
  match graphs:
    case Nil{}:
      walk
    case Con{+g, rest}:
      match walk:
        case GG.Got{+idx, +s}:
          bg_graphs(rest, bg_nodes(GG.copy_order(s, g), GG.Got{idx, s}, g, GG.gf(s, g, GG.g_background())))

# Story:AddBGNodes(0, 2) over pairs(root.children): 0-2 background rooms per node (math.random(0, 2)), two blocker
# blanks per entrance node; bg_idx runs across all graphs.
def add_bg_nodes(+s: GG.St) -> GG.St:
  +before = GG.rng_of(s)
  GG.returned(GG.st(bg_graphs(GG.children_order(s), GG.Got{0, GG.say(s)})), GG.f_add_bg_nodes(), before)

def cove_max_edges(+task: U32) -> U32:
  +m = TK.cove_room_max_edges(task)
  Bool.pick(U32, B.is_none(m), TK.default_cove_max_edges(), m)

def cove_eligible(+s: GG.St, +node: U32, +max_edges: U32) -> Bool:
  +t = GG.nf(s, node, GG.f_type())
  Bool.not(GG.is_entrance(s, node)) && U32.is_ne(t, EN.node_type_blank()) && U32.is_ne(t, EN.node_type_background_room())
    && U32.is_ne(GG.nf(s, node, GG.f_kind()), GG.id_start()) && (GG.nf(s, node, GG.f_edges()) <= max_edges : U32)

def cove_added(hit: Bool, +s: GG.St, +g: U32, +node: U32, +room: U32, +idx: U32) -> GG.Got:
  match hit:
    case True{}:
      +added = GG.add_node(GT.extras(s, room), g, background_room(GG.id_cove(), g, idx, room))
      GG.Got{(idx + 1 : U32), attached(added, node)}
    case False{}:
      GG.Got{idx, s}

def cove_rolled(+hit: GG.Got, +g: U32, +node: U32, +room: U32, +idx: U32) -> GG.Got:
  match hit:
    case GG.Got{+h, +s}:
      cove_added(U32.is_eq(h, 1), s, g, node, room, idx)

def cove_of(eligible: Bool, +s: GG.St, +g: U32, +node: U32, +task: U32, +idx: U32) -> GG.Got:
  match eligible:
    case True{}:
      cove_rolled(GG.below(s, TK.cove_threshold(task)), g, node, TK.cove_room(task), idx)
    case False{}:
      GG.Got{idx, s}

def cove_nodes(nodes: List<&2, U32>, +walk: GG.Got, +g: U32, +task: U32) -> GG.Got:
  match nodes:
    case Nil{}:
      walk
    case Con{+node, rest}:
      match walk:
        case GG.Got{+idx, +s}:
          cove_nodes(rest, cove_of(cove_eligible(s, node, cove_max_edges(task)), s, g, node, task, idx), g, task)

def cove_graph(task_graph: Bool, +s: GG.St, +g: U32) -> GG.St:
  match task_graph:
    case True{}:
      +task = GG.gf(s, g, GG.g_part())
      GG.st(cove_nodes(GG.copy_order(s, g), GG.Got{0, s}, g, task))
    case False{}:
      s

def no_coves(+task: U32) -> Bool:
  +chance = TK.cove_room_chance(task)
  (Bool.not(B.is_none(chance)) && U32.is_zero(chance)) || U32.is_zero(TK.cove_room_max_edges(task))

def coved(stop: Bool, +task_graph: Bool, +s: GG.St, +g: U32) -> GG.St:
  match stop:
    case True{}:
      s
    case False{}:
      cove_graph(task_graph, s, g)

def cove_graphs(graphs: List<&2, U32>, stopped: Bool, +s: GG.St) -> GG.St:
  match graphs:
    case Nil{}:
      s
    case Con{+g, rest}:
      match stopped:
        case True{}:
          s
        case False{}:
          +task_graph = U32.is_eq(GG.gf(s, g, GG.g_kind()), GG.k_task())
          +stop = task_graph && no_coves(GG.gf(s, g, GG.g_part()))
          cove_graphs(rest, stop, coved(stop, task_graph, s, g))

# Story:AddCoveNodes over the given graphs (pairs order): each leaf-ish node of a task draws math.random() against
# the task's cove chance; a task with chance 0 or max_edges 0 ends the whole pass.
def add_cove_nodes(+s: GG.St, +graphs: List<&2, U32>) -> GG.St:
  +before = GG.rng_of(s)
  GG.returned(cove_graphs(graphs, False{}, GG.say(s)), GG.f_add_cove_nodes(), before)

def loop_sub(+n: U32) -> GG.Info:
  GG.NodeData{GG.id_loop_sub(), 0, n, GG.none(), EN.node_type_blank(), SY.impassable_value(), EN.connection_edge_site(), 0,
    GG.none(), GG.none(), GG.none(), GG.none(), 0, 0}

def blank_locked(+added: GG.Got, +from: U32, +to: U32) -> GG.St:
  match added:
    case GG.Got{+blank, +s}:
      GG.lock(GG.lock(GG.bump(s, GG.s_loop_blanks()), from, blank), to, blank)

def blank_graph(+made: GG.Got, +n: U32, +from: U32, +to: U32) -> GG.St:
  match made:
    case GG.Got{+g, +s}:
      blank_locked(GG.add_node(GG.graph_child(s, g), g, loop_sub(n)), from, to)

# Story:SeperateStoryByBlanks(from, to): a LOOP_BLANK graph with one blank node, locked to both nodes.
def separate_by_blanks(+s: GG.St, +from: U32, +to: U32) -> GG.St:
  +n = GG.get(s, GG.s_loop_blanks())
  blank_graph(GG.new_graph(s, GG.k_loop_blank(), n, SY.impassable_value(), SY.bg_impassable_room()), n, from, to)
