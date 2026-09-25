import Base
import ../../trace/canon.bend as CN
import ../commit.bend as CM
import ../voronoi/diagram.bend as VD
import ../voronoi/builder.bend as VB
import ../voronoi/polygon.bend as VG
import ../voronoi/records.bend as VN

# Trace stages `voronoi` and `polygons` (lane N, M6). The input (written by .scratch/port/diff/voronoi.py and
# polygons.py from the oracle's graph, voronoi and polygons dumps) lists, per Voronoi call of an attempt:
#   tblock a g at op w h size b      op = pass (BuildVoronoi of the sites as given), commit (Commit from the sites
#                                    before it, in a w x h world) or tilemap (ConvertToTileMap's ScaleAndCenter to
#                                    `size` from a w x h world); b = the oracle build number of its first build
#   tsite a g site node sx sy kind parent cx cy   the sites (float bits), node type, has-parent flag and the
#                                    node's centroid from the previous build (kept by cell-less sites)
#   tnode a g kind parent            the nodes without a site (for CheckForValidCells)
# `voronoi` prints vbuild vsite vevent vcell vedge; `polygons` prints poly ppt pnb and `commit a ok size`.

def handles(+stage: String) -> Bool:
  String.eq(stage, "voronoi") || String.eq(stage, "polygons")

def hex_digit(+c: U32) -> U32:
  Bool.pick(U32, (c < 58 : U32), (c - 48 : U32), (c - 87 : U32))

def hex_value(s: String, +acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, rest}:
      hex_value(rest, ((acc << 4n) + hex_digit(c) : U32))

def hex_of(+key: String, +fields: List<&2, String>) -> U32:
  hex_value(String.take(CN.text_or(CN.value_of(key, fields), "0"), 8n), 0)

def num(+key: String, +fields: List<&2, String>) -> U32:
  CN.number_or(CN.value_of(key, fields), 0)

def text(+key: String, +fields: List<&2, String>) -> String:
  CN.text_or(CN.value_of(key, fields), "")

def unquoted(+s: String) -> String:
  String.take(String.drop(s, 1n), Nat.sub(String.length(s), 2n))

def same_block(+a: String, +g: String, +fields: List<&2, String>) -> Bool:
  String.eq(text("a", fields), a) && String.eq(text("g", fields), g)

def head_in(l: List<&2, List<&2, String>>, +a: String, +g: String) -> Bool:
  match l:
    case Nil{}:
      False{}
    case Con{+r, _}:
      same_block(a, g, r)

def sites_go(recs: List<&2, List<&2, String>>, here: Bool, +a: String, +g: String) -> List<&2, List<&2, String>>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+r, +rest}:
      match here:
        case True{}:
          r <> sites_go(rest, head_in(rest, a, g), a, g)
        case False{}:
          sites_go(rest, head_in(rest, a, g), a, g)

def block_sites(+recs: List<&2, List<&2, String>>, +a: String, +g: String) -> List<&2, List<&2, String>>:
  sites_go(recs, head_in(recs, a, g), a, g)

def site_in(+r: List<&2, String>) -> VG.SiteIn:
  VG.SiteIn{hex_of("sx", r), hex_of("sy", r), num("kind", r), hex_of("cx", r), hex_of("cy", r)}

def sites_in(recs: List<&2, List<&2, String>>) -> List<&2, VG.SiteIn>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+r, rest}:
      site_in(r) <> sites_in(rest)

def names_in(recs: List<&2, List<&2, String>>) -> List<&2, String>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+r, rest}:
      unquoted(text("node", r)) <> names_in(rest)

def checks_of_nodes(recs: List<&2, List<&2, String>>) -> List<&2, CM.NodeCheck>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+r, rest}:
      CM.NodeCheck{num("kind", r), U32.is_eq(num("parent", r), 1), 0} <> checks_of_nodes(rest)

type Out is Type:
  Out{voronoi: List<&2, String>, polygons: List<&2, String>}

def point_count(l: List<&2, VG.P32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      point_count(rest, (acc + 1 : U32))

type Checks is Type:
  Checks{polys: Array<VG.Poly>, acc: List<&2, CM.NodeCheck>}

def check_of(+p: VG.Poly, +r: List<&2, String>) -> CM.NodeCheck:
  match p:
    case VG.Poly{+pts, _, _, _, _}:
      CM.NodeCheck{num("kind", r), U32.is_eq(num("parent", r), 1), point_count(pts, 0)}

def check_got(got: Array<VG.Poly> & VG.Poly, +r: List<&2, String>, +acc: List<&2, CM.NodeCheck>) -> Checks:
  (polys, +p) = got
  Checks{polys, check_of(p, r) <> acc}

def check_step(c: Checks, +r: List<&2, String>, +i: U32) -> Checks:
  match c:
    case Checks{polys, +acc}:
      check_got(Array.get(VG.Poly, polys, i), r, acc)

# The CheckForValidCells entries of the sited nodes (their polygons' point counts).
def site_checks(recs: List<&2, List<&2, String>>, c: Checks, +i: U32) -> Checks:
  match recs:
    case Nil{}:
      c
    case Con{+r, rest}:
      site_checks(rest, check_step(c, r, i), (i + 1 : U32))

def renumber_words(l: List<&2, String>, +b: U32, +next: U32) -> List<&2, String>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+w, rest}:
      Bool.pick(String, String.eq(w, CN.number("b", b)), CN.number("b", next), w) <> renumber_words(rest, b, next)

def renumbered(l: List<&2, String>, +b: U32, +next: U32) -> List<&2, String>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+line, rest}:
      String.join(renumber_words(String.split(line, ' '), b, next), " ") <> renumbered(rest, b, next)

def copied(twice: Bool, +vl: List<&2, String>, +b: U32) -> List<&2, String>:
  match twice:
    case True{}:
      List.append(&2, String, vl, renumbered(vl, b, (b + 1 : U32)))
    case False{}:
      vl

def lines_with(got: VD.Diagram & List<&2, String>, polys: Array<VG.Poly>, +a: U32, +b: U32, +ctx: String, +copies: U32, +at: String, +sites: List<&2, VG.SiteIn>, +names: List<&2, String>) -> Out:
  (_, +vl) = got
  Out{copied(U32.is_eq(copies, 2), vl, b), VN.polygon_records(a, at, polys, sites, names)}

def build_lines(c: VG.Cells, +a: U32, +b: U32, +ctx: String, +copies: U32, +at: String, +sites: List<&2, VG.SiteIn>, +names: List<&2, String>) -> Out:
  match c:
    case VG.Cells{built, polys, _}:
      lines_with(VN.build_records(a, b, ctx, built), polys, a, b, ctx, copies, at, sites, names)

def commit_record(+a: U32, +ok: Bool, +size: U32) -> String:
  CN.record("commit", [CN.number("a", a), CN.number("ok", Bool.to_u32(ok)), CN.number("size", size)])

def commit_joined(o: Out, +rec: String) -> Out:
  match o:
    case Out{+v, +p}:
      Out{v, List.append(&2, String, p, [rec])}

def commit_checked_with(polys: Array<VG.Poly>, +checks: List<&2, CM.NodeCheck>, built: VB.Built, +n: U32, +block: List<&2, String>, +names: List<&2, String>, +size: U32, +sites: List<&2, VG.SiteIn>, +twice: Bool) -> Out:
  +a = num("a", block)
  commit_joined(build_lines(VG.Cells{built, polys, n}, a, num("b", block), unquoted(text("at", block)), Bool.pick(U32, twice, 2, 1), unquoted(text("at", block)), sites, names), commit_record(a, CM.valid_cells(checks), size))

def commit_checked(c: Checks, built: VB.Built, +n: U32, +block: List<&2, String>, +names: List<&2, String>, +size: U32, +sites: List<&2, VG.SiteIn>, +twice: Bool) -> Out:
  match c:
    case Checks{polys, +checks}:
      commit_checked_with(polys, checks, built, n, block, names, size, sites, twice)

def commit_cells(c: VG.Cells, +block: List<&2, String>, +site_recs: List<&2, List<&2, String>>, +extra: List<&2, CM.NodeCheck>, +names: List<&2, String>, +size: U32, +sites: List<&2, VG.SiteIn>, +twice: Bool) -> Out:
  match c:
    case VG.Cells{built, polys, +n}:
      commit_checked(site_checks(site_recs, Checks{polys, extra}, 0), built, n, block, names, size, sites, twice)

def commit_out(c: CM.Committed, +block: List<&2, String>, +site_recs: List<&2, List<&2, String>>, +extra: List<&2, CM.NodeCheck>, +names: List<&2, String>, +windows: Bool) -> Out:
  match c:
    case CM.Committed{+size, +sites, +twice, cells}:
      commit_cells(cells, block, site_recs, extra, names, size, sites, twice)

def tile_out(+c: CM.Centred, +windows: Bool, +a: U32, +b: U32, +at: String, +size: U32, +names: List<&2, String>) -> Out:
  match c:
    case CM.Centred{+sites, _}:
      build_lines(VG.build_voronoi(windows, size, size, sites), a, b, at, 1, at, sites, names)

def op_pass(tilemap: Bool, +windows: Bool, +sites: List<&2, VG.SiteIn>, +names: List<&2, String>, +a: U32, +b: U32, +at: String, +w: U32, +h: U32, +size: U32) -> Out:
  match tilemap:
    case True{}:
      tile_out(CM.tile_map_centre(sites, size, w, h), windows, a, b, at, size, names)
    case False{}:
      build_lines(VG.build_voronoi(windows, w, h, sites), a, b, at, 1, at, sites, names)

def op_block(commit: Bool, +tilemap: Bool, +windows: Bool, +block: List<&2, String>, +site_recs: List<&2, List<&2, String>>, +extra: List<&2, CM.NodeCheck>, +sites: List<&2, VG.SiteIn>, +names: List<&2, String>) -> Out:
  match commit:
    case True{}:
      commit_out(CM.commit(windows, num("w", block), num("h", block), sites), block, site_recs, extra, names, windows)
    case False{}:
      op_pass(tilemap, windows, sites, names, num("a", block), num("b", block), unquoted(text("at", block)), num("w", block),
        num("h", block), num("size", block))

def op_route(+op: String, +windows: Bool, +block: List<&2, String>, +site_recs: List<&2, List<&2, String>>, +extra: List<&2, CM.NodeCheck>) -> Out:
  op_block(String.eq(op, "commit"), String.eq(op, "tilemap"), windows, block, site_recs, extra, sites_in(site_recs), names_in(site_recs))

def block_out(+windows: Bool, +block: List<&2, String>, +site_recs: List<&2, List<&2, String>>, +node_recs: List<&2, List<&2, String>>) -> Out:
  +a = text("a", block)
  +g = text("g", block)
  op_route(text("op", block), windows, block, block_sites(site_recs, a, g), checks_of_nodes(block_sites(node_recs, a, g)))

def pick_lines(o: Out, +polygons: Bool) -> List<&2, String>:
  match o:
    case Out{+v, +p}:
      Bool.pick(List<&2, String>, polygons, p, v)

def all_blocks(blocks: List<&2, List<&2, String>>, +windows: Bool, +site_recs: List<&2, List<&2, String>>, +node_recs: List<&2, List<&2, String>>, +polygons: Bool) -> List<&2, String>:
  match blocks:
    case Nil{}:
      Nil{}
    case Con{+block, rest}:
      List.append(&2, String, pick_lines(block_out(windows, block, site_recs, node_recs), polygons), all_blocks(rest, windows, site_recs, node_recs, polygons))

def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  +lines = String.split(input, '\n')
  all_blocks(CN.records("tblock", lines), windows, CN.records("tsite", lines), CN.records("tnode", lines), String.eq(stage, "polygons"))
