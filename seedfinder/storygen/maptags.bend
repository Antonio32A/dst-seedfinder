import Base
import ../data/blob.bend as B
import ../data/rooms.bend as RM
import ../data/story.bend as SY
import ./graph.bend as GG

# Story:GetExtrasForRoom with MapTags (maptags.lua): a room's tags run their tag functions in ipairs order. Only the
# one-shot ITEM and STATIC tags have effects here: the first room carrying one gets its prefab or layout in
# terrain_contents_extra (Terrarium_Spawner picks one of its layouts with math.random(3)). TAG and GLOBALTAG results
# are node tags and global tags, which later stages derive from the room.

def is_extra(+kind: U32) -> Bool:
  U32.is_eq(kind, 3) || U32.is_eq(kind, 4)

def recorded(extra: Bool, +s: GG.St, +node: U32, +kind: U32, +row: List<&2, U32>, +k: U32) -> GG.St:
  match extra:
    case True{}:
      GG.add_extra(s, node, kind, B.at(row, (5 + k : U32)))
    case False{}:
      s

def record(+s: GG.St, +node: U32, +row: List<&2, U32>, +k: U32) -> GG.St:
  +kind = B.at(row, 2)
  recorded((k < B.at(row, 4) : U32) && is_extra(kind), s, node, kind, row, k)

def chosen(several: Bool, +s: GG.St, +node: U32, +row: List<&2, U32>) -> GG.St:
  match several:
    case True{}:
      +g = GG.upto(s, B.at(row, 4))
      record(GG.st(g), node, row, (GG.val(g) - 1 : U32))
    case False{}:
      record(s, node, row, 0)

def fire(first: Bool, +s: GG.St, +node: U32, +row: List<&2, U32>, +bit: U32) -> GG.St:
  match first:
    case True{}:
      +used = GG.put(s, GG.s_tags_used(), (GG.get(s, GG.s_tags_used()) .|. bit : U32))
      chosen((B.at(row, 4) >= 2 : U32), used, node, row)
    case False{}:
      s

def run_tag(+s: GG.St, +node: U32, +tag: U32) -> GG.St:
  +row = RM.maptags(tag)
  +bit = (1 << U32.to_nat(tag) : U32)
  +unused = U32.is_zero((GG.get(s, GG.s_tags_used()) .&. bit : U32))
  fire(U32.is_eq(B.at(row, 3), 1) && unused, s, node, row, bit)

def run_tags(tags: List<&2, U32>, +s: GG.St, +node: U32) -> GG.St:
  match tags:
    case Nil{}:
      s
    case Con{+tag, rest}:
      run_tags(rest, run_tag(s, node, tag), node)

# GetExtrasForRoom(room) for the node about to be added (node = the next node index).
def extras(+s: GG.St, +room: U32) -> GG.St:
  run_tags(SY.room_maptags(room), s, GG.get(s, GG.s_nodes()))
