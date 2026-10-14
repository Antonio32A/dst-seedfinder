import Base
import ../rng/pcg.bend as Pcg
import ../level/cave_prefix.bend as CavePrefix
import ../storygen/graph.bend as StoryGraph
import ../storygen/maptags.bend as MapTags
import ../data/builds.bend as Builds

# Build 757748's caves (seed 2 of build/groundtruth/757748/data/worlds_caves, whose rng_checkpoints have choose_tasks 21).
law cave_757748_seed_2_prefix:
  {CavePrefix.chosen(Builds.Build{757748}, 2) == CavePrefix.Chosen{0, [0, 11, 4, 15, 16, 6, 3, 1], CavePrefix.Masks{4294967295, 200887, 2148007682, False{}}, Pcg.at_counter(2, 21)} : CavePrefix.Chosen}

def cave_757748_seed_2_prefix():
  {==}

def first_extra(+s: StoryGraph.St) -> List<&2, U32> & Pcg.Rng:
  +at = StoryGraph.extra_base()
  ([StoryGraph.get(s, StoryGraph.s_extras()), StoryGraph.get(s, at), StoryGraph.get(s, (at + 1 : U32)), StoryGraph.get(s, (at + 2 : U32))], StoryGraph.rng_of(s))

# Build 757748's BatBossCave_Spawner (caves tag 1) fires once per story: one math.random(3) on the story RNG picks the
# node's STATIC layout, here bat_boss_cave2 (layout 247), and the tag's second use draws nothing.
law cave_757748_bat_boss_cave_is_drawn_once:
  {first_extra(MapTags.cave_tags(Builds.Build{757748}, [1, 1], StoryGraph.fresh(Pcg.at_counter(2, 1000)), 7, 0)) == ([1, 7, 4, 247], Pcg.at_counter(2, 1001)) : List<&2, U32> & Pcg.Rng}

def cave_757748_bat_boss_cave_is_drawn_once():
  {==}
