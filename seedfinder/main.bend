import Base
import ./filters/config.bend as Config
import ./filters/cave_config.bend as CaveConfig
import ./data/builds.bend as Builds
import ./cli/args.bend as Args
import ./cli/config_file.bend as ConfigFile
import ./search/setpiece.bend as SearchSetpiece
import ./search/report.bend as SearchReport
import ./search/shard.bend as SearchShard
import ./search/cave_scan.bend as CaveScan
import ./search/cave_setpiece.bend as CaveSetpiece
import ./search/odds.bend as SearchOdds
import ./search/eval.bend as SearchEval
import ./gen/run.bend as GenRun
import ./gen/dump.bend as GenDump

# Usage (default world settings):
#   seedfinder setpiece find [FROM] [TO] [Name[:min[:max]] ...] [--shard forest|caves] [--build NUMBER]
#     parallel search over seeds FROM..TO (inclusive)
#   seedfinder setpiece show FROM [TO] [--shard forest|caves] [--build NUMBER]
#     set pieces of seeds FROM..TO, one JSON line each
#   seedfinder world find [FROM [TO]] [--start-seed S] [--limit N] [--time-limit SECONDS] [--json] [--config filters.json]
#                         [--platform windows|linux] [--shard forest|caves] [--build NUMBER] [--worlds DIR] [--kk native|bend]
#                         [--verbose-timings]
#     parallel scan from S (or FROM, default 0) up to TO or once around the 2^32 seeds, stopping at N hits
#     (1..100, default 100) or when the time limit is up (docs/config.md section 8); parts B-E are
#     decided on worlds generated in memory (or on DIR/<seed>.dstw dumps with --worlds); --verbose-timings times each
#     option (slower)
#   seedfinder world show FROM [TO] [--config filters.json] [--shard forest|caves] [--build NUMBER]
#     level table of seeds FROM..TO, one JSON line each (the config is only validated)
#   seedfinder world odds FROM [TO] [--config filters.json] [--shard forest|caves] [--build NUMBER]
#     one line `odds {...}`: how many of the seeds FROM..TO choose each task, place each set piece and are candidates of the config (docs/config.md sections 1, 4 A)
#   seedfinder world dump SEED [TO] [--platform windows|linux] [--shard forest|caves] [--build NUMBER] [--kk native|bend] -o PATH
#     parallel worldgen of seeds SEED..TO into world dumps (docs/world-dump.md): PATH is the dump of SEED, or with TO
#     an existing folder for PATH/<seed>.dstw; one line per seed
#   seedfinder gen SEED [TO] [--platform windows|linux] [--shard forest|caves] [--build NUMBER] [--times] [--kk native|bend] [--dump BITS] [--draws N]
#     worldgen of seeds SEED..TO, one line per seed (`--times`: one line per stage of every attempt); the caves shard only
#     runs up to ForceConnectivity: `--dump` adds the attempt's tile map (1) and story graph (2), `--draws` starts an attempt
#     N draws into the seed's stream
#   the worldgen trace stages are in the debug binary built from trace.bend (seedfinder_trace trace ...)
#   --build NUMBER: the game build to generate for (data/builds.bend); it overrides the config's `build`, and without a
#   config it defaults to the latest build

def query_or_fail(json: Bool, +shard: U32, parsed: Result<&1, &1, U32 & String, Args.Query>) -> IO(Unit):
  match parsed:
    case Fail{failure}:
      SearchReport.fail_job(json, failure)
    case Done{+q}:
      do IO<Unit>:
        loaded : Result<&1, &1, U32 & String, ConfigFile.Loaded> <- ConfigFile.load_config(Args.query_config(q), shard, Args.query_build(q))
        SearchShard.run_query(q, loaded)

def find_on(+args: List<&2, String>, flag: Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  match flag:
    case Fail{failure}:
      SearchReport.fail_job(Config.is_member(args, "--json"), failure)
    case Done{+shard}:
      query_or_fail(Config.is_member(args, "--json"), shard, Args.query_of(args))

def world_find(+args: List<&2, String>) -> IO(Unit):
  find_on(args, Args.shard_flag(Args.flag_value(args, "--shard")))

def print_level_tables(loaded: ConfigFile.Loaded, n: Nat, +from: U32) -> IO(Unit):
  match loaded:
    case ConfigFile.Forest{Config.Config{_, +build, _, _, _, _}}:
      SearchReport.world_print_seeds(build, n, from)
    case ConfigFile.Caves{CaveConfig.Config{_, +build, _, _, _}}:
      CaveScan.world_print_seeds(build, n, from)

def show_on(+args: List<&2, String>, flag: Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 1)
  +to = Args.arg_u32(args, 2n, from)
  do IO<Unit>:
    +shard : U32 <- IO.pass(U32, flag)
    +build : Maybe<&2, Builds.Build> <- IO.pass(Maybe<&2, Builds.Build>, Args.build_flag(Args.flag_value(args, "--build")))
    loaded : Result<&1, &1, U32 & String, ConfigFile.Loaded> <- ConfigFile.load_config(Args.flag_value(args, "--config"), shard, build)
    checked : ConfigFile.Loaded <- IO.pass(ConfigFile.Loaded, loaded)
    print_level_tables(checked, Nat.add(U32.to_nat((to - from : U32)), 1n), from)

def world_show(+args: List<&2, String>) -> IO(Unit):
  show_on(args, Args.shard_flag(Args.flag_value(args, "--shard")))

def odds_on(+args: List<&2, String>, flag: Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 0)
  +to = Args.arg_u32(args, 2n, from)
  do IO<Unit>:
    +shard : U32 <- IO.pass(U32, flag)
    +build : Maybe<&2, Builds.Build> <- IO.pass(Maybe<&2, Builds.Build>, Args.build_flag(Args.flag_value(args, "--build")))
    loaded : Result<&1, &1, U32 & String, ConfigFile.Loaded> <- ConfigFile.load_config(Args.flag_value(args, "--config"), shard, build)
    +checked : ConfigFile.Loaded <- IO.pass(ConfigFile.Loaded, loaded)
    SearchOdds.run(ConfigFile.build_of(checked), checked, from, to)

def world_odds(+args: List<&2, String>) -> IO(Unit):
  odds_on(args, Args.shard_flag(Args.flag_value(args, "--shard")))

def gen_on(+args: List<&2, String>, +shard: U32) -> IO(Unit):
  +from = Args.arg_u32(args, 0n, 0)
  +to = Args.arg_u32(args, 1n, from)
  +windows = Bool.not(String.eq(Maybe.default(&2, String, Args.flag_value(args, "--platform"), "windows"), "linux"))
  do IO<Unit>:
    +native : Bool <- IO.pass(Bool, Args.kk_flag(Args.flag_value(args, "--kk")))
    +build : Builds.Build <- IO.pass(Builds.Build, Args.flag_build(args))
    GenRun.seeds(build, Nat.add(U32.to_nat((to - from : U32)), 1n), from, GenRun.Options{windows, Config.is_member(args, "--times"), native,
      U32.is_eq(shard, 2), Args.read_or(Args.flag_value(args, "--dump"), 0), Args.read_or(Args.flag_value(args, "--draws"), 0)})

def gen(+args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +shard : U32 <- IO.pass(U32, Args.shard_flag(Args.flag_value(args, "--shard")))
    gen_on(args, shard)

def usage() -> IO(Unit):
  IO.die(Unit, 2, "usage: seedfinder setpiece find [FROM] [TO] [Name[:min[:max]] ...] [--shard forest|caves] [--build NUMBER] | seedfinder setpiece show FROM [TO] [--shard forest|caves] [--build NUMBER] | seedfinder world find [FROM [TO]] [--start-seed S] [--limit N] [--time-limit SECONDS] [--json] [--config filters.json] [--platform windows|linux] [--shard forest|caves] [--build NUMBER] [--worlds DIR] [--kk native|bend] | seedfinder world show FROM [TO] [--config filters.json] [--shard forest|caves] [--build NUMBER] | seedfinder world odds FROM [TO] [--config filters.json] [--shard forest|caves] [--build NUMBER] | seedfinder world dump SEED [TO] [--platform windows|linux] [--shard forest|caves] [--build NUMBER] [--kk native|bend] -o PATH | seedfinder gen SEED [TO] [--platform windows|linux] [--shard forest|caves] [--build NUMBER] [--times] [--kk native|bend] [--dump BITS] [--draws N]")

def trace_moved() -> IO(Unit):
  IO.die(Unit, 2, "seedfinder: trace is in the debug binary: seedfinder_trace trace SEED --stage NAME [--platform windows|linux] [--build NUMBER] [--input FILE] (scripts/build.sh trace)")

def setpiece_on(+build: Builds.Build, +mode: String, +args: List<&2, String>, +shard: U32) -> IO(Unit):
  +plain = Args.without_value_flag(Args.without_value_flag(args, "--shard"), "--build")
  Bool.pick(IO(Unit), U32.is_eq(shard, 2),
    Bool.pick(IO(Unit), String.eq(mode, "show"), CaveSetpiece.show(build, plain),
      Bool.pick(IO(Unit), String.eq(mode, "find"), CaveSetpiece.find(build, plain), usage())),
    Bool.pick(IO(Unit), String.eq(mode, "show"), SearchSetpiece.show(build, plain),
      Bool.pick(IO(Unit), String.eq(mode, "find"), SearchSetpiece.find(build, plain), usage())))

def setpiece(+args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +shard : U32 <- IO.pass(U32, Args.shard_flag(Args.flag_value(args, "--shard")))
    +build : Builds.Build <- IO.pass(Builds.Build, Args.flag_build(args))
    setpiece_on(build, Args.word(args, 0n), args, shard)

def world(+args: List<&2, String>) -> IO(Unit):
  +mode = Args.word(args, 0n)
  Bool.pick(IO(Unit), String.eq(mode, "show"), world_show(args),
    Bool.pick(IO(Unit), String.eq(mode, "find"), world_find(args),
      Bool.pick(IO(Unit), String.eq(mode, "eval"), SearchEval.run(args),
        Bool.pick(IO(Unit), String.eq(mode, "odds"), world_odds(args),
        Bool.pick(IO(Unit), String.eq(mode, "dump"), GenDump.run(args), usage())))))

def run(+command: String, +args: List<&2, String>) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(command, "setpiece"), setpiece(args),
    Bool.pick(IO(Unit), String.eq(command, "world"), world(args),
      Bool.pick(IO(Unit), String.eq(command, "gen"), gen(args),
        Bool.pick(IO(Unit), String.eq(command, "trace"), trace_moved(), usage()))))

def main() -> IO(Unit):
  do IO<Unit>:
    raw : List<String> <- IO.args()
    +args : List<&2, String> = Args.share(raw)
    run(Args.word(args, 1n), List.drop(&2, String, args, 2n))
