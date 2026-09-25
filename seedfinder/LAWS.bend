import Base
import ./rng/pcg.bend as R
import ./rng/lua_random.bend as LR
import ./rng/crand.bend as CR
import ./level/setpieces.bend as S
import ./filters/setpiece.bend as F
import ./level/prefix.bend as P
import ./level/summary.bend as W
import ./filters/config.bend as CF
import ./level/choose.bend as CH

# Golden values below come from the reference harness (the real worldgen Lua under DST's PCG32),
# which matches set pieces dumped from the game (build 747465) for seeds 1..1000.

# The first draw set piece selection inspects, after the 13 skipped by R.seeded.
law seed_1_first_inspected_draw:
  {Pair.fst(U32, R.Rng, R.draw(R.seeded(1))) == 2542040730 : U32}

def seed_1_first_inspected_draw():
  {==}

# math.random() can return exactly 1.0, making math.random(n) return n + 1.
law top_output_rolls_past_range:
  {LR.scale(4294967295, 13) == 13 : U32}

def top_output_rolls_past_range():
  {==}

law rare_cutoff_below:
  {LR.is_below_rare_cutoff(4209067949) == True{} : Bool}

def rare_cutoff_below():
  {==}

law rare_cutoff_at:
  {LR.is_below_rare_cutoff(4209067950) == False{} : Bool}

def rare_cutoff_at():
  {==}

law seed_0_pieces:
  {S.generate(0) == S.Pieces{3, 0, 0, 1, 0, 16843265, 0} : S.Pieces}

def seed_0_pieces():
  {==}

law seed_1_pieces:
  {S.generate(1) == S.Pieces{3, 0, 1, 16777472, 33554688, 1, 1} : S.Pieces}

def seed_1_pieces():
  {==}

law seed_2147483648_pieces:
  {S.generate(2147483648) == S.Pieces{2, 9, 10, 257, 16777216, 256, 0} : S.Pieces}

def seed_2147483648_pieces():
  {==}

law seed_4294967295_pieces:
  {S.generate(4294967295) == S.Pieces{4, 0, 7, 131072, 256, 65537, 0} : S.Pieces}

def seed_4294967295_pieces():
  {==}

# On seed 1's pieces (the seed_1_pieces golden), without generating them again.
law unfiltered_matches_everything:
  {F.matches(F.unfiltered(), S.Pieces{3, 0, 1, 16777472, 33554688, 1, 1}) == True{} : Bool}

def unfiltered_matches_everything():
  {==}

# Prefab swaps (twiggy trees), ChooseTasks' shuffle of the optional tasks as 4-bit slots (the first five
# are the harness' chosen optional tasks) and the PCG32 state after these 13 draws.
law world_seed_1_prefix:
  {P.prefix(1) == P.Prefix{2, 426793026, 3894, R.Rng{3383314989, 1014003894}} : P.Prefix}

def world_seed_1_prefix():
  {==}

# The level table after ChooseSetPieces: level.set_pieces keys in pairs() order with their task masks,
# and the random set pieces with their tasks. .scratch/world/golden.py decodes these into the reference
# harness' world line and its pairs() order, which match byte for byte. The input is seed 1 after
# AddSetPeices (pieces as in seed_1_pieces, new boons in first-pick order FarmingBoon TwigsBoon Level2WoodBoon
# MiscBoon WeaponBoon CookingBoon, PCG32 state after 41 draws, all from .scratch/world/model.py), so the law
# skips the prefix and AddSetPeices the laws above already pin.
law world_seed_1_level_table:
  {W.summary_of(CH.choose(2, 426793026, P.chosen_tasks(426793026), CH.Added{S.Pieces{3, 0, 1, 16777472, 33554688, 1, 1}, 1586631, 0, 6, R.Rng{1208880263, 849893026}})) == W.Summary{2, 426793026, [67108869, 1073741832, 4107, 802756, 1039, 67108871, 2321, 556099, 4149, 262170, 67108870, 2389378, 134217737, 2113, 16402, 524301, 4118], 606346272, 245803085, 6, False{}} : W.Summary}

def world_seed_1_level_table():
  {==}

law config_parses_every_section:
  {CF.config_of("{\"version\": 1, \"settings\": {\"boons\": \"default\", \"touchstone\": \"default\"}, \"criteria\": [{\"tasks\": {\"excluded\": [\"Squeltch\"]}, \"prefab_swaps\": {\"twigs\": \"twiggy trees\"}, \"setpieces\": [{\"tasks\": [\"Badlands\"], \"required\": {\"MooseNest\": [1, 2], \"Chessy_1\": 1}}]}]}") == Done{CF.Config{True{}, [CF.Criteria{0, 8, 2, 2, [CF.Rule{70, 32768, 1, 4294967295}, CF.Rule{3, 32768, 1, 2}]}], [CF.no_later()], None{}}} : Result<&1, &1, U32 & String, CF.Config>}

def config_parses_every_section():
  {==}

law config_rejects_non_default_setting:
  {CF.config_of("{\"settings\": {\"traps\": \"default\", \"boons\": \"insane\"}}") == Fail{(2, "config: only default settings are supported (boons)")} : Result<&1, &1, U32 & String, CF.Config>}

def config_rejects_non_default_setting():
  {==}

law config_rejects_unknown_version:
  {CF.config_of("{\"version\": 2}") == Fail{(2, "config: unsupported version 2")} : Result<&1, &1, U32 & String, CF.Config>}

def config_rejects_unknown_version():
  {==}

law config_rejects_unknown_task:
  {CF.config_of("{\"criteria\": [{\"tasks\": {\"required\": [\"Killer Bees\"]}}]}") == Fail{(2, "config: unknown task \"Killer Bees\" in criteria[0].tasks.required")} : Result<&1, &1, U32 & String, CF.Config>}

def config_rejects_unknown_task():
  {==}

# Seed 4 does not choose the optional task "Killer bees!" (task id 10).
law killer_bees_criteria_reject_seed_4:
  {CF.matches([CF.Criteria{1024, 0, 0, 0, []}], 4) == False{} : Bool}

def killer_bees_criteria_reject_seed_4():
  {==}

# Spec search-v1 section 7: repeated keys and integers past 4294967295 are config errors.
law config_rejects_repeated_key:
  {CF.config_of("{\"version\": 1, \"version\": 1}") == Fail{(2, "config: duplicate key \"version\" in the config")} : Result<&1, &1, U32 & String, CF.Config>}

def config_rejects_repeated_key():
  {==}

law config_rejects_integer_past_u32:
  {CF.config_of("{\"version\": 4294967297}") == Fail{(2, "config: unsupported version 4294967297")} : Result<&1, &1, U32 & String, CF.Config>}

def config_rejects_integer_past_u32():
  {==}

law config_caps_entries:
  {CF.config_of("{\"criteria\": [{}, {}, {}, {}, {}, {}, {}, {}, {}]}") == Fail{(2, "config: criteria has 9 entries (at most 8)")} : Result<&1, &1, U32 & String, CF.Config>}

def config_caps_entries():
  {==}

# Seed 4 does not choose "Killer bees!" (task 10), which the first entry needs, and chooses "Make a pick"
# (task 0), which the second excludes (harness world line): both fail and the result is the entry count.
law first_match_skips_failing_entry:
  {CF.first_match([CF.Criteria{1024, 0, 0, 0, []}, CF.Criteria{0, 1, 0, 0, []}], 4) == 2 : U32}

def first_match_skips_failing_entry():
  {==}

law config_reads_linux_platform:
  {CF.config_of("{\"platform\": \"linux\"}") == Done{CF.Config{False{}, [], [], None{}}} : Result<&1, &1, U32 & String, CF.Config>}

def config_reads_linux_platform():
  {==}

law config_rejects_unknown_platform:
  {CF.config_of("{\"platform\": \"mac\"}") == Fail{(2, "config: unknown platform \"mac\" (windows or linux)")} : Result<&1, &1, U32 & String, CF.Config>}

def config_rejects_unknown_platform():
  {==}

# Draw counters (the oracle's canonical counter: raw PCG32 steps since math.randomseed). R.seeded is 13 draws in.
law pcg_advance_to_seeded:
  {R.advance(R.srandom(1), 13) == R.seeded(1) : R.Rng}

def pcg_advance_to_seeded():
  {==}

law pcg_counter_of_seeded:
  {R.counter(1, R.seeded(1)) == 13 : U32}

def pcg_counter_of_seeded():
  {==}

# Klei's rand() 100 draws after math.randomseed(1), from .scratch/port/test/crand_ref.py.
law crand_linux_rand:
  {Pair.fst(U32, R.Rng, CR.rand(False{}, R.at_counter(1, 100))) == 1595231506 : U32}

def crand_linux_rand():
  {==}

law crand_windows_rand:
  {Pair.fst(U32, R.Rng, CR.rand(True{}, R.at_counter(1, 100))) == 2878 : U32}

def crand_windows_rand():
  {==}

# std::random_shuffle of 8 indices at that point: libstdc++ (Linux) and VC9 (Windows) permutations.
law crand_linux_shuffle:
  {CR.shuffled_order(False{}, 8, R.at_counter(1, 100)) == CR.Order{[1, 6, 3, 5, 0, 7, 2, 4], R.at_counter(1, 107)} : CR.Order}

def crand_linux_shuffle():
  {==}

law crand_windows_shuffle:
  {CR.shuffled_order(True{}, 8, R.at_counter(1, 100)) == CR.Order{[3, 7, 1, 2, 4, 5, 0, 6], R.at_counter(1, 107)} : CR.Order}

def crand_windows_shuffle():
  {==}

