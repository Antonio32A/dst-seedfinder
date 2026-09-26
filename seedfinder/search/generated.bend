import Base
import ../filters/config.bend as Config
import ../filters/world.bend as FilterWorld
import ../worldsim/layout/space.bend as LayoutSpace
import ../gen/job.bend as GenJob
import ../gen/layout.bend as GenLayout
import ../gen/savedata.bend as SaveData
import ../cli/args.bend as Args
import ./report.bend as SearchReport
import ./worlds.bend as SearchWorlds
import ./order.bend as SearchOrder
import ./threads.bend as SearchThreads

# `world find` for configs with parts B-E, on worlds generated in memory: part A picks the candidates chunk by chunk
# (the level-table scan), and only candidates are generated, many at once, one per slot. A round:
# - starts every KK pass the slots asked for as its own computation (GenLayout.solve: the native KK runs on the runtime's IO
#   helper threads while the rounds go on), each sending its positions to the search's channel when done;
# - runs the next CPU stage of every other slot in parallel (storygen, Voronoi, commit, tiles, land, ocean, the
#   filters), on a fork tree split by the stages' estimated cost so the threads get even shares;
# - takes the positions of every pass that finished (a marker sent after them ends the take, so no round waits for a
#   pass), hands them back to their slots, harvests the decided seeds, refills the part-A scan and gives the free slots
#   the next candidates in scan order.
# A seed is decided on its world as `world find --worlds` does (the first entry whose part A and parts B-E hold; a
# seed without a world never matches), and decided seeds are released in scan order, so the hits are those of a
# sequential scan whatever the slot or thread count.

# A slot: free, a seed with a CPU stage to run, waiting for its KK pass, with its pass's positions back, one of the
# oldest seeds rushed this round (after its pass's positions when `back`), asking for a pass (after its CPU work),
# decided, or held out while its CPU work runs. `cost` estimates the next CPU work (ms).
type Slot is Type:
  Free{}
  Cpu{seed: U32, job: GenJob.Job, cost: U32}
  Wait{seed: U32, job: GenJob.Job, cost: U32}
  Back{seed: U32, job: GenJob.Job, ps: List<&2, LayoutSpace.Vec>, cost: U32}
  Rush{seed: U32, job: GenJob.Job, ps: List<&2, LayoutSpace.Vec>, back: Bool}
  Asked{seed: U32, job: GenJob.Job, layout: GenLayout.Layout}
  Decided{seed: U32, verdict: SearchWorlds.Verdict}
  Held{}

type Slots is Type:
  Leaf{slot: Slot}
  Fork{a: Slots, b: Slots}

# Nat.min by one native comparison. Base's Nat.min recurses once per unit (8 bytes of a worker's 2 GB machine stack),
# so scan positions past 2^28 overflow it.
def lesser(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(b, a), b, a)

def greater(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(a, b), b, a)

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

def leaf_of(xs: List<&1, Slot>) -> Slots:
  match xs:
    case Nil{}:
      Leaf{Free{}}
    case Con{x, _}:
      Leaf{x}

def total_of(costs: List<&2, U32>, +acc: U32) -> U32:
  match costs:
    case Nil{}:
      acc
    case Con{+c, rest}:
      total_of(rest, (acc + c : U32))

def weighed(costs: List<&2, U32>, +half: U32, +acc: U32, +k: Nat) -> Nat:
  match costs:
    case Nil{}:
      k
    case Con{+c, rest}:
      Bool.pick(Nat, (acc >= half : U32), k, weighed(rest, half, (acc + c : U32), Nat.add(k, 1n)))

# Where to split slots of these costs: where the cost reaches half, keeping a slot on each side (0 for one slot).
def cut(+costs: List<&2, U32>) -> Nat:
  +n = List.length(&2, U32, costs)
  Bool.pick(Nat, Nat.is_lt(n, 2n), 0n, lesser(greater(weighed(costs, (total_of(costs, 0) >> 1n : U32), 0, 0n), 1n), Nat.sub(n, 1n)))

def halved(xs: List<&1, Slot>, +costs: List<&2, U32>) -> Split:
  split_loop(cut(costs), xs, Nil{})

# The tree of the slots front ++ back (costs cf and cb), each side split again by cost, down to one slot per leaf.
def grown(+d: Nat, sp: Split, +cf: List<&2, U32>, +cb: List<&2, U32>) -> Slots:
  match d:
    case 0n:
      match sp:
        case Split{_, back}:
          leaf_of(back)
    case 1n+p:
      match sp:
        case Split{front, back}:
          match front:
            case Nil{}:
              leaf_of(back)
            case Con{x, rest}:
              +kf = cut(cf)
              +kb = cut(cb)
              Fork{grown(p, halved(x <> rest, cf), List.take(&2, U32, cf, kf), List.drop(&2, U32, cf, kf)),
                grown(p, halved(back, cb), List.take(&2, U32, cb, kb), List.drop(&2, U32, cb, kb))}

# The slots in a tree whose two halves at every fork carry about the same estimated work.
def tree_of(xs: List<&1, Slot>, +costs: List<&2, U32>) -> Slots:
  +k = cut(costs)
  grown(List.length(&2, U32, costs), halved(xs, costs), List.take(&2, U32, costs, k), List.drop(&2, U32, costs, k))

def flat(s: Slots) -> List<&1, Slot>:
  match s:
    case Leaf{slot}:
      [slot]
    case Fork{a, b}:
      List.append(&1, Slot, flat(a), flat(b))

# A KK pass a slot asked for (tag: the slot's index).
type Request is Data:
  Request{tag: U32, layout: GenLayout.Layout}

# What the search's channel carries: a finished pass's positions, or the marker that ends a take.
type Note is Data:
  Laid{tag: U32, ps: List<&2, LayoutSpace.Vec>}
  Mark{}

# The per-run constants: scan start and length, hit limit, time limit, output mode, config, the start time, the slots
# (seeds in flight), the KK engine and the channel the passes answer on.
type Ctx is Data:
  Ctx{start: U32, total: Nat, limit: U32, time_ms: Nat, json: Bool, config: Config.Config, started: Nat, slots: U32, native: Bool, laid: Chan(Note)}

def config_of(+ctx: Ctx) -> Config.Config:
  match ctx:
    case Ctx{_, _, _, _, _, +config, _, _, _, _}:
      config

def windows_of(+config: Config.Config) -> Bool:
  match config:
    case Config.Config{+windows, _, _, _, _}:
      windows

def ctx_start(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{+start, _, _, _, _, _, _, _, _, _}:
      start

def json_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{_, _, _, _, +json, _, _, _, _, _}:
      json

def time_ms_of(+ctx: Ctx) -> Nat:
  match ctx:
    case Ctx{_, _, _, +time_ms, _, _, _, _, _, _}:
      time_ms

def elapsed(+ctx: Ctx, +now: Nat) -> Nat:
  match ctx:
    case Ctx{_, _, _, _, _, _, +started, _, _, _}:
      Nat.sub(now, started)

def criteria_of(+ctx: Ctx) -> List<&2, Config.Criteria>:
  match ctx:
    case Ctx{_, _, _, _, _, Config.Config{_, _, _, _, +scanned}, _, _, _, _}:
      scanned

def slots_of(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{_, _, _, _, _, _, _, +slots, _, _}:
      slots

def laid_of(+ctx: Ctx) -> Chan(Note):
  match ctx:
    case Ctx{_, _, _, _, _, _, _, _, _, +laid}:
      laid

def world_verdict(job: GenJob.Job, +config: Config.Config, +seed: U32) -> SearchWorlds.Verdict:
  match job:
    case GenJob.JWorld{_, _, final}:
      SearchWorlds.world_verdict(Done{FilterWorld.Generated{SaveData.world(seed, windows_of(config), final), 0}}, config, seed)
    case _:
      SearchWorlds.Miss{}

# The estimated ms of a job's next CPU stage (see GenJob.Job: 0 start, 3 commit, 4 tiles, 5 land, 6 ocean; `gen --times`).
def stage_cost(+stage: U32) -> U32:
  match stage:
    case 4:
      24
    case 5:
      50
    case 6:
      100
    case _:
      8

# The estimated ms of resuming after a KK pass: Voronoi and the story up to pass 2 after pass 1, Voronoi after pass 2.
def pass_cost(+l: GenLayout.Layout) -> U32:
  match l:
    case GenLayout.Layout{+first, _, _, _, _}:
      Bool.pick(U32, U32.is_zero(first), 8, 5)

def asked(got: GenJob.Job & Maybe<&2, GenLayout.Layout>, +seed: U32, +stage: U32) -> Slot:
  (job, pass) = got
  match pass:
    case Some{+l}:
      Asked{seed, job, l}
    case None{}:
      Cpu{seed, job, stage_cost(stage)}

def settled_at(settled: Bool, job: GenJob.Job, +stage: U32, +config: Config.Config, +seed: U32) -> Slot:
  match settled:
    case True{}:
      Decided{seed, world_verdict(job, config, seed)}
    case False{}:
      asked(GenJob.layout(job), seed, stage)

# Where a job stands after its CPU work: decided, asking for a KK pass, or its next stage for the next round.
def parked(got: GenJob.Job & GenJob.Where, +config: Config.Config, +seed: U32) -> Slot:
  (job, +at) = got
  match at:
    case GenJob.Where{+stage, _}:
      settled_at(GenJob.settled(stage), job, stage, config, seed)

def moved_on(got: GenJob.Job & Maybe<&2, GenLayout.Layout>) -> GenJob.Job:
  (job, pass) = got
  match pass:
    case Some{_}:
      job
    case None{}:
      GenJob.step(job)

def moved_at(settled: Bool, job: GenJob.Job) -> GenJob.Job:
  match settled:
    case True{}:
      job
    case False{}:
      moved_on(GenJob.layout(job))

# A stage transition; decided jobs and jobs at a KK pass stay.
def moved(got: GenJob.Job & GenJob.Where) -> GenJob.Job:
  (job, +at) = got
  match at:
    case GenJob.Where{+stage, _}:
      moved_at(GenJob.settled(stage), job)

def rushed(budget: Nat, job: GenJob.Job, +config: Config.Config, +seed: U32) -> Slot:
  match budget:
    case 0n:
      parked(GenJob.stage(job), config, seed)
    case 1n+b:
      rushed(b, moved(GenJob.stage(job)), config, seed)

def resumed(back: Bool, job: GenJob.Job, +ps: List<&2, LayoutSpace.Vec>) -> GenJob.Job:
  match back:
    case True{}:
      GenJob.laid(job, ps)
    case False{}:
      job

# Stage transitions of a rushed seed: to its next KK pass or its verdict (six CPU stages at most in between).
def rush_steps() -> Nat:
  8n

# How many of the oldest seeds are rushed (one per thread): the ones that hold back the release of later hits.
def rushed_seeds(+ctx: Ctx) -> Nat:
  U32.to_nat((slots_of(ctx) >> 3n : U32))

# The estimated ms a rushed seed adds to its stage (the stages up to its next pass).
def rush_cost() -> U32:
  180

# One stage transition per slot and round (or the resume after a pass), so the work of a round splits evenly; a
# rushed seed runs on to its next pass or verdict.
def work(slot: Slot, +config: Config.Config) -> Slot:
  match slot:
    case Cpu{+seed, job, _}:
      parked(GenJob.stage(GenJob.step(job)), config, seed)
    case Back{+seed, job, +ps, _}:
      parked(GenJob.stage(GenJob.laid(job, ps)), config, seed)
    case Rush{+seed, job, +ps, back}:
      rushed(rush_steps(), resumed(back, job, ps), config, seed)
    case other:
      other

# The CPU work of every slot, both halves of each fork in parallel.
def worked_all(s: Slots, +config: Config.Config) -> Slots:
  match s:
    case Leaf{slot}:
      Leaf{work(slot, config)}
    case Fork{a, b}:
      x y = worked_all(a, config) worked_all(b, config)
      Fork{x, y}

# The slots with CPU work taken out (in order) and held, and their costs.
type Gathered is Type:
  Gathered{slots: List<&1, Slot>, todo: List<&1, Slot>, costs: List<&2, U32>}

def as_todo(rush: Bool, slot: Slot) -> Slot:
  match rush:
    case True{}:
      match slot:
        case Cpu{+seed, job, _}:
          Rush{seed, job, Nil{}, False{}}
        case Back{+seed, job, +ps, _}:
          Rush{seed, job, ps, True{}}
        case other:
          other
    case False{}:
      slot

# Takes the slots with CPU work out; those at scan positions up to `rush` (the oldest seeds) are rushed.
def gather(xs: List<&1, Slot>, acc: List<&1, Slot>, todo: List<&1, Slot>, +costs: List<&2, U32>, +start: U32, +rush: Nat) -> Gathered:
  match xs:
    case Nil{}:
      Gathered{List.reverse(&1, Slot, acc), List.reverse(&1, Slot, todo), List.reverse(&2, U32, costs)}
    case Con{x, rest}:
      match x:
        case Cpu{+seed, job, +cost}:
          +r = Nat.is_le(SearchOrder.position(seed, start), rush)
          gather(rest, Held{} <> acc, as_todo(r, Cpu{seed, job, cost}) <> todo, Bool.pick(U32, r, (cost + rush_cost() : U32), cost) <> costs, start, rush)
        case Back{+seed, job, +ps, +cost}:
          +r = Nat.is_le(SearchOrder.position(seed, start), rush)
          gather(rest, Held{} <> acc, as_todo(r, Back{seed, job, ps, cost}) <> todo, Bool.pick(U32, r, (cost + rush_cost() : U32), cost) <> costs, start, rush)
        case other:
          gather(rest, other <> acc, todo, costs, start, rush)

# The slots after their CPU work, and the passes they asked for (tagged with the slot index), in slot order.
type Merged is Type:
  Merged{slots: List<&1, Slot>, asked: List<&2, Request>}

def merge(xs: List<&1, Slot>, done: List<&1, Slot>, +tag: U32, acc: List<&1, Slot>, +asked: List<&2, Request>) -> Merged:
  match xs:
    case Nil{}:
      Merged{List.reverse(&1, Slot, acc), List.reverse(&2, Request, asked)}
    case Con{x, rest}:
      match x:
        case Held{}:
          match done:
            case Nil{}:
              merge(rest, Nil{}, (tag + 1 : U32), Free{} <> acc, asked)
            case Con{w, more}:
              match w:
                case Asked{+seed, job, +l}:
                  merge(rest, more, (tag + 1 : U32), Wait{seed, job, pass_cost(l)} <> acc, Request{tag, l} <> asked)
                case other:
                  merge(rest, more, (tag + 1 : U32), other <> acc, asked)
        case other:
          merge(rest, done, (tag + 1 : U32), other <> acc, asked)

def worked_slots(g: Gathered, +config: Config.Config) -> Merged:
  match g:
    case Gathered{slots, todo, +costs}:
      merge(slots, flat(worked_all(tree_of(todo, costs), config)), 0, Nil{}, Nil{})


def tag_of(+n: Note) -> U32:
  match n:
    case Laid{+tag, _}:
      tag
    case Mark{}:
      4294967295

def by_tag(+sorted: List<&2, Note>, +n: Note) -> List<&2, Note>:
  match sorted:
    case Nil{}:
      [n]
    case Con{+head, +rest}:
      Bool.pick(List<&2, Note>, (tag_of(n) < tag_of(head) : U32), n <> head <> rest, head <> by_tag(rest, n))

def sorted_laid(laid: List<&2, Note>, +acc: List<&2, Note>) -> List<&2, Note>:
  match laid:
    case Nil{}:
      acc
    case Con{+n, rest}:
      sorted_laid(rest, by_tag(acc, n))

def back_if(hit: Bool, x: Slot, +ps: List<&2, LayoutSpace.Vec>) -> Slot:
  match hit:
    case True{}:
      match x:
        case Wait{+seed, job, +cost}:
          Back{seed, job, ps, cost}
        case other:
          other
    case False{}:
      x

def laid_ps(+n: Note) -> List<&2, LayoutSpace.Vec>:
  match n:
    case Laid{_, +ps}:
      ps
    case Mark{}:
      Nil{}

# The finished passes (sorted by tag) handed back to their slots.
def deliver(xs: List<&1, Slot>, +laid: List<&2, Note>, +tag: U32, acc: List<&1, Slot>) -> List<&1, Slot>:
  match xs:
    case Nil{}:
      List.reverse(&1, Slot, acc)
    case Con{x, rest}:
      match laid:
        case Nil{}:
          deliver(rest, Nil{}, (tag + 1 : U32), x <> acc)
        case Con{+n, +more}:
          +hit = U32.is_eq(tag_of(n), tag)
          deliver(rest, Bool.pick(List<&2, Note>, hit, more, laid), (tag + 1 : U32), back_if(hit, x, laid_ps(n)) <> acc)
# The decided slots taken out (newest first), the others kept in order.
type Harvested is Type:
  Harvested{slots: List<&1, Slot>, done: List<&2, SearchWorlds.Judged>}

def harvest(xs: List<&1, Slot>, +done: List<&2, SearchWorlds.Judged>, acc: List<&1, Slot>) -> Harvested:
  match xs:
    case Nil{}:
      Harvested{List.reverse(&1, Slot, acc), done}
    case Con{x, rest}:
      match x:
        case Decided{+seed, +v}:
          harvest(rest, SearchWorlds.Judged{seed, v} <> done, Free{} <> acc)
        case other:
          harvest(rest, done, other <> acc)


# The slots after giving free ones the next pending candidates (at most `room`), the candidates left, the smallest
# scan position of a busy slot (`first` when none), the number of busy slots and of slots with CPU work.
type Filled is Type:
  Filled{slots: List<&1, Slot>, pending: List<&2, U32>, first: Nat, busy: U32, ready: U32, positions: List<&2, Nat>}

def fill(xs: List<&1, Slot>, +pending: List<&2, U32>, +windows: Bool, +start: U32, +first: Nat, +busy: U32, +ready: U32, +at: List<&2, Nat>, acc: List<&1, Slot>) -> Filled:
  match xs:
    case Nil{}:
      Filled{List.reverse(&1, Slot, acc), pending, first, busy, ready, at}
    case Con{x, rest}:
      match x:
        case Free{}:
          match pending:
            case Con{+seed, +more}:
              +p = SearchOrder.position(seed, start)
              fill(rest, more, windows, start, lesser(first, p), (busy + 1 : U32), (ready + 1 : U32), p <> at, Cpu{seed, GenJob.start(seed, windows), stage_cost(0)} <> acc)
            case Nil{}:
              fill(rest, Nil{}, windows, start, first, busy, ready, at, Free{} <> acc)
        case Cpu{+seed, job, +cost}:
          +p = SearchOrder.position(seed, start)
          fill(rest, pending, windows, start, lesser(first, p), (busy + 1 : U32), (ready + 1 : U32), p <> at, Cpu{seed, job, cost} <> acc)
        case Wait{+seed, job, +cost}:
          +p = SearchOrder.position(seed, start)
          fill(rest, pending, windows, start, lesser(first, p), (busy + 1 : U32), ready, p <> at, Wait{seed, job, cost} <> acc)
        case Back{+seed, job, +ps, +cost}:
          +p = SearchOrder.position(seed, start)
          fill(rest, pending, windows, start, lesser(first, p), (busy + 1 : U32), (ready + 1 : U32), p <> at, Back{seed, job, ps, cost} <> acc)
        case other:
          fill(rest, pending, windows, start, first, busy, ready, at, other <> acc)

def inserted(+sorted: List<&2, Nat>, +x: Nat) -> List<&2, Nat>:
  match sorted:
    case Nil{}:
      [x]
    case Con{+h, +rest}:
      Bool.pick(List<&2, Nat>, Nat.is_le(x, h), x <> h <> rest, h <> inserted(rest, x))

def sorted_nats(xs: List<&2, Nat>, +acc: List<&2, Nat>) -> List<&2, Nat>:
  match xs:
    case Nil{}:
      acc
    case Con{+x, rest}:
      sorted_nats(rest, inserted(acc, x))

# The scan position of the n-th oldest busy seed (0 when none): the seeds up to it are rushed.
def rush_at(+positions: List<&2, Nat>, +n: Nat) -> Nat:
  +sorted = sorted_nats(positions, Nil{})
  Maybe.default(&2, Nat, List.get(&2, Nat, sorted, Nat.sub(lesser(n, List.length(&2, Nat, sorted)), 1n)), 0n)

def judged_seed(+j: SearchWorlds.Judged) -> U32:
  match j:
    case SearchWorlds.Judged{+seed, _}:
      seed

def judged_position(+j: SearchWorlds.Judged, +start: U32) -> Nat:
  SearchOrder.position(judged_seed(j), start)

# Hits found (JSON objects of the job result), hit lines to print, the scan position after the last hit, the stop
# code (0 running, 1 limit, 2 end, 3 time) and the decided prefix of the scan.
type Tally is Data:
  Tally{found: U32, hits: List<&2, String>, lines: List<&2, String>, last: Nat, code: U32, scanned: Nat}

def tallied(+t: Tally, +seed: U32, +v: SearchWorlds.Verdict, +ctx: Ctx) -> Tally:
  match t ctx:
    case Tally{+found, +hits, +lines, +last, _, +scanned} Ctx{+start, _, +limit, _, _, _, _, _, _, _}:
      +count = (found + Bool.to_u32(SearchWorlds.is_hit(v)) : U32)
      Tally{count, List.append(&2, String, hits, SearchWorlds.hit_object(seed, v)), List.append(&2, String, lines, SearchWorlds.hit_line(seed, v)),
        Bool.pick(Nat, SearchWorlds.is_hit(v), Nat.add(SearchOrder.position(seed, start), 1n), last), Bool.pick(U32, (count >= limit : U32), 1, 0), scanned}

def ready(+sorted: List<&2, SearchWorlds.Judged>, +frontier: Nat, +start: U32) -> Bool:
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
  Released{waiting: List<&2, SearchWorlds.Judged>, tally: Tally}

# Decides the waiting candidates before the frontier (the first undecided scan position), in scan order, up to the
# hit limit.
def release(sorted: List<&2, SearchWorlds.Judged>, go: Bool, +frontier: Nat, +t: Tally, +ctx: Ctx) -> Released:
  match sorted:
    case Nil{}:
      Released{Nil{}, t}
    case Con{SearchWorlds.Judged{+seed, +v}, +rest}:
      match go:
        case False{}:
          Released{SearchWorlds.Judged{seed, v} <> rest, t}
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

def scanned_chunk(+sc: Scan, +criteria: List<&2, Config.Criteria>, +wanted: Nat) -> Scan:
  match sc:
    case Scan{+next, +left, +size, +pending}:
      +len = lesser(size, left)
      +found = SearchWorlds.candidates(SearchWorlds.chunk_candidates(len, next, criteria))
      Scan{(next + U32.from_nat(len) : U32), Nat.sub(left, len), Bool.pick(Nat, Nat.is_lt(List.length(&2, U32, found), wanted), lesser(Nat.mul(size, 2n), max_chunk()), size),
        List.append(&2, U32, pending, found)}

def short(+sc: Scan, +budget: Nat, +wanted: Nat) -> Bool:
  match sc:
    case Scan{_, +left, _, +pending}:
      Nat.is_lt(List.length(&2, U32, pending), wanted) && Nat.is_gt(left, 0n) && Nat.is_gt(budget, 0n)

def chunk_of(+sc: Scan) -> Nat:
  match sc:
    case Scan{_, _, +size, _}:
      size

# Scans part A chunk by chunk while candidates are short of `wanted`, up to round_seeds() seeds.
def refilled(n: Nat, go: Bool, +sc: Scan, +budget: Nat, +criteria: List<&2, Config.Criteria>, +wanted: Nat) -> Scan:
  match n:
    case 0n:
      sc
    case 1n+p:
      match go:
        case False{}:
          sc
        case True{}:
          +next = scanned_chunk(sc, criteria, wanted)
          +rest = Nat.sub(budget, chunk_of(sc))
          refilled(p, short(next, rest, wanted), next, rest, criteria, wanted)

def refill(+sc: Scan, +criteria: List<&2, Config.Criteria>, +wanted: Nat) -> Scan:
  refilled(64n, short(sc, round_seeds(), wanted), sc, round_seeds(), criteria, wanted)

def covered(+sc: Scan, +ctx: Ctx) -> Nat:
  match sc ctx:
    case Scan{_, +left, _, _} Ctx{_, +total, _, _, _, _, _, _, _, _}:
      Nat.sub(total, left)

def first_pending(+pending: List<&2, U32>, +start: U32, +otherwise: Nat) -> Nat:
  match pending:
    case Nil{}:
      otherwise
    case Con{+seed, _}:
      lesser(SearchOrder.position(seed, start), otherwise)

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
# Totals for the closing line: rounds, ms in the CPU phases, ms taking finished passes, KK passes finished, and when
# the progress line was last printed.
type Stats is Data:
  Stats{rounds: Nat, cpu: Nat, take: Nat, passes: Nat, shown: Nat}

def timed(+s: Stats, +t0: Nat, +t1: Nat, +t2: Nat, +passes: Nat) -> Stats:
  match s:
    case Stats{+rounds, +cpu, +take, +tp, +shown}:
      Stats{Nat.add(rounds, 1n), Nat.add(cpu, Nat.sub(t1, t0)), Nat.add(take, Nat.sub(t2, t1)), Nat.add(tp, passes), shown}

def shown_at(+s: Stats, +now: Nat) -> Stats:
  match s:
    case Stats{+rounds, +cpu, +take, +passes, _}:
      Stats{rounds, cpu, take, passes, now}

def due(+s: Stats, +now: Nat) -> Bool:
  match s:
    case Stats{_, _, _, _, +shown}:
      Nat.is_ge(Nat.sub(now, shown), 1000n)

# The search's data between rounds: the part-A scan, the passes to start, the decided candidates waiting for an
# earlier one, the tally, how many candidates were decided, the busy slots, the passes in flight and the stats.
type Book is Data:
  Book{scan: Scan, queue: List<&2, Request>, waiting: List<&2, SearchWorlds.Judged>, tally: Tally, made: U32, busy: U32, flying: U32, stats: Stats}

def book_scan(+b: Book) -> Scan:
  match b:
    case Book{+sc, _, _, _, _, _, _, _}:
      sc

def book_queue(+b: Book) -> List<&2, Request>:
  match b:
    case Book{_, +queue, _, _, _, _, _, _}:
      queue

def book_waiting(+b: Book) -> List<&2, SearchWorlds.Judged>:
  match b:
    case Book{_, _, +waiting, _, _, _, _, _}:
      waiting

def book_tally(+b: Book) -> Tally:
  match b:
    case Book{_, _, _, +t, _, _, _, _}:
      t

def book_flying(+b: Book) -> U32:
  match b:
    case Book{_, _, _, _, _, _, +flying, _}:
      flying

def book_stats(+b: Book) -> Stats:
  match b:
    case Book{_, _, _, _, _, _, _, +s}:
      s

def with_stats(+b: Book, +s: Stats) -> Book:
  match b:
    case Book{+sc, +queue, +waiting, +t, +made, +busy, +flying, _}:
      Book{sc, queue, waiting, t, made, busy, flying, s}

def with_tally(+b: Book, +waiting: List<&2, SearchWorlds.Judged>, +t: Tally) -> Book:
  match b:
    case Book{+sc, +queue, _, _, +made, +busy, +flying, +s}:
      Book{sc, queue, waiting, t, made, busy, flying, s}

# The book after a round's take: the passes asked for (to start next round) and the passes in flight.
def with_flow(+b: Book, +asked: List<&2, Request>, +laid: Nat, +s: Stats) -> Book:
  match b:
    case Book{+sc, _, +waiting, +t, +made, +busy, +flying, _}:
      +more = U32.from_nat(List.length(&2, Request, asked))
      Book{sc, asked, waiting, without_lines(t), made, busy, (flying + more - U32.from_nat(laid) : U32), s}

def pending_of(+sc: Scan) -> List<&2, U32>:
  match sc:
    case Scan{_, _, _, +pending}:
      pending

def with_pending(+sc: Scan, +pending: List<&2, U32>) -> Scan:
  match sc:
    case Scan{+next, +left, +size, _}:
      Scan{next, left, size, pending}

# The book after a harvest: the refilled scan and the decided candidates merged into the waiting ones.
def with_decided(+b: Book, +sc: Scan, +done: List<&2, SearchWorlds.Judged>, +ctx: Ctx) -> Book:
  match b:
    case Book{_, +queue, +waiting, +t, +made, +busy, +flying, +s}:
      Book{sc, queue, SearchOrder.merged(~SearchWorlds.Judged, ~judged_seed, done, waiting, ctx_start(ctx)), t,
        (made + U32.from_nat(List.length(&2, SearchWorlds.Judged, done)) : U32), busy, flying, s}

def with_filled(+b: Book, +pending: List<&2, U32>, +busy: U32) -> Book:
  match b:
    case Book{+sc, +queue, +waiting, +t, +made, _, +flying, +s}:
      Book{with_pending(sc, pending), queue, waiting, t, made, busy, flying, s}

def ended(+b: Book, +waiting: List<&2, SearchWorlds.Judged>) -> Bool:
  match b:
    case Book{Scan{_, +left, _, +pending}, _, _, _, _, +busy, _, _}:
      Nat.is_eq(left, 0n) && List.is_empty(&2, U32, pending) && U32.is_zero(busy) && List.is_empty(&2, SearchWorlds.Judged, waiting)

# Whether the next round has nothing to do but wait for passes in flight: no slot with CPU work, no pass to start,
# and no free slot the scan could still fill.
def idle(+b: Book, +ready: U32, +ctx: Ctx) -> Bool:
  match b:
    case Book{Scan{_, +left, _, +pending}, +queue, _, _, _, +busy, +flying, _}:
      +scanning = U32.is_ne(busy, slots_of(ctx)) && Nat.is_gt(left, 0n)
      U32.is_zero(ready) && List.is_empty(&2, Request, queue) && U32.is_ne(flying, 0) && Bool.not(scanning)

# The search between rounds: the book and the slots (index = request tag).
type Host is Type:
  Host{book: Book, slots: List<&1, Slot>}

# What a round hands to IO: hit lines to print, the stop code and a progress line ("" for none).
type Out is Data:
  Out{lines: List<&2, String>, code: U32, progress: String}

# The loop's state: the host side, whether the next round only waits for passes, up to which scan position its seeds
# are rushed, and the round's output.
type State is Type:
  State{host: Host, idle: Bool, rush: Nat, out: Out}

def progress(+b: Book, +levels: Nat) -> String:
  match b:
    case Book{_, _, +waiting, Tally{+found, _, _, _, _, +scanned}, +made, +busy, +flying, Stats{+rounds, +cpu, +take, +passes, _}}:
      "search: scanned " ++ Nat.show(scanned) ++ ", levels " ++ Nat.show(levels) ++ ", worlds " ++ U32.show(made) ++ ", generating " ++ U32.show(busy)
        ++ " (kk " ++ U32.show(flying) ++ ", passes " ++ Nat.show(passes) ++ "), waiting "
        ++ Nat.show(List.length(&2, SearchWorlds.Judged, waiting)) ++ ", hits " ++ U32.show(found) ++ " (rounds " ++ Nat.show(rounds)
        ++ ", cpu " ++ Nat.show(cpu) ++ " ms, take " ++ Nat.show(take) ++ " ms)"

def worked_round(go: Bool, slots: List<&1, Slot>, +b: Book, +ready: U32, +rush: Nat, +now: Nat, +ctx: Ctx) -> State:
  match go:
    case True{}:
      +show = due(book_stats(b), now)
      +kept = with_stats(b, Bool.pick(Stats, show, shown_at(book_stats(b), now), book_stats(b)))
      State{Host{kept, slots}, idle(kept, ready, ctx), rush, Out{lines_of(book_tally(b)), 0, Bool.pick(String, show, progress(kept, covered(book_scan(kept), ctx)), "")}}
    case False{}:
      State{Host{b, slots}, False{}, 0n, Out{lines_of(book_tally(b)), code_of(book_tally(b)), ""}}

def released_round(r: Released, slots: List<&1, Slot>, +b: Book, +ready: U32, +rush: Nat, +now: Nat, +ctx: Ctx) -> State:
  match r:
    case Released{+waiting, +t}:
      +code = Bool.pick(U32, running(t), Bool.pick(U32, ended(b, waiting), 2, 0), code_of(t))
      worked_round(U32.is_zero(code), slots, with_tally(b, waiting, with_code(t, code)), ready, rush, now, ctx)

def filled_round(f: Filled, +back: List<&2, U32>, +b: Book, +now: Nat, +ctx: Ctx) -> State:
  match f:
    case Filled{slots, +front, +first, +busy, +cpu, +positions}:
      +pending = List.append(&2, U32, front, back)
      +frontier = first_pending(pending, ctx_start(ctx), first)
      +sorted = book_waiting(b)
      +t = book_tally(b)
      +rush = rush_at(positions, rushed_seeds(ctx))
      released_round(release(sorted, ready(sorted, frontier, ctx_start(ctx)) && running(t), frontier, with_scanned(t, frontier), ctx),
        slots, with_filled(b, pending, busy), cpu, rush, now, ctx)

def ramp_ms() -> Nat:
  8000n

# How many seeds may be in flight: a quarter of the slots at the start, all of them after ramp_ms(), so the first
# seeds (and hits) come out sooner while the search fills up.
def allowed(+ctx: Ctx, +now: Nat) -> Nat:
  +slots = U32.to_nat(slots_of(ctx))
  lesser(slots, Nat.add(Nat.div(slots, 4n), Nat.div(Nat.mul(elapsed(ctx, now), slots), ramp_ms())))

def book_busy(+b: Book) -> U32:
  match b:
    case Book{_, _, _, _, _, +busy, _, _}:
      busy

def harvested(h: Harvested, +b: Book, +now: Nat, +ctx: Ctx) -> State:
  match h:
    case Harvested{slots, +done}:
      +cap = U32.to_nat(slots_of(ctx))
      +room = Nat.sub(allowed(ctx, now), Nat.sub(U32.to_nat(book_busy(b)), List.length(&2, SearchWorlds.Judged, done)))
      +next = refill(book_scan(b), criteria_of(ctx), cap)
      +pending = pending_of(next)
      filled_round(fill(slots, List.take(&2, U32, pending, room), windows_of(config_of(ctx)), ctx_start(ctx), covered(next, ctx), 0, 0, Nil{}, Nil{}),
        List.drop(&2, U32, pending, room), with_decided(b, next, done, ctx), now, ctx)

def late_or(late: Bool, +b: Book, slots: List<&1, Slot>, +laid: List<&2, Note>, +now: Nat, +ctx: Ctx) -> State:
  match late:
    case True{}:
      State{Host{with_tally(b, book_waiting(b), with_code(book_tally(b), 3)), slots}, False{}, 0n, Out{Nil{}, 3, ""}}
    case False{}:
      harvested(harvest(deliver(slots, sorted_laid(laid, Nil{}), 0, Nil{}), Nil{}, Nil{}), b, now, ctx)

# The host half of a round (CPU phase from t0 to t1, take until t2): stop at the time limit (dropping the work in
# flight), else hand the finished passes back, harvest, refill, fill and release in scan order.
def hosted(m: Merged, +b: Book, +laid: List<&2, Note>, +t0: Nat, +t1: Nat, +t2: Nat, +ctx: Ctx) -> State:
  match m:
    case Merged{slots, +asked}:
      +n = List.length(&2, Note, laid)
      +kept = with_flow(b, asked, n, timed(book_stats(b), t0, t1, t2, n))
      late_or(Nat.is_ge(elapsed(ctx, t2), time_ms_of(ctx)), kept, slots, laid, t2, ctx)

def native_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{_, _, _, _, _, _, _, _, +native, _}:
      native

# A pass as its own computation: its positions go to the search's channel.
def solved(+tag: U32, +l: GenLayout.Layout, +ctx: Ctx) -> IO(Bool):
  do IO<Bool>:
    +ps : List<&2, LayoutSpace.Vec> <- GenLayout.solve(native_of(ctx), l)
    Chan.send(Note, laid_of(ctx), Laid{tag, ps})

def launched(reqs: List<&2, Request>, +ctx: Ctx) -> IO(Unit):
  match reqs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Request{+tag, +l}, +rest}:
      do IO<Unit>:
        IO.spawn(Bool, solved(tag, l, ctx))
        launched(rest, ctx)

# The finished passes in the channel up to the marker.
def drained(n: Nat, got: Maybe<&1, Note>, +ch: Chan(Note), +acc: List<&2, Note>) -> IO(List<&2, Note>):
  match n:
    case 0n:
      IO.pure(List<&2, Note>, acc)
    case 1n+k:
      match got:
        case Some{Laid{+tag, +ps}}:
          do IO<List<&2, Note>>:
            next : Maybe<&1, Note> <- Chan.recv(Note, ch)
            drained(k, next, ch, Laid{tag, ps} <> acc)
        case _:
          IO.pure(List<&2, Note>, acc)

def idle_ms() -> U32:
  2

# Every pass finished by now: a yield lets the finished computations send, then a marker sent after them ends the
# take (an idle round sleeps idle_ms() first).
def taken(+idle: Bool, +flying: U32, +ctx: Ctx) -> IO(List<&2, Note>):
  +ch = laid_of(ctx)
  do IO<List<&2, Note>>:
    IO.sleep(Bool.pick(U32, idle, idle_ms(), 0))
    sent : Bool <- Chan.send(Note, ch, Mark{})
    first : Maybe<&1, Note> <- Chan.recv(Note, ch)
    drained(U32.to_nat((flying + 2 : U32)), first, ch, Nil{})

def print_hits(+json: Bool, lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+line, rest}:
      do IO<Unit>:
        Bool.pick(IO(Unit), json, IO.pure(Unit, Unit{}), IO.print(line))
        print_hits(json, rest)

def print_progress(+line: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(line), IO.pure(Unit, Unit{}), IO.print_err(line))

def scanned_at(+t: Tally, +code: U32, +total: Nat) -> Nat:
  match t:
    case Tally{_, _, _, +last, _, +scanned}:
      Bool.pick(Nat, U32.is_eq(code, 1), last, Bool.pick(Nat, U32.is_eq(code, 2), total, scanned))

def stats_line(+s: Stats) -> String:
  match s:
    case Stats{+rounds, +cpu, +take, +passes, _}:
      "search: " ++ Nat.show(rounds) ++ " rounds, cpu " ++ Nat.show(cpu) ++ " ms, take " ++ Nat.show(take) ++ " ms, "
        ++ Nat.show(passes) ++ " KK passes"

def report(host: Host, +code: U32, +ctx: Ctx) -> IO(Unit):
  match host ctx:
    case Host{Book{_, _, _, Tally{+found, +hits, _, +last, _, +scanned}, +made, _, _, +stats}, _} Ctx{+start, +total, _, _, +json, Config.Config{+windows, _, _, _, _}, _, _, _, _}:
      +position = SearchReport.position_json(start, scanned_at(Tally{found, hits, Nil{}, last, code, scanned}, code, total), code)
      do IO<Unit>:
        IO.print_err("search: " ++ U32.show(made) ++ " candidate worlds generated")
        IO.print_err(stats_line(stats))
        IO.print(Bool.pick(String, json,
          "{\"version\":1,\"platform\":\"" ++ SearchWorlds.platform_name(windows) ++ "\",\"hits\":[" ++ String.join(hits, ",") ++ "]," ++ position ++ ",\"stopped\":\"" ++ SearchReport.stop_name(code) ++ "\"}",
          "done {" ++ position ++ ",\"hits\":" ++ U32.show(found) ++ ",\"stopped\":\"" ++ SearchReport.stop_name(code) ++ "\"}"))
        SearchReport.exit_status(found)

# The rounds: print the last round's hits and progress, start the passes asked for (a yield lets them reach the KK
# engine), run the CPU phase, take the finished passes, then the host half.
def rounds(n: Nat, st: State, +ctx: Ctx) -> IO(Unit):
  match n:
    case 0n:
      match st:
        case State{host, _, _, _}:
          report(host, 3, ctx)
    case 1n+k:
      match st:
        case State{Host{+b, slots}, +idle, +rush, Out{+lines, 0, +line}}:
          do IO<Unit>:
            print_hits(json_of(ctx), lines)
            print_progress(line)
            launched(book_queue(b), ctx)
            IO.sleep(0)
            +t0 : Nat <- IO.now()
            m : Merged = worked_slots(gather(slots, Nil{}, Nil{}, Nil{}, ctx_start(ctx), rush), config_of(ctx))
            +t1 : Nat <- IO.now()
            +laid : List<&2, Note> <- taken(idle, book_flying(b), ctx)
            +t2 : Nat <- IO.now()
            rounds(k, hosted(m, b, laid, t0, t1, t2, ctx), ctx)
        case State{host, _, _, Out{+lines, +code, _}}:
          do IO<Unit>:
            print_hits(json_of(ctx), lines)
            report(host, code, ctx)

def round_limit() -> Nat:
  Nat.mul(1000000n, 1000000n)

# The slots (seeds in flight): eight per thread, so a round has enough CPU stages to split evenly across the threads
# (one ocean stage is ~100 ms) while the KK passes of the other slots run on the helper threads.
def slots_for(+threads: U32) -> U32:
  (threads * 8 : U32)

def started(+ctx: Ctx) -> State:
  match ctx:
    case Ctx{+start, +total, _, _, _, _, +now, +slots, _, _}:
      +book = {Book{Scan{start, total, min_chunk(), Nil{}}, Nil{}, Nil{}, Tally{0, Nil{}, Nil{}, 0n, 0, 0n}, 0, 0, 0, Stats{0n, 0n, 0n, 0n, now}} : Book}
      State{Host{book, free_slots(U32.to_nat(slots))}, False{}, 0n, Out{Nil{}, 0, "search: " ++ U32.show(slots) ++ " slots"}}

# world find on generated worlds for a config with parts B-E (spec search-v1.md section 8 output).
def run(+q: Args.Query, +config: Config.Config) -> IO(Unit):
  match q:
    case Args.Query{+start, +total, +limit, +time_ms, +json, _, _, _, +native}:
      do IO<Unit>:
        +threads : U32 <- SearchThreads.threads()
        +started_ms : Nat <- IO.now()
        +slots : U32 = slots_for(threads)
        +laid : Chan(Note) <- Chan.new(Note, (slots + 2 : U32))
        +ctx : Ctx = Ctx{start, total, limit, time_ms, json, config, started_ms, slots, native, laid}
        rounds(round_limit(), started(ctx), ctx)
