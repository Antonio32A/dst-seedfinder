import Base
import ./filters/config.bend as Config
import ./cli/args.bend as Args
import ./cli/config_file.bend as ConfigFile
import ./search/setpiece.bend as SearchSetpiece
import ./search/report.bend as SearchReport
import ./search/scan.bend as SearchScan
import ./search/eval.bend as SearchEval
import ./gen/run.bend as GenRun

# Usage (default world settings):
#   seedfinder setpiece find [FROM] [TO] [Name[:min[:max]] ...]
#     parallel search over seeds FROM..TO (inclusive)
#   seedfinder setpiece show FROM [TO]
#     set pieces of seeds FROM..TO, one JSON line each
#   seedfinder world find [FROM [TO]] [--start-seed S] [--limit N] [--time-limit SECONDS] [--json] [--config filters.json]
#                         [--platform windows|linux] [--worlds DIR] [--kk native|bend]
#     parallel scan from S (or FROM, default 0) up to TO or once around the 2^32 seeds, stopping at N hits
#     (1..100, default 100) or when the time limit is up (docs/config.md section 8); parts B-E are
#     decided on worlds generated in memory (or on DIR/<seed>.dstw dumps with --worlds)
#   seedfinder world show FROM [TO] [--config filters.json]
#     level table of seeds FROM..TO, one JSON line each (the config is only validated)
#   seedfinder gen SEED [TO] [--platform windows|linux] [--times] [--kk native|bend]
#     forest worldgen of seeds SEED..TO, one line per seed (`--times`: one line per stage of every attempt)
#   the worldgen trace stages are in the debug binary built from trace.bend (seedfinder_trace trace ...)

def query_or_fail(json: Bool, parsed: Result<&1, &1, U32 & String, Args.Query>) -> IO(Unit):
  match parsed:
    case Fail{failure}:
      SearchReport.fail_job(json, failure)
    case Done{+q}:
      do IO<Unit>:
        loaded : Result<&1, &1, U32 & String, Config.Config> <- ConfigFile.load_config(Args.query_config(q))
        SearchScan.run_query(q, loaded)

def world_find(+args: List<&2, String>) -> IO(Unit):
  query_or_fail(Config.is_member(args, "--json"), Args.query_of(args))

def world_show(+args: List<&2, String>) -> IO(Unit):
  +from = Args.arg_u32(args, 1n, 1)
  +to = Args.arg_u32(args, 2n, from)
  do IO<Unit>:
    loaded : Result<&1, &1, U32 & String, Config.Config> <- ConfigFile.load_config(Args.flag_value(args, "--config"))
    unused : Config.Config <- IO.pass(Config.Config, loaded)
    SearchReport.world_print_seeds(Nat.add(U32.to_nat((to - from : U32)), 1n), from)

def gen(+args: List<&2, String>) -> IO(Unit):
  +from = Args.arg_u32(args, 0n, 0)
  +to = Args.arg_u32(args, 1n, from)
  +windows = Bool.not(String.eq(Maybe.default(&2, String, Args.flag_value(args, "--platform"), "windows"), "linux"))
  do IO<Unit>:
    +native : Bool <- IO.pass(Bool, Args.kk_flag(Args.flag_value(args, "--kk")))
    GenRun.seeds(Nat.add(U32.to_nat((to - from : U32)), 1n), from, windows, Config.is_member(args, "--times"), native)

def usage() -> IO(Unit):
  IO.die(Unit, 2, "usage: seedfinder setpiece find [FROM] [TO] [Name[:min[:max]] ...] | seedfinder setpiece show FROM [TO] | seedfinder world find [FROM [TO]] [--start-seed S] [--limit N] [--time-limit SECONDS] [--json] [--config filters.json] [--platform windows|linux] [--worlds DIR] [--kk native|bend] | seedfinder world show FROM [TO] [--config filters.json] | seedfinder gen SEED [TO] [--platform windows|linux] [--times] [--kk native|bend]")

def trace_moved() -> IO(Unit):
  IO.die(Unit, 2, "seedfinder: trace is in the debug binary: seedfinder_trace trace SEED --stage NAME [--platform windows|linux] [--input FILE] (scripts/build.sh trace)")

def setpiece(+args: List<&2, String>) -> IO(Unit):
  +mode = Args.word(args, 0n)
  Bool.pick(IO(Unit), String.eq(mode, "show"), SearchSetpiece.show(args),
    Bool.pick(IO(Unit), String.eq(mode, "find"), SearchSetpiece.find(args), usage()))

def world(+args: List<&2, String>) -> IO(Unit):
  +mode = Args.word(args, 0n)
  Bool.pick(IO(Unit), String.eq(mode, "show"), world_show(args),
    Bool.pick(IO(Unit), String.eq(mode, "find"), world_find(args),
      Bool.pick(IO(Unit), String.eq(mode, "eval"), SearchEval.run(args), usage())))

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
