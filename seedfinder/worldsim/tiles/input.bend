import Base
import ../../trace/canon.bend as Canon
import ../../f32/ops.bend as F32Ops
import ../../f64/repr.bend as F64Repr
import ./table.bend as TileTable
import ./world.bend as TileWorld

# The tile stages' inputs read back from the oracle's `tileinput` records: the committed map of one attempt as a
# TileWorld.World, plus record helpers shared by the map trace stages.

def hex_value(+code: U32) -> U32:
  Bool.pick(U32, (code >= 97 : U32), (code - 87 : U32), (code - 48 : U32))

def hex_loop(n: Nat, s: String, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      match s:
        case SNil{}:
          acc
        case SCon{Chr{+code}, rest}:
          hex_loop(p, rest, ((acc << 4n) .|. hex_value(code) : U32))

def text(+key: String, +fields: List<&2, String>) -> String:
  Canon.text_or(Canon.value_of(key, fields), "")

def num(+key: String, +fields: List<&2, String>) -> U32:
  Canon.number_or(Canon.value_of(key, fields), TileWorld.none())

def f32_field(+key: String, +fields: List<&2, String>) -> F32:
  F32Ops.from_bits(hex_loop(8n, text(key, fields), 0))

def f64_field(+key: String, +fields: List<&2, String>) -> F64Repr.F64:
  +s = text(key, fields)
  F64Repr.F64{hex_loop(8n, s, 0), hex_loop(8n, String.drop(s, 8n), 0)}

def is_inf(+key: String, +fields: List<&2, String>) -> Bool:
  String.eq(text(key, fields), "inf")

def keep_if(hit: Bool, +fields: List<&2, String>, tail: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match hit:
    case True{}:
      fields <> tail
    case False{}:
      tail

def keep_attempt(+a: String, recs: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      keep_if(String.eq(text("a", fields), a), fields, keep_attempt(a, rest))

def of_attempt(+kind: String, +a: String, +lines: List<&2, String>) -> List<&2, List<&2, String>>:
  keep_attempt(a, Canon.records(kind, lines))

type Raw is Data:
  Raw{kind: U32, itype: U32, tile: U32, flags: U32, site: U32, parent: U32, pig: U32}

def pig_of(+id: String) -> U32:
  Bool.pick(U32, String.contains(id, "PigKingdom"), 1, Bool.pick(U32, String.contains(id, "PigVillage"), 2, 0))

def raw_of(+fields: List<&2, String>) -> Raw:
  Raw{num("type", fields), num("itype", fields), num("tile", fields), num("flags", fields), num("site", fields),
    num("parent", fields), pig_of(text("id", fields))}

def raws(recs: List<&2, List<&2, String>>) -> List<&2, Raw>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      raw_of(fields) <> raws(rest)

def no_raw() -> Raw:
  Raw{TileWorld.none(), 0, 0, 0, TileWorld.none(), TileWorld.none(), 0}

def raw_at(+t: TileTable.Tree<Raw>, +i: U32) -> Raw:
  Bool.pick(Raw, TileWorld.is_none(i), no_raw(), TileTable.at(~Raw, t, i))

def node_with_parent(+i: U32, r: Raw, p: Raw) -> TileWorld.Node:
  match r:
    case Raw{+kind, +itype, +tile, +flags, _, +parent, +pig}:
      match p:
        case Raw{+pkind, _, _, _, +psite, +grand, _}:
          TileWorld.Node{i, kind, itype, tile, flags, parent, grand, pkind, psite, pig}

def node_of(+t: TileTable.Tree<Raw>, +i: U32, r: Raw) -> TileWorld.Node:
  match r:
    case Raw{+kind, +itype, +tile, +flags, +site, +parent, +pig}:
      node_with_parent(i, Raw{kind, itype, tile, flags, site, parent, pig}, raw_at(t, parent))

def point_of(+fields: List<&2, String>) -> TileWorld.Point:
  TileWorld.Point{f32_field("x", fields), f32_field("y", fields)}

def points_of(recs: List<&2, List<&2, String>>) -> List<&2, TileWorld.Point>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      point_of(fields) <> points_of(rest)

def sites_loop(recs: List<&2, List<&2, String>>, +t: TileTable.Tree<Raw>, +i: U32, +points: List<&2, TileWorld.Point>) -> List<&2, TileWorld.Site>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      +n = U32.to_nat(num("n", fields))
      TileWorld.Site{node_of(t, i, raw_at(t, i)), f32_field("x", fields), f32_field("y", fields), f32_field("cx", fields),
        f32_field("cy", fields), List.take(&2, TileWorld.Point, points, n)}
        <> sites_loop(rest, t, (i + 1 : U32), List.drop(&2, TileWorld.Point, points, n))

def edge_of(+s: String, +t: String, +fields: List<&2, String>) -> TileWorld.Edge:
  TileWorld.Edge{num(s, fields), num(t, fields)}

def edges_of(+s: String, +t: String, recs: List<&2, List<&2, String>>) -> List<&2, TileWorld.Edge>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      edge_of(s, t, fields) <> edges_of(s, t, rest)

def targets_keep(hit: Bool, +t: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      t <> tail
    case False{}:
      tail

def targets_of(+v: U32, pairs: List<&2, TileWorld.Edge>) -> List<&2, U32>:
  match pairs:
    case Nil{}:
      Nil{}
    case Con{TileWorld.Edge{+s, +t}, rest}:
      targets_keep(U32.is_eq(s, v), t, targets_of(v, rest))

def adjacency_loop(n: Nat, +v: U32, +pairs: List<&2, TileWorld.Edge>) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      targets_of(v, pairs) <> adjacency_loop(p, (v + 1 : U32), pairs)

def maybe_point(inf: Bool, +x: F64Repr.F64, +y: F64Repr.F64) -> Maybe<&2, TileWorld.DPoint>:
  match inf:
    case True{}:
      None{}
    case False{}:
      Some{TileWorld.DPoint{x, y}}

def vertex_of(+kx: String, +ky: String, +fields: List<&2, String>) -> Maybe<&2, TileWorld.DPoint>:
  maybe_point(is_inf(kx, fields), f64_field(kx, fields), f64_field(ky, fields))

def dpoints_of(recs: List<&2, List<&2, String>>) -> List<&2, TileWorld.DPoint>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      TileWorld.DPoint{f64_field("x", fields), f64_field("y", fields)} <> dpoints_of(rest)

def plain_second(+a: TileWorld.DPoint, v1: Maybe<&2, TileWorld.DPoint>) -> List<&2, TileWorld.DPoint>:
  match v1:
    case None{}:
      Nil{}
    case Some{+b}:
      [a, b]

def plain_points(v0: Maybe<&2, TileWorld.DPoint>, +v1: Maybe<&2, TileWorld.DPoint>) -> List<&2, TileWorld.DPoint>:
  match v0:
    case None{}:
      Nil{}
    case Some{+a}:
      plain_second(a, v1)

def vedge_points(+np: Nat, +v0: Maybe<&2, TileWorld.DPoint>, +v1: Maybe<&2, TileWorld.DPoint>, +pts: List<&2, TileWorld.DPoint>) -> List<&2, TileWorld.DPoint>:
  match np:
    case 0n:
      plain_points(v0, v1)
    case 1n+_:
      List.take(&2, TileWorld.DPoint, pts, np)

def vedge_of(+fields: List<&2, String>, +pts: List<&2, TileWorld.DPoint>) -> TileWorld.VEdge:
  +v0 = vertex_of("x0", "y0", fields)
  +v1 = vertex_of("x1", "y1", fields)
  TileWorld.VEdge{num("twin", fields), v0, v1, vedge_points(U32.to_nat(num("np", fields)), v0, v1, pts)}

def vedges_loop(recs: List<&2, List<&2, String>>, +pts: List<&2, TileWorld.DPoint>) -> List<&2, TileWorld.VEdge>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      vedge_of(fields, pts) <> vedges_loop(rest, List.drop(&2, TileWorld.DPoint, pts, U32.to_nat(num("np", fields))))

def cells_loop(recs: List<&2, List<&2, String>>, +edges: List<&2, TileWorld.VEdge>) -> List<&2, TileWorld.Cell>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      +ne = U32.to_nat(num("ne", fields))
      TileWorld.Cell{num("src", fields), List.take(&2, TileWorld.VEdge, edges, ne)} <> cells_loop(rest, List.drop(&2, TileWorld.VEdge, edges, ne))

def no_cell() -> TileWorld.Cell:
  TileWorld.Cell{TileWorld.none(), Nil{}}

def cell_pick(hit: Bool, +c: TileWorld.Cell, +other: TileWorld.Cell) -> TileWorld.Cell:
  match hit:
    case True{}:
      c
    case False{}:
      other

def cell_for(+i: U32, cells: List<&2, TileWorld.Cell>) -> TileWorld.Cell:
  match cells:
    case Nil{}:
      no_cell()
    case Con{TileWorld.Cell{+src, +edges}, rest}:
      cell_pick(U32.is_eq(src, i), TileWorld.Cell{src, edges}, cell_for(i, rest))

def cells_by_site(n: Nat, +i: U32, +cells: List<&2, TileWorld.Cell>) -> List<&2, TileWorld.Cell>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cell_for(i, cells) <> cells_by_site(p, (i + 1 : U32), cells)

def first_fields(recs: List<&2, List<&2, String>>) -> List<&2, String>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, _}:
      fields

def world_parts(+map: List<&2, String>, +raw: TileTable.Tree<Raw>, +sites: List<&2, TileWorld.Site>, +adjacency: List<&2, List<&2, U32>>, +edges: List<&2, TileWorld.Edge>, +cells: List<&2, TileWorld.Cell>) -> TileWorld.World:
  +count = num("sites", map)
  TileWorld.World{num("w", map), num("h", map), count, sites, TileTable.from_list(~TileWorld.Site, sites, TileWorld.Site{node_of(raw, 0, no_raw()), 0.0, 0.0, 0.0, 0.0, Nil{}}),
    TileTable.from_list(~List<&2, U32>, adjacency, Nil{}), edges, cells,
    TileTable.from_list(~TileWorld.Cell, cells_by_site(U32.to_nat(count), 0, cells), no_cell())}

# The World of attempt `a` from the `tileinput` records.
def world_of(+a: String, +lines: List<&2, String>) -> TileWorld.World:
  +map = first_fields(of_attempt("tmap", a, lines))
  +raw = TileTable.from_list(~Raw, raws(of_attempt("tnode", a, lines)), no_raw())
  +count = num("sites", map)
  world_parts(map, raw, sites_loop(of_attempt("tsite", a, lines), raw, 0, points_of(of_attempt("tppt", a, lines))),
    adjacency_loop(U32.to_nat(count), 0, edges_of("v", "to", of_attempt("tadj", a, lines))),
    edges_of("s", "t", of_attempt("tedge", a, lines)),
    cells_loop(of_attempt("tcell", a, lines), vedges_loop(of_attempt("tvedge", a, lines), dpoints_of(of_attempt("tvpt", a, lines)))))

def attempts(recs: List<&2, List<&2, String>>) -> List<&2, String>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      text("a", fields) <> attempts(rest)
