import Base
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../data/gen_tags.bend as GenTagsData
import ../data/cave_story.bend as CaveStory
import ../data/story.bend as StoryData
import ../storygen/graph.bend as StoryGraph
import ../storygen/catalog.bend as StoryCatalog
import ../data/builds.bend as Builds

# Graph:ApplyPoisonTag (network.lua): a node's tags are its room's tags (MapTags passes these three through as TAG)
# plus its task's room_tags, and on builds whose START node takes the tags of the node it links to, that node's; the
# synthetic blanks (blocker, LOOP_BLANK_SUB, REGION_LINK_SUB) carry RoadPoison and ForceDisconnected. Bits: 2 ForceConnected, 4 RoadPoison (SetSiteFlags), 8 ForceDisconnected (ClearNodeLinks).

def has(xs: List<&2, U32>, +v: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, rest}:
      U32.is_eq(x, v) || has(rest, v)

def bit(+on: Bool, +b: U32) -> U32:
  Bool.pick(U32, on, b, 0)

def bits_of(+build: Builds.Build, +tags: List<&2, U32>) -> U32:
  (bit(has(tags, GenTagsData.tag_force_connected(build)), 2) .|. bit(has(tags, GenTagsData.tag_road_poison(build)), 4) .|. bit(has(tags, GenTagsData.tag_force_disconnected(build)), 8) : U32)

def room_bits(+build: Builds.Build, absent: Bool, +room: U32) -> U32:
  match absent:
    case True{}:
      0
    case False{}:
      Bool.pick(U32, StoryCatalog.is_cave_room(room), StoryCatalog.cave_room_poison(build, room), bits_of(build, Rooms.room_tags(build, room)))

def task_bits(+build: Builds.Build, task: Bool, +id: U32) -> U32:
  match task:
    case False{}:
      0
    case True{}:
      Bool.pick(U32, StoryCatalog.is_cave_task(id), StoryCatalog.cave_task_poison(build, id), bits_of(build, List.drop(&2, U32, Tasks.task_room_tags(build, id), 1n)))

def synthetic(+kind: U32) -> Bool:
  U32.is_eq(kind, StoryGraph.id_blocker()) || U32.is_eq(kind, StoryGraph.id_loop_sub()) || U32.is_eq(kind, StoryGraph.id_region_sub())

# Whether story node n is a START node that takes the tags of the node it links to (its first edge's other node, a room
# node of the start task).
def takes_link_tags(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> Bool:
  U32.is_eq(StoryGraph.nf(s, n, StoryGraph.f_kind()), StoryGraph.id_start()) && StoryData.start_takes_link_tags(build)

def own_poison(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> U32:
  +room = StoryGraph.nf(s, n, StoryGraph.f_room())
  +g = StoryGraph.nf(s, n, StoryGraph.f_graph())
  +task = task_bits(build, U32.is_eq(StoryGraph.gf(s, g, StoryGraph.g_kind()), StoryGraph.k_task()), StoryGraph.gf(s, g, StoryGraph.g_part()))
  (room_bits(build, U32.is_eq(room, StoryGraph.none()), room) .|. task .|. bit(synthetic(StoryGraph.nf(s, n, StoryGraph.f_kind())), 12) : U32)

def link_bits(+build: Builds.Build, takes: Bool, +s: StoryGraph.St, +n: U32) -> U32:
  match takes:
    case True{}:
      own_poison(build, s, StoryGraph.nf(s, n, StoryGraph.f_first_other()))
    case False{}:
      0

# The poison bits of story node n.
def poison(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> U32:
  (own_poison(build, s, n) .|. link_bits(build, takes_link_tags(build, s, n), s, n) : U32)

# SetSiteFlags(id, flags) of story node n.
def site_flags(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> U32:
  (poison(build, s, n) .&. 6 : U32)

# 1 when ApplyPoisonTag clears story node n's links, else 0.
def disconnected(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> U32:
  ((poison(build, s, n) >> 3n) .&. 1 : U32)

def tag_names(+build: Builds.Build, tags: List<&2, U32>) -> List<&2, String>:
  match tags:
    case Nil{}:
      Nil{}
    case Con{+tag, rest}:
      CaveStory.tag_name(build, tag) <> tag_names(build, rest)

def result_names(+build: Builds.Build, tags: List<&2, U32>) -> List<&2, String>:
  match tags:
    case Nil{}:
      Nil{}
    case Con{+tag, rest}:
      +tail = result_names(build, rest)
      Bool.pick(List<&2, String>, U32.is_eq(CaveStory.tag_kind(build, tag), 1), CaveStory.tag_value(build, tag) <> tail, tail)

def named(items: List<&2, String>, +name: String) -> Bool:
  match items:
    case Nil{}:
      False{}
    case Con{+item, rest}:
      String.eq(item, name) || named(rest, name)

def joined(seen: Bool, +name: String, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, seen, acc, List.append(&2, String, acc, [name]))

def union_into(items: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match items:
    case Nil{}:
      acc
    case Con{+item, rest}:
      union_into(rest, joined(named(acc, item), item, acc))

# ArrayUnion(a, b): the items of a then those of b, each once, in order.
def array_union(+a: List<&2, String>, +b: List<&2, String>) -> List<&2, String>:
  union_into(b, union_into(a, Nil{}))

def synthetic_tags() -> List<&2, String>:
  ["RoadPoison", "ForceDisconnected"]

def task_tag_names(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> List<&2, String>:
  tag_names(build, CaveStory.task_room_tags(build, StoryCatalog.cave_task(StoryGraph.gf(s, StoryGraph.nf(s, n, StoryGraph.f_graph()), StoryGraph.g_part()))))

def room_tag_ids(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> List<&2, U32>:
  CaveStory.room_tags(build, StoryCatalog.cave_room(StoryGraph.nf(s, n, StoryGraph.f_room())))

def room_node_names(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> List<&2, String>:
  array_union(result_names(build, room_tag_ids(build, s, n)), task_tag_names(build, s, n))

def start_names(+build: Builds.Build, takes: Bool, +s: StoryGraph.St, +n: U32) -> List<&2, String>:
  match takes:
    case True{}:
      array_union(room_node_names(build, s, StoryGraph.nf(s, n, StoryGraph.f_first_other())), tag_names(build, room_tag_ids(build, s, n)))
    case False{}:
      tag_names(build, room_tag_ids(build, s, n))

def cave_names_of(+build: Builds.Build, kind: U32, +s: StoryGraph.St, +n: U32) -> List<&2, String>:
  match kind:
    case 0:
      room_node_names(build, s, n)
    case 1:
      room_node_names(build, s, n)
    case 2:
      room_node_names(build, s, n)
    case 3:
      start_names(build, takes_link_tags(build, s, n), s, n)
    case 4:
      array_union(synthetic_tags(), task_tag_names(build, s, n))
    case 5:
      synthetic_tags()
    case _:
      Nil{}

# node.data.tags of a caves story node: a room's TAG results and its task's room_tags (Story:GenerateNodesFromTask,
# AddBGNodes, AddCoveNodes), the START node's own room tags (after the linked node's tags when the build's START node
# takes them), the blanks' RoadPoison and ForceDisconnected.
def cave_tag_names(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> List<&2, String>:
  cave_names_of(build, StoryGraph.nf(s, n, StoryGraph.f_kind()), s, n)
