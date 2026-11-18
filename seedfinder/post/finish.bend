import Base
import ../data/blob.bend as Blob
import ../data/ocean_post.bend as OceanPostData
import ../worldsim/points.bend as Points
import ../ocean/state.bend as OceanState
import ../ocean/post.bend as OceanPost
import ../ocean/bunches.bend as Bunches
import ./archive.bend as Archive
import ../data/builds.bend as Builds

# forest_map.Generate from Graph:GlobalPostPopulate to GetEncodedMap, the steps every shard shares: GlobalPostPopulate,
# the impassable filter, BunchSpawnerRun, AncientArchivePass, the required prefab check and, when the attempt is the
# world, ReplaceSingleNonLandTiles.

# What differs between the shards: the level's wormhole_prefab and the archive's dispenser prefab and its temporary one
# (Blob.none() for a shard without an archive).
type Shard is Data:
  Shard{wormhole: U32, dispenser: U32, temporary: U32}

def forest(+build: Builds.Build) -> Shard:
  Shard{OceanPostData.wormhole_prefab(build), Blob.none(), Blob.none()}

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

def finished(+build: Builds.Build, +c: OceanState.Ctx, +wormhole: U32, +dispenser: U32, +temporary: U32, +reqs: List<&2, OceanPost.Req>, s: OceanState.Sea) -> OceanState.Sea & Bool:
  checked(OceanPost.required(reqs, c, Archive.run(dispenser, temporary, Bunches.bunches(build, c, OceanPost.impassable_filter(build, c, OceanPost.post_populate(build, c, wormhole, s))))), c)

# Everything after the last population step, with the required prefab table: the final state and whether it passed.
def run(+build: Builds.Build, +c: OceanState.Ctx, shard: Shard, +reqs: List<&2, OceanPost.Req>, s: OceanState.Sea) -> OceanState.Sea & Bool:
  match shard:
    case Shard{+wormhole, +dispenser, +temporary}:
      finished(build, c, wormhole, dispenser, temporary, reqs, s)

# The steps of `run` up to the required prefab check without BunchSpawnerRun: the attempt as it ends when the bunch
# spawner adds nothing (its tile map not encoded).
def early(+build: Builds.Build, +c: OceanState.Ctx, shard: Shard, +reqs: List<&2, OceanPost.Req>, s: OceanState.Sea) -> OceanState.Sea & Bool:
  match shard:
    case Shard{+wormhole, +dispenser, +temporary}:
      OceanPost.required(reqs, c, Archive.run(dispenser, temporary, OceanPost.impassable_filter(build, c, OceanPost.post_populate(build, c, wormhole, s))))

def proxy_sources(+build: Builds.Build, n: Nat, +i: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      proxy_sources(build, p, (i + 1 : U32), Blob.at(OceanPostData.customization_proxies(build, i), 0) <> acc)

def required_sids(reqs: List<&2, OceanPost.Req>, +acc: List<&2, U32>) -> List<&2, U32>:
  match reqs:
    case Nil{}:
      acc
    case Con{OceanPost.Req{+prefab, _}, rest}:
      required_sids(rest, prefab <> acc)

# The string ids whose entities `early` reads for those of the string ids `keep` and for its required prefab check:
# those, the required prefabs, the wormhole markers, the archive's dispensers and the customization proxies.
def early_sids(+build: Builds.Build, shard: Shard, +reqs: List<&2, OceanPost.Req>, +keep: List<&2, U32>) -> List<&2, U32>:
  match shard:
    case Shard{_, +dispenser, +temporary}:
      +moved = proxy_sources(build, U32.to_nat(OceanPostData.customization_proxies_count(build)), 0, keep)
      required_sids(reqs, OceanPostData.wormhole_marker(build) <> dispenser <> temporary <> moved)
