import Base
import ../cli/files.bend as FL

# The runtime's worker thread count, for sizing the parallel rounds (results never depend on it): the value of the
# runtime's own `--threads N` flag in /proc/self/cmdline, else the online CPU count (the runtime's default), else 16.

def text_of(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}:
      SNil{}
    case Con{+b, rest}:
      SCon{Chr{Bool.pick(U32, U32.is_zero(b), 10, b)}, text_of(rest)}

def counted(+n: U32) -> U32:
  U32.min(U32.max(n, 1), 128)

# The value after the first `--threads` before `--` (0 when absent).
def flag_in(args: List<&2, String>) -> U32:
  match args:
    case Con{+arg, +rest}:
      Bool.pick(U32, String.eq(arg, "--"), 0,
        Bool.pick(U32, String.eq(arg, "--threads"), Maybe.default(&2, U32, U32.read(Maybe.default(&2, String, List.head(&2, String, rest), "")), 0), flag_in(rest)))
    case Nil{}:
      0

def range_count(parts: List<&2, String>) -> U32:
  match parts:
    case Con{+lo, Con{+hi, Nil{}}}:
      (Maybe.default(&2, U32, U32.read(hi), 0) - Maybe.default(&2, U32, U32.read(lo), 0) + 1 : U32)
    case Con{_, Nil{}}:
      1
    case _:
      0

# The CPUs of a sysfs cpu list such as "0-23" or "0-3,8-11".
def cpus_in(ranges: List<&2, String>) -> U32:
  match ranges:
    case Nil{}:
      0
    case Con{+r, rest}:
      (range_count(String.split(String.trim(r), '-')) + cpus_in(rest) : U32)

def from_cpus(cpus: Result<&1, &1, U32 & String, String>) -> U32:
  match cpus:
    case Done{text}:
      cpus_in(String.split(String.trim(text), ','))
    case Fail{_}:
      16

def pick(+flag: U32, +cpus: U32) -> U32:
  counted(Bool.pick(U32, U32.is_zero(flag), Bool.pick(U32, U32.is_zero(cpus), 16, cpus), flag))

def flag_of(cmdline: Result<&1, &1, U32 & String, List<&2, U32>>) -> U32:
  match cmdline:
    case Done{bytes}:
      flag_in(String.split(text_of(bytes), '\n'))
    case Fail{_}:
      0

def threads() -> IO(U32):
  do IO<U32>:
    cmdline : Result<&1, &1, U32 & String, List<&2, U32>> <- FL.read_bytes("", "/proc/self/cmdline")
    cpus : Result<&1, &1, U32 & String, String> <- FL.read_text("", "/sys/devices/system/cpu/online")
    return pick(flag_of(cmdline), from_cpus(cpus))
