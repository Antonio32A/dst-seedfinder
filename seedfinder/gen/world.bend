import Base
import ../f32/ops.bend as F32Ops
import ../f64/repr.bend as F64Repr
import ../storygen/graph.bend as StoryGraph
import ../worldsim/voronoi/diagram.bend as VoronoiDiagram
import ../worldsim/voronoi/polygon.bend as VoronoiPolygon
import ../worldsim/tiles/table.bend as TileTable
import ../worldsim/tiles/world.bend as TileWorld
import ./graph.bend as GenGraph
import ./tags.bend as GenTags

# The committed map as the tile stages read it (TileWorld.World, the input of M8's tile code): the Klei node of every site
# and the cells of the ConvertToTileMap build, with the double points DrawVoronoiEdge rasterises.

def pig_of(+id: String) -> U32:
  Bool.pick(U32, String.contains(id, "PigKingdom"), 1, Bool.pick(U32, String.contains(id, "PigVillage"), 2, 0))

# AddChild's type argument as the emulator stores it: 1..7, else 0 (nil included).
def cpp_type(+t: U32) -> U32:
  Bool.pick(U32, (0 < t : U32) && (t < 8 : U32), t, 0)

def cpp_itype(+t: U32) -> U32:
  Bool.pick(U32, U32.is_eq(t, StoryGraph.none()), 0, t)

def index_of(xs: List<&2, U32>, +v: U32, +i: U32) -> U32:
  match xs:
    case Nil{}:
      TileWorld.none()
    case Con{+x, rest}:
      Bool.pick(U32, U32.is_eq(x, v), i, index_of(rest, v, (i + 1 : U32)))

# The graph objects that parent the sites' nodes, in the order the oracle's tnode records number them (first use by
# a site in site order), so parent numbers are the site count plus this index.
def parents_loop(vs: List<&2, U32>, +k: GenGraph.Klei, +seen: List<&2, U32>) -> List<&2, U32>:
  match vs:
    case Nil{}:
      seen
    case Con{+x, rest}:
      +o = GenGraph.parent_of(k, x)
      +fresh = Bool.not(TileWorld.is_none(o)) && TileWorld.is_none(index_of(seen, o, 0))
      parents_loop(rest, k, Bool.pick(List<&2, U32>, fresh, List.append(&2, U32, seen, [o]), seen))

def parent_objects(+k: GenGraph.Klei) -> List<&2, U32>:
  parents_loop(GenGraph.vertices_of(k), k, Nil{})

def parent_number(+objects: List<&2, U32>, +count: U32, +o: U32) -> U32:
  Bool.pick(U32, TileWorld.is_none(o), TileWorld.none(), (count + index_of(objects, o, 0) : U32))

def node_of(+s: StoryGraph.St, +k: GenGraph.Klei, +objects: List<&2, U32>, +i: U32, +x: U32) -> TileWorld.Node:
  +parent = parent_number(objects, GenGraph.count_of(k), GenGraph.parent_of(k, x))
  +parent_kind = Bool.pick(U32, TileWorld.is_none(parent), TileWorld.none(), 0)
  TileWorld.Node{i, cpp_type(StoryGraph.nf(s, x, StoryGraph.f_type())), cpp_itype(StoryGraph.nf(s, x, StoryGraph.f_itype())), StoryGraph.nf(s, x, StoryGraph.f_value()), GenTags.site_flags(s, x),
    parent, TileWorld.none(), parent_kind, TileWorld.none(), pig_of(StoryGraph.node_name(s, x))}

def nodes_loop(vs: List<&2, U32>, +s: StoryGraph.St, +k: GenGraph.Klei, +objects: List<&2, U32>, +i: U32) -> List<&2, TileWorld.Node>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      node_of(s, k, objects, i, x) <> nodes_loop(rest, s, k, objects, (i + 1 : U32))

# The Klei node of every site (vertex order).
def nodes(+s: StoryGraph.St, +k: GenGraph.Klei) -> List<&2, TileWorld.Node>:
  nodes_loop(GenGraph.vertices_of(k), s, k, parent_objects(k), 0)

def poly_listed(got: Array<VoronoiPolygon.Poly> & VoronoiPolygon.Poly, +acc: List<&2, VoronoiPolygon.Poly>) -> Array<VoronoiPolygon.Poly> & List<&2, VoronoiPolygon.Poly>:
  (polys, +q) = got
  (polys, q <> acc)

def polys_loop(n: Nat, +i: U32, got: Array<VoronoiPolygon.Poly> & List<&2, VoronoiPolygon.Poly>) -> Array<VoronoiPolygon.Poly> & List<&2, VoronoiPolygon.Poly>:
  match n:
    case 0n:
      got
    case 1n+p:
      (polys, +acc) = got
      polys_loop(p, (i + 1 : U32), poly_listed(Array.get(VoronoiPolygon.Poly, polys, i), acc))

def polys_done(got: Array<VoronoiPolygon.Poly> & List<&2, VoronoiPolygon.Poly>) -> List<&2, VoronoiPolygon.Poly>:
  (_, +acc) = got
  List.reverse(&2, VoronoiPolygon.Poly, acc)

# The BuildVoronoi result of every site, in site order.
def poly_list(polys: Array<VoronoiPolygon.Poly>, +n: U32) -> List<&2, VoronoiPolygon.Poly>:
  polys_done(polys_loop(U32.to_nat(n), 0, (polys, Nil{})))

def dpoint(+p: VoronoiPolygon.D2) -> TileWorld.DPoint:
  match p:
    case VoronoiPolygon.D2{+x, +y}:
      TileWorld.DPoint{x, y}

def dpoints(ps: List<&2, VoronoiPolygon.D2>) -> List<&2, TileWorld.DPoint>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      dpoint(p) <> dpoints(rest)

def maybe_point(has: Bool, +x: F64Repr.F64, +y: F64Repr.F64) -> Maybe<&2, TileWorld.DPoint>:
  match has:
    case True{}:
      Some{TileWorld.DPoint{x, y}}
    case False{}:
      None{}

# DrawVoronoiEdge's points of a half-edge: its two vertices (plus the sampled parabola when curved), or the clipped
# ray when a vertex is missing.
def drawn(complete: Bool, c: VoronoiPolygon.Ctx, +cell1: VoronoiDiagram.Cell, +cell2: VoronoiDiagram.Cell, +h: VoronoiDiagram.Half) -> VoronoiPolygon.Ctx & List<&2, VoronoiPolygon.D2>:
  match complete:
    case True{}:
      match h:
        case VoronoiDiagram.Half{_, _, +x0, +y0, _, +x1, +y1, +f}:
          VoronoiPolygon.curved_if(U32.is_zero((f .&. VoronoiDiagram.linear_bit() : U32)), c, cell1, cell2, VoronoiPolygon.D2{x0, y0}, VoronoiPolygon.D2{x1, y1})
    case False{}:
      VoronoiPolygon.clip_infinite(c, cell1, cell2, h)

type Walk is Type:
  Walk{d: VoronoiDiagram.Diagram, c: VoronoiPolygon.Ctx, edges: List<&2, TileWorld.VEdge>}

def cell_src(+cell: VoronoiDiagram.Cell) -> U32:
  match cell:
    case VoronoiDiagram.Cell{+src, _, _}:
      src

def vedge_of(got: VoronoiPolygon.Ctx & List<&2, VoronoiPolygon.D2>, d: VoronoiDiagram.Diagram, +twin: U32, +h: VoronoiDiagram.Half, +acc: List<&2, TileWorld.VEdge>) -> Walk:
  (c, +pts) = got
  match h:
    case VoronoiDiagram.Half{_, +has0, +x0, +y0, +has1, +x1, +y1, _}:
      Walk{d, c, TileWorld.VEdge{twin, maybe_point(has0, x0, y0), maybe_point(has1, x1, y1), dpoints(pts)} <> acc}

def half_edge(got: VoronoiDiagram.Diagram & VoronoiDiagram.Cell, c: VoronoiPolygon.Ctx, +cell1: VoronoiDiagram.Cell, +h: VoronoiDiagram.Half, +acc: List<&2, TileWorld.VEdge>) -> Walk:
  (d, +cell2) = got
  vedge_of(drawn(VoronoiPolygon.half_complete(h), c, cell1, cell2, h), d, cell_src(cell2), h, acc)

def halves_loop(hs: List<&2, VoronoiDiagram.Half>, w: Walk, +cell1: VoronoiDiagram.Cell) -> Walk:
  match hs:
    case Nil{}:
      w
    case Con{+h, rest}:
      match w:
        case Walk{d, c, +acc}:
          halves_loop(rest, half_edge(VoronoiDiagram.cell_info(d, VoronoiPolygon.half_twin(h)), c, cell1, h, acc), cell1)

type Scan is Type:
  Scan{d: VoronoiDiagram.Diagram, c: VoronoiPolygon.Ctx, cells: List<&2, TileWorld.Cell>}

def walked(w: Walk, +src: U32, +cells: List<&2, TileWorld.Cell>) -> Scan:
  match w:
    case Walk{d, c, +acc}:
      Scan{d, c, TileWorld.Cell{src, List.reverse(&2, TileWorld.VEdge, acc)} <> cells}

def ringed(r: VoronoiDiagram.Ring, c: VoronoiPolygon.Ctx, +cell: VoronoiDiagram.Cell, +cells: List<&2, TileWorld.Cell>) -> Scan:
  match r:
    case VoronoiDiagram.Ring{d, +hs}:
      walked(halves_loop(hs, Walk{d, c, Nil{}}, cell), cell_src(cell), cells)

def cell_if(inside: Bool, got: VoronoiDiagram.Diagram & VoronoiDiagram.Cell, c: VoronoiPolygon.Ctx, +cells: List<&2, TileWorld.Cell>, +k: U32) -> Scan:
  match inside:
    case True{}:
      (d, +cell) = got
      ringed(VoronoiDiagram.cell_ring(d, k), c, cell, cells)
    case False{}:
      (d, _) = got
      Scan{d, c, cells}

def cell_at(got: VoronoiDiagram.Diagram & VoronoiDiagram.Cell, c: VoronoiPolygon.Ctx, +cells: List<&2, TileWorld.Cell>, +k: U32, +n: U32) -> Scan:
  (d, +cell) = got
  cell_if((cell_src(cell) < n : U32), (d, cell), c, cells, k)

def scan_loop(fuel: Nat, sc: Scan, +k: U32, +n: U32) -> Scan:
  match fuel:
    case 0n:
      sc
    case 1n+f:
      match sc:
        case Scan{d, c, +cells}:
          scan_loop(f, cell_at(VoronoiDiagram.cell_info(d, k), c, cells, k, n), (k + 1 : U32), n)

def scanned(got: VoronoiDiagram.Diagram & U32, c: VoronoiPolygon.Ctx, +n: U32) -> Scan:
  (d, +nc) = got
  scan_loop(U32.to_nat(nc), Scan{d, c, Nil{}}, 0, n)

def cells_done(sc: Scan) -> VoronoiDiagram.Diagram & List<&2, TileWorld.Cell>:
  match sc:
    case Scan{d, _, +cells}:
      (d, List.reverse(&2, TileWorld.Cell, cells))

def framed(got: VoronoiPolygon.Ctx & Array<VoronoiPolygon.Poly>, +w: U32, +h: U32) -> VoronoiPolygon.Ctx:
  (c, _) = got
  VoronoiPolygon.with_frame(c, VoronoiPolygon.Frame{F64Repr.from_u32(w), F64Repr.from_u32(h)})

def site_context(+sites: List<&2, VoronoiPolygon.SiteIn>, +w: U32, +h: U32) -> VoronoiPolygon.Ctx:
  +depth = VoronoiPolygon.depth_for(VoronoiPolygon.count_sites(sites, 0))
  framed(VoronoiPolygon.fill_polys(sites, Array.new(VoronoiPolygon.SiteIn, depth, VoronoiPolygon.SiteIn{0, 0, 0, 0, 0}), Array.new(VoronoiPolygon.Poly, depth, VoronoiPolygon.blank_poly(VoronoiPolygon.SiteIn{0, 0, 0, 0, 0})), 0), w, h)

# The point cells of a w x h build of `sites`, in cell order, each with its ring of half-edges.
def cells(d: VoronoiDiagram.Diagram, +sites: List<&2, VoronoiPolygon.SiteIn>, +w: U32, +h: U32) -> VoronoiDiagram.Diagram & List<&2, TileWorld.Cell>:
  cells_done(scanned(VoronoiDiagram.cell_count(d), site_context(sites, w, h), VoronoiPolygon.count_sites(sites, 0)))

def no_cell() -> TileWorld.Cell:
  TileWorld.Cell{TileWorld.none(), Nil{}}

def cell_le(a: TileWorld.Cell, b: TileWorld.Cell) -> Bool:
  match a b:
    case TileWorld.Cell{+s, _} TileWorld.Cell{+t, _}:
      (s <= t : U32)

def starts(+cs: List<&2, TileWorld.Cell>, +i: U32) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Con{TileWorld.Cell{+src, _}, _}:
      U32.is_eq(src, i)

def first_cell(+cs: List<&2, TileWorld.Cell>, go: Bool) -> TileWorld.Cell:
  match cs go:
    case Con{+c, _} True{}:
      c
    case _ _:
      no_cell()

def after(+cs: List<&2, TileWorld.Cell>, go: Bool, +i: U32) -> List<&2, TileWorld.Cell>:
  match cs go:
    case Con{_, +rest} True{}:
      after(rest, starts(rest, i), i)
    case Nil{} _:
      Nil{}
    case Con{+c, +rest} False{}:
      c <> rest

def by_site_loop(n: Nat, +cs: List<&2, TileWorld.Cell>, +i: U32) -> List<&2, TileWorld.Cell>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +go = starts(cs, i)
      first_cell(cs, go) <> by_site_loop(p, after(cs, go, i), (i + 1 : U32))

# Site i's cell for i < n: the first of the cells whose source is i, else no cell.
def by_site(+n: U32, +cs: List<&2, TileWorld.Cell>) -> List<&2, TileWorld.Cell>:
  by_site_loop(U32.to_nat(n), List.sort(~TileWorld.Cell, ~cell_le, cs), 0)

def point_of(+p: VoronoiPolygon.P32) -> TileWorld.Point:
  match p:
    case VoronoiPolygon.P32{+x, +y}:
      TileWorld.Point{F32Ops.from_bits(x), F32Ops.from_bits(y)}

def points_of(ps: List<&2, VoronoiPolygon.P32>) -> List<&2, TileWorld.Point>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      point_of(p) <> points_of(rest)

def site_of(+s: VoronoiPolygon.SiteIn, +p: VoronoiPolygon.Poly, +node: TileWorld.Node) -> TileWorld.Site:
  match s:
    case VoronoiPolygon.SiteIn{+x, +y, _, _, _}:
      match p:
        case VoronoiPolygon.Poly{+pts, +cx, +cy, _, _}:
          TileWorld.Site{node, F32Ops.from_bits(x), F32Ops.from_bits(y), F32Ops.from_bits(cx), F32Ops.from_bits(cy), points_of(pts)}

def sites_loop(ss: List<&2, VoronoiPolygon.SiteIn>, ps: List<&2, VoronoiPolygon.Poly>, ns: List<&2, TileWorld.Node>) -> List<&2, TileWorld.Site>:
  match ss ps ns:
    case Con{+s, rest} Con{+p, prest} Con{+n, nrest}:
      site_of(s, p, n) <> sites_loop(rest, prest, nrest)
    case _ _ _:
      Nil{}

def edge_list(ls: List<&2, GenGraph.Link>) -> List<&2, TileWorld.Edge>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{GenGraph.Link{+s, +t}, rest}:
      TileWorld.Edge{s, t} <> edge_list(rest)

# The World of a w x w ConvertToTileMap build: the centred sites, their polygons, their Klei nodes, the diagram's cells
# and the graph edges left after ApplyPoisonTag.
def world(+w: U32, +sites: List<&2, VoronoiPolygon.SiteIn>, +polys: List<&2, VoronoiPolygon.Poly>, +nodes: List<&2, TileWorld.Node>, +cs: List<&2, TileWorld.Cell>, +links: List<&2, GenGraph.Link>) -> TileWorld.World:
  +n = VoronoiPolygon.count_sites(sites, 0)
  +ts = sites_loop(sites, polys, nodes)
  +fill = {TileWorld.Site{TileWorld.Node{0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 0.0, 0.0, 0.0, 0.0, Nil{}} : TileWorld.Site}
  TileWorld.World{w, w, n, ts, TileTable.from_list(~TileWorld.Site, ts, fill), TileTable.from_list(~List<&2, U32>, GenGraph.adjacency(n, links), Nil{}), edge_list(links), cs,
    TileTable.from_list(~TileWorld.Cell, by_site(n, cs), no_cell())}
