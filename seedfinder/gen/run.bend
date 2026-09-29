import Base
import ../rng/pcg.bend as Pcg
import ../trace/canon.bend as Canon
import ../storygen/graph.bend as StoryGraph
import ../worldsim/grid.bend as Grid
import ../ocean/ents.bend as OceanEnts
import ./generate.bend as Generate
import ./job.bend as GenJob
import ./cave_dump.bend as CaveDump

# `seedfinder gen`: runs the job state machine of each seed to its world, one line per seed, and with `times` one
# line per stage of every attempt:
#   stage seed=S a=A name=NAME ms=T
#   gen seed=S platform=P a=A outcome=world|gaveup|crashed ctr=C ents=N tiles=H ms=T
# (ctr, ents and tiles: the RNG counter at the end of Generate, the savedata.ents count and the encoded tile map's
# digest of the world attempt).
# The caves shard is ported up to the custom tile pass (the tile map right before the mazes): its attempts end at stage
# `tiled` with
#   gen seed=S platform=P shard=caves a=A outcome=tiled ctr=C nodes=N w=W tiles=H ms=T
# (ctr: the RNG counter after the custom tile pass; tiles: the digest of the tile map after it), and `dump`
# adds records for the attempt: bit 1 the `tiles` record of that tile map, bit 2 its story graph as JSON. `draws` starts
# the attempt that many draws into the seed's stream (the counter of a real attempt's generate_begin), for checking the
# attempts after the first; that also takes the entrance list pick as made.

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
    case 10:
      "tiled"
    case _:
      "done"

# What `gen` was asked: the platform, per-stage timing, the KK engine, the shard and the caves' dump bits and start.
type Options is Data:
  Options{windows: Bool, times: Bool, native: Bool, caves: Bool, dump: U32, draws: U32}

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
    case GenJob.Final{g, +rng, +ents, _, _, _, _}:
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

def tiled_fields(+seed: U32, +a: U32, +s: StoryGraph.St, +w: U32, +rng: Pcg.Rng, +h: Grid.Hash) -> List<&2, String>:
  [Canon.number("a", a), Canon.field("outcome", "tiled"), Canon.number("ctr", Pcg.counter(seed, rng)),
    Canon.number("nodes", StoryGraph.get(s, StoryGraph.s_nodes())), Canon.number("w", w), Canon.field("tiles", hash_text(h))]

def dump_tiles(bits: U32, +seed: U32, +a: U32, g: Grid.Grid) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_zero((bits .&. 1 : U32)), Nil{}, [CaveDump.tiles_line(seed, a, g, "before_mazes")])

def dump_story(bits: U32, +seed: U32, +a: U32, +s: StoryGraph.St) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_zero((bits .&. 2 : U32)), Nil{}, [CaveDump.story_json(seed, a, s)])

def tiled_record(+seed: U32, +a: U32, +s: StoryGraph.St, +w: U32, +rng: Pcg.Rng, +h: Grid.Hash, +windows: Bool, +ms: Nat) -> String:
  Canon.record("gen", List.append(&2, String, [Canon.number("seed", seed), Canon.field("platform", platform_name(windows)), Canon.field("shard", "caves")],
    List.append(&2, String, tiled_fields(seed, a, s, w, rng, h), [Canon.field("ms", Nat.show(ms))])))

def tiled_summary(got: Grid.Grid & Grid.Hash, +seed: U32, +a: U32, +s: StoryGraph.St, +w: U32, +rng: Pcg.Rng, +o: Options, +ms: Nat) -> String:
  (g, +h) = got
  match o:
    case Options{+windows, _, _, _, +dump, _}:
      String.join(tiled_record(seed, a, s, w, rng, h, windows, ms) <> List.append(&2, String, dump_story(dump, seed, a, s), dump_tiles(dump, seed, a, g)), "\n")

def platform_of(+o: Options) -> Bool:
  match o:
    case Options{+windows, _, _, _, _, _}:
      windows

def native_of(+o: Options) -> Bool:
  match o:
    case Options{_, _, +native, _, _, _}:
      native

def times_of(+o: Options) -> Bool:
  match o:
    case Options{_, +times, _, _, _, _}:
      times

def line_summary(job: GenJob.Job, +seed: U32, +windows: Bool, +ms: Nat) -> String:
  Canon.record("gen", List.append(&2, String, [Canon.number("seed", seed), Canon.field("platform", platform_name(windows))],
    List.append(&2, String, outcome_fields(job, seed), [Canon.field("ms", Nat.show(ms))])))

def summary(job: GenJob.Job, +seed: U32, +o: Options, +ms: Nat) -> String:
  match job:
    case GenJob.JTiled{_, +a, +s, _, +w, grid, +rng, _, _}:
      tiled_summary(Grid.tiles_digest(grid), seed, a, s, w, rng, o, ms)
    case other:
      line_summary(other, seed, platform_of(o), ms)

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

def decided(final: Bool, job: GenJob.Job, +at: GenJob.Where, +since: Nat, +seed: U32, +o: Options, +ms: Nat) -> IO(Stepped):
  match final:
    case True{}:
      IO.pure(Stepped, Stopped{summary(job, seed, o, ms)})
    case False{}:
      do IO<Stepped>:
        next : GenJob.Job <- GenJob.advance_io(native_of(o), job)
        return Going{Drive{next, at, since}}

def stepped(got: GenJob.Job & GenJob.Where, +seed: U32, +o: Options, +prev: GenJob.Where, +since: Nat, +now: Nat, +start: Nat) -> IO(Stepped):
  (job, +at) = got
  +moved = Bool.not(same(prev, at))
  +final = GenJob.settled(stage_of(at))
  do IO<Stepped>:
    print_if(times_of(o) && moved && (stage_of(prev) < 9 : U32), stage_line(seed, prev, Nat.sub(now, since)))
    decided(final, job, at, Bool.pick(Nat, moved, now, since), seed, o, Nat.sub(now, start))

def job_of(caves: Bool, +seed: U32, +o: Options) -> GenJob.Job:
  match caves:
    case True{}:
      match o:
        case Options{+windows, _, _, _, _, +draws}:
          GenJob.start_caves(seed, windows, draws)
    case False{}:
      GenJob.start(seed, platform_of(o), False{})

def caves_of(+o: Options) -> Bool:
  match o:
    case Options{_, _, _, +caves, _, _}:
      caves

def drive(fuel: Nat, st: Stepped, +seed: U32, +o: Options, +start: Nat) -> IO(Unit):
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
            next : Stepped <- stepped(GenJob.stage(job), seed, o, at, since, now, start)
            drive(f, next, seed, o, start)

# Generates one seed and prints its lines (KK passes from GenLayout.solve: native or kk.bend).
def seed(+seed: U32, +o: Options) -> IO(Unit):
  do IO<Unit>:
    +start : Nat <- IO.now()
    drive(8192n, Going{Drive{job_of(caves_of(o), seed, o), GenJob.Where{9, 0}, start}}, seed, o, start)

def seeds(n: Nat, +from: U32, +o: Options) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        seed(from, o)
        seeds(p, (from + 1 : U32), o)
