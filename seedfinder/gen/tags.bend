import Base
import ../data/rooms.bend as RM
import ../data/tasks.bend as TK
import ../data/gen_tags.bend as TA
import ../storygen/graph.bend as GG

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
  (bit(has(tags, TA.tag_force_connected()), 2) .|. bit(has(tags, TA.tag_road_poison()), 4) .|. bit(has(tags, TA.tag_force_disconnected()), 8) : U32)

def room_bits(absent: Bool, +room: U32) -> U32:
  match absent:
    case True{}:
      0
    case False{}:
      bits_of(RM.room_tags(room))

def task_bits(task: Bool, +id: U32) -> U32:
  match task:
    case False{}:
      0
    case True{}:
      bits_of(List.drop(&2, U32, TK.task_room_tags(id), 1n))

def synthetic(+kind: U32) -> Bool:
  U32.is_eq(kind, GG.id_blocker()) || U32.is_eq(kind, GG.id_loop_sub()) || U32.is_eq(kind, GG.id_region_sub())

# The poison bits of story node n.
def poison(+s: GG.St, +n: U32) -> U32:
  +room = GG.nf(s, n, GG.f_room())
  +g = GG.nf(s, n, GG.f_graph())
  +task = task_bits(U32.is_eq(GG.gf(s, g, GG.g_kind()), GG.k_task()), GG.gf(s, g, GG.g_part()))
  (room_bits(U32.is_eq(room, GG.none()), room) .|. task .|. bit(synthetic(GG.nf(s, n, GG.f_kind())), 12) : U32)

# SetSiteFlags(id, flags) of story node n.
def site_flags(+s: GG.St, +n: U32) -> U32:
  (poison(s, n) .&. 6 : U32)

# 1 when ApplyPoisonTag clears story node n's links, else 0.
def disconnected(+s: GG.St, +n: U32) -> U32:
  ((poison(s, n) >> 3n) .&. 1 : U32)
