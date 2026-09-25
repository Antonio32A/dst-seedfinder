import Base
import ../rng/pcg.bend as R
import ../trace/canon.bend as CN
import ../worldsim/grid.bend as GR
import ../ocean/ents.bend as OE
import ./generate.bend as GE
import ./job.bend as GJ

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

def stage_line(+seed: U32, +at: GJ.Where, +ms: Nat) -> String:
  match at:
    case GJ.Where{+stage, +a}:
      CN.record("stage", [CN.number("seed", seed), CN.number("a", a), CN.field("name", stage_name(stage)), CN.field("ms", Nat.show(ms))])

def hash_text(+h: GR.Hash) -> String:
  match h:
    case GR.Hash{+hi, +lo}:
      CN.hex64(hi, lo)

def world_fields(got: GR.Grid & GR.Hash, +seed: U32, +rng: R.Rng, +n: U32) -> List<&2, String>:
  (_, +h) = got
  [CN.number("ctr", R.counter(seed, rng)), CN.number("ents", n), CN.field("tiles", hash_text(h))]

def final_fields(world: GJ.Final, +seed: U32) -> List<&2, String>:
  match world:
    case GJ.Final{g, +rng, +ents, _}:
      world_fields(GR.tiles_digest(g), seed, rng, U32.from_nat(List.length(&2, OE.Ent, ents)))

def outcome_fields(job: GJ.Job, +seed: U32) -> List<&2, String>:
  match job:
    case GJ.JWorld{_, +a, world}:
      CN.number("a", a) <> CN.field("outcome", "world") <> final_fields(world, seed)
    case GJ.JDone{_, +a, GJ.Crashed{}}:
      [CN.number("a", a), CN.field("outcome", "crashed")]
    case GJ.JDone{_, +a, _}:
      [CN.number("a", a), CN.field("outcome", "gaveup")]
    case _:
      [CN.field("outcome", "unfinished")]

def summary(job: GJ.Job, +seed: U32, +windows: Bool, +ms: Nat) -> String:
  CN.record("gen", List.append(&2, String, [CN.number("seed", seed), CN.field("platform", platform_name(windows))],
    List.append(&2, String, outcome_fields(job, seed), [CN.field("ms", Nat.show(ms))])))

def print_if(on: Bool, +line: String) -> IO(Unit):
  match on:
    case True{}:
      IO.print(line)
    case False{}:
      IO.pure(Unit, Unit{})

def same(+x: GJ.Where, +y: GJ.Where) -> Bool:
  match x:
    case GJ.Where{+s, +a}:
      match y:
        case GJ.Where{+t, +b}:
          U32.is_eq(s, t) && U32.is_eq(a, b)

# The state between two steps: the job, where it is, and when its current stage started.
type Drive is Type:
  Drive{job: GJ.Job, at: GJ.Where, since: Nat}

type Stepped is Type:
  Going{d: Drive}
  Stopped{line: String}

def stage_of(+at: GJ.Where) -> U32:
  match at:
    case GJ.Where{+stage, _}:
      stage

def decided(final: Bool, job: GJ.Job, +at: GJ.Where, +since: Nat, +seed: U32, +windows: Bool, +native: Bool, +ms: Nat) -> IO(Stepped):
  match final:
    case True{}:
      IO.pure(Stepped, Stopped{summary(job, seed, windows, ms)})
    case False{}:
      do IO<Stepped>:
        next : GJ.Job <- GJ.advance_io(native, job)
        return Going{Drive{next, at, since}}

def stepped(got: GJ.Job & GJ.Where, +times: Bool, +seed: U32, +windows: Bool, +native: Bool, +prev: GJ.Where, +since: Nat, +now: Nat, +start: Nat) -> IO(Stepped):
  (job, +at) = got
  +moved = Bool.not(same(prev, at))
  +final = GJ.settled(stage_of(at))
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
            next : Stepped <- stepped(GJ.stage(job), times, seed, windows, native, at, since, now, start)
            drive(f, next, times, seed, windows, native, start)

# Generates one seed and prints its lines (KK passes from LO.solve: native or kk.bend).
def seed(+seed: U32, +windows: Bool, +times: Bool, +native: Bool) -> IO(Unit):
  do IO<Unit>:
    +start : Nat <- IO.now()
    drive(8192n, Going{Drive{GJ.start(seed, windows), GJ.Where{9, 0}, start}}, times, seed, windows, native, start)

def seeds(n: Nat, +from: U32, +windows: Bool, +times: Bool, +native: Bool) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        seed(from, windows, times, native)
        seeds(p, (from + 1 : U32), windows, times, native)
