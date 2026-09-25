import Base
import ./space.bend as KS

# All-pairs hop counts of the layout graph, as Boost's johnson_all_pairs_shortest_paths computes them for unit
# edge weights (exact integers, so one BFS per source). The graph comes as directed arcs (from, to), every
# undirected edge in both directions, and is stored as CSR in the workspace.

type Arc is Data:
  Arc{from: U32, to: U32}

def unreachable() -> U32:
  4294967295

def clear_starts(fuel: Nat, +v: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      ws[KS.start_at(v)] <- 0
      clear_starts(f, (v + 1 : U32), ws)

def bump(got: Array<U32> & U32, +at: U32) -> Array<U32>:
  (ws, c) = got
  ws[at] <- (c + 1 : U32)

def count_arcs(arcs: List<&2, Arc>, ws: Array<U32>) -> Array<U32>:
  match arcs:
    case Nil{}:
      ws
    case Con{Arc{from, to}, rest}:
      +at = KS.start_at((from + 1 : U32))
      count_arcs(rest, bump(ws[at], at))

def bump_by(got: Array<U32> & U32, +at: U32, +total: U32) -> Array<U32> & U32:
  (ws, c) = got
  +sum = (c + total : U32)
  (ws[at] <- sum, sum)

def accumulate(got: Array<U32> & U32, +v: U32) -> Array<U32> & U32:
  (ws, total) = got
  bump_by(ws[KS.start_at(v)], KS.start_at(v), total)

def prefix_sums(fuel: Nat, +v: U32, got: Array<U32> & U32) -> Array<U32>:
  match fuel:
    case 0n:
      Pair.fst(Array<U32>, U32, got)
    case 1n+f:
      prefix_sums(f, (v + 1 : U32), accumulate(got, v))

def copy_cursor(got: Array<U32> & U32, +v: U32) -> Array<U32>:
  (ws, s) = got
  ws[KS.queue_at(v)] <- s

def cursors(fuel: Nat, +v: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      cursors(f, (v + 1 : U32), copy_cursor(ws[KS.start_at(v)], v))

def place(got: Array<U32> & U32, +from: U32, +to: U32) -> Array<U32>:
  (ws, +k) = got
  ws[KS.arc_at(k)] <- to
  ws[KS.queue_at(from)] <- (k + 1 : U32)

def fill_arcs(arcs: List<&2, Arc>, ws: Array<U32>) -> Array<U32>:
  match arcs:
    case Nil{}:
      ws
    case Con{Arc{+from, to}, rest}:
      fill_arcs(rest, place(ws[KS.queue_at(from)], from, to))

# Stores the CSR adjacency of n vertices: starts at KS.start_at(0..n), targets at KS.arc_at.
def load_arcs(+n: U32, +arcs: List<&2, Arc>, ws: Array<U32>) -> Array<U32>:
  +m = U32.to_nat((n + 1 : U32))
  counted = count_arcs(arcs, clear_starts(m, 0, ws))
  fill_arcs(arcs, cursors(U32.to_nat(n), 0, prefix_sums(m, 0, (counted, 0))))

type Bfs is Type:
  Bfs{ws: Array<U32>, head: U32, tail: U32}

def clear_row(fuel: Nat, +s: U32, +v: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      ws[KS.hop_at(s, v)] <- unreachable()
      clear_row(f, s, (v + 1 : U32), ws)

def mark(fresh: Bool, ws: Array<U32>, +s: U32, +w: U32, +hop: U32, +head: U32, +tail: U32) -> Bfs:
  match fresh:
    case True{}:
      ws[KS.hop_at(s, w)] <- hop
      ws[KS.queue_at(tail)] <- w
      Bfs{ws, head, (tail + 1 : U32)}
    case False{}:
      Bfs{ws, head, tail}

def visit_hop(got: Array<U32> & U32, +s: U32, +w: U32, +hop: U32, +head: U32, +tail: U32) -> Bfs:
  (ws, h) = got
  mark(U32.is_eq(h, unreachable()), ws, s, w, hop, head, tail)

def visit_arc(got: Array<U32> & U32, +s: U32, +hop: U32, +head: U32, +tail: U32) -> Bfs:
  (ws, +w) = got
  visit_hop(ws[KS.hop_at(s, w)], s, w, hop, head, tail)

def visit(st: Bfs, +k: U32, +s: U32, +hop: U32) -> Bfs:
  match st:
    case Bfs{ws, +head, +tail}:
      visit_arc(ws[KS.arc_at(k)], s, hop, head, tail)

def visit_arcs(fuel: Nat, +k: U32, +s: U32, +hop: U32, st: Bfs) -> Bfs:
  match fuel:
    case 0n:
      st
    case 1n+f:
      visit_arcs(f, (k + 1 : U32), s, hop, visit(st, k, s, hop))

def expand_end(got: Array<U32> & U32, +first: U32, +s: U32, +hop: U32, +head: U32, +tail: U32) -> Bfs:
  (ws, +last) = got
  visit_arcs(U32.to_nat((last - first : U32)), first, s, hop, Bfs{ws, head, tail})

def expand_start(got: Array<U32> & U32, +u: U32, +s: U32, +hop: U32, +head: U32, +tail: U32) -> Bfs:
  (ws, +first) = got
  expand_end(ws[KS.start_at((u + 1 : U32))], first, s, hop, head, tail)

def expand_hop(got: Array<U32> & U32, +u: U32, +s: U32, +head: U32, +tail: U32) -> Bfs:
  (ws, h) = got
  expand_start(ws[KS.start_at(u)], u, s, (h + 1 : U32), head, tail)

def expand_vertex(got: Array<U32> & U32, +s: U32, +head: U32, +tail: U32) -> Bfs:
  (ws, +u) = got
  expand_hop(ws[KS.hop_at(s, u)], u, s, head, tail)

def dequeue(pending: Bool, ws: Array<U32>, +s: U32, +head: U32, +tail: U32) -> Bfs:
  match pending:
    case True{}:
      expand_vertex(ws[KS.queue_at(head)], s, (head + 1 : U32), tail)
    case False{}:
      Bfs{ws, head, tail}

def bfs_loop(fuel: Nat, +s: U32, st: Bfs) -> Bfs:
  match fuel:
    case 0n:
      st
    case 1n+f:
      match st:
        case Bfs{ws, +head, +tail}:
          bfs_loop(f, s, dequeue((head < tail : U32), ws, s, head, tail))

def bfs_ws(st: Bfs) -> Array<U32>:
  match st:
    case Bfs{ws, head, tail}:
      ws

def bfs(+n: U32, +s: U32, ws: Array<U32>) -> Array<U32>:
  cleared = clear_row(U32.to_nat(n), s, 0, ws)
  seeded = cleared[KS.hop_at(s, s)] <- 0
  queued = seeded[KS.queue_at(0)] <- s
  bfs_ws(bfs_loop(U32.to_nat(n), s, Bfs{queued, 0, 1}))

def all_sources(fuel: Nat, +n: U32, +s: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      all_sources(f, n, (s + 1 : U32), bfs(n, s, ws))

# Fills the hop matrix (KS.hop_at(u, v), unreachable() when there is no path) for the stored CSR graph.
def hop_matrix(+n: U32, ws: Array<U32>) -> Array<U32>:
  all_sources(U32.to_nat(n), n, 0, ws)

def reached(got: Array<U32> & U32, +all: Bool) -> Array<U32> & Bool:
  (ws, h) = got
  (ws, all && Bool.not(U32.is_eq(h, unreachable())))

def scan_row(fuel: Nat, +v: U32, got: Array<U32> & Bool) -> Array<U32> & Bool:
  match fuel:
    case 0n:
      got
    case 1n+f:
      (ws, +all) = got
      scan_row(f, (v + 1 : U32), reached(ws[KS.hop_at(0, v)], all))

# Whether every vertex is reachable from vertex 0 (Boost's KK fails on a disconnected graph).
def connected(+n: U32, ws: Array<U32>) -> Array<U32> & Bool:
  scan_row(U32.to_nat(n), 0, (ws, True{}))
