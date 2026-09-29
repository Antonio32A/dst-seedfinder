import Base
import ../cli/args.bend as Args
import ../cli/files.bend as Files
import ../filters/dump.bend as FilterDump
import ../filters/par.bend as Par
import ../search/threads.bend as SearchThreads
import ../trace/canon.bend as Canon
import ../worldsim/layout/space.bend as LayoutSpace
import ./job.bend as GenJob
import ./layout.bend as GenLayout
import ./savedata.bend as SaveData

# `seedfinder world dump`: generates the seeds a slot each, several at once, and writes each world's dump
# (docs/world-dump.md), with one line per seed when it is written:
#   dump seed=S platform=P outcome=world|gaveup|crashed ents=N ms=T
# (ents: the entities in the dump, ms: from the start of the seed's generation to its dump written). A round runs the
# CPU stages of every slot in parallel, each up to its next KK pass or to its world (encoded there, also in parallel),
# starts the KK passes as their own computations (the native KK runs on the runtime's IO helper threads), writes the
# finished dumps, gives their slots the next seeds and waits for the passes. A gave-up seed's dump is the gave-up
# header; a crashed seed has none, and the exit status is 1 after the other seeds when a seed crashed or a dump could
# not be written.

# A slot: free, a seed with CPU work, at a KK pass, waiting for its pass's positions, or finished (outcome 0 world,
# 1 gave up, 2 crashed; count: the entities of its dump). `since`: when its generation started (ms).
type Slot is Type:
  Free{}
  Busy{seed: U32, job: GenJob.Job, since: Nat}
  Laying{seed: U32, job: GenJob.Job, layout: GenLayout.Layout, since: Nat}
  Waiting{seed: U32, job: GenJob.Job, laid: Chan(List<&2, LayoutSpace.Vec>), since: Nat}
  Finished{seed: U32, outcome: U32, count: U32, bytes: List<&2, U32>, since: Nat}

type Slots is Type:
  Leaf{slot: Slot}
  Fork{a: Slots, b: Slots}

type Split is Type:
  Split{front: List<&1, Slot>, back: List<&1, Slot>}

# The next seed and the seeds left to start, the slots in use, and the seeds without a dump.
type Feed is Data:
  Feed{next: U32, left: Nat, busy: U32, failed: U32}

type Fed is Type:
  Fed{slots: List<&1, Slot>, feed: Feed}

# The per-run constants: the query and the slot count.
type Ctx is Data:
  Ctx{query: Args.Dump, slots: Nat}

def windows_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{Args.Dump{_, _, +windows, _, _, _}, _}:
      windows

def native_of(+ctx: Ctx) -> Bool:
  match ctx:
    case Ctx{Args.Dump{_, _, _, +native, _, _}, _}:
      native

def path_of(+ctx: Ctx, +seed: U32) -> String:
  match ctx:
    case Ctx{Args.Dump{_, _, _, _, +out, +folder}, _}:
      Bool.pick(String, folder, out ++ "/" ++ U32.show(seed) ++ ".dstw", out)

def instance_count(prefabs: List<&2, FilterDump.Prefab>, +n: U32) -> U32:
  match prefabs:
    case Nil{}:
      n
    case Con{FilterDump.Prefab{_, +positions}, rest}:
      instance_count(rest, (n + U32.from_nat(List.length(&2, FilterDump.Position, positions)) : U32))

def world_finished(+d: FilterDump.Dump, +seed: U32, +since: Nat) -> Slot:
  Finished{seed, 0, instance_count(FilterDump.prefabs(d), 0), FilterDump.bytes(d), since}

def finished(job: GenJob.Job, +seed: U32, +since: Nat, +ctx: Ctx) -> Slot:
  match job:
    case GenJob.JWorld{_, _, final}:
      world_finished(SaveData.dump(seed, windows_of(ctx), final), seed, since)
    case GenJob.JDone{_, _, GenJob.Crashed{}}:
      Finished{seed, 2, 0, Nil{}, since}
    case _:
      Finished{seed, 1, 0, FilterDump.bytes(FilterDump.GaveUp{seed, Bool.pick(U32, windows_of(ctx), 1, 2), 0}), since}

def at_pass(got: GenJob.Job & Maybe<&2, GenLayout.Layout>, +seed: U32, +since: Nat) -> Slot:
  (job, pass) = got
  match pass:
    case Some{+l}:
      Laying{seed, job, l, since}
    case None{}:
      Busy{seed, job, since}

def settled_slot(settled: Bool, job: GenJob.Job, +seed: U32, +since: Nat, +ctx: Ctx) -> Slot:
  match settled:
    case True{}:
      finished(job, seed, since, ctx)
    case False{}:
      at_pass(GenJob.layout(job), seed, since)

def parked(got: GenJob.Job & GenJob.Where, +seed: U32, +since: Nat, +ctx: Ctx) -> Slot:
  (job, +at) = got
  match at:
    case GenJob.Where{+stage, _}:
      settled_slot(GenJob.settled(stage), job, seed, since, ctx)

def stepped_unless_laying(got: GenJob.Job & Maybe<&2, GenLayout.Layout>) -> GenJob.Job:
  (job, pass) = got
  match pass:
    case Some{_}:
      job
    case None{}:
      GenJob.step(job)

def moved_at(settled: Bool, native: Bool, job: GenJob.Job) -> GenJob.Job:
  match settled native:
    case True{} _:
      job
    case False{} True{}:
      stepped_unless_laying(GenJob.layout(job))
    case False{} False{}:
      GenJob.advance(job)

# A stage transition, or with kk.bend a whole KK pass; a job at a native KK pass, or decided, stays.
def moved(+native: Bool, got: GenJob.Job & GenJob.Where) -> GenJob.Job:
  (job, +at) = got
  match at:
    case GenJob.Where{+stage, _}:
      moved_at(GenJob.settled(stage), native, job)

def rush_steps() -> Nat:
  64n

def rushed(fuel: Nat, job: GenJob.Job, +seed: U32, +since: Nat, +ctx: Ctx) -> Slot:
  match fuel:
    case 0n:
      parked(GenJob.stage(job), seed, since, ctx)
    case 1n+f:
      rushed(f, moved(native_of(ctx), GenJob.stage(job)), seed, since, ctx)

def work(slot: Slot, +ctx: Ctx) -> Slot:
  match slot:
    case Busy{+seed, job, +since}:
      rushed(rush_steps(), job, seed, since, ctx)
    case other:
      other

def worked_all(s: Slots, +ctx: Ctx) -> Slots:
  match s:
    case Leaf{slot}:
      Leaf{work(slot, ctx)}
    case Fork{a, b}:
      x y = worked_all(a, ctx) worked_all(b, ctx)
      Fork{x, y}

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

def halved(xs: List<&1, Slot>, +n: Nat) -> Split:
  split_loop(Nat.div(n, 2n), xs, Nil{})

def grown(+depth: Nat, sp: Split, +nf: Nat, +nb: Nat) -> Slots:
  match depth:
    case 0n:
      match sp:
        case Split{_, back}:
          leaf_of(back)
    case 1n+d:
      match sp:
        case Split{front, back}:
          match front:
            case Nil{}:
              leaf_of(back)
            case Con{x, rest}:
              Fork{grown(d, halved(x <> rest, nf), Nat.div(nf, 2n), Nat.sub(nf, Nat.div(nf, 2n))),
                grown(d, halved(back, nb), Nat.div(nb, 2n), Nat.sub(nb, Nat.div(nb, 2n)))}

# The n slots in a tree whose two halves at every fork hold about as many slots, down to one slot per leaf.
def tree_of(xs: List<&1, Slot>, +n: Nat) -> Slots:
  +half = Nat.div(n, 2n)
  grown(Par.depth_for(n), halved(xs, n), half, Nat.sub(n, half))

def flat(s: Slots) -> List<&1, Slot>:
  match s:
    case Leaf{slot}:
      [slot]
    case Fork{a, b}:
      List.append(&1, Slot, flat(a), flat(b))

def launched(xs: List<&1, Slot>, +ctx: Ctx, acc: List<&1, Slot>) -> IO(List<&1, Slot>):
  match xs:
    case Nil{}:
      IO.pure(List<&1, Slot>, List.reverse(&1, Slot, acc))
    case Con{x, rest}:
      match x:
        case Laying{+seed, job, +l, +since}:
          do IO<List<&1, Slot>>:
            laid : Chan(List<&2, LayoutSpace.Vec>) <- IO.fork(List<&2, LayoutSpace.Vec>, GenLayout.solve(native_of(ctx), l))
            launched(rest, ctx, Waiting{seed, job, laid, since} <> acc)
        case other:
          launched(rest, ctx, other <> acc)

def joined(xs: List<&1, Slot>, acc: List<&1, Slot>) -> IO(List<&1, Slot>):
  match xs:
    case Nil{}:
      IO.pure(List<&1, Slot>, List.reverse(&1, Slot, acc))
    case Con{x, rest}:
      match x:
        case Waiting{+seed, job, laid, +since}:
          do IO<List<&1, Slot>>:
            +ps : List<&2, LayoutSpace.Vec> <- IO.join(List<&2, LayoutSpace.Vec>, laid)
            joined(rest, Busy{seed, GenJob.laid(job, ps), since} <> acc)
        case other:
          joined(rest, other <> acc)

def joined_fed(fed: Fed) -> IO(Fed):
  match fed:
    case Fed{slots, +feed}:
      do IO<Fed>:
        xs : List<&1, Slot> <- joined(slots, Nil{})
        return Fed{xs, feed}

def outcome_name(+outcome: U32) -> String:
  match outcome:
    case 0:
      "world"
    case 1:
      "gaveup"
    case _:
      "crashed"

def saved(+outcome: U32, +path: String, bytes: List<&2, U32>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match outcome:
    case 2:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{(1, "dump: seed crashed, no dump")})
    case _:
      Files.write_bytes("dump: ", path, bytes)

def reported(r: Result<&1, &1, U32 & String, Unit>, +feed: Feed) -> IO(Feed):
  match r feed:
    case Done{_} _:
      IO.pure(Feed, feed)
    case Fail{(+code, +message)} Feed{+next, +left, +busy, +failed}:
      do IO<Feed>:
        Bool.pick(IO(Unit), U32.is_eq(code, 1), IO.pure(Unit, Unit{}), IO.print_err(message))
        return Feed{next, left, busy, (failed + 1 : U32)}

def line(+seed: U32, +ctx: Ctx, +outcome: U32, +count: U32, +ms: Nat) -> String:
  Canon.record("dump", [Canon.number("seed", seed), Canon.field("platform", Bool.pick(String, windows_of(ctx), "windows", "linux")),
    Canon.field("outcome", outcome_name(outcome)), Canon.number("ents", count), Canon.field("ms", Nat.show(ms))])

def written_dump(+seed: U32, +outcome: U32, +count: U32, bytes: List<&2, U32>, +since: Nat, +feed: Feed, +ctx: Ctx) -> IO(Feed):
  do IO<Feed>:
    r : Result<&1, &1, U32 & String, Unit> <- saved(outcome, path_of(ctx, seed), bytes)
    +now : Nat <- IO.now()
    IO.print(line(seed, ctx, outcome, count, Nat.sub(now, since)))
    reported(r, feed)

def refilled(+feed: Feed, +ctx: Ctx, +now: Nat) -> Slot:
  match feed:
    case Feed{+next, +left, _, _}:
      Bool.pick(Slot, Nat.is_eq(left, 0n), Free{}, Busy{next, GenJob.start(next, windows_of(ctx), True{}), now})

def fed_after(+feed: Feed) -> Feed:
  match feed:
    case Feed{+next, +left, +busy, +failed}:
      Bool.pick(Feed, Nat.is_eq(left, 0n), feed, Feed{(next + 1 : U32), Nat.sub(left, 1n), (busy + 1 : U32), failed})

def busy_one(+feed: Feed) -> Feed:
  match feed:
    case Feed{+next, +left, +busy, +failed}:
      Feed{next, left, (busy + 1 : U32), failed}

# Writes the finished dumps (with their lines) and gives the free slots the next seeds, counting the slots in use.
def written(xs: List<&1, Slot>, +feed: Feed, +ctx: Ctx, acc: List<&1, Slot>) -> IO(Fed):
  match xs:
    case Nil{}:
      IO.pure(Fed, Fed{List.reverse(&1, Slot, acc), feed})
    case Con{x, rest}:
      match x:
        case Finished{+seed, +outcome, +count, bytes, +since}:
          do IO<Fed>:
            +after : Feed <- written_dump(seed, outcome, count, bytes, since, feed, ctx)
            +now : Nat <- IO.now()
            written(rest, fed_after(after), ctx, refilled(after, ctx, now) <> acc)
        case Free{}:
          do IO<Fed>:
            +now : Nat <- IO.now()
            written(rest, fed_after(feed), ctx, refilled(feed, ctx, now) <> acc)
        case other:
          written(rest, busy_one(feed), ctx, other <> acc)

def restarted(+feed: Feed) -> Feed:
  match feed:
    case Feed{+next, +left, _, +failed}:
      Feed{next, left, 0, failed}

def ended(+feed: Feed) -> IO(Unit):
  match feed:
    case Feed{_, _, _, +failed}:
      Bool.pick(IO(Unit), U32.is_zero(failed), IO.pure(Unit, Unit{}),
        IO.die(Unit, 1, "dump: " ++ U32.show(failed) ++ " seeds have no dump (crashed, or the dump could not be written)"))

def rounds(fuel: Nat, fed: Fed, +ctx: Ctx) -> IO(Unit):
  match fuel fed:
    case 0n Fed{_, +feed}:
      ended(feed)
    case 1n+k Fed{_, Feed{+next, +left, 0, +failed}}:
      ended(Feed{next, left, 0, failed})
    case 1n+k Fed{slots, +feed}:
      match ctx:
        case Ctx{_, +n}:
          do IO<Unit>:
            laying : List<&1, Slot> <- launched(flat(worked_all(tree_of(slots, n), ctx)), ctx, Nil{})
            IO.sleep(0)
            after : Fed <- written(laying, restarted(feed), ctx, Nil{})
            next : Fed <- joined_fed(after)
            rounds(k, next, ctx)

def free_slots(n: Nat) -> List<&1, Slot>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Free{} <> free_slots(p)

def round_limit() -> Nat:
  Nat.mul(1000000n, 1000000n)

# The slots (seeds in flight): two per thread, so the KK passes of some run while the others' CPU stages do.
def slots_for(+threads: U32, +total: Nat) -> Nat:
  Nat.min(U32.to_nat((threads * 2 : U32)), total)

def started(+q: Args.Dump, +threads: U32) -> IO(Unit):
  match q:
    case Args.Dump{+from, +total, +windows, +native, +out, +folder}:
      +ctx = {Ctx{Args.Dump{from, total, windows, native, out, folder}, slots_for(threads, total)} : Ctx}
      do IO<Unit>:
        first : Fed <- written(free_slots(slots_for(threads, total)), Feed{from, total, 0, 0}, ctx, Nil{})
        rounds(round_limit(), first, ctx)

# world dump SEED [TO] [--platform windows|linux] [--kk native|bend] -o PATH (args start with "dump").
def run(+args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +q : Args.Dump <- IO.pass(Args.Dump, Args.dump_of(args))
    +threads : U32 <- SearchThreads.threads()
    started(q, threads)
