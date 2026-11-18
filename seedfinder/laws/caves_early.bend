import Base
import ../f64/repr.bend as F64Repr
import ../rng/pcg.bend as Pcg
import ../worldsim/grid.bend as Grid
import ../populate/entities.bend as Entities
import ../ocean/ents.bend as OceanEnts
import ../ocean/state.bend as OceanState
import ../ocean/post.bend as OceanPost
import ../post/archive.bend as Archive
import ../post/finish.bend as Finish
import ../storygen/graph.bend as StoryGraph
import ../filters/world.bend as FilterWorld
import ../filters/dump.bend as FilterDump
import ../filters/rules.bend as Rules
import ../filters/evaluate.bend as Evaluate
import ../filters/shard_search.bend as ShardSearch
import ../gen/job.bend as GenJob
import ../gen/cave_required.bend as CaveRequired
import ../gen/savedata.bend as SaveData
import ../data/gen_tags.bend as GenTagsData
import ../data/builds.bend as Builds

# The caves search's early check (search/generated.bend) decides a candidate when its attempt reaches JGround (after
# ConvertGround, ReplaceSingleNonLandTiles and a passed DetectDisconnect). Let E be the attempt's entities then,
# restricted to a set of prefabs, and P the post steps without the bunch spawner (GenJob.early, Finish.early).
# 1. After JGround an attempt fails only at the required prefab check. Graph:PopulateVoronoi and BunchSpawnerRun only
#    add entities; the steps that move, relabel or remove (wormhole markers, customization and randomization proxies,
#    the impassable filter on the final tile map, the archive pass) act per prefab and entity, and the archive's
#    dispensers and their temporary ones are never added later (data/gen_tags.bend cave_late_prefabs keeps them late
#    only for their positions). So a required prefab has at least its count in P(E) in the world: when P(E) passes the
#    check, the attempt is the world.
# 2. A prefab outside cave_late_prefabs (nothing after JGround adds it, relabels it by a draw or moves a later prefab
#    into it) has the same instances, in the same order, in P(E) as in the world, and so do the pillar links between
#    the pillars.
# 3. No step after JGround writes a tile: the world's tile map and land are P(E)'s (its encoding is the same
#    ReplaceSingleNonLandTiles).
# 4. A count or distance reads only its prefabs' instances, the pillar links (with the pillars) and the land. So such
#    a rule on early prefabs has its world value on P(E); a filter with a false one is false (its rules are AND-ed); a
#    world where every filter has one is a miss, as the whole world's verdict says.
# Below, on build 762172: the generated late prefabs, the entities the early world keeps, the early world of a land at
# JGround against the world its attempt becomes with entities added after JGround, and which rules a filter checks
# early. The impassable filter is left out of these worlds (it reads F32 positions, which the kernel does not
# evaluate): it keeps or drops each entity by its own tile, whatever else is there.

def build() -> Builds.Build:
  Builds.Build{762172}

# The vocabulary ids whose instances can change after JGround on 762172: room contents, map tag items, bunch items,
# the archive dispensers and the randomization proxies' results (the 104 that differed between the early and the whole
# world of 2181 candidates of seeds 1-200000).
law caves_late_prefabs_762172:
  {GenTagsData.cave_late_prefabs(build()) == [28, 30, 36, 58, 83, 93, 98, 100, 101, 102, 112, 113, 115, 116, 117, 126, 146, 147, 189, 233, 234, 245, 247, 253, 256, 259, 264, 286, 306, 321, 337, 339, 346, 366, 368, 369, 371, 373, 374, 375, 376, 377, 378, 379, 381, 382, 383, 384, 385, 386, 387, 388, 390, 391, 392, 393, 394, 397, 398, 399, 400, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 413, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 432, 433, 434, 435, 436, 437, 438, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 458, 459, 461, 462] : List<&2, U32>}

def caves_late_prefabs_762172():
  {==}

# A story without nodes: the required prefabs are the level's and the task set's (multiplayer_portal, two
# tentacle_pillar_atrium, batbosscave).
def story() -> StoryGraph.St:
  StoryGraph.fresh(Pcg.at_counter(7, 0))

def reqs() -> List<&2, OceanPost.Req>:
  CaveRequired.required(build(), story())

# 7 x 7 tiles of land (6).
def grid() -> Grid.Grid:
  Grid.new(7, 7, Grid.cell(6, 0))

def at(+sid: U32, +x: U32, +z: U32) -> Entities.Ent:
  Entities.Ent{sid, F64Repr.zero(), F64Repr.zero(), F64Repr.from_u32(x), F64Repr.from_u32(z), 0, 0, Pcg.Rng{0, 0}}

# The entities at JGround (newest first): two cave_exit (927), a cave_fern (928, a room content) from a layout, three
# wormhole markers (546), two tentacle_pillar_atrium (1228), four temporary archive dispensers (836) and one
# dispenser (835), an atrium_gate (858), a customization proxy of rock2 (327) and a rock2 (426), a multiplayer_portal
# (381) and a batbosscave (919).
def ground_ents(+bat: Bool) -> List<&2, Entities.Ent>:
  List.append(&2, Entities.Ent, [at(927, 4, 4), at(927, 0, 0), at(928, 8, 4), at(546, 12, 12), at(546, 8, 8), at(546, 4, 8), at(1228, 4, 12), at(1228, 12, 4),
    at(836, 12, 8), at(836, 8, 12), at(836, 4, 12), at(836, 12, 12), at(835, 8, 12), at(858, 12, 12), at(327, 8, 4), at(426, 4, 8), at(381, 4, 4)],
    Bool.pick(List<&2, Entities.Ent>, bat, [at(919, 8, 8)], Nil{}))

# What Graph:PopulateVoronoi adds after JGround (newest first): room contents only, cave_fern and spiderhole (1219).
def later_ents() -> List<&2, Entities.Ent>:
  [at(928, 4, 8), at(1219, 8, 4), at(928, 12, 12)]

# The string ids of the prefabs a walk with pillars from cave_exit to atrium_gate reads, and rock2's.
def keep() -> List<&2, U32>:
  [426, 858, 927, 1227, 1228]

def kept(+ents: List<&2, Entities.Ent>) -> List<&2, Entities.Ent>:
  GenJob.kept_ents(build(), Some{Finish.early_sids(build(), GenJob.cave_shard(build()), reqs(), keep())}, ents)

# The early world keeps the entities of those prefabs and of what the post steps read: every one but the cave_fern.
law caves_early_keeps_what_the_post_steps_read:
  {kept(ground_ents(True{})) == List.append(&2, Entities.Ent, [at(927, 4, 4), at(927, 0, 0), at(546, 12, 12), at(546, 8, 8), at(546, 4, 8), at(1228, 4, 12), at(1228, 12, 4),
    at(836, 12, 8), at(836, 8, 12), at(836, 4, 12), at(836, 12, 12), at(835, 8, 12), at(858, 12, 12), at(327, 8, 4), at(426, 4, 8), at(381, 4, 4)], [at(919, 8, 8)]) : List<&2, Entities.Ent>}

def caves_early_keeps_what_the_post_steps_read():
  {==}

def ctx() -> OceanState.Ctx:
  OceanState.Ctx{True{}, 0, 7, 7, False{}, False{}}

def sea(+ents: List<&2, Entities.Ent>) -> OceanState.Sea:
  OceanState.Sea{grid(), Grid.new(0, 0, 0), Pcg.at_counter(7, 40), OceanEnts.of_land(ents), 0, Nil{}}

# Finish.early's steps but the impassable filter: the atrium pillars' ids, GlobalPostPopulate (tentacle_pillar 1227
# from the markers, rock2 from its proxy), the archive pass and the required prefab check.
def posted(+ents: List<&2, Entities.Ent>) -> OceanState.Sea & Bool:
  OceanPost.required(reqs(), ctx(), Archive.run(835, 836, OceanPost.post_populate(build(), ctx(), 1227, GenJob.atriumed(build(), OceanState.ents_of(sea(ents))))))

# A walk with pillars from cave_exit (vocabulary id 372) to atrium_gate (358), and rock2 (254): the early prefabs and
# the pillars (456, 457), with their links and the land.
def needs() -> Rules.Needs:
  Rules.Needs{[254, 358, 372, 456, 457], True{}, False{}, True{}, False{}, False{}}

def world_of(got: OceanState.Sea & Bool) -> Maybe<&2, FilterWorld.World>:
  (sea, +ok) = got
  match sea:
    case OceanState.Sea{g, _, +rng, +ents, _, _}:
      Bool.pick(Maybe<&2, FilterWorld.World>, ok, Some{SaveData.cave_world_for(build(), 7, True{}, needs(), GenJob.Final{g, rng, ents, 7, Nil{}, Nil{}, 0, FilterDump.Graph{Nil{}, Nil{}}, Nil{}})}, None{})

def early(+bat: Bool) -> Maybe<&2, FilterWorld.World>:
  world_of(posted(kept(ground_ents(bat))))

def whole(+bat: Bool) -> Maybe<&2, FilterWorld.World>:
  world_of(posted(List.append(&2, Entities.Ent, later_ents(), ground_ents(bat))))

# The early world passes the required prefab check and is the world's: the same cave_exit, atrium_gate, rock2 (its
# proxy moved in), pillar pairs from the markers, atrium pillar pair, links and land.
law caves_early_world_is_the_world:
  {(early(True{}), Maybe.is_some(&2, FilterWorld.World, whole(True{}))) == (whole(True{}), True{}) : (Maybe<&2, FilterWorld.World> & Bool)}

def caves_early_world_is_the_world():
  {==}

# Without the batbosscave the early check fails, and so does the attempt.
law caves_early_check_fails_with_the_attempt:
  {(early(False{}), whole(False{})) == (None{}, None{}) : (Maybe<&2, FilterWorld.World> & Maybe<&2, FilterWorld.World>)}

def caves_early_check_fails_with_the_attempt():
  {==}

def straight(+from: U32, +to: U32) -> Rules.Distance:
  Rules.Distance{[from], [to], None{}, Some{F64Repr.from_u32(40)}, Rules.Metric{False{}, True{}, True{}}}

def walked(+from: U32, +to: U32) -> Rules.Distance:
  Rules.Distance{[from], [to], None{}, Some{F64Repr.from_u32(40)}, Rules.Metric{True{}, True{}, True{}}}

def distances(+rules: List<&2, Rules.Distance>) -> Rules.Later:
  Rules.Later{Nil{}, Nil{}, rules, Nil{}, Nil{}, Nil{}}

def routed() -> Rules.Later:
  Rules.Later{Nil{}, Nil{}, [walked(372, 401)], Nil{}, Nil{}, [Rules.Route{[372], [[401]], None{}, F64Repr.from_u32(40), False{}, Rules.Metric{False{}, True{}, True{}}}]}

# A filter checks early its counts and distances on early prefabs (cave_exit, atrium_gate, minotaur_spawner 401; not
# spiderhole 449), those without a walk when it has some (the first filter), else the walks (the second); never its
# routes (the third).
law caves_early_jobs_by_reads:
  {ShardSearch.early_jobs(build(), [distances([walked(372, 401), straight(372, 449), straight(372, 358)]), distances([straight(372, 449), walked(372, 401)]), routed()])
    == [[Evaluate.JDistance{2, straight(372, 358)}], [Evaluate.JDistance{1, walked(372, 401)}], [Evaluate.JDistance{0, walked(372, 401)}]] : List<&2, List<&2, Evaluate.Job>>}

def caves_early_jobs_by_reads():
  {==}

# A filter without an early job leaves no early check.
law caves_early_check_needs_every_filter:
  {Maybe.is_none(&2, ShardSearch.Early, ShardSearch.early_check(build(), [distances([straight(372, 358)]), distances([straight(372, 449)])])) == True{} : Bool}

def caves_early_check_needs_every_filter():
  {==}
