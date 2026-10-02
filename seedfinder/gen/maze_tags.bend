import Base
import ../data/cave_story.bend as CaveStory
import ../data/enums.bend as Enums
import ../storygen/graph.bend as StoryGraph
import ../storygen/order.bend as StoryOrder

# What the caves' maze passes read of the finished story: Story.GlobalTags (tag value -> task -> node ids) and the
# edge lists of the nodes (Edge:Edge inserts itself into both nodes' `edges` in creation order).

# An edge as (node1, node2).
type Link is Data:
  Link{a: U32, b: U32}

def global_slot(+k: U32) -> U32:
  (StoryGraph.global_base() + (k * 3 : U32) : U32)

def global_tag_value(+s: StoryGraph.St, +k: U32) -> String:
  CaveStory.tag_value(StoryGraph.get(s, global_slot(k)))

def global_graph(+s: StoryGraph.St, +k: U32) -> U32:
  StoryGraph.get(s, (global_slot(k) + 1 : U32))

def global_node(+s: StoryGraph.St, +k: U32) -> U32:
  StoryGraph.get(s, (global_slot(k) + 2 : U32))

def new_graph(hit: Bool, +g: U32, +seen: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      Bool.pick(List<&2, U32>, StoryOrder.contains(seen, g), seen, g <> seen)
    case False{}:
      seen

def graphs_loop(n: Nat, +s: StoryGraph.St, +tag: String, +k: U32, +seen: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, seen)
    case 1n+p:
      graphs_loop(p, s, tag, (k + 1 : U32), new_graph(String.eq(global_tag_value(s, k), tag), global_graph(s, k), seen))

# pairs(Story.GlobalTags[tag]): the task graphs that got the global tag, in the order of the Lua table.
def tasks(+s: StoryGraph.St, +tag: String) -> List<&2, U32>:
  StoryGraph.graph_table_order(s, graphs_loop(U32.to_nat(StoryGraph.get(s, StoryGraph.s_globals())), s, tag, 0, Nil{}))

def nodes_add(hit: Bool, +node: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      node <> acc
    case False{}:
      acc

def nodes_loop(n: Nat, +s: StoryGraph.St, +tag: String, +g: U32, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, acc)
    case 1n+p:
      nodes_loop(p, s, tag, g, (k + 1 : U32), nodes_add(String.eq(global_tag_value(s, k), tag) && U32.is_eq(global_graph(s, k), g), global_node(s, k), acc))

# ipairs(Story.GlobalTags[tag][task]): the node ids in insertion order.
def nodes(+s: StoryGraph.St, +tag: String, +g: U32) -> List<&2, U32>:
  nodes_loop(U32.to_nat(StoryGraph.get(s, StoryGraph.s_globals())), s, tag, g, 0, Nil{})

def link_add(hit: Bool, +a: U32, +b: U32, +acc: List<&2, Link>) -> List<&2, Link>:
  match hit:
    case True{}:
      Link{a, b} <> acc
    case False{}:
      acc

def edges_loop(n: Nat, +s: StoryGraph.St, +node: U32, +e: U32, +acc: List<&2, Link>) -> List<&2, Link>:
  match n:
    case 0n:
      List.reverse(&2, Link, acc)
    case 1n+p:
      +a = StoryGraph.get(s, (StoryGraph.edge_base() + (e * 2 : U32) : U32))
      +b = StoryGraph.get(s, ((StoryGraph.edge_base() + (e * 2 : U32) : U32) + 1 : U32))
      edges_loop(p, s, node, (e + 1 : U32), link_add(U32.is_eq(a, node) || U32.is_eq(b, node), a, b, acc))

# pairs(node.edges): the edges touching the node in creation order.
def edges(+s: StoryGraph.St, +node: U32) -> List<&2, Link>:
  edges_loop(U32.to_nat(StoryGraph.get(s, StoryGraph.s_edges())), s, node, 0, Nil{})

# node.data.type ~= NODE_TYPE.Blank
def solid(+s: StoryGraph.St, +node: U32) -> Bool:
  Bool.not(U32.is_eq(StoryGraph.nf(s, node, StoryGraph.f_type()), Enums.node_type_blank()))

# Both ends of the edge are not Blank.
def is_solid(+s: StoryGraph.St, +l: Link) -> Bool:
  match l:
    case Link{+a, +b}:
      solid(s, a) && solid(s, b)
