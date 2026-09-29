import Base
import ./filters/config.bend as Config
import ./cli/args.bend as Args
import ./cli/config_file.bend as ConfigFile
import ./search/setpiece.bend as SearchSetpiece
import ./search/report.bend as SearchReport
import ./search/shard.bend as SearchShard
import ./search/cave_scan.bend as CaveScan
import ./search/cave_setpiece.bend as CaveSetpiece
import ./search/eval.bend as SearchEval
import ./gen/run.bend as GenRun
import ./gen/dump.bend as GenDump

# Usage (default world settings):
#   seedfinder setpiece find [FROM] [TO] [Name[:min[:max]] ...] [--shard forest|caves]
#     parallel search over seeds FROM..TO (inclusive)
#   seedfinder setpiece show FROM [TO] [--shard forest|caves]
#     set pieces of seeds FROM..TO, one JSON line each
#   seedfinder world find [FROM [TO]] [--start-seed S] [--limit N] [--time-limit SECONDS] [--json] [--config filters.json]
#                         [--platform windows|linux] [--shard forest|caves] [--worlds DIR] [--kk native|bend]
#     parallel scan from S (or FROM, default 0) up to TO or once around the 2^32 seeds, stopping at N hits
#     (1..100, default 100) or when the time limit is up (docs/config.md section 8); parts B-E are
#     decided on worlds generated in memory (or on DIR/<seed>.dstw dumps with --worlds)
#   seedfinder world show FROM [TO] [--config filters.json] [--shard forest|caves]
#     level table of seeds FROM..TO, one JSON line each (the config is only validated)
#   seedfinder world dump SEED [TO] [--platform windows|linux] [--shard forest|caves] [--kk native|bend] -o PATH
#     parallel worldgen of seeds SEED..TO into world dumps (docs/world-dump.md): PATH is the dump of SEED, or with TO
#     an existing folder for PATH/<seed>.dstw; one line per seed
#   seedfinder gen SEED [TO] [--platform windows|linux] [--shard forest|caves] [--times] [--kk native|bend] [--dump BITS] [--draws N]
#     worldgen of seeds SEED..TO, one line per seed (`--times`: one line per stage of every attempt); the caves shard only
#     runs up to ForceConnectivity: `--dump` adds the attempt's tile map (1) and story graph (2), `--draws` starts an attempt
#     N draws into the seed's stream
#   the worldgen trace stages are in the debug binary built from trace.bend (seedfinder_trace trace ...)

def query_or_fail(json: Bool, +shard: U32, parsed: Result<&1, &1, U32 & String, Args.Query>) -> IO(Unit):
  match parsed:
    case Fail{failure}:
      SearchReport.fail_job(json, failure)
    case Done{+q}:
      do IO<Unit>:
        loaded : Result<&1, &1, U32 & String, ConfigFile.Loaded> <- ConfigFile.load_config(Args.query_config(q), shard)
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
    case ConfigFile.Forest{_}:
      SearchReport.world_print_seeds(n, from)
    case ConfigFile.Caves{_}:
      CaveScan.world_print_seeds(n, from)

def show_on(+args: List<&2, String>, flag: Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 1)
  +to = Args.arg_u32(args, 2n, from)
  do IO<Unit>:
    +shard : U32 <- IO.pass(U32, flag)
    loaded : Result<&1, &1, U32 & String, ConfigFile.Loaded> <- ConfigFile.load_config(Args.flag_value(args, "--config"), shard)
    checked : ConfigFile.Loaded <- IO.pass(ConfigFile.Loaded, loaded)
    print_level_tables(checked, Nat.add(U32.to_nat((to - from : U32)), 1n), from)

def world_show(+args: List<&2, String>) -> IO(Unit):
  show_on(args, Args.shard_flag(Args.flag_value(args, "--shard")))

def gen_on(+args: List<&2, String>, +shard: U32) -> IO(Unit):
  +from = Args.arg_u32(args, 0n, 0)
  +to = Args.arg_u32(args, 1n, from)
  +windows = Bool.not(String.eq(Maybe.default(&2, String, Args.flag_value(args, "--platform"), "windows"), "linux"))
  do IO<Unit>:
    +native : Bool <- IO.pass(Bool, Args.kk_flag(Args.flag_value(args, "--kk")))
    GenRun.seeds(Nat.add(U32.to_nat((to - from : U32)), 1n), from, GenRun.Options{windows, Config.is_member(args, "--times"), native,
      U32.is_eq(shard, 2), Args.read_or(Args.flag_value(args, "--dump"), 0), Args.read_or(Args.flag_value(args, "--draws"), 0)})

def gen(+args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +shard : U32 <- IO.pass(U32, Args.shard_flag(Args.flag_value(args, "--shard")))
    gen_on(args, shard)

def dump(+args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +shard : U32 <- IO.pass(U32, Args.shard_flag(Args.flag_value(args, "--shard")))
    Bool.pick(IO(Unit), U32.is_eq(shard, 2), IO.die(Unit, 2, "dump: the caves worldgen stops before the mazes (gen --shard caves)"), GenDump.run(args))

def usage() -> IO(Unit):
  IO.die(Unit, 2, "usage: seedfinder setpiece find [FROM] [TO] [Name[:min[:max]] ...] [--shard forest|caves] | seedfinder setpiece show FROM [TO] [--shard forest|caves] | seedfinder world find [FROM [TO]] [--start-seed S] [--limit N] [--time-limit SECONDS] [--json] [--config filters.json] [--platform windows|linux] [--shard forest|caves] [--worlds DIR] [--kk native|bend] | seedfinder world show FROM [TO] [--config filters.json] [--shard forest|caves] | seedfinder world dump SEED [TO] [--platform windows|linux] [--shard forest|caves] [--kk native|bend] -o PATH | seedfinder gen SEED [TO] [--platform windows|linux] [--shard forest|caves] [--times] [--kk native|bend] [--dump BITS] [--draws N]")

def trace_moved() -> IO(Unit):
  IO.die(Unit, 2, "seedfinder: trace is in the debug binary: seedfinder_trace trace SEED --stage NAME [--platform windows|linux] [--input FILE] (scripts/build.sh trace)")

def setpiece_on(+mode: String, +args: List<&2, String>, +shard: U32) -> IO(Unit):
  +plain = Args.without_value_flag(args, "--shard")
  Bool.pick(IO(Unit), U32.is_eq(shard, 2),
    Bool.pick(IO(Unit), String.eq(mode, "show"), CaveSetpiece.show(plain),
      Bool.pick(IO(Unit), String.eq(mode, "find"), CaveSetpiece.find(plain), usage())),
    Bool.pick(IO(Unit), String.eq(mode, "show"), SearchSetpiece.show(plain),
      Bool.pick(IO(Unit), String.eq(mode, "find"), SearchSetpiece.find(plain), usage())))

def setpiece(+args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +shard : U32 <- IO.pass(U32, Args.shard_flag(Args.flag_value(args, "--shard")))
    setpiece_on(Args.word(args, 0n), args, shard)

def world(+args: List<&2, String>) -> IO(Unit):
  +mode = Args.word(args, 0n)
  Bool.pick(IO(Unit), String.eq(mode, "show"), world_show(args),
    Bool.pick(IO(Unit), String.eq(mode, "find"), world_find(args),
      Bool.pick(IO(Unit), String.eq(mode, "eval"), SearchEval.run(args),
        Bool.pick(IO(Unit), String.eq(mode, "dump"), dump(args), usage()))))

def run(+command: String, +args: List<&2, String>) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(command, "setpiece"), setpiece(args),
    Bool.pick(IO(Unit), String.eq(command, "world"), world(args),
      Bool.pick(IO(Unit), String.eq(command, "gen"), gen(args),
        Bool.pick(IO(Unit), String.eq(command, "trace"), trace_moved(), usage()))))

def main() -> IO(Unit):
  do IO<Unit>:
    raw : List<String> <- IO.args()
    +args : List<&2, String> = Args.share(raw)
    run(Args.word(args, 0n), List.drop(&2, String, args, 1n))
