import Base
import ../rng/pcg.bend as Pcg
import ../level/prefix.bend as LevelPrefix
import ../level/summary.bend as LevelSummary
import ../data/blob.bend as Blob
import ../data/strings.bend as Strings
import ../data/tasks.bend as Tasks
import ./graph.bend as StoryGraph
import ./order.bend as StoryOrder
import ./link.bend as StoryLink
import ./background.bend as Background
import ./setpieces.bend as StorySetpieces
import ./region.bend as StoryRegion

# forest_map.Generate up to WorldGen_Commit: the WorldSim setup calls, BuildStory (Story:GenerationPipeline), the
# first layout calls, Story:AddRegionsToMainland and Commit. Two phases, because FindMainlandNodesForNewRegion reads
# the sites of VoronoiPass(100): `build` runs up to that pass, the caller stores the sites (StoryGraph.site_base()), then
# `finish` runs up to and including WorldGen_Commit.

def chosen_loop(n: Nat, +lo: U32, +c: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      LevelPrefix.chosen_task(lo, c) <> chosen_loop(p, lo, (c + 1 : U32))

def task_slots(tasks: List<&2, U32>) -> List<&2, StoryOrder.Slot>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      StoryOrder.Slot{Strings.hash(t), t} <> task_slots(rest)

def in_region(tasks: List<&2, U32>, +island: Bool) -> List<&2, U32>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      +tail = in_region(rest, island)
      +kept = U32.is_eq(Bool.to_u32(Bool.not(Blob.is_none(Tasks.region_id(t)))), Bool.to_u32(island))
      Bool.pick(List<&2, U32>, kept, t <> tail, tail)

# pairs(self.tasks): Story's task table, filled from chosen_tasks in array order.
def story_tasks(+level: LevelSummary.Summary) -> List<&2, U32>:
  match level:
    case LevelSummary.Summary{_, +lo, _, _, _, _, _}:
      StoryOrder.order(task_slots(chosen_loop(20n, lo, 0)))

# pairs(region_tasksets[region]) for the mainland (False) or the island (True).
def region_tasks(+level: LevelSummary.Summary, +island: Bool) -> List<&2, U32>:
  StoryOrder.order(task_slots(in_region(story_tasks(level), island)))

def setup(+s: StoryGraph.St) -> StoryGraph.St:
  +a = StoryGraph.call(StoryGraph.call(StoryGraph.call(s, StoryGraph.m_set_points_barren()), StoryGraph.m_set_resolve_noise()), StoryGraph.m_set_validate_ground())
  StoryGraph.say(StoryGraph.call(StoryGraph.say(a), StoryGraph.m_set_world_size()))

def with_start(+region: StoryLink.Region, +before: Pcg.Rng) -> StoryGraph.St:
  StoryGraph.returned(StoryLink.add_start_node(StoryLink.region_st(region), StoryLink.region_start(region)), StoryGraph.f_generate_nodes_from_tasks(), before)

def untouched(+s: StoryGraph.St, +func: U32) -> StoryGraph.St:
  StoryGraph.returned(s, func, StoryGraph.rng_of(s))

def pipeline(+s: StoryGraph.St, +level: LevelSummary.Summary) -> StoryGraph.St:
  +nodes = with_start(StoryLink.generate_region(s, region_tasks(level, False{}), False{}), StoryGraph.rng_of(s))
  +bg = Background.add_bg_nodes(nodes)
  +coves = Background.add_cove_nodes(bg, StoryGraph.children_order(bg))
  +pieces = StorySetpieces.insert_set_pieces(coves, StoryGraph.children_order(coves), level)
  +tags = untouched(untouched(pieces, StoryGraph.f_place_teleportato_parts()), StoryGraph.f_process_extra_tags())
  untouched(StoryGraph.say(tags), StoryGraph.f_process_ocean_content())

# Generate from its first WorldSim call to WorldGen_VoronoiPass(100), with the RNG at Generate's entry.
def build(+level: LevelSummary.Summary, +rng: Pcg.Rng) -> StoryGraph.St:
  +s = setup(StoryGraph.initial(rng))
  +story = StoryGraph.returned(pipeline(s, level), StoryGraph.f_build_story(), StoryGraph.rng_of(s))
  StoryGraph.call(StoryGraph.call(story, StoryGraph.m_initialize_node_points()), StoryGraph.m_voronoi_pass())

# From AddRegionsToMainland to WorldGen_Commit, once the sites of VoronoiPass(100) are stored.
def finish(+s: StoryGraph.St, +level: LevelSummary.Summary) -> StoryGraph.St:
  StoryGraph.call(StoryGraph.say(StoryGraph.say(StoryRegion.add_regions(s, region_tasks(level, True{}), level))), StoryGraph.m_commit())
