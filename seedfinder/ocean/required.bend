import Base
import ../data/rooms.bend as RM
import ../data/tasks.bend as TK
import ../storygen/graph.bend as GG
import ../populate/nodes.bend as PN
import ./post.bend as OT

# forest_map's required prefab table from the story: GAME_root:GetRequiredPrefabs() is every task graph's task
# required_prefabs plus every node's room required_prefabs (Graph:AddNode adds them to the node's graph), then
# level.required_prefabs and the ocean rooms' (ocean/post.bend double_check).

def room_added(empty: Bool, +room: U32, +reqs: List<&2, OT.Req>) -> List<&2, OT.Req>:
  match empty:
    case True{}:
      reqs
    case False{}:
      OT.add_ones(RM.room_required_prefabs(room), reqs)

def nodes_loop(n: Nat, +s: GG.St, +i: U32, +reqs: List<&2, OT.Req>) -> List<&2, OT.Req>:
  match n:
    case 0n:
      reqs
    case 1n+p:
      +room = PN.room(s, i)
      nodes_loop(p, s, (i + 1 : U32), room_added(U32.is_eq(room, PN.none()), room, reqs))

def task_added(task: Bool, +id: U32, +reqs: List<&2, OT.Req>) -> List<&2, OT.Req>:
  match task:
    case False{}:
      reqs
    case True{}:
      OT.add_ones(TK.task_required_prefabs(id), reqs)

def graphs_loop(n: Nat, +s: GG.St, +g: U32, +reqs: List<&2, OT.Req>) -> List<&2, OT.Req>:
  match n:
    case 0n:
      reqs
    case 1n+p:
      +task = U32.is_eq(GG.gf(s, g, GG.g_kind()), GG.k_task())
      graphs_loop(p, s, (g + 1 : U32), task_added(task, GG.gf(s, g, GG.g_part()), reqs))

# GAME_root:GetRequiredPrefabs() of a finished story.
def root_required(+s: GG.St) -> List<&2, OT.Req>:
  +nodes = nodes_loop(U32.to_nat(GG.get(s, GG.s_nodes())), s, 0, Nil{})
  graphs_loop(U32.to_nat(GG.get(s, GG.s_graphs())), s, 0, nodes)

# The whole double_check of an attempt with this story.
def required(+s: GG.St) -> List<&2, OT.Req>:
  OT.double_check(root_required(s))
