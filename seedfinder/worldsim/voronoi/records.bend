import Base
import ../../f64/repr.bend as FR
import ../../trace/canon.bend as CN
import ./predicates.bend as VP
import ./diagram.bend as VD
import ./builder.bend as VB
import ./polygon.bend as VG

# The oracle's `voronoi` stage records of one construct_voronoi run (CONVENTIONS.md §8): vbuild, vsite, vevent,
# vcell and vedge, with the attempt field `a` and build number `b` given by the caller.

def signed(+key: String, +x: U32) -> String:
  Bool.pick(String, VP.lt(x, 0), key ++ "=-" ++ U32.show((0 - x : U32)), CN.number(key, x))

def f64_field(+key: String, +x: FR.F64) -> String:
  match x:
    case FR.F64{+h, +l}:
      key ++ "=" ++ CN.hex64(h, l)

def point_fields(+has: Bool, +kx: String, +ky: String, +x: FR.F64, +y: FR.F64) -> List<&2, String>:
  Bool.pick(List<&2, String>, has, [f64_field(kx, x), f64_field(ky, y)], [kx ++ "=inf", ky ++ "=inf"])

def site_lines(l: List<&2, VP.Site>, +head: List<&2, String>, +k: U32) -> List<&2, String>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      CN.record("vsite", List.append(&2, String, head, [CN.number("k", k), CN.number("src", VP.site_initial(s)),
        CN.number("cat", VP.site_category(s)), signed("x0", VP.site_x0(s)), signed("y0", VP.site_y0(s)),
        signed("x1", VP.site_x1(s)), signed("y1", VP.site_y1(s))])) <> site_lines(rest, head, (k + 1 : U32))

def event_lines(l: List<&2, VP.Circle>, +head: List<&2, String>, +k: U32) -> List<&2, String>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      CN.record("vevent", List.append(&2, String, head, [CN.number("k", k), f64_field("x", VP.circle_x(c)),
        f64_field("y", VP.circle_y(c)), f64_field("lx", VP.circle_lx(c))])) <> event_lines(rest, head, (k + 1 : U32))

def cell_src(c: VD.Cell) -> U32:
  match c:
    case VD.Cell{+s, _, _}:
      s

type Lines is Type:
  Lines{d: VD.Diagram, lines: List<&2, String>}

def edge_line(got: VD.Diagram & VD.Cell, +h: VD.Half, +head: List<&2, String>, +c: U32, +k: U32, +acc: List<&2, String>) -> Lines:
  (d, cell) = got
  match h:
    case VD.Half{_, +has0, +x0, +y0, +has1, +x1, +y1, +f}:
      +fields = {List.concat(&2, String, [head, [CN.number("c", c), CN.number("k", k), CN.number("twin", cell_src(cell))],
        point_fields(has0, "x0", "y0", x0, y0), point_fields(has1, "x1", "y1", x1, y1),
        [CN.number("lin", (f .&. VD.linear_bit() : U32)), CN.number("prim", ((f .&. VD.primary_bit() : U32) >> 1n : U32))]]) : List<&2, String>}
      Lines{d, CN.record("vedge", fields) <> acc}

def half_twin(h: VD.Half) -> U32:
  match h:
    case VD.Half{+t, _, _, _, _, _, _, _}:
      t

def edge_lines(hs: List<&2, VD.Half>, ls: Lines, +head: List<&2, String>, +c: U32, +k: U32) -> Lines:
  match hs:
    case Nil{}:
      ls
    case Con{+h, rest}:
      match ls:
        case Lines{d, +acc}:
          edge_lines(rest, edge_line(VD.cell_info(d, half_twin(h)), h, head, c, k, acc), head, c, (k + 1 : U32))

def length32(l: List<&2, VD.Half>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      length32(rest, (acc + 1 : U32))

def ring_lines(r: VD.Ring, +cell: VD.Cell, +head: List<&2, String>, +c: U32, +acc: List<&2, String>) -> Lines:
  match r:
    case VD.Ring{d, +hs}:
      match cell:
        case VD.Cell{+src, +cat, _}:
          +line = CN.record("vcell", List.append(&2, String, head, [CN.number("c", c), CN.number("src", src),
            CN.number("cat", cat), CN.number("deg", length32(hs, 0))]))
          edge_lines(hs, Lines{d, line <> acc}, head, c, 0)

def cell_lines(got: VD.Diagram & VD.Cell, +head: List<&2, String>, +c: U32, +acc: List<&2, String>) -> Lines:
  (d, +cell) = got
  ring_lines(VD.cell_ring(d, c), cell, head, c, acc)

def all_cells(n: Nat, ls: Lines, +head: List<&2, String>, +c: U32) -> Lines:
  match n:
    case 0n:
      ls
    case 1n+p:
      match ls:
        case Lines{d, +acc}:
          all_cells(p, cell_lines(VD.cell_info(d, c), head, c, acc), head, (c + 1 : U32))

def counted_cells(got: VD.Diagram & U32, +head: List<&2, String>) -> Lines:
  (d, +nc) = got
  all_cells(U32.to_nat(nc), Lines{d, Nil{}}, head, 0)

def lines_of(ls: Lines) -> VD.Diagram & List<&2, String>:
  match ls:
    case Lines{d, +acc}:
      (d, List.reverse(&2, String, acc))

def site_count(l: List<&2, VP.Site>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      site_count(rest, (acc + 1 : U32))

def with_cells(got: VD.Diagram & List<&2, String>, +front: List<&2, String>) -> VD.Diagram & List<&2, String>:
  (d, +cells) = got
  (d, List.append(&2, String, front, cells))

# The voronoi stage records of a build (the diagram is handed back for the polygon stage).
def build_records(+a: U32, +b: U32, +ctx: String, built: VB.Built) -> VD.Diagram & List<&2, String>:
  match built:
    case VB.Built{+sites, +events, d}:
      +head = {[CN.number("a", a), CN.number("b", b)] : List<&2, String>}
      +start = CN.record("vbuild", [CN.number("a", a), CN.number("b", b), CN.field("ctx", CN.quoted(ctx)), CN.number("sites", site_count(sites, 0))])
      +front = {start <> List.append(&2, String, site_lines(sites, head, 0), event_lines(events, head, 0)) : List<&2, String>}
      with_cells(lines_of(counted_cells(VD.cell_count(d), head)), front)

def hex32(+key: String, +x: U32) -> String:
  key ++ "=" ++ CN.hex32(x)

def name_of(+names: List<&2, String>, +j: U32) -> String:
  Bool.pick(String, U32.is_eq(j, VD.nil()), "<boundary>", Maybe.default(&2, String, List.get(&2, String, names, U32.to_nat(j)), "<null>"))

def point_lines(l: List<&2, VG.P32>, +head: List<&2, String>, +k: U32) -> List<&2, String>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      match p:
        case VG.P32{+x, +y}:
          CN.record("ppt", List.append(&2, String, head, [CN.number("k", k), hex32("x", x), hex32("y", y)])) <> point_lines(rest, head, (k + 1 : U32))

def neighbour_lines(l: List<&2, U32>, +head: List<&2, String>, +names: List<&2, String>, +k: U32) -> List<&2, String>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+j, rest}:
      CN.record("pnb", List.append(&2, String, head, [CN.number("k", k), CN.field("to", CN.quoted(name_of(names, j)))])) <> neighbour_lines(rest, head, names, (k + 1 : U32))

def count_points(l: List<&2, VG.P32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      count_points(rest, (acc + 1 : U32))

def count_nbs(l: List<&2, U32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      count_nbs(rest, (acc + 1 : U32))

def site_poly_lines(+p: VG.Poly, +s: VG.SiteIn, +head: List<&2, String>, +names: List<&2, String>, +i: U32) -> List<&2, String>:
  match p:
    case VG.Poly{+pts, +cx, +cy, +nbs, +state}:
      match s:
        case VG.SiteIn{+sx, +sy, _, _, _}:
          +site_head = {List.append(&2, String, head, [CN.number("site", i)]) : List<&2, String>}
          +poly = CN.record("poly", List.append(&2, String, site_head, [CN.field("node", CN.quoted(name_of(names, i))), hex32("sx", sx), hex32("sy", sy),
            CN.number("n", count_points(pts, 0)), hex32("cx", cx), hex32("cy", cy), signed("state", state), CN.number("nbs", count_nbs(nbs, 0))]))
          poly <> List.append(&2, String, point_lines(pts, site_head, 0), neighbour_lines(nbs, site_head, names, 0))

type PolyLines is Type:
  PolyLines{polys: Array<VG.Poly>, lines: List<&2, String>}

def poly_step(got: Array<VG.Poly> & VG.Poly, +s: VG.SiteIn, +head: List<&2, String>, +names: List<&2, String>, +i: U32, +acc: List<&2, String>) -> PolyLines:
  (polys, +p) = got
  PolyLines{polys, List.append(&2, String, List.reverse(&2, String, site_poly_lines(p, s, head, names, i)), acc)}

def poly_loop(sites: List<&2, VG.SiteIn>, pl: PolyLines, +head: List<&2, String>, +names: List<&2, String>, +i: U32) -> PolyLines:
  match sites:
    case Nil{}:
      pl
    case Con{+s, rest}:
      match pl:
        case PolyLines{polys, +acc}:
          poly_loop(rest, poly_step(Array.get(VG.Poly, polys, i), s, head, names, i, acc), head, names, (i + 1 : U32))

def poly_lines_of(pl: PolyLines) -> List<&2, String>:
  match pl:
    case PolyLines{_, +acc}:
      List.reverse(&2, String, acc)

# The `polygons` stage records (poly, ppt, pnb) of a BuildVoronoi, for every site in order (names: node ids).
def polygon_records(+a: U32, +at: String, polys: Array<VG.Poly>, +sites: List<&2, VG.SiteIn>, +names: List<&2, String>) -> List<&2, String>:
  +head = {[CN.number("a", a), CN.field("at", CN.quoted(at))] : List<&2, String>}
  poly_lines_of(poly_loop(sites, PolyLines{polys, Nil{}}, head, names, 0))
