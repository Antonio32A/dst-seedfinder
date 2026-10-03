import Base
import ../worldsim/tiles/table.bend as TileTable
import ../gen/graph.bend as GenGraph
import ../gen/world.bend as GenWorld
import ../worldsim/tiles/world.bend as TileWorld
import ../f64/repr.bend as F64Repr
import ../gen/centi.bend as Centi
import ../search/order.bend as SearchOrder
import ../search/threads.bend as SearchThreads
import ../search/bins.bend as SearchBins

# Integration (gen/, M11) laws. Goldens from Boost's undirected adjacency_list semantics (out-edge lists in insertion
# order) and ClearNodeLinks (every edge at a cleared vertex removed).

# boost::out_edges of vertex 0 in an undirected adjacency_list: its edges in insertion order, the other end of each.
law gen_out_edges_insertion_order:
  {GenGraph.targets([GenGraph.Link{0, 1}, GenGraph.Link{2, 0}, GenGraph.Link{1, 2}, GenGraph.Link{0, 3}], 0) == [1, 2, 3] : List<&2, U32>}

def gen_out_edges_insertion_order():
  {==}

# Every vertex's out-edge list equals boost::out_edges of it, a self loop twice and an edge past the vertex count ignored.
def gen_adjacency_edges() -> List<&2, GenGraph.Link>:
  [GenGraph.Link{0, 1}, GenGraph.Link{2, 0}, GenGraph.Link{1, 2}, GenGraph.Link{0, 3}, GenGraph.Link{2, 2}, GenGraph.Link{3, 5}, GenGraph.Link{1, 0}]

law gen_adjacency_out_edges:
  {GenGraph.adjacency(4, gen_adjacency_edges()) == [GenGraph.targets(gen_adjacency_edges(), 0), GenGraph.targets(gen_adjacency_edges(), 1), GenGraph.targets(gen_adjacency_edges(), 2), GenGraph.targets(gen_adjacency_edges(), 3)] : List<&2, List<&2, U32>>}

def gen_adjacency_out_edges():
  {==}

def gen_cell(+src: U32, +twin: U32) -> TileWorld.Cell:
  TileWorld.Cell{src, [TileWorld.VEdge{twin, None{}, None{}, Nil{}}]}

# Each site's cell is the first cell with its source, and a site without one gets no cell.
law gen_cells_by_site:
  {GenWorld.by_site(4, [gen_cell(2, 7), gen_cell(0, 1), gen_cell(2, 9), gen_cell(3, 4)]) == [gen_cell(0, 1), GenWorld.no_cell(), gen_cell(2, 7), gen_cell(3, 4)] : List<&2, TileWorld.Cell>}

def gen_cells_by_site():
  {==}

# ApplyPoisonTag's ClearNodeLinks of vertex 2 removes both edges at it and keeps the order of the rest.
law gen_clear_node_links:
  {GenGraph.cleared([GenGraph.Link{0, 1}, GenGraph.Link{2, 0}, GenGraph.Link{1, 2}], TileTable.from_list(~U32, [0, 0, 1], 0)) == [GenGraph.Link{0, 1}] : List<&2, GenGraph.Link>}

def gen_clear_node_links():
  {==}

# Savedata positions as the dump mod prints them, printf("%.2f") on glibc (goldens: Python's '%.2f', the same
# correctly rounded conversion): 1.005 is just below its tie, 0.125 an exact tie (to even), -2.675 just above.
law gen_centi_below_tie:
  {Centi.centi(F64Repr.F64{1072698490, 3779571220}, False{}) == 100 : U32}

def gen_centi_below_tie():
  {==}

law gen_centi_exact_tie:
  {Centi.centi(F64Repr.F64{1069547520, 0}, False{}) == 12 : U32}

def gen_centi_exact_tie():
  {==}

law gen_centi_negative:
  {Centi.centi(F64Repr.F64{3221579366, 1717986918}, False{}) == 4294967029 : U32}

def gen_centi_negative():
  {==}

# Decided candidates wait in scan order from the start seed, across the 2^32 wrap: from 4294967290 the order is
# 4294967295, 1, 3.
law gen_scan_order_wraps:
  {SearchOrder.merged(~U32, ~SearchOrder.seed_itself, [3, 4294967295], [1], 4294967290) == [4294967295, 1, 3] : List<&2, U32>}

def gen_scan_order_wraps():
  {==}

# The runtime's own --threads flag comes before `--`; a --threads after it belongs to the program (none: 0).
law gen_threads_flag:
  {SearchThreads.flag_in(["seedfinder", "--threads", "16", "--", "world", "--threads", "3"]) == 16 : U32}

def gen_threads_flag():
  {==}

# A sysfs cpu list "0-3,8-11" holds 8 CPUs.
law gen_threads_cpu_list:
  {SearchThreads.cpus_in(["0-3", "8-11"]) == 8 : U32}

def gen_threads_cpu_list():
  {==}

# The default thread count respects the cgroup CPU quota: cpu.max "1360000 100000" (13.6 cores) caps 64 CPUs at 14.
law gen_threads_quota:
  {SearchThreads.capped(64, SearchThreads.quota_cores(["1360000", "100000"])) == 14 : U32}

def gen_threads_quota():
  {==}

# cpu.max "max 100000" is no quota: the online CPUs stay.
law gen_threads_no_quota:
  {SearchThreads.capped(64, SearchThreads.quota_cores(["max", "100000"])) == 64 : U32}

def gen_threads_no_quota():
  {==}

# A round's bins: the heaviest slot first, each to the least loaded bin, and the bins laid out heaviest first in the
# cube's order (leaf 1 to 7 of a row, then its leaf 0, then the next row).
law search_bins_one_slot_each:
  {SearchBins.placed_leaves([10, 300, 20, 300, 5]) == [4n, 1n, 3n, 2n, 5n] : List<&2, Nat>}

def search_bins_one_slot_each():
  {==}

law search_bins_rows_in_order:
  {SearchBins.placed_leaves([9, 8, 7, 6, 5, 4, 3, 2, 1, 50]) == [2n, 3n, 4n, 5n, 6n, 7n, 0n, 9n, 10n, 1n] : List<&2, Nat>}

def search_bins_rows_in_order():
  {==}
