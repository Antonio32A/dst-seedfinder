import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../populate/entities.bend as Entities
import ../populate/setpiece.bend as PopulateSetpiece
import ../populate/state.bend as PopulateState
import ./maze_env.bend as MazeEnv

# The mazes and labyrinths of the caves as set pieces for the world dump (docs/world-dump.md): one piece per maze or
# labyrinth, named after its task (the labyrinth: Labyrinth), centred on the entities it added, with them as members.

# The extremes of x and z over a set of entities, in world units.
type Box is Data:
  Box{x0: F64Repr.F64, x1: F64Repr.F64, z0: F64Repr.F64, z1: F64Repr.F64}

def grown(+b: Box, +e: Entities.Ent) -> Box:
  match b e:
    case Box{+x0, +x1, +z0, +z1} Entities.Ent{_, _, _, +x, +z, _, _, _}:
      Box{F64Cmp.min(x0, x), F64Cmp.max(x1, x), F64Cmp.min(z0, z), F64Cmp.max(z1, z)}

def box_of(ents: List<&2, Entities.Ent>, +b: Box) -> Box:
  match ents:
    case Nil{}:
      b
    case Con{+e, rest}:
      box_of(rest, grown(b, e))

def empty_box() -> Box:
  Box{F64Repr.inf(), F64Repr.neg_inf(), F64Repr.inf(), F64Repr.neg_inf()}

def tile_of(+t: F64Repr.F64, +w: U32) -> F64Repr.F64:
  F64Arith.add(F64Arith.div(t, Entities.tile_scale()), F64Arith.div(F64Repr.from_u32(w), F64Repr.two()))

def span(+lo: F64Repr.F64, +hi: F64Repr.F64) -> F64Repr.F64:
  F64Arith.div(F64Arith.sub(hi, lo), Entities.tile_scale())

def middle(+lo: F64Repr.F64, +hi: F64Repr.F64, +w: U32) -> F64Repr.F64:
  tile_of(F64Arith.div(F64Arith.add(lo, hi), F64Repr.two()), w)

def piece_in(+b: Box, +built: MazeEnv.Built, +offset: U32, +w: U32) -> PopulateSetpiece.Piece:
  match b built:
    case Box{+x0, +x1, +z0, +z1} MazeEnv.Built{+name, +from, +to}:
      PopulateSetpiece.Piece{name, PopulateSetpiece.maze(), 0, middle(x0, x1, w), middle(z0, z1, w),
        F64Arith.div(F64Cmp.max(span(x0, x1), span(z0, z1)), F64Repr.two()), (offset + from : U32), (offset + to : U32)}

# The entries a maze added, from the maze pass's entity list (newest first, `total` long).
def members(+ents: List<&2, Entities.Ent>, +total: U32, +built: MazeEnv.Built) -> List<&2, Entities.Ent>:
  match built:
    case MazeEnv.Built{_, +from, +to}:
      List.take(&2, Entities.Ent, List.drop(&2, Entities.Ent, ents, U32.to_nat((total - to : U32))), U32.to_nat((to - from : U32)))

def piece_of(+ents: List<&2, Entities.Ent>, +total: U32, +built: MazeEnv.Built, +offset: U32, +w: U32) -> PopulateSetpiece.Piece:
  piece_in(box_of(members(ents, total, built), empty_box()), built, offset, w)

# The land's events for the built mazes (newest first), the mazes' entities lying after `offset` older entries.
def events(built: List<&2, MazeEnv.Built>, +ents: List<&2, Entities.Ent>, +offset: U32, +w: U32) -> List<&2, PopulateState.Ev>:
  match built:
    case Nil{}:
      Nil{}
    case Con{+b, rest}:
      PopulateState.EPiece{piece_of(ents, U32.from_nat(List.length(&2, Entities.Ent, ents)), b, offset, w)} <> events(rest, ents, offset, w)
