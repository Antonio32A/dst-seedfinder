import Base
import ../data/blob.bend as Blob
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../data/story.bend as StoryData
import ../data/enums.bend as Enums
import ./graph.bend as StoryGraph
import ./order.bend as StoryOrder
import ./maptags.bend as MapTags
import ./nodes.bend as StoryNodes

# Story:AddBGNodes, Story:AddCoveNodes and Story:SeperateStoryByBlanks.

# A background or cove node's type: Room becomes BackgroundRoom, Default becomes Background.
def background_type(+room: U32) -> U32:
  +t = StoryNodes.room_type(room)
  Bool.pick(U32, U32.is_eq(t, Enums.node_type_room()), Enums.node_type_background_room(),
    Bool.pick(U32, U32.is_eq(t, Enums.node_type_default()), Enums.node_type_background(), t))

def background_room(+kind: U32, +g: U32, +idx: U32, +room: U32) -> StoryGraph.Info:
  StoryGraph.NodeData{kind, g, idx, room, background_type(room), Rooms.value(room), StoryNodes.room_itype(room), 0, StoryGraph.none(), StoryGraph.none(), g, room, 2, 0}

def blocker(+g: U32, +entrance: U32, +i: U32) -> StoryGraph.Info:
  StoryGraph.NodeData{StoryGraph.id_blocker(), entrance, i, StoryGraph.none(), Enums.node_type_blank(), StoryData.impassable_value(), Enums.connection_edge_site(),
    0, StoryGraph.none(), StoryGraph.none(), g, StoryGraph.none(), 0, 1}

def attached(+added: StoryGraph.Got, +node: U32) -> StoryGraph.St:
  match added:
    case StoryGraph.Got{+n, +s}:
      StoryGraph.link(s, n, node)

def bg_loop(n: Nat, +s: StoryGraph.St, +g: U32, +node: U32, +room: U32, +idx: U32) -> StoryGraph.Got:
  match n:
    case 0n:
      StoryGraph.Got{idx, s}
    case 1n+p:
      +added = StoryGraph.add_node(MapTags.extras(s, room), g, background_room(StoryGraph.id_bg(), g, idx, room))
      bg_loop(p, attached(added, node), g, node, room, (idx + 1 : U32))

def blocker_linked(+node: U32, +added: StoryGraph.Got) -> StoryGraph.St:
  match added:
    case StoryGraph.Got{+n, +s}:
      StoryGraph.link(s, node, n)

def blocked(+s: StoryGraph.St, +g: U32, +node: U32, +i: U32) -> StoryGraph.St:
  blocker_linked(node, StoryGraph.add_node(s, g, blocker(g, node, i)))

def bg_counted(+count: StoryGraph.Got, +g: U32, +node: U32, +room: U32, +idx: U32) -> StoryGraph.Got:
  match count:
    case StoryGraph.Got{+n, +s}:
      bg_loop(U32.to_nat(n), s, g, node, room, idx)

def background_of(entrance: Bool, +s: StoryGraph.St, +g: U32, +node: U32, +room: U32, +idx: U32) -> StoryGraph.Got:
  match entrance:
    case True{}:
      StoryGraph.Got{idx, blocked(blocked(s, g, node, 1), g, node, 2)}
    case False{}:
      bg_counted(StoryGraph.range(s, 0, 2), g, node, room, idx)

def bg_nodes(nodes: List<&2, U32>, +walk: StoryGraph.Got, +g: U32, +room: U32) -> StoryGraph.Got:
  match nodes:
    case Nil{}:
      walk
    case Con{+node, rest}:
      match walk:
        case StoryGraph.Got{+idx, +s}:
          bg_nodes(rest, background_of(StoryGraph.is_entrance(s, node), s, g, node, room, idx), g, room)

def bg_graphs(graphs: List<&2, U32>, +walk: StoryGraph.Got) -> StoryGraph.Got:
  match graphs:
    case Nil{}:
      walk
    case Con{+g, rest}:
      match walk:
        case StoryGraph.Got{+idx, +s}:
          bg_graphs(rest, bg_nodes(StoryGraph.copy_order(s, g), StoryGraph.Got{idx, s}, g, StoryGraph.gf(s, g, StoryGraph.g_background())))

# Story:AddBGNodes(0, 2) over pairs(root.children): 0-2 background rooms per node (math.random(0, 2)), two blocker
# blanks per entrance node; bg_idx runs across all graphs.
def add_bg_nodes(+s: StoryGraph.St) -> StoryGraph.St:
  +before = StoryGraph.rng_of(s)
  StoryGraph.returned(StoryGraph.st(bg_graphs(StoryGraph.children_order(s), StoryGraph.Got{0, StoryGraph.say(s)})), StoryGraph.f_add_bg_nodes(), before)

def cove_max_edges(+task: U32) -> U32:
  +m = Tasks.cove_room_max_edges(task)
  Bool.pick(U32, Blob.is_none(m), Tasks.default_cove_max_edges(), m)

def cove_eligible(+s: StoryGraph.St, +node: U32, +max_edges: U32) -> Bool:
  +t = StoryGraph.nf(s, node, StoryGraph.f_type())
  Bool.not(StoryGraph.is_entrance(s, node)) && U32.is_ne(t, Enums.node_type_blank()) && U32.is_ne(t, Enums.node_type_background_room())
    && U32.is_ne(StoryGraph.nf(s, node, StoryGraph.f_kind()), StoryGraph.id_start()) && (StoryGraph.nf(s, node, StoryGraph.f_edges()) <= max_edges : U32)

def cove_added(hit: Bool, +s: StoryGraph.St, +g: U32, +node: U32, +room: U32, +idx: U32) -> StoryGraph.Got:
  match hit:
    case True{}:
      +added = StoryGraph.add_node(MapTags.extras(s, room), g, background_room(StoryGraph.id_cove(), g, idx, room))
      StoryGraph.Got{(idx + 1 : U32), attached(added, node)}
    case False{}:
      StoryGraph.Got{idx, s}

def cove_rolled(+hit: StoryGraph.Got, +g: U32, +node: U32, +room: U32, +idx: U32) -> StoryGraph.Got:
  match hit:
    case StoryGraph.Got{+h, +s}:
      cove_added(U32.is_eq(h, 1), s, g, node, room, idx)

def cove_of(eligible: Bool, +s: StoryGraph.St, +g: U32, +node: U32, +task: U32, +idx: U32) -> StoryGraph.Got:
  match eligible:
    case True{}:
      cove_rolled(StoryGraph.below(s, Tasks.cove_threshold(task)), g, node, Tasks.cove_room(task), idx)
    case False{}:
      StoryGraph.Got{idx, s}

def cove_nodes(nodes: List<&2, U32>, +walk: StoryGraph.Got, +g: U32, +task: U32) -> StoryGraph.Got:
  match nodes:
    case Nil{}:
      walk
    case Con{+node, rest}:
      match walk:
        case StoryGraph.Got{+idx, +s}:
          cove_nodes(rest, cove_of(cove_eligible(s, node, cove_max_edges(task)), s, g, node, task, idx), g, task)

def cove_graph(task_graph: Bool, +s: StoryGraph.St, +g: U32) -> StoryGraph.St:
  match task_graph:
    case True{}:
      +task = StoryGraph.gf(s, g, StoryGraph.g_part())
      StoryGraph.st(cove_nodes(StoryGraph.copy_order(s, g), StoryGraph.Got{0, s}, g, task))
    case False{}:
      s

def no_coves(+task: U32) -> Bool:
  +chance = Tasks.cove_room_chance(task)
  (Bool.not(Blob.is_none(chance)) && U32.is_zero(chance)) || U32.is_zero(Tasks.cove_room_max_edges(task))

def coved(stop: Bool, +task_graph: Bool, +s: StoryGraph.St, +g: U32) -> StoryGraph.St:
  match stop:
    case True{}:
      s
    case False{}:
      cove_graph(task_graph, s, g)

def cove_graphs(graphs: List<&2, U32>, stopped: Bool, +s: StoryGraph.St) -> StoryGraph.St:
  match graphs:
    case Nil{}:
      s
    case Con{+g, rest}:
      match stopped:
        case True{}:
          s
        case False{}:
          +task_graph = U32.is_eq(StoryGraph.gf(s, g, StoryGraph.g_kind()), StoryGraph.k_task())
          +stop = task_graph && no_coves(StoryGraph.gf(s, g, StoryGraph.g_part()))
          cove_graphs(rest, stop, coved(stop, task_graph, s, g))

# Story:AddCoveNodes over the given graphs (pairs order): each leaf-ish node of a task draws math.random() against
# the task's cove chance; a task with chance 0 or max_edges 0 ends the whole pass.
def add_cove_nodes(+s: StoryGraph.St, +graphs: List<&2, U32>) -> StoryGraph.St:
  +before = StoryGraph.rng_of(s)
  StoryGraph.returned(cove_graphs(graphs, False{}, StoryGraph.say(s)), StoryGraph.f_add_cove_nodes(), before)

def loop_sub(+n: U32) -> StoryGraph.Info:
  StoryGraph.NodeData{StoryGraph.id_loop_sub(), 0, n, StoryGraph.none(), Enums.node_type_blank(), StoryData.impassable_value(), Enums.connection_edge_site(), 0,
    StoryGraph.none(), StoryGraph.none(), StoryGraph.none(), StoryGraph.none(), 0, 0}

def blank_locked(+added: StoryGraph.Got, +from: U32, +to: U32) -> StoryGraph.St:
  match added:
    case StoryGraph.Got{+blank, +s}:
      StoryGraph.lock(StoryGraph.lock(StoryGraph.bump(s, StoryGraph.s_loop_blanks()), from, blank), to, blank)

def blank_graph(+made: StoryGraph.Got, +n: U32, +from: U32, +to: U32) -> StoryGraph.St:
  match made:
    case StoryGraph.Got{+g, +s}:
      blank_locked(StoryGraph.add_node(StoryGraph.graph_child(s, g), g, loop_sub(n)), from, to)

# Story:SeperateStoryByBlanks(from, to): a LOOP_BLANK graph with one blank node, locked to both nodes.
def separate_by_blanks(+s: StoryGraph.St, +from: U32, +to: U32) -> StoryGraph.St:
  +n = StoryGraph.get(s, StoryGraph.s_loop_blanks())
  blank_graph(StoryGraph.new_graph(s, StoryGraph.k_loop_blank(), n, StoryData.impassable_value(), StoryData.bg_impassable_room()), n, from, to)
