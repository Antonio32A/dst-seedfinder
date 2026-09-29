import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../lua/strhash.bend as StrHash
import ./catalog.bend as StoryCatalog
import ./mem.bend as StoryMem
import ./order.bend as StoryOrder

# The story graph (network.lua Graph/Node/Edge) as one persistent word array, plus the log of every WorldSim call and
# wrapped Lua function in execution order, and the RNG. Graph 0 is GAME_root; every other graph is a child of the root,
# created in root.children insertion order. Nodes and edges are numbered in creation order.

# One entry of the log. EGraph: AddChild(root, graph id, ...); ENode: AddChild(graph, node id, ...); ELink: AddLink or
# AddExternalLink; ECall: another WorldSim call (method codes below); ELua: a wrapped Lua function returned.
type Ev is Data:
  EGraph{graph: U32, rng: Pcg.Rng}
  ENode{node: U32, rng: Pcg.Rng}
  ELink{external: Bool, from: U32, to: U32, rng: Pcg.Rng}
  ECall{method: U32, rng: Pcg.Rng}
  ELua{func: U32, before: Pcg.Rng, after: Pcg.Rng}

type St is Data:
  St{mem: StoryMem.Mem, log: List<&2, Ev>, rng: Pcg.Rng}

# A result next to the state.
type Got is Data:
  Got{v: U32, st: St}

def none() -> U32:
  4294967295

def val(+g: Got) -> U32:
  match g:
    case Got{+v, _}:
      v

def st(+g: Got) -> St:
  match g:
    case Got{_, +s}:
      s

def m_set_points_barren() -> U32:
  0

def m_set_resolve_noise() -> U32:
  1

def m_set_validate_ground() -> U32:
  2

def m_print() -> U32:
  3

def m_set_world_size() -> U32:
  4

def m_get_site() -> U32:
  5

def m_initialize_node_points() -> U32:
  6

def m_voronoi_pass() -> U32:
  7

def m_add_new_positions() -> U32:
  8

def m_commit() -> U32:
  9

def f_build_story() -> U32:
  0

def f_generate_nodes_from_tasks() -> U32:
  1

def f_add_bg_nodes() -> U32:
  2

def f_add_cove_nodes() -> U32:
  3

def f_insert_additional_set_pieces() -> U32:
  4

def f_add_regions_to_mainland() -> U32:
  5

def f_link_nodes_by_keys() -> U32:
  6

def f_restrict_nodes_by_key() -> U32:
  7

def f_process_ocean_content() -> U32:
  8

def f_place_teleportato_parts() -> U32:
  9

def f_process_extra_tags() -> U32:
  10

def s_nodes() -> U32:
  0

def s_graphs() -> U32:
  1

def s_edges() -> U32:
  2

def s_loop_blanks() -> U32:
  3

def s_region_links() -> U32:
  4

def s_tags_used() -> U32:
  5

def s_extras() -> U32:
  6

def s_pieces() -> U32:
  7

def s_entrance() -> U32:
  8

def s_globals() -> U32:
  9

def graph_base() -> U32:
  64

def node_base() -> U32:
  1024

def edge_base() -> U32:
  33792

def extra_base() -> U32:
  37888

def piece_base() -> U32:
  38912

def site_base() -> U32:
  40960

def global_base() -> U32:
  44032

def k_root() -> U32:
  0

def k_task() -> U32:
  1

def k_loop_blank() -> U32:
  2

def k_region_link() -> U32:
  3

def g_kind() -> U32:
  0

def g_part() -> U32:
  1

def g_hash() -> U32:
  2

def g_first() -> U32:
  3

def g_last() -> U32:
  4

def g_count() -> U32:
  5

def g_depth() -> U32:
  6

def g_entrance() -> U32:
  7

def g_first_edge() -> U32:
  8

def g_background() -> U32:
  9

def g_tile() -> U32:
  10

def id_room() -> U32:
  0

def id_bg() -> U32:
  1

def id_cove() -> U32:
  2

def id_start() -> U32:
  3

def id_blocker() -> U32:
  4

def id_loop_sub() -> U32:
  5

def id_region_sub() -> U32:
  6

def f_graph() -> U32:
  0

def f_hash() -> U32:
  1

def f_kind() -> U32:
  2

def f_a() -> U32:
  3

def f_b() -> U32:
  4

def f_c() -> U32:
  5

def f_type() -> U32:
  6

def f_value() -> U32:
  7

def f_itype() -> U32:
  8

def f_entrance() -> U32:
  9

def f_exit_weight() -> U32:
  10

def f_entrance_weight() -> U32:
  11

def f_task() -> U32:
  12

def f_edges() -> U32:
  13

def f_first_other() -> U32:
  14

def f_next() -> U32:
  15

def f_room() -> U32:
  16

def f_depth() -> U32:
  17

def f_blocker_blank() -> U32:
  18

def mem_of(+s: St) -> StoryMem.Mem:
  match s:
    case St{+m, _, _}:
      m

def rng_of(+s: St) -> Pcg.Rng:
  match s:
    case St{_, _, +rng}:
      rng

def log_of(+s: St) -> List<&2, Ev>:
  match s:
    case St{_, +log, _}:
      log

def get(+s: St, +slot: U32) -> U32:
  StoryMem.get(mem_of(s), slot)

def put(+s: St, +slot: U32, +v: U32) -> St:
  match s:
    case St{+m, +log, +rng}:
      St{StoryMem.set(m, slot, v), log, rng}

def bump(+s: St, +slot: U32) -> St:
  put(s, slot, (get(s, slot) + 1 : U32))

def with_rng(+s: St, +rng: Pcg.Rng) -> St:
  match s:
    case St{+m, +log, _}:
      St{m, log, rng}

def emit(+s: St, +ev: Ev) -> St:
  match s:
    case St{+m, +log, +rng}:
      St{m, ev <> log, rng}

def call(+s: St, +method: U32) -> St:
  emit(s, ECall{method, rng_of(s)})

def say(+s: St) -> St:
  call(s, m_print())

# The record of a wrapped Lua function that started at `before` and returns now.
def returned(+s: St, +func: U32, +before: Pcg.Rng) -> St:
  emit(s, ELua{func, before, rng_of(s)})

# `returned` on the state of a result, keeping its value.
def returned_got(+g: Got, +func: U32, +before: Pcg.Rng) -> Got:
  match g:
    case Got{+v, +s}:
      Got{v, returned(s, func, before)}

def drawn(+x: U32, +rng: Pcg.Rng, +s: St) -> Got:
  Got{x, with_rng(s, rng)}

def drawn_pair(got: U32 & Pcg.Rng, +s: St) -> Got:
  (+x, +rng) = got
  drawn(x, rng, s)

# One raw PCG32 output (math.random() is x / (2^32 - 1)).
def draw(+s: St) -> Got:
  drawn_pair(Pcg.draw(rng_of(s)), s)

# math.random(u)
def upto(+s: St, +u: U32) -> Got:
  drawn_pair(MathRandom.random_upto(rng_of(s), u), s)

# math.random(m, n)
def range(+s: St, +m: U32, +n: U32) -> Got:
  drawn_pair(MathRandom.random_range(rng_of(s), m, n), s)

# math.random() < p, for the exact threshold of p: 1 or 0.
def below(+s: St, +threshold: U32) -> Got:
  +g = draw(s)
  Got{Bool.to_u32((val(g) < threshold : U32)), st(g)}

def node_slot(+n: U32, +f: U32) -> U32:
  ((node_base() + (n * 32 : U32) : U32) + f : U32)

def graph_slot(+g: U32, +f: U32) -> U32:
  ((graph_base() + (g * 16 : U32) : U32) + f : U32)

def nf(+s: St, +n: U32, +f: U32) -> U32:
  get(s, node_slot(n, f))

def set_nf(+s: St, +n: U32, +f: U32, +v: U32) -> St:
  put(s, node_slot(n, f), v)

def gf(+s: St, +g: U32, +f: U32) -> U32:
  get(s, graph_slot(g, f))

def set_gf(+s: St, +g: U32, +f: U32, +v: U32) -> St:
  put(s, graph_slot(g, f), v)

def is_entrance(+s: St, +n: U32) -> Bool:
  U32.is_eq(nf(s, n, f_entrance()), 1)

def graph_name_of(+kind: U32, +part: U32) -> String:
  match kind:
    case 0:
      "GAME_root"
    case 1:
      StoryCatalog.task_name(part)
    case 2:
      "LOOP_BLANK" ++ U32.show(part)
    case _:
      "REGION_LINK_" ++ U32.show(part)

def graph_name(+s: St, +g: U32) -> String:
  graph_name_of(gf(s, g, g_kind()), gf(s, g, g_part()))

def base_name(+kind: U32, +graph: String, +b: U32, +c: U32) -> String:
  match kind:
    case 0:
      graph ++ ":" ++ U32.show(b) ++ ":" ++ StoryCatalog.room_name(c)
    case 1:
      graph ++ ":BG_" ++ U32.show(b) ++ ":" ++ StoryCatalog.room_name(c)
    case 2:
      graph ++ ":COVE_" ++ U32.show(b) ++ ":" ++ StoryCatalog.room_name(c)
    case 3:
      "START"
    case 5:
      "LOOP_BLANK_SUB " ++ U32.show(b)
    case _:
      graph ++ ":REGION_LINK_SUB_" ++ U32.show(b)

def own_name(+s: St, +n: U32) -> String:
  base_name(nf(s, n, f_kind()), graph_name(s, nf(s, n, f_graph())), nf(s, n, f_b()), nf(s, n, f_c()))

def name_by_kind(blocker: Bool, +s: St, +n: U32) -> String:
  match blocker:
    case True{}:
      own_name(s, nf(s, n, f_a())) ++ ":BLOCKER_BLANK_" ++ U32.show(nf(s, n, f_b()))
    case False{}:
      own_name(s, n)

# The node's id string.
def node_name(+s: St, +n: U32) -> String:
  name_by_kind(U32.is_eq(nf(s, n, f_kind()), id_blocker()), s, n)

# A new graph, child of the root (Graph(id, {parent = root}) and root.children[id] = graph). No WorldSim call.
def put_block(+s: St, +slot: U32, +k: Nat, +words: List<&2, U32>) -> St:
  match s:
    case St{+m, +log, +rng}:
      St{StoryMem.set_block(m, slot, k, StoryMem.block(k, words)), log, rng}

def new_graph(+s: St, +kind: U32, +part: U32, +tile: U32, +background: U32) -> Got:
  +g = get(s, s_graphs())
  +fields = {[kind, part, StrHash.hash_string(graph_name_of(kind, part)), none(), none(), 0, none(), none(), get(s, s_edges()), background, tile] : List<&2, U32>}
  Got{g, put_block(put(s, s_graphs(), (g + 1 : U32)), graph_slot(g, 0), 4n, fields)}

# WorldSim:AddChild(root, graph id, tile, ...) for a graph.
def graph_child(+s: St, +g: U32) -> St:
  emit(s, EGraph{g, rng_of(s)})

# The fields of a node's data table that later stages read.
type Info is Data:
  NodeData{
    kind: U32, a: U32, b: U32, c: U32, ntype: U32, value: U32, itype: U32, entrance: U32, exit_weight: U32,
    entrance_weight: U32, task: U32, room: U32, depth: U32, blocker: U32
  }

def chained_member(first: Bool, +s: St, +g: U32, +n: U32, +last: U32) -> St:
  match first:
    case True{}:
      set_gf(s, g, g_first(), n)
    case False{}:
      set_nf(s, last, f_next(), n)

def link_member(+s: St, +g: U32, +n: U32, +last: U32) -> St:
  +linked = chained_member(U32.is_eq(last, none()), s, g, n, last)
  set_gf(set_gf(linked, g, g_last(), n), g, g_count(), (gf(s, g, g_count()) + 1 : U32))

def entrance_marked(entrance: Bool, +s: St, +g: U32, +n: U32) -> St:
  match entrance:
    case True{}:
      set_gf(s, g, g_entrance(), n)
    case False{}:
      s

def mark_entrance(+s: St, +g: U32, +n: U32, +entrance: U32) -> St:
  entrance_marked(U32.is_eq(entrance, 1), s, g, n)

# A new node's 32 words (graph, hash 0 until `hashed`, the data, no edges yet).
def store_data(+s: St, +n: U32, +g: U32, +d: Info) -> St:
  match d:
    case NodeData{+kind, +a, +b, +c, +ntype, +value, +itype, +entrance, +exit_weight, +entrance_weight, +task, +room, +depth, +blocker}:
      put_block(s, node_slot(n, 0), 5n, [g, 0, kind, a, b, c, ntype, value, itype, entrance, exit_weight, entrance_weight, task, 0, none(),
        none(), room, depth, blocker])

def entrance_of(+d: Info) -> U32:
  match d:
    case NodeData{_, _, _, _, _, _, _, +entrance, _, _, _, _, _, _}:
      entrance

def hashed(+s: St, +n: U32) -> St:
  set_nf(s, n, f_hash(), StrHash.hash_string(node_name(s, n)))

# Graph:AddNode: the node joins graph g (nodes[id] = node, entrancenode) and WorldSim:AddChild(graph, node, ...).
def add_node(+s: St, +g: U32, +d: Info) -> Got:
  +n = get(s, s_nodes())
  +s1 = hashed(store_data(put(s, s_nodes(), (n + 1 : U32)), n, g, d), n)
  +s2 = mark_entrance(link_member(s1, g, n, gf(s1, g, g_last())), g, n, entrance_of(d))
  Got{n, emit(s2, ENode{n, rng_of(s2)})}

def first_touch(first: Bool, +s: St, +n: U32, +other: U32) -> St:
  match first:
    case True{}:
      set_nf(s, n, f_first_other(), other)
    case False{}:
      s

def touch(+s: St, +n: U32, +other: U32) -> St:
  +count = nf(s, n, f_edges())
  first_touch(U32.is_zero(count), set_nf(s, n, f_edges(), (count + 1 : U32)), n, other)

# Edge(node1, node2) plus WorldSim:AddLink (Graph:AddEdge) or AddExternalLink (Graph:LockGraph).
def add_edge(+s: St, +external: Bool, +a: U32, +b: U32) -> St:
  +e = get(s, s_edges())
  +s1 = put(put(put(s, s_edges(), (e + 1 : U32)), (edge_base() + (e * 2 : U32) : U32), a), ((edge_base() + (e * 2 : U32) : U32) + 1 : U32), b)
  +s2 = touch(touch(s1, a, b), b, a)
  emit(s2, ELink{external, a, b, rng_of(s2)})

def link(+s: St, +a: U32, +b: U32) -> St:
  add_edge(s, False{}, a, b)

def lock(+s: St, +a: U32, +b: U32) -> St:
  add_edge(s, True{}, a, b)

# link(s, a, b) when `linked`, else s (the link is only built when taken).
def link_if(linked: Bool, +s: St, +a: U32, +b: U32) -> St:
  match linked:
    case True{}:
      link(s, a, b)
    case False{}:
      s

def connects(+s: St, +e: U32, +a: U32, +b: U32) -> Bool:
  +x = get(s, (edge_base() + (e * 2 : U32) : U32))
  +y = get(s, ((edge_base() + (e * 2 : U32) : U32) + 1 : U32))
  (U32.is_eq(x, a) && U32.is_eq(y, b)) || (U32.is_eq(x, b) && U32.is_eq(y, a))

def connected_loop(n: Nat, +s: St, +e: U32, +a: U32, +b: U32) -> Bool:
  match n:
    case 0n:
      False{}
    case 1n+p:
      connects(s, e, a, b) || connected_loop(p, s, (e + 1 : U32), a, b)

# Node:IsConnectedTo for two nodes of graph g (every edge touching them was made after g was).
def connected(+s: St, +g: U32, +a: U32, +b: U32) -> Bool:
  +first = gf(s, g, g_first_edge())
  connected_loop(U32.to_nat((get(s, s_edges()) - first : U32)), s, first, a, b)

def members_loop(n: Nat, +s: St, +node: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      node <> members_loop(p, s, nf(s, node, f_next()))

# The nodes of graph g in insertion order.
def members(+s: St, +g: U32) -> List<&2, U32>:
  members_loop(U32.to_nat(gf(s, g, g_count())), s, gf(s, g, g_first()))

def node_slots(+s: St, nodes: List<&2, U32>) -> List<&2, StoryOrder.Slot>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      StoryOrder.Slot{nf(s, n, f_hash()), n} <> node_slots(s, rest)

# pairs() order of a fresh table after t[node id] = node for each of `nodes` in turn.
def node_table_order(+s: St, +nodes: List<&2, U32>) -> List<&2, U32>:
  StoryOrder.order(node_slots(s, nodes))

# pairs(graph.nodes)
def node_order(+s: St, +g: U32) -> List<&2, U32>:
  node_table_order(s, members(s, g))

# pairs(graph:GetNodes(false)): a copy made by inserting in pairs(graph.nodes) order.
def copy_order(+s: St, +g: U32) -> List<&2, U32>:
  node_table_order(s, node_order(s, g))

def graph_slots(+s: St, graphs: List<&2, U32>) -> List<&2, StoryOrder.Slot>:
  match graphs:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      StoryOrder.Slot{gf(s, g, g_hash()), g} <> graph_slots(s, rest)

# pairs() order of a fresh table keyed by graph ids, inserted in the given order.
def graph_table_order(+s: St, +graphs: List<&2, U32>) -> List<&2, U32>:
  StoryOrder.order(graph_slots(s, graphs))

def span(n: Nat, +from: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      from <> span(p, (from + 1 : U32))

# pairs(root.children): every graph but the root, inserted in creation order.
def children_order(+s: St) -> List<&2, U32>:
  graph_table_order(s, span(U32.to_nat((get(s, s_graphs()) - 1 : U32)), 1))

# Records a set piece placed into a node's countstaticlayouts (string id and layout index of the name).
def place_piece(+s: St, +n: U32, +name: U32, +layout: U32) -> St:
  +k = get(s, s_pieces())
  +slot = (piece_base() + (k * 3 : U32) : U32)
  put(put(put(put(s, s_pieces(), (k + 1 : U32)), slot, n), (slot + 1 : U32), name), (slot + 2 : U32), layout)

# Records a map tag result in a node's terrain_contents_extra: kind 3 ITEM (a prefab string id) or 4 STATIC (layout).
def add_extra(+s: St, +n: U32, +kind: U32, +value: U32) -> St:
  +k = get(s, s_extras())
  +slot = (extra_base() + (k * 3 : U32) : U32)
  put(put(put(put(s, s_extras(), (k + 1 : U32)), slot, n), (slot + 1 : U32), kind), (slot + 2 : U32), value)

# Records a GLOBALTAG result (Story.GlobalTags[tag][task]): the caves tag id, the task's graph and the node's id.
def add_global(+s: St, +tag: U32, +g: U32, +node: U32) -> St:
  +k = get(s, s_globals())
  +slot = (global_base() + (k * 3 : U32) : U32)
  put(put(put(put(s, s_globals(), (k + 1 : U32)), slot, tag), (slot + 1 : U32), g), (slot + 2 : U32), node)

def fresh(+rng: Pcg.Rng) -> St:
  St{StoryMem.empty(), Nil{}, rng}

# The empty story: GAME_root only, loop_blanks and region_link_tasks at 1.
def initial(+rng: Pcg.Rng) -> St:
  put(put(st(new_graph(fresh(rng), k_root(), 0, 0, none())), s_loop_blanks(), 1), s_region_links(), 1)
