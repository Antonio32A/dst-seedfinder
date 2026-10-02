import Base
import ../rng/pcg.bend as Pcg
import ../storygen/graph.bend as StoryGraph
import ../worldsim/layout/space.bend as LayoutSpace
import ../worldsim/voronoi/polygon.bend as VoronoiPolygon
import ../worldsim/commit.bend as Commit
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/world.bend as TileWorld
import ../worldsim/tiles/convert.bend as TileConvert
import ../lua/math_random.bend as MathRandom
import ../populate/entities.bend as Entities
import ../populate/state.bend as PopulateState
import ../populate/setpiece.bend as PopulateSetpiece
import ../ocean/state.bend as OceanState
import ../ocean/ents.bend as OceanEnts
import ../ocean/required.bend as OceanRequired
import ../ocean/ocean.bend as Ocean
import ../post/atrium.bend as Atrium
import ../post/finish.bend as Finish
import ../populate/land.bend as PopulateLand
import ./graph.bend as GenGraph
import ./generate.bend as Generate
import ./layout.bend as GenLayout
import ./cave_custom.bend as CaveCustom
import ./cave_maze.bend as CaveMaze
import ./maze_pieces.bend as MazePieces
import ./cave_names.bend as CaveNames
import ./cave_required.bend as CaveRequired

# A resumable per-seed generator (forest_map.Generate's attempts, as worldgen_main retries them), for bounded search
# rounds: `step` does one bounded stage transition; at a KK pass the job waits for a layout engine (gen/layout.bend):
# `layout` hands over the pass, `laid` resumes with its positions, `advance` runs the pass on this thread (trace) and
# `advance_io` through GenLayout.solve (gen). At land_done the ocean stage (M10's ocean/ocean.bend) decides whether the
# attempt is the world.

# What the ocean stage starts from at land_done (M10's Ocean.run input): the tile grid, the RNG, the land entities (newest
# first), the finished story (required prefabs, topology), the map size, the land's placed layouts (when recorded) and
# GetRoads' polylines (tile world units).
type Landed is Type:
  Landed{grid: Grid.Grid, rng: Pcg.Rng, ents: List<&2, Entities.Ent>, story: StoryGraph.St, width: U32, pieces: List<&2, PopulateSetpiece.Piece>, roads: List<&2, List<&2, TileWorld.Point>>}

# The attempt that is the world: its encoded tile map, the RNG after Generate's last draw, savedata.ents (newest
# first; per prefab in savedata order), the map size and, for a job started to record them, the layouts it placed
# (in placement order; each entity's `piece` numbers them from 1), GetRoads' polylines and the shortest road the game
# keeps (its math.random(3, 5) draw).
type Final is Type:
  Final{grid: Grid.Grid, rng: Pcg.Rng, ents: List<&2, OceanEnts.Ent>, width: U32, pieces: List<&2, PopulateSetpiece.Piece>, roads: List<&2, List<&2, TileWorld.Point>>, min_road: U32}

# Why a seed has no world: the game crashes (the level table raises a Lua error, or the caves' custom tile pass runs
# RunCA on a site without a polygon), or all 5 attempts failed.
type Outcome is Data:
  Crashed{}
  GaveUp{}

# The stages of attempt a (numbered as `stage` reports them):
# 0 JStart: the attempt begins from rng. 1 JFirst / 2 JSecond: waiting for KK pass 1 / 2 (s, k: the story and graph
# of the pass). 3 JCommit: VoronoiPass(50) built, WorldGen_Commit next. 4 JTiles: the Commit passed CheckForValidCells
# (its size and centred sites with the Commit centroids); ConvertToTileMap and the GetSiteArea check next. 5 JLand: the
# check passed (the tile world of ConvertToTileMap, its site tile lists and point sites); the tile stages and the land
# population next. 6 JOcean: land_done, the ocean stage next. 7 JWorld: the attempt is the world. 8 JDone: no world.
# The caves: 10 JTiled: after the custom tile pass (the tile map right before the mazes run). 11 JMazed: after the mazes,
# with the entities so far. 12 JPost: after the land population (ConvertGround to PopulateVoronoi, DetectDisconnect passed),
# the post-populate steps and the required prefab check next.
type Job is Type:
  JStart{c: Generate.Seed, a: U32, rng: Pcg.Rng}
  JFirst{c: Generate.Seed, a: U32, s: StoryGraph.St, k: GenGraph.Klei}
  JSecond{c: Generate.Seed, a: U32, s: StoryGraph.St, k: GenGraph.Klei, first: Generate.Pass}
  JCommit{c: Generate.Seed, a: U32, s: StoryGraph.St, k: GenGraph.Klei, second: Generate.Pass}
  JTiles{c: Generate.Seed, a: U32, s: StoryGraph.St, k: GenGraph.Klei, size: U32, sites: List<&2, VoronoiPolygon.SiteIn>}
  JLand{c: Generate.Seed, a: U32, s: StoryGraph.St, k: GenGraph.Klei, w: U32, world: TileWorld.World, lists: List<&2, List<&2, U32>>, sites: Points.Sites}
  JOcean{c: Generate.Seed, a: U32, landed: Landed}
  JTiled{c: Generate.Seed, a: U32, s: StoryGraph.St, k: GenGraph.Klei, w: U32, grid: Grid.Grid, rng: Pcg.Rng, placed: List<&2, CaveCustom.Placed>, sites: Points.Sites}
  JMazed{c: Generate.Seed, a: U32, s: StoryGraph.St, k: GenGraph.Klei, w: U32, land: PopulateState.Land, sites: Points.Sites}
  JPost{c: Generate.Seed, a: U32, s: StoryGraph.St, w: U32, land: PopulateState.Land}
  JWorld{c: Generate.Seed, a: U32, world: Final}
  JDone{c: Generate.Seed, a: U32, outcome: Outcome}

# A new job for seed on the platform, recording the layouts it places when `pieces` (Final.pieces).
def start(+seed: U32, +windows: Bool, +pieces: Bool) -> Job:
  +c = Generate.seed_inputs(seed, windows, pieces)
  JStart{c, 1, Generate.first_rng(c)}

def cave_start(first: Bool, +c: Generate.Seed, +seed: U32, +draws: U32) -> Job:
  match first:
    case True{}:
      JStart{c, 1, Generate.first_rng(c)}
    case False{}:
      JStart{Generate.entrance_resolved(c), 1, Pcg.at_counter(seed, draws)}

# A new caves job for seed on the platform, recording the mazes and layouts it places when `pieces` (Final.pieces). With draws > 0 the attempt starts that many draws into the seed's stream
# (the counter of a real later attempt), with the entrance list pick as the earlier attempts made it.
def start_caves(+seed: U32, +windows: Bool, +draws: U32, +pieces: Bool) -> Job:
  cave_start(U32.is_zero(draws), Generate.cave_inputs(seed, windows, pieces), seed, draws)

def retry_if(more: Bool, +c: Generate.Seed, +a: U32, +rng: Pcg.Rng) -> Job:
  match more:
    case True{}:
      JStart{c, (a + 1 : U32), rng}
    case False{}:
      JDone{c, a, GaveUp{}}

# The next attempt from rng, or no world after the last one.
def retry(+c: Generate.Seed, +a: U32, +rng: Pcg.Rng) -> Job:
  retry_if((a < Generate.max_attempts() : U32), c, a, rng)

def started(crashed: Bool, +c: Generate.Seed, +a: U32, +rng: Pcg.Rng) -> Job:
  match crashed:
    case True{}:
      JDone{c, a, Crashed{}}
    case False{}:
      +s = Generate.first_story(c, rng)
      JFirst{c, a, s, GenGraph.klei(s)}

# The KK pass the job waits for, if any.
def layout(job: Job) -> Job & Maybe<&2, GenLayout.Layout>:
  match job:
    case JFirst{+c, +a, +s, +k}:
      (JFirst{c, a, s, k}, Some{GenLayout.Layout{0, GenGraph.count_of(k), GenGraph.arcs(k), (Generate.first_runs() - 1 : U32), Nil{}}})
    case JSecond{+c, +a, +s, +k, +first}:
      +prior = Generate.pass_positions(first)
      (JSecond{c, a, s, k, first}, Some{GenLayout.Layout{U32.from_nat(List.length(&2, LayoutSpace.Vec, prior)), GenGraph.count_of(k), GenGraph.arcs(k), (Generate.second_runs() - 1 : U32), prior}})
    case other:
      (other, None{})

def second_by(caves: Bool, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +first: Generate.Pass) -> Job:
  match caves:
    case True{}:
      JCommit{c, a, s, GenGraph.klei(s), first}
    case False{}:
      JSecond{c, a, s, GenGraph.klei(s), first}

# The story after pass 1 (Story:AddRegionsToMainland): the forest adds the moon island and waits for its KK pass 2; the
# caves have no regions, so their Commit follows pass 1.
def second_of(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +ps: List<&2, LayoutSpace.Vec>) -> Job:
  +first = Generate.pass_of(c, s, k, ps, Nil{})
  second_by(Generate.is_caves(c), c, a, Generate.second_story(c, s, k, Generate.pass_site_list(first)), first)

# The waiting job resumed with its pass's positions (VoronoiPass's BuildVoronoi, and after pass 1 the story up to
# pass 2); any other job as it is.
def laid(job: Job, +ps: List<&2, LayoutSpace.Vec>) -> Job:
  match job:
    case JFirst{+c, +a, +s, +k}:
      second_of(c, a, s, k, ps)
    case JSecond{+c, +a, +s, +k, +first}:
      JCommit{c, a, s, k, Generate.pass_of(c, s, k, ps, Generate.pass_polys(first))}
    case other:
      other

def commit_checked(ok: Bool, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +size: U32, +sites: List<&2, VoronoiPolygon.SiteIn>) -> Job:
  match ok:
    case True{}:
      JTiles{c, a, s, k, size, sites}
    case False{}:
      retry(Generate.carried(c, s), a, StoryGraph.rng_of(s))

def committed_polys(+size: U32, +sites: List<&2, VoronoiPolygon.SiteIn>, +polys: List<&2, VoronoiPolygon.Poly>, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei) -> Job:
  commit_checked(Generate.valid_cells(s, k, polys), c, a, s, k, size, Generate.with_centroids(sites, polys))

def committed(cm: Commit.Committed, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei) -> Job:
  match cm:
    case Commit.Committed{+size, +sites, _, cells}:
      committed_polys(size, sites, Generate.cells_polys(cells), c, a, s, k)

# WorldGen_Commit and CheckForValidCells; a failure retries from the RNG at Commit.
def commit(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +second: Generate.Pass) -> Job:
  committed(Generate.commit(c, second), c, a, s, k)

def areas_checked(ok: Bool, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +world: TileWorld.World, +lists: List<&2, List<&2, U32>>, +sites: Points.Sites) -> Job:
  match ok:
    case True{}:
      JLand{c, a, s, k, w, world, lists, sites}
    case False{}:
      retry(Generate.carried(c, s), a, Generate.rng_after_land(c, s, k, w, world, lists, sites))

def crash_checked(crashed: Bool, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +world: TileWorld.World, +lists: List<&2, List<&2, U32>>, +sites: Points.Sites) -> Job:
  match crashed:
    case True{}:
      JDone{c, a, Crashed{}}
    case False{}:
      areas_checked(Generate.site_areas_ok(s, k, sites), c, a, s, k, w, world, lists, sites)

def tiled(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +world: TileWorld.World) -> Job:
  +counted = TileConvert.counted_site_tiles(world)
  +lists = TileConvert.lists_of(counted)
  +sites = Points.sized_sites(world, lists, TileConvert.sizes_of(counted))
  crash_checked(Generate.custom_crashes(c, s, k, sites), c, a, s, k, w, world, lists, sites)

# ConvertToTileMap's build and the GetSiteArea < 8 check; a failure retries from the RNG after ConvertToTileMap (the
# caves: after their custom tile pass, which crashes the game first when Generate.custom_crashes).
def tiles(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +size: U32, +sites: List<&2, VoronoiPolygon.SiteIn>) -> Job:
  +w = Generate.tile_size(size)
  tiled(c, a, s, k, w, Generate.tile_world(s, k, w, Generate.tile_centred(size, sites), Generate.tile_build(c, size, sites)))

def landed_of(l: PopulateState.Land, +roads: List<&2, List<&2, TileWorld.Point>>, +s: StoryGraph.St, +w: U32) -> Landed:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      Landed{g, rng, ents, s, w, PopulateState.pieces(events), roads}

def grounded(got: Grid.Grid & List<&2, List<&2, TileWorld.Point>>, +ctx: PopulateState.Ctx, +s: StoryGraph.St, +w: U32) -> Landed:
  (g, +roads) = got
  landed_of(Generate.land(ctx, g, w), roads, s, w)

def land_forest(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +world: TileWorld.World, +lists: List<&2, List<&2, U32>>, +sites: Points.Sites) -> Job:
  +ctx = Generate.land_context(c, s, k, sites, w, False{})
  JOcean{c, a, grounded(Generate.tile_grid(Generate.windows_of(c), world, lists), ctx, s, w)}

def tiled_by(done: CaveCustom.Tiles, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +sites: Points.Sites) -> Job:
  match done:
    case CaveCustom.Tiles{g, rng, placed}:
      JTiled{c, a, s, k, w, g, rng, placed, sites}

def land_caves(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +world: TileWorld.World, +lists: List<&2, List<&2, U32>>, +sites: Points.Sites) -> Job:
  tiled_by(Generate.cave_land(c, s, k, w, world, lists, sites), c, a, s, k, w, sites)

def land_by(caves: Bool, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +world: TileWorld.World, +lists: List<&2, List<&2, U32>>, +sites: Points.Sites) -> Job:
  match caves:
    case True{}:
      land_caves(c, a, s, k, w, world, lists, sites)
    case False{}:
      land_forest(c, a, s, k, w, world, lists, sites)

# The tile stages and the land population, up to land_done (the caves stop after ForceConnectivity).
def land(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +world: TileWorld.World, +lists: List<&2, List<&2, U32>>, +sites: Points.Sites) -> Job:
  land_by(Generate.is_caves(c), c, a, s, k, w, world, lists, sites)

# #save.map.topology.ids: every story node (graph nodes and exit nodes of every graph).
def topology_count(+s: StoryGraph.St) -> U32:
  StoryGraph.get(s, StoryGraph.s_nodes())

def piece_events(ps: List<&2, PopulateSetpiece.Piece>, +acc: List<&2, OceanState.Ev>) -> List<&2, OceanState.Ev>:
  match ps:
    case Nil{}:
      acc
    case Con{+p, rest}:
      piece_events(rest, OceanState.EPiece{p} <> acc)

def ocean_ents(+ents: List<&2, Entities.Ent>, +pieces: List<&2, PopulateSetpiece.Piece>) -> List<&2, OceanEnts.Ent>:
  match pieces:
    case Nil{}:
      OceanEnts.of_land(ents)
    case Con{+p, rest}:
      OceanEnts.tagged(OceanEnts.of_land(ents), p <> rest)

def sea_of(landed: Landed) -> OceanState.Sea:
  match landed:
    case Landed{g, +rng, +ents, +s, _, +pieces, _}:
      OceanState.Sea{g, Grid.new(0, 0, 0), rng, ocean_ents(ents, pieces), topology_count(s), piece_events(pieces, Nil{})}

def drawn(got: U32 & Pcg.Rng, +c: Generate.Seed, +a: U32, g: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +w: U32, +pieces: List<&2, PopulateSetpiece.Piece>, +roads: List<&2, List<&2, TileWorld.Point>>) -> Job:
  (+min_road, +rng) = got
  JWorld{c, a, Final{g, rng, ents, w, pieces, roads, min_road}}

# The required prefab check's verdict: the world (after the road length draw, math.random(3, 5)), or the next attempt
# from the RNG after the ocean stage.
def verdict(ok: Bool, +c: Generate.Seed, +a: U32, sea: OceanState.Sea, +w: U32, +roads: List<&2, List<&2, TileWorld.Point>>) -> Job:
  match ok:
    case True{}:
      match sea:
        case OceanState.Sea{g, _, +rng, +ents, _, +events}:
          drawn(MathRandom.random_range(rng, 3, 5), c, a, g, ents, w, OceanState.pieces(events), roads)
    case False{}:
      match sea:
        case OceanState.Sea{_, _, +rng, _, _, _}:
          retry(c, a, rng)

def oceaned(got: OceanState.Sea & Bool, +c: Generate.Seed, +a: U32, +w: U32, +roads: List<&2, List<&2, TileWorld.Point>>) -> Job:
  (sea, +ok) = got
  verdict(ok, c, a, sea, w, roads)

# The ocean stage from land_done to the required prefab check (no node-id map, no tracing).
def ocean(+c: Generate.Seed, +a: U32, landed: Landed) -> Job:
  match landed:
    case Landed{g, +rng, +ents, +s, +w, +pieces, +roads}:
      +ctx = {OceanState.Ctx{Generate.windows_of(c), Generate.swaps_of(c), w, w, False{}, Generate.pieces_of(c)} : OceanState.Ctx}
      oceaned(Ocean.run(ctx, OceanRequired.required(s), sea_of(Landed{g, rng, ents, s, w, pieces, roads})), c, a, w, roads)

def maze_landed(m: CaveMaze.Mazed, +cave: List<&2, Entities.Ent>, +w: U32) -> PopulateState.Land:
  match m:
    case CaveMaze.Mazed{g, rng, +ents, built}:
      PopulateState.Land{g, rng, List.append(&2, Entities.Ent, ents, cave),
        MazePieces.events(built, ents, U32.from_nat(List.length(&2, Entities.Ent, cave)), w)}

def mazed_job(land: PopulateState.Land, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +sites: Points.Sites) -> Job:
  JMazed{c, a, s, k, w, land, sites}

# The Labyrinth and Maze passes (cave_maze.bend) on the tile map, with the custom tile pass's items as the first entities.
def mazes(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, g: Grid.Grid, +rng: Pcg.Rng, +placed: List<&2, CaveCustom.Placed>, +sites: Points.Sites) -> Job:
  mazed_job(maze_landed(CaveMaze.run(c, s, k, w, g, rng, placed, sites), CaveCustom.entities(placed, w, w, rng), w), c, a, s, k, w, sites)

def cave_failed(land: PopulateState.Land, +c: Generate.Seed, +a: U32, +s: StoryGraph.St) -> Job:
  match land:
    case PopulateState.Land{_, +rng, _, _}:
      retry(Generate.carried(c, s), a, rng)

def cave_populated(got: PopulateState.Land & Bool, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +w: U32) -> Job:
  (land, +ok) = got
  match ok:
    case True{}:
      JPost{c, a, s, w, land}
    case False{}:
      cave_failed(land, c, a, s)

def cave_land_of(start: U32 & U32, land: PopulateState.Land, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +sites: Points.Sites) -> Job:
  (+sx, +sy) = start
  cave_populated(PopulateLand.land_caves(Generate.land_context(c, s, k, sites, w, False{}), sx, sy, land), c, a, s, w)

# ConvertGround to PopulateVoronoi; a failed DetectDisconnect retries from the RNG then.
def populate_caves(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, land: PopulateState.Land, +sites: Points.Sites) -> Job:
  cave_land_of(Generate.cave_start(s, k, sites), land, c, a, s, k, w, sites)

# The layouts and mazes the land placed, when the job records them.
def cave_pieces(recording: Bool, +events: List<&2, PopulateState.Ev>) -> List<&2, PopulateSetpiece.Piece>:
  match recording:
    case True{}:
      PopulateState.pieces(events)
    case False{}:
      Nil{}

def cave_shard() -> Finish.Shard:
  Finish.Shard{CaveNames.wormhole(), CaveNames.dispenser(), CaveNames.temporary()}

def cave_verdict(ok: Bool, sea: OceanState.Sea, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +w: U32) -> Job:
  match ok:
    case True{}:
      match sea:
        case OceanState.Sea{g, _, +rng, +ents, _, +events}:
          JWorld{c, a, Final{g, rng, ents, w, OceanState.pieces(events), Nil{}, 0}}
    case False{}:
      match sea:
        case OceanState.Sea{_, _, +rng, _, _, _}:
          retry(Generate.carried(c, s), a, rng)

def cave_posted(got: OceanState.Sea & Bool, +c: Generate.Seed, +a: U32, +s: StoryGraph.St, +w: U32) -> Job:
  (sea, +ok) = got
  cave_verdict(ok, sea, c, a, s, w)

def atriumed(got: OceanState.Sea & List<&2, OceanEnts.Ent>) -> OceanState.Sea:
  (s, +ents) = got
  OceanState.with_ents(s, Atrium.paired(ents, CaveNames.atrium()))

# GlobalPostPopulate to the required prefab check on the caves' land (no roads: the world has no road length draw).
def post_caves(+c: Generate.Seed, +a: U32, +s: StoryGraph.St, +w: U32, land: PopulateState.Land) -> Job:
  match land:
    case PopulateState.Land{g, +rng, +ents, +events}:
      +ctx = {OceanState.Ctx{Generate.windows_of(c), Generate.swaps_of(c), w, w, False{}, Generate.pieces_of(c)} : OceanState.Ctx}
      cave_posted(Finish.run(ctx, cave_shard(), CaveRequired.required(s), atriumed(OceanState.ents_of(sea_of(Landed{g, rng, ents, s, w, cave_pieces(Generate.pieces_of(c), events), Nil{}})))), c, a, s, w)

# One stage transition. JFirst and JSecond wait (see layout), JWorld and JDone stay as they are.
def step(job: Job) -> Job:
  match job:
    case JStart{+c, +a, +rng}:
      started(Generate.crashed(c), c, a, rng)
    case JCommit{+c, +a, +s, +k, +second}:
      commit(c, a, s, k, second)
    case JTiles{+c, +a, +s, +k, +size, +sites}:
      tiles(c, a, s, k, size, sites)
    case JLand{+c, +a, +s, +k, +w, +world, +lists, +sites}:
      land(c, a, s, k, w, world, lists, sites)
    case JOcean{+c, +a, landed}:
      ocean(c, a, landed)
    case JTiled{+c, +a, +s, +k, +w, grid, +rng, +placed, +sites}:
      mazes(c, a, s, k, w, grid, rng, placed, sites)
    case JMazed{+c, +a, +s, +k, +w, land, +sites}:
      populate_caves(c, a, s, k, w, land, sites)
    case JPost{+c, +a, +s, +w, land}:
      post_caves(c, a, s, w, land)
    case other:
      other

def advanced(got: Job & Maybe<&2, GenLayout.Layout>) -> Job:
  (job, pass) = got
  match pass:
    case Some{+l}:
      laid(job, GenLayout.local(l))
    case None{}:
      step(job)

# One step, a waiting job's whole KK pass on this thread (GenLayout.local) included.
def advance(job: Job) -> Job:
  advanced(layout(job))

def solved(got: Job & Maybe<&2, GenLayout.Layout>, +native: Bool) -> IO(Job):
  (job, pass) = got
  match pass:
    case Some{+l}:
      do IO<Job>:
        +ps : List<&2, LayoutSpace.Vec> <- GenLayout.solve(native, l)
        return laid(job, ps)
    case None{}:
      IO.pure(Job, step(job))

# One step, a waiting job's KK pass from GenLayout.solve included.
def advance_io(+native: Bool, job: Job) -> IO(Job):
  solved(layout(job), native)

# Where a job is: its stage number (see Job) and attempt.
type Where is Data:
  Where{stage: U32, a: U32}

def stage(job: Job) -> Job & Where:
  match job:
    case JStart{+c, +a, +rng}:
      (JStart{c, a, rng}, Where{0, a})
    case JFirst{+c, +a, +s, +k}:
      (JFirst{c, a, s, k}, Where{1, a})
    case JSecond{+c, +a, +s, +k, +first}:
      (JSecond{c, a, s, k, first}, Where{2, a})
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
    case JTiled{+c, +a, +s, +k, +w, grid, +rng, placed, +sites}:
      (JTiled{c, a, s, k, w, grid, rng, placed, sites}, Where{10, a})
    case JMazed{+c, +a, +s, +k, +w, land, +sites}:
      (JMazed{c, a, s, k, w, land, sites}, Where{11, a})
    case JPost{+c, +a, +s, +w, land}:
      (JPost{c, a, s, w, land}, Where{12, a})

# Whether the job is decided (a world, or no world).
def settled(+stage: U32) -> Bool:
  U32.is_eq(stage, 7) || U32.is_eq(stage, 8)
