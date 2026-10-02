import Base
import ../ocean/ents.bend as OceanEnts

# The two tentacle_pillar_atrium entities carry fixed teleporter ids (the atrium_start layout's is 2400000 and the
# TentaclePillarToAtrium layout's 2400001, each targeting the other) that the layouts define as object properties. The
# atrium room's layout is placed first, so when the entities have no id yet the first saved is 2400000 and the second
# 2400001.

def first_id() -> U32:
  2400000

def unset(+e: OceanEnts.Ent) -> Bool:
  match e:
    case OceanEnts.Ent{_, _, _, +id, +target, _}:
      U32.is_zero(id) && U32.is_zero(target)

def with_ids(+e: OceanEnts.Ent, +id: U32, +target: U32) -> OceanEnts.Ent:
  match e:
    case OceanEnts.Ent{+prefab, +x, +z, _, _, +piece}:
      OceanEnts.Ent{prefab, x, z, id, target, piece}

def linked(+first: OceanEnts.Ent, +second: OceanEnts.Ent) -> List<&2, OceanEnts.Ent>:
  Bool.pick(List<&2, OceanEnts.Ent>, unset(first) && unset(second),
    [with_ids(first, first_id(), (first_id() + 1 : U32)), with_ids(second, (first_id() + 1 : U32), first_id())], [first, second])

def pair_up(atrium: List<&2, OceanEnts.Ent>) -> List<&2, OceanEnts.Ent>:
  match atrium:
    case Con{+first, Con{+second, Nil{}}}:
      linked(first, second)
    case other:
      other

# The entities with the atrium pillars' ids set when there are exactly two and neither has one.
def paired(+ents: List<&2, OceanEnts.Ent>, +atrium: U32) -> List<&2, OceanEnts.Ent>:
  OceanEnts.appended(OceanEnts.without(ents, atrium), pair_up(OceanEnts.of_prefab(ents, atrium)), atrium)
