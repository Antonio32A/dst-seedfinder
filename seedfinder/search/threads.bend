import Base
import ../cli/files.bend as Files

# The runtime's worker thread count, for sizing the parallel rounds (results never depend on it): the value of the
# runtime's own `--threads N` flag in /proc/self/cmdline, else the online CPU count (the runtime's default) capped by
# the cgroup CPU quota, else 16.

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
      0

def quota_of(+quota: U32, +period: U32) -> U32:
  Bool.pick(U32, U32.is_zero(period), 0, ((quota + period - 1 : U32) / period : U32))

# The whole cores of a cgroup v2 cpu.max such as "1360000 100000" (13.6 cores: 14); 0 for "max 100000".
def quota_cores(parts: List<&2, String>) -> U32:
  match parts:
    case Con{+quota, Con{+period, _}}:
      quota_of(Maybe.default(&2, U32, U32.read(quota), 0), Maybe.default(&2, U32, U32.read(period), 0))
    case _:
      0

def from_quota(max: Result<&1, &1, U32 & String, String>) -> U32:
  match max:
    case Done{text}:
      quota_cores(String.split(String.trim(text), ' '))
    case Fail{_}:
      0

def capped(+cpus: U32, +quota: U32) -> U32:
  Bool.pick(U32, U32.is_zero(quota), cpus, Bool.pick(U32, U32.is_zero(cpus), quota, U32.min(cpus, quota)))

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
    cmdline : Result<&1, &1, U32 & String, List<&2, U32>> <- Files.read_bytes("", "/proc/self/cmdline")
    cpus : Result<&1, &1, U32 & String, String> <- Files.read_text("", "/sys/devices/system/cpu/online")
    max : Result<&1, &1, U32 & String, String> <- Files.read_text("", "/sys/fs/cgroup/cpu.max")
    return pick(flag_of(cmdline), capped(from_cpus(cpus), from_quota(max)))
