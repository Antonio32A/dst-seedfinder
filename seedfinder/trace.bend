import Base
import ./cli/args.bend as Args
import ./trace/command.bend as TraceCommand

# Debug binary with every lane's trace stages (.scratch/port/CONVENTIONS.md "Trace mode"); the production binary is
# main.bend. Usage:
#   seedfinder_trace trace SEED --stage NAME [--platform windows|linux] [--input FILE]

def usage() -> IO(Unit):
  IO.die(Unit, 2, "usage: seedfinder_trace trace SEED --stage NAME [--platform windows|linux] [--input FILE]")

def run(+command: String, +args: List<&2, String>) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(command, "trace"), TraceCommand.trace(args), usage())

def main() -> IO(Unit):
  do IO<Unit>:
    raw : List<String> <- IO.args()
    +args : List<&2, String> = Args.share(raw)
    run(Args.word(args, 0n), List.drop(&2, String, args, 1n))
