import Base
import ../data/blob.bend as Blob
import ../data/rooms.bend as Rooms
import ../data/story.bend as StoryData
import ./graph.bend as StoryGraph

# Story:GetExtrasForRoom with MapTags (maptags.lua): a room's tags run their tag functions in ipairs order. Only the
# one-shot ITEM and STATIC tags have effects here: the first room carrying one gets its prefab or layout in
# terrain_contents_extra (Terrarium_Spawner picks one of its layouts with math.random(3)). TAG and GLOBALTAG results
# are node tags and global tags, which later stages derive from the room.

def is_extra(+kind: U32) -> Bool:
  U32.is_eq(kind, 3) || U32.is_eq(kind, 4)

def recorded(extra: Bool, +s: StoryGraph.St, +node: U32, +kind: U32, +row: List<&2, U32>, +k: U32) -> StoryGraph.St:
  match extra:
    case True{}:
      StoryGraph.add_extra(s, node, kind, Blob.at(row, (5 + k : U32)))
    case False{}:
      s

def record(+s: StoryGraph.St, +node: U32, +row: List<&2, U32>, +k: U32) -> StoryGraph.St:
  +kind = Blob.at(row, 2)
  recorded((k < Blob.at(row, 4) : U32) && is_extra(kind), s, node, kind, row, k)

def chosen_pick(+node: U32, +row: List<&2, U32>, +g: StoryGraph.Got) -> StoryGraph.St:
  match g:
    case StoryGraph.Got{+k, +s}:
      record(s, node, row, (k - 1 : U32))

def chosen(several: Bool, +s: StoryGraph.St, +node: U32, +row: List<&2, U32>) -> StoryGraph.St:
  match several:
    case True{}:
      chosen_pick(node, row, StoryGraph.upto(s, Blob.at(row, 4)))
    case False{}:
      record(s, node, row, 0)

def fire(first: Bool, +s: StoryGraph.St, +node: U32, +row: List<&2, U32>, +bit: U32) -> StoryGraph.St:
  match first:
    case True{}:
      +used = StoryGraph.put(s, StoryGraph.s_tags_used(), (StoryGraph.get(s, StoryGraph.s_tags_used()) .|. bit : U32))
      chosen((Blob.at(row, 4) >= 2 : U32), used, node, row)
    case False{}:
      s

def run_tag(+s: StoryGraph.St, +node: U32, +tag: U32) -> StoryGraph.St:
  +row = Rooms.maptags(tag)
  +bit = (1 << U32.to_nat(tag) : U32)
  +unused = U32.is_zero((StoryGraph.get(s, StoryGraph.s_tags_used()) .&. bit : U32))
  fire(U32.is_eq(Blob.at(row, 3), 1) && unused, s, node, row, bit)

def run_tags(tags: List<&2, U32>, +s: StoryGraph.St, +node: U32) -> StoryGraph.St:
  match tags:
    case Nil{}:
      s
    case Con{+tag, rest}:
      run_tags(rest, run_tag(s, node, tag), node)

# GetExtrasForRoom(room) for the node about to be added (node = the next node index).
def extras(+s: StoryGraph.St, +room: U32) -> StoryGraph.St:
  run_tags(StoryData.room_maptags(room), s, StoryGraph.get(s, StoryGraph.s_nodes()))
