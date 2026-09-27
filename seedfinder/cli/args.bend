import Base
import ../filters/config.bend as Config

def share(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      h <> share(t)

def read_or(m: Maybe<&2, String>, +fallback: U32) -> U32:
  match m:
    case None{}:
      fallback
    case Some{s}:
      Maybe.default(&2, U32, U32.read(s), fallback)

def arg_u32(+args: List<&2, String>, i: Nat, +fallback: U32) -> U32:
  read_or(List.get(&2, String, args, i), fallback)

def word(+args: List<&2, String>, i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, args, i), "")

def value_flags() -> List<&2, String>:
  ["--config", "--start-seed", "--limit", "--time-limit", "--worlds", "--platform", "--kk", "-o"]

def flag_value(args: List<&2, String>, +flag: String) -> Maybe<&2, String>:
  match args:
    case Nil{}:
      None{}
    case Con{+arg, +rest}:
      Bool.pick(Maybe<&2, String>, String.eq(arg, flag), List.head(&2, String, rest),
        Bool.pick(Maybe<&2, String>, String.starts_with(arg, flag ++ "="), Some{String.drop(arg, Nat.add(String.length(flag), 1n))},
          flag_value(rest, flag)))

def is_inline_flag(flags: List<&2, String>, +arg: String) -> Bool:
  match flags:
    case Nil{}:
      False{}
    case Con{+flag, rest}:
      String.starts_with(arg, flag ++ "=") || is_inline_flag(rest, arg)

def arg_kind(+arg: String) -> U32:
  Bool.pick(U32, Config.is_member(value_flags(), arg), 2,
    Bool.pick(U32, String.eq(arg, "--json") || is_inline_flag(value_flags(), arg), 1,
      Bool.pick(U32, String.starts_with(arg, "--"), 3, 0)))

def with_positional(+kind: U32, +arg: String, +prefix: String, rest: Result<&1, &1, U32 & String, List<&2, String>>) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match rest:
    case Fail{failure}:
      Bool.pick(Result<&1, &1, U32 & String, List<&2, String>>, U32.is_eq(kind, 3), Fail{(2, prefix ++ "unknown option " ++ arg)}, Fail{failure})
    case Done{+given}:
      Bool.pick(Result<&1, &1, U32 & String, List<&2, String>>, U32.is_eq(kind, 3), Fail{(2, prefix ++ "unknown option " ++ arg)},
        Done{Bool.pick(List<&2, String>, U32.is_zero(kind), arg <> given, given)})

def positionals(args: List<&2, String>, skip: Bool, +prefix: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match args:
    case Nil{}:
      Bool.pick(Result<&1, &1, U32 & String, List<&2, String>>, skip, Fail{(2, prefix ++ "the last option is missing its value")}, Done{Nil{}})
    case Con{+arg, rest}:
      +kind = Bool.pick(U32, skip, 1, arg_kind(arg))
      with_positional(kind, arg, prefix, positionals(rest, U32.is_eq(kind, 2), prefix))

def number_or_fail(m: Maybe<&2, U32>, +prefix: String, +name: String, +text: String) -> Result<&1, &1, U32 & String, U32>:
  match m:
    case None{}:
      Fail{(2, prefix ++ name ++ " must be an integer in 0..4294967295, got \"" ++ text ++ "\"")}
    case Some{n}:
      Done{n}

def number_arg(m: Maybe<&2, String>, +fallback: U32, +prefix: String, +name: String) -> Result<&1, &1, U32 & String, U32>:
  match m:
    case None{}:
      Done{fallback}
    case Some{+text}:
      number_or_fail(U32.read(text), prefix, name, text)

def start_seed(flag: Maybe<&2, String>, from: Maybe<&2, String>) -> Result<&1, &1, U32 & String, U32>:
  match flag:
    case None{}:
      number_arg(from, 0, "search: ", "FROM")
    case Some{+text}:
      Bool.pick(Result<&1, &1, U32 & String, U32>, Maybe.is_some(&2, String, from), Fail{(2, "search: give the start seed either as FROM or as --start-seed")},
        number_or_fail(U32.read(text), "search: ", "--start-seed", text))

def total_of(to: Maybe<&2, String>, +start: U32) -> Result<&1, &1, U32 & String, Nat>:
  do Result<&1, &1, U32 & String, Nat>:
    +end : U32 <- number_arg(to, (start - 1 : U32), "search: ", "TO")
    return Nat.add(U32.to_nat((end - start : U32)), 1n)

def max_limit() -> U32:
  100

def limit_in_range(+limit: U32) -> Result<&1, &1, U32 & String, U32>:
  Bool.pick(Result<&1, &1, U32 & String, U32>, Bool.not(U32.is_zero(limit)) && (limit <= max_limit() : U32), Done{limit},
    Fail{(2, "search: --limit must be in 1.." ++ U32.show(max_limit()))})

def no_time_limit() -> Nat:
  Nat.mul(1000000n, 1000000n)

def digits_of(m: Maybe<&2, Nat>, +text: String) -> Result<&1, &1, U32 & String, Nat>:
  match m:
    case None{}:
      Fail{(2, "search: --time-limit must be seconds > 0 such as 0.25, got \"" ++ text ++ "\"")}
    case Some{n}:
      Done{n}

def positive(+ms: Nat, +text: String) -> Result<&1, &1, U32 & String, Nat>:
  Bool.pick(Result<&1, &1, U32 & String, Nat>, Nat.is_eq(ms, 0n), digits_of(None{}, text), Done{ms})

def millis(+whole: String, +fraction: String, +text: String) -> Result<&1, &1, U32 & String, Nat>:
  do Result<&1, &1, U32 & String, Nat>:
    +seconds : Nat <- digits_of(Nat.read(whole), text)
    digits : Nat <- digits_of(Nat.read(fraction), text)
    +ms : Nat <- digits_of(Nat.read(String.take(fraction ++ "00", 3n)), text)
    positive(Nat.add(Nat.mul(Nat.min(seconds, 1000000000n), 1000n), ms), text)

def seconds_parts(parts: List<&2, String>, +text: String) -> Result<&1, &1, U32 & String, Nat>:
  match parts:
    case Con{+whole, Nil{}}:
      millis(whole, "0", text)
    case Con{+whole, Con{+fraction, Nil{}}}:
      millis(whole, fraction, text)
    case _:
      digits_of(None{}, text)

def time_limit(m: Maybe<&2, String>) -> Result<&1, &1, U32 & String, Nat>:
  match m:
    case None{}:
      Done{no_time_limit()}
    case Some{+text}:
      seconds_parts(String.split(text, '.'), text)

# The --platform flag: 0 when absent (the config's platform), 1 windows, 2 linux.
def platform_flag(m: Maybe<&2, String>) -> Result<&1, &1, U32 & String, U32>:
  match m:
    case None{}:
      Done{0}
    case Some{+text}:
      Bool.pick(Result<&1, &1, U32 & String, U32>, String.eq(text, "windows"), Done{1},
        Bool.pick(Result<&1, &1, U32 & String, U32>, String.eq(text, "linux"), Done{2}, Fail{(2, "--platform must be windows or linux, got \"" ++ text ++ "\"")}))

# The --kk flag: the KK engine, native (the C KK, the default) or bend (kk.bend, for validation).
def kk_flag(m: Maybe<&2, String>) -> Result<&1, &1, U32 & String, Bool>:
  match m:
    case None{}:
      Done{True{}}
    case Some{+text}:
      Bool.pick(Result<&1, &1, U32 & String, Bool>, String.eq(text, "native"), Done{True{}},
        Bool.pick(Result<&1, &1, U32 & String, Bool>, String.eq(text, "bend"), Done{False{}}, Fail{(2, "--kk must be native or bend, got \"" ++ text ++ "\"")}))

# A world find query; `platform` overrides the config's platform (platform_flag), `worlds` is the --worlds folder of
# pre-generated world dumps (<seed>.dstw), `native` the KK engine (kk_flag).
type Query is Data:
  Query{start: U32, total: Nat, limit: U32, time_ms: Nat, json: Bool, config: Maybe<&2, String>, platform: U32, worlds: Maybe<&2, String>, native: Bool}

def at_most_two(+given: List<&2, String>) -> Result<&1, &1, U32 & String, Unit>:
  Bool.pick(Result<&1, &1, U32 & String, Unit>, Nat.is_le(List.length(&2, String, given), 2n), Done{Unit{}},
    Fail{(2, "search: world find takes at most FROM and TO")})

def query_of(+args: List<&2, String>) -> Result<&1, &1, U32 & String, Query>:
  do Result<&1, &1, U32 & String, Query>:
    +given : List<&2, String> <- positionals(List.drop(&2, String, args, 1n), False{}, "search: ")
    few : Unit <- at_most_two(given)
    +start : U32 <- start_seed(flag_value(args, "--start-seed"), List.get(&2, String, given, 0n))
    +total : Nat <- total_of(List.get(&2, String, given, 1n), start)
    +asked : U32 <- number_arg(flag_value(args, "--limit"), max_limit(), "search: ", "--limit")
    +limit : U32 <- limit_in_range(asked)
    +time_ms : Nat <- time_limit(flag_value(args, "--time-limit"))
    +platform : U32 <- platform_flag(flag_value(args, "--platform"))
    +native : Bool <- kk_flag(flag_value(args, "--kk"))
    return Query{start, total, limit, time_ms, Config.is_member(args, "--json"), flag_value(args, "--config"), platform, flag_value(args, "--worlds"), native}

def query_config(+q: Query) -> Maybe<&2, String>:
  match q:
    case Query{_, _, _, _, _, config, _, _, _}:
      config

def query_json(+q: Query) -> Bool:
  match q:
    case Query{_, _, _, _, +json, _, _, _, _}:
      json

# A world dump query: seeds from..from + total - 1, the platform, the KK engine (kk_flag) and the output path, a
# folder of <seed>.dstw dumps when `folder` (TO was given), else the dump file of the one seed.
type Dump is Data:
  Dump{from: U32, total: Nat, windows: Bool, native: Bool, out: String, folder: Bool}

def dump_usage() -> String:
  "usage: seedfinder world dump SEED [TO] [--platform windows|linux] [--kk native|bend] -o PATH"

def dump_out(m: Maybe<&2, String>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      Fail{(2, dump_usage())}
    case Some{+path}:
      Done{path}

def dump_seed(m: Maybe<&2, String>) -> Result<&1, &1, U32 & String, U32>:
  match m:
    case None{}:
      Fail{(2, dump_usage())}
    case Some{+text}:
      number_or_fail(U32.read(text), "dump: ", "SEED", text)

def dump_total(rest: List<&2, String>, +from: U32) -> Result<&1, &1, U32 & String, Nat>:
  match rest:
    case Nil{}:
      Done{1n}
    case Con{+to, Nil{}}:
      do Result<&1, &1, U32 & String, Nat>:
        +end : U32 <- number_or_fail(U32.read(to), "dump: ", "TO", to)
        Bool.pick(Result<&1, &1, U32 & String, Nat>, (end < from : U32), Fail{(2, "dump: TO must not be below SEED")},
          Done{Nat.add(U32.to_nat((end - from : U32)), 1n)})
    case _:
      Fail{(2, dump_usage())}

# The world dump query of `world dump SEED [TO] [--platform windows|linux] [--kk native|bend] -o PATH` (args start
# with "dump"; the platform defaults to windows).
def dump_of(+args: List<&2, String>) -> Result<&1, &1, U32 & String, Dump>:
  do Result<&1, &1, U32 & String, Dump>:
    +given : List<&2, String> <- positionals(List.drop(&2, String, args, 1n), False{}, "dump: ")
    +from : U32 <- dump_seed(List.head(&2, String, given))
    +total : Nat <- dump_total(List.drop(&2, String, given, 1n), from)
    +platform : U32 <- platform_flag(flag_value(args, "--platform"))
    +native : Bool <- kk_flag(flag_value(args, "--kk"))
    +out : String <- dump_out(flag_value(args, "-o"))
    return Dump{from, total, U32.is_ne(platform, 2), native, out, Nat.is_gt(List.length(&2, String, given), 1n)}
