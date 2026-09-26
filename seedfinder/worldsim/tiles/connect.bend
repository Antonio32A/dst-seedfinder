import Base
import ../../f64/repr.bend as F64Repr
import ../grid.bend as Grid
import ./groups.bend as TileGroups
import ./lines.bend as TileLines
import ./separate.bend as TileSeparate
import ./table.bend as TileTable
import ./topology.bend as TileTopology
import ./world.bend as TileWorld

# ForceConnectivity (connectivity.cpp): GenerateLandmasses (a flood over the Voronoi neighbours that records each
# node's connections and numbers the landmasses), MergeConnectedLandmasses, then the connecting lines (thick site
# lines of RoadPoison + ForceConnected edges, site lines of every non-Blank edge, cell lines of room edges) and the
# impassable border.

# What the flood does across one edge of a cell: `connect` pushes the neighbour into the node's connections,
# `follow` floods into it (when not visited yet).
type Link is Data:
  Link{to: U32, connect: Bool, follow: Bool}

def should_connect(+w: TileWorld.World, +i: U32, +j: U32, +e: TileWorld.VEdge, +linked: Bool) -> Bool:
  match e:
    case TileWorld.VEdge{_, +v0, +v1, _}:
      Bool.pick(Bool, (TileSeparate.vertex_distance(v0, v1) < 4.0 : F32), linked,
        (TileSeparate.site_distance(TileWorld.site(w, i), TileWorld.site(w, j)) <= 40.0 : F32) || linked)

def reachable_link(+w: TileWorld.World, +i: U32, +j: U32, +e: TileWorld.VEdge) -> Link:
  +adjacent = TileTopology.adjacent(w, i, j)
  +linked = TileTopology.shares_task(w, i, j)
  Link{j, should_connect(w, i, j, e, linked), linked || adjacent}

def link_if(candidate: Bool, +w: TileWorld.World, +i: U32, +j: U32, +e: TileWorld.VEdge) -> Link:
  match candidate:
    case True{}:
      reachable_link(w, i, j, e)
    case False{}:
      Link{j, False{}, False{}}

def candidate(+w: TileWorld.World, +i: U32, +j: U32) -> Bool:
  +b = TileWorld.node(w, j)
  (j < TileWorld.count(w) : U32) && Bool.not(TileTopology.is_blank_or_random(b))
    && (TileTopology.adjacent(w, i, j) || Bool.not(TileSeparate.is_room(TileTopology.kind_of(b))))

def edge_links(+w: TileWorld.World, +i: U32, edges: List<&2, TileWorld.VEdge>) -> List<&2, Link>:
  match edges:
    case Nil{}:
      Nil{}
    case Con{+e, rest}:
      match e:
        case TileWorld.VEdge{+j, +v0, +v1, +pts}:
          link_if(candidate(w, i, j), w, i, j, TileWorld.VEdge{j, v0, v1, pts}) <> edge_links(w, i, rest)

def cell_links(+w: TileWorld.World, +c: TileWorld.Cell) -> List<&2, Link>:
  match c:
    case TileWorld.Cell{+src, +edges}:
      edge_links(w, src, edges)

def links_by_site(n: Nat, +w: TileWorld.World, +i: U32) -> List<&2, List<&2, Link>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cell_links(w, TileWorld.cell(w, i)) <> links_by_site(p, w, (i + 1 : U32))

# Every site's flood links across its cell's edges, in ring order.
def links(+w: TileWorld.World) -> TileTable.Tree<List<&2, Link>>:
  TileTable.from_list(~List<&2, Link>, links_by_site(U32.to_nat(TileWorld.count(w)), w, 0), Nil{})

type Frame is Data:
  Frame{site: U32, links: List<&2, Link>}

type Flood is Type:
  Flood{visited: Array<U32>, conns: List<&2, TileWorld.Edge>, members: List<&2, U32>}

def push_conn(connect: Bool, +i: U32, +j: U32, conns: List<&2, TileWorld.Edge>) -> List<&2, TileWorld.Edge>:
  match connect:
    case True{}:
      TileWorld.Edge{i, j} <> conns
    case False{}:
      conns

def enter(seen: Bool, +j: U32, +table: TileTable.Tree<List<&2, Link>>, +stack: List<&2, Frame>, visited: Array<U32>, +conns: List<&2, TileWorld.Edge>, +members: List<&2, U32>) -> Flood & List<&2, Frame>:
  match seen:
    case True{}:
      (Flood{visited, conns, members}, stack)
    case False{}:
      visited[j] <- 1
      (Flood{visited, conns, j <> members}, Frame{j, TileTable.at(~List<&2, Link>, table, j)} <> stack)

def enter_got(got: Array<U32> & U32, +j: U32, +table: TileTable.Tree<List<&2, Link>>, +stack: List<&2, Frame>, +conns: List<&2, TileWorld.Edge>, +members: List<&2, U32>) -> Flood & List<&2, Frame>:
  (visited, +v) = got
  enter(U32.is_ne(v, 0), j, table, stack, visited, conns, members)

def follow(go: Bool, +j: U32, +table: TileTable.Tree<List<&2, Link>>, +stack: List<&2, Frame>, visited: Array<U32>, +conns: List<&2, TileWorld.Edge>, +members: List<&2, U32>) -> Flood & List<&2, Frame>:
  match go:
    case True{}:
      enter_got(visited[j], j, table, stack, conns, members)
    case False{}:
      (Flood{visited, conns, members}, stack)

def step(+i: U32, l: Link, +more: List<&2, Link>, +rest: List<&2, Frame>, +table: TileTable.Tree<List<&2, Link>>, f: Flood) -> Flood & List<&2, Frame>:
  match l:
    case Link{+j, +connect, +go}:
      match f:
        case Flood{visited, conns, +members}:
          follow(connect && go, j, table, Frame{i, more} <> rest, visited, push_conn(connect, i, j, conns), members)

def flood_loop(n: Nat, got: Flood & List<&2, Frame>, +table: TileTable.Tree<List<&2, Link>>) -> Flood:
  match n:
    case 0n:
      (f, _) = got
      f
    case 1n+p:
      (f, stack) = got
      match stack:
        case Nil{}:
          f
        case Con{Frame{+i, +ls}, rest}:
          match ls:
            case Nil{}:
              flood_loop(p, (f, rest), table)
            case Con{+l, more}:
              flood_loop(p, step(i, l, more, rest, table, f), table)

def initially_visited(+n: TileWorld.Node) -> Bool:
  match n:
    case TileWorld.Node{_, _, _, _, _, +parent, _, +parent_kind, _, _}:
      TileTopology.is_blank_or_random(n) || (Bool.not(TileWorld.is_none(parent)) && U32.is_eq(parent_kind, 1))

def mark_cells(cells: List<&2, TileWorld.Cell>, +w: TileWorld.World, visited: Array<U32>) -> Array<U32>:
  match cells:
    case Nil{}:
      visited
    case Con{TileWorld.Cell{+src, _}, rest}:
      mark_cells(rest, w, visited[src] <- Bool.to_u32(initially_visited(TileWorld.node(w, src))))

def root_keep(seen: Bool, +src: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match seen:
    case True{}:
      tail
    case False{}:
      src <> tail

def root_list(cells: List<&2, TileWorld.Cell>, +w: TileWorld.World) -> List<&2, U32>:
  match cells:
    case Nil{}:
      Nil{}
    case Con{TileWorld.Cell{+src, _}, rest}:
      root_keep(initially_visited(TileWorld.node(w, src)), src, root_list(rest, w))

# The landmasses: `labels[site]` is the landmass number (1, 2, ... in creation order; 0 for none), `conns` every
# node connection (source site, target site) in push order.
type Landmasses is Type:
  Landmasses{labels: Array<U32>, conns: List<&2, TileWorld.Edge>, count: U32}

def label_members(members: List<&2, U32>, labels: Array<U32>, +k: U32) -> Array<U32>:
  match members:
    case Nil{}:
      labels
    case Con{+m, rest}:
      label_members(rest, labels[m] <- k, k)

type Sweep is Type:
  Sweep{visited: Array<U32>, conns: List<&2, TileWorld.Edge>, labels: Array<U32>, k: U32}

def after_flood(f: Flood, labels: Array<U32>, +k: U32) -> Sweep:
  match f:
    case Flood{visited, conns, +members}:
      +next = Bool.pick(U32, List.is_empty(&2, U32, members), k, (k + 1 : U32))
      Sweep{visited, conns, label_members(members, labels, next), next}

def root_flood(got: Array<U32> & U32, +root: U32, +table: TileTable.Tree<List<&2, Link>>, +conns: List<&2, TileWorld.Edge>) -> Flood:
  (visited, +v) = got
  flood_loop(U32.to_nat(4000000), enter(U32.is_ne(v, 0), root, table, Nil{}, visited, conns, Nil{}), table)

def roots_loop(roots: List<&2, U32>, sw: Sweep, +table: TileTable.Tree<List<&2, Link>>) -> Sweep:
  match roots:
    case Nil{}:
      sw
    case Con{+root, rest}:
      match sw:
        case Sweep{visited, conns, labels, +k}:
          roots_loop(rest, after_flood(root_flood(visited[root], root, table, conns), labels, k), table)

def cells_of(+w: TileWorld.World) -> List<&2, TileWorld.Cell>:
  match w:
    case TileWorld.World{_, _, _, _, _, _, _, +cells, _}:
      cells

def sites_depth(+w: TileWorld.World) -> Nat:
  Grid.depth_for(24n, TileWorld.count(w), 0n, 1)

def landmasses_of(sw: Sweep) -> Landmasses:
  match sw:
    case Sweep{_, conns, labels, +k}:
      Landmasses{labels, List.reverse(&2, TileWorld.Edge, conns), k}

# GenerateLandmasses.
def generate(+w: TileWorld.World) -> Landmasses:
  +d = sites_depth(w)
  landmasses_of(roots_loop(root_list(cells_of(w), w), Sweep{mark_cells(cells_of(w), w, Grid.alloc(d, 0)), Nil{}, Grid.alloc(d, 0), 0}, links(w)))

def edges_of(+w: TileWorld.World) -> List<&2, TileWorld.Edge>:
  match w:
    case TileWorld.World{_, _, _, _, _, _, +edges, _, _}:
      edges

def labels_got2(got: Array<U32> & U32, +la: U32, +b: U32) -> Array<U32> & TileWorld.Edge:
  (labels, +lb) = got
  (labels, TileWorld.Edge{la, lb})

def labels_got(got: Array<U32> & U32, +b: U32) -> Array<U32> & TileWorld.Edge:
  (labels, +la) = got
  labels_got2(labels[b], la, b)

# (labels[a], labels[b]).
def labels_of(labels: Array<U32>, +a: U32, +b: U32) -> Array<U32> & TileWorld.Edge:
  labels_got(labels[a], b)

def non_blank(+w: TileWorld.World, +e: TileWorld.Edge) -> Bool:
  match e:
    case TileWorld.Edge{+a, +b}:
      Bool.not(U32.is_eq(TileTopology.kind_of(TileWorld.node(w, a)), 1)) && Bool.not(U32.is_eq(TileTopology.kind_of(TileWorld.node(w, b)), 1))

def forced(+w: TileWorld.World, +e: TileWorld.Edge) -> Bool:
  match e:
    case TileWorld.Edge{+a, +b}:
      U32.is_ne(((TileTopology.flags_of(TileWorld.node(w, a)) .|. TileTopology.flags_of(TileWorld.node(w, b))) .&. 2 : U32), 0)

def edge_keep(hit: Bool, +e: TileWorld.Edge, tail: List<&2, TileWorld.Edge>) -> List<&2, TileWorld.Edge>:
  match hit:
    case True{}:
      e <> tail
    case False{}:
      tail

def same_label(+pair: TileWorld.Edge) -> Bool:
  match pair:
    case TileWorld.Edge{+la, +lb}:
      U32.is_eq(la, lb)

def pending_keep(pending: Maybe<&2, TileWorld.Edge>, +w: TileWorld.World, +all: Bool, +pair: TileWorld.Edge, acc: List<&2, TileWorld.Edge>) -> List<&2, TileWorld.Edge>:
  match pending:
    case None{}:
      acc
    case Some{+e}:
      edge_keep(non_blank(w, e) && (all || same_label(pair) || forced(w, e)), e, acc)

def graph_edges_loop(edges: List<&2, TileWorld.Edge>, got: Array<U32> & TileWorld.Edge, +pending: Maybe<&2, TileWorld.Edge>, +w: TileWorld.World, +all: Bool, acc: List<&2, TileWorld.Edge>) -> Array<U32> & List<&2, TileWorld.Edge>:
  match edges:
    case Nil{}:
      (labels, +pair) = got
      (labels, List.reverse(&2, TileWorld.Edge, pending_keep(pending, w, all, pair, acc)))
    case Con{TileWorld.Edge{+a, +b}, rest}:
      (labels, +pair) = got
      graph_edges_loop(rest, labels_of(labels, a, b), Some{TileWorld.Edge{a, b}}, w, all, pending_keep(pending, w, all, pair, acc))

# NonBlankGraphEdges(map, all_landmasses): graph edges without a Blank end; unless `all`, only those within one
# landmass or with a ForceConnected end.
def graph_edges(labels: Array<U32>, +w: TileWorld.World, +all: Bool) -> Array<U32> & List<&2, TileWorld.Edge>:
  graph_edges_loop(edges_of(w), (labels, TileWorld.Edge{0, 0}), None{}, w, all, Nil{})

def relabel_loop(n: Nat, got: Array<U32> & U32, +i: U32, +from: U32, +to: U32) -> Array<U32>:
  match n:
    case 0n:
      (labels, _) = got
      labels
    case 1n+p:
      (labels, +v) = got
      labels[i] <- Bool.pick(U32, U32.is_eq(v, from), to, v)
      relabel_loop(p, labels[(i + 1 : U32)], (i + 1 : U32), from, to)

def merge_apply(go: Bool, labels: Array<U32>, +keep: U32, +absorbed: U32, +count: U32) -> Array<U32>:
  match go:
    case False{}:
      labels
    case True{}:
      relabel_loop(U32.to_nat(count), labels[0], 0, absorbed, keep)

def merge_pair(pending: Bool, labels: Array<U32>, +pair: TileWorld.Edge, +count: U32) -> Array<U32>:
  match pending:
    case False{}:
      labels
    case True{}:
      match pair:
        case TileWorld.Edge{+keep, +absorbed}:
          merge_apply(U32.is_ne(keep, 0) && U32.is_ne(absorbed, 0) && U32.is_ne(keep, absorbed), labels, keep, absorbed, count)

def merge_loop(edges: List<&2, TileWorld.Edge>, got: Array<U32> & TileWorld.Edge, +pending: Bool, +count: U32) -> Array<U32>:
  match edges:
    case Nil{}:
      (labels, +pair) = got
      merge_pair(pending, labels, pair, count)
    case Con{TileWorld.Edge{+a, +b}, rest}:
      (labels, +pair) = got
      merge_loop(rest, labels_of(merge_pair(pending, labels, pair, count), a, b), True{}, count)

def merge_edges(got: Array<U32> & List<&2, TileWorld.Edge>, +count: U32) -> Array<U32>:
  (labels, +edges) = got
  merge_loop(edges, (labels, TileWorld.Edge{0, 0}), False{}, count)

# MergeConnectedLandmasses(join_islands): each kept edge (chosen with the labels before any merge) folds the second
# end's landmass into the first's. Merged landmasses keep every member, so a relabel is exact.
def merge(+w: TileWorld.World, lm: Landmasses, +join: Bool) -> Landmasses:
  match lm:
    case Landmasses{labels, +conns, +k}:
      Landmasses{merge_edges(graph_edges(labels, w, join), TileWorld.count(w)), conns, k}

def non_blank_loop(edges: List<&2, TileWorld.Edge>, +w: TileWorld.World) -> List<&2, TileWorld.Edge>:
  match edges:
    case Nil{}:
      Nil{}
    case Con{+e, rest}:
      edge_keep(non_blank(w, e), e, non_blank_loop(rest, w))

# NonBlankGraphEdges(map, true).
def non_blank_edges(+w: TileWorld.World) -> List<&2, TileWorld.Edge>:
  non_blank_loop(edges_of(w), w)

def touching_loop(edges: List<&2, TileWorld.Edge>, +w: TileWorld.World, +kind: U32) -> List<&2, TileWorld.Edge>:
  match edges:
    case Nil{}:
      Nil{}
    case Con{TileWorld.Edge{+a, +b}, rest}:
      edge_keep(U32.is_eq(TileTopology.kind_of(TileWorld.node(w, a)), kind) || U32.is_eq(TileTopology.kind_of(TileWorld.node(w, b)), kind), TileWorld.Edge{a, b},
        touching_loop(rest, w, kind))

def position(s: TileWorld.Site) -> TileWorld.Point:
  match s:
    case TileWorld.Site{_, +x, +y, _, _, _}:
      TileWorld.Point{x, y}

def centroid(s: TileWorld.Site) -> TileWorld.Point:
  match s:
    case TileWorld.Site{_, _, _, +cx, +cy, _}:
      TileWorld.Point{cx, cy}

def itype_of(+n: TileWorld.Node) -> U32:
  match n:
    case TileWorld.Node{_, _, +itype, _, _, _, _, _, _, _}:
      itype

def site_point(+w: TileWorld.World, +i: U32) -> TileWorld.Point:
  position(TileWorld.site(w, i))

# The first point of CellLinePoints(a, ...): the site (EdgeSite), nothing (EdgeEdgeDirect, the EdgeEdge sides,
# EdgeData), else the centroid.
def line_start(+s: TileWorld.Site) -> List<&2, TileWorld.Point>:
  +it = itype_of(TileWorld.node_of(s))
  Bool.pick(List<&2, TileWorld.Point>, U32.is_eq(it, 1), [position(s)],
    Bool.pick(List<&2, TileWorld.Point>, (it >= 2 : U32) && (it <= 5 : U32), Nil{}, [centroid(s)]))

def anchor(+s: TileWorld.Site) -> TileWorld.Point:
  Bool.pick(TileWorld.Point, U32.is_eq(itype_of(TileWorld.node_of(s)), 1), position(s), centroid(s))

def midpoint(+last: TileWorld.Point, +to: TileWorld.Point) -> TileWorld.Point:
  match last:
    case TileWorld.Point{+lx, +ly}:
      match to:
        case TileWorld.Point{+tx, +ty}:
          TileWorld.Point{((tx + lx) * 0.5 : F32), ((ty + ly) * 0.5 : F32)}

def with_midpoint(start: List<&2, TileWorld.Point>, +to: TileWorld.Point) -> List<&2, TileWorld.Point>:
  match start:
    case Nil{}:
      Nil{}
    case Con{+p, _}:
      [p, midpoint(p, to)]

def line_end(linked: Bool, +start: List<&2, TileWorld.Point>, +to: TileWorld.Point) -> List<&2, TileWorld.Point>:
  match linked:
    case True{}:
      with_midpoint(start, to)
    case False{}:
      start

# CellLinePoints(a, b) (0x7ecad0): a's start point, then the midpoint towards b's anchor when a connects to b.
def cell_line_points(+w: TileWorld.World, +conns: TileTable.Tree<List<&2, U32>>, +a: U32, +b: U32) -> List<&2, TileWorld.Point>:
  line_end(TileTopology.contains(TileTable.at(~List<&2, U32>, conns, a), b), line_start(TileWorld.site(w, a)), anchor(TileWorld.site(w, b)))

def site_pen(+tile: U32) -> TileLines.Pen:
  TileLines.Pen{tile, False{}, True{}}

def px(+p: TileWorld.Point) -> F32:
  match p:
    case TileWorld.Point{+x, _}:
      x

def py(+p: TileWorld.Point) -> F32:
  match p:
    case TileWorld.Point{_, +y}:
      y

def thick_line(g: Grid.Grid, +pen: TileLines.Pen, +p: TileWorld.Point, +q: TileWorld.Point) -> Grid.Grid:
  g1 = TileLines.draw(g, pen, px(p), py(p), px(q), py(q))
  g2 = TileLines.draw(g1, pen, (px(p) + 1.0 : F32), py(p), (px(q) + 1.0 : F32), py(q))
  g3 = TileLines.draw(g2, pen, (px(p) - 1.0 : F32), py(p), (px(q) - 1.0 : F32), py(q))
  g4 = TileLines.draw(g3, pen, px(p), (py(p) + 1.0 : F32), px(q), (py(q) + 1.0 : F32))
  TileLines.draw(g4, pen, px(p), (py(p) - 1.0 : F32), px(q), (py(q) - 1.0 : F32))

def site_line(g: Grid.Grid, +pen: TileLines.Pen, +p: TileWorld.Point, +q: TileWorld.Point) -> Grid.Grid:
  g1 = TileLines.draw(g, pen, px(p), py(p), px(q), py(q))
  g2 = TileLines.draw(g1, pen, (px(p) + 1.0 : F32), py(p), (px(q) + 1.0 : F32), py(q))
  TileLines.draw(g2, pen, px(p), (py(p) + 1.0 : F32), px(q), (py(q) + 1.0 : F32))

def cell_segment(g: Grid.Grid, +pen: TileLines.Pen, +p: TileWorld.Point, +q: TileWorld.Point) -> Grid.Grid:
  g1 = TileLines.draw(g, pen, px(p), py(p), px(q), py(q))
  g2 = TileLines.draw(g1, pen, (px(p) + 1.0 : F32), (py(p) + 0.0 : F32), (px(q) + 1.0 : F32), (py(q) + 0.0 : F32))
  TileLines.draw(g2, pen, (px(p) + 0.0 : F32), (py(p) + 1.0 : F32), (px(q) + 0.0 : F32), (py(q) + 1.0 : F32))

def cell_segments(pts: List<&2, TileWorld.Point>, g: Grid.Grid, +pen: TileLines.Pen) -> Grid.Grid:
  match pts:
    case Nil{}:
      g
    case Con{+p, rest}:
      match rest:
        case Nil{}:
          g
        case Con{+q, _}:
          cell_segments(rest, cell_segment(g, pen, p, q), pen)

def thick_if(go: Bool, g: Grid.Grid, +pen: TileLines.Pen, +p: TileWorld.Point, +q: TileWorld.Point) -> Grid.Grid:
  match go:
    case True{}:
      thick_line(g, pen, p, q)
    case False{}:
      g

def plain_if(go: Bool, g: Grid.Grid, +pen: TileLines.Pen, +p: TileWorld.Point, +q: TileWorld.Point) -> Grid.Grid:
  match go:
    case True{}:
      site_line(g, pen, p, q)
    case False{}:
      g

def edge_lines(+w: TileWorld.World, g: Grid.Grid, +a: U32, +b: U32) -> Grid.Grid:
  +na = TileWorld.node(w, a)
  +nb = TileWorld.node(w, b)
  +flags = (TileTopology.flags_of(na) .|. TileTopology.flags_of(nb) : U32)
  +pen = site_pen(TileGroups.validate_ground(TileTopology.tile_of(na)))
  +p = site_point(w, a)
  +q = site_point(w, b)
  +thick = U32.is_ne((flags .&. 4 : U32), 0) && U32.is_ne((flags .&. 2 : U32), 0) && U32.is_ne(TileTopology.kind_of(na), 7)
    && U32.is_ne(TileTopology.kind_of(nb), 7)
  plain_if(U32.is_ne(TileTopology.kind_of(na), 1) && U32.is_ne(TileTopology.kind_of(na), 7), thick_if(thick, g, pen, p, q), pen, p, q)

def site_lines(edges: List<&2, TileWorld.Edge>, g: Grid.Grid, +w: TileWorld.World) -> Grid.Grid:
  match edges:
    case Nil{}:
      g
    case Con{TileWorld.Edge{+a, +b}, rest}:
      site_lines(rest, edge_lines(w, g, a, b), w)

def room_lines(edges: List<&2, TileWorld.Edge>, g: Grid.Grid, +w: TileWorld.World, +conns: TileTable.Tree<List<&2, U32>>) -> Grid.Grid:
  match edges:
    case Nil{}:
      g
    case Con{TileWorld.Edge{+a, +b}, rest}:
      +pen = site_pen(TileGroups.validate_ground(TileTopology.tile_of(TileWorld.node(w, a))))
      room_lines(rest, cell_segments(cell_line_points(w, conns, b, a), cell_segments(cell_line_points(w, conns, a, b), g, pen), pen), w, conns)

def border_cell(got: Grid.Grid & U32, +i: U32) -> Grid.Grid:
  (g, +old) = got
  Grid.put(g, i, Grid.cell(TileGroups.impassable(), Grid.flags_of(old)))

def border_at(g: Grid.Grid, +i: U32) -> Grid.Grid:
  border_cell(Grid.get(g, i), i)

def border_row(n: Nat, g: Grid.Grid, +i: U32) -> Grid.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      border_row(p, border_at(g, i), (i + 1 : U32))

def border_sides(n: Nat, g: Grid.Grid, +y: U32, +w: U32) -> Grid.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      border_sides(p, border_at(border_at(g, (y * w : U32)), (y * w + w - 1 : U32)), (y + 1 : U32), w)

def border_grid(g: Grid.Grid) -> Grid.Grid:
  match g:
    case Grid.Grid{cells, +w, +h}:
      sides = border_sides(U32.to_nat(h), Grid.Grid{cells, w, h}, 0, w)
      border_row(U32.to_nat(w), border_row(U32.to_nat(w), sides, 0), ((h - 1) * w : U32))

def conn_keep(hit: Bool, +t: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      t <> tail
    case False{}:
      tail

# The connections of site i (target sites in push order).
def conns_of(+i: U32, conns: List<&2, TileWorld.Edge>) -> List<&2, U32>:
  match conns:
    case Nil{}:
      Nil{}
    case Con{TileWorld.Edge{+s, +t}, rest}:
      conn_keep(U32.is_eq(s, i), t, conns_of(i, rest))

def bumped(got: Array<U32> & U32, +s: U32) -> Array<U32>:
  (counts, +v) = got
  counts[s] <- (v + 1 : U32)

def count_step(site: Bool, counts: Array<U32>, +s: U32) -> Array<U32>:
  match site:
    case True{}:
      bumped(counts[s], s)
    case False{}:
      counts

def count_loop(conns: List<&2, TileWorld.Edge>, counts: Array<U32>, +n: U32) -> Array<U32>:
  match conns:
    case Nil{}:
      counts
    case Con{TileWorld.Edge{+s, _}, rest}:
      count_loop(rest, count_step((s < n : U32), counts, s), n)

def starts_step(got: Array<U32> & U32, +i: U32, +acc: U32) -> Array<U32> & U32:
  (arr, +v) = got
  arr2 = arr[i] <- acc
  (arr2, (acc + v : U32))

def starts_loop(n: Nat, got: Array<U32> & U32, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      (arr, _) = got
      arr
    case 1n+p:
      (arr, +acc) = got
      starts_loop(p, starts_step(arr[i], i, acc), (i + 1 : U32))

type Buckets is Type:
  Buckets{starts: Array<U32>, flat: Array<U32>}

def placed(got: Array<U32> & U32, flat: Array<U32>, +s: U32, +t: U32) -> Buckets:
  (starts, +pos) = got
  starts2 = starts[s] <- (pos + 1 : U32)
  Buckets{starts2, flat[pos] <- t}

def place_step(site: Bool, b: Buckets, +s: U32, +t: U32) -> Buckets:
  match site:
    case True{}:
      match b:
        case Buckets{starts, flat}:
          placed(starts[s], flat, s, t)
    case False{}:
      b

def place_loop(conns: List<&2, TileWorld.Edge>, b: Buckets, +n: U32) -> Buckets:
  match conns:
    case Nil{}:
      b
    case Con{TileWorld.Edge{+s, +t}, rest}:
      place_loop(rest, place_step((s < n : U32), b, s, t), n)

def range_loop(n: Nat, got: Array<U32> & U32, +k: U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      (flat, _) = got
      (flat, acc)
    case 1n+p:
      (flat, +v) = got
      range_loop(p, flat[(k - 1 : U32)], (k - 1 : U32), v <> acc)

def site_range(flat: Array<U32>, +begin: U32, +end: U32) -> Array<U32> & List<&2, U32>:
  range_loop(U32.to_nat((end - begin : U32)), flat[(end - 1 : U32)], (end - 1 : U32), Nil{})

# The bucket walk: the arrays, where the next site's range begins, the last site's targets.
type Gather is Type:
  Gather{flat: Array<U32>, ends: Array<U32>, begin: U32, xs: List<&2, U32>}

def gathered(got: Array<U32> & List<&2, U32>, ends: Array<U32>, +end: U32) -> Gather:
  (flat, +xs) = got
  Gather{flat, ends, end, xs}

def gather_end(got: Array<U32> & U32, flat: Array<U32>, +begin: U32) -> Gather:
  (ends, +end) = got
  gathered(site_range(flat, begin, end), ends, end)

def lists_loop(n: Nat, g: Gather, +i: U32, +started: Bool, +acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      match g:
        case Gather{_, _, _, +xs}:
          List.reverse(&2, List<&2, U32>, Bool.pick(List<&2, List<&2, U32>>, started, xs <> acc, acc))
    case 1n+p:
      match g:
        case Gather{flat, ends, +begin, +xs}:
          lists_loop(p, gather_end(ends[i], flat, begin), (i + 1 : U32), True{}, Bool.pick(List<&2, List<&2, U32>>, started, xs <> acc, acc))

def bucket_lists(b: Buckets, +n: U32) -> List<&2, List<&2, U32>>:
  match b:
    case Buckets{ends, flat}:
      lists_loop(U32.to_nat(n), Gather{flat, ends, 0, Nil{}}, 0, False{}, Nil{})

# Each site's connections (target sites in push order): a counting sort of the connections by source.
def connections(+w: TileWorld.World, +conns: List<&2, TileWorld.Edge>) -> TileTable.Tree<List<&2, U32>>:
  +n = TileWorld.count(w)
  +depth = sites_depth(w)
  counts = count_loop(conns, Grid.alloc(depth, 0), n)
  starts = starts_loop(U32.to_nat(n), (counts, 0), 0)
  +flat_depth = Grid.depth_for(24n, U32.from_nat(List.length(&2, TileWorld.Edge, conns)), 0n, 1)
  TileTable.from_list(~List<&2, U32>, bucket_lists(place_loop(conns, Buckets{starts, Grid.alloc(flat_depth, 0)}, n), n), Nil{})

def labels_loop(n: Nat, got: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      (labels, _) = got
      (labels, List.reverse(&2, U32, acc))
    case 1n+p:
      (labels, +v) = got
      labels_loop(p, labels[(i + 1 : U32)], (i + 1 : U32), v <> acc)

# The landmass numbers of sites 0 .. count - 1.
def label_list(labels: Array<U32>, +count: U32) -> List<&2, U32>:
  Pair.snd(Array<U32>, List<&2, U32>, labels_loop(U32.to_nat(count), labels[0], 0, Nil{}))

# The landmass of every site and every node's connections after ForceConnectivity's GenerateLandmasses and
# MergeConnectedLandmasses.
type Islands is Data:
  Islands{labels: List<&2, U32>, conns: List<&2, TileWorld.Edge>}

def islands_of(lm: Landmasses, +w: TileWorld.World) -> Islands:
  match lm:
    case Landmasses{labels, +conns, _}:
      Islands{label_list(labels, TileWorld.count(w)), conns}

def islands(+w: TileWorld.World, +join: Bool) -> Islands:
  islands_of(merge(w, generate(w), join), w)

def conns_list(+i: Islands) -> List<&2, TileWorld.Edge>:
  match i:
    case Islands{_, +conns}:
      conns

# ForceConnectivity(join_islands, false, ROCKY) after SeparateIslands, given the landmasses.
def force(+w: TileWorld.World, +isl: Islands, g: Grid.Grid) -> Grid.Grid:
  +conns = connections(w, conns_list(isl))
  lines = site_lines(non_blank_edges(w), g, w)
  rooms5 = room_lines(touching_loop(edges_of(w), w, 5), lines, w, conns)
  border_grid(room_lines(touching_loop(edges_of(w), w, 6), rooms5, w, conns))
