import Base
import ../rng/pcg.bend as R
import ../f64/repr.bend as FR
import ../level/summary.bend as W
import ../trace/canon.bend as CN
import ../data/strings.bend as ST
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/table.bend as TB
import ../worldsim/tiles/world.bend as TW
import ../worldsim/tiles/input.bend as TN
import ../worldsim/tiles/convert.bend as TC
import ../worldsim/tiles/separate.bend as TI
import ../worldsim/tiles/connect.bend as TF
import ../worldsim/tiles/roads.bend as TR
import ../storygen/graph.bend as GG
import ../storygen/story.bend as GY
import ../storygen/trace.bend as GX
import ./entities.bend as PE
import ./state.bend as PS
import ./voronoi.bend as PV
import ./land.bend as PD

# Lane G's populate trace stages. `populate`: the land population (Graph:ConvertGround, ReplaceSingleNonLandTiles,
# Graph:PopulateVoronoi) on the grid the tile stages build from `tileinput`, from the counter at ConvertGround
# (`pland f="ConvertGround"`); prints the points records (gpfs*, reserve) and every populate record. `pvoronoi`: Graph:PopulateVoronoi alone, from the oracle's tile grid at its start
# (`trow at="Graph:PopulateVoronoi"`, stage tilegrid) and its start counter (`pland f="PopulateVoronoi"`); the story
# from `attempt` + `poly at="VoronoiPass(100)"` (as the storygen stage), the sites from `tileinput`. Prints the
# oracle's points records (gpfs, gpfs_perm, gpfs_kept with call=0, gpfs_pt) and populate records (ppv, pent,
# pland, pdigest) of that window.

def f64_text(+x: FR.F64) -> String:
  match x:
    case FR.F64{+hi, +lo}:
      CN.hex64(hi, lo)

type Out is Data:
  Out{seed: U32, a: String, width: U32, height: U32, story: GG.St, gpfs: U32, pv: U32, ent: U32, cg: U32, lay: U32, res: U32}

def ctr(+o: Out, +rng: R.Rng) -> U32:
  match o:
    case Out{+seed, _, _, _, _, _, _, _, _, _, _}:
      R.counter(seed, rng)

def attempt_of(+o: Out) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, _, _}:
      a

def node_text(+o: Out, +n: U32) -> String:
  match o:
    case Out{_, _, _, _, +s, _, _, _, _, _, _}:
      CN.quoted(GG.node_name(s, n))

def perm_lines(xs: List<&2, U32>, +a: String, +i: U32, +k: U32) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+v, rest}:
      CN.record("gpfs_perm", [CN.field("a", a), CN.number("i", i), CN.number("k", k), CN.number("src", PT.shuffled_src(v))])
        <> perm_lines(rest, a, i, (k + 1 : U32))

def pt_lines(xs: List<&2, PT.Pt>, +a: String, +i: U32, +k: U32) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{PT.Pt{+x, +y, +t}, rest}:
      CN.record("gpfs_pt", [CN.field("a", a), CN.number("i", i), CN.number("k", k), CN.number("x", x), CN.number("y", y),
        CN.number("t", t)]) <> pt_lines(rest, a, i, (k + 1 : U32))

def points_lines(+o: Out, +node: U32, +n: U32, +before: R.Rng, +after: R.Rng, +shuffled: List<&2, U32>, +kept: List<&2, PT.Pt>) -> List<&2, String>:
  match o:
    case Out{_, +a, _, _, _, +i, _, _, _, _, _}:
      +head = CN.record("gpfs", [CN.field("a", a), CN.number("i", i), CN.field("node", node_text(o, node)), CN.number("n", n),
        CN.number("before", ctr(o, before)), CN.number("after", ctr(o, after))])
      +count = CN.record("gpfs_kept", [CN.field("a", a), CN.number("i", i), CN.number("call", 0),
        CN.number("kept", U32.from_nat(List.length(&2, PT.Pt, kept)))])
      head <> List.append(&2, String, perm_lines(shuffled, a, i, 0), count <> pt_lines(kept, a, i, 0))

def ent_line(+o: Out, +e: PE.Ent) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, +k, _, _, _}:
      match e:
        case PE.Ent{+prefab, +tx, +ty, +x, +z, _, _, +rng}:
          CN.record("pent", [CN.field("a", a), CN.number("k", k), CN.field("prefab", CN.quoted(ST.name(prefab))),
            CN.field("tx", f64_text(tx)), CN.field("ty", f64_text(ty)), CN.field("x", f64_text(x)), CN.field("z", f64_text(z)),
            CN.number("after", ctr(o, rng))])

def ppv_line(+o: Out, +node: U32, +before: R.Rng, +after: R.Rng) -> String:
  match o:
    case Out{_, +a, _, _, _, _, +k, _, _, _, _}:
      CN.record("ppv", [CN.field("a", a), CN.number("k", k), CN.field("node", node_text(o, node)),
        CN.number("before", ctr(o, before)), CN.number("after", ctr(o, after))])

def land_name(+populate: Bool) -> String:
  Bool.pick(String, populate, "\"PopulateVoronoi\"", "\"ConvertGround\"")

def land_line(+o: Out, +populate: Bool, +before: R.Rng, +after: R.Rng) -> String:
  CN.record("pland", [CN.field("a", attempt_of(o)), CN.field("f", land_name(populate)), CN.number("before", ctr(o, before)),
    CN.number("after", ctr(o, after))])

def digest_name(+at: U32) -> String:
  match at:
    case 0:
      "\"Graph:ConvertGround\""
    case 1:
      "\"ReplaceSingleNonLandTiles\""
    case _:
      "\"Graph:PopulateVoronoi\""

def hash_text(+h: GR.Hash) -> String:
  match h:
    case GR.Hash{+hi, +lo}:
      CN.hex64(hi, lo)

def digest_line(+o: Out, +at: U32, +rng: R.Rng, +tiles: GR.Hash, +flags: GR.Hash) -> String:
  match o:
    case Out{_, +a, +w, +h, _, _, _, _, _, _, _}:
      CN.record("pdigest", [CN.field("a", a), CN.field("at", digest_name(at)), CN.number("ctr", ctr(o, rng)), CN.number("w", w),
        CN.number("h", h), CN.field("tiles", hash_text(tiles)), CN.field("flags", hash_text(flags))])

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

def reserve_line(+o: Out, +node: U32, +size: U32, +start: U32, +fill: U32, +pos: U32, +n: U32, +before: R.Rng, +after: R.Rng, +ok: Bool, +x: U32, +y: U32) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, _, +i}:
      CN.record("reserve", [CN.field("a", a), CN.number("i", i), CN.number("call", 0), CN.field("node", node_text(o, node)),
        CN.field("size", CN.hex32(size)), CN.number("start", start), CN.number("fill", fill), CN.number("pos", pos), CN.number("n", n),
        CN.number("before", ctr(o, before)), CN.number("after", ctr(o, after)), CN.number("ok", Bool.to_u32(ok)),
        CN.field("x", optional(ok, x)), CN.field("y", optional(ok, y))])

def pcg_line(+o: Out, +node: U32, +before: R.Rng, +after: R.Rng) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, +k, _, _}:
      CN.record("pcg", [CN.field("a", a), CN.number("k", k), CN.field("node", node_text(o, node)),
        CN.number("before", ctr(o, before)), CN.number("after", ctr(o, after))])

def layout_line(+o: Out, +node: U32, +name: U32, +before: R.Rng) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, +k, _}:
      CN.record("playout", [CN.field("a", a), CN.number("k", k), CN.field("node", node_text(o, node)),
        CN.field("name", CN.quoted(ST.name(name))), CN.number("before", ctr(o, before))])

def item_lines(objs: List<&2, PS.Obj>, +a: String, +k: U32, +j: U32) -> List<&2, String>:
  match objs:
    case Nil{}:
      Nil{}
    case Con{PS.Obj{+prefab, +x, +y}, rest}:
      CN.record("pitem", [CN.field("a", a), CN.number("k", k), CN.number("j", j), CN.field("prefab", CN.quoted(ST.name(prefab))),
        CN.field("x", f64_text(x)), CN.field("y", f64_text(y))]) <> item_lines(rest, a, k, (j + 1 : U32))

def items_lines(+o: Out, +name: U32, +objs: List<&2, PS.Obj>, +before: R.Rng, +after: R.Rng) -> List<&2, String>:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, +k, _}:
      List.append(&2, String, item_lines(objs, a, (k - 1 : U32), 0), [CN.record("pitems", [CN.field("a", a),
        CN.number("k", (k - 1 : U32)), CN.field("name", CN.quoted(ST.name(name))), CN.number("n", U32.from_nat(List.length(&2, PS.Obj, objs))),
        CN.number("before", ctr(o, before)), CN.number("after", ctr(o, after))])])

def placed_line(+o: Out, +after: R.Rng) -> String:
  match o:
    case Out{_, +a, _, _, _, _, _, _, _, +k, _}:
      CN.record("pplaced", [CN.field("a", a), CN.number("k", (k - 1 : U32)), CN.number("after", ctr(o, after))])

def event_lines(evs: List<&2, PS.Ev>, +o: Out) -> List<&2, String>:
  match evs:
    case Nil{}:
      Nil{}
    case Con{+ev, rest}:
      match ev:
        case PS.EPoints{+node, +n, +before, +after, +shuffled, +kept}:
          List.append(&2, String, points_lines(o, node, n, before, after, shuffled, kept), event_lines(rest, bumped(o, 1, 0, 0)))
        case PS.EEntity{+e}:
          ent_line(o, e) <> event_lines(rest, bumped(o, 0, 0, 1))
        case PS.EPopulateNode{+node, +before, +after}:
          ppv_line(o, node, before, after) <> event_lines(rest, bumped(o, 0, 1, 0))
        case PS.ELand{+populate, +before, +after}:
          land_line(o, populate, before, after) <> event_lines(rest, o)
        case PS.EDigest{+at, +rng, +tiles, +flags}:
          digest_line(o, at, rng, tiles, flags) <> event_lines(rest, o)
        case PS.EReserve{+node, +size, +start, +fill, +pos, +n, +before, +after, +ok, +x, +y}:
          reserve_line(o, node, size, start, fill, pos, n, before, after, ok, x, y) <> event_lines(rest, bumped_ground(o, 0, 0, 1))
        case PS.EConvertNode{+node, +before, +after}:
          pcg_line(o, node, before, after) <> event_lines(rest, bumped_ground(o, 1, 0, 0))
        case PS.ELayout{+node, +name, +before}:
          layout_line(o, node, name, before) <> event_lines(rest, bumped_ground(o, 0, 1, 0))
        case PS.EItems{+name, +objs, +before, +after}:
          List.append(&2, String, items_lines(o, name, objs, before, after), event_lines(rest, o))
        case PS.EPlaced{+after}:
          placed_line(o, after) <> event_lines(rest, o)

def hex_cell(+tiles: String, +flags: String) -> U32:
  GR.cell(TN.hex_loop(4n, tiles, 0), (TN.hex_loop(4n, flags, 0) .&. 61695 : U32))

def row_loop(n: Nat, g: GR.Grid, +tiles: String, +flags: String, +i: U32) -> GR.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      row_loop(p, GR.put(g, i, hex_cell(tiles, flags)), String.drop(tiles, 4n), String.drop(flags, 4n), (i + 1 : U32))

def rows_loop(recs: List<&2, List<&2, String>>, g: GR.Grid, +w: U32) -> GR.Grid:
  match recs:
    case Nil{}:
      g
    case Con{+fields, rest}:
      +y = TN.num("y", fields)
      rows_loop(rest, row_loop(U32.to_nat(w), g, TN.text("tiles", fields), TN.text("flags", fields), (y * w : U32)), w)

def keep_at(recs: List<&2, List<&2, String>>, +at: String) -> List<&2, List<&2, String>>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      TN.keep_if(String.eq(TN.text("at", fields), at), fields, keep_at(rest, at))

def grid_rows(+a: String, +at: String, +lines: List<&2, String>) -> List<&2, List<&2, String>>:
  keep_at(TN.of_attempt("trow", a, lines), at)

def site_for(recs: List<&2, List<&2, String>>, found: Bool, +name: String, +site: U32) -> U32:
  match recs:
    case Nil{}:
      Bool.pick(U32, found, site, TW.none())
    case Con{+fields, rest}:
      match found:
        case True{}:
          site
        case False{}:
          site_for(rest, String.eq(TN.text("id", fields), name), name, TN.num("site", fields))

def node_sites(n: Nat, +s: GG.St, +nodes: List<&2, List<&2, String>>, +k: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      site_for(nodes, False{}, CN.quoted(GG.node_name(s, k)), TW.none()) <> node_sites(p, s, nodes, (k + 1 : U32))

def story_at(+seed: U32, +a: String, +lines: List<&2, String>) -> GG.St:
  +level = W.summary(seed)
  +start = TN.num("ctr", TN.first_fields(TN.of_attempt("attempt", a, lines)))
  GY.finish(GX.with_sites(GY.build(level, R.at_counter(seed, start)), GX.attempt_sites(CN.records("poly", lines), a)), level)

def land_scan(recs: List<&2, List<&2, String>>, found: Bool, +f: String, +before: U32) -> U32:
  match recs:
    case Nil{}:
      before
    case Con{+fields, rest}:
      match found:
        case True{}:
          before
        case False{}:
          land_scan(rest, String.eq(TN.text("f", fields), f), f, TN.num("before", fields))

def land_before(+a: String, +f: String, +lines: List<&2, String>) -> U32:
  land_scan(TN.of_attempt("pland", a, lines), False{}, f, 0)

def swaps_of(+level: W.Summary) -> U32:
  match level:
    case W.Summary{+swaps, _, _, _, _, _, _}:
      swaps

def context_of(+seed: U32, +windows: Bool, +a: String, +w: TW.World, +s: GG.St, +lists: List<&2, List<&2, U32>>, +lines: List<&2, String>) -> PS.Ctx:
  match w:
    case TW.World{+width, +height, _, _, _, _, _, _, _}:
      +nodes = TN.of_attempt("tnode", a, lines)
      +site_of = TB.from_list(~U32, node_sites(U32.to_nat(GG.get(s, GG.s_nodes())), s, nodes, 0), TW.none())
      +tiles_rng = R.at_counter(seed, TN.num("before", TN.first_fields(TN.of_attempt("tmap", a, lines))))
      PS.Ctx{windows, swaps_of(W.summary(seed)), PT.sites(w, lists), s, site_of, width, height, True{}, tiles_rng}

def grid_at(+a: String, +at: String, +w: U32, +h: U32, +lines: List<&2, String>) -> GR.Grid:
  rows_loop(grid_rows(a, at, lines), GR.new(w, h, 0), w)

def land_lines(l: PS.Land, +o: Out) -> List<&2, String>:
  match l:
    case PS.Land{_, _, _, +events}:
      event_lines(List.reverse(&2, PS.Ev, events), o)

def pvoronoi_attempt(+seed: U32, +windows: Bool, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  +w = TN.world_of(a, lines)
  +s = story_at(seed, a, lines)
  +c = context_of(seed, windows, a, w, s, TC.site_tiles(w), lines)
  +width = PS.width_of(c)
  +height = PS.height_of(c)
  +rng = R.at_counter(seed, land_before(a, "\"PopulateVoronoi\"", lines))
  land_lines(PV.populate(c, PS.Land{grid_at(a, "\"Graph:PopulateVoronoi\"", width, height, lines), rng, Nil{}, Nil{}}),
    Out{seed, a, width, height, s, 0, 0, 0, 0, 0, 0})

def pvoronoi_all(as: List<&2, String>, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, pvoronoi_attempt(seed, windows, a, lines), pvoronoi_all(rest, seed, windows, lines))

def roads_grid(+windows: Bool, +w: TW.World, +lists: List<&2, List<&2, U32>>) -> GR.Grid:
  +isl = TF.islands(w, False{})
  TR.draw_roads(windows, TR.roads(windows, w, isl), TF.force(w, isl, TI.separate(w, TC.paint(w, lists))))

def populate_attempt(+seed: U32, +windows: Bool, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  +w = TN.world_of(a, lines)
  +lists = TC.site_tiles(w)
  +s = story_at(seed, a, lines)
  +c = context_of(seed, windows, a, w, s, lists, lines)
  +rng = R.at_counter(seed, land_before(a, "\"ConvertGround\"", lines))
  land_lines(PD.land(c, PS.Land{roads_grid(windows, w, lists), rng, Nil{}, Nil{}}), Out{seed, a, PS.width_of(c), PS.height_of(c), s, 0, 0, 0, 0, 0, 0})

def has_land(recs: List<&2, List<&2, String>>, +a: String) -> Bool:
  match recs:
    case Nil{}:
      False{}
    case Con{+fields, rest}:
      String.eq(TN.text("a", fields), a) || has_land(rest, a)

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
      +on = has_land(CN.records("pland", lines), a)
      List.append(&2, String, attempt_if(on, populate, seed, windows, a, lines), stage_all(rest, populate, seed, windows, lines))

# The stage's records for a seed, platform and the lines of its input.
def run(+stage: String, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  stage_all(TN.attempts(CN.records("tmap", lines)), String.eq(stage, "populate"), seed, windows, lines)
