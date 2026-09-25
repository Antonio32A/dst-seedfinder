import Base
import ./canon.bend as CN
import ../f32/ops.bend as FO
import ../f64/repr.bend as FR
import ../worldsim/tiles/table.bend as TB
import ../worldsim/tiles/world.bend as TW
import ../worldsim/tiles/sitetiles.bend as TT
import ../worldsim/tiles/convert.bend as TC
import ../worldsim/tiles/separate.bend as TI
import ../worldsim/tiles/connect.bend as TF
import ../worldsim/tiles/roads.bend as TR
import ../worldsim/grid.bend as GR
import ../rng/pcg.bend as R
import ../worldsim/tiles/input.bend as TN
import ../populate/trace.bend as PX
import ../ocean/trace.bend as OX

# Lane G (grid) trace stages: `handles` names the stages this file owns, `run` returns their canonical
# records (.scratch/port/CONVENTIONS.md "Trace mode"). Only lane G edits this file.
# Input: the `tileinput` records of lane G's oracle stage (.scratch/port/status/M8.md).

def is_populate(+stage: String) -> Bool:
  String.eq(stage, "populate") || String.eq(stage, "pvoronoi")

def handles(+stage: String) -> Bool:
  String.eq(stage, "sitetiles") || String.eq(stage, "tiles") || is_populate(stage) || OX.handles(stage)

def stile_lines(tiles: List<&2, U32>, +a: String, +site: U32, +k: U32) -> List<&2, String>:
  match tiles:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      CN.record("stile", [CN.field("a", a), CN.number("site", site), CN.number("k", k), CN.number("x", TT.unpack_x(t)),
        CN.number("y", TT.unpack_y(t))]) <> stile_lines(rest, a, site, (k + 1 : U32))

def site_tile_lines(sites: List<&2, TW.Site>, +ids: List<&2, List<&2, String>>, +a: String, +i: U32) -> List<&2, String>:
  match sites:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      +tiles = TT.site_tiles(s)
      +id = TN.text("id", TN.first_fields(ids))
      CN.record("sitetiles", [CN.field("a", a), CN.number("site", i), CN.field("node", id),
        CN.number("n", U32.from_nat(List.length(&2, U32, tiles)))])
        <> List.append(&2, String, stile_lines(tiles, a, i, 0), site_tile_lines(rest, List.tail(&2, List<&2, String>, ids), a, (i + 1 : U32)))

def sitetiles_world(w: TW.World, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  match w:
    case TW.World{_, _, _, +sites, _, _, _, _, _}:
      site_tile_lines(sites, TN.of_attempt("tnode", a, lines), a, 0)

def sitetiles_attempt(+a: String, +lines: List<&2, String>) -> List<&2, String>:
  sitetiles_world(TN.world_of(a, lines), a, lines)

def sitetiles_all(as: List<&2, String>, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, sitetiles_attempt(a, lines), sitetiles_all(rest, lines))

type Traced is Type:
  Traced{grid: GR.Grid, lines: List<&2, String>}

type Context is Data:
  Context{seed: U32, windows: Bool, a: String, before: U32}

def digest_line(+c: Context, +at: String, +ctr: U32, +w: U32, +h: U32, +tiles: GR.Hash, +flags: GR.Hash) -> String:
  match c:
    case Context{_, _, +a, _}:
      match tiles:
        case GR.Hash{+th, +tl}:
          match flags:
            case GR.Hash{+fh, +fl}:
              CN.record("tdigest", [CN.field("a", a), CN.field("at", CN.quoted(at)), CN.number("ctr", ctr), CN.number("w", w),
                CN.number("h", h), CN.field("tiles", CN.hex64(th, tl)), CN.field("flags", CN.hex64(fh, fl))])

def digest_flags(got: GR.Grid & GR.Hash, +c: Context, +at: String, +tiles: GR.Hash, lines: List<&2, String>) -> Traced:
  (g, +flags) = got
  match g:
    case GR.Grid{cells, +w, +h}:
      match c:
        case Context{+seed, +windows, +a, +before}:
          Traced{GR.Grid{cells, w, h}, digest_line(Context{seed, windows, a, before}, at, (before + w * h : U32), w, h, tiles, flags) <> lines}

def digest_tiles(got: GR.Grid & GR.Hash, +c: Context, +at: String, lines: List<&2, String>) -> Traced:
  (g, +tiles) = got
  match c:
    case Context{+seed, +windows, +a, +before}:
      digest_flags(GR.flags_digest(g, R.at_counter(seed, before)), Context{seed, windows, a, before}, at, tiles, lines)

# Appends the `tdigest` record of the current maps.
def digest(t: Traced, +c: Context, +at: String) -> Traced:
  match t:
    case Traced{g, lines}:
      digest_tiles(GR.tiles_digest(g), c, at, lines)

def tiles_done(t: Traced) -> List<&2, String>:
  match t:
    case Traced{_, lines}:
      List.reverse(&2, String, lines)

def separated(t: Traced, +w: TW.World) -> Traced:
  match t:
    case Traced{g, lines}:
      Traced{TI.separate(w, g), lines}

def conn_lines(ts: List<&2, U32>, +a: String, +site: U32, +k: U32) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      CN.record("tconn", [CN.field("a", a), CN.number("site", site), CN.number("k", k), CN.number("to", t), CN.number("kind", 1)])
        <> conn_lines(rest, a, site, (k + 1 : U32))

def land_lines(labels: List<&2, U32>, +conns: List<&2, TW.Edge>, +a: String, +i: U32) -> List<&2, String>:
  match labels:
    case Nil{}:
      Nil{}
    case Con{+island, rest}:
      +ts = TF.conns_of(i, conns)
      CN.record("tland", [CN.field("a", a), CN.number("site", i), CN.number("island", island),
        CN.number("n", U32.from_nat(List.length(&2, U32, ts)))])
        <> List.append(&2, String, conn_lines(ts, a, i, 0), land_lines(rest, conns, a, (i + 1 : U32)))

def context_attempt(+c: Context) -> String:
  match c:
    case Context{_, _, +a, _}:
      a

def landmass_lines(t: Traced, +isl: TF.Islands, +c: Context) -> Traced:
  match t:
    case Traced{g, lines}:
      match isl:
        case TF.Islands{+labels, +conns}:
          Traced{g, List.append(&2, String, List.reverse(&2, String, land_lines(labels, conns, context_attempt(c), 0)), lines)}

def forced(t: Traced, +w: TW.World, +isl: TF.Islands) -> Traced:
  match t:
    case Traced{g, lines}:
      Traced{TF.force(w, isl, g), lines}

def point_lines(pts: List<&2, TW.Point>, +a: String, +r: U32, +k: U32) -> List<&2, String>:
  match pts:
    case Nil{}:
      Nil{}
    case Con{TW.Point{+x, +y}, rest}:
      CN.record("trpt", [CN.field("a", a), CN.number("r", r), CN.number("k", k), CN.field("x", CN.hex32(FO.bits(x))),
        CN.field("y", CN.hex32(FO.bits(y)))]) <> point_lines(rest, a, r, (k + 1 : U32))

def road_lines(rs: List<&2, List<&2, TW.Point>>, +a: String, +r: U32) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{+pts, rest}:
      CN.record("troad", [CN.field("a", a), CN.number("r", r), CN.number("n", U32.from_nat(List.length(&2, TW.Point, pts)))])
        <> List.append(&2, String, point_lines(pts, a, r, 0), road_lines(rest, a, (r + 1 : U32)))

def with_roads(t: Traced, +rs: List<&2, List<&2, TW.Point>>, +c: Context) -> Traced:
  match t:
    case Traced{g, lines}:
      Traced{g, List.append(&2, String, List.reverse(&2, String, road_lines(rs, context_attempt(c), 0)), lines)}

def drawn(t: Traced, +rs: List<&2, List<&2, TW.Point>>, +windows: Bool) -> Traced:
  match t:
    case Traced{g, lines}:
      Traced{TR.draw_roads(windows, rs, g), lines}

def context_windows(+c: Context) -> Bool:
  match c:
    case Context{_, +windows, _, _}:
      windows

def tiles_world(+w: TW.World, +c: Context) -> List<&2, String>:
  +isl = TF.islands(w, False{})
  +rs = TR.roads(context_windows(c), w, isl)
  separate = digest(separated(digest(Traced{TC.convert(w), Nil{}}, c, "ConvertToTileMap"), w), c, "SeparateIslands")
  force = digest(forced(landmass_lines(separate, isl, c), w, isl), c, "ForceConnectivity")
  tiles_done(digest(drawn(with_roads(force, rs, c), rs, context_windows(c)), c, "DrawRoads"))

def tiles_attempt(+seed: U32, +windows: Bool, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  tiles_world(TN.world_of(a, lines), Context{seed, windows, a, TN.num("before", TN.first_fields(TN.of_attempt("tmap", a, lines)))})

def tiles_all(+seed: U32, +windows: Bool, as: List<&2, String>, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, tiles_attempt(seed, windows, a, lines), tiles_all(seed, windows, rest, lines))

def run_stage(sitetiles: Bool, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match sitetiles:
    case True{}:
      sitetiles_all(TN.attempts(CN.records("tmap", lines)), lines)
    case False{}:
      tiles_all(seed, windows, TN.attempts(CN.records("tmap", lines)), lines)

def run_grid_or_land(populate: Bool, +stage: String, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match populate:
    case True{}:
      PX.run(stage, seed, windows, lines)
    case False{}:
      run_stage(String.eq(stage, "sitetiles"), seed, windows, lines)

def run_lane(ocean: Bool, +stage: String, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match ocean:
    case True{}:
      OX.run(stage, seed, windows, lines)
    case False{}:
      run_grid_or_land(is_populate(stage), stage, seed, windows, lines)

def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  run_lane(OX.handles(stage), stage, seed, windows, String.split(input, '\n'))
