import Base
import ../f64/repr.bend as F64Repr
import ../populate/entities.bend as Entities

# savedata.ents during the ocean phase as one list, newest first: each prefab's entries keep their insertion order
# (a stable filter by prefab gives savedata.ents[prefab]), and a move to the end of a prefab's list is a remove and
# a new head.

# An entity: prefab string id, x and z as the Lua doubles, and the wormhole id and target (0 when unset).
type Ent is Data:
  Ent{prefab: U32, x: F64Repr.F64, z: F64Repr.F64, id: U32, target: U32}

def of_land(ents: List<&2, Entities.Ent>) -> List<&2, Ent>:
  match ents:
    case Nil{}:
      Nil{}
    case Con{Entities.Ent{+prefab, _, _, +x, +z, _, _, _}, rest}:
      Ent{prefab, x, z, 0, 0} <> of_land(rest)

def prefab_of(+e: Ent) -> U32:
  match e:
    case Ent{+prefab, _, _, _, _}:
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
    case Ent{_, +x, +z, +id, +target}:
      Ent{prefab, x, z, id, target}

def append_loop(moved: List<&2, Ent>, +prefab: U32, acc: List<&2, Ent>) -> List<&2, Ent>:
  match moved:
    case Nil{}:
      acc
    case Con{+e, rest}:
      append_loop(rest, prefab, relabeled(e, prefab) <> acc)

# Appends entities (oldest first) to savedata.ents[prefab].
def appended(+ents: List<&2, Ent>, +moved: List<&2, Ent>, +prefab: U32) -> List<&2, Ent>:
  append_loop(moved, prefab, ents)

# Moves savedata.ents[from] to the end of savedata.ents[to].
def moved(+ents: List<&2, Ent>, +from: U32, +to: U32) -> List<&2, Ent>:
  appended(without(ents, from), of_prefab(ents, from), to)
