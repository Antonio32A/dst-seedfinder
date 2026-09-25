import Base
import ../rng/pcg.bend as R
import ../level/prefix.bend as P
import ../level/summary.bend as W
import ../data/blob.bend as B
import ../data/strings.bend as ST
import ../data/tasks.bend as TK
import ./graph.bend as GG
import ./order.bend as GO
import ./link.bend as GL
import ./background.bend as GB
import ./setpieces.bend as GP
import ./region.bend as GR

# forest_map.Generate up to WorldGen_Commit: the WorldSim setup calls, BuildStory (Story:GenerationPipeline), the
# first layout calls, Story:AddRegionsToMainland and Commit. Two phases, because FindMainlandNodesForNewRegion reads
# the sites of VoronoiPass(100): `build` runs up to that pass, the caller stores the sites (GG.site_base()), then
# `finish` runs up to and including WorldGen_Commit.

def chosen_loop(n: Nat, +lo: U32, +c: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      P.chosen_task(lo, c) <> chosen_loop(p, lo, (c + 1 : U32))

def task_slots(tasks: List<&2, U32>) -> List<&2, GO.Slot>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      GO.Slot{ST.hash(t), t} <> task_slots(rest)

def in_region(tasks: List<&2, U32>, +island: Bool) -> List<&2, U32>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      +tail = in_region(rest, island)
      +kept = U32.is_eq(Bool.to_u32(Bool.not(B.is_none(TK.region_id(t)))), Bool.to_u32(island))
      Bool.pick(List<&2, U32>, kept, t <> tail, tail)

# pairs(self.tasks): Story's task table, filled from chosen_tasks in array order.
def story_tasks(+level: W.Summary) -> List<&2, U32>:
  match level:
    case W.Summary{_, +lo, _, _, _, _, _}:
      GO.order(task_slots(chosen_loop(20n, lo, 0)))

# pairs(region_tasksets[region]) for the mainland (False) or the island (True).
def region_tasks(+level: W.Summary, +island: Bool) -> List<&2, U32>:
  GO.order(task_slots(in_region(story_tasks(level), island)))

def setup(+s: GG.St) -> GG.St:
  +a = GG.call(GG.call(GG.call(s, GG.m_set_points_barren()), GG.m_set_resolve_noise()), GG.m_set_validate_ground())
  GG.say(GG.call(GG.say(a), GG.m_set_world_size()))

def with_start(+region: GL.Region, +before: R.Rng) -> GG.St:
  GG.returned(GL.add_start_node(GL.region_st(region), GL.region_start(region)), GG.f_generate_nodes_from_tasks(), before)

def untouched(+s: GG.St, +func: U32) -> GG.St:
  GG.returned(s, func, GG.rng_of(s))

def pipeline(+s: GG.St, +level: W.Summary) -> GG.St:
  +nodes = with_start(GL.generate_region(s, region_tasks(level, False{}), False{}), GG.rng_of(s))
  +bg = GB.add_bg_nodes(nodes)
  +coves = GB.add_cove_nodes(bg, GG.children_order(bg))
  +pieces = GP.insert_set_pieces(coves, GG.children_order(coves), level)
  +tags = untouched(untouched(pieces, GG.f_place_teleportato_parts()), GG.f_process_extra_tags())
  untouched(GG.say(tags), GG.f_process_ocean_content())

# Generate from its first WorldSim call to WorldGen_VoronoiPass(100), with the RNG at Generate's entry.
def build(+level: W.Summary, +rng: R.Rng) -> GG.St:
  +s = setup(GG.initial(rng))
  +story = GG.returned(pipeline(s, level), GG.f_build_story(), GG.rng_of(s))
  GG.call(GG.call(story, GG.m_initialize_node_points()), GG.m_voronoi_pass())

# From AddRegionsToMainland to WorldGen_Commit, once the sites of VoronoiPass(100) are stored.
def finish(+s: GG.St, +level: W.Summary) -> GG.St:
  GG.call(GG.say(GG.say(GR.add_regions(s, region_tasks(level, True{}), level))), GG.m_commit())
