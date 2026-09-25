import Base
import ../lua/util.bend as LU
import ../lua/sort.bend as LO
import ../lua/table.bend as LT
import ../level/summary.bend as W
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ../data/story.bend as SY
import ../data/enums.bend as EN
import ./graph.bend as GG
import ./order.bend as GO
import ./link.bend as GL
import ./background.bend as GB
import ./setpieces.bend as GP

# Story:AddRegionsToMainland for the moon island: FindMainlandNodesForNewRegion (the geometry-dependent choice of the
# two mainland nodes the island links to), GenerateNodesForRegion (RestrictNodesByKey), coves, set pieces and two
# LinkRegions. The geometry is WorldSim:GetSite after VoronoiPass(100): f32 x, y bits of node n at GG.site_base() + 2n
# (the trace fills them from the oracle; the generator will fill them from the Voronoi stage).

type Pt is Data:
  Pt{node: U32, x: FR.F64, y: FR.F64}

def site_x(+s: GG.St, +n: U32) -> FR.F64:
  FR.from_f32_bits(GG.get(s, (GG.site_base() + (n * 2 : U32) : U32)))

def site_y(+s: GG.St, +n: U32) -> FR.F64:
  FR.from_f32_bits(GG.get(s, ((GG.site_base() + (n * 2 : U32) : U32) + 1 : U32)))

def task_graphs(n: Nat, +s: GG.St, +g: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +tail = task_graphs(p, s, (g + 1 : U32))
      Bool.pick(List<&2, U32>, U32.is_eq(GG.gf(s, g, GG.g_kind()), GG.k_task()), g <> tail, tail)

def with_task(+s: GG.St, nodes: List<&2, U32>) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      +tail = with_task(s, rest)
      Bool.pick(List<&2, U32>, U32.is_ne(GG.nf(s, n, GG.f_task()), GG.none()), n <> tail, tail)

def sited(graphs: List<&2, U32>, +s: GG.St) -> List<&2, U32>:
  match graphs:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      List.append(&2, U32, with_task(s, GG.node_order(s, g)), sited(rest, s))

def get_sites(nodes: List<&2, U32>, +s: GG.St) -> GG.St:
  match nodes:
    case Nil{}:
      s
    case Con{_, rest}:
      get_sites(rest, GG.call(s, GG.m_get_site()))

type Box is Data:
  Box{min_x: FR.F64, max_x: FR.F64, min_y: FR.F64, max_y: FR.F64}

def boxed(nodes: List<&2, U32>, +s: GG.St, +b: Box) -> Box:
  match nodes:
    case Nil{}:
      b
    case Con{+n, rest}:
      match b:
        case Box{+x0, +x1, +y0, +y1}:
          +x = site_x(s, n)
          +y = site_y(s, n)
          boxed(rest, s, Box{FC.min(x, x0), FC.max(x, x1), FC.min(y, y0), FC.max(y, y1)})

def five() -> FR.F64:
  FR.from_u32(5)

def three() -> FR.F64:
  FR.from_u32(3)

def shifted(nodes: List<&2, U32>, +s: GG.St, +dx: FR.F64, +dy: FR.F64) -> List<&2, Pt>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      Pt{n, FA.add(site_x(s, n), dx), FA.add(site_y(s, n), dy)} <> shifted(rest, s, dx, dy)

type Frame is Data:
  Frame{points: List<&2, Pt>, w: FR.F64}

def framed(+order: List<&2, U32>, +s: GG.St, +b: Box) -> Frame:
  match b:
    case Box{+x0, +x1, +y0, +y1}:
      +min_x = FR.floor(FA.sub(x0, five()))
      +min_y = FR.floor(FA.sub(y0, five()))
      +span_x = FA.sub(FR.ceil(FA.add(x1, five())), min_x)
      +span_y = FA.sub(FR.ceil(FA.add(y1, five())), min_y)
      +wide = FC.lt(span_y, span_x)
      +pad_y = FR.pick(wide, FA.div(FA.sub(span_x, span_y), FR.two()), FR.zero())
      +pad_x = FR.pick(wide, FR.zero(), FA.div(FA.sub(span_y, span_x), FR.two()))
      +dx = FR.pick(wide, FR.neg(min_x), FA.add(FR.neg(min_x), pad_x))
      +dy = FR.pick(wide, FA.add(FR.neg(min_y), pad_y), FR.neg(min_y))
      Frame{shifted(order, s, dx, dy), FC.max(span_x, span_y)}

def bucket_of(+v: FR.F64, +w: FR.F64) -> U32:
  FR.to_i32(FC.max(FR.zero(), FR.floor(FA.mul(FA.div(v, w), three()))))

def bump_at(counts: List<&2, U32>, +i: U32) -> List<&2, U32>:
  match counts:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      Bool.pick(U32, U32.is_zero(i), (c + 1 : U32), c) <> bump_at(rest, (i - 1 : U32))

def counted(points: List<&2, Pt>, +w: FR.F64, +counts: List<&2, U32>) -> List<&2, U32>:
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
      (Counts{list}, (GO.nth_or_last(list, a, 0) < GO.nth_or_last(list, b, 0) : U32))

def fill_from(xs: List<&2, U32>, arr: Array<U32>, +i: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      arr
    case Con{+x, rest}:
      fill_from(rest, GP.written(arr, i, x), (i + 1 : U32))

def read_list(n: Nat, got: Array<U32> & U32, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      (arr, +v) = got
      v <> read_list(p, arr[(i + 1 : U32)], (i + 1 : U32))

def sorted_buckets(w: LO.Sorting<Counts>) -> List<&2, U32>:
  match w:
    case LO.Sorting{_, items, _}:
      read_list(2n, items[1], 1)

def sort_shuffled(sh: LU.Shuffled, +counts: List<&2, U32>, +s: GG.St) -> GG.Got:
  match sh:
    case LU.Shuffled{items, rng}:
      +order = read_list(9n, items[0], 0)
      +best = sorted_buckets(LO.sort(~Counts, ~count_lt, Counts{counts}, fill_from(order, [0 : U32*16n], 1), 9, GG.none()))
      +first = GO.nth_or_last(best, 0, 0)
      GG.Got{Bool.pick(U32, U32.is_eq(first, 4), GO.nth_or_last(best, 1, 0), first), GG.with_rng(s, rng)}

# shuffleArray(bucket_counts) (8 draws) and table.sort by count: the chosen bucket (x - 1) * 3 + (y - 1), never the
# centre one.
def chosen_bucket(+s: GG.St, +counts: List<&2, U32>) -> GG.Got:
  sort_shuffled(LU.shuffle_array(fill_from([0, 1, 2, 3, 4, 5, 6, 7, 8], [0 : U32*16n], 0), 9, GG.rng_of(s)), counts, s)

def dist(+px: FR.F64, +py: FR.F64, +qx: FR.F64, +qy: FR.F64) -> FR.F64:
  +dx = FA.sub(px, qx)
  +dy = FA.sub(py, qy)
  FA.add(FA.mul(dx, dx), FA.mul(dy, dy))

type Best is Data:
  Best{pt: Pt, dist: FR.F64}

def closer(+s: GG.St, +p: Pt, +exclude: U32, +px: FR.F64, +py: FR.F64, +b: Best) -> Best:
  match p:
    case Pt{+node, +x, +y}:
      match b:
        case Best{+pt, +d}:
          +allowed = U32.is_ne(GG.nf(s, node, GG.f_type()), EN.node_type_blank()) && U32.is_ne(GG.nf(s, node, GG.f_task()), exclude)
          +here = dist(px, py, x, y)
          Bool.pick(Best, allowed && FC.lt(here, d), Best{Pt{node, x, y}, here}, Best{pt, d})

def closest_loop(points: List<&2, Pt>, +s: GG.St, +exclude: U32, +px: FR.F64, +py: FR.F64, +b: Best) -> Best:
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
def closest(+points: List<&2, Pt>, +s: GG.St, +exclude: U32, +px: FR.F64, +py: FR.F64) -> Pt:
  best_pt(closest_loop(points, s, exclude, px, py, Best{Pt{GG.none(), FR.zero(), FR.zero()}, FR.inf()}))

def pt_node(+p: Pt) -> U32:
  match p:
    case Pt{+node, _, _}:
      node

def pt_dist(+p: Pt, +qx: FR.F64, +qy: FR.F64) -> FR.F64:
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

def edge_coord(+code: U32, +k: U32, +w: FR.F64) -> FR.F64:
  +third = ((code >> U32.to_nat((12 - (k * 4 : U32) : U32))) .&. 3 : U32)
  Bool.pick(FR.F64, U32.is_zero(third), FR.zero(), Bool.pick(FR.F64, U32.is_eq(third, 1), FA.div(w, three()),
    Bool.pick(FR.F64, U32.is_eq(third, 2), FA.div(FA.mul(FR.two(), w), three()), w)))

type Ends is Data:
  Ends{a: U32, b: U32}

def best_nodes(+points: List<&2, Pt>, +s: GG.St, +bucket: U32, +count: U32, +w: FR.F64) -> Ends:
  +code = edge_code(bucket)
  +p1x = edge_coord(code, 0, w)
  +p1y = edge_coord(code, 1, w)
  +p2x = edge_coord(code, 2, w)
  +p2y = edge_coord(code, 3, w)
  +empty = U32.is_zero(count)
  +outer_x = FA.div(FA.mul(FR.from_u32((bucket / 3 : U32)), w), FR.two())
  +outer_y = FA.div(FA.mul(FR.from_u32((bucket % 3 : U32)), w), FR.two())
  +c1 = closest(points, s, GG.none(), FR.pick(empty, outer_x, p1x), FR.pick(empty, outer_y, p1y))
  +swap = empty && Bool.not(FC.lt(pt_dist(c1, p1x, p1y), pt_dist(c1, p2x, p2y)))
  +c2 = closest(points, s, GG.nf(s, pt_node(c1), GG.f_task()), FR.pick(swap, p1x, p2x), FR.pick(swap, p1y, p2y))
  Ends{pt_node(c1), pt_node(c2)}

def found(+frame: Frame, +picked: GG.Got) -> Ends & GG.St:
  match frame:
    case Frame{+points, +w}:
      +bucket = GG.val(picked)
      +s = GG.st(picked)
      +counts = counted(points, w, [0, 0, 0, 0, 0, 0, 0, 0, 0])
      (best_nodes(points, s, bucket, GO.nth_or_last(counts, bucket, 0), w), s)

def framed_counts(+frame: Frame) -> List<&2, U32>:
  match frame:
    case Frame{+points, +w}:
      counted(points, w, [0, 0, 0, 0, 0, 0, 0, 0, 0])

# Story:FindMainlandNodesForNewRegion: GetSite for every node with a task, in pairs(TERRAIN) x pairs(task.nodes)
# order, then the two mainland nodes (c1, c2) the island links to.
def find_mainland(+s: GG.St) -> Ends & GG.St:
  +graphs = GG.graph_table_order(s, task_graphs(U32.to_nat(GG.get(s, GG.s_graphs())), s, 0))
  +inserted = sited(graphs, s)
  +s1 = get_sites(inserted, GG.say(s))
  +order = GG.node_table_order(s1, inserted)
  +frame = framed(order, s1, boxed(order, s1, Box{FR.inf(), FR.neg_inf(), FR.inf(), FR.neg_inf()}))
  found(frame, chosen_bucket(s1, framed_counts(frame)))

def region_sub(+i: U32) -> GG.Info:
  GG.NodeData{GG.id_region_sub(), 0, i, GG.none(), EN.node_type_background(), EN.tile_ocean_coastal(), EN.connection_edge_site(), 0,
    GG.none(), GG.none(), GG.none(), GG.none(), 0, 0}

def link_nodes(n: Nat, +s: GG.St, +g: U32, +i: U32, +prev: U32) -> GG.St:
  match n:
    case 0n:
      s
    case 1n+p:
      +added = GG.add_node(GG.graph_child(s, g), g, region_sub(i))
      +node = GG.val(added)
      +s1 = GG.link_if(U32.is_ne(prev, GG.none()), GG.st(added), prev, node)
      link_nodes(p, s1, g, (i + 1 : U32), node)

def region_linked(+made: GG.Got, +from: U32, +to: U32) -> GG.St:
  +g = GG.val(made)
  +s = link_nodes(4n, GG.graph_child(GG.st(made), g), g, 1, GG.none())
  +first = GG.gf(s, g, GG.g_first())
  +third = GG.nf(s, GG.nf(s, first, GG.f_next()), GG.f_next())
  GG.bump(GG.lock(GG.lock(GG.link(s, first, GG.gf(s, g, GG.g_last())), from, first), third, to), GG.s_region_links())

# Story:LinkRegions(from, to): a REGION_LINK graph of four OCEAN_COASTAL nodes in a ring, locked to both ends.
def link_regions(+s: GG.St, +from: U32, +to: U32) -> GG.St:
  +k = GG.get(s, GG.s_region_links())
  region_linked(GG.new_graph(s, GG.k_region_link(), k, SY.impassable_value(), SY.region_link_room()), from, to)

def island_linked(+region: GL.Region, +ends: Ends, +graphs: List<&2, U32>, +level: W.Summary) -> GG.St:
  match ends:
    case Ends{+c1, +c2}:
      +s = GL.region_st(region)
      +order = GG.graph_table_order(s, graphs)
      +placed = GP.insert_set_pieces(GB.add_cove_nodes(s, order), order, level)
      +linked = link_regions(link_regions(placed, c1, GL.region_entrance(region)), c2, GL.region_final(region))
      GG.call(GG.call(linked, GG.m_add_new_positions()), GG.m_voronoi_pass())

def island(found: Ends & GG.St, +tasks: List<&2, U32>, +level: W.Summary) -> GG.St:
  (+ends, +s) = found
  +graphs = GL.graphs_after(tasks, GG.get(s, GG.s_graphs()))
  island_linked(GL.generate_region(s, tasks, True{}), ends, graphs, level)

# Story:AddRegionsToMainland for the island region (tasks in pairs(region_tasksets.island1) order), with
# on_region_added_fn's WorldGen_AddNewPositions and VoronoiPass(50).
def add_regions(+s: GG.St, +tasks: List<&2, U32>, +level: W.Summary) -> GG.St:
  +before = GG.rng_of(s)
  GG.returned(island(find_mainland(s), tasks, level), GG.f_add_regions_to_mainland(), before)
