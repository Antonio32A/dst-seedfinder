import Base
import ./rng/pcg.bend as Pcg
import ./rng/lua_random.bend as LuaRandom
import ./rng/crand.bend as CRand
import ./level/setpieces.bend as LevelSetpieces
import ./filters/setpiece.bend as FilterSetpiece
import ./level/prefix.bend as LevelPrefix
import ./level/summary.bend as LevelSummary
import ./filters/config.bend as Config
import ./filters/rules.bend as Rules
import ./filters/level_checks.bend as LevelChecks
import ./level/choose.bend as LevelChoose

# Golden values below come from the reference harness (the real worldgen Lua under DST's PCG32),
# which matches set pieces dumped from the game (builds 747465 and 756039) for seeds 1..1000.

# The first draw set piece selection inspects, after the 13 skipped by Pcg.seeded.
law seed_1_first_inspected_draw:
  {Pair.fst(U32, Pcg.Rng, Pcg.draw(Pcg.seeded(1))) == 2542040730 : U32}

def seed_1_first_inspected_draw():
  {==}

# math.random() can return exactly 1.0, making math.random(n) return n + 1.
law top_output_rolls_past_range:
  {LuaRandom.scale(4294967295, 13) == 13 : U32}

def top_output_rolls_past_range():
  {==}

law rare_cutoff_below:
  {LuaRandom.is_below_rare_cutoff(4209067949) == True{} : Bool}

def rare_cutoff_below():
  {==}

law rare_cutoff_at:
  {LuaRandom.is_below_rare_cutoff(4209067950) == False{} : Bool}

def rare_cutoff_at():
  {==}

law seed_0_pieces:
  {LevelSetpieces.generate(0) == LevelSetpieces.Pieces{3, 0, 0, 1, 0, 16843265, 0} : LevelSetpieces.Pieces}

def seed_0_pieces():
  {==}

law seed_1_pieces:
  {LevelSetpieces.generate(1) == LevelSetpieces.Pieces{3, 0, 1, 16777472, 33554688, 1, 1} : LevelSetpieces.Pieces}

def seed_1_pieces():
  {==}

law seed_2147483648_pieces:
  {LevelSetpieces.generate(2147483648) == LevelSetpieces.Pieces{2, 9, 10, 257, 16777216, 256, 0} : LevelSetpieces.Pieces}

def seed_2147483648_pieces():
  {==}

law seed_4294967295_pieces:
  {LevelSetpieces.generate(4294967295) == LevelSetpieces.Pieces{4, 0, 7, 131072, 256, 65537, 0} : LevelSetpieces.Pieces}

def seed_4294967295_pieces():
  {==}

# On seed 1's pieces (the seed_1_pieces golden), without generating them again.
law unfiltered_matches_everything:
  {FilterSetpiece.matches(FilterSetpiece.unfiltered(), LevelSetpieces.Pieces{3, 0, 1, 16777472, 33554688, 1, 1}) == True{} : Bool}

def unfiltered_matches_everything():
  {==}

# Prefab swaps (twiggy trees), ChooseTasks' shuffle of the optional tasks as 4-bit slots (the first five
# are the harness' chosen optional tasks) and the PCG32 state after these 13 draws.
law world_seed_1_prefix:
  {LevelPrefix.prefix(1) == LevelPrefix.Prefix{2, 426793026, 3894, Pcg.Rng{3383314989, 1014003894}} : LevelPrefix.Prefix}

def world_seed_1_prefix():
  {==}

# The level table after ChooseSetPieces: level.set_pieces keys in pairs() order with their task masks,
# and the random set pieces with their tasks, which decode into the reference harness' world line and its
# pairs() order byte for byte. The input is seed 1 after
# AddSetPeices (pieces as in seed_1_pieces, new boons in first-pick order FarmingBoon TwigsBoon Level2WoodBoon
# MiscBoon WeaponBoon CookingBoon, PCG32 state after 41 draws), so the law
# skips the prefix and AddSetPeices the laws above already pin.
law world_seed_1_level_table:
  {LevelSummary.summary_of(LevelChoose.choose(2, 426793026, LevelPrefix.chosen_tasks(426793026), LevelChoose.Added{LevelSetpieces.Pieces{3, 0, 1, 16777472, 33554688, 1, 1}, 1586631, 0, 6, Pcg.Rng{1208880263, 849893026}})) == LevelSummary.Summary{2, 426793026, [67108869, 1073741832, 4107, 802756, 1039, 67108871, 2321, 556099, 4149, 262170, 67108870, 2389378, 134217737, 2113, 16402, 524301, 4118], 606346272, 245803085, 6, False{}} : LevelSummary.Summary}

def world_seed_1_level_table():
  {==}

law config_parses_every_section:
  {Config.config_of("{\"version\": 1, \"settings\": {\"boons\": \"default\", \"touchstone\": \"default\"}, \"criteria\": [{\"tasks\": {\"excluded\": [\"Squeltch\"]}, \"prefab_swaps\": {\"twigs\": \"twiggy trees\"}, \"setpieces\": [{\"tasks\": [\"Badlands\"], \"required\": {\"MooseNest\": [1, 2], \"Chessy_1\": 1}}]}]}") == Done{Config.Config{True{}, [Config.Criteria{0, 8, 2, 2, [Config.Rule{70, 32768, 1, 4294967295}, Config.Rule{3, 32768, 1, 2}]}], [Config.no_later()], None{}, [Config.Criteria{0, 8, 2, 2, [Config.Rule{70, 32768, 1, 4294967295}, Config.Rule{3, 32768, 1, 2}]}]}} : Result<&1, &1, U32 & String, Config.Config>}

def config_parses_every_section():
  {==}

# docs/config.md section A: a `placed` name keeps only its minimum in the level table and is bounded on the world, which
# makes the entry a world entry (and one a finder without worlds can't decide).
law config_reads_placed:
  {Config.config_of("{\"criteria\": [{\"setpieces\": [{\"tasks\": [\"Badlands\"], \"required\": {\"MooseNest\": [1, 2], \"Chessy_1\": 1}, \"placed\": [\"MooseNest\"]}]}]}") == Done{Config.Config{True{}, [Config.Criteria{0, 0, 0, 0, [Config.Rule{70, 32768, 1, 4294967295}, Config.Rule{3, 32768, 1, 4294967295}]}], [Rules.Later{[Rules.Placed{0, ["Badlands"], [LevelChecks.Bounded{"MooseNest", 1, Some{2}}]}], [], [], [], [], []}], Some{"config: criteria[0].setpieces[0].placed is not supported by this binary yet (it needs the generated world)"}, [Config.Criteria{0, 0, 0, 0, [Config.Rule{70, 32768, 1, 4294967295}, Config.Rule{3, 32768, 1, 4294967295}]}]}} : Result<&1, &1, U32 & String, Config.Config>}

def config_reads_placed():
  {==}

def has_rules(laters: List<&2, Rules.Later>) -> List<&2, Bool>:
  match laters:
    case Nil{}:
      Nil{}
    case Con{+later, rest}:
      Rules.has_rules(later) <> has_rules(rest)

def world_entries(compiled: Result<&1, &1, U32 & String, Config.Config>) -> List<&2, Bool>:
  match compiled:
    case Done{Config.Config{_, _, laters, _, _}}:
      has_rules(laters)
    case Fail{_}:
      Nil{}

law config_placed_makes_world_entry:
  {world_entries(Config.config_of("{\"criteria\": [{\"setpieces\": [{\"required\": {\"MooseNest\": 1}, \"placed\": [\"MooseNest\"]}]}, {\"setpieces\": [{\"required\": {\"MooseNest\": 1}, \"placed\": []}]}]}")) == [True{}, False{}] : List<&2, Bool>}

def config_placed_makes_world_entry():
  {==}

law config_rejects_placed_outside_required:
  {Config.config_of("{\"criteria\": [{\"setpieces\": [{\"required\": {\"MooseNest\": 1}, \"placed\": [\"Chessy_1\"]}]}]}") == Fail{(2, "config: criteria[0].setpieces[0].placed names \"Chessy_1\", which isn't in required")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_placed_outside_required():
  {==}

law config_rejects_repeated_placed:
  {Config.config_of("{\"criteria\": [{\"setpieces\": [{\"required\": {\"MooseNest\": 1}, \"placed\": [\"MooseNest\", \"MooseNest\"]}]}]}") == Fail{(2, "config: criteria[0].setpieces[0].placed names \"MooseNest\" twice")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_repeated_placed():
  {==}

law config_rejects_non_default_setting:
  {Config.config_of("{\"settings\": {\"traps\": \"default\", \"boons\": \"insane\"}}") == Fail{(2, "config: only default settings are supported (boons)")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_non_default_setting():
  {==}

law config_rejects_unknown_version:
  {Config.config_of("{\"version\": 2}") == Fail{(2, "config: unsupported version 2")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_unknown_version():
  {==}

law config_rejects_unknown_task:
  {Config.config_of("{\"criteria\": [{\"tasks\": {\"required\": [\"Killer Bees\"]}}]}") == Fail{(2, "config: unknown task \"Killer Bees\" in criteria[0].tasks.required")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_unknown_task():
  {==}

# Seed 4 does not choose the optional task "Killer bees!" (task id 10).
law killer_bees_criteria_reject_seed_4:
  {Config.matches([Config.Criteria{1024, 0, 0, 0, []}], 4) == False{} : Bool}

def killer_bees_criteria_reject_seed_4():
  {==}

# docs/config.md section 7: repeated keys and integers past 4294967295 are config errors.
law config_rejects_repeated_key:
  {Config.config_of("{\"version\": 1, \"version\": 1}") == Fail{(2, "config: duplicate key \"version\" in the config")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_repeated_key():
  {==}

law config_rejects_integer_past_u32:
  {Config.config_of("{\"version\": 4294967297}") == Fail{(2, "config: unsupported version 4294967297")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_integer_past_u32():
  {==}

law config_caps_entries:
  {Config.config_of("{\"criteria\": [{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}]}") == Fail{(2, "config: criteria has 26 entries (at most 25)")} : Result<&1, &1, U32 & String, Config.Config>}

def config_caps_entries():
  {==}

# Seed 4 does not choose "Killer bees!" (task 10), which the first entry needs, and chooses "Make a pick"
# (task 0), which the second excludes (harness world line): both fail and the result is the entry count.
law first_match_skips_failing_entry:
  {Config.first_match([Config.Criteria{1024, 0, 0, 0, []}, Config.Criteria{0, 1, 0, 0, []}], 4) == 2 : U32}

def first_match_skips_failing_entry():
  {==}

law config_reads_linux_platform:
  {Config.config_of("{\"platform\": \"linux\"}") == Done{Config.Config{False{}, [], [], None{}, [Config.anything()]}} : Result<&1, &1, U32 & String, Config.Config>}

def config_reads_linux_platform():
  {==}

law passive_entry_makes_no_candidates:
  {Config.config_of("{\"criteria\": [{\"passive\": true, \"tasks\": {\"excluded\": [\"Squeltch\"]}}, {\"tasks\": {\"required\": [\"Killer bees!\"]}}]}") == Done{Config.Config{True{}, [Config.Criteria{0, 8, 0, 0, []}, Config.Criteria{1024, 0, 0, 0, []}], [Config.no_later(), Config.no_later()], None{}, [Config.Criteria{1024, 0, 0, 0, []}]}} : Result<&1, &1, U32 & String, Config.Config>}

def passive_entry_makes_no_candidates():
  {==}

law config_rejects_only_passive_entries:
  {Config.config_of("{\"criteria\": [{\"passive\": true}]}") == Fail{(2, "config: every criteria entry is passive (at least one must not be)")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_only_passive_entries():
  {==}

law config_rejects_non_flag_passive:
  {Config.config_of("{\"criteria\": [{\"passive\": 1}]}") == Fail{(2, "config: criteria[0].passive must be true or false")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_non_flag_passive():
  {==}

law config_rejects_unknown_platform:
  {Config.config_of("{\"platform\": \"mac\"}") == Fail{(2, "config: unknown platform \"mac\" (windows or linux)")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_unknown_platform():
  {==}

# Draw counters (the oracle's canonical counter: raw PCG32 steps since math.randomseed). Pcg.seeded is 13 draws in.
law pcg_advance_to_seeded:
  {Pcg.advance(Pcg.srandom(1), 13) == Pcg.seeded(1) : Pcg.Rng}

def pcg_advance_to_seeded():
  {==}

law pcg_counter_of_seeded:
  {Pcg.counter(1, Pcg.seeded(1)) == 13 : U32}

def pcg_counter_of_seeded():
  {==}

# Klei's rand() 100 draws after math.randomseed(1).
law crand_linux_rand:
  {Pair.fst(U32, Pcg.Rng, CRand.rand(False{}, Pcg.at_counter(1, 100))) == 1595231506 : U32}

def crand_linux_rand():
  {==}

law crand_windows_rand:
  {Pair.fst(U32, Pcg.Rng, CRand.rand(True{}, Pcg.at_counter(1, 100))) == 2878 : U32}

def crand_windows_rand():
  {==}

# std::random_shuffle of 8 indices at that point: libstdc++ (Linux) and VC9 (Windows) permutations.
law crand_linux_shuffle:
  {CRand.shuffled_order(False{}, 8, Pcg.at_counter(1, 100)) == CRand.Order{[1, 6, 3, 5, 0, 7, 2, 4], Pcg.at_counter(1, 107)} : CRand.Order}

def crand_linux_shuffle():
  {==}

law crand_windows_shuffle:
  {CRand.shuffled_order(True{}, 8, Pcg.at_counter(1, 100)) == CRand.Order{[3, 7, 1, 2, 4, 5, 0, 6], Pcg.at_counter(1, 107)} : CRand.Order}

def crand_windows_shuffle():
  {==}

