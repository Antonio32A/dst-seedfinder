import Base
import ../rng/pcg.bend as Pcg
import ../f64/repr.bend as F64Repr
import ../level/summary.bend as LevelSummary
import ../level/choose.bend as LevelChoose
import ../storygen/graph.bend as StoryGraph
import ../storygen/story.bend as Story
import ../worldsim/layout/space.bend as LayoutSpace
import ../worldsim/voronoi/diagram.bend as VoronoiDiagram
import ../worldsim/voronoi/builder.bend as VoronoiBuilder
import ../worldsim/voronoi/polygon.bend as VoronoiPolygon
import ../worldsim/commit.bend as Commit
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/table.bend as TileTable
import ../worldsim/tiles/world.bend as TileWorld
import ../worldsim/tiles/convert.bend as TileConvert
import ../worldsim/tiles/separate.bend as TileSeparate
import ../worldsim/tiles/connect.bend as TileConnect
import ../worldsim/tiles/roads.bend as TileRoads
import ../populate/entities.bend as Entities
import ../populate/state.bend as PopulateState
import ../populate/land.bend as Land
import ./graph.bend as GenGraph
import ./tags.bend as GenTags
import ./world.bend as GenWorld

# forest_map.Generate from a seed to land_done (the end of Graph:PopulateVoronoi), one attempt at a time, as stage
# functions that gen/job.bend chains and the `gen` trace stage prints: the story to VoronoiPass(100), each KK pass,
# the BuildVoronoi of each pass, the rest of the story to WorldGen_Commit (retry point 1: CheckForValidCells),
# ApplyPoisonTag, ConvertToTileMap and the tile stages, the GetSiteArea < 8 check (retry point 2), and the land
# population. A failed attempt hands its RNG to the next one (worldgen_main.lua: up to 5 Generate calls, no reseed).

# SetWorldSize and ConvertToTileMap's min_size for world_size "default".
def world_size() -> U32:
  425

def max_attempts() -> U32:
  5

def first_runs() -> U32:
  100

def second_runs() -> U32:
  50

# A seed's fixed inputs: the seed, the platform, its level table (part A) and whether to record the layouts the world
# generation places (populate/setpiece.bend).
type Seed is Data:
  Seed{seed: U32, windows: Bool, level: LevelSummary.Summary, pieces: Bool}

def seed_inputs(+seed: U32, +windows: Bool, +pieces: Bool) -> Seed:
  Seed{seed, windows, LevelSummary.summary(seed), pieces}

def seed_of(+c: Seed) -> U32:
  match c:
    case Seed{+seed, _, _, _}:
      seed

def windows_of(+c: Seed) -> Bool:
  match c:
    case Seed{_, +windows, _, _}:
      windows

def level_of(+c: Seed) -> LevelSummary.Summary:
  match c:
    case Seed{_, _, +level, _}:
      level

def swaps_of(+c: Seed) -> U32:
  match c:
    case Seed{_, _, LevelSummary.Summary{+swaps, _, _, _, _, _, _}, _}:
      swaps

def pieces_of(+c: Seed) -> Bool:
  match c:
    case Seed{_, _, _, +pieces}:
      pieces

# The level table raises a Lua error before Generate.
def crashed(+c: Seed) -> Bool:
  match c:
    case Seed{_, _, LevelSummary.Summary{_, _, _, _, _, _, +crashed}, _}:
      crashed

# The RNG at the first attempt's first WorldSim call.
def first_rng(+c: Seed) -> Pcg.Rng:
  LevelChoose.generate_rng(seed_of(c))

# Generate from its first WorldSim call to WorldGen_VoronoiPass(100).
def first_story(+c: Seed, +rng: Pcg.Rng) -> StoryGraph.St:
  Story.build(level_of(c), rng)

def centroid_of(+p: VoronoiPolygon.Poly) -> VoronoiPolygon.P32:
  match p:
    case VoronoiPolygon.Poly{_, +cx, +cy, _, _}:
      VoronoiPolygon.P32{cx, cy}

def centroids(ps: List<&2, VoronoiPolygon.Poly>) -> List<&2, VoronoiPolygon.P32>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      centroid_of(p) <> centroids(rest)

def site_in(+s: StoryGraph.St, +x: U32, +p: LayoutSpace.Vec, +c: VoronoiPolygon.P32) -> VoronoiPolygon.SiteIn:
  match p:
    case LayoutSpace.Vec{+px, +py}:
      match c:
        case VoronoiPolygon.P32{+cx, +cy}:
          VoronoiPolygon.SiteIn{F64Repr.to_f32_bits(px), F64Repr.to_f32_bits(py), GenWorld.cpp_type(StoryGraph.nf(s, x, StoryGraph.f_type())), cx, cy}

def sites_loop(vs: List<&2, U32>, ps: List<&2, LayoutSpace.Vec>, cs: List<&2, VoronoiPolygon.P32>, +s: StoryGraph.St) -> List<&2, VoronoiPolygon.SiteIn>:
  match vs ps:
    case Con{+x, rest} Con{+p, prest}:
      match cs:
        case Nil{}:
          site_in(s, x, p, VoronoiPolygon.P32{0, 0}) <> sites_loop(rest, prest, Nil{}, s)
        case Con{+c, crest}:
          site_in(s, x, p, c) <> sites_loop(rest, prest, crest, s)
    case _ _:
      Nil{}

# KamadaKawaiPass's sites: the float positions in vertex order, each node's type, and its centroid from the build
# before (a node new to the graph has (0, 0)).
def pass_sites(+s: StoryGraph.St, +k: GenGraph.Klei, +ps: List<&2, LayoutSpace.Vec>, +before: List<&2, VoronoiPolygon.Poly>) -> List<&2, VoronoiPolygon.SiteIn>:
  sites_loop(GenGraph.vertices_of(k), ps, centroids(before), s)

# The BuildVoronoi at the end of a VoronoiPass.
def pass_build(+c: Seed, +sites: List<&2, VoronoiPolygon.SiteIn>) -> VoronoiPolygon.Cells:
  VoronoiPolygon.build_voronoi(windows_of(c), world_size(), world_size(), sites)

def cells_polys(cells: VoronoiPolygon.Cells) -> List<&2, VoronoiPolygon.Poly>:
  match cells:
    case VoronoiPolygon.Cells{_, polys, +n}:
      GenWorld.poly_list(polys, n)

def answer_loop(vs: List<&2, U32>, ss: List<&2, VoronoiPolygon.SiteIn>, +s: StoryGraph.St) -> StoryGraph.St:
  match vs ss:
    case Con{+x, rest} Con{VoronoiPolygon.SiteIn{+sx, +sy, _, _, _}, srest}:
      +slot = (StoryGraph.site_base() + (x * 2 : U32) : U32)
      answer_loop(rest, srest, StoryGraph.put(StoryGraph.put(s, slot, sx), (slot + 1 : U32), sy))
    case _ _:
      s

# The GetSite answers of every linked node, stored where FindMainlandNodesForNewRegion reads them.
def with_sites(+s: StoryGraph.St, +k: GenGraph.Klei, +sites: List<&2, VoronoiPolygon.SiteIn>) -> StoryGraph.St:
  answer_loop(GenGraph.vertices_of(k), sites, s)

# Story:AddRegionsToMainland to WorldGen_Commit, once VoronoiPass(100)'s sites are known.
def second_story(+c: Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +sites: List<&2, VoronoiPolygon.SiteIn>) -> StoryGraph.St:
  Story.finish(with_sites(s, k, sites), level_of(c))

def point_count(l: List<&2, VoronoiPolygon.P32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      point_count(rest, (acc + 1 : U32))

def poly_points(+p: VoronoiPolygon.Poly) -> U32:
  match p:
    case VoronoiPolygon.Poly{+pts, _, _, _, _}:
      point_count(pts, 0)

def counts_of(ps: List<&2, VoronoiPolygon.Poly>) -> List<&2, U32>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      poly_points(p) <> counts_of(rest)

def points_of_vertex(+v: U32, +counts: TileTable.Tree<U32>) -> U32:
  Bool.pick(U32, TileWorld.is_none(v), 0, TileTable.at(~U32, counts, v))

def checks_loop(n: Nat, +s: StoryGraph.St, +k: GenGraph.Klei, +counts: TileTable.Tree<U32>, +x: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      +check = {Commit.NodeCheck{GenWorld.cpp_type(StoryGraph.nf(s, x, StoryGraph.f_type())), Bool.not(TileWorld.is_none(GenGraph.parent_of(k, x))), points_of_vertex(GenGraph.vertex_of(k, x), counts)} : Commit.NodeCheck}
      Commit.node_ok(check) && checks_loop(p, s, k, counts, (x + 1 : U32))

# CheckForValidCells over the story nodes (the graph objects have no parent, so they always pass).
def valid_cells(+s: StoryGraph.St, +k: GenGraph.Klei, +polys: List<&2, VoronoiPolygon.Poly>) -> Bool:
  checks_loop(U32.to_nat(StoryGraph.get(s, StoryGraph.s_nodes())), s, k, TileTable.from_list(~U32, counts_of(polys), 0), 0)

def cut_loop(vs: List<&2, U32>, +s: StoryGraph.St) -> List<&2, U32>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      GenTags.disconnected(s, x) <> cut_loop(rest, s)

# ApplyPoisonTag's ClearNodeLinks: the graph edges left.
def poisoned_edges(+s: StoryGraph.St, +k: GenGraph.Klei) -> List<&2, GenGraph.Link>:
  GenGraph.cleared(GenGraph.edges_of(k), TileTable.from_list(~U32, cut_loop(GenGraph.vertices_of(k), s), 0))

# ConvertToTileMap's size and centred sites (ScaleAndCenter from the Commit size).
def tile_size(+size: U32) -> U32:
  Commit.tile_map_size(world_size(), size, size)

def tile_sites(+size: U32, +sites: List<&2, VoronoiPolygon.SiteIn>) -> Commit.Centred:
  Commit.tile_map_centre(sites, tile_size(size), size, size)

def centred_sites(+cm: Commit.Centred) -> List<&2, VoronoiPolygon.SiteIn>:
  match cm:
    case Commit.Centred{+sites, _}:
      sites

def tile_centred(+size: U32, +sites: List<&2, VoronoiPolygon.SiteIn>) -> List<&2, VoronoiPolygon.SiteIn>:
  centred_sites(tile_sites(size, sites))

# ConvertToTileMap's BuildVoronoi of the centred sites.
def tile_build(+c: Seed, +size: U32, +sites: List<&2, VoronoiPolygon.SiteIn>) -> VoronoiPolygon.Cells:
  +w = tile_size(size)
  VoronoiPolygon.build_voronoi(windows_of(c), w, w, tile_centred(size, sites))

def with_centroids(ss: List<&2, VoronoiPolygon.SiteIn>, +polys: List<&2, VoronoiPolygon.Poly>) -> List<&2, VoronoiPolygon.SiteIn>:
  match ss polys:
    case Con{VoronoiPolygon.SiteIn{+x, +y, +kind, _, _}, rest} Con{VoronoiPolygon.Poly{_, +cx, +cy, _, _}, prest}:
      VoronoiPolygon.SiteIn{x, y, kind, cx, cy} <> with_centroids(rest, prest)
    case _ _:
      ss

# A finished VoronoiPass: the KK positions (vertex order), the sites BuildVoronoi got and its polygons.
type Pass is Data:
  Pass{ps: List<&2, LayoutSpace.Vec>, sites: List<&2, VoronoiPolygon.SiteIn>, polys: List<&2, VoronoiPolygon.Poly>}

def pass_positions(+p: Pass) -> List<&2, LayoutSpace.Vec>:
  match p:
    case Pass{+ps, _, _}:
      ps

def pass_site_list(+p: Pass) -> List<&2, VoronoiPolygon.SiteIn>:
  match p:
    case Pass{_, +sites, _}:
      sites

def pass_polys(+p: Pass) -> List<&2, VoronoiPolygon.Poly>:
  match p:
    case Pass{_, _, +polys}:
      polys

# The positions, sites and polygons of a pass that has ended (`before`: the polygons of the pass before, if any).
def pass_of(+c: Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +ps: List<&2, LayoutSpace.Vec>, +before: List<&2, VoronoiPolygon.Poly>) -> Pass:
  +sites = pass_sites(s, k, ps, before)
  Pass{ps, sites, cells_polys(pass_build(c, sites))}

# WorldGen_Commit from VoronoiPass(50): the sites carry that build's centroids.
def commit(+c: Seed, +p: Pass) -> Commit.Committed:
  Commit.commit(windows_of(c), world_size(), world_size(), with_centroids(pass_site_list(p), pass_polys(p)))

def tile_world_cells(+s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +sites: List<&2, VoronoiPolygon.SiteIn>, +polys: List<&2, VoronoiPolygon.Poly>, got: VoronoiDiagram.Diagram & List<&2, TileWorld.Cell>) -> TileWorld.World:
  (_, +cs) = got
  GenWorld.world(w, sites, polys, GenWorld.nodes(s, k), cs, poisoned_edges(s, k))

def tile_world_built(+s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +sites: List<&2, VoronoiPolygon.SiteIn>, built: VoronoiBuilder.Built, +polys: List<&2, VoronoiPolygon.Poly>) -> TileWorld.World:
  match built:
    case VoronoiBuilder.Built{_, _, d}:
      tile_world_cells(s, k, w, sites, polys, GenWorld.cells(d, sites, w, w))

# The TileWorld.World of ConvertToTileMap's build (M8's tile input).
def tile_world(+s: StoryGraph.St, +k: GenGraph.Klei, +w: U32, +sites: List<&2, VoronoiPolygon.SiteIn>, cells: VoronoiPolygon.Cells) -> TileWorld.World:
  match cells:
    case VoronoiPolygon.Cells{built, polys, +n}:
      tile_world_built(s, k, w, sites, built, GenWorld.poly_list(polys, n))

def areas_ok(n: Nat, +s: StoryGraph.St, +k: GenGraph.Klei, +sites: Points.Sites, +x: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      +v = GenGraph.vertex_of(k, x)
      +blank = U32.is_eq(StoryGraph.nf(s, x, StoryGraph.f_kind()), StoryGraph.id_loop_sub())
      +area = Bool.pick(U32, TileWorld.is_none(v), 0, Points.site_area(sites, v))
      (blank || (7 < area : U32)) && areas_ok(p, s, k, sites, (x + 1 : U32))

# The encode check: every topology node but LOOP_BLANK_SUB has GetSiteArea >= 8.
def site_areas_ok(+s: StoryGraph.St, +k: GenGraph.Klei, +sites: Points.Sites) -> Bool:
  areas_ok(U32.to_nat(StoryGraph.get(s, StoryGraph.s_nodes())), s, k, sites, 0)

# The RNG after ConvertToTileMap (the variant draws of every cell are a jump); nothing else draws before ConvertGround.
def rng_after_tiles(+s: StoryGraph.St, +w: U32) -> Pcg.Rng:
  Pcg.advance(StoryGraph.rng_of(s), (w * w : U32))

# ConvertToTileMap's paint, SeparateIslands, ForceConnectivity and DrawRoads: the drawn grid and GetRoads' polylines.
def tile_grid(+windows: Bool, +w: TileWorld.World, +lists: List<&2, List<&2, U32>>) -> Grid.Grid & List<&2, List<&2, TileWorld.Point>>:
  +isl = TileConnect.islands(w, False{})
  +roads = TileRoads.roads(windows, w, isl)
  (TileRoads.draw_roads(windows, roads, TileConnect.force(w, isl, TileSeparate.separate(w, TileConvert.paint(w, lists)))), roads)

# The land context: the RNG at ConvertToTileMap is the story's RNG at Commit (the flag digests replay its variant draws).
def land_context(+c: Seed, +s: StoryGraph.St, +k: GenGraph.Klei, +sites: Points.Sites, +w: U32, +tracing: Bool) -> PopulateState.Ctx:
  PopulateState.Ctx{windows_of(c), swaps_of(c), sites, s, GenGraph.vertex_table(k), w, w, tracing, StoryGraph.rng_of(s), pieces_of(c)}

# Graph:ConvertGround to the end of Graph:PopulateVoronoi, from the grid after DrawRoads.
def land(+ctx: PopulateState.Ctx, g: Grid.Grid, +w: U32) -> PopulateState.Land:
  Land.land(ctx, PopulateState.Land{g, rng_after_tiles(PopulateState.story_of(ctx), w), Nil{}, Nil{}})
