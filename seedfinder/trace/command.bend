import Base
import ../cli/args.bend as A
import ../cli/files.bend as FL
import ./dispatch.bend as D

# seedfinder trace SEED --stage NAME [--platform windows|linux] [--input FILE]

def fail(+message: String) -> Result<&1, &1, U32 & String, Unit>:
  Fail{(2, "trace: " ++ message)}

def platform_of(m: Maybe<&2, String>) -> Result<&1, &1, U32 & String, Bool>:
  match m:
    case None{}:
      Done{True{}}
    case Some{+name}:
      Bool.pick(Result<&1, &1, U32 & String, Bool>, String.eq(name, "windows"), Done{True{}},
        Bool.pick(Result<&1, &1, U32 & String, Bool>, String.eq(name, "linux"), Done{False{}},
          Fail{(2, "trace: unknown platform \"" ++ name ++ "\" (windows or linux)")}))

def seed_of(m: Maybe<&2, U32>) -> Result<&1, &1, U32 & String, U32>:
  match m:
    case None{}:
      Fail{(2, "trace: SEED must be an integer in 0..4294967295")}
    case Some{seed}:
      Done{seed}

def stage_of(m: Maybe<&2, String>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      Fail{(2, "trace: --stage is required")}
    case Some{stage}:
      Done{stage}

def input_text(m: Maybe<&2, String>) -> IO(Result<&1, &1, U32 & String, String>):
  match m:
    case None{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Done{""})
    case Some{+path}:
      FL.read_text("trace: ", path)

def print_lines(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+line, rest}:
      do IO<Unit>:
        IO.print(line)
        print_lines(rest)

def platform_name(windows: Bool) -> String:
  match windows:
    case True{}:
      "windows"
    case False{}:
      "linux"

def header(+stage: String, +seed: U32, +windows: Bool) -> String:
  "# bend stage=" ++ stage ++ " seed=" ++ U32.show(seed) ++ " platform=" ++ platform_name(windows) ++ " format=1"

def print_traced(traced: Result<&1, &1, U32 & String, List<&2, String>>, +stage: String, +seed: U32, +windows: Bool) -> IO(Unit):
  match traced:
    case Fail{failure}:
      (code, message) = failure
      IO.die(Unit, 2, message)
    case Done{lines}:
      do IO<Unit>:
        IO.print(header(stage, seed, windows))
        print_lines(lines)

def traced_text(text: Result<&1, &1, U32 & String, String>, +stage: String, +seed: U32, +windows: Bool) -> IO(Unit):
  match text:
    case Fail{failure}:
      (code, message) = failure
      IO.die(Unit, 2, message)
    case Done{+input}:
      print_traced(D.run(stage, seed, windows, input), stage, seed, windows)

type Request is Data:
  Request{seed: U32, stage: String, windows: Bool}

def request_of(+args: List<&2, String>) -> Result<&1, &1, U32 & String, Request>:
  do Result<&1, &1, U32 & String, Request>:
    +seed : U32 <- seed_of(U32.read(A.word(args, 0n)))
    +stage : String <- stage_of(A.flag_value(args, "--stage"))
    +windows : Bool <- platform_of(A.flag_value(args, "--platform"))
    return Request{seed, stage, windows}

def run_request(parsed: Result<&1, &1, U32 & String, Request>, +args: List<&2, String>) -> IO(Unit):
  match parsed:
    case Fail{failure}:
      (code, message) = failure
      IO.die(Unit, 2, message)
    case Done{Request{+seed, +stage, +windows}}:
      do IO<Unit>:
        text : Result<&1, &1, U32 & String, String> <- input_text(A.flag_value(args, "--input"))
        traced_text(text, stage, seed, windows)

# Prints the canonical records of one stage (see .scratch/port/CONVENTIONS.md "Trace mode").
def trace(+args: List<&2, String>) -> IO(Unit):
  run_request(request_of(args), args)
