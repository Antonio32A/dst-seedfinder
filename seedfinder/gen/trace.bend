import Base
import ../rng/pcg.bend as Pcg
import ../f64/repr.bend as F64Repr
import ../trace/canon.bend as Canon
import ../storygen/graph.bend as StoryGraph
import ../storygen/trace.bend as StoryTrace
import ../worldsim/layout/space.bend as LayoutSpace
import ../worldsim/voronoi/polygon.bend as VoronoiPolygon
import ../worldsim/voronoi/records.bend as VoronoiRecords
import ../worldsim/commit.bend as Commit
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/world.bend as TileWorld
import ../worldsim/tiles/convert.bend as TileConvert
import ../worldsim/tiles/separate.bend as TileSeparate
import ../worldsim/tiles/connect.bend as TileConnect
import ../worldsim/tiles/roads.bend as TileRoads
import ../populate/entities.bend as Entities
import ../populate/state.bend as PopulateState
import ../populate/trace.bend as PopulateTrace
import ./graph.bend as GenGraph
import ./generate.bend as Generate
import ./job.bend as GenJob
import ../filters/dump.bend as FilterDump

# The `gen` trace stage: forest_map.Generate from the seed alone, every attempt, through the job state machine
# (gen/job.bend) with M10's ocean between attempts. On entering each job stage it prints the oracle's records of what
# that stage's data determines (recomputing the intermediate maps from it with the same pure stage functions):
# storygen `attempt call lua child link` (to WorldGen_Commit), graph `vertex outedge` (k counts the out-edges of the
# whole graph), the last KK run's `kkpos` of each pass, `poly ppt pnb` and `digest` (i=0, the diff drops the call
# index) after VoronoiPass(100), VoronoiPass(50), Commit, ConvertToTileMap and the tile stages up to DrawRoads, the
# populate stage's records without gpfs_perm, and two Bend-only kinds: `landed a ctr n tiles flags topo` (the job's
# land_done state) and `outcome a kind`.

type Tr is Data:
  Tr{seed: U32, stage: U32, a: U32, ctr: U32, chunks: List<&2, List<&2, String>>}

type Step is Type:
  Go{job: GenJob.Job}
  Stop{}

def handles(+stage: String) -> Bool:
  String.eq(stage, "gen")

def hash_text(+h: Grid.Hash) -> String:
  match h:
    case Grid.Hash{+hi, +lo}:
      Canon.hex64(hi, lo)

def f64_text(+x: F64Repr.F64) -> String:
  match x:
    case F64Repr.F64{+hi, +lo}:
      Canon.hex64(hi, lo)

def site_fold(ss: List<&2, VoronoiPolygon.SiteIn>, h: Grid.Hash) -> Grid.Hash:
  match ss:
    case Nil{}:
      h
    case Con{VoronoiPolygon.SiteIn{+x, +y, _, _, _}, rest}:
      site_fold(rest, Grid.fnv_u32(Grid.fnv_u32(h, x), y))

def points_fold(ps: List<&2, VoronoiPolygon.P32>, h: Grid.Hash) -> Grid.Hash:
  match ps:
    case Nil{}:
      h
    case Con{VoronoiPolygon.P32{+x, +y}, rest}:
      points_fold(rest, Grid.fnv_u32(Grid.fnv_u32(h, x), y))

def poly_fold(ps: List<&2, VoronoiPolygon.Poly>, h: Grid.Hash) -> Grid.Hash:
  match ps:
    case Nil{}:
      h
    case Con{VoronoiPolygon.Poly{+pts, _, _, _, _}, rest}:
      poly_fold(rest, points_fold(pts, Grid.fnv_u32(h, U32.from_nat(List.length(&2, VoronoiPolygon.P32, pts)))))

def site_count(+ss: List<&2, VoronoiPolygon.SiteIn>) -> U32:
  U32.from_nat(List.length(&2, VoronoiPolygon.SiteIn, ss))

def zero_hash() -> Grid.Hash:
  Grid.Hash{0, 0}

def digest_line(+a: U32, +at: String, +ctr: U32, +w: U32, +sites: List<&2, VoronoiPolygon.SiteIn>, +polys: List<&2, VoronoiPolygon.Poly>, +tiles: Grid.Hash, +flags: Grid.Hash) -> String:
  Canon.record("digest", [Canon.number("a", a), Canon.field("at", Canon.quoted(at)), Canon.number("i", 0), Canon.number("ctr", ctr), Canon.number("w", w),
    Canon.number("h", w), Canon.number("sites", site_count(sites)), Canon.field("site_hash", hash_text(site_fold(sites, Grid.fnv_offset()))),
    Canon.field("poly_hash", hash_text(poly_fold(polys, Grid.fnv_offset()))), Canon.field("tiles", hash_text(tiles)),
    Canon.field("flags", hash_text(flags)), Canon.field("node_ids", hash_text(zero_hash()))])

def names_of(vs: List<&2, U32>, +s: StoryGraph.St) -> List<&2, String>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      StoryGraph.node_name(s, x) <> names_of(rest, s)

def poly_loop(ss: List<&2, VoronoiPolygon.SiteIn>, ps: List<&2, VoronoiPolygon.Poly>, +head: List<&2, String>, +names: List<&2, String>, +i: U32) -> List<&2, String>:
  match ss ps:
    case Con{+site, rest} Con{+p, prest}:
      List.append(&2, String, VoronoiRecords.site_poly_lines(p, site, head, names, i), poly_loop(rest, prest, head, names, (i + 1 : U32)))
    case _ _:
      Nil{}

def poly_lines(+a: U32, +at: String, +ss: List<&2, VoronoiPolygon.SiteIn>, +ps: List<&2, VoronoiPolygon.Poly>, +names: List<&2, String>) -> List<&2, String>:
  poly_loop(ss, ps, [Canon.number("a", a), Canon.field("at", Canon.quoted(at))], names, 0)

def build_lines(+a: U32, +at: String, +ctr: U32, +w: U32, +ss: List<&2, VoronoiPolygon.SiteIn>, +ps: List<&2, VoronoiPolygon.Poly>, +names: List<&2, String>) -> List<&2, String>:
  digest_line(a, at, ctr, w, ss, ps, zero_hash(), zero_hash()) <> poly_lines(a, at, ss, ps, names)

def vertex_lines(vs: List<&2, U32>, +s: StoryGraph.St, +a: U32, +g: U32, +v: U32) -> List<&2, String>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      Canon.record("vertex", [Canon.number("a", a), Canon.number("g", g), Canon.number("v", v), Canon.field("name", Canon.quoted(StoryGraph.node_name(s, x)))])
        <> vertex_lines(rest, s, a, g, (v + 1 : U32))

def target_lines(ts: List<&2, U32>, +a: U32, +g: U32, +v: U32, +k: U32) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      Canon.record("outedge", [Canon.number("a", a), Canon.number("g", g), Canon.number("v", v), Canon.number("k", k), Canon.number("to", t),
        Canon.field("w", "3ff0000000000000")]) <> target_lines(rest, a, g, v, (k + 1 : U32))

def outedge_lines(rows: List<&2, List<&2, U32>>, +a: U32, +g: U32, +v: U32, +k: U32) -> List<&2, String>:
  match rows:
    case Nil{}:
      Nil{}
    case Con{+ts, rest}:
      List.append(&2, String, target_lines(ts, a, g, v, k),
        outedge_lines(rest, a, g, (v + 1 : U32), (k + U32.from_nat(List.length(&2, U32, ts)) : U32)))

def graph_lines(+s: StoryGraph.St, +k: GenGraph.Klei, +a: U32, +g: U32) -> List<&2, String>:
  List.append(&2, String, vertex_lines(GenGraph.vertices_of(k), s, a, g, 0), outedge_lines(GenGraph.adjacency(GenGraph.count_of(k), GenGraph.edges_of(k)), a, g, 0, 0))

def kkpos_lines(ps: List<&2, LayoutSpace.Vec>, +a: U32, +g: U32, +run: U32, +v: U32) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{LayoutSpace.Vec{+x, +y}, rest}:
      Canon.record("kkpos", [Canon.number("a", a), Canon.number("g", g), Canon.number("run", run), Canon.number("v", v), Canon.field("x", f64_text(x)),
        Canon.field("y", f64_text(y))]) <> kkpos_lines(rest, a, g, run, (v + 1 : U32))

def kept_if(keep: Bool, +v: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{}:
      v <> rest
    case False{}:
      rest

def pass_calls(evs: List<&2, StoryGraph.Ev>, +seed: U32) -> List<&2, U32>:
  match evs:
    case Nil{}:
      Nil{}
    case Con{+ev, rest}:
      match ev:
        case StoryGraph.ECall{+m, +rng}:
          kept_if(U32.is_eq(m, 7), Pcg.counter(seed, rng), pass_calls(rest, seed))
        case _:
          pass_calls(rest, seed)

# The draw counter at the story's n-th WorldGen_VoronoiPass call (n from 0).
def pass_counter(+s: StoryGraph.St, +n: Nat, +seed: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, pass_calls(List.reverse(&2, StoryGraph.Ev, StoryGraph.log_of(s)), seed), n), 0)

def story_lines(+st: Tr, +s: StoryGraph.St, +a: U32) -> List<&2, String>:
  match st:
    case Tr{+seed, _, _, +ctr, _}:
      StoryTrace.story_lines(s, seed, U32.show(a), ctr)

def seed_of(+st: Tr) -> U32:
  match st:
    case Tr{+seed, _, _, _, _}:
      seed

def first_lines(+st: Tr, +s: StoryGraph.St, +k: GenGraph.Klei, +a: U32, +first: Generate.Pass) -> List<&2, String>:
  +names = names_of(GenGraph.vertices_of(k), s)
  +ctr = pass_counter(s, 0n, seed_of(st))
  List.append(&2, String, story_lines(st, s, a), List.append(&2, String, graph_lines(s, k, a, 2),
    List.append(&2, String, kkpos_lines(Generate.pass_positions(first), a, 1, 100, 0),
      build_lines(a, "VoronoiPass(100)", ctr, Generate.world_size(), Generate.pass_site_list(first), Generate.pass_polys(first), names))))

def commit_lines(cm: Commit.Committed, +ctr: U32, +a: U32, +names: List<&2, String>) -> List<&2, String>:
  match cm:
    case Commit.Committed{+size, +sites, _, cells}:
      build_lines(a, "Commit", ctr, size, sites, Generate.cells_polys(cells), names)

def second_lines(+st: Tr, +c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +a: U32, +second: Generate.Pass) -> List<&2, String>:
  +names = names_of(GenGraph.vertices_of(k), s)
  +seed = seed_of(st)
  List.append(&2, String, kkpos_lines(Generate.pass_positions(second), a, 2, 50, 0),
    List.append(&2, String, build_lines(a, "VoronoiPass(50)", pass_counter(s, 1n, seed), Generate.world_size(), Generate.pass_site_list(second), Generate.pass_polys(second), names),
      commit_lines(Generate.commit(c, second), Pcg.counter(seed, StoryGraph.rng_of(s)), a, names)))

# A tile digest: the counter after ConvertToTileMap, and the flags with the variant draws from the RNG before it.
type Tiles is Type:
  Tiles{g: Grid.Grid, lines: List<&2, String>}

type At is Data:
  At{a: U32, ctr: U32, w: U32, sites: List<&2, VoronoiPolygon.SiteIn>, polys: List<&2, VoronoiPolygon.Poly>, rng: Pcg.Rng}

def flags_hashed(got: Grid.Grid & Grid.Hash, +at: At, +name: String, +tiles: Grid.Hash, +lines: List<&2, String>) -> Tiles:
  (g, +flags) = got
  match at:
    case At{+a, +ctr, +w, +sites, +polys, _}:
      Tiles{g, digest_line(a, name, ctr, w, sites, polys, tiles, flags) <> lines}

def tiles_hashed(got: Grid.Grid & Grid.Hash, +at: At, +name: String, +lines: List<&2, String>) -> Tiles:
  (g, +tiles) = got
  match at:
    case At{_, _, _, _, _, +rng}:
      flags_hashed(Grid.flags_digest(g, rng), at, name, tiles, lines)

def tile_digest(t: Tiles, +at: At, +name: String) -> Tiles:
  match t:
    case Tiles{g, +lines}:
      tiles_hashed(Grid.tiles_digest(g), at, name, lines)

def separated(t: Tiles, +w: TileWorld.World) -> Tiles:
  match t:
    case Tiles{g, +lines}:
      Tiles{TileSeparate.separate(w, g), lines}

def forced(t: Tiles, +w: TileWorld.World, +isl: TileConnect.Islands) -> Tiles:
  match t:
    case Tiles{g, +lines}:
      Tiles{TileConnect.force(w, isl, g), lines}

def roads_drawn(t: Tiles, +windows: Bool, +w: TileWorld.World, +isl: TileConnect.Islands) -> Tiles:
  match t:
    case Tiles{g, +lines}:
      Tiles{TileRoads.draw_roads(windows, TileRoads.roads(windows, w, isl), g), lines}

def tiles_lines(t: Tiles) -> List<&2, String>:
  match t:
    case Tiles{_, +lines}:
      List.reverse(&2, String, lines)

# ConvertToTileMap's paint, SeparateIslands, ForceConnectivity and DrawRoads as Generate.tile_grid runs them, with a digest
# after each.
def grid_lines(+windows: Bool, +w: TileWorld.World, +at: At) -> List<&2, String>:
  +isl = TileConnect.islands(w, False{})
  t0 = tile_digest(Tiles{TileConvert.paint(w, TileConvert.site_tiles(w)), Nil{}}, at, "ConvertToTileMap")
  t1 = tile_digest(separated(t0, w), at, "SeparateIslands")
  t2 = tile_digest(forced(t1, w, isl), at, "ForceConnectivity")
  tiles_lines(tile_digest(roads_drawn(t2, windows, w, isl), at, "DrawRoads"))

def tiles_world_lines(+windows: Bool, +names: List<&2, String>, +world: TileWorld.World, +at: At) -> List<&2, String>:
  match at:
    case At{+a, _, _, +centred, +polys, _}:
      List.append(&2, String, grid_lines(windows, world, at), poly_lines(a, "ConvertToTileMap", centred, polys, names))

def tiles_polys_lines(+st: Tr, +c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +a: U32, +w: U32, +centred: List<&2, VoronoiPolygon.SiteIn>, +polys: List<&2, VoronoiPolygon.Poly>, cells: VoronoiPolygon.Cells) -> List<&2, String>:
  tiles_world_lines(Generate.windows_of(c), names_of(GenGraph.vertices_of(k), s), Generate.tile_world(s, k, w, centred, cells),
    At{a, Pcg.counter(seed_of(st), Generate.rng_after_tiles(s, w)), w, centred, polys, StoryGraph.rng_of(s)})

def tiles_stage_lines(+st: Tr, +c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +a: U32, +size: U32, +sites: List<&2, VoronoiPolygon.SiteIn>) -> List<&2, String>:
  tiles_polys_lines(st, c, s, k, a, Generate.tile_size(size), Generate.tile_centred(size, sites), Generate.cells_polys(Generate.tile_build(c, size, sites)), Generate.tile_build(c, size, sites))

def unshuffled(evs: List<&2, PopulateState.Ev>) -> List<&2, PopulateState.Ev>:
  match evs:
    case Nil{}:
      Nil{}
    case Con{+ev, rest}:
      match ev:
        case PopulateState.EPoints{+node, +n, +before, +after, _, +kept}:
          PopulateState.EPoints{node, n, before, after, Nil{}, kept} <> unshuffled(rest)
        case _:
          ev <> unshuffled(rest)

def land_events(l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      PopulateState.Land{g, rng, ents, unshuffled(events)}

def grid_only(got: Grid.Grid & List<&2, List<&2, TileWorld.Point>>) -> Grid.Grid:
  (g, _) = got
  g

def land_lines(+st: Tr, +c: Generate.Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +a: U32, +w: U32, +world: TileWorld.World, +lists: List<&2, List<&2, U32>>, +sites: Points.Sites) -> List<&2, String>:
  PopulateTrace.land_lines(land_events(Generate.land(Generate.land_context(c, s, k, sites, w, True{}), grid_only(Generate.tile_grid(Generate.windows_of(c), world, lists)), w)),
    PopulateTrace.Out{seed_of(st), U32.show(a), w, w, s, 0, 0, 0, 0, 0, 0})

def landed_flags(got: Grid.Grid & Grid.Hash, +st: Tr, +a: U32, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +s: StoryGraph.St, +w: U32, +roads: List<&2, List<&2, TileWorld.Point>>, +graph: FilterDump.Graph, +tiles: Grid.Hash) -> GenJob.Landed & List<&2, String>:
  (g, +flags) = got
  +line = Canon.record("landed", [Canon.number("a", a), Canon.number("ctr", Pcg.counter(seed_of(st), rng)),
    Canon.number("n", U32.from_nat(List.length(&2, Entities.Ent, ents))), Canon.field("tiles", hash_text(tiles)), Canon.field("flags", hash_text(flags)),
    Canon.number("topo", GenJob.topology_count(s))])
  (GenJob.Landed{g, rng, ents, s, w, Nil{}, roads, graph}, [line])

def landed_tiles(got: Grid.Grid & Grid.Hash, +st: Tr, +a: U32, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +s: StoryGraph.St, +w: U32, +roads: List<&2, List<&2, TileWorld.Point>>, +graph: FilterDump.Graph) -> GenJob.Landed & List<&2, String>:
  (g, +tiles) = got
  landed_flags(Grid.flags_digest(g, StoryGraph.rng_of(s)), st, a, rng, ents, s, w, roads, graph, tiles)

def landed_lines(landed: GenJob.Landed, +st: Tr, +a: U32) -> GenJob.Landed & List<&2, String>:
  match landed:
    case GenJob.Landed{g, +rng, +ents, +s, +w, _, +roads, +graph}:
      landed_tiles(Grid.tiles_digest(g), st, a, rng, ents, s, w, roads, graph)

def ocean_entered(got: GenJob.Landed & List<&2, String>, +c: Generate.Seed, +a: U32) -> GenJob.Job & List<&2, String>:
  (landed, +lines) = got
  (GenJob.JOcean{c, a, landed}, lines)

def outcome_line(+a: U32, +kind: String) -> List<&2, String>:
  [Canon.record("outcome", [Canon.number("a", a), Canon.field("kind", Canon.quoted(kind))])]

def outcome_name(+o: GenJob.Outcome) -> String:
  match o:
    case GenJob.Crashed{}:
      "crashed"
    case GenJob.GaveUp{}:
      "gaveup"

# The records of a stage the job has just entered, and the job handed back.
def entered(job: GenJob.Job, +st: Tr) -> GenJob.Job & List<&2, String>:
  match job:
    case GenJob.JStart{+c, +a, +rng}:
      (GenJob.JStart{c, a, rng}, Nil{})
    case GenJob.JFirst{+c, +a, +s, +k}:
      (GenJob.JFirst{c, a, s, k}, graph_lines(s, k, a, 1))
    case GenJob.JSecond{+c, +a, +s, +k, +first}:
      (GenJob.JSecond{c, a, s, k, first}, first_lines(st, s, k, a, first))
    case GenJob.JCommit{+c, +a, +s, +k, +second}:
      (GenJob.JCommit{c, a, s, k, second}, second_lines(st, c, s, k, a, second))
    case GenJob.JTiles{+c, +a, +s, +k, +size, +sites}:
      (GenJob.JTiles{c, a, s, k, size, sites}, tiles_stage_lines(st, c, s, k, a, size, sites))
    case GenJob.JLand{+c, +a, +s, +k, +w, +world, +lists, +sites}:
      (GenJob.JLand{c, a, s, k, w, world, lists, sites}, land_lines(st, c, s, k, a, w, world, lists, sites))
    case GenJob.JOcean{+c, +a, landed}:
      ocean_entered(landed_lines(landed, st, a), c, a)
    case GenJob.JWorld{+c, +a, world}:
      (GenJob.JWorld{c, a, world}, outcome_line(a, "world"))
    case GenJob.JDone{+c, +a, +o}:
      (GenJob.JDone{c, a, o}, outcome_line(a, outcome_name(o)))
    case GenJob.JTiled{+c, +a, +s, +k, +w, grid, +rng, placed, +sites}:
      (GenJob.JTiled{c, a, s, k, w, grid, rng, placed, sites}, outcome_line(a, "tiled"))
    case GenJob.JMazed{+c, +a, +s, +k, +w, land, +sites}:
      (GenJob.JMazed{c, a, s, k, w, land, sites}, Nil{})
    case GenJob.JPost{+c, +a, +s, +w, land, +graph}:
      (GenJob.JPost{c, a, s, w, land, graph}, Nil{})

def start_counter(+stage: U32, +seed: U32, +ctr: U32, +rng: Pcg.Rng) -> U32:
  Bool.pick(U32, U32.is_zero(stage), Pcg.counter(seed, rng), ctr)

def job_rng(job: GenJob.Job) -> GenJob.Job & Pcg.Rng:
  match job:
    case GenJob.JStart{+c, +a, +rng}:
      (GenJob.JStart{c, a, rng}, rng)
    case _:
      (job, Pcg.Rng{0, 0})

def with_lines(got: GenJob.Job & List<&2, String>, +st: Tr, +stage: U32, +a: U32, +rng: Pcg.Rng) -> GenJob.Job & Tr:
  (job, +lines) = got
  match st:
    case Tr{+seed, _, _, +ctr, +chunks}:
      (job, Tr{seed, stage, a, start_counter(stage, seed, ctr, rng), lines <> chunks})

def tr_ctr(+st: Tr) -> U32:
  match st:
    case Tr{_, _, _, +ctr, _}:
      ctr

def entered_rng(got: GenJob.Job & Pcg.Rng, +st: Tr, +stage: U32, +a: U32) -> GenJob.Job & Tr:
  (job, +rng) = got
  with_lines(entered(job, Tr{seed_of(st), stage, a, start_counter(stage, seed_of(st), tr_ctr(st), rng), Nil{}}), st, stage, a, rng)

def changed(+st: Tr, +stage: U32, +a: U32) -> Bool:
  match st:
    case Tr{_, +was, +wa, _, _}:
      U32.is_ne(was, stage) || U32.is_ne(wa, a)

def enter_if(on: Bool, job: GenJob.Job, +st: Tr, +stage: U32, +a: U32) -> GenJob.Job & Tr:
  match on:
    case True{}:
      entered_rng(job_rng(job), st, stage, a)
    case False{}:
      (job, st)

def moved_final(final: Bool, job: GenJob.Job) -> Step:
  match final:
    case True{}:
      Stop{}
    case False{}:
      Go{GenJob.advance(job)}

def visited(got: GenJob.Job & Tr, +stage: U32) -> Tr & Step:
  (job, +st) = got
  (st, moved_final(GenJob.settled(stage), job))

def visit_at(job: GenJob.Job, +at: GenJob.Where, +st: Tr) -> Tr & Step:
  match at:
    case GenJob.Where{+stage, +a}:
      visited(enter_if(changed(st, stage, a), job, st, stage, a), stage)

def visit(got: GenJob.Job & GenJob.Where, +st: Tr) -> Tr & Step:
  (job, +sa) = got
  visit_at(job, sa, st)

def trace_loop(fuel: Nat, got: Tr & Step) -> Tr:
  match fuel:
    case 0n:
      (+st, _) = got
      st
    case 1n+f:
      (+st, step) = got
      match step:
        case Stop{}:
          st
        case Go{job}:
          trace_loop(f, visit(GenJob.stage(job), st))

def flatten(chunks: List<&2, List<&2, String>>, acc: List<&2, String>) -> List<&2, String>:
  match chunks:
    case Nil{}:
      acc
    case Con{+lines, rest}:
      flatten(rest, List.append(&2, String, lines, acc))

def lines_of(+st: Tr) -> List<&2, String>:
  match st:
    case Tr{_, _, _, _, +chunks}:
      flatten(chunks, Nil{})

# The stage's records for a seed on the platform (the input is not used).
def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  lines_of(trace_loop(8192n, (Tr{seed, 9, 0, 0, Nil{}}, Go{GenJob.start(seed, windows, False{})})))
