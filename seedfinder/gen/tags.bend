import Base
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../data/gen_tags.bend as GenTagsData
import ../data/cave_story.bend as CaveStory
import ../storygen/graph.bend as StoryGraph
import ../storygen/catalog.bend as StoryCatalog

# Graph:ApplyPoisonTag (network.lua): a node's tags are its room's tags (MapTags passes these three through as TAG)
# plus its task's room_tags; the synthetic blanks (blocker, LOOP_BLANK_SUB, REGION_LINK_SUB) carry RoadPoison and
# ForceDisconnected. Bits: 2 ForceConnected, 4 RoadPoison (SetSiteFlags), 8 ForceDisconnected (ClearNodeLinks).

def has(xs: List<&2, U32>, +v: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, rest}:
      U32.is_eq(x, v) || has(rest, v)

def bit(+on: Bool, +b: U32) -> U32:
  Bool.pick(U32, on, b, 0)

def bits_of(+tags: List<&2, U32>) -> U32:
  (bit(has(tags, GenTagsData.tag_force_connected()), 2) .|. bit(has(tags, GenTagsData.tag_road_poison()), 4) .|. bit(has(tags, GenTagsData.tag_force_disconnected()), 8) : U32)

def room_bits(absent: Bool, +room: U32) -> U32:
  match absent:
    case True{}:
      0
    case False{}:
      Bool.pick(U32, StoryCatalog.is_cave_room(room), StoryCatalog.cave_room_poison(room), bits_of(Rooms.room_tags(room)))

def task_bits(task: Bool, +id: U32) -> U32:
  match task:
    case False{}:
      0
    case True{}:
      Bool.pick(U32, StoryCatalog.is_cave_task(id), StoryCatalog.cave_task_poison(id), bits_of(List.drop(&2, U32, Tasks.task_room_tags(id), 1n)))

def synthetic(+kind: U32) -> Bool:
  U32.is_eq(kind, StoryGraph.id_blocker()) || U32.is_eq(kind, StoryGraph.id_loop_sub()) || U32.is_eq(kind, StoryGraph.id_region_sub())

# The poison bits of story node n.
def poison(+s: StoryGraph.St, +n: U32) -> U32:
  +room = StoryGraph.nf(s, n, StoryGraph.f_room())
  +g = StoryGraph.nf(s, n, StoryGraph.f_graph())
  +task = task_bits(U32.is_eq(StoryGraph.gf(s, g, StoryGraph.g_kind()), StoryGraph.k_task()), StoryGraph.gf(s, g, StoryGraph.g_part()))
  (room_bits(U32.is_eq(room, StoryGraph.none()), room) .|. task .|. bit(synthetic(StoryGraph.nf(s, n, StoryGraph.f_kind())), 12) : U32)

# SetSiteFlags(id, flags) of story node n.
def site_flags(+s: StoryGraph.St, +n: U32) -> U32:
  (poison(s, n) .&. 6 : U32)

# 1 when ApplyPoisonTag clears story node n's links, else 0.
def disconnected(+s: StoryGraph.St, +n: U32) -> U32:
  ((poison(s, n) >> 3n) .&. 1 : U32)

def tag_names(tags: List<&2, U32>) -> List<&2, String>:
  match tags:
    case Nil{}:
      Nil{}
    case Con{+tag, rest}:
      CaveStory.tag_name(tag) <> tag_names(rest)

def result_names(tags: List<&2, U32>) -> List<&2, String>:
  match tags:
    case Nil{}:
      Nil{}
    case Con{+tag, rest}:
      +tail = result_names(rest)
      Bool.pick(List<&2, String>, U32.is_eq(CaveStory.tag_kind(tag), 1), CaveStory.tag_value(tag) <> tail, tail)

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

def task_tag_names(+s: StoryGraph.St, +n: U32) -> List<&2, String>:
  tag_names(CaveStory.task_room_tags(StoryCatalog.cave_task(StoryGraph.gf(s, StoryGraph.nf(s, n, StoryGraph.f_graph()), StoryGraph.g_part()))))

def room_tag_ids(+s: StoryGraph.St, +n: U32) -> List<&2, U32>:
  CaveStory.room_tags(StoryCatalog.cave_room(StoryGraph.nf(s, n, StoryGraph.f_room())))

def room_node_names(+s: StoryGraph.St, +n: U32) -> List<&2, String>:
  array_union(result_names(room_tag_ids(s, n)), task_tag_names(s, n))

def cave_names_of(kind: U32, +s: StoryGraph.St, +n: U32) -> List<&2, String>:
  match kind:
    case 0:
      room_node_names(s, n)
    case 1:
      room_node_names(s, n)
    case 2:
      room_node_names(s, n)
    case 3:
      tag_names(room_tag_ids(s, n))
    case 4:
      array_union(synthetic_tags(), task_tag_names(s, n))
    case 5:
      synthetic_tags()
    case _:
      Nil{}

# node.data.tags of a caves story node: a room's TAG results and its task's room_tags (Story:GenerateNodesFromTask,
# AddBGNodes, AddCoveNodes), the START node's own room tags, the blanks' RoadPoison and ForceDisconnected.
def cave_tag_names(+s: StoryGraph.St, +n: U32) -> List<&2, String>:
  cave_names_of(StoryGraph.nf(s, n, StoryGraph.f_kind()), s, n)
