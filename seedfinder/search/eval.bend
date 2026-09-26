import Base
import ../filters/config.bend as Config
import ../filters/rules.bend as Rules
import ../filters/world.bend as FilterWorld
import ../filters/evaluate.bend as Evaluate
import ../filters/level_checks.bend as LevelChecks
import ../level/summary.bend as LevelSummary
import ../cli/args.bend as Args
import ../cli/files.bend as Files

# seedfinder world eval --config CONFIG.json --world WORLD.dstw [--json] [--fast]: one config on one dumped world,
# printed as .scratch/search/evaluate.py --json --level prints it (the level table comes from the seed). Exit 0 when
# some entry matches, 1 when none does or the world gave up, 2 on a config or input error.

def usage() -> String:
  "usage: seedfinder world eval --config CONFIG.json --world WORLD.dstw [--json] [--fast]"

type Evaluated is Data:
  Evaluated{entries: List<&2, String>, matched: List<&2, U32>}

def entry_json(+outcomes: List<&2, Evaluate.Outcome>) -> String:
  "{\"ok\":" ++ Bool.pick(String, Evaluate.holds(outcomes), "true", "false") ++ ",\"results\":" ++ Evaluate.results_json(outcomes, False{}) ++ "}"

def evaluated_step(+outcomes: List<&2, Evaluate.Outcome>, +i: U32, e: Evaluated) -> Evaluated:
  match e:
    case Evaluated{+entries, +matched}:
      Evaluated{List.append(&2, String, entries, [entry_json(outcomes)]), Bool.pick(List<&2, U32>, Evaluate.holds(outcomes), List.append(&2, U32, matched, [i]), matched)}

def entries_loop(shown: List<&2, LevelChecks.Shown>, laters: List<&2, Rules.Later>, stop: Bool, +world: FilterWorld.World, +s: LevelSummary.Summary, +fast: Bool, +i: U32, +e: Evaluated) -> Evaluated:
  match shown laters stop:
    case Con{+sh, ss} Con{+later, ls} False{}:
      +outcomes = Evaluate.entry_outcomes(sh, later, world, s, fast)
      entries_loop(ss, ls, fast && Evaluate.holds(outcomes), world, s, fast, (i + 1 : U32), evaluated_step(outcomes, i, e))
    case _ _ _:
      e

def matched_json(matched: List<&2, U32>) -> List<&2, String>:
  match matched:
    case Nil{}:
      Nil{}
    case Con{+i, rest}:
      U32.show(i) <> matched_json(rest)

def outcome_line(+seed: U32, +windows: Bool, +empty: Bool, e: Evaluated) -> String:
  match e:
    case Evaluated{+entries, +matched}:
      +match_all = empty || Bool.not(List.is_empty(&2, U32, matched))
      U32.show(seed) ++ " {\"platform\":\"" ++ Bool.pick(String, windows, "windows", "linux") ++ "\",\"match\":" ++ Bool.pick(String, match_all, "true", "false")
        ++ ",\"entries\":[" ++ String.join(entries, ",") ++ "],\"matched_entries\":[" ++ String.join(matched_json(matched), ",") ++ "]}"

def line_matches(+line: String) -> Bool:
  String.contains(line, ",\"match\":true,")

def print_outcome(+line: String) -> IO(Unit):
  do IO<Unit>:
    IO.print(line)
    Bool.pick(IO(Unit), line_matches(line), IO.pure(Unit, Unit{}), IO.die(Unit, 1, ""))

def platform_mismatch(+windows: Bool, +platform: U32) -> Bool:
  (U32.is_eq(platform, 1) && Bool.not(windows)) || (U32.is_eq(platform, 2) && windows)

def platform_message(+windows: Bool) -> String:
  "config: the world dump was generated on " ++ Bool.pick(String, windows, "linux", "windows") ++ ", the config's platform is " ++ Bool.pick(String, windows, "windows", "linux")

def evaluate_world(+config: Config.Config, +text: String, loaded: FilterWorld.Loaded, +path: String, +fast: Bool) -> IO(Unit):
  match config loaded:
    case Config.Config{+windows, +criteria, +laters, _, _} FilterWorld.Generated{+world, +platform}:
      match world:
        case FilterWorld.World{+seed, _, _, _, _, _, _}:
          Bool.pick(IO(Unit), platform_mismatch(windows, platform), IO.die(Unit, 2, platform_message(windows)),
            print_outcome(outcome_line(seed, windows, List.is_empty(&2, Config.Criteria, criteria),
              entries_loop(LevelChecks.shown_of(text), laters, False{}, world, LevelSummary.summary(seed), fast, 0, Evaluated{Nil{}, Nil{}}))))
    case _ FilterWorld.GaveUp{+seed}:
      IO.die(Unit, 1, "evaluate: seed " ++ path ++ ": world generation did not finish (seed " ++ U32.show(seed) ++ "); no match")

def with_loaded(+config: Config.Config, +text: String, loaded: Result<&1, &1, U32 & String, FilterWorld.Loaded>, +path: String, +fast: Bool) -> IO(Unit):
  match loaded:
    case Fail{(code, message)}:
      IO.die(Unit, 2, "world: " ++ path ++ ": " ++ message)
    case Done{world}:
      evaluate_world(config, text, world, path, fast)

def with_world(+config: Config.Config, +text: String, bytes: Result<&1, &1, U32 & String, List<&2, U32>>, +path: String, +fast: Bool) -> IO(Unit):
  match bytes:
    case Fail{(code, message)}:
      IO.die(Unit, 2, message)
    case Done{data}:
      with_loaded(config, text, FilterWorld.of_bytes(data), path, fast)

def with_compiled(compiled: Result<&1, &1, U32 & String, Config.Config>, +text: String, +world_path: String, +fast: Bool) -> IO(Unit):
  match compiled:
    case Fail{(code, message)}:
      IO.die(Unit, 2, message)
    case Done{+config}:
      do IO<Unit>:
        bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Files.read_bytes("world: ", world_path)
        with_world(config, text, bytes, world_path, fast)

def with_config(text: Result<&1, &1, U32 & String, String>, +world_path: String, +fast: Bool) -> IO(Unit):
  match text:
    case Fail{(code, message)}:
      IO.die(Unit, 2, message)
    case Done{+t}:
      with_compiled(Config.config_of(t), t, world_path, fast)

def eval_paths(config: Maybe<&2, String>, world: Maybe<&2, String>, +fast: Bool) -> IO(Unit):
  match config world:
    case Some{+config_path} Some{+world_path}:
      do IO<Unit>:
        text : Result<&1, &1, U32 & String, String> <- Files.read_text("config: ", config_path)
        with_config(text, world_path, fast)
    case _ _:
      IO.die(Unit, 2, usage())

# The `world eval` subcommand; args start with "eval".
def run(+args: List<&2, String>) -> IO(Unit):
  eval_paths(Args.flag_value(args, "--config"), Args.flag_value(args, "--world"), Config.is_member(args, "--fast"))
