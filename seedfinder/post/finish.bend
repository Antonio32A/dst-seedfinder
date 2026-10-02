import Base
import ../data/blob.bend as Blob
import ../data/ocean_post.bend as OceanPostData
import ../worldsim/points.bend as Points
import ../ocean/state.bend as OceanState
import ../ocean/post.bend as OceanPost
import ../ocean/bunches.bend as Bunches
import ./archive.bend as Archive

# forest_map.Generate from Graph:GlobalPostPopulate to GetEncodedMap, the steps every shard shares: GlobalPostPopulate,
# the impassable filter, BunchSpawnerRun, AncientArchivePass, the required prefab check and, when the attempt is the
# world, ReplaceSingleNonLandTiles.

# What differs between the shards: the level's wormhole_prefab and the archive's dispenser prefab and its temporary one
# (Blob.none() for a shard without an archive).
type Shard is Data:
  Shard{wormhole: U32, dispenser: U32, temporary: U32}

def forest() -> Shard:
  Shard{OceanPostData.wormhole_prefab(), Blob.none(), Blob.none()}

def encoded(ok: Bool, +c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match ok:
    case False{}:
      s
    case True{}:
      match s:
        case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
          OceanState.digest(c, OceanState.Sea{Points.replace_single_non_land(g), ids, rng, ents, topo, events}, 10)

def checked(got: OceanState.Sea & Bool, +c: OceanState.Ctx) -> OceanState.Sea & Bool:
  (s, +ok) = got
  (encoded(ok, c, s), ok)

def finished(+c: OceanState.Ctx, +wormhole: U32, +dispenser: U32, +temporary: U32, +reqs: List<&2, OceanPost.Req>, s: OceanState.Sea) -> OceanState.Sea & Bool:
  checked(OceanPost.required(reqs, c, Archive.run(dispenser, temporary, Bunches.bunches(c, OceanPost.impassable_filter(c, OceanPost.post_populate(c, wormhole, s))))), c)

# Everything after the last population step, with the required prefab table: the final state and whether it passed.
def run(+c: OceanState.Ctx, shard: Shard, +reqs: List<&2, OceanPost.Req>, s: OceanState.Sea) -> OceanState.Sea & Bool:
  match shard:
    case Shard{+wormhole, +dispenser, +temporary}:
      finished(c, wormhole, dispenser, temporary, reqs, s)
