import Base
import ../f64/repr.bend as F64Repr
import ../populate/entities.bend as Entities
import ../populate/setpiece.bend as PopulateSetpiece

# savedata.ents during the ocean phase as one list, newest first: each prefab's entries keep their insertion order
# (a stable filter by prefab gives savedata.ents[prefab]), and a move to the end of a prefab's list is a remove and
# a new head.

# An entity: prefab string id, x and z as the Lua doubles, the wormhole id and target (0 when unset), and the set
# piece it is a member of (k for the k-th placed layout, 0 none; see populate/setpiece.bend).
type Ent is Data:
  Ent{prefab: U32, x: F64Repr.F64, z: F64Repr.F64, id: U32, target: U32, piece: U32}

def of_land(ents: List<&2, Entities.Ent>) -> List<&2, Ent>:
  match ents:
    case Nil{}:
      Nil{}
    case Con{Entities.Ent{+prefab, _, _, +x, +z, _, _, _}, rest}:
      Ent{prefab, x, z, 0, 0, 0} <> of_land(rest)

def prefab_of(+e: Ent) -> U32:
  match e:
    case Ent{+prefab, _, _, _, _, _}:
      prefab

def keep_if(hit: Bool, +e: Ent, tail: List<&2, Ent>) -> List<&2, Ent>:
  match hit:
    case True{}:
      e <> tail
    case False{}:
      tail

def filter_loop(ents: List<&2, Ent>, +prefab: U32, acc: List<&2, Ent>) -> List<&2, Ent>:
  match ents:
    case Nil{}:
      acc
    case Con{+e, rest}:
      filter_loop(rest, prefab, keep_if(U32.is_eq(prefab_of(e), prefab), e, acc))

# savedata.ents[prefab] in insertion order (empty when absent).
def of_prefab(+ents: List<&2, Ent>, +prefab: U32) -> List<&2, Ent>:
  filter_loop(ents, prefab, Nil{})

def count_loop(ents: List<&2, Ent>, +prefab: U32, +n: U32) -> U32:
  match ents:
    case Nil{}:
      n
    case Con{+e, rest}:
      count_loop(rest, prefab, (n + Bool.to_u32(U32.is_eq(prefab_of(e), prefab)) : U32))

# #savedata.ents[prefab].
def count(+ents: List<&2, Ent>, +prefab: U32) -> U32:
  count_loop(ents, prefab, 0)

def without_loop(ents: List<&2, Ent>, +prefab: U32) -> List<&2, Ent>:
  match ents:
    case Nil{}:
      Nil{}
    case Con{+e, rest}:
      keep_if(U32.is_ne(prefab_of(e), prefab), e, without_loop(rest, prefab))

# savedata.ents[prefab] = nil.
def without(+ents: List<&2, Ent>, +prefab: U32) -> List<&2, Ent>:
  without_loop(ents, prefab)

def relabeled(+e: Ent, +prefab: U32) -> Ent:
  match e:
    case Ent{_, +x, +z, +id, +target, +piece}:
      Ent{prefab, x, z, id, target, piece}

def append_loop(moved: List<&2, Ent>, +prefab: U32, acc: List<&2, Ent>) -> List<&2, Ent>:
  match moved:
    case Nil{}:
      acc
    case Con{+e, rest}:
      append_loop(rest, prefab, relabeled(e, prefab) <> acc)

# Appends entities (oldest first) to savedata.ents[prefab].
def appended(+ents: List<&2, Ent>, +moved: List<&2, Ent>, +prefab: U32) -> List<&2, Ent>:
  append_loop(moved, prefab, ents)

def split_back(hit: Bool, +e: Ent, got: List<&2, Ent> & List<&2, Ent>) -> List<&2, Ent> & List<&2, Ent>:
  (kept, found) = got
  (keep_if(Bool.not(hit), e, kept), found)

def split_loop(ents: List<&2, Ent>, +prefab: U32, found: List<&2, Ent>) -> List<&2, Ent> & List<&2, Ent>:
  match ents:
    case Nil{}:
      (Nil{}, found)
    case Con{+e, rest}:
      +hit = U32.is_eq(prefab_of(e), prefab)
      split_back(hit, e, split_loop(rest, prefab, keep_if(hit, e, found)))

# (without(ents, prefab), of_prefab(ents, prefab)) in one walk of the list.
def split(+ents: List<&2, Ent>, +prefab: U32) -> List<&2, Ent> & List<&2, Ent>:
  split_loop(ents, prefab, Nil{})

def moved_done(got: List<&2, Ent> & List<&2, Ent>, +to: U32) -> List<&2, Ent>:
  (+kept, +found) = got
  appended(kept, found, to)

# Moves savedata.ents[from] to the end of savedata.ents[to].
def moved(+ents: List<&2, Ent>, +from: U32, +to: U32) -> List<&2, Ent>:
  moved_done(split(ents, from), to)

def with_piece(+e: Ent, +piece: U32) -> Ent:
  match e:
    case Ent{+prefab, +x, +z, +id, +target, _}:
      Ent{prefab, x, z, id, target, piece}

def piece_runs(pieces: List<&2, PopulateSetpiece.Piece>, +end: U32, +k: U32) -> List<&2, U32>:
  match pieces:
    case Nil{}:
      Nil{}
    case Con{PopulateSetpiece.Piece{_, _, _, _, _, _, +from, +to}, more}:
      +gap = List.replicate(U32, U32.to_nat((from - end : U32)), 0)
      List.append(&2, U32, gap, List.append(&2, U32, List.replicate(U32, U32.to_nat((to - from : U32)), k), piece_runs(more, to, (k + 1 : U32))))

def tag_loop(oldest: List<&2, Ent>, tags: List<&2, U32>, acc: List<&2, Ent>) -> List<&2, Ent>:
  match oldest tags:
    case Nil{} _:
      acc
    case Con{+e, rest} Nil{}:
      tag_loop(rest, Nil{}, e <> acc)
    case Con{+e, rest} Con{+k, more}:
      tag_loop(rest, more, with_piece(e, k) <> acc)

# Every entity with the set piece it is a member of: the k-th of `pieces` (placement order, from 1) holds the entries
# from..to - 1 of the list, oldest first.
def tagged(+ents: List<&2, Ent>, +pieces: List<&2, PopulateSetpiece.Piece>) -> List<&2, Ent>:
  tag_loop(List.reverse(&2, Ent, ents), piece_runs(pieces, 0, 1), Nil{})
