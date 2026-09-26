import Base
import ../rng/pcg.bend as Pcg
import ../trace/canon.bend as Canon
import ../worldsim/grid.bend as Grid
import ../ocean/ents.bend as OceanEnts
import ./generate.bend as Generate
import ./job.bend as GenJob

# `seedfinder gen`: runs the job state machine of each seed to its world, one line per seed, and with `times` one
# line per stage of every attempt:
#   stage seed=S a=A name=NAME ms=T
#   gen seed=S platform=P a=A outcome=world|gaveup|crashed ctr=C ents=N tiles=H ms=T
# (ctr, ents and tiles: the RNG counter at the end of Generate, the savedata.ents count and the encoded tile map's
# digest of the world attempt).

def stage_name(+stage: U32) -> String:
  match stage:
    case 0:
      "start"
    case 1:
      "kk1"
    case 2:
      "kk2"
    case 3:
      "commit"
    case 4:
      "tiles"
    case 5:
      "land"
    case 6:
      "ocean"
    case 7:
      "world"
    case _:
      "done"

def platform_name(+windows: Bool) -> String:
  Bool.pick(String, windows, "windows", "linux")

def stage_line(+seed: U32, +at: GenJob.Where, +ms: Nat) -> String:
  match at:
    case GenJob.Where{+stage, +a}:
      Canon.record("stage", [Canon.number("seed", seed), Canon.number("a", a), Canon.field("name", stage_name(stage)), Canon.field("ms", Nat.show(ms))])

def hash_text(+h: Grid.Hash) -> String:
  match h:
    case Grid.Hash{+hi, +lo}:
      Canon.hex64(hi, lo)

def world_fields(got: Grid.Grid & Grid.Hash, +seed: U32, +rng: Pcg.Rng, +n: U32) -> List<&2, String>:
  (_, +h) = got
  [Canon.number("ctr", Pcg.counter(seed, rng)), Canon.number("ents", n), Canon.field("tiles", hash_text(h))]

def final_fields(world: GenJob.Final, +seed: U32) -> List<&2, String>:
  match world:
    case GenJob.Final{g, +rng, +ents, _}:
      world_fields(Grid.tiles_digest(g), seed, rng, U32.from_nat(List.length(&2, OceanEnts.Ent, ents)))

def outcome_fields(job: GenJob.Job, +seed: U32) -> List<&2, String>:
  match job:
    case GenJob.JWorld{_, +a, world}:
      Canon.number("a", a) <> Canon.field("outcome", "world") <> final_fields(world, seed)
    case GenJob.JDone{_, +a, GenJob.Crashed{}}:
      [Canon.number("a", a), Canon.field("outcome", "crashed")]
    case GenJob.JDone{_, +a, _}:
      [Canon.number("a", a), Canon.field("outcome", "gaveup")]
    case _:
      [Canon.field("outcome", "unfinished")]

def summary(job: GenJob.Job, +seed: U32, +windows: Bool, +ms: Nat) -> String:
  Canon.record("gen", List.append(&2, String, [Canon.number("seed", seed), Canon.field("platform", platform_name(windows))],
    List.append(&2, String, outcome_fields(job, seed), [Canon.field("ms", Nat.show(ms))])))

def print_if(on: Bool, +line: String) -> IO(Unit):
  match on:
    case True{}:
      IO.print(line)
    case False{}:
      IO.pure(Unit, Unit{})

def same(+x: GenJob.Where, +y: GenJob.Where) -> Bool:
  match x:
    case GenJob.Where{+s, +a}:
      match y:
        case GenJob.Where{+t, +b}:
          U32.is_eq(s, t) && U32.is_eq(a, b)

# The state between two steps: the job, where it is, and when its current stage started.
type Drive is Type:
  Drive{job: GenJob.Job, at: GenJob.Where, since: Nat}

type Stepped is Type:
  Going{d: Drive}
  Stopped{line: String}

def stage_of(+at: GenJob.Where) -> U32:
  match at:
    case GenJob.Where{+stage, _}:
      stage

def decided(final: Bool, job: GenJob.Job, +at: GenJob.Where, +since: Nat, +seed: U32, +windows: Bool, +native: Bool, +ms: Nat) -> IO(Stepped):
  match final:
    case True{}:
      IO.pure(Stepped, Stopped{summary(job, seed, windows, ms)})
    case False{}:
      do IO<Stepped>:
        next : GenJob.Job <- GenJob.advance_io(native, job)
        return Going{Drive{next, at, since}}

def stepped(got: GenJob.Job & GenJob.Where, +times: Bool, +seed: U32, +windows: Bool, +native: Bool, +prev: GenJob.Where, +since: Nat, +now: Nat, +start: Nat) -> IO(Stepped):
  (job, +at) = got
  +moved = Bool.not(same(prev, at))
  +final = GenJob.settled(stage_of(at))
  do IO<Stepped>:
    print_if(times && moved && (stage_of(prev) < 9 : U32), stage_line(seed, prev, Nat.sub(now, since)))
    decided(final, job, at, Bool.pick(Nat, moved, now, since), seed, windows, native, Nat.sub(now, start))

def drive(fuel: Nat, st: Stepped, +times: Bool, +seed: U32, +windows: Bool, +native: Bool, +start: Nat) -> IO(Unit):
  match fuel:
    case 0n:
      IO.print("gen: out of fuel")
    case 1n+f:
      match st:
        case Stopped{+line}:
          IO.print(line)
        case Going{Drive{job, +at, +since}}:
          do IO<Unit>:
            +now : Nat <- IO.now()
            next : Stepped <- stepped(GenJob.stage(job), times, seed, windows, native, at, since, now, start)
            drive(f, next, times, seed, windows, native, start)

# Generates one seed and prints its lines (KK passes from GenLayout.solve: native or kk.bend).
def seed(+seed: U32, +windows: Bool, +times: Bool, +native: Bool) -> IO(Unit):
  do IO<Unit>:
    +start : Nat <- IO.now()
    drive(8192n, Going{Drive{GenJob.start(seed, windows), GenJob.Where{9, 0}, start}}, times, seed, windows, native, start)

def seeds(n: Nat, +from: U32, +windows: Bool, +times: Bool, +native: Bool) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        seed(from, windows, times, native)
        seeds(p, (from + 1 : U32), windows, times, native)
