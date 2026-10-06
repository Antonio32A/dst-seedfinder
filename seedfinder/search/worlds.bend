import Base
import ../filters/shard_search.bend as ShardSearch
import ../filters/rules.bend as Rules
import ../filters/world.bend as FilterWorld
import ../filters/evaluate.bend as Evaluate
import ../cli/files.bend as Files
import ./common.bend as SearchCommon
import ./report.bend as SearchReport
import ../cli/args.bend as Args
import ../filters/par.bend as Par
import ./speed.bend as Speed
import ./timings.bend as Timings

# `world find --worlds DIR` for configs with parts B-E: the scan of search.py over pre-generated worlds. Part A
# selects candidates chunk by chunk; each candidate's DIR/<seed>.dstw decides it (a missing dump counts as a world
# that gave up, i.e. no match, and is reported on stderr). A seed matches when an entry's part A and all its parts
# B-E hold; the first such entry is the hit's entry and its B-E witnesses are the results. A dump without the topology
# (no GRPH section) counts as missing too when an entry has a bridges rule, and one without the level plan (no PLAN
# section) when an entry has a setpieces rule with `placed` names.

# The per-run constants: start seed, seeds in the scan, hit limit, time limit, output mode, config, folder, start time
# and whether to time the options (--verbose-timings).
type Ctx is Data:
  Ctx{start: U32, total: Nat, limit: U32, time_ms: Nat, json: Bool, config: ShardSearch.Search, dir: String, started: Nat, timings: Bool}

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

def later_holds(level: Bool, +world: FilterWorld.World, +later: Rules.Later) -> Bool:
  match level:
    case True{}:
      Evaluate.parallel_holds(world, Evaluate.jobs_of(later))
    case False{}:
      False{}

def entry_verdict(+seed: U32, +caves: Bool, +index: U32, +outcomes: List<&2, Evaluate.Outcome>) -> Verdict:
  Hit{"\"entry\":" ++ U32.show(index) ++ ",\"level\":" ++ ShardSearch.summary_json(caves, seed) ++ ",\"results\":" ++ Evaluate.results_json(outcomes, True{})}

def first_entry(flags: List<&2, Bool>, laters: List<&2, Rules.Later>, found: Bool, +world: FilterWorld.World, +seed: U32, +caves: Bool, +index: U32, +outcomes: List<&2, Evaluate.Outcome>) -> Verdict:
  match flags laters found:
    case _ _ True{}:
      entry_verdict(seed, caves, (index - 1 : U32), outcomes)
    case Con{+level, cs} Con{+later, ls} False{}:
      +found = later_holds(level, world, later)
      first_entry(cs, ls, found, world, seed, caves, (index + 1 : U32), outcomes_of(Bool.not(found), world, later))
    case _ _ _:
      Miss{}

def later_at(+laters: List<&2, Rules.Later>, +index: U32) -> Rules.Later:
  Maybe.default(&2, Rules.Later, List.get(&2, Rules.Later, laters, U32.to_nat(index)), Rules.nothing_later())

# A world's verdict from the option that matched it after Timings.judged, as world_verdict gives it (`otherwise` when
# none did).
def open_verdict(+o: Timings.Open, +config: ShardSearch.Search, +seed: U32, +otherwise: Verdict) -> Verdict:
  match o:
    case Timings.Open{Some{+world}, _, Some{+index}}:
      entry_verdict(seed, ShardSearch.caves(config), index, Evaluate.parallel_jobs(world, Evaluate.jobs_of(later_at(ShardSearch.laters(config), index))))
    case _:
      otherwise

# A world after Timings.judged: its seed, the option that matched it and its verdict when none did.
type Matched is Data:
  Matched{seed: U32, open: Timings.Open, otherwise: Verdict}

def matched_with(+config: ShardSearch.Search, m: Matched) -> Judged:
  match m:
    case Matched{+seed, +o, +otherwise}:
      Judged{seed, open_verdict(o, config, seed, otherwise)}

def matched_judged(config: ShardSearch.Search, m: Matched) -> Judged:
  matched_with(config, m)

# The verdicts of the worlds after Timings.judged (the witnesses and level tables of the hits), in parallel, in order.
def matched_verdicts(+config: ShardSearch.Search, +matches: List<&2, Matched>) -> List<&2, Judged>:
  Par.map(~Matched, ~Judged, ~ShardSearch.Search, ~matched_judged, config, matches)

def platform_matches(+windows: Bool, +platform: U32) -> Bool:
  U32.is_zero(platform) || Bool.xor(windows, U32.is_eq(platform, 2))

def usable(+config: ShardSearch.Search, +platform: U32, +world: FilterWorld.World) -> Bool:
  platform_matches(ShardSearch.windows(config), platform) && (FilterWorld.has_graph(world) || Bool.not(Rules.needs_graph(ShardSearch.laters(config))))
    && (FilterWorld.has_plan(world) || Bool.not(Rules.needs_plan(ShardSearch.laters(config))))

def world_verdict(loaded: Result<&1, &1, U32 & String, FilterWorld.Loaded>, +config: ShardSearch.Search, +seed: U32) -> Verdict:
  match loaded:
    case Done{FilterWorld.Generated{+world, +platform}}:
      Bool.pick(Verdict, usable(config, platform, world),
        first_entry(ShardSearch.entry_flags(ShardSearch.entries(config), seed), ShardSearch.laters(config), False{}, world, seed, ShardSearch.caves(config), 0, Nil{}), Absent{})
    case Done{FilterWorld.GaveUp{_}}:
      Miss{}
    case Fail{_}:
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

def judged_with(+config: ShardSearch.Search, r: Read) -> Judged:
  match r:
    case Read{+seed, Some{bytes}}:
      Judged{seed, world_verdict(FilterWorld.of_bytes_in(bytes, ShardSearch.caves(config)), config, seed)}
    case Read{+seed, None{}}:
      Judged{seed, Absent{}}

def judged(config: ShardSearch.Search, r: Read) -> Judged:
  judged_with(config, r)

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
    case Ctx{_, _, _, _, _, _, _, +started, _}:
      Nat.sub(now, started)

def ctx_limit(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{_, _, +limit, _, _, _, _, _, _}:
      limit

def ctx_time(+ctx: Ctx) -> Nat:
  match ctx:
    case Ctx{_, _, _, +time_ms, _, _, _, _, _}:
      time_ms

def ctx_start(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{+start, _, _, _, _, _, _, _, _}:
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

def ctx_config(+ctx: Ctx) -> ShardSearch.Search:
  match ctx:
    case Ctx{_, _, _, _, _, +config, _, _, _}:
      config

def ctx_dir(+ctx: Ctx) -> String:
  match ctx:
    case Ctx{_, _, _, _, _, _, +dir, _, _}:
      dir

def scan_leaves(+depth: Nat, +lo: U32, +n: Nat, +levels: ShardSearch.Levels) -> U32 & List<&2, U32>:
  match depth:
    case 0n:
      (0, ShardSearch.candidates_leaf(levels, lo, n))
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = scan_leaves(d, lo, half, levels) scan_leaves(d, (lo + U32.from_nat(half) : U32), Nat.sub(n, half), levels)
      SearchCommon.combine(a, b)

def chunk_candidates(+len: Nat, +lo: U32, +levels: ShardSearch.Levels) -> U32 & List<&2, U32>:
  scan_leaves(SearchCommon.search_depth(), lo, len, levels)

def criteria_of(+ctx: Ctx) -> ShardSearch.Levels:
  match ctx:
    case Ctx{_, _, _, _, _, +config, _, _, _}:
      ShardSearch.scanned(config)

def candidates(got: U32 & List<&2, U32>) -> List<&2, U32>:
  (count, seeds) = got
  seeds

def ctx_total(+ctx: Ctx) -> Nat:
  match ctx:
    case Ctx{_, +total, _, _, _, _, _, _, _}:
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

def ctx_timings(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{_, _, _, _, _, _, _, _, +timings}:
      timings

def json_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{_, _, _, _, +json, _, _, _, _}:
      json

def missing_note(+missing: U32, +dir: String) -> IO(Unit):
  Bool.pick(IO(Unit), U32.is_zero(missing), IO.pure(Unit, Unit{}),
    IO.print_err("search: " ++ U32.show(missing) ++ " candidates have no usable world dump in " ++ dir
      ++ " (missing, unreadable, of the other platform, or without the topology a bridges rule or the level plan a placed set piece needs;"
      ++ " regenerate those; counted as no match)"))

def platform_name(+windows: Bool) -> String:
  Bool.pick(String, windows, "windows", "linux")

# The speed points, when the speed line was last printed, the candidates decided and the --verbose-timings timings.
type Pace is Data:
  Pace{points: List<&2, Speed.Point>, shown: Nat, made: Nat, timings: Timings.Timings}

def pace_line(+p: Pace, +h: Hunt, +now: Nat, +ctx: Ctx) -> String:
  match p h:
    case Pace{+points, _, +made, _} Hunt{_, +left, +decided, _, _, _, _, _}:
      Speed.line(Speed.ticked(points, Speed.Point{elapsed(ctx, now), Nat.sub(ctx_total(ctx), left), made, decided}))

def pace_timings(+p: Pace) -> Timings.Timings:
  match p:
    case Pace{_, _, _, +t}:
      t

def report(+h: Hunt, +ctx: Ctx, +pace: Pace) -> IO(Unit):
  match h ctx:
    case Hunt{_, _, +scanned, +found, +hits, +code, +missing, _} Ctx{+start, _, _, _, +json, +config, +dir, _, +timings}:
      +position = SearchReport.position_json(start, scanned, code)
      do IO<Unit>:
        +now : Nat <- IO.now()
        missing_note(missing, dir)
        IO.print_err(pace_line(pace, h, now, ctx))
        Timings.print_if(timings, pace_timings(pace), elapsed(ctx, now))
        IO.print(Bool.pick(String, json,
          "{\"version\":1,\"platform\":\"" ++ platform_name(ShardSearch.windows(config)) ++ "\",\"hits\":[" ++ String.join(hits, ",") ++ "]," ++ position ++ ",\"stopped\":\"" ++ SearchReport.stop_name(code) ++ "\"}",
          "done {" ++ position ++ ",\"hits\":" ++ U32.show(found) ++ ",\"stopped\":\"" ++ SearchReport.stop_name(code) ++ "\"}"))
        SearchReport.exit_status(found)

# The speed line (and the timings) once a second, after a batch decided `n` more candidates.
def paced(+p: Pace, +n: Nat, +h: Hunt, +now: Nat, +ctx: Ctx) -> IO(Pace):
  match p h:
    case Pace{+points, +shown, +made, +t} Hunt{_, +left, +decided, _, _, _, _, _}:
      +point = {Speed.Point{elapsed(ctx, now), Nat.sub(ctx_total(ctx), left), Nat.add(made, n), decided} : Speed.Point}
      +due = Nat.is_ge(Nat.sub(now, shown), 1000n)
      do IO<Pace>:
        Bool.pick(IO(Unit), due, IO.print_err(Speed.line(Speed.ticked(points, point))), IO.pure(Unit, Unit{}))
        Timings.print_if(due && ctx_timings(ctx), t, elapsed(ctx, now))
        return Pace{Bool.pick(List<&2, Speed.Point>, due, Speed.ticked(points, point), points), Bool.pick(Nat, due, now, shown), Nat.add(made, n), t}

def with_pace_timings(+p: Pace, +t: Timings.Timings) -> Pace:
  match p:
    case Pace{+points, +shown, +made, _}:
      Pace{points, shown, made, t}

# A read dump as Timings.judged checks it: its world when usable, and its verdict when no option matches.
type Loaded is Data:
  Loaded{seed: U32, world: Maybe<&2, FilterWorld.World>, otherwise: Verdict}

def loaded_of(+seed: U32, loaded: Result<&1, &1, U32 & String, FilterWorld.Loaded>, +config: ShardSearch.Search) -> Loaded:
  match loaded:
    case Done{FilterWorld.Generated{+world, +platform}}:
      Bool.pick(Loaded, usable(config, platform, world), Loaded{seed, Some{world}, Miss{}}, Loaded{seed, None{}, Absent{}})
    case Done{FilterWorld.GaveUp{_}}:
      Loaded{seed, None{}, Miss{}}
    case Fail{_}:
      Loaded{seed, None{}, Absent{}}

def loaded_with(+config: ShardSearch.Search, r: Read) -> Loaded:
  match r:
    case Read{+seed, Some{bytes}}:
      loaded_of(seed, FilterWorld.of_bytes_in(bytes, ShardSearch.caves(config)), config)
    case Read{+seed, None{}}:
      Loaded{seed, None{}, Absent{}}

def loaded_read(config: ShardSearch.Search, r: Read) -> Loaded:
  loaded_with(config, r)

def opens_of(loaded: List<&2, Loaded>, +config: ShardSearch.Search) -> List<&2, Timings.Open>:
  match loaded:
    case Nil{}:
      Nil{}
    case Con{Loaded{+seed, +world, _}, rest}:
      Timings.Open{world, ShardSearch.entry_flags(ShardSearch.entries(config), seed), None{}} <> opens_of(rest, config)

def matches_of(loaded: List<&2, Loaded>, +opens: List<&2, Timings.Open>) -> List<&2, Matched>:
  match loaded opens:
    case Con{Loaded{+seed, _, +otherwise}, ls} Con{+o, os}:
      Matched{seed, o, otherwise} <> matches_of(ls, os)
    case _ _:
      Nil{}

# The verdicts of a batch and the pace after it.
type Batch is Data:
  Batch{judged: List<&2, Judged>, pace: Pace}

def judged_with_timings(+loaded: List<&2, Loaded>, +j: Timings.Judged, +p: Pace, +ctx: Ctx) -> IO(Batch):
  match j:
    case Timings.Judged{+t, +opens}:
      do IO<Batch>:
        +t0 : Nat <- IO.now()
        +verdicts : List<&2, Judged> = matched_verdicts(ctx_config(ctx), matches_of(loaded, opens))
        +t1 : Nat <- IO.now()
        return Batch{verdicts, with_pace_timings(p, Timings.with_hits(t, Nat.sub(t1, t0)))}

def judged_batch(timed: Bool, reads: List<&2, Read>, +p: Pace, +ctx: Ctx) -> IO(Batch):
  match timed:
    case False{}:
      IO.pure(Batch, Batch{Par.map(~Read, ~Judged, ~ShardSearch.Search, ~judged, ctx_config(ctx), reads), p})
    case True{}:
      +loaded = Par.map(~Read, ~Loaded, ~ShardSearch.Search, ~loaded_read, ctx_config(ctx), reads)
      do IO<Batch>:
        +j : Timings.Judged <- Timings.judged(pace_timings(p), ShardSearch.laters(ctx_config(ctx)), opens_of(loaded, ctx_config(ctx)))
        judged_with_timings(loaded, j, p, ctx)

def batch_judged(+b: Batch) -> List<&2, Judged>:
  match b:
    case Batch{+judged, _}:
      judged

def batch_pace(+b: Batch) -> Pace:
  match b:
    case Batch{_, +p}:
      p

def scan_chunk(+h: Hunt) -> U32 & Nat:
  match h:
    case Hunt{+next, +left, _, _, _, _, _, _}:
      (next, Nat.min(chunk_size(), left))

def counted_chunk(+t: Timings.Timings, +ctx: Ctx, chunk: U32 & Nat) -> IO(Timings.Timings):
  (+lo, +len) = chunk
  Timings.prefiltered(t, ShardSearch.each_entry(ShardSearch.entries(ctx_config(ctx))), lo, len)

# The scan and the pace after a refill.
type Refilled is Data:
  Refilled{hunt: Hunt, pace: Pace}

def refilled_hunt(+r: Refilled) -> Hunt:
  match r:
    case Refilled{+h, _}:
      h

def refilled_pace(+r: Refilled) -> Pace:
  match r:
    case Refilled{_, +p}:
      p

# The next chunk's candidates, with --verbose-timings each option's level table first over the chunk on its own and
# the scan's own timed.
def timed_refill(timed: Bool, +h: Hunt, +p: Pace, +now: Nat, +ctx: Ctx) -> IO(Refilled):
  match timed:
    case False{}:
      IO.pure(Refilled, Refilled{refilled(h, now, ctx), p})
    case True{}:
      do IO<Refilled>:
        +counted : Timings.Timings <- counted_chunk(pace_timings(p), ctx, scan_chunk(h))
        +t0 : Nat <- IO.now()
        +after : Hunt = refilled(h, now, ctx)
        +t1 : Nat <- IO.now()
        return Refilled{after, with_pace_timings(p, Timings.with_prefilter(counted, Nat.sub(t1, t0)))}

def scanning(+h: Hunt, +now: Nat, +ctx: Ctx) -> Bool:
  match h:
    case Hunt{_, +left, _, _, _, _, _, _}:
      Nat.is_gt(left, 0n) && Nat.is_lt(elapsed(ctx, now), ctx_time(ctx))

def hunt(fuel: Nat, h: Hunt, +ctx: Ctx, +pace: Pace) -> IO(Unit):
  match fuel h:
    case 1n+k Hunt{+next, +left, +scanned, +found, +hits, 0, +missing, Con{+seed, +rest}}:
      +pending = {seed <> rest : List<&2, U32>}
      do IO<Unit>:
        reads : List<&2, Read> <- read_batch(List.take(&2, U32, pending, batch_size()), ctx_dir(ctx), Nil{})
        +batch : Batch <- judged_batch(ctx_timings(ctx), reads, pace, ctx)
        +f : Folded = folded(batch_judged(batch), Hunt{next, left, scanned, found, hits, 0, missing, List.drop(&2, U32, pending, batch_size())}, ctx, Nil{})
        print_lines(json_of(ctx), folded_lines(f))
        +now : Nat <- IO.now()
        +after : Hunt = timed(folded_hunt(f), now, ctx)
        +p : Pace <- paced(batch_pace(batch), List.length(&2, Judged, batch_judged(batch)), after, now, ctx)
        hunt(k, after, ctx, p)
    case 1n+k Hunt{+next, +left, +scanned, +found, +hits, 0, +missing, Nil{}}:
      +h = {Hunt{next, left, scanned, found, hits, 0, missing, Nil{}} : Hunt}
      do IO<Unit>:
        +now : Nat <- IO.now()
        +got : Refilled <- timed_refill(ctx_timings(ctx) && scanning(h, now, ctx), h, pace, now, ctx)
        hunt(k, refilled_hunt(got), ctx, refilled_pace(got))
    case _ other:
      report(other, ctx, pace)

# world find --worlds DIR for a config with parts B-E (docs/config.md section 8 output).
def run(+q: Args.Query, +config: ShardSearch.Search, +dir: String) -> IO(Unit):
  match q:
    case Args.Query{+start, +total, +limit, +time_ms, +json, _, _, _, _, +timings}:
      do IO<Unit>:
        +started : Nat <- IO.now()
        hunt(Nat.add(Nat.add(total, Nat.div(total, chunk_size())), 4n), Hunt{start, total, 0n, 0, Nil{}, 0, 0, Nil{}},
          Ctx{start, total, limit, time_ms, json, config, dir, started, timings}, Pace{Speed.started(), started, 0n, Timings.started(ShardSearch.laters(config))})
