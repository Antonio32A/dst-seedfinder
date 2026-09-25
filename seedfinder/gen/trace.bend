import Base
import ../rng/pcg.bend as R
import ../f64/repr.bend as FR
import ../trace/canon.bend as CN
import ../storygen/graph.bend as GG
import ../storygen/trace.bend as GX
import ../worldsim/layout/space.bend as KS
import ../worldsim/layout/kk.bend as KK
import ../worldsim/voronoi/polygon.bend as VG
import ../worldsim/voronoi/records.bend as VN
import ../worldsim/commit.bend as CM
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/world.bend as TW
import ../worldsim/tiles/convert.bend as TC
import ../worldsim/tiles/separate.bend as TI
import ../worldsim/tiles/connect.bend as TF
import ../worldsim/tiles/roads.bend as TR
import ../populate/entities.bend as PE
import ../populate/state.bend as PS
import ../populate/trace.bend as PX
import ./graph.bend as GK
import ./generate.bend as GE
import ./job.bend as GJ

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
  Go{job: GJ.Job}
  Stop{}

def handles(+stage: String) -> Bool:
  String.eq(stage, "gen")

def hash_text(+h: GR.Hash) -> String:
  match h:
    case GR.Hash{+hi, +lo}:
      CN.hex64(hi, lo)

def f64_text(+x: FR.F64) -> String:
  match x:
    case FR.F64{+hi, +lo}:
      CN.hex64(hi, lo)

def site_fold(ss: List<&2, VG.SiteIn>, h: GR.Hash) -> GR.Hash:
  match ss:
    case Nil{}:
      h
    case Con{VG.SiteIn{+x, +y, _, _, _}, rest}:
      site_fold(rest, GR.fnv_u32(GR.fnv_u32(h, x), y))

def points_fold(ps: List<&2, VG.P32>, h: GR.Hash) -> GR.Hash:
  match ps:
    case Nil{}:
      h
    case Con{VG.P32{+x, +y}, rest}:
      points_fold(rest, GR.fnv_u32(GR.fnv_u32(h, x), y))

def poly_fold(ps: List<&2, VG.Poly>, h: GR.Hash) -> GR.Hash:
  match ps:
    case Nil{}:
      h
    case Con{VG.Poly{+pts, _, _, _, _}, rest}:
      poly_fold(rest, points_fold(pts, GR.fnv_u32(h, U32.from_nat(List.length(&2, VG.P32, pts)))))

def site_count(+ss: List<&2, VG.SiteIn>) -> U32:
  U32.from_nat(List.length(&2, VG.SiteIn, ss))

def zero_hash() -> GR.Hash:
  GR.Hash{0, 0}

def digest_line(+a: U32, +at: String, +ctr: U32, +w: U32, +sites: List<&2, VG.SiteIn>, +polys: List<&2, VG.Poly>, +tiles: GR.Hash, +flags: GR.Hash) -> String:
  CN.record("digest", [CN.number("a", a), CN.field("at", CN.quoted(at)), CN.number("i", 0), CN.number("ctr", ctr), CN.number("w", w),
    CN.number("h", w), CN.number("sites", site_count(sites)), CN.field("site_hash", hash_text(site_fold(sites, GR.fnv_offset()))),
    CN.field("poly_hash", hash_text(poly_fold(polys, GR.fnv_offset()))), CN.field("tiles", hash_text(tiles)),
    CN.field("flags", hash_text(flags)), CN.field("node_ids", hash_text(zero_hash()))])

def names_of(vs: List<&2, U32>, +s: GG.St) -> List<&2, String>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      GG.node_name(s, x) <> names_of(rest, s)

def poly_loop(ss: List<&2, VG.SiteIn>, ps: List<&2, VG.Poly>, +head: List<&2, String>, +names: List<&2, String>, +i: U32) -> List<&2, String>:
  match ss ps:
    case Con{+site, rest} Con{+p, prest}:
      List.append(&2, String, VN.site_poly_lines(p, site, head, names, i), poly_loop(rest, prest, head, names, (i + 1 : U32)))
    case _ _:
      Nil{}

def poly_lines(+a: U32, +at: String, +ss: List<&2, VG.SiteIn>, +ps: List<&2, VG.Poly>, +names: List<&2, String>) -> List<&2, String>:
  poly_loop(ss, ps, [CN.number("a", a), CN.field("at", CN.quoted(at))], names, 0)

def build_lines(+a: U32, +at: String, +ctr: U32, +w: U32, +ss: List<&2, VG.SiteIn>, +ps: List<&2, VG.Poly>, +names: List<&2, String>) -> List<&2, String>:
  digest_line(a, at, ctr, w, ss, ps, zero_hash(), zero_hash()) <> poly_lines(a, at, ss, ps, names)

def vertex_lines(vs: List<&2, U32>, +s: GG.St, +a: U32, +g: U32, +v: U32) -> List<&2, String>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      CN.record("vertex", [CN.number("a", a), CN.number("g", g), CN.number("v", v), CN.field("name", CN.quoted(GG.node_name(s, x)))])
        <> vertex_lines(rest, s, a, g, (v + 1 : U32))

def target_lines(ts: List<&2, U32>, +a: U32, +g: U32, +v: U32, +k: U32) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      CN.record("outedge", [CN.number("a", a), CN.number("g", g), CN.number("v", v), CN.number("k", k), CN.number("to", t),
        CN.field("w", "3ff0000000000000")]) <> target_lines(rest, a, g, v, (k + 1 : U32))

def outedge_lines(rows: List<&2, List<&2, U32>>, +a: U32, +g: U32, +v: U32, +k: U32) -> List<&2, String>:
  match rows:
    case Nil{}:
      Nil{}
    case Con{+ts, rest}:
      List.append(&2, String, target_lines(ts, a, g, v, k),
        outedge_lines(rest, a, g, (v + 1 : U32), (k + U32.from_nat(List.length(&2, U32, ts)) : U32)))

def graph_lines(+s: GG.St, +k: GK.Klei, +a: U32, +g: U32) -> List<&2, String>:
  List.append(&2, String, vertex_lines(GK.vertices_of(k), s, a, g, 0), outedge_lines(GK.adjacency(GK.count_of(k), GK.edges_of(k)), a, g, 0, 0))

def kkpos_lines(ps: List<&2, KS.Vec>, +a: U32, +g: U32, +run: U32, +v: U32) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{KS.Vec{+x, +y}, rest}:
      CN.record("kkpos", [CN.number("a", a), CN.number("g", g), CN.number("run", run), CN.number("v", v), CN.field("x", f64_text(x)),
        CN.field("y", f64_text(y))]) <> kkpos_lines(rest, a, g, run, (v + 1 : U32))

def kept_if(keep: Bool, +v: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{}:
      v <> rest
    case False{}:
      rest

def pass_calls(evs: List<&2, GG.Ev>, +seed: U32) -> List<&2, U32>:
  match evs:
    case Nil{}:
      Nil{}
    case Con{+ev, rest}:
      match ev:
        case GG.ECall{+m, +rng}:
          kept_if(U32.is_eq(m, 7), R.counter(seed, rng), pass_calls(rest, seed))
        case _:
          pass_calls(rest, seed)

# The draw counter at the story's n-th WorldGen_VoronoiPass call (n from 0).
def pass_counter(+s: GG.St, +n: Nat, +seed: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, pass_calls(List.reverse(&2, GG.Ev, GG.log_of(s)), seed), n), 0)

def story_lines(+st: Tr, +s: GG.St, +a: U32) -> List<&2, String>:
  match st:
    case Tr{+seed, _, _, +ctr, _}:
      GX.story_lines(s, seed, U32.show(a), ctr)

def seed_of(+st: Tr) -> U32:
  match st:
    case Tr{+seed, _, _, _, _}:
      seed

def first_lines(+st: Tr, +s: GG.St, +k: GK.Klei, +a: U32, +first: GE.Pass) -> List<&2, String>:
  +names = names_of(GK.vertices_of(k), s)
  +ctr = pass_counter(s, 0n, seed_of(st))
  List.append(&2, String, story_lines(st, s, a), List.append(&2, String, graph_lines(s, k, a, 2),
    List.append(&2, String, kkpos_lines(GE.pass_positions(first), a, 1, 100, 0),
      build_lines(a, "VoronoiPass(100)", ctr, GE.world_size(), GE.pass_site_list(first), GE.pass_polys(first), names))))

def commit_lines(cm: CM.Committed, +ctr: U32, +a: U32, +names: List<&2, String>) -> List<&2, String>:
  match cm:
    case CM.Committed{+size, +sites, _, cells}:
      build_lines(a, "Commit", ctr, size, sites, GE.cells_polys(cells), names)

def second_lines(+st: Tr, +c: GE.Seed, +s: GG.St, +k: GK.Klei, +a: U32, +second: GE.Pass) -> List<&2, String>:
  +names = names_of(GK.vertices_of(k), s)
  +seed = seed_of(st)
  List.append(&2, String, kkpos_lines(GE.pass_positions(second), a, 2, 50, 0),
    List.append(&2, String, build_lines(a, "VoronoiPass(50)", pass_counter(s, 1n, seed), GE.world_size(), GE.pass_site_list(second), GE.pass_polys(second), names),
      commit_lines(GE.commit(c, second), R.counter(seed, GG.rng_of(s)), a, names)))

# A tile digest: the counter after ConvertToTileMap, and the flags with the variant draws from the RNG before it.
type Tiles is Type:
  Tiles{g: GR.Grid, lines: List<&2, String>}

type At is Data:
  At{a: U32, ctr: U32, w: U32, sites: List<&2, VG.SiteIn>, polys: List<&2, VG.Poly>, rng: R.Rng}

def flags_hashed(got: GR.Grid & GR.Hash, +at: At, +name: String, +tiles: GR.Hash, +lines: List<&2, String>) -> Tiles:
  (g, +flags) = got
  match at:
    case At{+a, +ctr, +w, +sites, +polys, _}:
      Tiles{g, digest_line(a, name, ctr, w, sites, polys, tiles, flags) <> lines}

def tiles_hashed(got: GR.Grid & GR.Hash, +at: At, +name: String, +lines: List<&2, String>) -> Tiles:
  (g, +tiles) = got
  match at:
    case At{_, _, _, _, _, +rng}:
      flags_hashed(GR.flags_digest(g, rng), at, name, tiles, lines)

def tile_digest(t: Tiles, +at: At, +name: String) -> Tiles:
  match t:
    case Tiles{g, +lines}:
      tiles_hashed(GR.tiles_digest(g), at, name, lines)

def separated(t: Tiles, +w: TW.World) -> Tiles:
  match t:
    case Tiles{g, +lines}:
      Tiles{TI.separate(w, g), lines}

def forced(t: Tiles, +w: TW.World, +isl: TF.Islands) -> Tiles:
  match t:
    case Tiles{g, +lines}:
      Tiles{TF.force(w, isl, g), lines}

def roads_drawn(t: Tiles, +windows: Bool, +w: TW.World, +isl: TF.Islands) -> Tiles:
  match t:
    case Tiles{g, +lines}:
      Tiles{TR.draw_roads(windows, TR.roads(windows, w, isl), g), lines}

def tiles_lines(t: Tiles) -> List<&2, String>:
  match t:
    case Tiles{_, +lines}:
      List.reverse(&2, String, lines)

# ConvertToTileMap's paint, SeparateIslands, ForceConnectivity and DrawRoads as GE.tile_grid runs them, with a digest
# after each.
def grid_lines(+windows: Bool, +w: TW.World, +at: At) -> List<&2, String>:
  +isl = TF.islands(w, False{})
  t0 = tile_digest(Tiles{TC.paint(w, TC.site_tiles(w)), Nil{}}, at, "ConvertToTileMap")
  t1 = tile_digest(separated(t0, w), at, "SeparateIslands")
  t2 = tile_digest(forced(t1, w, isl), at, "ForceConnectivity")
  tiles_lines(tile_digest(roads_drawn(t2, windows, w, isl), at, "DrawRoads"))

def tiles_world_lines(+windows: Bool, +names: List<&2, String>, +world: TW.World, +at: At) -> List<&2, String>:
  match at:
    case At{+a, _, _, +centred, +polys, _}:
      List.append(&2, String, grid_lines(windows, world, at), poly_lines(a, "ConvertToTileMap", centred, polys, names))

def tiles_polys_lines(+st: Tr, +c: GE.Seed, +s: GG.St, +k: GK.Klei, +a: U32, +w: U32, +centred: List<&2, VG.SiteIn>, +polys: List<&2, VG.Poly>, cells: VG.Cells) -> List<&2, String>:
  tiles_world_lines(GE.windows_of(c), names_of(GK.vertices_of(k), s), GE.tile_world(s, k, w, centred, cells),
    At{a, R.counter(seed_of(st), GE.rng_after_tiles(s, w)), w, centred, polys, GG.rng_of(s)})

def tiles_stage_lines(+st: Tr, +c: GE.Seed, +s: GG.St, +k: GK.Klei, +a: U32, +size: U32, +sites: List<&2, VG.SiteIn>) -> List<&2, String>:
  tiles_polys_lines(st, c, s, k, a, GE.tile_size(size), GE.tile_centred(size, sites), GE.cells_polys(GE.tile_build(c, size, sites)), GE.tile_build(c, size, sites))

def unshuffled(evs: List<&2, PS.Ev>) -> List<&2, PS.Ev>:
  match evs:
    case Nil{}:
      Nil{}
    case Con{+ev, rest}:
      match ev:
        case PS.EPoints{+node, +n, +before, +after, _, +kept}:
          PS.EPoints{node, n, before, after, Nil{}, kept} <> unshuffled(rest)
        case _:
          ev <> unshuffled(rest)

def land_events(l: PS.Land) -> PS.Land:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      PS.Land{g, rng, ents, unshuffled(events)}

def land_lines(+st: Tr, +c: GE.Seed, +s: GG.St, +k: GK.Klei, +a: U32, +w: U32, +world: TW.World, +lists: List<&2, List<&2, U32>>, +sites: PT.Sites) -> List<&2, String>:
  PX.land_lines(land_events(GE.land(GE.land_context(c, s, k, sites, w, True{}), GE.tile_grid(GE.windows_of(c), world, lists), w)),
    PX.Out{seed_of(st), U32.show(a), w, w, s, 0, 0, 0, 0, 0, 0})

def landed_flags(got: GR.Grid & GR.Hash, +st: Tr, +a: U32, +rng: R.Rng, +ents: List<&2, PE.Ent>, +s: GG.St, +w: U32, +tiles: GR.Hash) -> GJ.Landed & List<&2, String>:
  (g, +flags) = got
  +line = CN.record("landed", [CN.number("a", a), CN.number("ctr", R.counter(seed_of(st), rng)),
    CN.number("n", U32.from_nat(List.length(&2, PE.Ent, ents))), CN.field("tiles", hash_text(tiles)), CN.field("flags", hash_text(flags)),
    CN.number("topo", GJ.topology_count(s))])
  (GJ.Landed{g, rng, ents, s, w}, [line])

def landed_tiles(got: GR.Grid & GR.Hash, +st: Tr, +a: U32, +rng: R.Rng, +ents: List<&2, PE.Ent>, +s: GG.St, +w: U32) -> GJ.Landed & List<&2, String>:
  (g, +tiles) = got
  landed_flags(GR.flags_digest(g, GG.rng_of(s)), st, a, rng, ents, s, w, tiles)

def landed_lines(landed: GJ.Landed, +st: Tr, +a: U32) -> GJ.Landed & List<&2, String>:
  match landed:
    case GJ.Landed{g, +rng, +ents, +s, +w}:
      landed_tiles(GR.tiles_digest(g), st, a, rng, ents, s, w)

def ocean_entered(got: GJ.Landed & List<&2, String>, +c: GE.Seed, +a: U32) -> GJ.Job & List<&2, String>:
  (landed, +lines) = got
  (GJ.JOcean{c, a, landed}, lines)

def outcome_line(+a: U32, +kind: String) -> List<&2, String>:
  [CN.record("outcome", [CN.number("a", a), CN.field("kind", CN.quoted(kind))])]

def outcome_name(+o: GJ.Outcome) -> String:
  match o:
    case GJ.Crashed{}:
      "crashed"
    case GJ.GaveUp{}:
      "gaveup"

# The records of a stage the job has just entered, and the job handed back.
def entered(job: GJ.Job, +st: Tr) -> GJ.Job & List<&2, String>:
  match job:
    case GJ.JStart{+c, +a, +rng}:
      (GJ.JStart{c, a, rng}, Nil{})
    case GJ.JFirst{+c, +a, +s, +k, kk}:
      (GJ.JFirst{c, a, s, k, kk}, graph_lines(s, k, a, 1))
    case GJ.JSecond{+c, +a, +s, +k, +first, kk}:
      (GJ.JSecond{c, a, s, k, first, kk}, first_lines(st, s, k, a, first))
    case GJ.JCommit{+c, +a, +s, +k, +second}:
      (GJ.JCommit{c, a, s, k, second}, second_lines(st, c, s, k, a, second))
    case GJ.JTiles{+c, +a, +s, +k, +size, +sites}:
      (GJ.JTiles{c, a, s, k, size, sites}, tiles_stage_lines(st, c, s, k, a, size, sites))
    case GJ.JLand{+c, +a, +s, +k, +w, +world, +lists, +sites}:
      (GJ.JLand{c, a, s, k, w, world, lists, sites}, land_lines(st, c, s, k, a, w, world, lists, sites))
    case GJ.JOcean{+c, +a, landed}:
      ocean_entered(landed_lines(landed, st, a), c, a)
    case GJ.JWorld{+c, +a, world}:
      (GJ.JWorld{c, a, world}, outcome_line(a, "world"))
    case GJ.JDone{+c, +a, +o}:
      (GJ.JDone{c, a, o}, outcome_line(a, outcome_name(o)))

def start_counter(+stage: U32, +seed: U32, +ctr: U32, +rng: R.Rng) -> U32:
  Bool.pick(U32, U32.is_zero(stage), R.counter(seed, rng), ctr)

def job_rng(job: GJ.Job) -> GJ.Job & R.Rng:
  match job:
    case GJ.JStart{+c, +a, +rng}:
      (GJ.JStart{c, a, rng}, rng)
    case _:
      (job, R.Rng{0, 0})

def with_lines(got: GJ.Job & List<&2, String>, +st: Tr, +stage: U32, +a: U32, +rng: R.Rng) -> GJ.Job & Tr:
  (job, +lines) = got
  match st:
    case Tr{+seed, _, _, +ctr, +chunks}:
      (job, Tr{seed, stage, a, start_counter(stage, seed, ctr, rng), lines <> chunks})

def tr_ctr(+st: Tr) -> U32:
  match st:
    case Tr{_, _, _, +ctr, _}:
      ctr

def entered_rng(got: GJ.Job & R.Rng, +st: Tr, +stage: U32, +a: U32) -> GJ.Job & Tr:
  (job, +rng) = got
  with_lines(entered(job, Tr{seed_of(st), stage, a, start_counter(stage, seed_of(st), tr_ctr(st), rng), Nil{}}), st, stage, a, rng)

def changed(+st: Tr, +stage: U32, +a: U32) -> Bool:
  match st:
    case Tr{_, +was, +wa, _, _}:
      U32.is_ne(was, stage) || U32.is_ne(wa, a)

def enter_if(on: Bool, job: GJ.Job, +st: Tr, +stage: U32, +a: U32) -> GJ.Job & Tr:
  match on:
    case True{}:
      entered_rng(job_rng(job), st, stage, a)
    case False{}:
      (job, st)

def moved_final(final: Bool, job: GJ.Job) -> Step:
  match final:
    case True{}:
      Stop{}
    case False{}:
      Go{GJ.advance(KK.run_fuel(), job)}

def visited(got: GJ.Job & Tr, +stage: U32) -> Tr & Step:
  (job, +st) = got
  (st, moved_final(GJ.settled(stage), job))

def visit_at(job: GJ.Job, +at: GJ.Where, +st: Tr) -> Tr & Step:
  match at:
    case GJ.Where{+stage, +a}:
      visited(enter_if(changed(st, stage, a), job, st, stage, a), stage)

def visit(got: GJ.Job & GJ.Where, +st: Tr) -> Tr & Step:
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
          trace_loop(f, visit(GJ.stage(job), st))

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
  lines_of(trace_loop(8192n, (Tr{seed, 9, 0, 0, Nil{}}, Go{GJ.start(seed, windows)})))
