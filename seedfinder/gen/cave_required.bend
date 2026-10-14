import Base
import ../data/cave_story.bend as CaveStory
import ../storygen/graph.bend as StoryGraph
import ../storygen/catalog.bend as StoryCatalog
import ../populate/nodes.bend as PopulateNodes
import ../ocean/post.bend as OceanPost
import ../data/builds.bend as Builds

# forest_map's required prefab table of a caves attempt: level.required_prefabs (the location's and the task set's),
# then GAME_root:GetRequiredPrefabs(): every task's required_prefabs plus every node's room required_prefabs. There are
# no ocean rooms.

def room_added(+build: Builds.Build, has: Bool, +room: U32, +reqs: List<&2, OceanPost.Req>) -> List<&2, OceanPost.Req>:
  match has:
    case False{}:
      reqs
    case True{}:
      OceanPost.add_ones(CaveStory.room_required_prefabs(build, StoryCatalog.cave_room(room)), reqs)

def nodes_loop(+build: Builds.Build, n: Nat, +s: StoryGraph.St, +i: U32, +reqs: List<&2, OceanPost.Req>) -> List<&2, OceanPost.Req>:
  match n:
    case 0n:
      reqs
    case 1n+p:
      +room = StoryGraph.nf(s, i, StoryGraph.f_room())
      nodes_loop(build, p, s, (i + 1 : U32), room_added(build, StoryCatalog.is_cave_room(room) && U32.is_ne(room, PopulateNodes.none()), room, reqs))

def task_added(+build: Builds.Build, has: Bool, +task: U32, +reqs: List<&2, OceanPost.Req>) -> List<&2, OceanPost.Req>:
  match has:
    case False{}:
      reqs
    case True{}:
      OceanPost.add_ones(CaveStory.task_required_prefabs(build, StoryCatalog.cave_task(task)), reqs)

def graphs_loop(+build: Builds.Build, n: Nat, +s: StoryGraph.St, +g: U32, +reqs: List<&2, OceanPost.Req>) -> List<&2, OceanPost.Req>:
  match n:
    case 0n:
      reqs
    case 1n+p:
      +task = StoryGraph.gf(s, g, StoryGraph.g_part())
      +is_task = U32.is_eq(StoryGraph.gf(s, g, StoryGraph.g_kind()), StoryGraph.k_task())
      graphs_loop(build, p, s, (g + 1 : U32), task_added(build, is_task && StoryCatalog.is_cave_task(task), task, reqs))

# The required prefab table of an attempt with this caves story.
def required(+build: Builds.Build, +s: StoryGraph.St) -> List<&2, OceanPost.Req>:
  +nodes = nodes_loop(build, U32.to_nat(StoryGraph.get(s, StoryGraph.s_nodes())), s, 0, OceanPost.add_ones(CaveStory.level_required_prefabs(build, 0), OceanPost.add_ones(CaveStory.taskset_required_prefabs(build, 0), Nil{})))
  graphs_loop(build, U32.to_nat(StoryGraph.get(s, StoryGraph.s_graphs())), s, 0, nodes)
