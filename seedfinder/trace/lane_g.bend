import Base
import ./canon.bend as Canon
import ../f32/ops.bend as F32Ops
import ../f64/repr.bend as F64Repr
import ../worldsim/tiles/table.bend as TileTable
import ../worldsim/tiles/world.bend as TileWorld
import ../worldsim/tiles/sitetiles.bend as SiteTiles
import ../worldsim/tiles/convert.bend as TileConvert
import ../worldsim/tiles/separate.bend as TileSeparate
import ../worldsim/tiles/connect.bend as TileConnect
import ../worldsim/tiles/roads.bend as TileRoads
import ../worldsim/grid.bend as Grid
import ../rng/pcg.bend as Pcg
import ../worldsim/tiles/input.bend as TileInput
import ../populate/trace.bend as PopulateTrace
import ../ocean/trace.bend as OceanTrace

# Lane G (grid) trace stages: `handles` names the stages this file owns, `run` returns their canonical
# records (.scratch/port/CONVENTIONS.md "Trace mode"). Only lane G edits this file.
# Input: the `tileinput` records of lane G's oracle stage (.scratch/port/status/M8.md).

def is_populate(+stage: String) -> Bool:
  String.eq(stage, "populate") || String.eq(stage, "pvoronoi")

def handles(+stage: String) -> Bool:
  String.eq(stage, "sitetiles") || String.eq(stage, "tiles") || is_populate(stage) || OceanTrace.handles(stage)

def stile_lines(tiles: List<&2, U32>, +a: String, +site: U32, +k: U32) -> List<&2, String>:
  match tiles:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      Canon.record("stile", [Canon.field("a", a), Canon.number("site", site), Canon.number("k", k), Canon.number("x", SiteTiles.unpack_x(t)),
        Canon.number("y", SiteTiles.unpack_y(t))]) <> stile_lines(rest, a, site, (k + 1 : U32))

def site_tile_lines(sites: List<&2, TileWorld.Site>, +ids: List<&2, List<&2, String>>, +a: String, +i: U32) -> List<&2, String>:
  match sites:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      +tiles = SiteTiles.site_tiles(s)
      +id = TileInput.text("id", TileInput.first_fields(ids))
      Canon.record("sitetiles", [Canon.field("a", a), Canon.number("site", i), Canon.field("node", id),
        Canon.number("n", U32.from_nat(List.length(&2, U32, tiles)))])
        <> List.append(&2, String, stile_lines(tiles, a, i, 0), site_tile_lines(rest, List.tail(&2, List<&2, String>, ids), a, (i + 1 : U32)))

def sitetiles_world(w: TileWorld.World, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  match w:
    case TileWorld.World{_, _, _, +sites, _, _, _, _, _}:
      site_tile_lines(sites, TileInput.of_attempt("tnode", a, lines), a, 0)

def sitetiles_attempt(+a: String, +lines: List<&2, String>) -> List<&2, String>:
  sitetiles_world(TileInput.world_of(a, lines), a, lines)

def sitetiles_all(as: List<&2, String>, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, sitetiles_attempt(a, lines), sitetiles_all(rest, lines))

type Traced is Type:
  Traced{grid: Grid.Grid, lines: List<&2, String>}

type Context is Data:
  Context{seed: U32, windows: Bool, a: String, before: U32}

def digest_line(+c: Context, +at: String, +ctr: U32, +w: U32, +h: U32, +tiles: Grid.Hash, +flags: Grid.Hash) -> String:
  match c:
    case Context{_, _, +a, _}:
      match tiles:
        case Grid.Hash{+th, +tl}:
          match flags:
            case Grid.Hash{+fh, +fl}:
              Canon.record("tdigest", [Canon.field("a", a), Canon.field("at", Canon.quoted(at)), Canon.number("ctr", ctr), Canon.number("w", w),
                Canon.number("h", h), Canon.field("tiles", Canon.hex64(th, tl)), Canon.field("flags", Canon.hex64(fh, fl))])

def digest_flags(got: Grid.Grid & Grid.Hash, +c: Context, +at: String, +tiles: Grid.Hash, lines: List<&2, String>) -> Traced:
  (g, +flags) = got
  match g:
    case Grid.Grid{cells, +w, +h}:
      match c:
        case Context{+seed, +windows, +a, +before}:
          Traced{Grid.Grid{cells, w, h}, digest_line(Context{seed, windows, a, before}, at, (before + w * h : U32), w, h, tiles, flags) <> lines}

def digest_tiles(got: Grid.Grid & Grid.Hash, +c: Context, +at: String, lines: List<&2, String>) -> Traced:
  (g, +tiles) = got
  match c:
    case Context{+seed, +windows, +a, +before}:
      digest_flags(Grid.flags_digest(g, Pcg.at_counter(seed, before)), Context{seed, windows, a, before}, at, tiles, lines)

# Appends the `tdigest` record of the current maps.
def digest(t: Traced, +c: Context, +at: String) -> Traced:
  match t:
    case Traced{g, lines}:
      digest_tiles(Grid.tiles_digest(g), c, at, lines)

def tiles_done(t: Traced) -> List<&2, String>:
  match t:
    case Traced{_, lines}:
      List.reverse(&2, String, lines)

def separated(t: Traced, +w: TileWorld.World) -> Traced:
  match t:
    case Traced{g, lines}:
      Traced{TileSeparate.separate(w, g), lines}

def conn_lines(ts: List<&2, U32>, +a: String, +site: U32, +k: U32) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      Canon.record("tconn", [Canon.field("a", a), Canon.number("site", site), Canon.number("k", k), Canon.number("to", t), Canon.number("kind", 1)])
        <> conn_lines(rest, a, site, (k + 1 : U32))

def land_lines(labels: List<&2, U32>, +conns: List<&2, TileWorld.Edge>, +a: String, +i: U32) -> List<&2, String>:
  match labels:
    case Nil{}:
      Nil{}
    case Con{+island, rest}:
      +ts = TileConnect.conns_of(i, conns)
      Canon.record("tland", [Canon.field("a", a), Canon.number("site", i), Canon.number("island", island),
        Canon.number("n", U32.from_nat(List.length(&2, U32, ts)))])
        <> List.append(&2, String, conn_lines(ts, a, i, 0), land_lines(rest, conns, a, (i + 1 : U32)))

def context_attempt(+c: Context) -> String:
  match c:
    case Context{_, _, +a, _}:
      a

def landmass_lines(t: Traced, +isl: TileConnect.Islands, +c: Context) -> Traced:
  match t:
    case Traced{g, lines}:
      match isl:
        case TileConnect.Islands{+labels, +conns}:
          Traced{g, List.append(&2, String, List.reverse(&2, String, land_lines(labels, conns, context_attempt(c), 0)), lines)}

def forced(t: Traced, +w: TileWorld.World, +isl: TileConnect.Islands) -> Traced:
  match t:
    case Traced{g, lines}:
      Traced{TileConnect.force(w, isl, g), lines}

def point_lines(pts: List<&2, TileWorld.Point>, +a: String, +r: U32, +k: U32) -> List<&2, String>:
  match pts:
    case Nil{}:
      Nil{}
    case Con{TileWorld.Point{+x, +y}, rest}:
      Canon.record("trpt", [Canon.field("a", a), Canon.number("r", r), Canon.number("k", k), Canon.field("x", Canon.hex32(F32Ops.bits(x))),
        Canon.field("y", Canon.hex32(F32Ops.bits(y)))]) <> point_lines(rest, a, r, (k + 1 : U32))

def road_lines(rs: List<&2, List<&2, TileWorld.Point>>, +a: String, +r: U32) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{+pts, rest}:
      Canon.record("troad", [Canon.field("a", a), Canon.number("r", r), Canon.number("n", U32.from_nat(List.length(&2, TileWorld.Point, pts)))])
        <> List.append(&2, String, point_lines(pts, a, r, 0), road_lines(rest, a, (r + 1 : U32)))

def with_roads(t: Traced, +rs: List<&2, List<&2, TileWorld.Point>>, +c: Context) -> Traced:
  match t:
    case Traced{g, lines}:
      Traced{g, List.append(&2, String, List.reverse(&2, String, road_lines(rs, context_attempt(c), 0)), lines)}

def drawn(t: Traced, +rs: List<&2, List<&2, TileWorld.Point>>, +windows: Bool) -> Traced:
  match t:
    case Traced{g, lines}:
      Traced{TileRoads.draw_roads(windows, rs, g), lines}

def context_windows(+c: Context) -> Bool:
  match c:
    case Context{_, +windows, _, _}:
      windows

def tiles_world(+w: TileWorld.World, +c: Context) -> List<&2, String>:
  +isl = TileConnect.islands(w, False{})
  +rs = TileRoads.roads(context_windows(c), w, isl)
  separate = digest(separated(digest(Traced{TileConvert.convert(w), Nil{}}, c, "ConvertToTileMap"), w), c, "SeparateIslands")
  force = digest(forced(landmass_lines(separate, isl, c), w, isl), c, "ForceConnectivity")
  tiles_done(digest(drawn(with_roads(force, rs, c), rs, context_windows(c)), c, "DrawRoads"))

def tiles_attempt(+seed: U32, +windows: Bool, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  tiles_world(TileInput.world_of(a, lines), Context{seed, windows, a, TileInput.num("before", TileInput.first_fields(TileInput.of_attempt("tmap", a, lines)))})

def tiles_all(+seed: U32, +windows: Bool, as: List<&2, String>, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, tiles_attempt(seed, windows, a, lines), tiles_all(seed, windows, rest, lines))

def run_stage(sitetiles: Bool, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match sitetiles:
    case True{}:
      sitetiles_all(TileInput.attempts(Canon.records("tmap", lines)), lines)
    case False{}:
      tiles_all(seed, windows, TileInput.attempts(Canon.records("tmap", lines)), lines)

def run_grid_or_land(populate: Bool, +stage: String, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match populate:
    case True{}:
      PopulateTrace.run(stage, seed, windows, lines)
    case False{}:
      run_stage(String.eq(stage, "sitetiles"), seed, windows, lines)

def run_lane(ocean: Bool, +stage: String, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match ocean:
    case True{}:
      OceanTrace.run(stage, seed, windows, lines)
    case False{}:
      run_grid_or_land(is_populate(stage), stage, seed, windows, lines)

def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  run_lane(OceanTrace.handles(stage), stage, seed, windows, String.split(input, '\n'))
