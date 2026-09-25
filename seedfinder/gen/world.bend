import Base
import ../f32/ops.bend as FO
import ../f64/repr.bend as FR
import ../storygen/graph.bend as GG
import ../worldsim/voronoi/diagram.bend as VD
import ../worldsim/voronoi/polygon.bend as VG
import ../worldsim/tiles/table.bend as TB
import ../worldsim/tiles/world.bend as TW
import ./graph.bend as GK
import ./tags.bend as GP

# The committed map as the tile stages read it (TW.World, the input of M8's tile code): the Klei node of every site
# and the cells of the ConvertToTileMap build, with the double points DrawVoronoiEdge rasterises.

def pig_of(+id: String) -> U32:
  Bool.pick(U32, String.contains(id, "PigKingdom"), 1, Bool.pick(U32, String.contains(id, "PigVillage"), 2, 0))

# AddChild's type argument as the emulator stores it: 1..7, else 0 (nil included).
def cpp_type(+t: U32) -> U32:
  Bool.pick(U32, (0 < t : U32) && (t < 8 : U32), t, 0)

def cpp_itype(+t: U32) -> U32:
  Bool.pick(U32, U32.is_eq(t, GG.none()), 0, t)

def index_of(xs: List<&2, U32>, +v: U32, +i: U32) -> U32:
  match xs:
    case Nil{}:
      TW.none()
    case Con{+x, rest}:
      Bool.pick(U32, U32.is_eq(x, v), i, index_of(rest, v, (i + 1 : U32)))

# The graph objects that parent the sites' nodes, in the order the oracle's tnode records number them (first use by
# a site in site order), so parent numbers are the site count plus this index.
def parents_loop(vs: List<&2, U32>, +k: GK.Klei, +seen: List<&2, U32>) -> List<&2, U32>:
  match vs:
    case Nil{}:
      seen
    case Con{+x, rest}:
      +o = GK.parent_of(k, x)
      +fresh = Bool.not(TW.is_none(o)) && TW.is_none(index_of(seen, o, 0))
      parents_loop(rest, k, Bool.pick(List<&2, U32>, fresh, List.append(&2, U32, seen, [o]), seen))

def parent_objects(+k: GK.Klei) -> List<&2, U32>:
  parents_loop(GK.vertices_of(k), k, Nil{})

def parent_number(+objects: List<&2, U32>, +count: U32, +o: U32) -> U32:
  Bool.pick(U32, TW.is_none(o), TW.none(), (count + index_of(objects, o, 0) : U32))

def node_of(+s: GG.St, +k: GK.Klei, +objects: List<&2, U32>, +i: U32, +x: U32) -> TW.Node:
  +parent = parent_number(objects, GK.count_of(k), GK.parent_of(k, x))
  +parent_kind = Bool.pick(U32, TW.is_none(parent), TW.none(), 0)
  TW.Node{i, cpp_type(GG.nf(s, x, GG.f_type())), cpp_itype(GG.nf(s, x, GG.f_itype())), GG.nf(s, x, GG.f_value()), GP.site_flags(s, x),
    parent, TW.none(), parent_kind, TW.none(), pig_of(GG.node_name(s, x))}

def nodes_loop(vs: List<&2, U32>, +s: GG.St, +k: GK.Klei, +objects: List<&2, U32>, +i: U32) -> List<&2, TW.Node>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      node_of(s, k, objects, i, x) <> nodes_loop(rest, s, k, objects, (i + 1 : U32))

# The Klei node of every site (vertex order).
def nodes(+s: GG.St, +k: GK.Klei) -> List<&2, TW.Node>:
  nodes_loop(GK.vertices_of(k), s, k, parent_objects(k), 0)

def poly_listed(got: Array<VG.Poly> & VG.Poly, +acc: List<&2, VG.Poly>) -> Array<VG.Poly> & List<&2, VG.Poly>:
  (polys, +q) = got
  (polys, q <> acc)

def polys_loop(n: Nat, +i: U32, got: Array<VG.Poly> & List<&2, VG.Poly>) -> Array<VG.Poly> & List<&2, VG.Poly>:
  match n:
    case 0n:
      got
    case 1n+p:
      (polys, +acc) = got
      polys_loop(p, (i + 1 : U32), poly_listed(Array.get(VG.Poly, polys, i), acc))

def polys_done(got: Array<VG.Poly> & List<&2, VG.Poly>) -> List<&2, VG.Poly>:
  (_, +acc) = got
  List.reverse(&2, VG.Poly, acc)

# The BuildVoronoi result of every site, in site order.
def poly_list(polys: Array<VG.Poly>, +n: U32) -> List<&2, VG.Poly>:
  polys_done(polys_loop(U32.to_nat(n), 0, (polys, Nil{})))

def dpoint(+p: VG.D2) -> TW.DPoint:
  match p:
    case VG.D2{+x, +y}:
      TW.DPoint{x, y}

def dpoints(ps: List<&2, VG.D2>) -> List<&2, TW.DPoint>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      dpoint(p) <> dpoints(rest)

def maybe_point(has: Bool, +x: FR.F64, +y: FR.F64) -> Maybe<&2, TW.DPoint>:
  match has:
    case True{}:
      Some{TW.DPoint{x, y}}
    case False{}:
      None{}

# DrawVoronoiEdge's points of a half-edge: its two vertices (plus the sampled parabola when curved), or the clipped
# ray when a vertex is missing.
def drawn(complete: Bool, c: VG.Ctx, +cell1: VD.Cell, +cell2: VD.Cell, +h: VD.Half) -> VG.Ctx & List<&2, VG.D2>:
  match complete:
    case True{}:
      match h:
        case VD.Half{_, _, +x0, +y0, _, +x1, +y1, +f}:
          VG.curved_if(U32.is_zero((f .&. VD.linear_bit() : U32)), c, cell1, cell2, VG.D2{x0, y0}, VG.D2{x1, y1})
    case False{}:
      VG.clip_infinite(c, cell1, cell2, h)

type Walk is Type:
  Walk{d: VD.Diagram, c: VG.Ctx, edges: List<&2, TW.VEdge>}

def cell_src(+cell: VD.Cell) -> U32:
  match cell:
    case VD.Cell{+src, _, _}:
      src

def vedge_of(got: VG.Ctx & List<&2, VG.D2>, d: VD.Diagram, +twin: U32, +h: VD.Half, +acc: List<&2, TW.VEdge>) -> Walk:
  (c, +pts) = got
  match h:
    case VD.Half{_, +has0, +x0, +y0, +has1, +x1, +y1, _}:
      Walk{d, c, TW.VEdge{twin, maybe_point(has0, x0, y0), maybe_point(has1, x1, y1), dpoints(pts)} <> acc}

def half_edge(got: VD.Diagram & VD.Cell, c: VG.Ctx, +cell1: VD.Cell, +h: VD.Half, +acc: List<&2, TW.VEdge>) -> Walk:
  (d, +cell2) = got
  vedge_of(drawn(VG.half_complete(h), c, cell1, cell2, h), d, cell_src(cell2), h, acc)

def halves_loop(hs: List<&2, VD.Half>, w: Walk, +cell1: VD.Cell) -> Walk:
  match hs:
    case Nil{}:
      w
    case Con{+h, rest}:
      match w:
        case Walk{d, c, +acc}:
          halves_loop(rest, half_edge(VD.cell_info(d, VG.half_twin(h)), c, cell1, h, acc), cell1)

type Scan is Type:
  Scan{d: VD.Diagram, c: VG.Ctx, cells: List<&2, TW.Cell>}

def walked(w: Walk, +src: U32, +cells: List<&2, TW.Cell>) -> Scan:
  match w:
    case Walk{d, c, +acc}:
      Scan{d, c, TW.Cell{src, List.reverse(&2, TW.VEdge, acc)} <> cells}

def ringed(r: VD.Ring, c: VG.Ctx, +cell: VD.Cell, +cells: List<&2, TW.Cell>) -> Scan:
  match r:
    case VD.Ring{d, +hs}:
      walked(halves_loop(hs, Walk{d, c, Nil{}}, cell), cell_src(cell), cells)

def cell_if(inside: Bool, got: VD.Diagram & VD.Cell, c: VG.Ctx, +cells: List<&2, TW.Cell>, +k: U32) -> Scan:
  match inside:
    case True{}:
      (d, +cell) = got
      ringed(VD.cell_ring(d, k), c, cell, cells)
    case False{}:
      (d, _) = got
      Scan{d, c, cells}

def cell_at(got: VD.Diagram & VD.Cell, c: VG.Ctx, +cells: List<&2, TW.Cell>, +k: U32, +n: U32) -> Scan:
  (d, +cell) = got
  cell_if((cell_src(cell) < n : U32), (d, cell), c, cells, k)

def scan_loop(fuel: Nat, sc: Scan, +k: U32, +n: U32) -> Scan:
  match fuel:
    case 0n:
      sc
    case 1n+f:
      match sc:
        case Scan{d, c, +cells}:
          scan_loop(f, cell_at(VD.cell_info(d, k), c, cells, k, n), (k + 1 : U32), n)

def scanned(got: VD.Diagram & U32, c: VG.Ctx, +n: U32) -> Scan:
  (d, +nc) = got
  scan_loop(U32.to_nat(nc), Scan{d, c, Nil{}}, 0, n)

def cells_done(sc: Scan) -> VD.Diagram & List<&2, TW.Cell>:
  match sc:
    case Scan{d, _, +cells}:
      (d, List.reverse(&2, TW.Cell, cells))

def framed(got: VG.Ctx & Array<VG.Poly>, +w: U32, +h: U32) -> VG.Ctx:
  (c, _) = got
  VG.with_frame(c, VG.Frame{FR.from_u32(w), FR.from_u32(h)})

def site_context(+sites: List<&2, VG.SiteIn>, +w: U32, +h: U32) -> VG.Ctx:
  +depth = VG.depth_for(VG.count_sites(sites, 0))
  framed(VG.fill_polys(sites, Array.new(VG.SiteIn, depth, VG.SiteIn{0, 0, 0, 0, 0}), Array.new(VG.Poly, depth, VG.blank_poly(VG.SiteIn{0, 0, 0, 0, 0})), 0), w, h)

# The point cells of a w x h build of `sites`, in cell order, each with its ring of half-edges.
def cells(d: VD.Diagram, +sites: List<&2, VG.SiteIn>, +w: U32, +h: U32) -> VD.Diagram & List<&2, TW.Cell>:
  cells_done(scanned(VD.cell_count(d), site_context(sites, w, h), VG.count_sites(sites, 0)))

def no_cell() -> TW.Cell:
  TW.Cell{TW.none(), Nil{}}

def cell_for(cs: List<&2, TW.Cell>, +i: U32) -> TW.Cell:
  match cs:
    case Nil{}:
      no_cell()
    case Con{TW.Cell{+src, +edges}, rest}:
      Bool.pick(TW.Cell, U32.is_eq(src, i), TW.Cell{src, edges}, cell_for(rest, i))

def by_site(n: Nat, +cs: List<&2, TW.Cell>, +i: U32) -> List<&2, TW.Cell>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cell_for(cs, i) <> by_site(p, cs, (i + 1 : U32))

def point_of(+p: VG.P32) -> TW.Point:
  match p:
    case VG.P32{+x, +y}:
      TW.Point{FO.from_bits(x), FO.from_bits(y)}

def points_of(ps: List<&2, VG.P32>) -> List<&2, TW.Point>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      point_of(p) <> points_of(rest)

def site_of(+s: VG.SiteIn, +p: VG.Poly, +node: TW.Node) -> TW.Site:
  match s:
    case VG.SiteIn{+x, +y, _, _, _}:
      match p:
        case VG.Poly{+pts, +cx, +cy, _, _}:
          TW.Site{node, FO.from_bits(x), FO.from_bits(y), FO.from_bits(cx), FO.from_bits(cy), points_of(pts)}

def sites_loop(ss: List<&2, VG.SiteIn>, ps: List<&2, VG.Poly>, ns: List<&2, TW.Node>) -> List<&2, TW.Site>:
  match ss ps ns:
    case Con{+s, rest} Con{+p, prest} Con{+n, nrest}:
      site_of(s, p, n) <> sites_loop(rest, prest, nrest)
    case _ _ _:
      Nil{}

def edge_list(ls: List<&2, GK.Link>) -> List<&2, TW.Edge>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{GK.Link{+s, +t}, rest}:
      TW.Edge{s, t} <> edge_list(rest)

# The World of a w x w ConvertToTileMap build: the centred sites, their polygons, their Klei nodes, the diagram's cells
# and the graph edges left after ApplyPoisonTag.
def world(+w: U32, +sites: List<&2, VG.SiteIn>, +polys: List<&2, VG.Poly>, +nodes: List<&2, TW.Node>, +cs: List<&2, TW.Cell>, +links: List<&2, GK.Link>) -> TW.World:
  +n = VG.count_sites(sites, 0)
  +ts = sites_loop(sites, polys, nodes)
  +fill = {TW.Site{TW.Node{0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 0.0, 0.0, 0.0, 0.0, Nil{}} : TW.Site}
  TW.World{w, w, n, ts, TB.from_list(~TW.Site, ts, fill), TB.from_list(~List<&2, U32>, GK.adjacency(n, links), Nil{}), edge_list(links), cs,
    TB.from_list(~TW.Cell, by_site(U32.to_nat(n), cs, 0), no_cell())}
