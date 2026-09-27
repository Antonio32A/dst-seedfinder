import Base
import ../rng/pcg.bend as Pcg
import ../f64/repr.bend as F64Repr
import ../level/summary.bend as LevelSummary
import ../trace/canon.bend as Canon
import ../data/strings.bend as Strings
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/table.bend as TileTable
import ../worldsim/tiles/world.bend as TileWorld
import ../worldsim/tiles/input.bend as TileInput
import ../worldsim/tiles/convert.bend as TileConvert
import ../worldsim/tiles/separate.bend as TileSeparate
import ../worldsim/tiles/connect.bend as TileConnect
import ../worldsim/tiles/roads.bend as TileRoads
import ../storygen/graph.bend as StoryGraph
import ../storygen/story.bend as Story
import ../storygen/trace.bend as StoryTrace
import ./entities.bend as Entities
import ./state.bend as PopulateState
import ./voronoi.bend as PopulateVoronoi
import ./land.bend as Land

# Lane G's populate trace stages. `populate`: the land population (Graph:ConvertGround, ReplaceSingleNonLandTiles,
# Graph:PopulateVoronoi) on the grid the tile stages build from `tileinput`, from the counter at ConvertGround
# (`pland f="ConvertGround"`); prints the points records (gpfs*, reserve) and every populate record. `pvoronoi`: Graph:PopulateVoronoi alone, from the oracle's tile grid at its start
# (`trow at="Graph:PopulateVoronoi"`, stage tilegrid) and its start counter (`pland f="PopulateVoronoi"`); the story
# from `attempt` + `poly at="VoronoiPass(100)"` (as the storygen stage), the sites from `tileinput`. Prints the
# oracle's points records (gpfs, gpfs_perm, gpfs_kept with call=0, gpfs_pt) and populate records (ppv, pent,
# pland, pdigest) of that window.

def f64_text(+x: F64Repr.F64) -> String:
  match x:
    case F64Repr.F64{+hi, +lo}:
      Canon.hex64(hi, lo)

type Out is Data:
  Out{seed: U32, a: String, width: U32, height: U32, story: StoryGraph.St, gpfs: U32, pv: U32, ent: U32, cg: U32, lay: U32, res: U32}

def ctr(+o: Out, +rng: Pcg.Rng) -> U32:
  match o:
    case Out{+seed, _, _, _, _, _, _, _, _, _, _}:
      Pcg.counter(seed, rng)

def attempt_of(+o: Out) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, _, _}:
      a

def node_text(+o: Out, +n: U32) -> String:
  match o:
    case Out{_, _, _, _, +s, _, _, _, _, _, _}:
      Canon.quoted(StoryGraph.node_name(s, n))

def perm_lines(xs: List<&2, U32>, +a: String, +i: U32, +k: U32) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+v, rest}:
      Canon.record("gpfs_perm", [Canon.field("a", a), Canon.number("i", i), Canon.number("k", k), Canon.number("src", Points.shuffled_src(v))])
        <> perm_lines(rest, a, i, (k + 1 : U32))

def pt_lines(xs: List<&2, Points.Pt>, +a: String, +i: U32, +k: U32) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Points.Pt{+x, +y, +t}, rest}:
      Canon.record("gpfs_pt", [Canon.field("a", a), Canon.number("i", i), Canon.number("k", k), Canon.number("x", x), Canon.number("y", y),
        Canon.number("t", t)]) <> pt_lines(rest, a, i, (k + 1 : U32))

def points_lines(+o: Out, +node: U32, +n: U32, +before: Pcg.Rng, +after: Pcg.Rng, +shuffled: List<&2, U32>, +kept: List<&2, Points.Pt>) -> List<&2, String>:
  match o:
    case Out{_, +a, _, _, _, +i, _, _, _, _, _}:
      +head = Canon.record("gpfs", [Canon.field("a", a), Canon.number("i", i), Canon.field("node", node_text(o, node)), Canon.number("n", n),
        Canon.number("before", ctr(o, before)), Canon.number("after", ctr(o, after))])
      +count = Canon.record("gpfs_kept", [Canon.field("a", a), Canon.number("i", i), Canon.number("call", 0),
        Canon.number("kept", U32.from_nat(List.length(&2, Points.Pt, kept)))])
      head <> List.append(&2, String, perm_lines(shuffled, a, i, 0), count <> pt_lines(kept, a, i, 0))

def ent_line(+o: Out, +e: Entities.Ent) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, +k, _, _, _}:
      match e:
        case Entities.Ent{+prefab, +tx, +ty, +x, +z, _, _, +rng}:
          Canon.record("pent", [Canon.field("a", a), Canon.number("k", k), Canon.field("prefab", Canon.quoted(Strings.name(prefab))),
            Canon.field("tx", f64_text(tx)), Canon.field("ty", f64_text(ty)), Canon.field("x", f64_text(x)), Canon.field("z", f64_text(z)),
            Canon.number("after", ctr(o, rng))])

def ppv_line(+o: Out, +node: U32, +before: Pcg.Rng, +after: Pcg.Rng) -> String:
  match o:
    case Out{_, +a, _, _, _, _, +k, _, _, _, _}:
      Canon.record("ppv", [Canon.field("a", a), Canon.number("k", k), Canon.field("node", node_text(o, node)),
        Canon.number("before", ctr(o, before)), Canon.number("after", ctr(o, after))])

def land_name(+populate: Bool) -> String:
  Bool.pick(String, populate, "\"PopulateVoronoi\"", "\"ConvertGround\"")

def land_line(+o: Out, +populate: Bool, +before: Pcg.Rng, +after: Pcg.Rng) -> String:
  Canon.record("pland", [Canon.field("a", attempt_of(o)), Canon.field("f", land_name(populate)), Canon.number("before", ctr(o, before)),
    Canon.number("after", ctr(o, after))])

def digest_name(+at: U32) -> String:
  match at:
    case 0:
      "\"Graph:ConvertGround\""
    case 1:
      "\"ReplaceSingleNonLandTiles\""
    case _:
      "\"Graph:PopulateVoronoi\""

def hash_text(+h: Grid.Hash) -> String:
  match h:
    case Grid.Hash{+hi, +lo}:
      Canon.hex64(hi, lo)

def digest_line(+o: Out, +at: U32, +rng: Pcg.Rng, +tiles: Grid.Hash, +flags: Grid.Hash) -> String:
  match o:
    case Out{_, +a, +w, +h, _, _, _, _, _, _, _}:
      Canon.record("pdigest", [Canon.field("a", a), Canon.field("at", digest_name(at)), Canon.number("ctr", ctr(o, rng)), Canon.number("w", w),
        Canon.number("h", h), Canon.field("tiles", hash_text(tiles)), Canon.field("flags", hash_text(flags))])

def bumped(+o: Out, +gpfs: U32, +pv: U32, +ent: U32) -> Out:
  match o:
    case Out{+seed, +a, +w, +h, +s, +g, +p, +e, +cg, +lay, +res}:
      Out{seed, a, w, h, s, (g + gpfs : U32), (p + pv : U32), (e + ent : U32), cg, lay, res}

def bumped_ground(+o: Out, +cg: U32, +lay: U32, +res: U32) -> Out:
  match o:
    case Out{+seed, +a, +w, +h, +s, +g, +p, +e, +c, +l, +r}:
      Out{seed, a, w, h, s, g, p, e, (c + cg : U32), (l + lay : U32), (r + res : U32)}

def optional(+ok: Bool, +v: U32) -> String:
  Bool.pick(String, ok, U32.show(v), "nil")

def reserve_line(+o: Out, +node: U32, +size: U32, +start: U32, +fill: U32, +pos: U32, +n: U32, +before: Pcg.Rng, +after: Pcg.Rng, +ok: Bool, +x: U32, +y: U32) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, _, +i}:
      Canon.record("reserve", [Canon.field("a", a), Canon.number("i", i), Canon.number("call", 0), Canon.field("node", node_text(o, node)),
        Canon.field("size", Canon.hex32(size)), Canon.number("start", start), Canon.number("fill", fill), Canon.number("pos", pos), Canon.number("n", n),
        Canon.number("before", ctr(o, before)), Canon.number("after", ctr(o, after)), Canon.number("ok", Bool.to_u32(ok)),
        Canon.field("x", optional(ok, x)), Canon.field("y", optional(ok, y))])

def pcg_line(+o: Out, +node: U32, +before: Pcg.Rng, +after: Pcg.Rng) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, +k, _, _}:
      Canon.record("pcg", [Canon.field("a", a), Canon.number("k", k), Canon.field("node", node_text(o, node)),
        Canon.number("before", ctr(o, before)), Canon.number("after", ctr(o, after))])

def layout_line(+o: Out, +node: U32, +name: U32, +before: Pcg.Rng) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, +k, _}:
      Canon.record("playout", [Canon.field("a", a), Canon.number("k", k), Canon.field("node", node_text(o, node)),
        Canon.field("name", Canon.quoted(Strings.name(name))), Canon.number("before", ctr(o, before))])

def item_lines(objs: List<&2, PopulateState.Obj>, +a: String, +k: U32, +j: U32) -> List<&2, String>:
  match objs:
    case Nil{}:
      Nil{}
    case Con{PopulateState.Obj{+prefab, +x, +y}, rest}:
      Canon.record("pitem", [Canon.field("a", a), Canon.number("k", k), Canon.number("j", j), Canon.field("prefab", Canon.quoted(Strings.name(prefab))),
        Canon.field("x", f64_text(x)), Canon.field("y", f64_text(y))]) <> item_lines(rest, a, k, (j + 1 : U32))

def items_lines(+o: Out, +name: U32, +objs: List<&2, PopulateState.Obj>, +before: Pcg.Rng, +after: Pcg.Rng) -> List<&2, String>:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, +k, _}:
      List.append(&2, String, item_lines(objs, a, (k - 1 : U32), 0), [Canon.record("pitems", [Canon.field("a", a),
        Canon.number("k", (k - 1 : U32)), Canon.field("name", Canon.quoted(Strings.name(name))), Canon.number("n", U32.from_nat(List.length(&2, PopulateState.Obj, objs))),
        Canon.number("before", ctr(o, before)), Canon.number("after", ctr(o, after))])])

def placed_line(+o: Out, +after: Pcg.Rng) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, +k, _}:
      Canon.record("pplaced", [Canon.field("a", a), Canon.number("k", (k - 1 : U32)), Canon.number("after", ctr(o, after))])

def event_lines(evs: List<&2, PopulateState.Ev>, +o: Out) -> List<&2, String>:
  match evs:
    case Nil{}:
      Nil{}
    case Con{+ev, rest}:
      match ev:
        case PopulateState.EPoints{+node, +n, +before, +after, +shuffled, +kept}:
          List.append(&2, String, points_lines(o, node, n, before, after, shuffled, kept), event_lines(rest, bumped(o, 1, 0, 0)))
        case PopulateState.EEntity{+e}:
          ent_line(o, e) <> event_lines(rest, bumped(o, 0, 0, 1))
        case PopulateState.EPopulateNode{+node, +before, +after}:
          ppv_line(o, node, before, after) <> event_lines(rest, bumped(o, 0, 1, 0))
        case PopulateState.ELand{+populate, +before, +after}:
          land_line(o, populate, before, after) <> event_lines(rest, o)
        case PopulateState.EDigest{+at, +rng, +tiles, +flags}:
          digest_line(o, at, rng, tiles, flags) <> event_lines(rest, o)
        case PopulateState.EReserve{+node, +size, +start, +fill, +pos, +n, +before, +after, +ok, +x, +y}:
          reserve_line(o, node, size, start, fill, pos, n, before, after, ok, x, y) <> event_lines(rest, bumped_ground(o, 0, 0, 1))
        case PopulateState.EConvertNode{+node, +before, +after}:
          pcg_line(o, node, before, after) <> event_lines(rest, bumped_ground(o, 1, 0, 0))
        case PopulateState.ELayout{+node, +name, +before}:
          layout_line(o, node, name, before) <> event_lines(rest, bumped_ground(o, 0, 1, 0))
        case PopulateState.EItems{+name, +objs, +before, +after}:
          List.append(&2, String, items_lines(o, name, objs, before, after), event_lines(rest, o))
        case PopulateState.EPlaced{+after}:
          placed_line(o, after) <> event_lines(rest, o)
        case PopulateState.EPiece{_}:
          event_lines(rest, o)

def hex_cell(+tiles: String, +flags: String) -> U32:
  Grid.cell(TileInput.hex_loop(4n, tiles, 0), (TileInput.hex_loop(4n, flags, 0) .&. 61695 : U32))

def row_loop(n: Nat, g: Grid.Grid, +tiles: String, +flags: String, +i: U32) -> Grid.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      row_loop(p, Grid.put(g, i, hex_cell(tiles, flags)), String.drop(tiles, 4n), String.drop(flags, 4n), (i + 1 : U32))

def rows_loop(recs: List<&2, List<&2, String>>, g: Grid.Grid, +w: U32) -> Grid.Grid:
  match recs:
    case Nil{}:
      g
    case Con{+fields, rest}:
      +y = TileInput.num("y", fields)
      rows_loop(rest, row_loop(U32.to_nat(w), g, TileInput.text("tiles", fields), TileInput.text("flags", fields), (y * w : U32)), w)

def keep_at(recs: List<&2, List<&2, String>>, +at: String) -> List<&2, List<&2, String>>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      TileInput.keep_if(String.eq(TileInput.text("at", fields), at), fields, keep_at(rest, at))

def grid_rows(+a: String, +at: String, +lines: List<&2, String>) -> List<&2, List<&2, String>>:
  keep_at(TileInput.of_attempt("trow", a, lines), at)

def site_for(recs: List<&2, List<&2, String>>, found: Bool, +name: String, +site: U32) -> U32:
  match recs:
    case Nil{}:
      Bool.pick(U32, found, site, TileWorld.none())
    case Con{+fields, rest}:
      match found:
        case True{}:
          site
        case False{}:
          site_for(rest, String.eq(TileInput.text("id", fields), name), name, TileInput.num("site", fields))

def node_sites(n: Nat, +s: StoryGraph.St, +nodes: List<&2, List<&2, String>>, +k: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      site_for(nodes, False{}, Canon.quoted(StoryGraph.node_name(s, k)), TileWorld.none()) <> node_sites(p, s, nodes, (k + 1 : U32))

def story_at(+seed: U32, +a: String, +lines: List<&2, String>) -> StoryGraph.St:
  +level = LevelSummary.summary(seed)
  +start = TileInput.num("ctr", TileInput.first_fields(TileInput.of_attempt("attempt", a, lines)))
  Story.finish(StoryTrace.with_sites(Story.build(level, Pcg.at_counter(seed, start)), StoryTrace.attempt_sites(Canon.records("poly", lines), a)), level)

def land_scan(recs: List<&2, List<&2, String>>, found: Bool, +f: String, +before: U32) -> U32:
  match recs:
    case Nil{}:
      before
    case Con{+fields, rest}:
      match found:
        case True{}:
          before
        case False{}:
          land_scan(rest, String.eq(TileInput.text("f", fields), f), f, TileInput.num("before", fields))

def land_before(+a: String, +f: String, +lines: List<&2, String>) -> U32:
  land_scan(TileInput.of_attempt("pland", a, lines), False{}, f, 0)

def swaps_of(+level: LevelSummary.Summary) -> U32:
  match level:
    case LevelSummary.Summary{+swaps, _, _, _, _, _, _}:
      swaps

def context_of(+seed: U32, +windows: Bool, +a: String, +w: TileWorld.World, +s: StoryGraph.St, +lists: List<&2, List<&2, U32>>, +lines: List<&2, String>) -> PopulateState.Ctx:
  match w:
    case TileWorld.World{+width, +height, _, _, _, _, _, _, _}:
      +nodes = TileInput.of_attempt("tnode", a, lines)
      +site_of = TileTable.from_list(~U32, node_sites(U32.to_nat(StoryGraph.get(s, StoryGraph.s_nodes())), s, nodes, 0), TileWorld.none())
      +tiles_rng = Pcg.at_counter(seed, TileInput.num("before", TileInput.first_fields(TileInput.of_attempt("tmap", a, lines))))
      PopulateState.Ctx{windows, swaps_of(LevelSummary.summary(seed)), Points.sites(w, lists), s, site_of, width, height, True{}, tiles_rng, False{}}

def grid_at(+a: String, +at: String, +w: U32, +h: U32, +lines: List<&2, String>) -> Grid.Grid:
  rows_loop(grid_rows(a, at, lines), Grid.new(w, h, 0), w)

def land_lines(l: PopulateState.Land, +o: Out) -> List<&2, String>:
  match l:
    case PopulateState.Land{_, _, _, +events}:
      event_lines(List.reverse(&2, PopulateState.Ev, events), o)

def pvoronoi_attempt(+seed: U32, +windows: Bool, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  +w = TileInput.world_of(a, lines)
  +s = story_at(seed, a, lines)
  +c = context_of(seed, windows, a, w, s, TileConvert.site_tiles(w), lines)
  +width = PopulateState.width_of(c)
  +height = PopulateState.height_of(c)
  +rng = Pcg.at_counter(seed, land_before(a, "\"PopulateVoronoi\"", lines))
  land_lines(PopulateVoronoi.populate(c, PopulateState.Land{grid_at(a, "\"Graph:PopulateVoronoi\"", width, height, lines), rng, Nil{}, Nil{}}),
    Out{seed, a, width, height, s, 0, 0, 0, 0, 0, 0})

def pvoronoi_all(as: List<&2, String>, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, pvoronoi_attempt(seed, windows, a, lines), pvoronoi_all(rest, seed, windows, lines))

def roads_grid(+windows: Bool, +w: TileWorld.World, +lists: List<&2, List<&2, U32>>) -> Grid.Grid:
  +isl = TileConnect.islands(w, False{})
  TileRoads.draw_roads(windows, TileRoads.roads(windows, w, isl), TileConnect.force(w, isl, TileSeparate.separate(w, TileConvert.paint(w, lists))))

def populate_attempt(+seed: U32, +windows: Bool, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  +w = TileInput.world_of(a, lines)
  +lists = TileConvert.site_tiles(w)
  +s = story_at(seed, a, lines)
  +c = context_of(seed, windows, a, w, s, lists, lines)
  +rng = Pcg.at_counter(seed, land_before(a, "\"ConvertGround\"", lines))
  land_lines(Land.land(c, PopulateState.Land{roads_grid(windows, w, lists), rng, Nil{}, Nil{}}), Out{seed, a, PopulateState.width_of(c), PopulateState.height_of(c), s, 0, 0, 0, 0, 0, 0})

def has_land(recs: List<&2, List<&2, String>>, +a: String) -> Bool:
  match recs:
    case Nil{}:
      False{}
    case Con{+fields, rest}:
      String.eq(TileInput.text("a", fields), a) || has_land(rest, a)

def attempt_if(on: Bool, populate: Bool, +seed: U32, +windows: Bool, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  match on:
    case False{}:
      Nil{}
    case True{}:
      match populate:
        case True{}:
          populate_attempt(seed, windows, a, lines)
        case False{}:
          pvoronoi_attempt(seed, windows, a, lines)

def stage_all(as: List<&2, String>, +populate: Bool, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      +on = has_land(Canon.records("pland", lines), a)
      List.append(&2, String, attempt_if(on, populate, seed, windows, a, lines), stage_all(rest, populate, seed, windows, lines))

# The stage's records for a seed, platform and the lines of its input.
def run(+stage: String, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  stage_all(TileInput.attempts(Canon.records("tmap", lines)), String.eq(stage, "populate"), seed, windows, lines)
