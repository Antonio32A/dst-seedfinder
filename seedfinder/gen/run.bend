import Base
import ../rng/pcg.bend as Pcg
import ../trace/canon.bend as Canon
import ../storygen/graph.bend as StoryGraph
import ../worldsim/grid.bend as Grid
import ../ocean/ents.bend as OceanEnts
import ./generate.bend as Generate
import ./job.bend as GenJob
import ./cave_dump.bend as CaveDump
import ./cave_maze.bend as CaveMaze
import ../worldsim/points.bend as Points
import ./cave_custom.bend as CaveCustom
import ./graph.bend as GenGraph

# `seedfinder gen`: runs the job state machine of each seed to its world, one line per seed, and with `times` one
# line per stage of every attempt:
#   stage seed=S a=A name=NAME ms=T
#   gen seed=S platform=P a=A outcome=world|gaveup|crashed ctr=C ents=N tiles=H ms=T
# (ctr, ents and tiles: the RNG counter at the end of Generate, the savedata.ents count and the encoded tile map's
# digest of the world attempt).
# The caves shard runs the whole worldgen and ends like the forest, with `shard=caves` after the platform. With `dump`
# bits 1 or 2 it stops at the first attempt's custom tile pass (the tile map right before the mazes) instead:
#   gen seed=S platform=P shard=caves a=A outcome=tiled ctr=C nodes=N w=W tiles=H ms=T
# (ctr: the RNG counter after the custom tile pass; tiles: the digest of the tile map after it), and `dump`
# adds records for the attempt: bit 1 the `tiles` record of that tile map, bit 2 its story graph as JSON, bit 4 the entities
# of the Labyrinth and Maze passes with the stream counters around each maze engine call (JSON), bit 8 the `tiles` record after
# them. `draws` starts
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
    case 11:
      "mazed"
    case 12:
      "post"
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

def kept_lines(got: Grid.Grid & String) -> Grid.Grid & List<&2, String>:
  (g, +line) = got
  (g, [line])

def tiles_dumped(off: Bool, +seed: U32, +a: U32, g: Grid.Grid) -> Grid.Grid & List<&2, String>:
  match off:
    case True{}:
      (g, Nil{})
    case False{}:
      kept_lines(CaveDump.tiles_kept(seed, a, g, "before_mazes"))

def dump_tiles(bits: U32, +seed: U32, +a: U32, g: Grid.Grid) -> Grid.Grid & List<&2, String>:
  tiles_dumped(U32.is_zero((bits .&. 1 : U32)), seed, a, g)

def dump_story(bits: U32, +seed: U32, +a: U32, +s: StoryGraph.St) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_zero((bits .&. 2 : U32)), Nil{}, [CaveDump.story_json(seed, a, s)])

def marked_lines(m: CaveMaze.Mazed, +marks: List<&2, Pcg.Rng>, +bits: U32, +seed: U32, +a: U32) -> List<&2, String>:
  match m:
    case CaveMaze.Mazed{g, +rng, +ents}:
      List.append(&2, String, Bool.pick(List<&2, String>, U32.is_zero((bits .&. 4 : U32)), Nil{}, [CaveDump.mazes_json(seed, a, marks, rng, ents)]),
        Bool.pick(List<&2, String>, U32.is_zero((bits .&. 8 : U32)), Nil{}, [CaveDump.tiles_line(seed, a, g, "after_mazes")]))

def mazed_lines(m: CaveMaze.Marked, +bits: U32, +seed: U32, +a: U32) -> List<&2, String>:
  match m:
    case CaveMaze.Marked{mazed, +marks}:
      marked_lines(mazed, marks, bits, seed, a)

def mazes_run(off: Bool, +bits: U32, +seed: U32, +a: U32, +c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, g: Grid.Grid, +rng: Pcg.Rng, placed: List<&2, CaveCustom.Placed>, +sites: Points.Sites) -> List<&2, String>:
  match off:
    case True{}:
      Nil{}
    case False{}:
      mazed_lines(CaveMaze.run_marked(c, s, k, w, g, rng, placed, sites), bits, seed, a)

def mazes_of(+bits: U32, +seed: U32, +a: U32, +c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, g: Grid.Grid, +rng: Pcg.Rng, placed: List<&2, CaveCustom.Placed>, +sites: Points.Sites) -> List<&2, String>:
  mazes_run(U32.is_zero((bits .&. 12 : U32)), bits, seed, a, c, s, k, w, g, rng, placed, sites)

def tiled_record(+seed: U32, +a: U32, +s: StoryGraph.St, +w: U32, +rng: Pcg.Rng, +h: Grid.Hash, +windows: Bool, +ms: Nat) -> String:
  Canon.record("gen", List.append(&2, String, [Canon.number("seed", seed), Canon.field("platform", platform_name(windows)), Canon.field("shard", "caves")],
    List.append(&2, String, tiled_fields(seed, a, s, w, rng, h), [Canon.field("ms", Nat.show(ms))])))

def tiled_lines(got: Grid.Grid & List<&2, String>, +head: String, +story: List<&2, String>, +bits: U32, +seed: U32, +a: U32, +c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +rng: Pcg.Rng, placed: List<&2, CaveCustom.Placed>, +sites: Points.Sites) -> String:
  (g, +tiles) = got
  String.join(head <> List.append(&2, String, story, List.append(&2, String, tiles, mazes_of(bits, seed, a, c, s, k, w, g, rng, placed, sites))), "\n")

def tiled_summary(got: Grid.Grid & Grid.Hash, +seed: U32, +a: U32, +c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +rng: Pcg.Rng, placed: List<&2, CaveCustom.Placed>, +sites: Points.Sites, +o: Options, +ms: Nat) -> String:
  (g, +h) = got
  match o:
    case Options{+windows, _, _, _, +dump, _}:
      tiled_lines(dump_tiles(dump, seed, a, g), tiled_record(seed, a, s, w, rng, h, windows, ms), dump_story(dump, seed, a, s), dump, seed, a, c, s, k, w, rng, placed, sites)

def caves_of(+o: Options) -> Bool:
  match o:
    case Options{_, _, _, +caves, _, _}:
      caves

def dump_of(+o: Options) -> U32:
  match o:
    case Options{_, _, _, _, +dump, _}:
      dump

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

def shard_fields(caves: Bool) -> List<&2, String>:
  Bool.pick(List<&2, String>, caves, [Canon.field("shard", "caves")], Nil{})

def line_summary(job: GenJob.Job, +seed: U32, +windows: Bool, +caves: Bool, +ms: Nat) -> String:
  Canon.record("gen", List.append(&2, String, [Canon.number("seed", seed), Canon.field("platform", platform_name(windows))],
    List.append(&2, String, shard_fields(caves), List.append(&2, String, outcome_fields(job, seed), [Canon.field("ms", Nat.show(ms))]))))

def summary(job: GenJob.Job, +seed: U32, +o: Options, +ms: Nat) -> String:
  match job:
    case GenJob.JTiled{+c, +a, +s, +k, +w, grid, +rng, placed, +sites}:
      tiled_summary(Grid.tiles_digest(grid), seed, a, c, s, k, w, rng, placed, sites, o, ms)
    case other:
      line_summary(other, seed, platform_of(o), caves_of(o), ms)

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
  +final = GenJob.settled(stage_of(at)) || (U32.is_eq(stage_of(at), 10) && Bool.not(U32.is_zero((dump_of(o) .&. 3 : U32))))
  do IO<Stepped>:
    print_if(times_of(o) && moved && U32.is_ne(stage_of(prev), 9), stage_line(seed, prev, Nat.sub(now, since)))
    decided(final, job, at, Bool.pick(Nat, moved, now, since), seed, o, Nat.sub(now, start))

def job_of(caves: Bool, +seed: U32, +o: Options) -> GenJob.Job:
  match caves:
    case True{}:
      match o:
        case Options{+windows, _, _, _, _, +draws}:
          GenJob.start_caves(seed, windows, draws)
    case False{}:
      GenJob.start(seed, platform_of(o), False{})

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
