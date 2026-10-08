import Base
import ../level/summary.bend as LevelSummary

def world_line(+seed: U32) -> String:
  U32.show(seed) ++ " " ++ LevelSummary.summary_json(LevelSummary.summary(seed))

def world_print_seeds(n: Nat, +seed: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.print(world_line(seed))
        world_print_seeds(p, (seed + 1 : U32))

def stop_name(+code: U32) -> String:
  Bool.pick(String, U32.is_eq(code, 1), "limit", Bool.pick(String, U32.is_eq(code, 2), "end", "time"))

def scanned_of(+code: U32, +hits: List<&2, U32>, +start: U32, +total: Nat, +left: Nat) -> Nat:
  +last_hit = Maybe.default(&2, U32, List.last(&2, U32, hits), start)
  Bool.pick(Nat, U32.is_eq(code, 1), Nat.add(U32.to_nat((last_hit - start : U32)), 1n), Nat.sub(total, left))

def seed_space() -> Nat:
  Nat.mul(65536n, 65536n)

def position_json(+start: U32, +scanned: Nat, +code: U32) -> String:
  +next = (start + U32.from_nat(scanned) : U32)
  +last = Bool.pick(String, Nat.is_eq(scanned, 0n), "null", U32.show((next - 1 : U32)))
  +following = Bool.pick(String, U32.is_eq(code, 2) || Nat.is_eq(scanned, seed_space()), "null", U32.show(next))
  "\"scanned\":" ++ Nat.show(scanned) ++ ",\"last_scanned\":" ++ last ++ ",\"next_seed\":" ++ following

# A level-table hit's fields: without world rules, the first filter matches every candidate.
def hit_fields(+seed: U32) -> String:
  "\"entry\":0,\"level\":" ++ LevelSummary.summary_json(LevelSummary.summary(seed)) ++ ",\"results\":[]"

# A hit: its seed and the fields of its JSON object after the seed.
type Hit is Data:
  Hit{seed: U32, fields: String}

def hits_of(hits: List<&2, U32>) -> List<&2, Hit>:
  match hits:
    case Nil{}:
      Nil{}
    case Con{+seed, rest}:
      Hit{seed, hit_fields(seed)} <> hits_of(rest)

def hits_json(hits: List<&2, Hit>) -> List<&2, String>:
  match hits:
    case Nil{}:
      Nil{}
    case Con{Hit{+seed, +fields}, rest}:
      ("{\"seed\":" ++ U32.show(seed) ++ "," ++ fields ++ "}") <> hits_json(rest)

def print_hit_lines(hits: List<&2, Hit>) -> IO(Unit):
  match hits:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Hit{+seed, +fields}, rest}:
      do IO<Unit>:
        IO.print(U32.show(seed) ++ " {" ++ fields ++ "}")
        print_hit_lines(rest)

def exit_status(+found: U32) -> IO(Unit):
  Bool.pick(IO(Unit), U32.is_zero(found), IO.die(Unit, 1, "no hits"), IO.pure(Unit, Unit{}))

def platform_name(windows: Bool) -> String:
  match windows:
    case True{}:
      "windows"
    case False{}:
      "linux"

def print_hits_report(
  json: Bool, windows: Bool, +hits: List<&2, Hit>, +start: U32, +scanned: Nat, +found: U32, +code: U32
) -> IO(Unit):
  match json:
    case True{}:
      do IO<Unit>:
        IO.print("{\"version\":1,\"platform\":\"" ++ platform_name(windows) ++ "\",\"hits\":[" ++ String.join(hits_json(hits), ",") ++ "]," ++ position_json(start, scanned, code)
          ++ ",\"stopped\":\"" ++ stop_name(code) ++ "\"}")
        exit_status(found)
    case False{}:
      do IO<Unit>:
        print_hit_lines(hits)
        IO.print("done {" ++ position_json(start, scanned, code) ++ ",\"hits\":" ++ U32.show(found) ++ ",\"stopped\":\"" ++ stop_name(code) ++ "\"}")
        exit_status(found)

def print_report(
  json: Bool, windows: Bool, +hits: List<&2, U32>, +start: U32, +scanned: Nat, +found: U32, +code: U32
) -> IO(Unit):
  print_hits_report(json, windows, hits_of(hits), start, scanned, found, code)

def json_escaped(+code: U32) -> String:
  Bool.pick(String, U32.is_eq(code, 34) || U32.is_eq(code, 92), SCon{Chr{92}, SCon{Chr{code}, SNil{}}},
    SCon{Chr{Bool.pick(U32, (code < 32 : U32), 32, code)}, SNil{}})

def json_text(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+code}, rest}:
      json_escaped(code) ++ json_text(rest)

def print_error(failure: U32 & String) -> IO(Unit):
  (code, +message) = failure
  do IO<Unit>:
    IO.print("{\"error\":\"" ++ json_text(message) ++ "\"}")
    IO.die(Unit, 2, message)

def die_with(failure: U32 & String) -> IO(Unit):
  (code, message) = failure
  IO.die(Unit, 2, message)

def fail_job(json: Bool, failure: U32 & String) -> IO(Unit):
  match json:
    case True{}:
      print_error(failure)
    case False{}:
      die_with(failure)
