import Base
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../storygen/graph.bend as StoryGraph
import ../populate/nodes.bend as PopulateNodes
import ./post.bend as OceanPost

# forest_map's required prefab table from the story: GAME_root:GetRequiredPrefabs() is every task graph's task
# required_prefabs plus every node's room required_prefabs (Graph:AddNode adds them to the node's graph), then
# level.required_prefabs and the ocean rooms' (ocean/post.bend double_check).

def room_added(empty: Bool, +room: U32, +reqs: List<&2, OceanPost.Req>) -> List<&2, OceanPost.Req>:
  match empty:
    case True{}:
      reqs
    case False{}:
      OceanPost.add_ones(Rooms.room_required_prefabs(room), reqs)

def nodes_loop(n: Nat, +s: StoryGraph.St, +i: U32, +reqs: List<&2, OceanPost.Req>) -> List<&2, OceanPost.Req>:
  match n:
    case 0n:
      reqs
    case 1n+p:
      +room = PopulateNodes.room(s, i)
      nodes_loop(p, s, (i + 1 : U32), room_added(U32.is_eq(room, PopulateNodes.none()), room, reqs))

def task_added(task: Bool, +id: U32, +reqs: List<&2, OceanPost.Req>) -> List<&2, OceanPost.Req>:
  match task:
    case False{}:
      reqs
    case True{}:
      OceanPost.add_ones(Tasks.task_required_prefabs(id), reqs)

def graphs_loop(n: Nat, +s: StoryGraph.St, +g: U32, +reqs: List<&2, OceanPost.Req>) -> List<&2, OceanPost.Req>:
  match n:
    case 0n:
      reqs
    case 1n+p:
      +task = U32.is_eq(StoryGraph.gf(s, g, StoryGraph.g_kind()), StoryGraph.k_task())
      graphs_loop(p, s, (g + 1 : U32), task_added(task, StoryGraph.gf(s, g, StoryGraph.g_part()), reqs))

# GAME_root:GetRequiredPrefabs() of a finished story.
def root_required(+s: StoryGraph.St) -> List<&2, OceanPost.Req>:
  +nodes = nodes_loop(U32.to_nat(StoryGraph.get(s, StoryGraph.s_nodes())), s, 0, Nil{})
  graphs_loop(U32.to_nat(StoryGraph.get(s, StoryGraph.s_graphs())), s, 0, nodes)

# The whole double_check of an attempt with this story.
def required(+s: StoryGraph.St) -> List<&2, OceanPost.Req>:
  OceanPost.double_check(root_required(s))
