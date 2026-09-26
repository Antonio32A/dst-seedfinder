import Base
import ../../f32/ops.bend as F32Ops
import ../../f64/repr.bend as F64Repr
import ../../f64/arith.bend as F64Arith
import ../../data/constants.bend as Constants
import ../../data/tile_groups.bend as TileGroupsData
import ./groups.bend as TileGroups
import ./sitetiles.bend as SiteTiles
import ../../stl/heap.bend as Heap
import ../../stl/sort.bend as StlSort
import ../grid.bend as Grid
import ./connect.bend as TileConnect
import ./table.bend as TileTable
import ./topology.bend as TileTopology
import ./world.bend as TileWorld

# GetRoads (roads.cpp): the PigKingdom -> PigVillage road (hop-count A* over the graph, the open list sorted with the
# platform's std::sort every step it changed), then the remaining graph edges chained into polylines.

type Pigs is Data:
  Pigs{kingdom: U32, village: U32, has_kingdom: Bool, has_village: Bool}

def pig_of(+n: TileWorld.Node) -> U32:
  match n:
    case TileWorld.Node{_, _, _, _, _, _, _, _, _, +pig}:
      pig

def pigs_seen(+p: Pigs, +v: U32, +pig: U32) -> Pigs:
  match p:
    case Pigs{+kingdom, +village, +hk, +hv}:
      +is_k = U32.is_eq(pig, 1)
      +is_v = U32.is_eq(pig, 2)
      Pigs{Bool.pick(U32, is_k, v, kingdom), Bool.pick(U32, is_v, v, village), hk || is_k, hv || is_v}

def both(+p: Pigs) -> Bool:
  match p:
    case Pigs{_, _, +hk, +hv}:
      hk && hv

def pigs_loop(n: Nat, stop: Bool, +w: TileWorld.World, +v: U32, +p: Pigs) -> Pigs:
  match n:
    case 0n:
      p
    case 1n+q:
      match stop:
        case True{}:
          p
        case False{}:
          +seen = pigs_seen(p, v, pig_of(TileWorld.node(w, v)))
          pigs_loop(q, ((v + 1 : U32) < TileWorld.count(w) : U32) && both(seen), w, (v + 1 : U32), seen)

# FindPigVertices: the last PigKingdom and PigVillage vertices up to the first vertex where both are known.
def find_pigs(+w: TileWorld.World) -> Pigs:
  pigs_loop(U32.to_nat(TileWorld.count(w)), False{}, w, 0, Pigs{0, 0, False{}, False{}})

type Bfs is Type:
  Bfs{dist: Array<U32>, queue: Array<U32>, head: U32, tail: U32, go: Bool}

def bfs(dist: Array<U32>, queue: Array<U32>, +head: U32, +tail: U32) -> Bfs:
  Bfs{dist, queue, head, tail, (head < tail : U32)}

def visit_new(fresh: Bool, dist: Array<U32>, queue: Array<U32>, +t: U32, +d: U32, +head: U32, +tail: U32) -> Bfs:
  match fresh:
    case True{}:
      dist[t] <- d
      queue[tail] <- t
      bfs(dist, queue, head, (tail + 1 : U32))
    case False{}:
      bfs(dist, queue, head, tail)

def visit_got(got: Array<U32> & U32, queue: Array<U32>, +t: U32, +d: U32, +head: U32, +tail: U32) -> Bfs:
  (dist, +old) = got
  visit_new(TileWorld.is_none(old), dist, queue, t, d, head, tail)

def visit_all(ts: List<&2, U32>, b: Bfs, +d: U32) -> Bfs:
  match ts:
    case Nil{}:
      b
    case Con{+t, rest}:
      match b:
        case Bfs{dist, queue, +head, +tail, _}:
          visit_all(rest, visit_got(dist[t], queue, t, d, head, tail), d)

def expand_got(got: Array<U32> & U32, queue: Array<U32>, +w: TileWorld.World, +v: U32, +head: U32, +tail: U32) -> Bfs:
  (dist, +dv) = got
  visit_all(TileTopology.neighbours(w, v), bfs(dist, queue, head, tail), (dv + 1 : U32))

def dequeued(got: Array<U32> & U32, dist: Array<U32>, +w: TileWorld.World, +head: U32, +tail: U32) -> Bfs:
  (queue, +v) = got
  expand_got(dist[v], queue, w, v, (head + 1 : U32), tail)

def bfs_loop(n: Nat, b: Bfs, +w: TileWorld.World) -> Bfs:
  match n:
    case 0n:
      b
    case 1n+p:
      match b:
        case Bfs{dist, queue, +head, +tail, +go}:
          match go:
            case False{}:
              Bfs{dist, queue, head, tail, go}
            case True{}:
              bfs_loop(p, dequeued(queue[head], dist, w, head, tail), w)

def none_array(+d: Nat) -> Array<U32>:
  Grid.alloc(d, TileWorld.none())

def distances(b: Bfs, +count: U32) -> List<&2, U32>:
  match b:
    case Bfs{dist, _, _, _, _}:
      TileConnect.label_list(dist, count)

# HopDistancesTo(goal): BFS hop counts to the goal (NONE when unreachable).
def hops_to(+w: TileWorld.World, +goal: U32) -> List<&2, U32>:
  +d = TileConnect.sites_depth(w)
  dist = none_array(d)
  queue = Grid.alloc(d, 0)
  distances(bfs_loop(U32.to_nat((TileWorld.count(w) + 2 : U32)), bfs(dist[goal] <- 0, queue[0] <- goal, 0, 1), w), TileWorld.count(w))

# A* state: nodes (vertex, parent node, g bits, h bits per node), the open list of node handles, and per vertex
# (closed flag, open node or NONE); a vertex enters the open list at most once, so it has at most one open node.
type Star is Type:
  Star{nodes: Array<U32>, open: Array<U32>, marks: Array<U32>, n_open: U32, n_nodes: U32, resort: Bool}

def inf_bits() -> U32:
  2139095040

def h_bits(+hops: TileTable.Tree<U32>, +v: U32) -> U32:
  +d = TileTable.at(~U32, hops, v)
  Bool.pick(U32, TileWorld.is_none(d), inf_bits(), F32Ops.bits(U32.to_f32(d)))

def cost(+g: U32, +h: U32) -> F32:
  (F32Ops.from_bits(g) + F32Ops.from_bits(h) : F32)

def less_hb(got: Array<U32> & U32, +ga: U32, +ha: U32, +gb: U32) -> Array<U32> & Bool:
  (nodes, +hb) = got
  (nodes, (cost(gb, hb) < cost(ga, ha) : F32))

def less_gb(got: Array<U32> & U32, +ga: U32, +ha: U32, +b: U32) -> Array<U32> & Bool:
  (nodes, +gb) = got
  less_hb(nodes[(b * 4 + 3 : U32)], ga, ha, gb)

def less_ha(got: Array<U32> & U32, +ga: U32, +b: U32) -> Array<U32> & Bool:
  (nodes, +ha) = got
  less_gb(nodes[(b * 4 + 2 : U32)], ga, ha, b)

def less_ga(got: Array<U32> & U32, +a: U32, +b: U32) -> Array<U32> & Bool:
  (nodes, +ga) = got
  less_ha(nodes[(a * 4 + 3 : U32)], ga, b)

def cost_less(nodes: Array<U32>, +a: U32, +b: U32) -> Array<U32> & Bool:
  less_ga(nodes[(a * 4 + 2 : U32)], a, b)

# by_cost_descending(a, b): cost(b) < cost(a), so the cheapest node ends up last.
def by_cost_descending(nodes: Array<U32>, a: U32, b: U32) -> Array<U32> & Bool:
  cost_less(nodes, a, b)

def sorted(work: Heap.Work<Array<U32>>, marks: Array<U32>, +n_open: U32, +n_nodes: U32) -> Star:
  match work:
    case Heap.Work{nodes, open}:
      Star{nodes, open, marks, n_open, n_nodes, False{}}

def sort_open(go: Bool, +windows: Bool, s: Star) -> Star:
  match go:
    case True{}:
      match s:
        case Star{nodes, open, marks, +n_open, +n_nodes, _}:
          sorted(StlSort.sort_for(~Array<U32>, ~by_cost_descending, windows, nodes, open, 0, n_open), marks, n_open, n_nodes)
    case False{}:
      s

def put_node(nodes: Array<U32>, +k: U32, +v: U32, +parent: U32, +g: U32, +h: U32) -> Array<U32>:
  nodes[(k * 4 : U32)] <- v
  nodes[(k * 4 + 1 : U32)] <- parent
  nodes[(k * 4 + 2 : U32)] <- g
  nodes[(k * 4 + 3 : U32)] <- h

def pushed(s: Star, +t: U32, +current: U32, +g: U32, +h: U32) -> Star:
  match s:
    case Star{nodes, open, marks, +n_open, +n_nodes, _}:
      open[n_open] <- n_nodes
      marks[(t * 2 + 1 : U32)] <- n_nodes
      Star{put_node(nodes, n_nodes, t, current, g, h), open, marks, (n_open + 1 : U32), (n_nodes + 1 : U32), True{}}

def improved(better: Bool, s: Star, +f: U32, +current: U32, +g: U32, +h: U32) -> Star:
  match better:
    case False{}:
      s
    case True{}:
      match s:
        case Star{nodes, open, marks, +n_open, +n_nodes, _}:
          nodes[(f * 4 + 1 : U32)] <- current
          nodes[(f * 4 + 3 : U32)] <- h
          nodes[(f * 4 + 2 : U32)] <- g
          Star{nodes, open, marks, n_open, n_nodes, True{}}

def compare_open(got: Array<U32> & U32, open: Array<U32>, marks: Array<U32>, +n_open: U32, +n_nodes: U32, +resort: Bool, +f: U32, +current: U32, +g: U32, +h: U32) -> Star:
  (nodes, +gf) = got
  improved((F32Ops.from_bits(g) < F32Ops.from_bits(gf) : F32), Star{nodes, open, marks, n_open, n_nodes, resort}, f, current, g, h)

def in_open(fresh: Bool, s: Star, +t: U32, +f: U32, +current: U32, +g: U32, +h: U32) -> Star:
  match fresh:
    case True{}:
      pushed(s, t, current, g, h)
    case False{}:
      match s:
        case Star{nodes, open, marks, +n_open, +n_nodes, +resort}:
          compare_open(nodes[(f * 4 + 2 : U32)], open, marks, n_open, n_nodes, resort, f, current, g, h)

def open_got(got: Array<U32> & U32, nodes: Array<U32>, open: Array<U32>, +n_open: U32, +n_nodes: U32, +resort: Bool, +t: U32, +current: U32, +g: U32, +h: U32) -> Star:
  (marks, +f) = got
  in_open(TileWorld.is_none(f), Star{nodes, open, marks, n_open, n_nodes, resort}, t, f, current, g, h)

def consider(skip: Bool, s: Star, +t: U32, +current: U32, +g: U32, +h: U32) -> Star:
  match skip:
    case True{}:
      s
    case False{}:
      match s:
        case Star{nodes, open, marks, +n_open, +n_nodes, +resort}:
          open_got(marks[(t * 2 + 1 : U32)], nodes, open, n_open, n_nodes, resort, t, current, g, h)

def closed_got(got: Array<U32> & U32, nodes: Array<U32>, open: Array<U32>, +n_open: U32, +n_nodes: U32, +resort: Bool, +t: U32, +cv: U32, +current: U32, +g: U32, +h: U32) -> Star:
  (marks, +closed) = got
  consider(U32.is_eq(t, cv) || U32.is_eq(closed, 1), Star{nodes, open, marks, n_open, n_nodes, resort}, t, current, g, h)

def neighbour_step(s: Star, +t: U32, +cv: U32, +current: U32, +g: U32, +hops: TileTable.Tree<U32>) -> Star:
  match s:
    case Star{nodes, open, marks, +n_open, +n_nodes, +resort}:
      closed_got(marks[(t * 2 : U32)], nodes, open, n_open, n_nodes, resort, t, cv, current, g, h_bits(hops, t))

def neighbours_loop(ts: List<&2, U32>, s: Star, +cv: U32, +current: U32, +g: U32, +hops: TileTable.Tree<U32>) -> Star:
  match ts:
    case Nil{}:
      s
    case Con{+t, rest}:
      neighbours_loop(rest, neighbour_step(s, t, cv, current, g, hops), cv, current, g, hops)

type Turn is Type:
  Turn{star: Star, found: Bool, go: Bool, current: U32}

def expanded(s: Star, +found: Bool, +current: U32) -> Turn:
  match s:
    case Star{nodes, open, marks, +n_open, +n_nodes, +resort}:
      Turn{Star{nodes, open, marks, n_open, n_nodes, resort}, found, U32.is_ne(n_open, 0), current}

def expand(at_goal: Bool, s: Star, +w: TileWorld.World, +cv: U32, +current: U32, +g: U32, +hops: TileTable.Tree<U32>) -> Turn:
  match at_goal:
    case True{}:
      Turn{s, True{}, True{}, current}
    case False{}:
      expanded(neighbours_loop(TileTopology.neighbours(w, cv), s, cv, current, F32Ops.bits((F32Ops.from_bits(g) + 1.0 : F32)), hops), False{}, current)

def popped_g(got: Array<U32> & U32, open: Array<U32>, marks: Array<U32>, +n_open: U32, +n_nodes: U32, +w: TileWorld.World, +goal: U32, +hops: TileTable.Tree<U32>, +current: U32, +cv: U32) -> Turn:
  (nodes, +g) = got
  marks[(cv * 2 : U32)] <- 1
  expand(U32.is_eq(cv, goal), Star{nodes, open, marks, n_open, n_nodes, False{}}, w, cv, current, g, hops)

def popped_vertex(got: Array<U32> & U32, open: Array<U32>, marks: Array<U32>, +n_open: U32, +n_nodes: U32, +w: TileWorld.World, +goal: U32, +hops: TileTable.Tree<U32>, +current: U32) -> Turn:
  (nodes, +cv) = got
  popped_g(nodes[(current * 4 + 2 : U32)], open, marks, n_open, n_nodes, w, goal, hops, current, cv)

def popped(got: Array<U32> & U32, nodes: Array<U32>, marks: Array<U32>, +n_open: U32, +n_nodes: U32, +w: TileWorld.World, +goal: U32, +hops: TileTable.Tree<U32>) -> Turn:
  (open, +current) = got
  popped_vertex(nodes[(current * 4 : U32)], open, marks, n_open, n_nodes, w, goal, hops, current)

# One A* iteration after the optional sort: pop the last open node, close it, stop at the goal, else relax its
# out-edge targets.
def iteration(s: Star, +w: TileWorld.World, +goal: U32, +hops: TileTable.Tree<U32>) -> Turn:
  match s:
    case Star{nodes, open, marks, +n_open, +n_nodes, _}:
      popped(open[(n_open - 1 : U32)], nodes, marks, (n_open - 1 : U32), n_nodes, w, goal, hops)

def star_loop(n: Nat, t: Turn, +windows: Bool, +w: TileWorld.World, +goal: U32, +hops: TileTable.Tree<U32>) -> Array<U32> & U32:
  match n:
    case 0n:
      match t:
        case Turn{Star{nodes, _, _, _, _, _}, _, _, _}:
          (nodes, TileWorld.none())
    case 1n+p:
      match t:
        case Turn{Star{nodes, open, marks, +n_open, +n_nodes, +resort}, +found, +go, +current}:
          match found:
            case True{}:
              (nodes, current)
            case False{}:
              match go:
                case False{}:
                  (nodes, TileWorld.none())
                case True{}:
                  star_loop(p, iteration(sort_open(resort, windows, Star{nodes, open, marks, n_open, n_nodes, resort}), w, goal, hops), windows, w, goal, hops)

type Hop is Data:
  Hop{vertex: U32, parent: U32, more: Bool}

def hop_parent(got: Array<U32> & U32, +v: U32) -> Array<U32> & Hop:
  (nodes, +parent) = got
  (nodes, Hop{v, parent, Bool.not(TileWorld.is_none(parent))})

def hop_vertex(got: Array<U32> & U32, +k: U32) -> Array<U32> & Hop:
  (nodes, +v) = got
  hop_parent(nodes[(k * 4 + 1 : U32)], v)

def hop(nodes: Array<U32>, +k: U32) -> Array<U32> & Hop:
  hop_vertex(nodes[(k * 4 : U32)], k)

def path_loop(n: Nat, got: Array<U32> & Hop, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, acc)
    case 1n+p:
      (nodes, h) = got
      match h:
        case Hop{+v, +parent, +more}:
          match more:
            case False{}:
              List.reverse(&2, U32, v <> acc)
            case True{}:
              path_loop(p, hop(nodes, parent), v <> acc)

def path_of(got: Array<U32> & U32) -> List<&2, U32>:
  (nodes, +k) = got
  Bool.pick(List<&2, U32>, TileWorld.is_none(k), Nil{}, path_loop(U32.to_nat(4096), hop(nodes, k), Nil{}))

def start_star(+w: TileWorld.World, +start: U32, +hops: TileTable.Tree<U32>) -> Star:
  +d = TileConnect.sites_depth(w)
  nodes = Grid.alloc(Nat.add(d, 2n), 0)
  marks = Grid.alloc(1n+d, TileWorld.none())
  open = Grid.alloc(d, 0)
  marks[(start * 2 + 1 : U32)] <- 0
  Star{put_node(nodes, 0, start, TileWorld.none(), 0, h_bits(hops, start)), open[0] <- 0, marks, 1, 1, True{}}

# AStarPath(start, goal): the vertices from the goal back to the start (empty when no path within 1000 steps).
def astar(+windows: Bool, +w: TileWorld.World, +start: U32, +goal: U32) -> List<&2, U32>:
  +hops = TileTable.from_list(~U32, hops_to(w, goal), TileWorld.none())
  path_of(star_loop(1000n, Turn{start_star(w, start, hops), False{}, True{}, 0}, windows, w, goal, hops))

def labels_tree(+isl: TileConnect.Islands) -> TileTable.Tree<U32>:
  match isl:
    case TileConnect.Islands{+labels, _}:
      TileTable.from_list(~U32, labels, 0)

def same_point(+a: TileWorld.Point, +b: TileWorld.Point) -> Bool:
  match a:
    case TileWorld.Point{+ax, +ay}:
      match b:
        case TileWorld.Point{+bx, +by}:
          F32.is_eq(ax, bx) && F32.is_eq(ay, by)

def link_points(adjacent: Bool, +w: TileWorld.World, +conns: TileTable.Tree<List<&2, U32>>, +a: U32, +b: U32) -> List<&2, TileWorld.Point>:
  match adjacent:
    case True{}:
      TileConnect.cell_line_points(w, conns, a, b)
    case False{}:
      Nil{}

def path_links(path: List<&2, U32>, +w: TileWorld.World, +conns: TileTable.Tree<List<&2, U32>>) -> List<&2, TileWorld.Point>:
  match path:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      match rest:
        case Nil{}:
          Nil{}
        case Con{+b, _}:
          List.append(&2, TileWorld.Point, link_points(TileTopology.adjacent(w, a, b), w, conns, a, b), path_links(rest, w, conns))

def last_or(xs: List<&2, U32>, +fill: U32) -> U32:
  Maybe.default(&2, U32, List.last(&2, U32, xs), fill)

def road_along(ok: Bool, +path: List<&2, U32>, +w: TileWorld.World, +conns: TileTable.Tree<List<&2, U32>>) -> List<&2, TileWorld.Point>:
  match ok:
    case False{}:
      Nil{}
    case True{}:
      List.append(&2, TileWorld.Point, path_links(path, w, conns), [TileConnect.site_point(w, last_or(path, 0))])

def road_of_path(+path: List<&2, U32>, +w: TileWorld.World, +isl: TileConnect.Islands) -> List<&2, TileWorld.Point>:
  +labels = labels_tree(isl)
  +long = Nat.is_ge(List.length(&2, U32, path), 2n)
  +same = U32.is_eq(TileTable.at(~U32, labels, TileTable.first_or(~U32, path, 0)), TileTable.at(~U32, labels, last_or(path, 0)))
  road_along(long && same, path, w, TileConnect.connections(w, TileConnect.conns_list(isl)))

def pig_road_for(found: Bool, +p: Pigs, +windows: Bool, +w: TileWorld.World, +isl: TileConnect.Islands) -> List<&2, TileWorld.Point>:
  match found:
    case False{}:
      Nil{}
    case True{}:
      match p:
        case Pigs{+kingdom, +village, _, _}:
          road_of_path(astar(windows, w, kingdom, village), w, isl)

# PigRoad(map, join_islands = false).
def pig_road(+windows: Bool, +w: TileWorld.World, +isl: TileConnect.Islands) -> List<&2, TileWorld.Point>:
  +p = find_pigs(w)
  pig_road_for(both(p), p, windows, w, isl)

def has_segment(road: List<&2, TileWorld.Point>, +a: TileWorld.Point, +b: TileWorld.Point) -> Bool:
  match road:
    case Nil{}:
      False{}
    case Con{+p, rest}:
      match rest:
        case Nil{}:
          False{}
        case Con{+q, _}:
          (same_point(p, a) && same_point(q, b)) || (same_point(p, b) && same_point(q, a)) || has_segment(rest, a, b)

def segment_keep(hit: Bool, +seg: List<&2, TileWorld.Point>, tail: List<&2, List<&2, TileWorld.Point>>) -> List<&2, List<&2, TileWorld.Point>>:
  match hit:
    case True{}:
      seg <> tail
    case False{}:
      tail

def poison(+n: TileWorld.Node) -> Bool:
  U32.is_ne((TileTopology.flags_of(n) .&. 4 : U32), 0)

def road_segments(edges: List<&2, TileWorld.Edge>, +w: TileWorld.World, +labels: TileTable.Tree<U32>, +pig: List<&2, TileWorld.Point>) -> List<&2, List<&2, TileWorld.Point>>:
  match edges:
    case Nil{}:
      Nil{}
    case Con{TileWorld.Edge{+a, +b}, rest}:
      +na = TileWorld.node(w, a)
      +nb = TileWorld.node(w, b)
      +kept = TileConnect.non_blank(w, TileWorld.Edge{a, b}) && (U32.is_eq(TileTable.at(~U32, labels, a), TileTable.at(~U32, labels, b)) || TileConnect.forced(w, TileWorld.Edge{a, b}))
      +pa = TileConnect.site_point(w, a)
      +pb = TileConnect.site_point(w, b)
      +on_pig = Nat.is_ge(List.length(&2, TileWorld.Point, pig), 2n) && has_segment(pig, pa, pb)
      segment_keep(kept && Bool.not(poison(na) || poison(nb)) && Bool.not(on_pig), [pa, pb], road_segments(rest, w, labels, pig))

type Chained is Data:
  Chained{chains: List<&2, List<&2, TileWorld.Point>>, attached: Bool}

def front(+xs: List<&2, TileWorld.Point>) -> TileWorld.Point:
  TileTable.first_or(~TileWorld.Point, xs, TileWorld.Point{0.0, 0.0})

def back(+xs: List<&2, TileWorld.Point>) -> TileWorld.Point:
  Maybe.default(&2, TileWorld.Point, List.last(&2, TileWorld.Point, xs), TileWorld.Point{0.0, 0.0})

def prepend(+c: List<&2, TileWorld.Point>, r: Chained) -> Chained:
  match r:
    case Chained{+chains, +attached}:
      Chained{c <> chains, attached}

def choose(to_back: Bool, to_front: Bool, +c: List<&2, TileWorld.Point>, +rest: List<&2, List<&2, TileWorld.Point>>, +seg: List<&2, TileWorld.Point>, later: Chained) -> Chained:
  match to_back:
    case True{}:
      Chained{List.append(&2, TileWorld.Point, c, List.tail(&2, TileWorld.Point, seg)) <> rest, True{}}
    case False{}:
      match to_front:
        case True{}:
          Chained{List.append(&2, TileWorld.Point, seg, List.tail(&2, TileWorld.Point, c)) <> rest, True{}}
        case False{}:
          prepend(c, later)

def attach(chains: List<&2, List<&2, TileWorld.Point>>, +seg: List<&2, TileWorld.Point>) -> Chained:
  match chains:
    case Nil{}:
      Chained{Nil{}, False{}}
    case Con{+c, +rest}:
      choose(same_point(front(seg), back(c)), same_point(back(seg), front(c)), c, rest, seg, attach(rest, seg))

def attached_or_new(r: Chained, +seg: List<&2, TileWorld.Point>) -> List<&2, List<&2, TileWorld.Point>>:
  match r:
    case Chained{+chains, +attached}:
      Bool.pick(List<&2, List<&2, TileWorld.Point>>, attached, chains, List.append(&2, List<&2, TileWorld.Point>, chains, [seg]))

def chain_loop(segs: List<&2, List<&2, TileWorld.Point>>, +chains: List<&2, List<&2, TileWorld.Point>>) -> List<&2, List<&2, TileWorld.Point>>:
  match segs:
    case Nil{}:
      chains
    case Con{+seg, rest}:
      chain_loop(rest, attached_or_new(attach(chains, seg), seg))

# ChainSegments: each segment extends the first chain it continues (its front at the chain's back, or its back at
# the chain's front), else starts a chain.
def chain_segments(+segs: List<&2, List<&2, TileWorld.Point>>) -> List<&2, List<&2, TileWorld.Point>>:
  chain_loop(segs, Nil{})

def edges_of(+w: TileWorld.World) -> List<&2, TileWorld.Edge>:
  match w:
    case TileWorld.World{_, _, _, _, _, _, +edges, _, _}:
      edges

def with_pig(+pig: List<&2, TileWorld.Point>, +chains: List<&2, List<&2, TileWorld.Point>>) -> List<&2, List<&2, TileWorld.Point>>:
  Bool.pick(List<&2, List<&2, TileWorld.Point>>, List.is_empty(&2, TileWorld.Point, pig), chains, pig <> chains)

# GetRoads(map, join_islands = false) after ForceConnectivity: the pig road (if any), then the chained edges.
def roads(+windows: Bool, +w: TileWorld.World, +isl: TileConnect.Islands) -> List<&2, List<&2, TileWorld.Point>>:
  +pig = pig_road(windows, w, isl)
  with_pig(pig, chain_segments(road_segments(edges_of(w), w, labels_tree(isl), pig)))

# DrawRoads (roads.cpp): every road's control points in quarter-tile world units, a Catmull-Rom spline per segment
# stepped about one tile at a time, widths from a 1D gradient noise, and each step's quad outlined with a grid
# traversal that flags cells 0x2000 and turns impassable cells into the road tile.

def perm_units(units: List<&2, U32>) -> List<&2, U32>:
  match units:
    case Nil{}:
      Nil{}
    case Con{+u, rest}:
      (u .&. 255 : U32) <> (u >> 8n : U32) <> perm_units(rest)

def perm_table() -> TileTable.Tree<U32>:
  TileTable.from_list(~U32, perm_units(Constants.perlin(0)), 0)

def gradient(+perm: TileTable.Tree<U32>, +i: U32) -> F32:
  +p = TileTable.at(~U32, perm, (i .&. 255 : U32))
  +g = (U32.to_f32((p .&. 7 : U32)) + 1.0 : F32)
  Bool.pick(F32, U32.is_ne((p .&. 8 : U32), 0), (0.0 - g : F32), g)

def gradient_noise(+perm: TileTable.Tree<U32>, +x: F32) -> F32:
  +t = F32.to_u32(x)
  +positive = (0.0 < x : F32)
  +i = Bool.pick(U32, positive, t, (t - 1 : U32))
  +fi = Bool.pick(F32, positive, U32.to_f32(t), (U32.to_f32(t) - 1.0 : F32))
  +f = (x - fi : F32)
  +f1 = (f - 1.0 : F32)
  +a = (1.0 - f * f : F32)
  +a2 = (a * a : F32)
  +v0 = (f * (a2 * a2 * gradient(perm, i)) : F32)
  +b = (1.0 - f1 * f1 : F32)
  +b2 = (b * b : F32)
  +v1 = (f1 * (b2 * b2 * gradient(perm, (i + 1 : U32))) : F32)
  ((v0 + v1) * 0.25 : F32)

type Spline is Data:
  Spline{p0: TileWorld.Point, p1: TileWorld.Point, p2: TileWorld.Point, p3: TileWorld.Point}

def cr_a(+p0: F32, +p1: F32, +p2: F32, +p3: F32) -> F32:
  (((p1 * 3.0 - p0) - p2 * 3.0) + p3 : F32)

def cr_b(+p0: F32, +p1: F32, +p2: F32, +p3: F32) -> F32:
  ((p2 * 4.0 + ((p0 + p0) - p1 * 5.0)) - p3 : F32)

def cr_position(+p0: F32, +p1: F32, +p2: F32, +p3: F32, +t: F32) -> F32:
  +t2 = (t * t : F32)
  +t3 = (t * t2 : F32)
  ((cr_a(p0, p1, p2, p3) * t3 + (cr_b(p0, p1, p2, p3) * t2 + ((p2 - p0) * t + (p1 + p1)))) * 0.5 : F32)

def cr_tangent(+p0: F32, +p1: F32, +p2: F32, +p3: F32, +t: F32) -> F32:
  +t2 = (t * t : F32)
  (cr_a(p0, p1, p2, p3) * (t2 * 1.5) + (cr_b(p0, p1, p2, p3) * t + (p2 - p0)) : F32)

def position(+s: Spline, +t: F32) -> TileWorld.Point:
  match s:
    case Spline{TileWorld.Point{+x0, +y0}, TileWorld.Point{+x1, +y1}, TileWorld.Point{+x2, +y2}, TileWorld.Point{+x3, +y3}}:
      TileWorld.Point{cr_position(x0, x1, x2, x3, t), cr_position(y0, y1, y2, y3, t)}

def tangent(+s: Spline, +t: F32) -> TileWorld.Point:
  match s:
    case Spline{TileWorld.Point{+x0, +y0}, TileWorld.Point{+x1, +y1}, TileWorld.Point{+x2, +y2}, TileWorld.Point{+x3, +y3}}:
      TileWorld.Point{cr_tangent(x0, x1, x2, x3, t), cr_tangent(y0, y1, y2, y3, t)}

type Frame is Data:
  Frame{x: F32, y: F32, nx: F32, ny: F32, width: F32}

def frame_of(+pos: TileWorld.Point, +tan: TileWorld.Point, +width: F32) -> Frame:
  match pos:
    case TileWorld.Point{+x, +y}:
      match tan:
        case TileWorld.Point{+tx, +ty}:
          +len = F32.sqrt((tx * tx + ty * ty : F32))
          Frame{x, y, (0.0 - (tx / len) : F32), (ty / len : F32), width}

def param(+bits: U32) -> F32:
  F32Ops.from_bits(bits)

def jittered_width(+noise: F32) -> F32:
  ((param(TileGroupsData.road_max_width_bits()) - param(TileGroupsData.road_min_width_bits())) * noise + param(TileGroupsData.road_min_width_bits())
    + (noise * (param(TileGroupsData.road_max_edge_width_bits()) - param(TileGroupsData.road_min_edge_width_bits())) + param(TileGroupsData.road_min_edge_width_bits())) : F32)

def step_width(+noise: F32) -> F32:
  ((noise * (param(TileGroupsData.road_max_edge_width_bits()) - param(TileGroupsData.road_min_edge_width_bits())) + param(TileGroupsData.road_min_edge_width_bits()))
    + ((param(TileGroupsData.road_max_width_bits()) - param(TileGroupsData.road_min_width_bits())) * noise + param(TileGroupsData.road_min_width_bits())) : F32)

type Raster is Data:
  Raster{windows: Bool, tile: U32, ox: F32, oy: F32}

def mark_got(got: Grid.Grid & U32, +i: U32, +tile: U32) -> Grid.Grid:
  (g, +old) = got
  +t = Grid.tile_of(old)
  Grid.put(g, i, Grid.cell(Bool.pick(U32, TileGroups.is_impassable(t), tile, t), (Grid.flags_of(old) .|. 8192 : U32)))

def mark_in(inside: Bool, g: Grid.Grid, +i: U32, +tile: U32) -> Grid.Grid:
  match inside:
    case True{}:
      mark_got(Grid.get(g, i), i, tile)
    case False{}:
      g

def mark(g: Grid.Grid, +x: U32, +y: U32, +tile: U32) -> Grid.Grid:
  match g:
    case Grid.Grid{cells, +w, +h}:
      +i = (w * y + x : U32)
      mark_in((i < (w * h : U32) : U32), Grid.Grid{cells, w, h}, i, tile)

type Walker is Data:
  Walker{ix: U32, iy: U32, sx: U32, sy: U32, dx: F32, dy: F32, err: F32}

def walk(n: Nat, g: Grid.Grid, +k: Walker, +tile: U32) -> Grid.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      match k:
        case Walker{+ix, +iy, +sx, +sy, +dx, +dy, +err}:
          +up = (0.0 < err : F32)
          walk(p, mark(g, ix, iy, tile), Walker{Bool.pick(U32, up, ix, (ix + sx : U32)), Bool.pick(U32, up, (iy + sy : U32), iy),
            sx, sy, dx, dy, Bool.pick(F32, up, (err - dx : F32), (err + dy : F32))}, tile)

def f64_of(+v: F32) -> F64Repr.F64:
  F32Ops.to_f64(v)

def inf() -> F32:
  F32Ops.from_bits(inf_bits())

def floor_int(+v: F32) -> U32:
  SiteTiles.trunc_wrap(F32.floor(v))

def x_gap(forward: Bool, +x0: F32, +fx: F32) -> F64Repr.F64:
  match forward:
    case True{}:
      F64Arith.sub(F64Arith.add(f64_of(fx), F64Repr.one()), f64_of(x0))
    case False{}:
      F64Arith.sub(f64_of(x0), f64_of(fx))

def x_err(windows: Bool, +x0: F32, +fx: F32, +dy: F32, +forward: Bool) -> F32:
  match windows:
    case True{}:
      Bool.pick(F32, forward, (((fx + 1.0) - x0) * dy : F32), ((x0 - fx) * dy : F32))
    case False{}:
      F32Ops.from_f64(F64Arith.mul(x_gap(forward, x0, fx), f64_of(dy)))

def y_gap(down: Bool, +y0: F32, +fy: F32) -> F64Repr.F64:
  match down:
    case True{}:
      F64Arith.sub(f64_of(y0), f64_of(fy))
    case False{}:
      F64Arith.sub(F64Arith.add(f64_of(fy), F64Repr.one()), f64_of(y0))

def y_err(windows: Bool, +err: F32, +y0: F32, +fy: F32, +dx: F32, +down: Bool) -> F32:
  match windows:
    case True{}:
      Bool.pick(F32, down, (err + (0.0 - (y0 - fy) * dx) : F32), (err + (0.0 - ((fy + 1.0) - y0) * dx) : F32))
    case False{}:
      F32Ops.from_f64(F64Arith.sub(f64_of(err), F64Arith.mul(y_gap(down, y0, fy), f64_of(dx))))

def signed_positive(+n: U32) -> Bool:
  U32.is_ne(n, 0) && (n < 2147483648 : U32)

# RoadRaster::Line: the grid traversal from (x0, y0) to (x1, y1), with the platform's initial error term.
def line(g: Grid.Grid, +r: Raster, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Grid.Grid:
  match r:
    case Raster{+windows, +tile, _, _}:
      +dx = F32.abs((x1 - x0 : F32))
      +dy = F32.abs((y1 - y0 : F32))
      +fx = F32.floor(x0)
      +fy = F32.floor(y0)
      +ix = SiteTiles.trunc_wrap(fx)
      +iy = SiteTiles.trunc_wrap(fy)
      +flat_x = F32.is_eq(dx, 0.0)
      +forward = (x0 < x1 : F32)
      +sx = Bool.pick(U32, flat_x, 0, Bool.pick(U32, forward, 1, 4294967295))
      +nx = Bool.pick(U32, flat_x, 1, Bool.pick(U32, forward, (floor_int(x1) - ix + 1 : U32), (ix - floor_int(x1) + 1 : U32)))
      +ex = Bool.pick(F32, flat_x, inf(), x_err(windows, x0, fx, dy, forward))
      +flat_y = F32.is_eq(dy, 0.0)
      +down = (y1 <= y0 : F32)
      +sy = Bool.pick(U32, flat_y, 0, Bool.pick(U32, down, 4294967295, 1))
      +n = Bool.pick(U32, flat_y, nx, Bool.pick(U32, down, (nx + (iy - floor_int(y1)) : U32), (nx + (floor_int(y1) - iy) : U32)))
      +err = Bool.pick(F32, flat_y, (ex - inf() : F32), y_err(windows, ex, y0, fy, dx, down))
      walk(Bool.pick(Nat, signed_positive(n), U32.to_nat(Bool.pick(U32, (n < 1048576 : U32), n, 1048576)), 0n), g,
        Walker{ix, iy, sx, sy, dx, dy, err}, tile)

def corner_x(+f: Frame, +neg: Bool, +o: F32) -> F32:
  match f:
    case Frame{+x, _, _, +ny, +width}:
      (((Bool.pick(F32, neg, F32.neg(width), width) * ny + x) - o) * 0.25 : F32)

def corner_y(+f: Frame, +neg: Bool, +o: F32) -> F32:
  match f:
    case Frame{_, +y, +nx, _, +width}:
      (((nx * Bool.pick(F32, neg, F32.neg(width), width) + y) - o) * 0.25 : F32)

def raster_ox(+r: Raster) -> F32:
  match r:
    case Raster{_, _, +ox, _}:
      ox

def raster_oy(+r: Raster) -> F32:
  match r:
    case Raster{_, _, _, +oy}:
      oy

# DrawRoadQuad: the outline of the quad between two frames (4 lines).
def quad(g: Grid.Grid, +r: Raster, +a: Frame, +b: Frame) -> Grid.Grid:
  +ox = raster_ox(r)
  +oy = raster_oy(r)
  +q0x = corner_x(a, False{}, ox)
  +q0y = corner_y(a, False{}, oy)
  +q1x = corner_x(a, True{}, ox)
  +q1y = corner_y(a, True{}, oy)
  +q2x = corner_x(b, False{}, ox)
  +q2y = corner_y(b, False{}, oy)
  +q3x = corner_x(b, True{}, ox)
  +q3y = corner_y(b, True{}, oy)
  line(line(line(line(g, r, q0x, q0y, q1x, q1y), r, q2x, q2y, q3x, q3y), r, q0x, q0y, q2x, q2y), r, q1x, q1y, q3x, q3y)

def gap(+a: TileWorld.Point, +b: TileWorld.Point) -> F32:
  match a:
    case TileWorld.Point{+ax, +ay}:
      match b:
        case TileWorld.Point{+bx, +by}:
          ((ax - bx) * (ax - bx) + (ay - by) * (ay - by) : F32)

def halve(n: Nat, far: Bool, +s: Spline, +t: F32, +next: F32, +here: TileWorld.Point) -> F32:
  match n:
    case 0n:
      next
    case 1n+p:
      match far:
        case False{}:
          next
        case True{}:
          +half = ((next + t) * 0.5 : F32)
          halve(p, (16.0 < gap(here, position(s, half)) : F32), s, t, half, here)

# The t after `t`: t + step (at most 1), halved towards t while the chord is longer than 4.
def next_t(+s: Spline, +t: F32, +step: F32) -> F32:
  +next = Bool.pick(F32, ((step + t) < 1.0 : F32), (step + t : F32), 1.0)
  +here = position(s, t)
  halve(200n, (16.0 < gap(here, position(s, next)) : F32), s, t, next, here)

def step_loop(n: Nat, go: Bool, g: Grid.Grid, +r: Raster, +perm: TileTable.Tree<U32>, +s: Spline, +prev: Frame, +t: F32, +step: F32, +segf: F32) -> Grid.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      match go:
        case False{}:
          g
        case True{}:
          +cur = frame_of(position(s, t), tangent(s, t), step_width(gradient_noise(perm, (5.0 * t + segf : F32))))
          step_loop(p, Bool.not(F32.is_eq(t, 1.0)), quad(g, r, prev, cur), r, perm, s, cur, next_t(s, t, step), step, segf)

def frame_x(+f: Frame) -> F32:
  match f:
    case Frame{+x, _, _, _, _}:
      x

def frame_y(+f: Frame) -> F32:
  match f:
    case Frame{_, +y, _, _, _}:
      y

def segment(g: Grid.Grid, +r: Raster, +perm: TileTable.Tree<U32>, +s: Spline, +segf: F32) -> Grid.Grid:
  +prev = frame_of(position(s, 0.0), tangent(s, 0.0), jittered_width(gradient_noise(perm, (0.0 + segf : F32))))
  +end = position(s, 1.0)
  +ex = (TileConnect.px(end) - frame_x(prev) : F32)
  +ey = (TileConnect.py(end) - frame_y(prev) : F32)
  +step = (1.0 / (F32.sqrt((ex * ex + ey * ey : F32)) * 0.25) : F32)
  step_loop(U32.to_nat(1048576), True{}, g, r, perm, s, prev, Bool.pick(F32, (step < 1.0 : F32), step, 1.0), step, segf)

def splines(ps: List<&2, TileWorld.Point>) -> List<&2, Spline>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+a, +rest}:
      match rest:
        case Con{+b, Con{+c, Con{+d, _}}}:
          Spline{a, b, c, d} <> splines(rest)
        case _:
          Nil{}

def segments(ss: List<&2, Spline>, g: Grid.Grid, +r: Raster, +perm: TileTable.Tree<U32>, +k: U32) -> Grid.Grid:
  match ss:
    case Nil{}:
      g
    case Con{+s, rest}:
      segments(rest, segment(g, r, perm, s, (0.0 + U32.to_f32(k) : F32)), r, perm, (k + 1 : U32))

def control(+q: TileWorld.Point, +half_w: F32, +half_h: F32) -> TileWorld.Point:
  match q:
    case TileWorld.Point{+x, +y}:
      TileWorld.Point{(F32.floor(((x - half_w) * 4.0 * 10.0 : F32)) / 10.0 : F32), (F32.floor(((y - half_h) * 4.0 * 10.0 : F32)) / 10.0 : F32)}

def controls(qs: List<&2, TileWorld.Point>, +half_w: F32, +half_h: F32) -> List<&2, TileWorld.Point>:
  match qs:
    case Nil{}:
      Nil{}
    case Con{+q, rest}:
      control(q, half_w, half_h) <> controls(rest, half_w, half_h)

def padded(+c: List<&2, TileWorld.Point>) -> List<&2, TileWorld.Point>:
  front(c) <> List.append(&2, TileWorld.Point, c, [back(c)])

def road(drawn: Bool, g: Grid.Grid, +r: Raster, +perm: TileTable.Tree<U32>, +road: List<&2, TileWorld.Point>) -> Grid.Grid:
  match drawn:
    case False{}:
      g
    case True{}:
      match g:
        case Grid.Grid{cells, +w, +h}:
          segments(splines(padded(controls(road, (U32.to_f32(w) * 0.5 : F32), (U32.to_f32(h) * 0.5 : F32)))), Grid.Grid{cells, w, h}, r, perm, 0)

def roads_loop(rs: List<&2, List<&2, TileWorld.Point>>, g: Grid.Grid, +r: Raster, +perm: TileTable.Tree<U32>) -> Grid.Grid:
  match rs:
    case Nil{}:
      g
    case Con{+pts, rest}:
      roads_loop(rest, road(Nat.is_ge(List.length(&2, TileWorld.Point, pts), 2n), g, r, perm, pts), r, perm)

def raster_for(+windows: Bool, +w: U32, +h: U32) -> Raster:
  Raster{windows, TileGroupsData.tile_dirt(), (U32.to_f32(w) * (0.0 - 0.5 : F32) * 4.0 - 2.0 : F32), (U32.to_f32(h) * (0.0 - 0.5 : F32) * 4.0 - 2.0 : F32)}

# DrawRoads(join_islands, DIRT) over GetRoads' polylines.
def draw_roads(+windows: Bool, +rs: List<&2, List<&2, TileWorld.Point>>, g: Grid.Grid) -> Grid.Grid:
  match g:
    case Grid.Grid{cells, +w, +h}:
      roads_loop(rs, Grid.Grid{cells, w, h}, raster_for(windows, w, h), perm_table())
