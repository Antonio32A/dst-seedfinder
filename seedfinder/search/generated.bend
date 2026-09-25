import Base
import ../filters/config.bend as CF
import ../filters/world.bend as WD
import ../gen/job.bend as GJ
import ../gen/savedata.bend as GV
import ../cli/args.bend as A
import ./report.bend as RP
import ./worlds.bend as SWD
import ./order.bend as SO
import ./threads.bend as STH

# `world find` for configs with parts B-E, on worlds generated in memory: part A picks the candidates chunk by chunk
# (the level-table scan), and only candidates are generated, many at once in fuel-bounded rounds. Each round fills
# the free slots with the next candidates in scan order, advances every slot's job by the same budget in parallel
# (a slow seed only holds its own slot), and decides the finished ones on their world as `world find --worlds` does
# (the first entry whose part A and parts B-E hold; a seed without a world never matches). Decided seeds are
# released in scan order, so the hits are those of a sequential scan whatever the thread count.

# A slot of a round: free, a candidate being generated, or a decided candidate.
type Slot is Type:
  Free{}
  Busy{seed: U32, job: GJ.Job}
  Decided{seed: U32, verdict: SWD.Verdict}

type Slots is Type:
  Leaf{slot: Slot}
  Fork{a: Slots, b: Slots}

def free_slots(+n: Nat) -> List<&1, Slot>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Free{} <> free_slots(p)

type Split is Type:
  Split{front: List<&1, Slot>, back: List<&1, Slot>}

def split_loop(n: Nat, xs: List<&1, Slot>, acc: List<&1, Slot>) -> Split:
  match n:
    case 0n:
      Split{List.reverse(&1, Slot, acc), xs}
    case 1n+p:
      match xs:
        case Nil{}:
          Split{List.reverse(&1, Slot, acc), Nil{}}
        case Con{x, rest}:
          split_loop(p, rest, x <> acc)

def split(+n: Nat, xs: List<&1, Slot>) -> Split:
  split_loop(Nat.div(n, 2n), xs, Nil{})

def leaf_of(xs: List<&1, Slot>) -> Slots:
  match xs:
    case Nil{}:
      Leaf{Free{}}
    case Con{x, _}:
      Leaf{x}

# The balanced tree of the n slots front ++ back (front holds n / 2 of them), halving down to one slot per leaf.
def grown(+d: Nat, sp: Split, +n: Nat) -> Slots:
  match d:
    case 0n:
      match sp:
        case Split{_, back}:
          leaf_of(back)
    case 1n+p:
      match sp:
        case Split{front, back}:
          match n:
            case 0n:
              Leaf{Free{}}
            case 1n+m:
              match m:
                case 0n:
                  leaf_of(back)
                case 1n+_:
                  +half = Nat.div(n, 2n)
                  Fork{grown(p, split(half, front), half), grown(p, split(Nat.sub(n, half), back), Nat.sub(n, half))}

def tree_of(xs: List<&1, Slot>, +n: Nat) -> Slots:
  grown(n, split(n, xs), n)

def flat(s: Slots) -> List<&1, Slot>:
  match s:
    case Leaf{slot}:
      [slot]
    case Fork{a, b}:
      List.append(&1, Slot, flat(a), flat(b))

# The per-run constants: scan start and length, hit limit, time limit, output mode, config, the start time and the
# number of slots (the runtime's thread count, so every slot of a round has a thread).
type Ctx is Data:
  Ctx{start: U32, total: Nat, limit: U32, time_ms: Nat, json: Bool, config: CF.Config, started: Nat, width: Nat}

def width_of(+ctx: Ctx) -> Nat:
  match ctx:
    case Ctx{_, _, _, _, _, _, _, +width}:
      width

def config_of(+ctx: Ctx) -> CF.Config:
  match ctx:
    case Ctx{_, _, _, _, _, +config, _, _}:
      config

def windows_of(+config: CF.Config) -> Bool:
  match config:
    case CF.Config{+windows, _, _, _}:
      windows

def world_verdict(job: GJ.Job, +config: CF.Config, +seed: U32) -> SWD.Verdict:
  match job:
    case GJ.JWorld{_, _, final}:
      SWD.world_verdict(Done{WD.Generated{GV.world(seed, windows_of(config), final), 0}}, config, seed)
    case _:
      SWD.Miss{}

def settled_slot(settled: Bool, job: GJ.Job, +config: CF.Config, +seed: U32) -> Slot:
  match settled:
    case True{}:
      Decided{seed, world_verdict(job, config, seed)}
    case False{}:
      Busy{seed, job}

def is_settled(got: GJ.Job & GJ.Where) -> GJ.Job & Bool:
  (job, +at) = got
  match at:
    case GJ.Where{+stage, _}:
      (job, GJ.settled(stage))

# Up to `budget` job steps of `fuel` KK phase steps each; a settled job is decided on its world.
def worked(budget: Nat, got: GJ.Job & Bool, +config: CF.Config, +seed: U32, +fuel: Nat) -> Slot:
  match budget:
    case 0n:
      (job, +settled) = got
      settled_slot(settled, job, config, seed)
    case 1n+b:
      (job, +settled) = got
      match settled:
        case True{}:
          settled_slot(True{}, job, config, seed)
        case False{}:
          worked(b, is_settled(GJ.stage(GJ.advance(fuel, job))), config, seed, fuel)

def work(slot: Slot, +config: CF.Config, +budget: Nat, +fuel: Nat) -> Slot:
  match slot:
    case Busy{+seed, job}:
      worked(budget, is_settled(GJ.stage(job)), config, seed, fuel)
    case other:
      other

# One round of every slot, both halves of each fork in parallel.
def worked_all(s: Slots, +config: CF.Config, +budget: Nat, +fuel: Nat) -> Slots:
  match s:
    case Leaf{slot}:
      Leaf{work(slot, config, budget, fuel)}
    case Fork{a, b}:
      x y = worked_all(a, config, budget, fuel) worked_all(b, config, budget, fuel)
      Fork{x, y}

def worked_list(xs: List<&1, Slot>, +width: Nat, +config: CF.Config, +budget: Nat, +fuel: Nat) -> List<&1, Slot>:
  flat(worked_all(tree_of(xs, width), config, budget, fuel))

# The decided slots taken out (newest first), the others kept in order.
type Harvested is Type:
  Harvested{slots: List<&1, Slot>, done: List<&2, SWD.Judged>}

def harvest(xs: List<&1, Slot>, +done: List<&2, SWD.Judged>, acc: List<&1, Slot>) -> Harvested:
  match xs:
    case Nil{}:
      Harvested{List.reverse(&1, Slot, acc), done}
    case Con{x, rest}:
      match x:
        case Decided{+seed, +v}:
          harvest(rest, SWD.Judged{seed, v} <> done, Free{} <> acc)
        case other:
          harvest(rest, done, other <> acc)

# Nat.min by one native comparison. Base's Nat.min recurses once per unit (8 bytes of a worker's 2 GB machine stack),
# so scan positions past 2^28 overflow it.
def lesser(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(b, a), b, a)

# The slots after giving every free one the next pending candidate, the candidates left, the smallest scan position
# of a busy slot (`first` when none) and the number of busy slots.
type Filled is Type:
  Filled{slots: List<&1, Slot>, pending: List<&2, U32>, first: Nat, busy: U32}

def fill(xs: List<&1, Slot>, +pending: List<&2, U32>, +windows: Bool, +start: U32, +first: Nat, +busy: U32, acc: List<&1, Slot>) -> Filled:
  match xs:
    case Nil{}:
      Filled{List.reverse(&1, Slot, acc), pending, first, busy}
    case Con{x, rest}:
      match x:
        case Busy{+seed, job}:
          fill(rest, pending, windows, start, lesser(first, SO.position(seed, start)), (busy + 1 : U32), Busy{seed, job} <> acc)
        case other:
          match pending:
            case Nil{}:
              fill(rest, Nil{}, windows, start, first, busy, other <> acc)
            case Con{+seed, +more}:
              fill(rest, more, windows, start, lesser(first, SO.position(seed, start)), (busy + 1 : U32), Busy{seed, GJ.start(seed, windows)} <> acc)

def judged_seed(+j: SWD.Judged) -> U32:
  match j:
    case SWD.Judged{+seed, _}:
      seed

def judged_position(+j: SWD.Judged, +start: U32) -> Nat:
  SO.position(judged_seed(j), start)

# Hits found (JSON objects of the job result), hit lines to print, the scan position after the last hit, the stop
# code (0 running, 1 limit, 2 end, 3 time) and the decided prefix of the scan.
type Tally is Data:
  Tally{found: U32, hits: List<&2, String>, lines: List<&2, String>, last: Nat, code: U32, scanned: Nat}

def tallied(+t: Tally, +seed: U32, +v: SWD.Verdict, +ctx: Ctx) -> Tally:
  match t ctx:
    case Tally{+found, +hits, +lines, +last, _, +scanned} Ctx{+start, _, +limit, _, _, _, _, _}:
      +count = (found + Bool.to_u32(SWD.is_hit(v)) : U32)
      Tally{count, List.append(&2, String, hits, SWD.hit_object(seed, v)), List.append(&2, String, lines, SWD.hit_line(seed, v)),
        Bool.pick(Nat, SWD.is_hit(v), Nat.add(SO.position(seed, start), 1n), last), Bool.pick(U32, (count >= limit : U32), 1, 0), scanned}

def ready(+sorted: List<&2, SWD.Judged>, +frontier: Nat, +start: U32) -> Bool:
  match sorted:
    case Nil{}:
      False{}
    case Con{+j, _}:
      Nat.is_lt(judged_position(j, start), frontier)

def running(+t: Tally) -> Bool:
  match t:
    case Tally{_, _, _, _, +code, _}:
      U32.is_zero(code)

type Released is Data:
  Released{waiting: List<&2, SWD.Judged>, tally: Tally}

def ctx_start(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{+start, _, _, _, _, _, _, _}:
      start

# Decides the waiting candidates before the frontier (the first undecided scan position), in scan order, up to the
# hit limit.
def release(sorted: List<&2, SWD.Judged>, go: Bool, +frontier: Nat, +t: Tally, +ctx: Ctx) -> Released:
  match sorted:
    case Nil{}:
      Released{Nil{}, t}
    case Con{SWD.Judged{+seed, +v}, +rest}:
      match go:
        case False{}:
          Released{SWD.Judged{seed, v} <> rest, t}
        case True{}:
          +next = tallied(t, seed, v, ctx)
          release(rest, ready(rest, frontier, ctx_start(ctx)) && running(next), frontier, next, ctx)

# The part-A scan: next seed to scan, seeds left, the chunk size, and the candidates not yet started.
type Scan is Data:
  Scan{next: U32, left: Nat, size: Nat, pending: List<&2, U32>}

def min_chunk() -> Nat:
  65536n

def max_chunk() -> Nat:
  4194304n

def round_seeds() -> Nat:
  16777216n

def wanted() -> Nat:
  128n

def scanned_chunk(+sc: Scan, +criteria: List<&2, CF.Criteria>) -> Scan:
  match sc:
    case Scan{+next, +left, +size, +pending}:
      +len = lesser(size, left)
      +found = SWD.candidates(SWD.chunk_candidates(len, next, criteria))
      Scan{(next + U32.from_nat(len) : U32), Nat.sub(left, len), Bool.pick(Nat, Nat.is_lt(List.length(&2, U32, found), wanted()), lesser(Nat.mul(size, 2n), max_chunk()), size),
        List.append(&2, U32, pending, found)}

def short(+sc: Scan, +budget: Nat) -> Bool:
  match sc:
    case Scan{_, +left, _, +pending}:
      Nat.is_lt(List.length(&2, U32, pending), wanted()) && Nat.is_gt(left, 0n) && Nat.is_gt(budget, 0n)

def chunk_of(+sc: Scan) -> Nat:
  match sc:
    case Scan{_, _, +size, _}:
      size

# Scans part A chunk by chunk while candidates are short, up to round_seeds() seeds.
def refilled(n: Nat, go: Bool, +sc: Scan, +budget: Nat, +criteria: List<&2, CF.Criteria>) -> Scan:
  match n:
    case 0n:
      sc
    case 1n+p:
      match go:
        case False{}:
          sc
        case True{}:
          +next = scanned_chunk(sc, criteria)
          +rest = Nat.sub(budget, chunk_of(sc))
          refilled(p, short(next, rest), next, rest, criteria)

def refill(+sc: Scan, +criteria: List<&2, CF.Criteria>) -> Scan:
  refilled(64n, short(sc, round_seeds()), sc, round_seeds(), criteria)

# The search between rounds: the part-A scan, the slots, the decided candidates waiting for an earlier one, the tally,
# the KK fuel per job step, when the round started, and how many candidates were decided.
type Gen is Type:
  Gen{scan: Scan, slots: List<&1, Slot>, waiting: List<&2, SWD.Judged>, tally: Tally, fuel: Nat, ticked: Nat, made: U32}

# What a round hands to IO: hit lines to print, the stop code and a progress line.
type Out is Data:
  Out{lines: List<&2, String>, code: U32, progress: String}

def job_steps() -> Nat:
  6n

def adapted(+fuel: Nat, +round_ms: Nat, +remaining_ms: Nat) -> Nat:
  +grown = Bool.pick(Nat, Nat.is_lt(round_ms, 500n), Nat.min(Nat.mul(fuel, 2n), 16384n),
    Bool.pick(Nat, Nat.is_gt(round_ms, 2000n), Nat.max(Nat.div(fuel, 2n), 256n), fuel))
  Bool.pick(Nat, Nat.is_lt(remaining_ms, Nat.mul(round_ms, 2n)), Nat.max(Nat.div(grown, 4n), 64n), grown)

def elapsed(+ctx: Ctx, +now: Nat) -> Nat:
  match ctx:
    case Ctx{_, _, _, _, _, _, +started, _}:
      Nat.sub(now, started)

def remaining(+ctx: Ctx, +now: Nat) -> Nat:
  match ctx:
    case Ctx{_, _, _, +time_ms, _, _, +started, _}:
      Nat.sub(time_ms, Nat.sub(now, started))

def criteria_of(+ctx: Ctx) -> List<&2, CF.Criteria>:
  match ctx:
    case Ctx{_, _, _, _, _, CF.Config{_, +criteria, _, _}, _, _}:
      CF.or_anything(criteria)

def covered(+sc: Scan, +ctx: Ctx) -> Nat:
  match sc ctx:
    case Scan{_, +left, _, _} Ctx{_, +total, _, _, _, _, _, _}:
      Nat.sub(total, left)

def pending_of(+sc: Scan) -> List<&2, U32>:
  match sc:
    case Scan{_, _, _, +pending}:
      pending

def with_pending(+sc: Scan, +pending: List<&2, U32>) -> Scan:
  match sc:
    case Scan{+next, +left, +size, _}:
      Scan{next, left, size, pending}

def first_pending(+pending: List<&2, U32>, +start: U32, +otherwise: Nat) -> Nat:
  match pending:
    case Nil{}:
      otherwise
    case Con{+seed, _}:
      lesser(SO.position(seed, start), otherwise)

def with_scanned(+t: Tally, +scanned: Nat) -> Tally:
  match t:
    case Tally{+found, +hits, +lines, +last, +code, _}:
      Tally{found, hits, lines, last, code, scanned}

def with_code(+t: Tally, +code: U32) -> Tally:
  match t:
    case Tally{+found, +hits, +lines, +last, _, +scanned}:
      Tally{found, hits, lines, last, code, scanned}

def lines_of(+t: Tally) -> List<&2, String>:
  match t:
    case Tally{_, _, +lines, _, _, _}:
      lines

def without_lines(+t: Tally) -> Tally:
  match t:
    case Tally{+found, +hits, _, +last, +code, +scanned}:
      Tally{found, hits, Nil{}, last, code, scanned}

def code_of(+t: Tally) -> U32:
  match t:
    case Tally{_, _, _, _, +code, _}:
      code

def ended(+sc: Scan, +busy: U32, +waiting: List<&2, SWD.Judged>) -> Bool:
  match sc:
    case Scan{_, +left, _, +pending}:
      Nat.is_eq(left, 0n) && List.is_empty(&2, U32, pending) && U32.is_zero(busy) && List.is_empty(&2, SWD.Judged, waiting)

def progress(+t: Tally, +made: U32, +busy: U32, +waiting: List<&2, SWD.Judged>, +fuel: Nat, +round_ms: Nat) -> String:
  match t:
    case Tally{+found, _, _, _, _, +scanned}:
      "search: scanned " ++ Nat.show(scanned) ++ ", worlds " ++ U32.show(made) ++ ", generating " ++ U32.show(busy)
        ++ ", waiting " ++ Nat.show(List.length(&2, SWD.Judged, waiting)) ++ ", hits " ++ U32.show(found) ++ " (fuel "
        ++ Nat.show(fuel) ++ ", last round " ++ Nat.show(round_ms) ++ " ms)"

def worked_round(go: Bool, slots: List<&1, Slot>, +sc: Scan, +waiting: List<&2, SWD.Judged>, +t: Tally, +fuel: Nat, +now: Nat, +made: U32, +ctx: Ctx) -> Gen:
  match go:
    case True{}:
      Gen{sc, worked_list(slots, width_of(ctx), config_of(ctx), job_steps(), fuel), waiting, without_lines(t), fuel, now, made}
    case False{}:
      Gen{sc, slots, waiting, without_lines(t), fuel, now, made}

def released(r: Released, slots: List<&1, Slot>, +sc: Scan, +busy: U32, +fuel: Nat, +ticked: Nat, +made: U32, +now: Nat, +ctx: Ctx) -> Gen & Out:
  match r:
    case Released{+waiting, +t}:
      +code = Bool.pick(U32, running(t), Bool.pick(U32, ended(sc, busy, waiting), 2, 0), code_of(t))
      +next_fuel = adapted(fuel, Nat.sub(now, ticked), remaining(ctx, now))
      (worked_round(U32.is_zero(code), slots, sc, waiting, with_code(t, code), next_fuel, now, made, ctx),
        Out{lines_of(t), code, progress(t, made, busy, waiting, fuel, Nat.sub(now, ticked))})

def filled_round(f: Filled, +sc: Scan, +sorted: List<&2, SWD.Judged>, +t: Tally, +fuel: Nat, +ticked: Nat, +made: U32, +now: Nat, +ctx: Ctx) -> Gen & Out:
  match f:
    case Filled{slots, +pending, +first, +busy}:
      +frontier = first_pending(pending, ctx_start(ctx), first)
      released(release(sorted, ready(sorted, frontier, ctx_start(ctx)) && running(t), frontier, with_scanned(t, frontier), ctx),
        slots, with_pending(sc, pending), busy, fuel, ticked, made, now, ctx)

def harvested(h: Harvested, +sc: Scan, +waiting: List<&2, SWD.Judged>, +t: Tally, +fuel: Nat, +ticked: Nat, +made: U32, +now: Nat, +ctx: Ctx) -> Gen & Out:
  match h:
    case Harvested{slots, +done}:
      +next = refill(sc, criteria_of(ctx))
      filled_round(fill(slots, pending_of(next), windows_of(config_of(ctx)), ctx_start(ctx), covered(next, ctx), 0, Nil{}), next,
        SO.merged(~SWD.Judged, ~judged_seed, done, waiting, ctx_start(ctx)), t, fuel, ticked, (made + U32.from_nat(List.length(&2, SWD.Judged, done)) : U32), now, ctx)

def time_stop(late: Bool, g: Gen, +now: Nat, +ctx: Ctx) -> Gen & Out:
  match late:
    case True{}:
      match g:
        case Gen{+sc, slots, +waiting, +t, +fuel, +ticked, +made}:
          (Gen{sc, slots, waiting, with_code(t, 3), fuel, ticked, made}, Out{Nil{}, 3, ""})
    case False{}:
      match g:
        case Gen{+sc, slots, +waiting, +t, +fuel, +ticked, +made}:
          harvested(harvest(slots, Nil{}, Nil{}), sc, waiting, t, fuel, ticked, made, now, ctx)

def time_ms_of(+ctx: Ctx) -> Nat:
  match ctx:
    case Ctx{_, _, _, +time_ms, _, _, _, _}:
      time_ms

# One round: stop at the time limit (dropping the work in flight), else harvest, refill, release in scan order, and
# (still running) advance every slot.
def round(g: Gen, +now: Nat, +ctx: Ctx) -> Gen & Out:
  time_stop(Nat.is_ge(elapsed(ctx, now), time_ms_of(ctx)), g, now, ctx)

def print_hits(+json: Bool, lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+line, rest}:
      do IO<Unit>:
        Bool.pick(IO(Unit), json, IO.pure(Unit, Unit{}), IO.print(line))
        print_hits(json, rest)

def scanned_at(+t: Tally, +code: U32, +total: Nat) -> Nat:
  match t:
    case Tally{_, _, _, +last, _, +scanned}:
      Bool.pick(Nat, U32.is_eq(code, 1), last, Bool.pick(Nat, U32.is_eq(code, 2), total, scanned))

def report(g: Gen, +code: U32, +ctx: Ctx) -> IO(Unit):
  match g ctx:
    case Gen{_, _, _, Tally{+found, +hits, _, +last, _, +scanned}, _, _, +made} Ctx{+start, +total, _, _, +json, CF.Config{+windows, _, _, _}, _, _}:
      +position = RP.position_json(start, scanned_at(Tally{found, hits, Nil{}, last, code, scanned}, code, total), code)
      do IO<Unit>:
        IO.print_err("search: " ++ U32.show(made) ++ " candidate worlds generated")
        IO.print(Bool.pick(String, json,
          "{\"version\":1,\"platform\":\"" ++ SWD.platform_name(windows) ++ "\",\"hits\":[" ++ String.join(hits, ",") ++ "]," ++ position ++ ",\"stopped\":\"" ++ RP.stop_name(code) ++ "\"}",
          "done {" ++ position ++ ",\"hits\":" ++ U32.show(found) ++ ",\"stopped\":\"" ++ RP.stop_name(code) ++ "\"}"))
        RP.exit_status(found)

def json_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{_, _, _, _, +json, _, _, _}:
      json

def rounds(n: Nat, got: Gen & Out, +ctx: Ctx) -> IO(Unit):
  match n:
    case 0n:
      (g, _) = got
      report(g, 3, ctx)
    case 1n+k:
      (g, +out) = got
      match out:
        case Out{+lines, 0, +line}:
          do IO<Unit>:
            print_hits(json_of(ctx), lines)
            IO.print_err(line)
            +now : Nat <- IO.now()
            rounds(k, round(g, now, ctx), ctx)
        case Out{+lines, +code, _}:
          do IO<Unit>:
            print_hits(json_of(ctx), lines)
            report(g, code, ctx)

def round_limit() -> Nat:
  Nat.mul(1000000n, 1000000n)

# world find on generated worlds for a config with parts B-E (spec search-v1.md section 8 output).
def run(+q: A.Query, +config: CF.Config) -> IO(Unit):
  match q:
    case A.Query{+start, +total, +limit, +time_ms, +json, _, _, _}:
      do IO<Unit>:
        +width : U32 <- STH.threads()
        +started : Nat <- IO.now()
        +ctx : Ctx = Ctx{start, total, limit, time_ms, json, config, started, U32.to_nat(width)}
        rounds(round_limit(), round(Gen{Scan{start, total, min_chunk(), Nil{}}, free_slots(U32.to_nat(width)), Nil{}, Tally{0, Nil{}, Nil{}, 0n, 0, 0n}, 1024n, started, 0}, started, ctx), ctx)
