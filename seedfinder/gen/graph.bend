import Base
import ../storygen/graph.bend as GG
import ../worldsim/layout/hops.bend as KH
import ../worldsim/tiles/table.bend as TB

# The C++ side of the story's WorldSim calls (boostmap.cpp). A Boost vertex is made when AddLink first names a node
# (its second argument first); edges are undirected, kept in insertion order with AddLink's first argument as the
# source. AddChild of an existing id replaces the object, so a node's parent is the graph object current at its
# AddChild; graph objects are numbered in AddChild order.

type Link is Data:
  Link{s: U32, t: U32}

# The graph after a prefix of the log: vertex count, the story node of each vertex, the edges, per story node its
# vertex and its parent object (NONE when absent), and the graph of each object.
type Klei is Data:
  Klei{count: U32, vertices: List<&2, U32>, edges: List<&2, Link>, vertex_of: TB.Tree<U32>, parent_of: TB.Tree<U32>, graphs: List<&2, U32>}

def none() -> U32:
  4294967295

def parent_slot(+n: U32) -> U32:
  (4096 + n : U32)

def graph_slot(+g: U32) -> U32:
  (8192 + g : U32)

type Fold is Type:
  Fold{a: Array<U32>, n: U32, objects: U32, vertices: List<&2, U32>, edges: List<&2, Link>, graphs: List<&2, U32>}

type Named is Type:
  Named{f: Fold, v: U32}

def vertex_named(fresh: Bool, a: Array<U32>, +v: U32, +node: U32, +n: U32, +objects: U32, +vertices: List<&2, U32>, +edges: List<&2, Link>, +graphs: List<&2, U32>) -> Named:
  match fresh:
    case True{}:
      Named{Fold{a[node] <- n, (n + 1 : U32), objects, node <> vertices, edges, graphs}, n}
    case False{}:
      Named{Fold{a, n, objects, vertices, edges, graphs}, v}

def vertex_read(got: Array<U32> & U32, +node: U32, +n: U32, +objects: U32, +vertices: List<&2, U32>, +edges: List<&2, Link>, +graphs: List<&2, U32>) -> Named:
  (a, +v) = got
  vertex_named(U32.is_eq(v, none()), a, v, node, n, objects, vertices, edges, graphs)

def vertex(f: Fold, +node: U32) -> Named:
  match f:
    case Fold{a, +n, +objects, +vertices, +edges, +graphs}:
      vertex_read(a[node], node, n, objects, vertices, edges, graphs)

def with_edge(na: Named, +vb: U32) -> Fold:
  match na:
    case Named{f, +va}:
      match f:
        case Fold{a, +n, +objects, +vertices, +edges, +graphs}:
          Fold{a, n, objects, vertices, Link{va, vb} <> edges, graphs}

def second_named(nb: Named, +from: U32) -> Fold:
  match nb:
    case Named{f, +vb}:
      with_edge(vertex(f, from), vb)

def link(f: Fold, +from: U32, +to: U32) -> Fold:
  second_named(vertex(f, to), from)

def new_object(f: Fold, +g: U32) -> Fold:
  match f:
    case Fold{a, +n, +objects, +vertices, +edges, +graphs}:
      Fold{a[graph_slot(g)] <- objects, n, (objects + 1 : U32), vertices, edges, g <> graphs}

def parent_read(got: Array<U32> & U32, +node: U32, +n: U32, +objects: U32, +vertices: List<&2, U32>, +edges: List<&2, Link>, +graphs: List<&2, U32>) -> Fold:
  (a, +o) = got
  Fold{a[parent_slot(node)] <- o, n, objects, vertices, edges, graphs}

def node_added(f: Fold, +s: GG.St, +node: U32) -> Fold:
  match f:
    case Fold{a, +n, +objects, +vertices, +edges, +graphs}:
      parent_read(a[graph_slot(GG.nf(s, node, GG.f_graph()))], node, n, objects, vertices, edges, graphs)

def on_event(+ev: GG.Ev, f: Fold, +s: GG.St) -> Fold:
  match ev:
    case GG.EGraph{+g, _}:
      new_object(f, g)
    case GG.ENode{+node, _}:
      node_added(f, s, node)
    case GG.ELink{_, +from, +to, _}:
      link(f, from, to)
    case GG.ECall{_, _}:
      f
    case GG.ELua{_, _, _}:
      f

def fold(evs: List<&2, GG.Ev>, f: Fold, +s: GG.St) -> Fold:
  match evs:
    case Nil{}:
      f
    case Con{+ev, rest}:
      fold(rest, on_event(ev, f, s), s)

def listed(got: Array<U32> & U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  (a, +v) = got
  (a, v <> acc)

def list_loop(fuel: Nat, +at: U32, got: Array<U32> & List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match fuel:
    case 0n:
      got
    case 1n+f:
      (a, acc) = got
      list_loop(f, (at - 1 : U32), listed(a[at], acc))

def slots(a: Array<U32>, +base: U32, +count: U32) -> Array<U32> & List<&2, U32>:
  list_loop(U32.to_nat(count), ((base + count : U32) - 1 : U32), (a, Nil{}))

def parents_done(got: Array<U32> & List<&2, U32>, +vs: List<&2, U32>, +n: U32, +vertices: List<&2, U32>, +edges: List<&2, Link>, +graphs: List<&2, U32>) -> Klei:
  (_, +ps) = got
  Klei{n, List.reverse(&2, U32, vertices), List.reverse(&2, Link, edges), TB.from_list(~U32, vs, none()), TB.from_list(~U32, ps, none()),
    List.reverse(&2, U32, graphs)}

def with_parents(got: Array<U32> & List<&2, U32>, +count: U32, +n: U32, +vertices: List<&2, U32>, +edges: List<&2, Link>, +graphs: List<&2, U32>) -> Klei:
  (a, +vs) = got
  parents_done(slots(a, parent_slot(0), count), vs, n, vertices, edges, graphs)

def folded(f: Fold, +count: U32) -> Klei:
  match f:
    case Fold{a, +n, _, +vertices, +edges, +graphs}:
      with_parents(slots(a, 0, count), count, n, vertices, edges, graphs)

# The Boost graph and the Klei objects after every WorldSim call the story state has logged.
def klei(+s: GG.St) -> Klei:
  start = {Fold{[4294967295 : U32^14n], 0, 0, Nil{}, Nil{}, Nil{}} : Fold}
  folded(fold(List.reverse(&2, GG.Ev, GG.log_of(s)), start, s), GG.get(s, GG.s_nodes()))

def count_of(+k: Klei) -> U32:
  match k:
    case Klei{+n, _, _, _, _, _}:
      n

def vertices_of(+k: Klei) -> List<&2, U32>:
  match k:
    case Klei{_, +vs, _, _, _, _}:
      vs

def edges_of(+k: Klei) -> List<&2, Link>:
  match k:
    case Klei{_, _, +es, _, _, _}:
      es

# The vertex of story node n (NONE when no AddLink named it).
def vertex_of(+k: Klei, +n: U32) -> U32:
  match k:
    case Klei{_, _, _, +t, _, _}:
      TB.at(~U32, t, n)

def vertex_table(+k: Klei) -> TB.Tree<U32>:
  match k:
    case Klei{_, _, _, +t, _, _}:
      t

# The object number of story node n's parent (NONE when its graph had no AddChild yet).
def parent_of(+k: Klei, +n: U32) -> U32:
  match k:
    case Klei{_, _, _, _, +t, _}:
      TB.at(~U32, t, n)

def graphs_of(+k: Klei) -> List<&2, U32>:
  match k:
    case Klei{_, _, _, _, _, +gs}:
      gs

def arcs_of(es: List<&2, Link>) -> List<&2, KH.Arc>:
  match es:
    case Nil{}:
      Nil{}
    case Con{Link{+s, +t}, rest}:
      KH.Arc{s, t} <> KH.Arc{t, s} <> arcs_of(rest)

# KK's input: every edge in both directions.
def arcs(+k: Klei) -> List<&2, KH.Arc>:
  arcs_of(edges_of(k))

# boost::out_edges(v) targets: for each edge in insertion order, the other end if v is an end (twice for a loop).
def targets(es: List<&2, Link>, +v: U32) -> List<&2, U32>:
  match es:
    case Nil{}:
      Nil{}
    case Con{Link{+s, +t}, rest}:
      +tail = targets(rest, v)
      +back = Bool.pick(List<&2, U32>, U32.is_eq(t, v), s <> tail, tail)
      Bool.pick(List<&2, U32>, U32.is_eq(s, v), t <> back, back)

def adjacency_loop(n: Nat, +es: List<&2, Link>, +v: U32) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      targets(es, v) <> adjacency_loop(p, es, (v + 1 : U32))

# Every vertex's out-edge targets, in vertex order.
def adjacency(+count: U32, +es: List<&2, Link>) -> List<&2, List<&2, U32>>:
  adjacency_loop(U32.to_nat(count), es, 0)

def kept(es: List<&2, Link>, +cut: TB.Tree<U32>) -> List<&2, Link>:
  match es:
    case Nil{}:
      Nil{}
    case Con{Link{+s, +t}, rest}:
      +tail = kept(rest, cut)
      +keep = U32.is_zero((TB.at(~U32, cut, s) .|. TB.at(~U32, cut, t) : U32))
      Bool.pick(List<&2, Link>, keep, Link{s, t} <> tail, tail)

# The edges left after ClearNodeLinks of every vertex whose `cut` entry is non-zero.
def cleared(+es: List<&2, Link>, +cut: TB.Tree<U32>) -> List<&2, Link>:
  kept(es, cut)
