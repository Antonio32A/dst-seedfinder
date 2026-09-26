import Base
import ../filters/config.bend as Config
import ../filters/rules.bend as Rules
import ../filters/world.bend as FilterWorld
import ../filters/evaluate.bend as Evaluate
import ../level/summary.bend as LevelSummary
import ../cli/files.bend as Files
import ./common.bend as SearchCommon
import ./report.bend as SearchReport
import ../cli/args.bend as Args
import ../filters/par.bend as Par

# `world find --worlds DIR` for configs with parts B-E: the scan of search.py over pre-generated worlds. Part A
# selects candidates chunk by chunk; each candidate's DIR/<seed>.dstw decides it (a missing dump counts as a world
# that gave up, i.e. no match, and is reported on stderr). A seed matches when an entry's part A and all its parts
# B-E hold; the first such entry is the hit's entry and its B-E witnesses are the results.

# The per-run constants: start seed, seeds in the scan, hit limit, time limit, output mode, config and folder.
type Ctx is Data:
  Ctx{start: U32, total: Nat, limit: U32, time_ms: Nat, json: Bool, config: Config.Config, dir: String, started: Nat}

type Verdict is Data:
  Hit{fields: String}
  Miss{}
  Absent{}

# The scan so far: next seed and seeds left to scan by part A, seeds decided from the start, hits (JSON objects of
# the job result), the stop code (0 running, 1 limit, 2 end, 3 time), missing dumps, and the pending candidates.
type Hunt is Data:
  Hunt{next: U32, left: Nat, decided: Nat, found: U32, hits: List<&2, String>, code: U32, missing: U32, pending: List<&2, U32>}

def chunk_size() -> Nat:
  65536n

def outcomes_of(skip: Bool, +world: FilterWorld.World, +later: Rules.Later) -> List<&2, Evaluate.Outcome>:
  match skip:
    case True{}:
      Nil{}
    case False{}:
      Evaluate.parallel_jobs(world, Evaluate.jobs_of(later))

def entry_verdict(+seed: U32, +index: U32, +outcomes: List<&2, Evaluate.Outcome>) -> Verdict:
  Hit{"\"entry\":" ++ U32.show(index) ++ ",\"level\":" ++ LevelSummary.summary_json(LevelSummary.summary(seed)) ++ ",\"results\":" ++ Evaluate.results_json(outcomes, True{})}

def first_entry(criteria: List<&2, Config.Criteria>, laters: List<&2, Rules.Later>, found: Bool, +world: FilterWorld.World, +seed: U32, +index: U32, +outcomes: List<&2, Evaluate.Outcome>) -> Verdict:
  match criteria laters found:
    case _ _ True{}:
      entry_verdict(seed, (index - 1 : U32), outcomes)
    case Con{+c, cs} Con{+later, ls} False{}:
      +level = Config.matches([c], seed)
      +next = outcomes_of(Bool.not(level), world, later)
      first_entry(cs, ls, level && Evaluate.holds(next), world, seed, (index + 1 : U32), next)
    case _ _ _:
      Miss{}

def platform_matches(+windows: Bool, +platform: U32) -> Bool:
  U32.is_zero(platform) || Bool.xor(windows, U32.is_eq(platform, 2))

def world_verdict(loaded: Result<&1, &1, U32 & String, FilterWorld.Loaded>, +config: Config.Config, +seed: U32) -> Verdict:
  match loaded config:
    case Done{FilterWorld.Generated{+world, +platform}} Config.Config{+windows, +criteria, +laters, _, _}:
      Bool.pick(Verdict, platform_matches(windows, platform), first_entry(criteria, laters, False{}, world, seed, 0, Nil{}), Absent{})
    case Done{FilterWorld.GaveUp{_}} _:
      Miss{}
    case Fail{_} _:
      Absent{}

def dump_path(+dir: String, +seed: U32) -> String:
  dir ++ "/" ++ U32.show(seed) ++ ".dstw"

# A candidate's dump bytes (None when unreadable).
type Read is Data:
  Read{seed: U32, bytes: Maybe<&2, List<&2, U32>>}

def maybe_bytes(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match r:
    case Done{bytes}:
      Some{bytes}
    case Fail{_}:
      None{}

def read_batch(seeds: List<&2, U32>, +dir: String, +acc: List<&2, Read>) -> IO(List<&2, Read>):
  match seeds:
    case Nil{}:
      IO.pure(List<&2, Read>, List.reverse(&2, Read, acc))
    case Con{+seed, rest}:
      do IO<List<&2, Read>>:
        bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Files.read_bytes("world: ", dump_path(dir, seed))
        read_batch(rest, dir, Read{seed, maybe_bytes(bytes)} <> acc)

type Judged is Data:
  Judged{seed: U32, verdict: Verdict}

def judged(config: Config.Config, r: Read) -> Judged:
  match r:
    case Read{+seed, Some{bytes}}:
      Judged{seed, world_verdict(FilterWorld.of_bytes(bytes), config, seed)}
    case Read{+seed, None{}}:
      Judged{seed, Absent{}}

def batch_size() -> Nat:
  32n

def hit_line(+seed: U32, v: Verdict) -> List<&2, String>:
  match v:
    case Hit{+fields}:
      [U32.show(seed) ++ " {" ++ fields ++ "}"]
    case _:
      Nil{}

def print_lines(+json: Bool, lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+line, rest}:
      do IO<Unit>:
        Bool.pick(IO(Unit), json, IO.pure(Unit, Unit{}), IO.print(line))
        print_lines(json, rest)

def hit_object(+seed: U32, v: Verdict) -> List<&2, String>:
  match v:
    case Hit{+fields}:
      ["{\"seed\":" ++ U32.show(seed) ++ "," ++ fields ++ "}"]
    case _:
      Nil{}

def is_hit(v: Verdict) -> Bool:
  match v:
    case Hit{_}:
      True{}
    case _:
      False{}

def is_absent(v: Verdict) -> Bool:
  match v:
    case Absent{}:
      True{}
    case _:
      False{}

def elapsed(+ctx: Ctx, +now: Nat) -> Nat:
  match ctx:
    case Ctx{_, _, _, _, _, _, _, +started}:
      Nat.sub(now, started)

def ctx_limit(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{_, _, +limit, _, _, _, _, _}:
      limit

def ctx_time(+ctx: Ctx) -> Nat:
  match ctx:
    case Ctx{_, _, _, +time_ms, _, _, _, _}:
      time_ms

def ctx_start(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{+start, _, _, _, _, _, _, _}:
      start

# The scan after deciding candidate `seed` with verdict v.
def decided(+h: Hunt, +v: Verdict, +seed: U32, +ctx: Ctx) -> Hunt:
  match h:
    case Hunt{+next, +left, _, +found, +hits, _, +missing, +pending}:
      +count = (found + Bool.to_u32(is_hit(v)) : U32)
      Hunt{next, left, Nat.add(U32.to_nat((seed - ctx_start(ctx) : U32)), 1n), count, List.append(&2, String, hits, hit_object(seed, v)),
        Bool.pick(U32, (count >= ctx_limit(ctx) : U32), 1, 0), (missing + Bool.to_u32(is_absent(v)) : U32), pending}

# The scan and the hit lines to print after a batch, in order, up to the hit limit.
type Folded is Data:
  Folded{hunt: Hunt, lines: List<&2, String>}

def folded(judged: List<&2, Judged>, +h: Hunt, +ctx: Ctx, +lines: List<&2, String>) -> Folded:
  match judged h:
    case Con{Judged{+seed, +v}, rest} Hunt{_, _, _, _, _, 0, _, _}:
      folded(rest, decided(h, v, seed, ctx), ctx, List.append(&2, String, lines, hit_line(seed, v)))
    case _ _:
      Folded{h, lines}

def folded_hunt(+f: Folded) -> Hunt:
  match f:
    case Folded{+h, _}:
      h

def folded_lines(+f: Folded) -> List<&2, String>:
  match f:
    case Folded{_, +lines}:
      lines

# The time stop after a batch.
def timed(+h: Hunt, +now: Nat, +ctx: Ctx) -> Hunt:
  match h:
    case Hunt{+next, +left, +scanned, +found, +hits, 0, +missing, +pending}:
      Hunt{next, left, scanned, found, hits, Bool.pick(U32, Nat.is_ge(elapsed(ctx, now), ctx_time(ctx)), 3, 0), missing, pending}
    case other:
      other

def ctx_config(+ctx: Ctx) -> Config.Config:
  match ctx:
    case Ctx{_, _, _, _, _, +config, _, _}:
      config

def ctx_dir(+ctx: Ctx) -> String:
  match ctx:
    case Ctx{_, _, _, _, _, _, +dir, _}:
      dir

def scan_leaf(n: Nat, +seed: U32, +criteria: List<&2, Config.Criteria>, +hits: List<&2, U32>) -> U32 & List<&2, U32>:
  match n:
    case 0n:
      (0, List.reverse(&2, U32, hits))
    case 1n+p:
      scan_leaf(p, (seed + 1 : U32), criteria, Bool.pick(List<&2, U32>, Config.matches(criteria, seed), seed <> hits, hits))

def scan_leaves(+depth: Nat, +lo: U32, +n: Nat, +criteria: List<&2, Config.Criteria>) -> U32 & List<&2, U32>:
  match depth:
    case 0n:
      scan_leaf(n, lo, Config.local_criteria(criteria), Nil{})
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = scan_leaves(d, lo, half, criteria) scan_leaves(d, (lo + U32.from_nat(half) : U32), Nat.sub(n, half), criteria)
      SearchCommon.combine(a, b)

def chunk_candidates(+len: Nat, +lo: U32, +criteria: List<&2, Config.Criteria>) -> U32 & List<&2, U32>:
  scan_leaves(SearchCommon.search_depth(), lo, len, criteria)

def criteria_of(+ctx: Ctx) -> List<&2, Config.Criteria>:
  match ctx:
    case Ctx{_, _, _, _, _, Config.Config{_, _, _, _, +scanned}, _, _}:
      scanned

def candidates(got: U32 & List<&2, U32>) -> List<&2, U32>:
  (count, seeds) = got
  seeds

def ctx_total(+ctx: Ctx) -> Nat:
  match ctx:
    case Ctx{_, +total, _, _, _, _, _, _}:
      total

# The next chunk's candidates (or the end or time stop).
def refilled(+h: Hunt, +now: Nat, +ctx: Ctx) -> Hunt:
  match h:
    case Hunt{+next, +left, _, +found, +hits, _, +missing, _}:
      +len = Nat.min(chunk_size(), left)
      +late = Nat.is_ge(elapsed(ctx, now), ctx_time(ctx))
      +done = Nat.is_eq(left, 0n)
      +scanned = Nat.sub(ctx_total(ctx), left)
      Bool.pick(Hunt, done || late, Hunt{next, left, scanned, found, hits, Bool.pick(U32, done, 2, 3), missing, Nil{}},
        Hunt{(next + U32.from_nat(len) : U32), Nat.sub(left, len), scanned, found, hits, 0, missing,
          candidates(chunk_candidates(len, next, criteria_of(ctx)))})

def json_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{_, _, _, _, +json, _, _, _}:
      json

def missing_note(+missing: U32, +dir: String) -> IO(Unit):
  Bool.pick(IO(Unit), U32.is_zero(missing), IO.pure(Unit, Unit{}),
    IO.print_err("search: " ++ U32.show(missing) ++ " candidates have no usable world dump in " ++ dir ++ " (counted as no match)"))

def platform_name(+windows: Bool) -> String:
  Bool.pick(String, windows, "windows", "linux")

def report(+h: Hunt, +ctx: Ctx) -> IO(Unit):
  match h ctx:
    case Hunt{_, _, +scanned, +found, +hits, +code, +missing, _} Ctx{+start, _, _, _, +json, Config.Config{+windows, _, _, _, _}, +dir, _}:
      +position = SearchReport.position_json(start, scanned, code)
      do IO<Unit>:
        missing_note(missing, dir)
        IO.print(Bool.pick(String, json,
          "{\"version\":1,\"platform\":\"" ++ platform_name(windows) ++ "\",\"hits\":[" ++ String.join(hits, ",") ++ "]," ++ position ++ ",\"stopped\":\"" ++ SearchReport.stop_name(code) ++ "\"}",
          "done {" ++ position ++ ",\"hits\":" ++ U32.show(found) ++ ",\"stopped\":\"" ++ SearchReport.stop_name(code) ++ "\"}"))
        SearchReport.exit_status(found)

def hunt(fuel: Nat, h: Hunt, +ctx: Ctx) -> IO(Unit):
  match fuel h:
    case 1n+k Hunt{+next, +left, +scanned, +found, +hits, 0, +missing, Con{+seed, +rest}}:
      +pending = {seed <> rest : List<&2, U32>}
      do IO<Unit>:
        reads : List<&2, Read> <- read_batch(List.take(&2, U32, pending, batch_size()), ctx_dir(ctx), Nil{})
        +f : Folded = folded(Par.map(~Read, ~Judged, ~Config.Config, ~judged, ctx_config(ctx), reads), Hunt{next, left, scanned, found, hits, 0, missing, List.drop(&2, U32, pending, batch_size())}, ctx, Nil{})
        print_lines(json_of(ctx), folded_lines(f))
        +now : Nat <- IO.now()
        hunt(k, timed(folded_hunt(f), now, ctx), ctx)
    case 1n+k Hunt{+next, +left, +scanned, +found, +hits, 0, +missing, Nil{}}:
      do IO<Unit>:
        +now : Nat <- IO.now()
        hunt(k, refilled(Hunt{next, left, scanned, found, hits, 0, missing, Nil{}}, now, ctx), ctx)
    case _ other:
      report(other, ctx)

# world find --worlds DIR for a config with parts B-E (docs/config.md section 8 output).
def run(+q: Args.Query, +config: Config.Config, +dir: String) -> IO(Unit):
  match q:
    case Args.Query{+start, +total, +limit, +time_ms, +json, _, _, _, _}:
      do IO<Unit>:
        +started : Nat <- IO.now()
        hunt(Nat.add(Nat.add(total, Nat.div(total, chunk_size())), 4n), Hunt{start, total, 0n, 0, Nil{}, 0, 0, Nil{}},
          Ctx{start, total, limit, time_ms, json, config, dir, started})
