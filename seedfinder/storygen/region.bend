import Base
import ../lua/util.bend as LuaUtil
import ../lua/sort.bend as LuaSort
import ../lua/table.bend as LuaTable
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../data/story.bend as StoryData
import ../data/enums.bend as Enums
import ./graph.bend as StoryGraph
import ./order.bend as StoryOrder
import ./link.bend as StoryLink
import ./background.bend as Background
import ./setpieces.bend as StorySetpieces
import ./plan.bend as StoryPlan

# Story:AddRegionsToMainland for the moon island: FindMainlandNodesForNewRegion (the geometry-dependent choice of the
# two mainland nodes the island links to), GenerateNodesForRegion (RestrictNodesByKey), coves, set pieces and two
# LinkRegions. The geometry is WorldSim:GetSite after VoronoiPass(100): f32 x, y bits of node n at StoryGraph.site_base() + 2n
# (the trace fills them from the oracle; the generator will fill them from the Voronoi stage).

type Pt is Data:
  Pt{node: U32, x: F64Repr.F64, y: F64Repr.F64}

def site_x(+s: StoryGraph.St, +n: U32) -> F64Repr.F64:
  F64Repr.from_f32_bits(StoryGraph.get(s, (StoryGraph.site_base() + (n * 2 : U32) : U32)))

def site_y(+s: StoryGraph.St, +n: U32) -> F64Repr.F64:
  F64Repr.from_f32_bits(StoryGraph.get(s, ((StoryGraph.site_base() + (n * 2 : U32) : U32) + 1 : U32)))

def task_graphs(n: Nat, +s: StoryGraph.St, +g: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +tail = task_graphs(p, s, (g + 1 : U32))
      Bool.pick(List<&2, U32>, U32.is_eq(StoryGraph.gf(s, g, StoryGraph.g_kind()), StoryGraph.k_task()), g <> tail, tail)

def with_task(+s: StoryGraph.St, nodes: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      +tail = with_task(s, rest)
      Bool.pick(List<&2, U32>, U32.is_ne(StoryGraph.nf(s, n, StoryGraph.f_task()), StoryGraph.none()), n <> tail, tail)

def sited(graphs: List<&2, U32>, +s: StoryGraph.St) -> List<&2, U32>:
  match graphs:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      List.append(&2, U32, with_task(s, StoryGraph.node_order(s, g)), sited(rest, s))

def get_sites(nodes: List<&2, U32>, +s: StoryGraph.St) -> StoryGraph.St:
  match nodes:
    case Nil{}:
      s
    case Con{_, rest}:
      get_sites(rest, StoryGraph.call(s, StoryGraph.m_get_site()))

type Box is Data:
  Box{min_x: F64Repr.F64, max_x: F64Repr.F64, min_y: F64Repr.F64, max_y: F64Repr.F64}

def boxed(nodes: List<&2, U32>, +s: StoryGraph.St, +b: Box) -> Box:
  match nodes:
    case Nil{}:
      b
    case Con{+n, rest}:
      match b:
        case Box{+x0, +x1, +y0, +y1}:
          +x = site_x(s, n)
          +y = site_y(s, n)
          boxed(rest, s, Box{F64Cmp.min(x, x0), F64Cmp.max(x, x1), F64Cmp.min(y, y0), F64Cmp.max(y, y1)})

def five() -> F64Repr.F64:
  F64Repr.from_u32(5)

def three() -> F64Repr.F64:
  F64Repr.from_u32(3)

def shifted(nodes: List<&2, U32>, +s: StoryGraph.St, +dx: F64Repr.F64, +dy: F64Repr.F64) -> List<&2, Pt>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      Pt{n, F64Arith.add(site_x(s, n), dx), F64Arith.add(site_y(s, n), dy)} <> shifted(rest, s, dx, dy)

type Frame is Data:
  Frame{points: List<&2, Pt>, w: F64Repr.F64}

def framed(+order: List<&2, U32>, +s: StoryGraph.St, +b: Box) -> Frame:
  match b:
    case Box{+x0, +x1, +y0, +y1}:
      +min_x = F64Repr.floor(F64Arith.sub(x0, five()))
      +min_y = F64Repr.floor(F64Arith.sub(y0, five()))
      +span_x = F64Arith.sub(F64Repr.ceil(F64Arith.add(x1, five())), min_x)
      +span_y = F64Arith.sub(F64Repr.ceil(F64Arith.add(y1, five())), min_y)
      +wide = F64Cmp.lt(span_y, span_x)
      +pad_y = F64Repr.pick(wide, F64Arith.div(F64Arith.sub(span_x, span_y), F64Repr.two()), F64Repr.zero())
      +pad_x = F64Repr.pick(wide, F64Repr.zero(), F64Arith.div(F64Arith.sub(span_y, span_x), F64Repr.two()))
      +dx = F64Repr.pick(wide, F64Repr.neg(min_x), F64Arith.add(F64Repr.neg(min_x), pad_x))
      +dy = F64Repr.pick(wide, F64Arith.add(F64Repr.neg(min_y), pad_y), F64Repr.neg(min_y))
      Frame{shifted(order, s, dx, dy), F64Cmp.max(span_x, span_y)}

def bucket_of(+v: F64Repr.F64, +w: F64Repr.F64) -> U32:
  F64Repr.to_i32(F64Cmp.max(F64Repr.zero(), F64Repr.floor(F64Arith.mul(F64Arith.div(v, w), three()))))

def bump_at(counts: List<&2, U32>, +i: U32) -> List<&2, U32>:
  match counts:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      Bool.pick(U32, U32.is_zero(i), (c + 1 : U32), c) <> bump_at(rest, (i - 1 : U32))

def counted(points: List<&2, Pt>, +w: F64Repr.F64, +counts: List<&2, U32>) -> List<&2, U32>:
  match points:
    case Nil{}:
      counts
    case Con{+p, rest}:
      match p:
        case Pt{_, +x, +y}:
          counted(rest, w, bump_at(counts, ((bucket_of(x, w) * 3 : U32) + bucket_of(y, w) : U32)))

type Counts is Data:
  Counts{list: List<&2, U32>}

def count_lt(c: Counts, a: U32, b: U32) -> Counts & Bool:
  match c:
    case Counts{+list}:
      (Counts{list}, (StoryOrder.nth_or_last(list, a, 0) < StoryOrder.nth_or_last(list, b, 0) : U32))

def fill_from(xs: List<&2, U32>, arr: Array<U32>, +i: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      arr
    case Con{+x, rest}:
      fill_from(rest, StorySetpieces.written(arr, i, x), (i + 1 : U32))

def read_list(n: Nat, got: Array<U32> & U32, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      (arr, +v) = got
      v <> read_list(p, arr[(i + 1 : U32)], (i + 1 : U32))

def sorted_buckets(w: LuaSort.Sorting<Counts>) -> List<&2, U32>:
  match w:
    case LuaSort.Sorting{_, items, _}:
      read_list(2n, items[1], 1)

def sort_shuffled(sh: LuaUtil.Shuffled, +counts: List<&2, U32>, +s: StoryGraph.St) -> StoryGraph.Got:
  match sh:
    case LuaUtil.Shuffled{items, rng}:
      +order = read_list(9n, items[0], 0)
      +best = sorted_buckets(LuaSort.sort(~Counts, ~count_lt, Counts{counts}, fill_from(order, [0 : U32*16n], 1), 9, StoryGraph.none()))
      +first = StoryOrder.nth_or_last(best, 0, 0)
      StoryGraph.Got{Bool.pick(U32, U32.is_eq(first, 4), StoryOrder.nth_or_last(best, 1, 0), first), StoryGraph.with_rng(s, rng)}

# shuffleArray(bucket_counts) (8 draws) and table.sort by count: the chosen bucket (x - 1) * 3 + (y - 1), never the
# centre one.
def chosen_bucket(+s: StoryGraph.St, +counts: List<&2, U32>) -> StoryGraph.Got:
  sort_shuffled(LuaUtil.shuffle_array(fill_from([0, 1, 2, 3, 4, 5, 6, 7, 8], [0 : U32*16n], 0), 9, StoryGraph.rng_of(s)), counts, s)

def dist(+px: F64Repr.F64, +py: F64Repr.F64, +qx: F64Repr.F64, +qy: F64Repr.F64) -> F64Repr.F64:
  +dx = F64Arith.sub(px, qx)
  +dy = F64Arith.sub(py, qy)
  F64Arith.add(F64Arith.mul(dx, dx), F64Arith.mul(dy, dy))

type Best is Data:
  Best{pt: Pt, dist: F64Repr.F64}

def closer(+s: StoryGraph.St, +p: Pt, +exclude: U32, +px: F64Repr.F64, +py: F64Repr.F64, +b: Best) -> Best:
  match p:
    case Pt{+node, +x, +y}:
      match b:
        case Best{+pt, +d}:
          +allowed = U32.is_ne(StoryGraph.nf(s, node, StoryGraph.f_type()), Enums.node_type_blank()) && U32.is_ne(StoryGraph.nf(s, node, StoryGraph.f_task()), exclude)
          +here = dist(px, py, x, y)
          Bool.pick(Best, allowed && F64Cmp.lt(here, d), Best{Pt{node, x, y}, here}, Best{pt, d})

def closest_loop(points: List<&2, Pt>, +s: StoryGraph.St, +exclude: U32, +px: F64Repr.F64, +py: F64Repr.F64, +b: Best) -> Best:
  match points:
    case Nil{}:
      b
    case Con{+p, rest}:
      closest_loop(rest, s, exclude, px, py, closer(s, p, exclude, px, py, b))

def best_pt(+b: Best) -> Pt:
  match b:
    case Best{+pt, _}:
      pt

# GetClosestNode(point, exclude_task) over pairs(node_pos): the first strictly closest non-blank node.
def closest(+points: List<&2, Pt>, +s: StoryGraph.St, +exclude: U32, +px: F64Repr.F64, +py: F64Repr.F64) -> Pt:
  best_pt(closest_loop(points, s, exclude, px, py, Best{Pt{StoryGraph.none(), F64Repr.zero(), F64Repr.zero()}, F64Repr.inf()}))

def pt_node(+p: Pt) -> U32:
  match p:
    case Pt{+node, _, _}:
      node

def pt_dist(+p: Pt, +qx: F64Repr.F64, +qy: F64Repr.F64) -> F64Repr.F64:
  match p:
    case Pt{_, +x, +y}:
      dist(x, y, qx, qy)

# bucket_edge_pts[y][x] of a bucket: hex digits p1.x p1.y p2.x p2.y, each a multiple of w/3 (0, w/3, 2*w/3, w).
def edge_code(+bucket: U32) -> U32:
  match bucket:
    case 0:
      272
    case 1:
      258
    case 2:
      531
    case 3:
      4128
    case 5:
      4899
    case 6:
      8241
    case 7:
      12594
    case _:
      9010

def edge_coord(+code: U32, +k: U32, +w: F64Repr.F64) -> F64Repr.F64:
  +third = ((code >> U32.to_nat((12 - (k * 4 : U32) : U32))) .&. 3 : U32)
  Bool.pick(F64Repr.F64, U32.is_zero(third), F64Repr.zero(), Bool.pick(F64Repr.F64, U32.is_eq(third, 1), F64Arith.div(w, three()),
    Bool.pick(F64Repr.F64, U32.is_eq(third, 2), F64Arith.div(F64Arith.mul(F64Repr.two(), w), three()), w)))

type Ends is Data:
  Ends{a: U32, b: U32}

def best_nodes(+points: List<&2, Pt>, +s: StoryGraph.St, +bucket: U32, +count: U32, +w: F64Repr.F64) -> Ends:
  +code = edge_code(bucket)
  +p1x = edge_coord(code, 0, w)
  +p1y = edge_coord(code, 1, w)
  +p2x = edge_coord(code, 2, w)
  +p2y = edge_coord(code, 3, w)
  +empty = U32.is_zero(count)
  +outer_x = F64Arith.div(F64Arith.mul(F64Repr.from_u32((bucket / 3 : U32)), w), F64Repr.two())
  +outer_y = F64Arith.div(F64Arith.mul(F64Repr.from_u32((bucket % 3 : U32)), w), F64Repr.two())
  +c1 = closest(points, s, StoryGraph.none(), F64Repr.pick(empty, outer_x, p1x), F64Repr.pick(empty, outer_y, p1y))
  +swap = empty && Bool.not(F64Cmp.lt(pt_dist(c1, p1x, p1y), pt_dist(c1, p2x, p2y)))
  +c2 = closest(points, s, StoryGraph.nf(s, pt_node(c1), StoryGraph.f_task()), F64Repr.pick(swap, p1x, p2x), F64Repr.pick(swap, p1y, p2y))
  Ends{pt_node(c1), pt_node(c2)}

def found(+frame: Frame, +picked: StoryGraph.Got) -> Ends & StoryGraph.St:
  match frame:
    case Frame{+points, +w}:
      match picked:
        case StoryGraph.Got{+bucket, +s}:
          +counts = counted(points, w, [0, 0, 0, 0, 0, 0, 0, 0, 0])
          (best_nodes(points, s, bucket, StoryOrder.nth_or_last(counts, bucket, 0), w), s)

def framed_counts(+frame: Frame) -> List<&2, U32>:
  match frame:
    case Frame{+points, +w}:
      counted(points, w, [0, 0, 0, 0, 0, 0, 0, 0, 0])

# Story:FindMainlandNodesForNewRegion: GetSite for every node with a task, in pairs(TERRAIN) x pairs(task.nodes)
# order, then the two mainland nodes (c1, c2) the island links to.
def find_mainland(+s: StoryGraph.St) -> Ends & StoryGraph.St:
  +graphs = StoryGraph.graph_table_order(s, task_graphs(U32.to_nat(StoryGraph.get(s, StoryGraph.s_graphs())), s, 0))
  +inserted = sited(graphs, s)
  +s1 = get_sites(inserted, StoryGraph.say(s))
  +order = StoryGraph.node_table_order(s1, inserted)
  +frame = framed(order, s1, boxed(order, s1, Box{F64Repr.inf(), F64Repr.neg_inf(), F64Repr.inf(), F64Repr.neg_inf()}))
  found(frame, chosen_bucket(s1, framed_counts(frame)))

def region_sub(+i: U32) -> StoryGraph.Info:
  StoryGraph.NodeData{StoryGraph.id_region_sub(), 0, i, StoryGraph.none(), Enums.node_type_background(), Enums.tile_ocean_coastal(), Enums.connection_edge_site(), 0,
    StoryGraph.none(), StoryGraph.none(), StoryGraph.none(), StoryGraph.none(), 0, 0}

def region_added(+prev: U32, +added: StoryGraph.Got) -> StoryGraph.Got:
  match added:
    case StoryGraph.Got{+node, +s}:
      StoryGraph.Got{node, StoryGraph.link_if(U32.is_ne(prev, StoryGraph.none()), s, prev, node)}

# n region sub nodes of graph g, each linked to the one before; `walk` holds the last node and the state.
def link_nodes(n: Nat, +walk: StoryGraph.Got, +g: U32, +i: U32) -> StoryGraph.St:
  match n:
    case 0n:
      StoryGraph.st(walk)
    case 1n+p:
      match walk:
        case StoryGraph.Got{+prev, +s}:
          link_nodes(p, region_added(prev, StoryGraph.add_node(StoryGraph.graph_child(s, g), g, region_sub(i))), g, (i + 1 : U32))

def region_joined(+s: StoryGraph.St, +g: U32, +from: U32, +to: U32) -> StoryGraph.St:
  +first = StoryGraph.gf(s, g, StoryGraph.g_first())
  +third = StoryGraph.nf(s, StoryGraph.nf(s, first, StoryGraph.f_next()), StoryGraph.f_next())
  StoryGraph.bump(StoryGraph.lock(StoryGraph.lock(StoryGraph.link(s, first, StoryGraph.gf(s, g, StoryGraph.g_last())), from, first), third, to), StoryGraph.s_region_links())

def region_linked(+made: StoryGraph.Got, +from: U32, +to: U32) -> StoryGraph.St:
  match made:
    case StoryGraph.Got{+g, +m}:
      region_joined(link_nodes(4n, StoryGraph.Got{StoryGraph.none(), StoryGraph.graph_child(m, g)}, g, 1), g, from, to)

# Story:LinkRegions(from, to): a REGION_LINK graph of four OCEAN_COASTAL nodes in a ring, locked to both ends.
def link_regions(+s: StoryGraph.St, +from: U32, +to: U32) -> StoryGraph.St:
  +k = StoryGraph.get(s, StoryGraph.s_region_links())
  region_linked(StoryGraph.new_graph(s, StoryGraph.k_region_link(), k, StoryData.impassable_value(), StoryData.region_link_room()), from, to)

def island_linked(+region: StoryLink.Region, +ends: Ends, +graphs: List<&2, U32>, +plan: StoryPlan.Plan) -> StoryGraph.St:
  match ends:
    case Ends{+c1, +c2}:
      +s = StoryLink.region_st(region)
      +order = StoryGraph.graph_table_order(s, graphs)
      +placed = StorySetpieces.insert_set_pieces(Background.add_cove_nodes(s, order), order, plan)
      +linked = link_regions(link_regions(placed, c1, StoryLink.region_entrance(region)), c2, StoryLink.region_final(region))
      StoryGraph.call(StoryGraph.call(linked, StoryGraph.m_add_new_positions()), StoryGraph.m_voronoi_pass())

def island(found: Ends & StoryGraph.St, +tasks: List<&2, U32>, +plan: StoryPlan.Plan) -> StoryGraph.St:
  (+ends, +s) = found
  +graphs = StoryLink.graphs_after(tasks, StoryGraph.get(s, StoryGraph.s_graphs()))
  island_linked(StoryLink.generate_region(s, tasks, True{}), ends, graphs, plan)

# Story:AddRegionsToMainland for the island region (tasks in pairs(region_tasksets.island1) order), with
# on_region_added_fn's WorldGen_AddNewPositions and VoronoiPass(50).
def add_regions(+s: StoryGraph.St, +tasks: List<&2, U32>, +plan: StoryPlan.Plan) -> StoryGraph.St:
  +before = StoryGraph.rng_of(s)
  StoryGraph.returned(island(find_mainland(s), tasks, plan), StoryGraph.f_add_regions_to_mainland(), before)
