import Base
import ./rng/pcg.bend as Pcg
import ./rng/lua_random.bend as LuaRandom
import ./rng/crand.bend as CRand
import ./level/setpieces.bend as LevelSetpieces
import ./filters/setpiece.bend as FilterSetpiece
import ./level/prefix.bend as LevelPrefix
import ./level/summary.bend as LevelSummary
import ./filters/config.bend as Config
import ./search/report.bend as SearchReport
import ./filters/rules.bend as Rules
import ./filters/level_checks.bend as LevelChecks
import ./level/choose.bend as LevelChoose
import ./filters/json.bend as Json

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
  {Config.config_of("{\"version\": 2, \"settings\": {\"boons\": \"default\", \"touchstone\": \"default\"}, \"generation\": {\"tasks\": {\"excluded\": [\"Squeltch\"]}, \"prefab_swaps\": {\"twigs\": \"twiggy trees\"}, \"setpieces\": [{\"tasks\": [\"Badlands\"], \"required\": {\"MooseNest\": [1, 2], \"Chessy_1\": 1}}]}}") == Done{Config.Config{True{}, Config.Criteria{0, 8, 2, 2, [Config.Rule{70, 32768, 1, 4294967295}, Config.Rule{3, 32768, 1, 2}], []}, [Config.no_later()], None{}, []}} : Result<&1, &1, U32 & String, Config.Config>}

def config_parses_every_section():
  {==}

# docs/config.md section A: a `placed` name keeps only its minimum in the level table and is bounded on the world, which
# makes a world rule (one a finder without worlds can't decide).
law config_reads_placed:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"tasks\": [\"Badlands\"], \"required\": {\"MooseNest\": [1, 2], \"Chessy_1\": 1}, \"placed\": [\"MooseNest\"]}]}}") == Done{Config.Config{True{}, Config.Criteria{0, 0, 0, 0, [Config.Rule{70, 32768, 1, 4294967295}, Config.Rule{3, 32768, 1, 4294967295}], []}, [Rules.Later{[Rules.Placed{0, ["Badlands"], [LevelChecks.Bounded{"MooseNest", 1, Some{2}}]}], [], [], [], [], []}], Some{"config: generation.setpieces[0].placed is not supported by this binary yet (it needs the generated world)"}, []}} : Result<&1, &1, U32 & String, Config.Config>}

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

# The world rules of `generation`'s `placed` names are checked by every filter.
law config_placed_joins_every_filter:
  {(world_entries(Config.config_of("{\"generation\": {\"setpieces\": [{\"required\": {\"MooseNest\": 1}, \"placed\": [\"MooseNest\"]}]}, \"filters\": [{}, {}]}")),
    world_entries(Config.config_of("{\"generation\": {\"setpieces\": [{\"required\": {\"MooseNest\": 1}, \"placed\": []}]}, \"filters\": [{}, {}]}")))
    == ([True{}, True{}], [False{}, False{}]) : List<&2, Bool> & List<&2, Bool>}

def config_placed_joins_every_filter():
  {==}

law config_rejects_placed_outside_required:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"required\": {\"MooseNest\": 1}, \"placed\": [\"Chessy_1\"]}]}}") == Fail{(2, "config: generation.setpieces[0].placed names \"Chessy_1\", which isn't in required")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_placed_outside_required():
  {==}

law config_rejects_repeated_placed:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"required\": {\"MooseNest\": 1}, \"placed\": [\"MooseNest\", \"MooseNest\"]}]}}") == Fail{(2, "config: generation.setpieces[0].placed names \"MooseNest\" twice")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_repeated_placed():
  {==}

# docs/config.md section A: a group (`any`) is kept apart from the rules, as the rules of each of its members.
law config_reads_group:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"required\": {\"Chessy_1\": 1}}, {\"any\": [{\"tasks\": [\"Badlands\"], \"required\": {\"MooseNest\": 1}}, {\"required\": {\"Chessy_1\": [0, 0]}}]}]}}") == Done{Config.Config{True{}, Config.Criteria{0, 0, 0, 0, [Config.Rule{70, 33554431, 1, 4294967295}], [Config.Group{[[Config.Rule{3, 32768, 1, 4294967295}], [Config.Rule{70, 33554431, 0, 0}]], None{}}]}, [Config.no_later()], None{}, []}} : Result<&1, &1, U32 & String, Config.Config>}

def config_reads_group():
  {==}

# A group with `placed` names in one of its rules is one world rule, at the group's index.
law config_reads_group_placed:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"any\": [{\"required\": {\"MooseNest\": [1, 2]}, \"placed\": [\"MooseNest\"]}, {\"required\": {\"Chessy_1\": 1}}]}]}}") == Done{Config.Config{True{}, Config.Criteria{0, 0, 0, 0, [], [Config.Group{[[Config.Rule{3, 33554431, 1, 4294967295}], [Config.Rule{70, 33554431, 1, 4294967295}]], None{}}]}, [Rules.Later{[Rules.AnyPlaced{0, [Rules.Member{LevelChecks.Pieces{[], [LevelChecks.Bounded{"MooseNest", 1, None{}}]}, [LevelChecks.Bounded{"MooseNest", 1, Some{2}}]}, Rules.Member{LevelChecks.Pieces{[], [LevelChecks.Bounded{"Chessy_1", 1, None{}}]}, []}], None{}}], [], [], [], [], []}], Some{"config: generation.setpieces[0].any has placed names, which this binary doesn't support yet (they need the generated world)"}, []}} : Result<&1, &1, U32 & String, Config.Config>}

def config_reads_group_placed():
  {==}

law config_rejects_empty_group:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"any\": []}]}}") == Fail{(2, "config: generation.setpieces[0].any must not be empty")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_empty_group():
  {==}

# A group's `total`; with `placed` names the level table keeps only its minimum and the world rule the whole bound.
law config_reads_group_total:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"any\": [{\"required\": {\"MooseNest\": 0}}, {\"tasks\": [\"Badlands\"], \"required\": {\"Chessy_1\": 0}}], \"total\": [2, 3]}]}}") == Done{Config.Config{True{}, Config.Criteria{0, 0, 0, 0, [], [Config.Group{[[Config.Rule{3, 33554431, 0, 4294967295}], [Config.Rule{70, 32768, 0, 4294967295}]], Some{LevelChecks.Total{2, Some{3}}}}]}, [Config.no_later()], None{}, []}} : Result<&1, &1, U32 & String, Config.Config>}

def config_reads_group_total():
  {==}

law config_reads_group_total_placed:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"any\": [{\"required\": {\"MooseNest\": 0}, \"placed\": [\"MooseNest\"]}], \"total\": [1, 2]}]}}") == Done{Config.Config{True{}, Config.Criteria{0, 0, 0, 0, [], [Config.Group{[[Config.Rule{3, 33554431, 0, 4294967295}]], Some{LevelChecks.Total{1, None{}}}}]}, [Rules.Later{[Rules.AnyPlaced{0, [Rules.Member{LevelChecks.Pieces{[], [LevelChecks.Bounded{"MooseNest", 0, None{}}]}, [LevelChecks.Bounded{"MooseNest", 0, None{}}]}], Some{LevelChecks.Total{1, Some{2}}}}], [], [], [], [], []}], Some{"config: generation.setpieces[0].any has placed names, which this binary doesn't support yet (they need the generated world)"}, []}} : Result<&1, &1, U32 & String, Config.Config>}

def config_reads_group_total_placed():
  {==}

law config_rejects_bad_total:
  {(Config.config_of("{\"generation\": {\"setpieces\": [{\"any\": [{}], \"total\": [1]}]}}"), Config.config_of("{\"generation\": {\"setpieces\": [{\"total\": 1}]}}")) == (Fail{(2, "config: generation.setpieces[0].total must be an integer in 0..4294967295 or [min, max]")}, Fail{(2, "config: generation.setpieces[0].any must not be empty")}) : Result<&1, &1, U32 & String, Config.Config> & Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_bad_total():
  {==}

law config_rejects_nested_group:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"any\": [{\"any\": [{}]}]}]}}") == Fail{(2, "config: unknown key \"any\" in generation.setpieces[0].any[0]")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_nested_group():
  {==}

law config_rejects_group_with_rule_keys:
  {Config.config_of("{\"generation\": {\"setpieces\": [{\"any\": [{}], \"required\": {\"MooseNest\": 1}}]}}") == Fail{(2, "config: unknown key \"required\" in generation.setpieces[0]")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_group_with_rule_keys():
  {==}

# Chessy_1 at least 0 always holds, at least 100 never does.
def always() -> Config.Rule:
  Config.Rule{70, 33554431, 0, 4294967295}

def never() -> Config.Rule:
  Config.Rule{70, 33554431, 100, 4294967295}

def grouped(alternatives: List<&2, List<&2, Config.Rule>>) -> List<&2, Config.Criteria>:
  [Config.Criteria{0, 0, 0, 0, [], [Config.Group{alternatives, None{}}]}]

def totaled(+total: LevelChecks.Total) -> List<&2, Config.Criteria>:
  +moose : Config.Rule = Config.Rule{3, 33554431, 0, 4294967295}
  [Config.Criteria{0, 0, 0, 0, [], [Config.Group{[[moose], [moose, always()]], Some{total}}]}]

# A group holds when one of its rules' lists holds, and a list holds when all its rules do.
law group_holds_on_any_alternative:
  {(Config.matches(grouped([[never()], [always()]]), 4), Config.matches(grouped([[never()]]), 4), Config.matches(grouped([[always(), never()]]), 4)) == (True{}, False{}, False{}) : Bool & Bool & Bool}

def group_holds_on_any_alternative():
  {==}

# Seed 4 plans MooseNest 7 times and Chessy_1 never: a total sums every rule of every alternative, 7 + 7 + 0.
law group_total_sums_rules:
  {(Config.matches(totaled(LevelChecks.Total{14, Some{14}}), 4), Config.matches(totaled(LevelChecks.Total{15, None{}}), 4), Config.matches(totaled(LevelChecks.Total{0, Some{13}}), 4)) == (True{}, False{}, False{}) : Bool & Bool & Bool}

def group_total_sums_rules():
  {==}

# The level-table witness of a group: each rule's result under "any".
law group_level_witness:
  {LevelChecks.setpiece_check(LevelChecks.Group{[LevelChecks.Pieces{[], [LevelChecks.Bounded{"MooseNest", 1, None{}}]}, LevelChecks.Pieces{["Make a pick"], [LevelChecks.Bounded{"Chessy_1", 1, None{}}]}], None{}}, [LevelChecks.Placed{"Make a pick", ["Chessy_1"]}]) == (True{}, ",\"any\":[{\"ok\":false,\"counts\":{\"MooseNest\":0}},{\"ok\":true,\"counts\":{\"Chessy_1\":1}}]") : Bool & String}

def group_level_witness():
  {==}

# A total counts each rule's names in its tasks: MooseNest twice anywhere, Chessy_1 once in Make a pick.
law group_level_total_witness:
  {LevelChecks.setpiece_check(LevelChecks.Group{[LevelChecks.Pieces{[], [LevelChecks.Bounded{"MooseNest", 0, None{}}]}, LevelChecks.Pieces{["Make a pick"], [LevelChecks.Bounded{"Chessy_1", 0, None{}}]}], Some{LevelChecks.Total{3, Some{3}}}}, [LevelChecks.Placed{"Make a pick", ["Chessy_1", "MooseNest"]}, LevelChecks.Placed{"Badlands", ["Chessy_1", "MooseNest"]}]) == (True{}, ",\"any\":[{\"ok\":true,\"counts\":{\"MooseNest\":2}},{\"ok\":true,\"counts\":{\"Chessy_1\":1}}],\"total\":3") : Bool & String}

def group_level_total_witness():
  {==}

law config_rejects_non_default_setting:
  {Config.config_of("{\"settings\": {\"traps\": \"default\", \"boons\": \"insane\"}}") == Fail{(2, "config: only default settings are supported (boons)")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_non_default_setting():
  {==}

law config_rejects_unknown_version:
  {Config.config_of("{\"version\": 1}") == Fail{(2, "config: unsupported version 1")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_unknown_version():
  {==}

law config_rejects_unknown_task:
  {Config.config_of("{\"generation\": {\"tasks\": {\"required\": [\"Killer Bees\"]}}}") == Fail{(2, "config: unknown task \"Killer Bees\" in generation.tasks.required")} : Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_unknown_task():
  {==}

# Seed 4 does not choose the optional task "Killer bees!" (task id 10).
law killer_bees_criteria_reject_seed_4:
  {Config.matches([Config.Criteria{1024, 0, 0, 0, [], []}], 4) == False{} : Bool}

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
  {Config.config_of("{\"filters\": [{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}]}") == Fail{(2, "config: filters has 26 entries (at most 25)")} : Result<&1, &1, U32 & String, Config.Config>}

def config_caps_entries():
  {==}

# docs/config.md section 1: a filter's `name` labels it and its hits, and has at most 40 characters.
law config_reads_filter_names:
  {(Config.config_of("{\"filters\": [{\"name\": \"abcdefghijklmnopqrstuvwxyzabcdefghijklmn\"}]}"), Config.config_of("{\"filters\": [{\"name\": \"abcdefghijklmnopqrstuvwxyzabcdefghijklmno\"}]}"),
    Config.config_of("{\"filters\": [{\"name\": 1}]}"))
    == (Done{Config.Config{True{}, Config.anything(), [Config.no_later()], None{}, ["abcdefghijklmnopqrstuvwxyzabcdefghijklmn"]}}, Fail{(2, "config: filters[0].name has 41 characters (at most 40)")},
      Fail{(2, "config: filters[0].name must be a string")}) : Result<&1, &1, U32 & String, Config.Config> & Result<&1, &1, U32 & String, Config.Config> & Result<&1, &1, U32 & String, Config.Config>}

def config_reads_filter_names():
  {==}

# docs/config.md section 8: a hit names its filter when that filter has a name.
law hit_entry_names_its_filter:
  {(SearchReport.entry_json(0, SearchReport.name_at([], 0)), SearchReport.entry_json(1, SearchReport.name_at(["", "Pig \"King\""], 1)))
    == ("\"entry\":0", "\"entry\":1,\"name\":\"Pig \\\"King\\\"\"") : String & String}

def hit_entry_names_its_filter():
  {==}

law config_reads_linux_platform:
  {Config.config_of("{\"platform\": \"linux\"}") == Done{Config.Config{False{}, Config.anything(), [Config.no_later()], None{}, []}} : Result<&1, &1, U32 & String, Config.Config>}

def config_reads_linux_platform():
  {==}

def level_table_only(compiled: Result<&1, &1, U32 & String, Config.Config>) -> Result<&1, &1, U32 & String, Config.Config>:
  match compiled:
    case Done{+config}:
      Config.level_table_only(config)
    case Fail{failure}:
      Fail{failure}

# docs/config.md section 1: `generation` is the one level table, every filter is world rules only, in order.
law config_reads_filters:
  {(world_entries(Config.config_of("{\"generation\": {\"tasks\": {\"excluded\": [\"Squeltch\"]}}, \"filters\": [{\"counts\": [{\"prefab\": \"pigking\"}]}, {}]}")),
    level_table_only(Config.config_of("{\"filters\": [{}, {\"counts\": [{\"prefab\": \"pigking\"}]}]}")))
    == ([True{}, False{}], Fail{(2, "config: filters[1].counts is not supported by this binary yet (only generation is)")}) : List<&2, Bool> & Result<&1, &1, U32 & String, Config.Config>}

def config_reads_filters():
  {==}

law config_rejects_level_sections_in_filters:
  {(Config.config_of("{\"filters\": [{\"tasks\": {\"required\": [\"Killer bees!\"]}}]}"), Config.config_of("{\"criteria\": []}"))
    == (Fail{(2, "config: unknown key \"tasks\" in filters[0]")}, Fail{(2, "config: unknown key \"criteria\" in the config")}) : Result<&1, &1, U32 & String, Config.Config> & Result<&1, &1, U32 & String, Config.Config>}

def config_rejects_level_sections_in_filters():
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

# Python's json.loads number grammar.
law json_number_grammar_accepts_exponent:
  {Json.is_number_end(Json.number_state("-0.5e+3", 0)) == True{} : Bool}

def json_number_grammar_accepts_exponent():
  {==}

law json_number_grammar_rejects_leading_zero:
  {Json.number_state("01", 0) == 9 : U32}

def json_number_grammar_rejects_leading_zero():
  {==}
