import Base
import ../rng/pcg.bend as Pcg
import ../level/prefix.bend as LevelPrefix
import ../level/summary.bend as LevelSummary
import ../lua/math_random.bend as MathRandom
import ../data/blob.bend as Blob
import ../data/rooms.bend as Rooms
import ../data/cave_story.bend as CaveStory
import ../data/cave_catalog.bend as CaveCatalog
import ./catalog.bend as StoryCatalog
import ./plan.bend as StoryPlan
import ./graph.bend as StoryGraph
import ./order.bend as StoryOrder
import ./link.bend as StoryLink
import ./background.bend as Background
import ./setpieces.bend as StorySetpieces
import ./region.bend as StoryRegion
import ../data/builds.bend as Builds

# forest_map.Generate up to WorldGen_Commit: the WorldSim setup calls, BuildStory (Story:GenerationPipeline), the
# first layout calls, Story:AddRegionsToMainland and Commit. Two phases, because FindMainlandNodesForNewRegion reads
# the sites of VoronoiPass(100): `build` runs up to that pass, the caller stores the sites (StoryGraph.site_base()), then
# `finish` runs up to and including WorldGen_Commit.

def chosen_loop(+build: Builds.Build, n: Nat, +lo: U32, +c: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      LevelPrefix.chosen_task(build, lo, c) <> chosen_loop(build, p, lo, (c + 1 : U32))

def task_slots(+build: Builds.Build, tasks: List<&2, U32>) -> List<&2, StoryOrder.Slot>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      StoryOrder.Slot{StoryCatalog.task_hash(build, t), t} <> task_slots(build, rest)

def in_region(+build: Builds.Build, tasks: List<&2, U32>, +island: Bool) -> List<&2, U32>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      +tail = in_region(build, rest, island)
      +kept = U32.is_eq(Bool.to_u32(Bool.not(Blob.is_none(StoryCatalog.task_region_id(build, t)))), Bool.to_u32(island))
      Bool.pick(List<&2, U32>, kept, t <> tail, tail)

def chosen_tasks(+build: Builds.Build, +plan: StoryPlan.Plan) -> List<&2, U32>:
  match plan:
    case StoryPlan.ForestPlan{LevelSummary.Summary{_, +lo, _, _, _, _, _}}:
      chosen_loop(build, 20n, lo, 0)
    case StoryPlan.CavePlan{+tasks, _, _}:
      tasks

# pairs(self.tasks): Story's task table, filled from chosen_tasks in array order.
def story_tasks(+build: Builds.Build, +plan: StoryPlan.Plan) -> List<&2, U32>:
  StoryOrder.order(task_slots(build, chosen_tasks(build, plan)))

# pairs(region_tasksets[region]) for the mainland (False) or the island (True).
def region_tasks(+build: Builds.Build, +plan: StoryPlan.Plan, +island: Bool) -> List<&2, U32>:
  StoryOrder.order(task_slots(build, in_region(build, story_tasks(build, plan), island)))

def setup(+s: StoryGraph.St) -> StoryGraph.St:
  +a = StoryGraph.call(StoryGraph.call(StoryGraph.call(s, StoryGraph.m_set_points_barren()), StoryGraph.m_set_resolve_noise()), StoryGraph.m_set_validate_ground())
  StoryGraph.say(StoryGraph.call(StoryGraph.say(a), StoryGraph.m_set_world_size()))

def with_start(+build: Builds.Build, +region: StoryLink.Region, +before: Pcg.Rng, +plan: StoryPlan.Plan, +room: U32) -> StoryGraph.St:
  StoryGraph.returned(StoryLink.add_start_node(build, StoryLink.region_st(region), StoryLink.region_start(region), room, StoryPlan.valid_start_tasks(build, plan)), StoryGraph.f_generate_nodes_from_tasks(), before)

def untouched(+s: StoryGraph.St, +func: U32) -> StoryGraph.St:
  StoryGraph.returned(s, func, StoryGraph.rng_of(s))

def pipeline(+build: Builds.Build, +s: StoryGraph.St, +plan: StoryPlan.Plan, +room: U32) -> StoryGraph.St:
  +nodes = with_start(build, StoryLink.generate_region(build, s, region_tasks(build, plan, False{}), StoryPlan.restricted(plan)), StoryGraph.rng_of(s), plan, room)
  +bg = Background.add_bg_nodes(build, nodes, StoryPlan.bg_min(build, plan), StoryPlan.bg_max(build, plan))
  +coves = Background.add_cove_nodes(build, bg, StoryGraph.children_order(bg))
  +pieces = StorySetpieces.insert_set_pieces(build, coves, StoryGraph.children_order(coves), plan)
  +tags = untouched(untouched(pieces, StoryGraph.f_place_teleportato_parts()), StoryGraph.f_process_extra_tags())
  untouched(StoryGraph.say(tags), StoryGraph.f_process_ocean_content())

def planned(+build: Builds.Build, +plan: StoryPlan.Plan, +room: U32, +rng: Pcg.Rng) -> StoryGraph.St:
  +s = StoryGraph.put(setup(StoryGraph.initial(build, rng)), StoryGraph.s_entrance(), StoryPlan.entrance_of(plan))
  +story = StoryGraph.returned(pipeline(build, s, plan, room), StoryGraph.f_build_story(), StoryGraph.rng_of(s))
  StoryGraph.call(StoryGraph.call(story, StoryGraph.m_initialize_node_points()), StoryGraph.m_voronoi_pass())

def caves_started(+build: Builds.Build, +plan: StoryPlan.Plan, got: U32 & Pcg.Rng) -> StoryGraph.St:
  (+k, +rng) = got
  planned(build, plan, StoryCatalog.caves_room_id(CaveStory.start_room(build, (k - 1 : U32))), rng)

# Generate from its first WorldSim call to WorldGen_VoronoiPass(100), with the RNG at Generate's entry. The caves'
# start_location has a list of start rooms, so Generate draws math.random(#start_node) first.
def build_plan(+build: Builds.Build, +plan: StoryPlan.Plan, +rng: Pcg.Rng) -> StoryGraph.St:
  match plan:
    case StoryPlan.ForestPlan{_}:
      planned(build, plan, Rooms.start_room(build), rng)
    case StoryPlan.CavePlan{_, _, _}:
      caves_started(build, plan, MathRandom.random_upto(rng, CaveCatalog.start_room_count(build)))

# The forest's Generate.
def build(+build: Builds.Build, +level: LevelSummary.Summary, +rng: Pcg.Rng) -> StoryGraph.St:
  build_plan(build, StoryPlan.ForestPlan{level}, rng)

# From AddRegionsToMainland to WorldGen_Commit, once the sites of VoronoiPass(100) are stored. The caves have no
# regions: the pass does nothing.
def finish_plan(+build: Builds.Build, +s: StoryGraph.St, +plan: StoryPlan.Plan) -> StoryGraph.St:
  match plan:
    case StoryPlan.ForestPlan{_}:
      StoryGraph.call(StoryGraph.say(StoryGraph.say(StoryRegion.add_regions(build, s, region_tasks(build, plan, True{}), plan))), StoryGraph.m_commit())
    case StoryPlan.CavePlan{_, _, _}:
      StoryGraph.call(StoryGraph.say(StoryGraph.say(s)), StoryGraph.m_commit())

def finish(+build: Builds.Build, +s: StoryGraph.St, +level: LevelSummary.Summary) -> StoryGraph.St:
  finish_plan(build, s, StoryPlan.ForestPlan{level})
