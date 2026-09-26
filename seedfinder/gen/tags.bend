import Base
import ../data/rooms.bend as Rooms
import ../data/tasks.bend as Tasks
import ../data/gen_tags.bend as GenTagsData
import ../storygen/graph.bend as StoryGraph

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
      bits_of(Rooms.room_tags(room))

def task_bits(task: Bool, +id: U32) -> U32:
  match task:
    case False{}:
      0
    case True{}:
      bits_of(List.drop(&2, U32, Tasks.task_room_tags(id), 1n))

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
