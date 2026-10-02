import Base
import ../f64/repr.bend as F64Repr

# The static layouts the world generation placed, for the world dump's SETP section (docs/world-dump.md).

# A layout object_layout.lua's ReserveAndPlaceLayout placed: the layout's name (string id), its source (SETP's source
# codes), its transform (bit 0 switch_xy, bit 1 flip_x = -1, bit 2 flip_y = -1, as applied), the centre it placed the
# entities around (rcx, rcy in tile coordinates), its half-size (`size`: half the ground's side, else the scale times
# half the larger extent of its entities) and, for a land layout, the savedata.ents entries it added: the from..to - 1
# oldest (the land's entity list only grows). An ocean layout's entities carry its number as they are added (from and
# to are 0).
type Piece is Data:
  Piece{name: U32, source: U32, turn: U32, cx: F64Repr.F64, cy: F64Repr.F64, half: F64Repr.F64, from: U32, to: U32}

# The piece with the entries from..to - 1 as its members.
def with_members(+p: Piece, +from: U32, +to: U32) -> Piece:
  match p:
    case Piece{+name, +source, +turn, +cx, +cy, +half, _, _}:
      Piece{name, source, turn, cx, cy, half, from, to}

# Source codes: a room's countstaticlayouts, a task set piece (Story:InsertAdditionalSetPieces), the START node's
# starting set piece, a map tag layout (terrain_contents_extra.static_layouts), level.ocean_prefill_setpieces, an ocean
# room's countstaticlayouts.
def room() -> U32:
  0

def task() -> U32:
  1

def start() -> U32:
  2

def map_tag() -> U32:
  3

def ocean_prefill() -> U32:
  4

def ocean_room() -> U32:
  5

# A maze or labyrinth of the caves' maze passes.
def maze() -> U32:
  6
