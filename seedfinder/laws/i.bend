import Base
import ../worldsim/tiles/table.bend as TileTable
import ../gen/graph.bend as GenGraph
import ../f64/repr.bend as F64Repr
import ../gen/centi.bend as Centi
import ../search/order.bend as SearchOrder
import ../search/threads.bend as SearchThreads

# Integration (gen/, M11) laws. Goldens from Boost's undirected adjacency_list semantics (out-edge lists in insertion
# order) and ClearNodeLinks (every edge at a cleared vertex removed).

# boost::out_edges of vertex 0 in an undirected adjacency_list: its edges in insertion order, the other end of each.
law gen_out_edges_insertion_order:
  {GenGraph.targets([GenGraph.Link{0, 1}, GenGraph.Link{2, 0}, GenGraph.Link{1, 2}, GenGraph.Link{0, 3}], 0) == [1, 2, 3] : List<&2, U32>}

def gen_out_edges_insertion_order():
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
