import Base
import ../rng/pcg.bend as R
import ../f64/repr.bend as FR
import ../level/summary.bend as W
import ../level/choose.bend as CH
import ../storygen/graph.bend as GG
import ../storygen/story.bend as GY
import ../worldsim/layout/space.bend as KS
import ../worldsim/voronoi/diagram.bend as VD
import ../worldsim/voronoi/builder.bend as VB
import ../worldsim/voronoi/polygon.bend as VG
import ../worldsim/commit.bend as CM
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/table.bend as TB
import ../worldsim/tiles/world.bend as TW
import ../worldsim/tiles/convert.bend as TC
import ../worldsim/tiles/separate.bend as TI
import ../worldsim/tiles/connect.bend as TF
import ../worldsim/tiles/roads.bend as TR
import ../populate/entities.bend as PE
import ../populate/state.bend as PS
import ../populate/land.bend as PD
import ./graph.bend as GK
import ./tags.bend as GP
import ./world.bend as GW

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

# A seed's fixed inputs: the seed, the platform and its level table (part A).
type Seed is Data:
  Seed{seed: U32, windows: Bool, level: W.Summary}

def seed_inputs(+seed: U32, +windows: Bool) -> Seed:
  Seed{seed, windows, W.summary(seed)}

def seed_of(+c: Seed) -> U32:
  match c:
    case Seed{+seed, _, _}:
      seed

def windows_of(+c: Seed) -> Bool:
  match c:
    case Seed{_, +windows, _}:
      windows

def level_of(+c: Seed) -> W.Summary:
  match c:
    case Seed{_, _, +level}:
      level

def swaps_of(+c: Seed) -> U32:
  match c:
    case Seed{_, _, W.Summary{+swaps, _, _, _, _, _, _}}:
      swaps

# The level table raises a Lua error before Generate.
def crashed(+c: Seed) -> Bool:
  match c:
    case Seed{_, _, W.Summary{_, _, _, _, _, _, +crashed}}:
      crashed

# The RNG at the first attempt's first WorldSim call.
def first_rng(+c: Seed) -> R.Rng:
  CH.generate_rng(seed_of(c))

# Generate from its first WorldSim call to WorldGen_VoronoiPass(100).
def first_story(+c: Seed, +rng: R.Rng) -> GG.St:
  GY.build(level_of(c), rng)

def centroid_of(+p: VG.Poly) -> VG.P32:
  match p:
    case VG.Poly{_, +cx, +cy, _, _}:
      VG.P32{cx, cy}

def centroids(ps: List<&2, VG.Poly>) -> List<&2, VG.P32>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      centroid_of(p) <> centroids(rest)

def site_in(+s: GG.St, +x: U32, +p: KS.Vec, +c: VG.P32) -> VG.SiteIn:
  match p:
    case KS.Vec{+px, +py}:
      match c:
        case VG.P32{+cx, +cy}:
          VG.SiteIn{FR.to_f32_bits(px), FR.to_f32_bits(py), GW.cpp_type(GG.nf(s, x, GG.f_type())), cx, cy}

def sites_loop(vs: List<&2, U32>, ps: List<&2, KS.Vec>, cs: List<&2, VG.P32>, +s: GG.St) -> List<&2, VG.SiteIn>:
  match vs ps:
    case Con{+x, rest} Con{+p, prest}:
      match cs:
        case Nil{}:
          site_in(s, x, p, VG.P32{0, 0}) <> sites_loop(rest, prest, Nil{}, s)
        case Con{+c, crest}:
          site_in(s, x, p, c) <> sites_loop(rest, prest, crest, s)
    case _ _:
      Nil{}

# KamadaKawaiPass's sites: the float positions in vertex order, each node's type, and its centroid from the build
# before (a node new to the graph has (0, 0)).
def pass_sites(+s: GG.St, +k: GK.Klei, +ps: List<&2, KS.Vec>, +before: List<&2, VG.Poly>) -> List<&2, VG.SiteIn>:
  sites_loop(GK.vertices_of(k), ps, centroids(before), s)

# The BuildVoronoi at the end of a VoronoiPass.
def pass_build(+c: Seed, +sites: List<&2, VG.SiteIn>) -> VG.Cells:
  VG.build_voronoi(windows_of(c), world_size(), world_size(), sites)

def cells_polys(cells: VG.Cells) -> List<&2, VG.Poly>:
  match cells:
    case VG.Cells{_, polys, +n}:
      GW.poly_list(polys, n)

def answer_loop(vs: List<&2, U32>, ss: List<&2, VG.SiteIn>, +s: GG.St) -> GG.St:
  match vs ss:
    case Con{+x, rest} Con{VG.SiteIn{+sx, +sy, _, _, _}, srest}:
      +slot = (GG.site_base() + (x * 2 : U32) : U32)
      answer_loop(rest, srest, GG.put(GG.put(s, slot, sx), (slot + 1 : U32), sy))
    case _ _:
      s

# The GetSite answers of every linked node, stored where FindMainlandNodesForNewRegion reads them.
def with_sites(+s: GG.St, +k: GK.Klei, +sites: List<&2, VG.SiteIn>) -> GG.St:
  answer_loop(GK.vertices_of(k), sites, s)

# Story:AddRegionsToMainland to WorldGen_Commit, once VoronoiPass(100)'s sites are known.
def second_story(+c: Seed, +s: GG.St, +k: GK.Klei, +sites: List<&2, VG.SiteIn>) -> GG.St:
  GY.finish(with_sites(s, k, sites), level_of(c))

def point_count(l: List<&2, VG.P32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      point_count(rest, (acc + 1 : U32))

def poly_points(+p: VG.Poly) -> U32:
  match p:
    case VG.Poly{+pts, _, _, _, _}:
      point_count(pts, 0)

def counts_of(ps: List<&2, VG.Poly>) -> List<&2, U32>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      poly_points(p) <> counts_of(rest)

def points_of_vertex(+v: U32, +counts: TB.Tree<U32>) -> U32:
  Bool.pick(U32, TW.is_none(v), 0, TB.at(~U32, counts, v))

def checks_loop(n: Nat, +s: GG.St, +k: GK.Klei, +counts: TB.Tree<U32>, +x: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      +check = {CM.NodeCheck{GW.cpp_type(GG.nf(s, x, GG.f_type())), Bool.not(TW.is_none(GK.parent_of(k, x))), points_of_vertex(GK.vertex_of(k, x), counts)} : CM.NodeCheck}
      CM.node_ok(check) && checks_loop(p, s, k, counts, (x + 1 : U32))

# CheckForValidCells over the story nodes (the graph objects have no parent, so they always pass).
def valid_cells(+s: GG.St, +k: GK.Klei, +polys: List<&2, VG.Poly>) -> Bool:
  checks_loop(U32.to_nat(GG.get(s, GG.s_nodes())), s, k, TB.from_list(~U32, counts_of(polys), 0), 0)

def cut_loop(vs: List<&2, U32>, +s: GG.St) -> List<&2, U32>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      GP.disconnected(s, x) <> cut_loop(rest, s)

# ApplyPoisonTag's ClearNodeLinks: the graph edges left.
def poisoned_edges(+s: GG.St, +k: GK.Klei) -> List<&2, GK.Link>:
  GK.cleared(GK.edges_of(k), TB.from_list(~U32, cut_loop(GK.vertices_of(k), s), 0))

# ConvertToTileMap's size and centred sites (ScaleAndCenter from the Commit size).
def tile_size(+size: U32) -> U32:
  CM.tile_map_size(world_size(), size, size)

def tile_sites(+size: U32, +sites: List<&2, VG.SiteIn>) -> CM.Centred:
  CM.tile_map_centre(sites, tile_size(size), size, size)

def centred_sites(+cm: CM.Centred) -> List<&2, VG.SiteIn>:
  match cm:
    case CM.Centred{+sites, _}:
      sites

def tile_centred(+size: U32, +sites: List<&2, VG.SiteIn>) -> List<&2, VG.SiteIn>:
  centred_sites(tile_sites(size, sites))

# ConvertToTileMap's BuildVoronoi of the centred sites.
def tile_build(+c: Seed, +size: U32, +sites: List<&2, VG.SiteIn>) -> VG.Cells:
  +w = tile_size(size)
  VG.build_voronoi(windows_of(c), w, w, tile_centred(size, sites))

def with_centroids(ss: List<&2, VG.SiteIn>, +polys: List<&2, VG.Poly>) -> List<&2, VG.SiteIn>:
  match ss polys:
    case Con{VG.SiteIn{+x, +y, +kind, _, _}, rest} Con{VG.Poly{_, +cx, +cy, _, _}, prest}:
      VG.SiteIn{x, y, kind, cx, cy} <> with_centroids(rest, prest)
    case _ _:
      ss

# A finished VoronoiPass: the KK positions (vertex order), the sites BuildVoronoi got and its polygons.
type Pass is Data:
  Pass{ps: List<&2, KS.Vec>, sites: List<&2, VG.SiteIn>, polys: List<&2, VG.Poly>}

def pass_positions(+p: Pass) -> List<&2, KS.Vec>:
  match p:
    case Pass{+ps, _, _}:
      ps

def pass_site_list(+p: Pass) -> List<&2, VG.SiteIn>:
  match p:
    case Pass{_, +sites, _}:
      sites

def pass_polys(+p: Pass) -> List<&2, VG.Poly>:
  match p:
    case Pass{_, _, +polys}:
      polys

# The positions, sites and polygons of a pass that has ended (`before`: the polygons of the pass before, if any).
def pass_of(+c: Seed, +s: GG.St, +k: GK.Klei, +ps: List<&2, KS.Vec>, +before: List<&2, VG.Poly>) -> Pass:
  +sites = pass_sites(s, k, ps, before)
  Pass{ps, sites, cells_polys(pass_build(c, sites))}

# WorldGen_Commit from VoronoiPass(50): the sites carry that build's centroids.
def commit(+c: Seed, +p: Pass) -> CM.Committed:
  CM.commit(windows_of(c), world_size(), world_size(), with_centroids(pass_site_list(p), pass_polys(p)))

def tile_world_cells(+s: GG.St, +k: GK.Klei, +w: U32, +sites: List<&2, VG.SiteIn>, +polys: List<&2, VG.Poly>, got: VD.Diagram & List<&2, TW.Cell>) -> TW.World:
  (_, +cs) = got
  GW.world(w, sites, polys, GW.nodes(s, k), cs, poisoned_edges(s, k))

def tile_world_built(+s: GG.St, +k: GK.Klei, +w: U32, +sites: List<&2, VG.SiteIn>, built: VB.Built, +polys: List<&2, VG.Poly>) -> TW.World:
  match built:
    case VB.Built{_, _, d}:
      tile_world_cells(s, k, w, sites, polys, GW.cells(d, sites, w, w))

# The TW.World of ConvertToTileMap's build (M8's tile input).
def tile_world(+s: GG.St, +k: GK.Klei, +w: U32, +sites: List<&2, VG.SiteIn>, cells: VG.Cells) -> TW.World:
  match cells:
    case VG.Cells{built, polys, +n}:
      tile_world_built(s, k, w, sites, built, GW.poly_list(polys, n))

def areas_ok(n: Nat, +s: GG.St, +k: GK.Klei, +sites: PT.Sites, +x: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      +v = GK.vertex_of(k, x)
      +blank = U32.is_eq(GG.nf(s, x, GG.f_kind()), GG.id_loop_sub())
      +area = Bool.pick(U32, TW.is_none(v), 0, PT.site_area(sites, v))
      (blank || (7 < area : U32)) && areas_ok(p, s, k, sites, (x + 1 : U32))

# The encode check: every topology node but LOOP_BLANK_SUB has GetSiteArea >= 8.
def site_areas_ok(+s: GG.St, +k: GK.Klei, +sites: PT.Sites) -> Bool:
  areas_ok(U32.to_nat(GG.get(s, GG.s_nodes())), s, k, sites, 0)

# The RNG after ConvertToTileMap (the variant draws of every cell are a jump); nothing else draws before ConvertGround.
def rng_after_tiles(+s: GG.St, +w: U32) -> R.Rng:
  R.advance(GG.rng_of(s), (w * w : U32))

# ConvertToTileMap's paint, SeparateIslands, ForceConnectivity and DrawRoads.
def tile_grid(+windows: Bool, +w: TW.World, +lists: List<&2, List<&2, U32>>) -> GR.Grid:
  +isl = TF.islands(w, False{})
  TR.draw_roads(windows, TR.roads(windows, w, isl), TF.force(w, isl, TI.separate(w, TC.paint(w, lists))))

# The land context: the RNG at ConvertToTileMap is the story's RNG at Commit (the flag digests replay its variant draws).
def land_context(+c: Seed, +s: GG.St, +k: GK.Klei, +sites: PT.Sites, +w: U32, +tracing: Bool) -> PS.Ctx:
  PS.Ctx{windows_of(c), swaps_of(c), sites, s, GK.vertex_table(k), w, w, tracing, GG.rng_of(s)}

# Graph:ConvertGround to the end of Graph:PopulateVoronoi, from the grid after DrawRoads.
def land(+ctx: PS.Ctx, g: GR.Grid, +w: U32) -> PS.Land:
  PD.land(ctx, PS.Land{g, rng_after_tiles(PS.story_of(ctx), w), Nil{}, Nil{}})
