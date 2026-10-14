import Base
import ../data/blob.bend as Blob
import ../data/story.bend as StoryData
import ../data/enums.bend as Enums
import ./catalog.bend as StoryCatalog
import ./graph.bend as StoryGraph
import ./order.bend as StoryOrder
import ./maptags.bend as MapTags
import ./nodes.bend as StoryNodes
import ../data/builds.bend as Builds

# Story:AddBGNodes, Story:AddCoveNodes and Story:SeperateStoryByBlanks.

# A background or cove node's type: Room becomes BackgroundRoom, Default becomes Background.
def background_type(+build: Builds.Build, +room: U32) -> U32:
  +t = StoryNodes.room_type(build, room)
  Bool.pick(U32, U32.is_eq(t, Enums.node_type_room()), Enums.node_type_background_room(),
    Bool.pick(U32, U32.is_eq(t, Enums.node_type_default()), Enums.node_type_background(), t))

def background_room(+build: Builds.Build, +kind: U32, +g: U32, +idx: U32, +room: U32) -> StoryGraph.Info:
  StoryGraph.NodeData{kind, g, idx, room, background_type(build, room), StoryCatalog.room_value(build, room), StoryNodes.room_itype(build, room), 0, StoryGraph.none(), StoryGraph.none(), g, room, 2, 0}

def blocker(+build: Builds.Build, +g: U32, +entrance: U32, +i: U32) -> StoryGraph.Info:
  StoryGraph.NodeData{StoryGraph.id_blocker(), entrance, i, StoryGraph.none(), Enums.node_type_blank(), StoryData.impassable_value(build), Enums.connection_edge_site(),
    0, StoryGraph.none(), StoryGraph.none(), g, StoryGraph.none(), 0, 1}

def attached(+added: StoryGraph.Got, +node: U32) -> StoryGraph.St:
  match added:
    case StoryGraph.Got{+n, +s}:
      StoryGraph.link(s, n, node)

def bg_loop(+build: Builds.Build, n: Nat, +s: StoryGraph.St, +g: U32, +node: U32, +room: U32, +idx: U32) -> StoryGraph.Got:
  match n:
    case 0n:
      StoryGraph.Got{idx, s}
    case 1n+p:
      +added = StoryGraph.add_node(build, MapTags.extras(build, s, room, g), g, background_room(build, StoryGraph.id_bg(), g, idx, room))
      bg_loop(build, p, attached(added, node), g, node, room, (idx + 1 : U32))

def blocker_linked(+node: U32, +added: StoryGraph.Got) -> StoryGraph.St:
  match added:
    case StoryGraph.Got{+n, +s}:
      StoryGraph.link(s, node, n)

def blocked(+build: Builds.Build, +s: StoryGraph.St, +g: U32, +node: U32, +i: U32) -> StoryGraph.St:
  blocker_linked(node, StoryGraph.add_node(build, s, g, blocker(build, g, node, i)))

def bg_counted(+build: Builds.Build, +count: StoryGraph.Got, +g: U32, +node: U32, +room: U32, +idx: U32) -> StoryGraph.Got:
  match count:
    case StoryGraph.Got{+n, +s}:
      bg_loop(build, U32.to_nat(n), s, g, node, room, idx)

def background_of(+build: Builds.Build, entrance: Bool, +s: StoryGraph.St, +g: U32, +node: U32, +room: U32, +idx: U32, +lo: U32, +hi: U32) -> StoryGraph.Got:
  match entrance:
    case True{}:
      StoryGraph.Got{idx, blocked(build, blocked(build, s, g, node, 1), g, node, 2)}
    case False{}:
      bg_counted(build, StoryGraph.range(s, lo, hi), g, node, room, idx)

def bg_nodes(+build: Builds.Build, nodes: List<&2, U32>, +walk: StoryGraph.Got, +g: U32, +room: U32, +lo: U32, +hi: U32) -> StoryGraph.Got:
  match nodes:
    case Nil{}:
      walk
    case Con{+node, rest}:
      match walk:
        case StoryGraph.Got{+idx, +s}:
          bg_nodes(build, rest, background_of(build, StoryGraph.is_entrance(s, node), s, g, node, room, idx, lo, hi), g, room, lo, hi)

def bg_graphs(+build: Builds.Build, graphs: List<&2, U32>, +walk: StoryGraph.Got, +lo: U32, +hi: U32) -> StoryGraph.Got:
  match graphs:
    case Nil{}:
      walk
    case Con{+g, rest}:
      match walk:
        case StoryGraph.Got{+idx, +s}:
          bg_graphs(build, rest, bg_nodes(build, StoryGraph.copy_order(s, g), StoryGraph.Got{idx, s}, g, StoryGraph.gf(s, g, StoryGraph.g_background()), lo, hi), lo, hi)

# Story:AddBGNodes(lo, hi) over pairs(root.children): lo to hi background rooms per node (math.random(lo, hi); the
# forest's range is 0..2, the caves' 0..1), two blocker blanks per entrance node; bg_idx runs across all graphs.
def add_bg_nodes(+build: Builds.Build, +s: StoryGraph.St, +lo: U32, +hi: U32) -> StoryGraph.St:
  +before = StoryGraph.rng_of(s)
  StoryGraph.returned(StoryGraph.st(bg_graphs(build, StoryGraph.children_order(s), StoryGraph.Got{0, StoryGraph.say(s)}, lo, hi)), StoryGraph.f_add_bg_nodes(), before)

def cove_max_edges(+build: Builds.Build, +task: U32) -> U32:
  +m = StoryCatalog.task_cove_room_max_edges(build, task)
  Bool.pick(U32, Blob.is_none(m), StoryCatalog.default_cove_max_edges(build), m)

def cove_eligible(+s: StoryGraph.St, +node: U32, +max_edges: U32) -> Bool:
  +t = StoryGraph.nf(s, node, StoryGraph.f_type())
  Bool.not(StoryGraph.is_entrance(s, node)) && U32.is_ne(t, Enums.node_type_blank()) && U32.is_ne(t, Enums.node_type_background_room())
    && U32.is_ne(StoryGraph.nf(s, node, StoryGraph.f_kind()), StoryGraph.id_start()) && (StoryGraph.nf(s, node, StoryGraph.f_edges()) <= max_edges : U32)

def cove_added(+build: Builds.Build, hit: Bool, +s: StoryGraph.St, +g: U32, +node: U32, +room: U32, +idx: U32) -> StoryGraph.Got:
  match hit:
    case True{}:
      +added = StoryGraph.add_node(build, MapTags.extras(build, s, room, g), g, background_room(build, StoryGraph.id_cove(), g, idx, room))
      StoryGraph.Got{(idx + 1 : U32), attached(added, node)}
    case False{}:
      StoryGraph.Got{idx, s}

def cove_rolled(+build: Builds.Build, +hit: StoryGraph.Got, +g: U32, +node: U32, +room: U32, +idx: U32) -> StoryGraph.Got:
  match hit:
    case StoryGraph.Got{+h, +s}:
      cove_added(build, U32.is_eq(h, 1), s, g, node, room, idx)

def cove_of(+build: Builds.Build, eligible: Bool, +s: StoryGraph.St, +g: U32, +node: U32, +task: U32, +idx: U32) -> StoryGraph.Got:
  match eligible:
    case True{}:
      cove_rolled(build, StoryGraph.below(s, StoryCatalog.task_cove_threshold(build, task)), g, node, StoryCatalog.task_cove_room(build, task), idx)
    case False{}:
      StoryGraph.Got{idx, s}

def cove_nodes(+build: Builds.Build, nodes: List<&2, U32>, +walk: StoryGraph.Got, +g: U32, +task: U32) -> StoryGraph.Got:
  match nodes:
    case Nil{}:
      walk
    case Con{+node, rest}:
      match walk:
        case StoryGraph.Got{+idx, +s}:
          cove_nodes(build, rest, cove_of(build, cove_eligible(s, node, cove_max_edges(build, task)), s, g, node, task, idx), g, task)

def cove_graph(+build: Builds.Build, task_graph: Bool, +s: StoryGraph.St, +g: U32) -> StoryGraph.St:
  match task_graph:
    case True{}:
      +task = StoryGraph.gf(s, g, StoryGraph.g_part())
      StoryGraph.st(cove_nodes(build, StoryGraph.copy_order(s, g), StoryGraph.Got{0, s}, g, task))
    case False{}:
      s

def no_coves(+build: Builds.Build, +task: U32) -> Bool:
  +chance = StoryCatalog.task_cove_room_chance(build, task)
  (Bool.not(Blob.is_none(chance)) && U32.is_zero(chance)) || U32.is_zero(StoryCatalog.task_cove_room_max_edges(build, task))

def coved(+build: Builds.Build, stop: Bool, +task_graph: Bool, +s: StoryGraph.St, +g: U32) -> StoryGraph.St:
  match stop:
    case True{}:
      s
    case False{}:
      cove_graph(build, task_graph, s, g)

def cove_graphs(+build: Builds.Build, graphs: List<&2, U32>, stopped: Bool, +s: StoryGraph.St) -> StoryGraph.St:
  match graphs:
    case Nil{}:
      s
    case Con{+g, rest}:
      match stopped:
        case True{}:
          s
        case False{}:
          +task_graph = U32.is_eq(StoryGraph.gf(s, g, StoryGraph.g_kind()), StoryGraph.k_task())
          +stop = task_graph && no_coves(build, StoryGraph.gf(s, g, StoryGraph.g_part()))
          cove_graphs(build, rest, stop, coved(build, stop, task_graph, s, g))

# Story:AddCoveNodes over the given graphs (pairs order): each leaf-ish node of a task draws math.random() against
# the task's cove chance; a task with chance 0 or max_edges 0 ends the whole pass.
def add_cove_nodes(+build: Builds.Build, +s: StoryGraph.St, +graphs: List<&2, U32>) -> StoryGraph.St:
  +before = StoryGraph.rng_of(s)
  StoryGraph.returned(cove_graphs(build, graphs, False{}, StoryGraph.say(s)), StoryGraph.f_add_cove_nodes(), before)

def loop_sub(+build: Builds.Build, +n: U32) -> StoryGraph.Info:
  StoryGraph.NodeData{StoryGraph.id_loop_sub(), 0, n, StoryGraph.none(), Enums.node_type_blank(), StoryData.impassable_value(build), Enums.connection_edge_site(), 0,
    StoryGraph.none(), StoryGraph.none(), StoryGraph.none(), StoryGraph.none(), 0, 0}

def blank_locked(+added: StoryGraph.Got, +from: U32, +to: U32) -> StoryGraph.St:
  match added:
    case StoryGraph.Got{+blank, +s}:
      StoryGraph.lock(StoryGraph.lock(StoryGraph.bump(s, StoryGraph.s_loop_blanks()), from, blank), to, blank)

def blank_graph(+build: Builds.Build, +made: StoryGraph.Got, +n: U32, +from: U32, +to: U32) -> StoryGraph.St:
  match made:
    case StoryGraph.Got{+g, +s}:
      blank_locked(StoryGraph.add_node(build, StoryGraph.graph_child(s, g), g, loop_sub(build, n)), from, to)

# Story:SeperateStoryByBlanks(from, to): a LOOP_BLANK graph with one blank node, locked to both nodes.
def separate_by_blanks(+build: Builds.Build, +s: StoryGraph.St, +from: U32, +to: U32) -> StoryGraph.St:
  +n = StoryGraph.get(s, StoryGraph.s_loop_blanks())
  blank_graph(build, StoryGraph.new_graph(build, s, StoryGraph.k_loop_blank(), n, StoryData.impassable_value(build), StoryData.bg_impassable_room(build)), n, from, to)
