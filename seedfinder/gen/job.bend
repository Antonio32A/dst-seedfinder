import Base
import ../rng/pcg.bend as R
import ../storygen/graph.bend as GG
import ../worldsim/layout/space.bend as KS
import ../worldsim/layout/kk.bend as KK
import ../worldsim/voronoi/polygon.bend as VG
import ../worldsim/commit.bend as CM
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/world.bend as TW
import ../worldsim/tiles/convert.bend as TC
import ../populate/entities.bend as PE
import ../populate/state.bend as PS
import ../ocean/state.bend as OS
import ../ocean/ents.bend as OE
import ../ocean/required.bend as OQR
import ../ocean/ocean.bend as OO
import ./graph.bend as GK
import ./generate.bend as GE

# A resumable per-seed generator (forest_map.Generate's attempts, as worldgen_main retries them), for bounded search
# rounds: `advance` spends at most `fuel` KK phase steps (the heavy-tailed part), or does one bounded stage
# transition. At land_done the ocean stage (M10's ocean/ocean.bend) decides whether the attempt is the world.

# What the ocean stage starts from at land_done (M10's OO.run input): the tile grid, the RNG, the land entities (newest
# first), the finished story (required prefabs, topology) and the map size.
type Landed is Type:
  Landed{grid: GR.Grid, rng: R.Rng, ents: List<&2, PE.Ent>, story: GG.St, width: U32}

# The attempt that is the world: its encoded tile map, the RNG after Generate's last draw, savedata.ents (newest
# first; per prefab in savedata order) and the map size.
type Final is Type:
  Final{grid: GR.Grid, rng: R.Rng, ents: List<&2, OE.Ent>, width: U32}

# Why a seed has no world: the level table raises a Lua error, or all 5 attempts failed.
type Outcome is Data:
  Crashed{}
  GaveUp{}

# The stages of attempt a (numbered as `stage` reports them):
# 0 JStart: the attempt begins from rng. 1 JFirst / 2 JSecond: KK pass 1 / 2 running (s, k: the story and graph of
# the pass). 3 JCommit: VoronoiPass(50) built, WorldGen_Commit next. 4 JTiles: the Commit passed CheckForValidCells
# (its size and centred sites with the Commit centroids); ConvertToTileMap and the GetSiteArea check next. 5 JLand: the
# check passed (the tile world of ConvertToTileMap, its site tile lists and point sites); the tile stages and the land
# population next. 6 JOcean: land_done, the ocean stage next. 7 JWorld: the attempt is the world. 8 JDone: no world.
type Job is Type:
  JStart{c: GE.Seed, a: U32, rng: R.Rng}
  JFirst{c: GE.Seed, a: U32, s: GG.St, k: GK.Klei, kk: KK.Job}
  JSecond{c: GE.Seed, a: U32, s: GG.St, k: GK.Klei, first: GE.Pass, kk: KK.Job}
  JCommit{c: GE.Seed, a: U32, s: GG.St, k: GK.Klei, second: GE.Pass}
  JTiles{c: GE.Seed, a: U32, s: GG.St, k: GK.Klei, size: U32, sites: List<&2, VG.SiteIn>}
  JLand{c: GE.Seed, a: U32, s: GG.St, k: GK.Klei, w: U32, world: TW.World, lists: List<&2, List<&2, U32>>, sites: PT.Sites}
  JOcean{c: GE.Seed, a: U32, landed: Landed}
  JWorld{c: GE.Seed, a: U32, world: Final}
  JDone{c: GE.Seed, a: U32, outcome: Outcome}

# A new job for seed on the platform.
def start(+seed: U32, +windows: Bool) -> Job:
  +c = GE.seed_inputs(seed, windows)
  JStart{c, 1, GE.first_rng(c)}

def retry_if(more: Bool, +c: GE.Seed, +a: U32, +rng: R.Rng) -> Job:
  match more:
    case True{}:
      JStart{c, (a + 1 : U32), rng}
    case False{}:
      JDone{c, a, GaveUp{}}

# The next attempt from rng, or no world after the last one.
def retry(+c: GE.Seed, +a: U32, +rng: R.Rng) -> Job:
  retry_if((a < GE.max_attempts() : U32), c, a, rng)

def first_of(+c: GE.Seed, +a: U32, +s: GG.St) -> Job:
  +k = GK.klei(s)
  JFirst{c, a, s, k, GE.first_job(k, (GE.first_runs() - 1 : U32))}

def started(crashed: Bool, +c: GE.Seed, +a: U32, +rng: R.Rng) -> Job:
  match crashed:
    case True{}:
      JDone{c, a, Crashed{}}
    case False{}:
      first_of(c, a, GE.first_story(c, rng))

def second_of(got: KK.Job & List<&2, KS.Vec>, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei) -> Job:
  (kk, +ps) = got
  +first = GE.pass_of(c, s, k, ps, Nil{})
  +s2 = GE.second_story(c, s, k, GE.pass_site_list(first))
  +k2 = GK.klei(s2)
  JSecond{c, a, s2, k2, first, GE.second_job(GE.job_workspace(kk), k, k2, (GE.second_runs() - 1 : U32))}

def first_live(going: Bool, kk: KK.Job, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei) -> Job:
  match going:
    case True{}:
      JFirst{c, a, s, k, kk}
    case False{}:
      second_of(GE.job_positions(kk), c, a, s, k)

def first_step(got: KK.Job & Bool, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei) -> Job:
  (kk, +going) = got
  first_live(going, kk, c, a, s, k)

def commit_of(got: KK.Job & List<&2, KS.Vec>, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei, +first: GE.Pass) -> Job:
  (_, +ps) = got
  JCommit{c, a, s, k, GE.pass_of(c, s, k, ps, GE.pass_polys(first))}

def second_live(going: Bool, kk: KK.Job, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei, +first: GE.Pass) -> Job:
  match going:
    case True{}:
      JSecond{c, a, s, k, first, kk}
    case False{}:
      commit_of(GE.job_positions(kk), c, a, s, k, first)

def second_step(got: KK.Job & Bool, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei, +first: GE.Pass) -> Job:
  (kk, +going) = got
  second_live(going, kk, c, a, s, k, first)

def commit_checked(ok: Bool, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei, +size: U32, +sites: List<&2, VG.SiteIn>) -> Job:
  match ok:
    case True{}:
      JTiles{c, a, s, k, size, sites}
    case False{}:
      retry(c, a, GG.rng_of(s))

def committed_polys(+size: U32, +sites: List<&2, VG.SiteIn>, +polys: List<&2, VG.Poly>, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei) -> Job:
  commit_checked(GE.valid_cells(s, k, polys), c, a, s, k, size, GE.with_centroids(sites, polys))

def committed(cm: CM.Committed, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei) -> Job:
  match cm:
    case CM.Committed{+size, +sites, _, cells}:
      committed_polys(size, sites, GE.cells_polys(cells), c, a, s, k)

# WorldGen_Commit and CheckForValidCells; a failure retries from the RNG at Commit.
def commit(+c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei, +second: GE.Pass) -> Job:
  committed(GE.commit(c, second), c, a, s, k)

def areas_checked(ok: Bool, +c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei, +w: U32, +world: TW.World, +lists: List<&2, List<&2, U32>>, +sites: PT.Sites) -> Job:
  match ok:
    case True{}:
      JLand{c, a, s, k, w, world, lists, sites}
    case False{}:
      retry(c, a, GE.rng_after_tiles(s, w))

def tiled(+c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei, +w: U32, +world: TW.World) -> Job:
  +lists = TC.site_tiles(world)
  +sites = PT.sites(world, lists)
  areas_checked(GE.site_areas_ok(s, k, sites), c, a, s, k, w, world, lists, sites)

# ConvertToTileMap's build and the GetSiteArea < 8 check; a failure retries from the RNG after ConvertToTileMap.
def tiles(+c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei, +size: U32, +sites: List<&2, VG.SiteIn>) -> Job:
  +w = GE.tile_size(size)
  tiled(c, a, s, k, w, GE.tile_world(s, k, w, GE.tile_centred(size, sites), GE.tile_build(c, size, sites)))

def landed_of(l: PS.Land, +s: GG.St, +w: U32) -> Landed:
  match l:
    case PS.Land{g, +rng, +ents, _}:
      Landed{g, rng, ents, s, w}

# The tile stages and the land population, up to land_done.
def land(+c: GE.Seed, +a: U32, +s: GG.St, +k: GK.Klei, +w: U32, +world: TW.World, +lists: List<&2, List<&2, U32>>, +sites: PT.Sites) -> Job:
  +ctx = GE.land_context(c, s, k, sites, w, False{})
  JOcean{c, a, landed_of(GE.land(ctx, GE.tile_grid(GE.windows_of(c), world, lists), w), s, w)}

# #save.map.topology.ids: every story node (graph nodes and exit nodes of every graph).
def topology_count(+s: GG.St) -> U32:
  GG.get(s, GG.s_nodes())

def sea_of(landed: Landed) -> OS.Sea:
  match landed:
    case Landed{g, +rng, +ents, +s, _}:
      OS.Sea{g, GR.new(0, 0, 0), rng, OE.of_land(ents), topology_count(s), Nil{}}

# The required prefab check's verdict: the world (after the road length draw, math.random(3, 5)), or the next attempt
# from the RNG after the ocean stage.
def verdict(ok: Bool, +c: GE.Seed, +a: U32, sea: OS.Sea, +w: U32) -> Job:
  match ok:
    case True{}:
      match sea:
        case OS.Sea{g, _, +rng, +ents, _, _}:
          JWorld{c, a, Final{g, R.advance(rng, 1), ents, w}}
    case False{}:
      match sea:
        case OS.Sea{_, _, +rng, _, _, _}:
          retry(c, a, rng)

def oceaned(got: OS.Sea & Bool, +c: GE.Seed, +a: U32, +w: U32) -> Job:
  (sea, +ok) = got
  verdict(ok, c, a, sea, w)

# The ocean stage from land_done to the required prefab check (no node-id map, no tracing).
def ocean(+c: GE.Seed, +a: U32, landed: Landed) -> Job:
  match landed:
    case Landed{g, +rng, +ents, +s, +w}:
      +ctx = {OS.Ctx{GE.windows_of(c), GE.swaps_of(c), w, w, False{}} : OS.Ctx}
      oceaned(OO.run(ctx, OQR.required(s), sea_of(Landed{g, rng, ents, s, w})), c, a, w)

# One step of the job: a stage transition, or up to `fuel` KK phase steps of the running pass. JWorld and JDone stay
# as they are.
def advance(fuel: Nat, job: Job) -> Job:
  match job:
    case JStart{+c, +a, +rng}:
      started(GE.crashed(c), c, a, rng)
    case JFirst{+c, +a, +s, +k, kk}:
      first_step(GE.live(KK.advance(fuel, kk)), c, a, s, k)
    case JSecond{+c, +a, +s, +k, +first, kk}:
      second_step(GE.live(KK.advance(fuel, kk)), c, a, s, k, first)
    case JCommit{+c, +a, +s, +k, +second}:
      commit(c, a, s, k, second)
    case JTiles{+c, +a, +s, +k, +size, +sites}:
      tiles(c, a, s, k, size, sites)
    case JLand{+c, +a, +s, +k, +w, +world, +lists, +sites}:
      land(c, a, s, k, w, world, lists, sites)
    case JOcean{+c, +a, landed}:
      ocean(c, a, landed)
    case JWorld{+c, +a, world}:
      JWorld{c, a, world}
    case JDone{+c, +a, +o}:
      JDone{c, a, o}

# Where a job is: its stage number (see Job) and attempt.
type Where is Data:
  Where{stage: U32, a: U32}

def stage(job: Job) -> Job & Where:
  match job:
    case JStart{+c, +a, +rng}:
      (JStart{c, a, rng}, Where{0, a})
    case JFirst{+c, +a, +s, +k, kk}:
      (JFirst{c, a, s, k, kk}, Where{1, a})
    case JSecond{+c, +a, +s, +k, +first, kk}:
      (JSecond{c, a, s, k, first, kk}, Where{2, a})
    case JCommit{+c, +a, +s, +k, +second}:
      (JCommit{c, a, s, k, second}, Where{3, a})
    case JTiles{+c, +a, +s, +k, +size, +sites}:
      (JTiles{c, a, s, k, size, sites}, Where{4, a})
    case JLand{+c, +a, +s, +k, +w, +world, +lists, +sites}:
      (JLand{c, a, s, k, w, world, lists, sites}, Where{5, a})
    case JOcean{+c, +a, landed}:
      (JOcean{c, a, landed}, Where{6, a})
    case JWorld{+c, +a, world}:
      (JWorld{c, a, world}, Where{7, a})
    case JDone{+c, +a, +o}:
      (JDone{c, a, o}, Where{8, a})

# Whether the job is decided (a world, or no world).
def settled(+stage: U32) -> Bool:
  (6 < stage : U32)
