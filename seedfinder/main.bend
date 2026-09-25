import Base
import ./filters/config.bend as CF
import ./cli/args.bend as A
import ./cli/config_file.bend as CFG
import ./search/setpiece.bend as SP
import ./search/report.bend as RP
import ./search/scan.bend as SW
import ./search/eval.bend as EVC
import ./gen/run.bend as GN

# Usage (default world settings):
#   seedfinder setpiece find [FROM] [TO] [Name[:min[:max]] ...]
#     parallel search over seeds FROM..TO (inclusive)
#   seedfinder setpiece show FROM [TO]
#     set pieces of seeds FROM..TO, one JSON line each
#   seedfinder world find [FROM [TO]] [--start-seed S] [--limit N] [--time-limit SECONDS] [--json] [--config filters.json]
#                         [--platform windows|linux] [--worlds DIR]
#     parallel scan from S (or FROM, default 0) up to TO or once around the 2^32 seeds, stopping at N hits
#     (1..100, default 100) or when the time limit is up (.scratch/spec/search-v1.md section 8); parts B-E are
#     decided on worlds generated in memory (or on DIR/<seed>.dstw dumps with --worlds)
#   seedfinder world show FROM [TO] [--config filters.json]
#     level table of seeds FROM..TO, one JSON line each (the config is only validated)
#   seedfinder gen SEED [TO] [--platform windows|linux] [--times]
#     forest worldgen of seeds SEED..TO, one line per seed (`--times`: one line per stage of every attempt)
#   the worldgen trace stages are in the debug binary built from trace.bend (seedfinder_trace trace ...)

def query_or_fail(json: Bool, parsed: Result<&1, &1, U32 & String, A.Query>) -> IO(Unit):
  match parsed:
    case Fail{failure}:
      RP.fail_job(json, failure)
    case Done{+q}:
      do IO<Unit>:
        loaded : Result<&1, &1, U32 & String, CF.Config> <- CFG.load_config(A.query_config(q))
        SW.run_query(q, loaded)

def world_find(+args: List<&2, String>) -> IO(Unit):
  query_or_fail(CF.is_member(args, "--json"), A.query_of(args))

def world_show(+args: List<&2, String>) -> IO(Unit):
  +from = A.arg_u32(args, 1n, 1)
  +to = A.arg_u32(args, 2n, from)
  do IO<Unit>:
    loaded : Result<&1, &1, U32 & String, CF.Config> <- CFG.load_config(A.flag_value(args, "--config"))
    unused : CF.Config <- IO.pass(CF.Config, loaded)
    RP.world_print_seeds(Nat.add(U32.to_nat((to - from : U32)), 1n), from)

def gen(+args: List<&2, String>) -> IO(Unit):
  +from = A.arg_u32(args, 0n, 0)
  +to = A.arg_u32(args, 1n, from)
  +windows = Bool.not(String.eq(Maybe.default(&2, String, A.flag_value(args, "--platform"), "windows"), "linux"))
  GN.seeds(Nat.add(U32.to_nat((to - from : U32)), 1n), from, windows, CF.is_member(args, "--times"))

def usage() -> IO(Unit):
  IO.die(Unit, 2, "usage: seedfinder setpiece find [FROM] [TO] [Name[:min[:max]] ...] | seedfinder setpiece show FROM [TO] | seedfinder world find [FROM [TO]] [--start-seed S] [--limit N] [--time-limit SECONDS] [--json] [--config filters.json] [--platform windows|linux] [--worlds DIR] | seedfinder world show FROM [TO] [--config filters.json] | seedfinder gen SEED [TO] [--platform windows|linux] [--times]")

def trace_moved() -> IO(Unit):
  IO.die(Unit, 2, "seedfinder: trace is in the debug binary: seedfinder_trace trace SEED --stage NAME [--platform windows|linux] [--input FILE] (scripts/build.sh trace)")

def setpiece(+args: List<&2, String>) -> IO(Unit):
  +mode = A.word(args, 0n)
  Bool.pick(IO(Unit), String.eq(mode, "show"), SP.show(args),
    Bool.pick(IO(Unit), String.eq(mode, "find"), SP.find(args), usage()))

def world(+args: List<&2, String>) -> IO(Unit):
  +mode = A.word(args, 0n)
  Bool.pick(IO(Unit), String.eq(mode, "show"), world_show(args),
    Bool.pick(IO(Unit), String.eq(mode, "find"), world_find(args),
      Bool.pick(IO(Unit), String.eq(mode, "eval"), EVC.run(args), usage())))

def run(+command: String, +args: List<&2, String>) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(command, "setpiece"), setpiece(args),
    Bool.pick(IO(Unit), String.eq(command, "world"), world(args),
      Bool.pick(IO(Unit), String.eq(command, "gen"), gen(args),
        Bool.pick(IO(Unit), String.eq(command, "trace"), trace_moved(), usage()))))

def main() -> IO(Unit):
  do IO<Unit>:
    raw : List<String> <- IO.args()
    +args : List<&2, String> = A.share(raw)
    run(A.word(args, 0n), List.drop(&2, String, args, 1n))
