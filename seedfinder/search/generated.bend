import Base
import ../filters/shard_search.bend as ShardSearch
import ../filters/world.bend as FilterWorld
import ../gen/job.bend as GenJob
import ../gen/layout.bend as GenLayout
import ../gen/savedata.bend as SaveData
import ../cli/args.bend as Args
import ./report.bend as SearchReport
import ./worlds.bend as SearchWorlds
import ./order.bend as SearchOrder
import ./threads.bend as SearchThreads
import ./bins.bend as SearchBins
import ./speed.bend as Speed
import ./timings.bend as Timings
import ../filters/evaluate.bend as Evaluate
import ../filters/rules.bend as Rules

# `world find` for configs with parts B-E, on worlds generated in memory: part A picks the candidates chunk by chunk
# (the level-table scan), and only candidates are generated, many at once, one per slot. A round:
# - starts every KK pass the slots asked for as its own computation (GenLayout.answer: the native KK runs on the runtime's
#   IO helper threads while the rounds go on, on input words the CPU work that reached the pass built), each sending its
#   answer to the search's channel when done;
# - runs the next CPU stage of every other slot in parallel (storygen, Voronoi, commit, tiles, land, ocean, the
#   filters), in bins packed by the stages' estimated cost, which the threads take heaviest first (search/bins.bend);
# - takes the answers of every pass that finished (a marker sent after them ends the take, so no round waits for a
#   pass), hands them back to their slots, harvests the decided seeds, refills the part-A scan and gives the free slots
#   the next candidates in scan order.
# A seed is decided on its world as `world find --worlds` does (the first filter whose parts B-E hold; a seed without
# a world never matches), and decided seeds are released in scan order, so the hits are those of a
# sequential scan whatever the slot or thread count.

# A slot: free, a seed with a CPU stage to run, waiting for its KK pass, with its pass's answer back, one of the
# oldest seeds rushed this round (after its pass's answer when `back`), asking for a pass prepared for its engine (after
# its CPU work), decided, with its world built and its verdict left for the timed checks (--verbose-timings) or
# waiting for them, or held out while its CPU work runs. `cost` estimates the next CPU work (ms).
type Slot is Type:
  Free{}
  Cpu{seed: U32, job: GenJob.Job, cost: U32}
  Wait{seed: U32, job: GenJob.Job, cost: U32}
  Back{seed: U32, job: GenJob.Job, answer: GenLayout.Answer, cost: U32}
  Rush{seed: U32, job: GenJob.Job, answer: GenLayout.Answer, back: Bool}
  Asked{seed: U32, job: GenJob.Job, pass: GenLayout.Ready, cost: U32}
  Decided{seed: U32, verdict: SearchWorlds.Verdict}
  Built{seed: U32, world: Maybe<&2, FilterWorld.World>}
  Unjudged{seed: U32}
  Held{}

# Nat.min by one native comparison. Base's Nat.min recurses once per unit (8 bytes of a worker's 2 GB machine stack),
# so scan positions past 2^28 overflow it.
def lesser(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(b, a), b, a)

def free_slots(+n: Nat) -> List<&1, Slot>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Free{} <> free_slots(p)

def empty_bins(n: Nat) -> List<&1, List<&1, Slot>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Nil{} <> empty_bins(p)

def pushed(bins: List<&1, List<&1, Slot>>, +bin: Nat, x: Slot) -> List<&1, List<&1, Slot>>:
  match bins bin:
    case Nil{} _:
      [[x]]
    case Con{slots, rest} 0n:
      (x <> slots) <> rest
    case Con{slots, rest} 1n+b:
      slots <> pushed(rest, b, x)

def reversed_bins(bins: List<&1, List<&1, Slot>>) -> List<&1, List<&1, Slot>>:
  match bins:
    case Nil{}:
      Nil{}
    case Con{slots, rest}:
      List.reverse(&1, Slot, slots) <> reversed_bins(rest)

# The slots dealt to their bins, each bin in slot order.
def dealt(xs: List<&1, Slot>, +bins: List<&2, Nat>, acc: List<&1, List<&1, Slot>>) -> List<&1, List<&1, Slot>>:
  match xs:
    case Nil{}:
      reversed_bins(acc)
    case Con{x, rest}:
      dealt(rest, List.drop(&2, Nat, bins, 1n), pushed(acc, Maybe.default(&2, Nat, List.head(&2, Nat, bins), 0n), x))

type Popped is Type:
  Popped{slot: Slot, bins: List<&1, List<&1, Slot>>}

def popped_first(slots: List<&1, Slot>, rest: List<&1, List<&1, Slot>>) -> Popped:
  match slots:
    case Nil{}:
      Popped{Free{}, Nil{} <> rest}
    case Con{x, more}:
      Popped{x, more <> rest}

def popped_after(slots: List<&1, Slot>, got: Popped) -> Popped:
  match got:
    case Popped{x, bins}:
      Popped{x, slots <> bins}

# The first slot of the given bin, taken out.
def popped(bins: List<&1, List<&1, Slot>>, +bin: Nat) -> Popped:
  match bins bin:
    case Nil{} _:
      Popped{Free{}, Nil{}}
    case Con{slots, rest} 0n:
      popped_first(slots, rest)
    case Con{slots, rest} 1n+b:
      popped_after(slots, popped(rest, b))

def collect(+bins: List<&2, Nat>, got: Popped, acc: List<&1, Slot>) -> List<&1, Slot>:
  match bins got:
    case Nil{} Popped{x, _}:
      List.reverse(&1, Slot, x <> acc)
    case Con{+b, +rest} Popped{x, left}:
      collect(rest, popped(left, b), x <> acc)

# The worked bins' slots back in slot order.
def collected(+bins: List<&2, Nat>, worked: List<&1, List<&1, Slot>>) -> List<&1, Slot>:
  match bins:
    case Nil{}:
      Nil{}
    case Con{+b, +rest}:
      collect(rest, popped(worked, b), Nil{})

type Bins is Type:
  Bin{slots: List<&1, Slot>}
  Pair{a: Bins, b: Bins}

type Halves is Type:
  Halves{front: List<&1, List<&1, Slot>>, back: List<&1, List<&1, Slot>>}

def halves(n: Nat, bins: List<&1, List<&1, Slot>>, acc: List<&1, List<&1, Slot>>) -> Halves:
  match n:
    case 0n:
      Halves{List.reverse(&1, List<&1, Slot>, acc), bins}
    case 1n+p:
      match bins:
        case Nil{}:
          Halves{List.reverse(&1, List<&1, Slot>, acc), Nil{}}
        case Con{x, rest}:
          halves(p, rest, x <> acc)

def single(sp: Halves) -> Bins:
  match sp:
    case Halves{Con{slots, _}, _}:
      Bin{slots}
    case Halves{Nil{}, Con{slots, _}}:
      Bin{slots}
    case Halves{Nil{}, Nil{}}:
      Bin{Nil{}}

# 2^d bins, split in two halves of `half`, in a balanced tree with one bin per leaf.
def bin_tree(+d: Nat, +half: Nat, sp: Halves) -> Bins:
  match d sp:
    case 0n Halves{front, back}:
      single(Halves{front, back})
    case 1n+f Halves{front, back}:
      +quarter = Nat.div(half, 2n)
      Pair{bin_tree(f, quarter, halves(quarter, front, Nil{})), bin_tree(f, quarter, halves(quarter, back, Nil{}))}

def bins_flat(t: Bins) -> List<&1, List<&1, Slot>>:
  match t:
    case Bin{slots}:
      [slots]
    case Pair{a, b}:
      List.append(&1, List<&1, Slot>, bins_flat(a), bins_flat(b))

# The bins in rows of eight, each row's tree balanced.
def row_trees(fuel: Nat, sp: Halves) -> List<&1, Bins>:
  match fuel sp:
    case 0n Halves{_, _}:
      Nil{}
    case 1n+f Halves{row, rest}:
      bin_tree(3n, 4n, halves(4n, row, Nil{})) <> row_trees(f, halves(8n, rest, Nil{}))

def rows_flat(rows: List<&1, Bins>) -> List<&1, List<&1, Slot>>:
  match rows:
    case Nil{}:
      Nil{}
    case Con{t, rest}:
      List.append(&1, List<&1, Slot>, bins_flat(t), rows_flat(rest))

# A KK pass a slot asked for (tag: the slot's index).
type Request is Type:
  Request{tag: U32, pass: GenLayout.Ready}

# What the search's channel carries: a finished pass's answer, or the marker that ends a take.
type Note is Type:
  Laid{tag: U32, answer: GenLayout.Answer}
  Mark{}

# A finished pass's answer for the slot of its tag.
type Got is Type:
  Got{tag: U32, answer: GenLayout.Answer}

# The finished passes a take found, and how many.
type Taken is Type:
  Taken{laid: List<&1, Got>, count: Nat}

# The answer for one tag taken out of the finished passes, and the others.
type Pulled is Type:
  Pulled{found: Maybe<&1, GenLayout.Answer>, rest: List<&1, Got>}

# The per-run constants: scan start and length, hit limit, time limit, output mode, config, the start time, the slots
# (seeds in flight), the KK engine, the channel the passes answer on and whether to time the options (--verbose-timings).
type Ctx is Data:
  Ctx{start: U32, total: Nat, limit: U32, time_ms: Nat, json: Bool, config: ShardSearch.Search, started: Nat, slots: U32, native: Bool, laid: Chan(Note), timings: Bool}

def config_of(+ctx: Ctx) -> ShardSearch.Search:
  match ctx:
    case Ctx{_, _, _, _, _, +config, _, _, _, _, _}:
      config

def windows_of(+config: ShardSearch.Search) -> Bool:
  ShardSearch.windows(config)

def ctx_start(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{+start, _, _, _, _, _, _, _, _, _, _}:
      start

def json_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{_, _, _, _, +json, _, _, _, _, _, _}:
      json

def time_ms_of(+ctx: Ctx) -> Nat:
  match ctx:
    case Ctx{_, _, _, +time_ms, _, _, _, _, _, _, _}:
      time_ms

def elapsed(+ctx: Ctx, +now: Nat) -> Nat:
  match ctx:
    case Ctx{_, _, _, _, _, _, +started, _, _, _, _}:
      Nat.sub(now, started)

def criteria_of(+ctx: Ctx) -> ShardSearch.Levels:
  match ctx:
    case Ctx{_, _, _, _, _, +config, _, _, _, _, _}:
      ShardSearch.level(config)

def slots_of(+ctx: Ctx) -> U32:
  match ctx:
    case Ctx{_, _, _, _, _, _, _, +slots, _, _, _}:
      slots

def timings_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{_, _, _, _, _, _, _, _, _, _, +timings}:
      timings

def laid_of(+ctx: Ctx) -> Chan(Note):
  match ctx:
    case Ctx{_, _, _, _, _, _, _, _, _, +laid, _}:
      laid

def generated_in(caves: Bool, +windows: Bool, +seed: U32, final: GenJob.Final) -> Result<&1, &1, U32 & String, FilterWorld.Loaded>:
  match caves:
    case True{}:
      Done{FilterWorld.Generated{SaveData.cave_world(seed, windows, final), 0}}
    case False{}:
      Done{FilterWorld.Generated{SaveData.world(seed, windows, final), 0}}

def generated_world(+config: ShardSearch.Search, +seed: U32, final: GenJob.Final) -> Result<&1, &1, U32 & String, FilterWorld.Loaded>:
  generated_in(ShardSearch.caves(config), ShardSearch.windows(config), seed, final)

def world_verdict(job: GenJob.Job, +config: ShardSearch.Search, +seed: U32) -> SearchWorlds.Verdict:
  match job:
    case GenJob.JWorld{_, _, final}:
      SearchWorlds.world_verdict(generated_world(config, seed, final), config, seed)
    case _:
      SearchWorlds.Miss{}

# The estimated ms of a job's next CPU stage (see GenJob.Job; `gen --times` names a stage line after the stage left).
def stage_cost(+caves: Bool, +stage: U32) -> U32:
  match stage:
    case 4:
      Bool.pick(U32, caves, 31, 24)
    case 5:
      Bool.pick(U32, caves, 17, 50)
    case 6:
      100
    case 10:
      13
    case 11:
      55
    case 12:
      80
    case _:
      8

# The estimated ms of resuming after a KK pass: Voronoi, and the story up to pass 2 after the forest's pass 1.
def pass_cost(+caves: Bool, +l: GenLayout.Layout) -> U32:
  match l:
    case GenLayout.Layout{+first, _, _, _, _}:
      Bool.pick(U32, caves, 10, Bool.pick(U32, U32.is_zero(first), 8, 5))

def asked(got: GenJob.Job & Maybe<&2, GenLayout.Layout>, +seed: U32, +stage: U32, +caves: Bool, +native: Bool) -> Slot:
  (job, pass) = got
  match pass:
    case Some{+l}:
      Asked{seed, job, GenLayout.ready(native, l), pass_cost(caves, l)}
    case None{}:
      Cpu{seed, job, stage_cost(caves, stage)}

def usable_world(loaded: Result<&1, &1, U32 & String, FilterWorld.Loaded>, +config: ShardSearch.Search) -> Maybe<&2, FilterWorld.World>:
  match loaded:
    case Done{FilterWorld.Generated{+world, +platform}}:
      Bool.pick(Maybe<&2, FilterWorld.World>, SearchWorlds.usable(config, platform, world), Some{world}, None{})
    case _:
      None{}

def built_world(job: GenJob.Job, +config: ShardSearch.Search, +seed: U32) -> Maybe<&2, FilterWorld.World>:
  match job:
    case GenJob.JWorld{_, _, final}:
      usable_world(generated_world(config, seed, final), config)
    case _:
      None{}

def decided_now(timed: Bool, job: GenJob.Job, +config: ShardSearch.Search, +seed: U32) -> Slot:
  match timed:
    case True{}:
      Built{seed, built_world(job, config, seed)}
    case False{}:
      Decided{seed, world_verdict(job, config, seed)}

def settled_at(settled: Bool, job: GenJob.Job, +stage: U32, +config: ShardSearch.Search, +native: Bool, +timed: Bool, +seed: U32) -> Slot:
  match settled:
    case True{}:
      decided_now(timed, job, config, seed)
    case False{}:
      asked(GenJob.layout(job), seed, stage, ShardSearch.caves(config), native)

# Where a job stands after its CPU work: decided, asking for a KK pass (prepared for its engine), or its next stage for
# the next round; with `timed` a decided job only has its world built.
def parked(got: GenJob.Job & GenJob.Where, +config: ShardSearch.Search, +native: Bool, +timed: Bool, +seed: U32) -> Slot:
  (job, +at) = got
  match at:
    case GenJob.Where{+stage, _}:
      settled_at(GenJob.settled(stage), job, stage, config, native, timed, seed)

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

def rushed(budget: Nat, job: GenJob.Job, +config: ShardSearch.Search, +native: Bool, +timed: Bool, +seed: U32) -> Slot:
  match budget:
    case 0n:
      parked(GenJob.stage(job), config, native, timed, seed)
    case 1n+b:
      rushed(b, moved(GenJob.stage(job)), config, native, timed, seed)

def resumed(back: Bool, job: GenJob.Job, answer: GenLayout.Answer) -> GenJob.Job:
  match back:
    case True{}:
      GenJob.laid(job, GenLayout.positions(answer))
    case False{}:
      job

# Stage transitions of a rushed seed: to its next KK pass or its verdict (six CPU stages at most in between).
def rush_steps() -> Nat:
  8n

# How many of the oldest seeds are rushed (one per thread): the ones that hold back the release of later hits.
def rushed_seeds(+ctx: Ctx) -> Nat:
  U32.to_nat((slots_of(ctx) >> 4n : U32))

# The estimated ms a rushed seed adds to its stage (the stages up to its next pass or verdict).
def rush_cost(+caves: Bool) -> U32:
  Bool.pick(U32, caves, 200, 180)

# One stage transition per slot and round (or the resume after a pass), so the work of a round splits evenly; a
# rushed seed runs on to its next pass or verdict.
def work(slot: Slot, +config: ShardSearch.Search, +native: Bool, +timed: Bool) -> Slot:
  match slot:
    case Cpu{+seed, job, _}:
      parked(GenJob.stage(GenJob.step(job)), config, native, timed, seed)
    case Back{+seed, job, answer, _}:
      parked(GenJob.stage(GenJob.laid(job, GenLayout.positions(answer))), config, native, timed, seed)
    case Rush{+seed, job, answer, back}:
      rushed(rush_steps(), resumed(back, job, answer), config, native, timed, seed)
    case other:
      other

def worked_bin(slots: List<&1, Slot>, +config: ShardSearch.Search, +native: Bool, +timed: Bool) -> List<&1, Slot>:
  match slots:
    case Nil{}:
      Nil{}
    case Con{x, rest}:
      work(x, config, native, timed) <> worked_bin(rest, config, native, timed)

# The CPU work of every bin, both halves of each fork in parallel.
def worked_all(t: Bins, +config: ShardSearch.Search, +native: Bool, +timed: Bool) -> Bins:
  match t:
    case Bin{slots}:
      Bin{worked_bin(slots, config, native, timed)}
    case Pair{a, b}:
      x y = worked_all(a, config, native, timed) worked_all(b, config, native, timed)
      Pair{x, y}

# The eight rows' trees, all in parallel.
def rows_worked(rows: List<&1, Bins>, +config: ShardSearch.Search, +native: Bool, +timed: Bool) -> List<&1, Bins>:
  match rows:
    case Con{r0, Con{r1, Con{r2, Con{r3, Con{r4, Con{r5, Con{r6, Con{r7, _}}}}}}}}:
      w0 w1 w2 w3 w4 w5 w6 w7 = worked_all(r0, config, native, timed) worked_all(r1, config, native, timed) worked_all(r2, config, native, timed) worked_all(r3, config, native, timed) worked_all(r4, config, native, timed) worked_all(r5, config, native, timed) worked_all(r6, config, native, timed) worked_all(r7, config, native, timed)
      [w0, w1, w2, w3, w4, w5, w6, w7]
    case other:
      other

def spread(small: Bool, todo: List<&1, Slot>, +costs: List<&2, U32>, +config: ShardSearch.Search, +native: Bool, +timed: Bool) -> List<&1, Slot>:
  match small:
    case True{}:
      worked_bin(todo, config, native, timed)
    case False{}:
      +at = SearchBins.placed_leaves(costs)
      collected(at, rows_flat(rows_worked(row_trees(8n, halves(8n, dealt(todo, at, empty_bins(SearchBins.leaves())), Nil{})), config, native, timed)))

# The slots with CPU work taken out (in order) and held, and their costs.
type Gathered is Type:
  Gathered{slots: List<&1, Slot>, todo: List<&1, Slot>, costs: List<&2, U32>}

def as_todo(rush: Bool, slot: Slot) -> Slot:
  match rush:
    case True{}:
      match slot:
        case Cpu{+seed, job, _}:
          Rush{seed, job, GenLayout.Positioned{Nil{}}, False{}}
        case Back{+seed, job, answer, _}:
          Rush{seed, job, answer, True{}}
        case other:
          other
    case False{}:
      slot

# Takes the slots with CPU work out; those at scan positions up to `rush` (the oldest seeds) are rushed.
def gather(xs: List<&1, Slot>, acc: List<&1, Slot>, todo: List<&1, Slot>, +costs: List<&2, U32>, +start: U32, +rush: Nat, +caves: Bool) -> Gathered:
  match xs:
    case Nil{}:
      Gathered{List.reverse(&1, Slot, acc), List.reverse(&1, Slot, todo), List.reverse(&2, U32, costs)}
    case Con{x, rest}:
      match x:
        case Cpu{+seed, job, +cost}:
          +r = Nat.is_le(SearchOrder.position(seed, start), rush)
          gather(rest, Held{} <> acc, as_todo(r, Cpu{seed, job, cost}) <> todo, Bool.pick(U32, r, (cost + rush_cost(caves) : U32), cost) <> costs, start, rush, caves)
        case Back{+seed, job, answer, +cost}:
          +r = Nat.is_le(SearchOrder.position(seed, start), rush)
          gather(rest, Held{} <> acc, as_todo(r, Back{seed, job, answer, cost}) <> todo, Bool.pick(U32, r, (cost + rush_cost(caves) : U32), cost) <> costs, start, rush, caves)
        case other:
          gather(rest, other <> acc, todo, costs, start, rush, caves)

# The slots after their CPU work, and the passes they asked for (tagged with the slot index, in slot order) and their
# count.
type Merged is Type:
  Merged{slots: List<&1, Slot>, asked: List<&1, Request>, count: U32}

def merge(xs: List<&1, Slot>, done: List<&1, Slot>, +tag: U32, acc: List<&1, Slot>, asked: List<&1, Request>, +count: U32) -> Merged:
  match xs:
    case Nil{}:
      Merged{List.reverse(&1, Slot, acc), List.reverse(&1, Request, asked), count}
    case Con{x, rest}:
      match x:
        case Held{}:
          match done:
            case Nil{}:
              merge(rest, Nil{}, (tag + 1 : U32), Free{} <> acc, asked, count)
            case Con{w, more}:
              match w:
                case Asked{+seed, job, pass, +cost}:
                  merge(rest, more, (tag + 1 : U32), Wait{seed, job, cost} <> acc, Request{tag, pass} <> asked, (count + 1 : U32))
                case other:
                  merge(rest, more, (tag + 1 : U32), other <> acc, asked, count)
        case other:
          merge(rest, done, (tag + 1 : U32), other <> acc, asked, count)

def worked_slots(g: Gathered, +config: ShardSearch.Search, +native: Bool, +timed: Bool) -> Merged:
  match g:
    case Gathered{slots, todo, +costs}:
      merge(slots, spread(Nat.is_le(List.length(&2, U32, costs), 1n), todo, costs, config, native, timed), 0, Nil{}, Nil{}, 0)


def pulled_from(hit: Bool, +t: U32, answer: GenLayout.Answer, p: Pulled) -> Pulled:
  match hit p:
    case True{} Pulled{_, rest}:
      Pulled{Some{answer}, rest}
    case False{} Pulled{found, rest}:
      Pulled{found, Got{t, answer} <> rest}

def pulled(gots: List<&1, Got>, +tag: U32) -> Pulled:
  match gots:
    case Nil{}:
      Pulled{None{}, Nil{}}
    case Con{Got{+t, answer}, more}:
      pulled_from(U32.is_eq(t, tag), t, answer, pulled(more, tag))

def back(x: Slot, found: Maybe<&1, GenLayout.Answer>) -> Slot:
  match x:
    case Wait{+seed, job, +cost}:
      match found:
        case Some{answer}:
          Back{seed, job, answer, cost}
        case None{}:
          Wait{seed, job, cost}
    case other:
      other

# The finished passes handed back to their slots (the answer for the slot of `tag` pulled out).
def deliver(xs: List<&1, Slot>, got: Pulled, +tag: U32, acc: List<&1, Slot>) -> List<&1, Slot>:
  match xs got:
    case Nil{} _:
      List.reverse(&1, Slot, acc)
    case Con{x, rest} Pulled{found, gots}:
      deliver(rest, pulled(gots, (tag + 1 : U32)), (tag + 1 : U32), back(x, found) <> acc)

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

def started_job(caves: Bool, +seed: U32, +windows: Bool) -> GenJob.Job:
  match caves:
    case True{}:
      GenJob.start_caves(seed, windows, 0, False{})
    case False{}:
      GenJob.start(seed, windows, False{})

def fill(xs: List<&1, Slot>, +pending: List<&2, U32>, +windows: Bool, +caves: Bool, +start: U32, +first: Nat, +busy: U32, +ready: U32, +at: List<&2, Nat>, acc: List<&1, Slot>) -> Filled:
  match xs:
    case Nil{}:
      Filled{List.reverse(&1, Slot, acc), pending, first, busy, ready, at}
    case Con{x, rest}:
      match x:
        case Free{}:
          match pending:
            case Con{+seed, +more}:
              +p = SearchOrder.position(seed, start)
              fill(rest, more, windows, caves, start, lesser(first, p), (busy + 1 : U32), (ready + 1 : U32), p <> at, Cpu{seed, started_job(caves, seed, windows), stage_cost(caves, 0)} <> acc)
            case Nil{}:
              fill(rest, Nil{}, windows, caves, start, first, busy, ready, at, Free{} <> acc)
        case Cpu{+seed, job, +cost}:
          +p = SearchOrder.position(seed, start)
          fill(rest, pending, windows, caves, start, lesser(first, p), (busy + 1 : U32), (ready + 1 : U32), p <> at, Cpu{seed, job, cost} <> acc)
        case Wait{+seed, job, +cost}:
          +p = SearchOrder.position(seed, start)
          fill(rest, pending, windows, caves, start, lesser(first, p), (busy + 1 : U32), ready, p <> at, Wait{seed, job, cost} <> acc)
        case Back{+seed, job, answer, +cost}:
          +p = SearchOrder.position(seed, start)
          fill(rest, pending, windows, caves, start, lesser(first, p), (busy + 1 : U32), (ready + 1 : U32), p <> at, Back{seed, job, answer, cost} <> acc)
        case other:
          fill(rest, pending, windows, caves, start, first, busy, ready, at, other <> acc)

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
    case Tally{+found, +hits, +lines, +last, _, +scanned} Ctx{+start, _, +limit, _, _, _, _, _, _, _, _}:
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

def scanned_chunk(+sc: Scan, +criteria: ShardSearch.Levels, +wanted: Nat) -> Scan:
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
def refilled(n: Nat, go: Bool, +sc: Scan, +budget: Nat, +criteria: ShardSearch.Levels, +wanted: Nat) -> Scan:
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

def refill(+sc: Scan, +criteria: ShardSearch.Levels, +wanted: Nat) -> Scan:
  refilled(64n, short(sc, round_seeds(), wanted), sc, round_seeds(), criteria, wanted)

# The refilled scan; with --verbose-timings the round's timed checks refilled it already.
def refilled_now(timed: Bool, +sc: Scan, +criteria: ShardSearch.Levels, +wanted: Nat) -> Scan:
  match timed:
    case True{}:
      sc
    case False{}:
      refill(sc, criteria, wanted)

def chunk_seeds(+sc: Scan) -> Nat:
  match sc:
    case Scan{_, +left, +size, _}:
      lesser(size, left)

# The scan and timings after a --verbose-timings refill.
type Refilled is Data:
  Refilled{scan: Scan, timings: Timings.Timings}

# refill with --verbose-timings: each chunk's scan timed.
def timed_refilled(n: Nat, go: Bool, +sc: Scan, +budget: Nat, +ctx: Ctx, +t: Timings.Timings) -> IO(Refilled):
  match n:
    case 0n:
      IO.pure(Refilled, Refilled{sc, t})
    case 1n+p:
      match go:
        case False{}:
          IO.pure(Refilled, Refilled{sc, t})
        case True{}:
          +wanted = U32.to_nat(slots_of(ctx))
          +rest = Nat.sub(budget, chunk_of(sc))
          do IO<Refilled>:
            +t0 : Nat <- IO.now()
            +next : Scan = scanned_chunk(sc, criteria_of(ctx), wanted)
            +t1 : Nat <- IO.now()
            timed_refilled(p, short(next, rest, wanted), next, rest, ctx, Timings.with_prefilter(t, chunk_seeds(sc), Nat.sub(t1, t0)))

def covered(+sc: Scan, +ctx: Ctx) -> Nat:
  match sc ctx:
    case Scan{_, +left, _, _} Ctx{_, +total, _, _, _, _, _, _, _, _, _}:
      Nat.sub(total, left)

def scan_left(+sc: Scan) -> Nat:
  match sc:
    case Scan{_, +left, _, _}:
      left

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

# Totals for the closing line: rounds, ms in the CPU phases, ms taking finished passes, KK passes finished, when the
# progress line was last printed, the speed points of the progress lines, and the --verbose-timings timings.
type Stats is Data:
  Stats{rounds: Nat, cpu: Nat, take: Nat, passes: Nat, shown: Nat, speed: List<&2, Speed.Point>, timings: Timings.Timings}

def timed(+s: Stats, +t0: Nat, +t1: Nat, +t2: Nat, +passes: Nat) -> Stats:
  match s:
    case Stats{+rounds, +cpu, +take, +tp, +shown, +speed, +timings}:
      Stats{Nat.add(rounds, 1n), Nat.add(cpu, Nat.sub(t1, t0)), Nat.add(take, Nat.sub(t2, t1)), Nat.add(tp, passes), shown, speed, timings}

def shown_at(+s: Stats, +now: Nat, +p: Speed.Point) -> Stats:
  match s:
    case Stats{+rounds, +cpu, +take, +passes, _, +speed, +timings}:
      Stats{rounds, cpu, take, passes, now, Speed.ticked(speed, p), timings}

def due(+s: Stats, +now: Nat) -> Bool:
  match s:
    case Stats{_, _, _, _, +shown, _, _}:
      Nat.is_ge(Nat.sub(now, shown), 1000n)

def stats_speed(+s: Stats) -> List<&2, Speed.Point>:
  match s:
    case Stats{_, _, _, _, _, +speed, _}:
      speed

def stats_timings(+s: Stats) -> Timings.Timings:
  match s:
    case Stats{_, _, _, _, _, _, +timings}:
      timings

def with_timings(+s: Stats, +t: Timings.Timings) -> Stats:
  match s:
    case Stats{+rounds, +cpu, +take, +passes, +shown, +speed, _}:
      Stats{rounds, cpu, take, passes, shown, speed, t}

# The search's data between rounds: the part-A scan, how many passes to start, the decided candidates waiting for an
# earlier one, the tally, how many candidates were decided, the busy slots, the passes in flight and the stats.
type Book is Data:
  Book{scan: Scan, queued: U32, waiting: List<&2, SearchWorlds.Judged>, tally: Tally, made: U32, busy: U32, flying: U32, stats: Stats}

def book_scan(+b: Book) -> Scan:
  match b:
    case Book{+sc, _, _, _, _, _, _, _}:
      sc

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
    case Book{+sc, +queued, +waiting, +t, +made, +busy, +flying, _}:
      Book{sc, queued, waiting, t, made, busy, flying, s}

def with_tally(+b: Book, +waiting: List<&2, SearchWorlds.Judged>, +t: Tally) -> Book:
  match b:
    case Book{+sc, +queued, _, _, +made, +busy, +flying, +s}:
      Book{sc, queued, waiting, t, made, busy, flying, s}

# The book after a round's take: how many passes were asked for (to start next round) and the passes in flight.
def with_flow(+b: Book, +more: U32, +laid: Nat, +s: Stats) -> Book:
  match b:
    case Book{+sc, _, +waiting, +t, +made, +busy, +flying, _}:
      Book{sc, more, waiting, without_lines(t), made, busy, (flying + more - U32.from_nat(laid) : U32), s}

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
    case Book{_, +queued, +waiting, +t, +made, +busy, +flying, +s}:
      Book{sc, queued, SearchOrder.merged(~SearchWorlds.Judged, ~judged_seed, done, waiting, ctx_start(ctx)), t,
        (made + U32.from_nat(List.length(&2, SearchWorlds.Judged, done)) : U32), busy, flying, s}

def with_filled(+b: Book, +pending: List<&2, U32>, +busy: U32) -> Book:
  match b:
    case Book{+sc, +queued, +waiting, +t, +made, _, +flying, +s}:
      Book{with_pending(sc, pending), queued, waiting, t, made, busy, flying, s}

def ended(+b: Book, +waiting: List<&2, SearchWorlds.Judged>) -> Bool:
  match b:
    case Book{Scan{_, +left, _, +pending}, _, _, _, _, +busy, _, _}:
      Nat.is_eq(left, 0n) && List.is_empty(&2, U32, pending) && U32.is_zero(busy) && List.is_empty(&2, SearchWorlds.Judged, waiting)

# Whether the next round has nothing to do but wait for passes in flight: no slot with CPU work, no pass to start,
# and no free slot the scan could still fill.
def idle(+b: Book, +ready: U32, +ctx: Ctx) -> Bool:
  match b:
    case Book{Scan{_, +left, _, +pending}, +queued, _, _, _, +busy, +flying, _}:
      +scanning = U32.is_ne(busy, slots_of(ctx)) && Nat.is_gt(left, 0n)
      U32.is_zero(ready) && U32.is_zero(queued) && U32.is_ne(flying, 0) && Bool.not(scanning)

# The search between rounds: the book, the slots (index = request tag) and the passes to start.
type Host is Type:
  Host{book: Book, slots: List<&1, Slot>, queue: List<&1, Request>}

# What a round hands to IO: hit lines to print, the stop code and a progress line ("" for none).
type Out is Data:
  Out{lines: List<&2, String>, code: U32, progress: String}

# The loop's state: the host side, whether the next round only waits for passes, up to which scan position its seeds
# are rushed, and the round's output.
type State is Type:
  State{host: Host, idle: Bool, rush: Nat, out: Out}

def progress(+b: Book, +levels: Nat) -> String:
  match b:
    case Book{_, _, +waiting, Tally{+found, _, _, _, _, +scanned}, +made, +busy, +flying, Stats{+rounds, +cpu, +take, +passes, _, +speed, _}}:
      "search: scanned " ++ Nat.show(scanned) ++ ", levels " ++ Nat.show(levels) ++ ", worlds " ++ U32.show(made) ++ ", generating " ++ U32.show(busy)
        ++ " (kk " ++ U32.show(flying) ++ ", passes " ++ Nat.show(passes) ++ "), waiting "
        ++ Nat.show(List.length(&2, SearchWorlds.Judged, waiting)) ++ ", hits " ++ U32.show(found) ++ " (rounds " ++ Nat.show(rounds)
        ++ ", cpu " ++ Nat.show(cpu) ++ " ms, take " ++ Nat.show(take) ++ " ms)\n" ++ Speed.line(speed)

# The speed point of the book `ms` into the run: the part-A scan's prefix, the candidates decided and the decided
# prefix of the scan.
def point_of(+b: Book, +ms: Nat, +ctx: Ctx) -> Speed.Point:
  match b:
    case Book{_, _, _, Tally{_, _, _, _, _, +scanned}, +made, _, _, _}:
      Speed.Point{ms, covered(book_scan(b), ctx), U32.to_nat(made), scanned}

def worked_round(go: Bool, slots: List<&1, Slot>, +b: Book, +ready: U32, +rush: Nat, +now: Nat, +ctx: Ctx) -> State:
  match go:
    case True{}:
      +show = due(book_stats(b), now)
      +kept = with_stats(b, Bool.pick(Stats, show, shown_at(book_stats(b), now, point_of(b, elapsed(ctx, now), ctx)), book_stats(b)))
      State{Host{kept, slots, Nil{}}, idle(kept, ready, ctx), rush, Out{lines_of(book_tally(b)), 0, Bool.pick(String, show, progress(kept, covered(book_scan(kept), ctx)), "")}}
    case False{}:
      State{Host{b, slots, Nil{}}, False{}, 0n, Out{lines_of(book_tally(b)), code_of(book_tally(b)), ""}}

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
  3000n

def widen_at_ms() -> Nat:
  10000n

def widen_ms() -> Nat:
  10000n

# How many seeds may be in flight: a quarter of half the slots at the start and that half after ramp_ms(), so the first
# seeds (and hits) come out sooner while the search fills up; the other half joins from widen_at_ms() on, over
# widen_ms(): more seeds per round fill the threads better, and a search that runs that long no longer minds the seeds
# still in flight past its last hit.
def allowed(+ctx: Ctx, +now: Nat) -> Nat:
  +half = Nat.div(U32.to_nat(slots_of(ctx)), 2n)
  +t = elapsed(ctx, now)
  Nat.add(lesser(half, Nat.add(Nat.div(half, 4n), Nat.div(Nat.mul(t, half), ramp_ms()))),
    lesser(half, Nat.div(Nat.mul(Nat.sub(t, widen_at_ms()), half), widen_ms())))

def book_busy(+b: Book) -> U32:
  match b:
    case Book{_, _, _, _, _, +busy, _, _}:
      busy

def harvested(h: Harvested, +b: Book, +now: Nat, +ctx: Ctx) -> State:
  match h:
    case Harvested{slots, +done}:
      +cap = U32.to_nat(slots_of(ctx))
      +room = Nat.sub(allowed(ctx, now), Nat.sub(U32.to_nat(book_busy(b)), List.length(&2, SearchWorlds.Judged, done)))
      +next = refilled_now(timings_of(ctx), book_scan(b), criteria_of(ctx), cap)
      +pending = pending_of(next)
      filled_round(fill(slots, List.take(&2, U32, pending, room), windows_of(config_of(ctx)), ShardSearch.caves(config_of(ctx)), ctx_start(ctx), covered(next, ctx), 0, 0, Nil{}, Nil{}),
        List.drop(&2, U32, pending, room), with_decided(b, next, done, ctx), now, ctx)

def late_or(late: Bool, +b: Book, slots: List<&1, Slot>, laid: List<&1, Got>, +now: Nat, +ctx: Ctx) -> State:
  match late:
    case True{}:
      State{Host{with_tally(b, book_waiting(b), with_code(book_tally(b), 3)), slots, Nil{}}, False{}, 0n, Out{Nil{}, 3, ""}}
    case False{}:
      harvested(harvest(deliver(slots, pulled(laid, 0), 0, Nil{}), Nil{}, Nil{}), b, now, ctx)

def with_queue(st: State, reqs: List<&1, Request>) -> State:
  match st:
    case State{Host{+b, slots, _}, +idle, +rush, +out}:
      State{Host{b, slots, reqs}, idle, rush, out}

# The host half of a round (CPU phase from t0 to t1, take until t2): stop at the time limit (dropping the work in
# flight), else hand the finished passes back, harvest, refill, fill and release in scan order; the passes asked for
# start next round.
def hosted(m: Merged, +b: Book, got: Taken, +t0: Nat, +t1: Nat, +t2: Nat, +ctx: Ctx) -> State:
  match m got:
    case Merged{slots, asked, +count} Taken{laid, +n}:
      +kept = with_flow(b, count, n, timed(book_stats(b), t0, t1, t2, n))
      with_queue(late_or(Nat.is_ge(elapsed(ctx, t2), time_ms_of(ctx)), kept, slots, laid, t2, ctx), asked)

# The worlds built this round with their verdicts left out (Unjudged), what --verbose-timings checks on them and their
# seeds.
type Split is Type:
  Split{slots: List<&1, Slot>, opens: List<&2, Timings.Open>, seeds: List<&2, U32>}

def split(xs: List<&1, Slot>, +config: ShardSearch.Search, acc: List<&1, Slot>, +opens: List<&2, Timings.Open>, +seeds: List<&2, U32>) -> Split:
  match xs:
    case Nil{}:
      Split{List.reverse(&1, Slot, acc), List.reverse(&2, Timings.Open, opens), List.reverse(&2, U32, seeds)}
    case Con{x, rest}:
      match x:
        case Built{+seed, +world}:
          split(rest, config, Unjudged{seed} <> acc, Timings.Open{world, None{}} <> opens, seed <> seeds)
        case other:
          split(rest, config, other <> acc, opens, seeds)

def matches_of(+seeds: List<&2, U32>, +opens: List<&2, Timings.Open>) -> List<&2, SearchWorlds.Matched>:
  match seeds opens:
    case Con{+seed, ss} Con{+o, os}:
      SearchWorlds.Matched{seed, o, SearchWorlds.Miss{}} <> matches_of(ss, os)
    case _ _:
      Nil{}

def first_verdict(+judged: List<&2, SearchWorlds.Judged>) -> SearchWorlds.Verdict:
  match judged:
    case Con{SearchWorlds.Judged{_, +v}, _}:
      v
    case Nil{}:
      SearchWorlds.Miss{}

def judged_slots(xs: List<&1, Slot>, +judged: List<&2, SearchWorlds.Judged>, acc: List<&1, Slot>) -> List<&1, Slot>:
  match xs:
    case Nil{}:
      List.reverse(&1, Slot, acc)
    case Con{x, rest}:
      match x:
        case Unjudged{+seed}:
          judged_slots(rest, List.drop(&2, SearchWorlds.Judged, judged, 1n), Decided{seed, first_verdict(judged)} <> acc)
        case other:
          judged_slots(rest, judged, other <> acc)

def with_judged(+b: Book, +sc: Scan, +t: Timings.Timings) -> Book:
  match b:
    case Book{_, +queued, +waiting, +tally, +made, +busy, +flying, +s}:
      Book{sc, queued, waiting, tally, made, busy, flying, with_timings(s, t)}

def refilled_scan(+r: Refilled) -> Scan:
  match r:
    case Refilled{+sc, _}:
      sc

def refilled_timings(+r: Refilled) -> Timings.Timings:
  match r:
    case Refilled{_, +t}:
      t

def judged_opens(+j: Timings.Judged) -> List<&2, Timings.Open>:
  match j:
    case Timings.Judged{_, +opens}:
      opens

def judged_timings(+j: Timings.Judged) -> Timings.Timings:
  match j:
    case Timings.Judged{+t, _}:
      t

# A round's slots and book after its timed checks.
type Judging is Type:
  Judging{merged: Merged, book: Book}

def judging(sp: Split, asked: List<&1, Request>, +count: U32, +b: Book, +ms: Nat, +ctx: Ctx) -> IO(Judging):
  match sp:
    case Split{slots, +opens, +seeds}:
      +sc = book_scan(b)
      do IO<Judging>:
        +refilled : Refilled <- timed_refilled(64n, short(sc, round_seeds(), U32.to_nat(slots_of(ctx))), sc, round_seeds(), ctx,
          Timings.with_generation(stats_timings(book_stats(b)), ms))
        +j : Timings.Judged <- Timings.judged(refilled_timings(refilled), ShardSearch.laters(config_of(ctx)), opens)
        +t0 : Nat <- IO.now()
        +verdicts : List<&2, SearchWorlds.Judged> = SearchWorlds.matched_verdicts(config_of(ctx), matches_of(seeds, judged_opens(j)))
        +t1 : Nat <- IO.now()
        return Judging{Merged{judged_slots(slots, verdicts, Nil{}), asked, count}, with_judged(b, refilled_scan(refilled), Timings.with_hits(judged_timings(j), Nat.sub(t1, t0)))}

# With --verbose-timings, the round's generation (`ms`) is counted, the part-A scan refilled and the worlds built this
# round decided, all timed per option; the host half then finds the scan refilled and the slots decided.
def judged_round(timed: Bool, m: Merged, +b: Book, +ms: Nat, +ctx: Ctx) -> IO(Judging):
  match timed:
    case False{}:
      IO.pure(Judging, Judging{m, b})
    case True{}:
      match m:
        case Merged{slots, asked, +count}:
          judging(split(slots, config_of(ctx), Nil{}, Nil{}, Nil{}), asked, count, b, ms, ctx)

def judged_hosted(j: Judging, got: Taken, +t0: Nat, +t1: Nat, +t2: Nat, +ctx: Ctx) -> State:
  match j:
    case Judging{m, +b}:
      hosted(m, b, got, t0, t1, t2, ctx)

def native_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{_, _, _, _, _, _, _, _, +native, _, _}:
      native

# A pass as its own computation: its answer goes to the search's channel.
def solved(+tag: U32, pass: GenLayout.Ready, +ctx: Ctx) -> IO(Bool):
  do IO<Bool>:
    answer : GenLayout.Answer <- GenLayout.answer(pass)
    Chan.send(Note, laid_of(ctx), Laid{tag, answer})

def launched(reqs: List<&1, Request>, +ctx: Ctx) -> IO(Unit):
  match reqs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Request{+tag, pass}, rest}:
      do IO<Unit>:
        IO.spawn(Bool, solved(tag, pass, ctx))
        launched(rest, ctx)

# The finished passes in the channel up to the marker.
def drained(n: Nat, got: Maybe<&1, Note>, +ch: Chan(Note), acc: List<&1, Got>, +count: Nat) -> IO(Taken):
  match n:
    case 0n:
      IO.pure(Taken, Taken{acc, count})
    case 1n+k:
      match got:
        case Some{note}:
          match note:
            case Laid{+tag, answer}:
              do IO<Taken>:
                next : Maybe<&1, Note> <- Chan.recv(Note, ch)
                drained(k, next, ch, Got{tag, answer} <> acc, Nat.add(count, 1n))
            case Mark{}:
              IO.pure(Taken, Taken{acc, count})
        case None{}:
          IO.pure(Taken, Taken{acc, count})

def idle_ms() -> U32:
  2

# Every pass finished by now: a yield lets the finished computations send, then a marker sent after them ends the
# take (an idle round sleeps idle_ms() first).
def taken(+idle: Bool, +flying: U32, +ctx: Ctx) -> IO(Taken):
  +ch = laid_of(ctx)
  do IO<Taken>:
    IO.sleep(Bool.pick(U32, idle, idle_ms(), 0))
    sent : Bool <- Chan.send(Note, ch, Mark{})
    first : Maybe<&1, Note> <- Chan.recv(Note, ch)
    drained(U32.to_nat((flying + 2 : U32)), first, ch, Nil{}, 0n)

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
    case Stats{+rounds, +cpu, +take, +passes, _, _, _}:
      "search: " ++ Nat.show(rounds) ++ " rounds, cpu " ++ Nat.show(cpu) ++ " ms, take " ++ Nat.show(take) ++ " ms, "
        ++ Nat.show(passes) ++ " KK passes"

def report(host: Host, +code: U32, +ctx: Ctx) -> IO(Unit):
  match host ctx:
    case Host{Book{+sc, _, _, Tally{+found, +hits, _, +last, _, +scanned}, +made, _, _, +stats}, _, _} Ctx{+start, +total, _, _, +json, +config, +started, _, _, _, +timings}:
      +decided = scanned_at(Tally{found, hits, Nil{}, last, code, scanned}, code, total)
      +position = SearchReport.position_json(start, decided, code)
      do IO<Unit>:
        +now : Nat <- IO.now()
        IO.print_err("search: " ++ U32.show(made) ++ " candidate worlds generated")
        IO.print_err(stats_line(stats))
        IO.print_err(Speed.line(Speed.ticked(stats_speed(stats), Speed.Point{Nat.sub(now, started), Nat.sub(total, scan_left(sc)), U32.to_nat(made), decided})))
        Timings.print_if(timings, stats_timings(stats), Nat.sub(now, started))
        IO.print(Bool.pick(String, json,
          "{\"version\":1,\"platform\":\"" ++ SearchWorlds.platform_name(ShardSearch.windows(config)) ++ "\",\"hits\":[" ++ String.join(hits, ",") ++ "]," ++ position ++ ",\"stopped\":\"" ++ SearchReport.stop_name(code) ++ "\"}",
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
        case State{Host{+b, slots, queue}, +idle, +rush, Out{+lines, 0, +line}}:
          do IO<Unit>:
            print_hits(json_of(ctx), lines)
            print_progress(line)
            +shown : Nat <- IO.now()
            Timings.print_if(timings_of(ctx) && Bool.not(String.is_empty(line)), stats_timings(book_stats(b)), elapsed(ctx, shown))
            launched(queue, ctx)
            IO.sleep(0)
            +t0 : Nat <- IO.now()
            m : Merged = worked_slots(gather(slots, Nil{}, Nil{}, Nil{}, ctx_start(ctx), rush, ShardSearch.caves(config_of(ctx))), config_of(ctx), native_of(ctx), timings_of(ctx))
            +t1 : Nat <- IO.now()
            laid : Taken <- taken(idle, book_flying(b), ctx)
            +t2 : Nat <- IO.now()
            j : Judging <- judged_round(timings_of(ctx), m, b, Nat.sub(t2, t0), ctx)
            rounds(k, judged_hosted(j, laid, t0, t1, t2, ctx), ctx)
        case State{host, _, _, Out{+lines, +code, _}}:
          do IO<Unit>:
            print_hits(json_of(ctx), lines)
            report(host, code, ctx)

def round_limit() -> Nat:
  Nat.mul(1000000n, 1000000n)

# The slots (seeds in flight): sixteen per thread (eight at first, see allowed), so a round has enough CPU stages to
# split evenly across the threads (one ocean stage is ~100 ms) while the KK passes of the other slots run on the helper
# threads.
def slots_for(+threads: U32) -> U32:
  (threads * 16 : U32)

def started(+ctx: Ctx) -> State:
  match ctx:
    case Ctx{+start, +total, _, _, _, +config, +now, +slots, _, _, _}:
      +stats = {Stats{0n, 0n, 0n, 0n, now, Speed.started(), Timings.started(ShardSearch.laters(config))} : Stats}
      +book = {Book{Scan{start, total, min_chunk(), Nil{}}, 0, Nil{}, Tally{0, Nil{}, Nil{}, 0n, 0, 0n}, 0, 0, 0, stats} : Book}
      State{Host{book, free_slots(U32.to_nat(slots)), Nil{}}, False{}, 0n, Out{Nil{}, 0, "search: " ++ U32.show(slots) ++ " slots"}}

# world find on generated worlds for a config with parts B-E (docs/config.md section 8 output).
def run(+q: Args.Query, +config: ShardSearch.Search) -> IO(Unit):
  match q:
    case Args.Query{+start, +total, +limit, +time_ms, +json, _, _, _, +native, +timings}:
      do IO<Unit>:
        +threads : U32 <- SearchThreads.threads()
        +started_ms : Nat <- IO.now()
        +slots : U32 = slots_for(threads)
        +laid : Chan(Note) <- Chan.new(Note, (slots + 2 : U32))
        +ctx : Ctx = Ctx{start, total, limit, time_ms, json, config, started_ms, slots, native, laid, timings}
        rounds(round_limit(), started(ctx), ctx)
