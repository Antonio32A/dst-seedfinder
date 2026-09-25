import Base
import ../../f64/word.bend as FW
import ../../f64/repr.bend as FR
import ../../stl/sort.bend as SS
import ../../stl/heap.bend as SH
import ./predicates.bend as VP
import ./lazy.bend as VL
import ./diagram.bend as VD

# Boost.Polygon 1.52 voronoi_builder<int32>::construct: site events sorted with the platform's std::sort and
# made unique, the sweep over site and circle events, and the diagram's _build. The beach line is a linked list in
# std::map order: the lower_bound comparator is monotone and every hinted insert lands right before its hint
# (checked by the reference harness), so position inserts reproduce the map. The circle event queue is the
# libstdc++ / VC9 binary heap (identical on both platforms) over event ids.

# A beach line node: its key (left and right site), its edge (or nil), its circle event (or nil) and an id.
type Node is Data:
  Node{left: VP.Site, right: VP.Site, edge: U32, circle: U32, id: U32}

type Pending is Data:
  Pending{c: VP.Circle, active: Bool, node: U32}

type End is Data:
  End{p: VP.Pt, node: U32}

type Queue is Type:
  Queue{events: Array<Pending>, heap: Array<U32>, size: U32, count: U32}

# The beach line: nodes by id, prev/next links in std::map order, which ids are in the line, and the first and last
# id (nil when empty). Insert, erase and updates by id are O(1); lower_bound walks from the first node.
type Beach is Type:
  Beach{nodes: Array<Node>, prev: Array<U32>, next: Array<U32>, live: Array<U32>, first: U32, last: U32}

type Sweep is Type:
  Sweep{beach: Beach, queue: Queue, ends: List<&2, End>, d: VD.Diagram, ids: U32, log: List<&2, VP.Circle>}

# A segment input: its two end points.
type Segment is Data:
  Segment{x0: U32, y0: U32, x1: U32, y1: U32}

# The result: the site events after sort + unique, the circle events in processing order and the built diagram.
type Built is Type:
  Built{sites: List<&2, VP.Site>, events: List<&2, VP.Circle>, d: VD.Diagram}

def nil() -> U32:
  VD.nil()

def node_id(n: Node) -> U32:
  match n:
    case Node{_, _, _, _, +id}:
      id

def node_left(n: Node) -> VP.Site:
  match n:
    case Node{+l, _, _, _, _}:
      l

def node_right(n: Node) -> VP.Site:
  match n:
    case Node{_, +r, _, _, _}:
      r

def node_edge(n: Node) -> U32:
  match n:
    case Node{_, _, +e, _, _}:
      e

def node_circle(n: Node) -> U32:
  match n:
    case Node{_, _, _, +c, _}:
      c

def dummy_site() -> VP.Site:
  VP.Site{0, 0, 0, 0, 0, 0, 0}

def dummy_node() -> Node:
  Node{dummy_site(), dummy_site(), nil(), nil(), nil()}

# Room for every node id: a site event inserts at most three nodes, the collinear start one per site.
def beach_new(+n: U32) -> Beach:
  +d = U32.to_nat((U32.from_nat(U32.log2(((n * 4 : U32) + 16 : U32))) + 1 : U32))
  Beach{Array.new(Node, d, dummy_node()), Array.new(U32, d, nil()), Array.new(U32, d, nil()), Array.new(U32, d, 0), nil(), nil()}

def node_read(got: Array<Node> & Node, prev: Array<U32>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32) -> Beach & Node:
  (nodes, +n) = got
  (Beach{nodes, prev, next, live, first, last}, n)

def node_or_dummy(none: Bool, nodes: Array<Node>, prev: Array<U32>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +id: U32) -> Beach & Node:
  match none:
    case True{}:
      (Beach{nodes, prev, next, live, first, last}, dummy_node())
    case False{}:
      node_read(Array.get(Node, nodes, id), prev, next, live, first, last)

# The node with id `id`, a dummy node for nil.
def beach_node(b: Beach, +id: U32) -> Beach & Node:
  match b:
    case Beach{nodes, prev, next, live, +first, +last}:
      node_or_dummy(U32.is_eq(id, nil()), nodes, prev, next, live, first, last, id)

def before_read(got: Array<U32> & U32, nodes: Array<Node>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32) -> Beach & Node:
  (prev, +p) = got
  beach_node(Beach{nodes, prev, next, live, first, last}, p)

# The node before `id` (a dummy node at the start).
def beach_before(b: Beach, +id: U32) -> Beach & Node:
  match b:
    case Beach{nodes, prev, next, live, +first, +last}:
      before_read(prev[id], nodes, next, live, first, last)

def after_read(got: Array<U32> & U32, nodes: Array<Node>, prev: Array<U32>, live: Array<U32>, +first: U32, +last: U32) -> Beach & U32:
  (next, +q) = got
  (Beach{nodes, prev, next, live, first, last}, q)

# The id after `id` (nil at the end).
def beach_after(b: Beach, +id: U32) -> Beach & U32:
  match b:
    case Beach{nodes, prev, next, live, +first, +last}:
      after_read(next[id], nodes, prev, live, first, last)

def beach_first(b: Beach) -> Beach & U32:
  match b:
    case Beach{nodes, prev, next, live, +first, +last}:
      (Beach{nodes, prev, next, live, first, last}, first)

def beach_last(b: Beach) -> Beach & Node:
  match b:
    case Beach{nodes, prev, next, live, +first, +last}:
      beach_node(Beach{nodes, prev, next, live, first, last}, last)

def linked_at_end(empty: Bool, nodes: Array<Node>, prev: Array<U32>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +id: U32) -> Beach:
  match empty:
    case True{}:
      Beach{nodes, Array.set(U32, prev, id, nil()), Array.set(U32, next, id, nil()), live, id, id}
    case False{}:
      Beach{nodes, Array.set(U32, prev, id, last), Array.set(U32, Array.set(U32, next, id, nil()), last, id), live, first, id}

def linked_after(head: Bool, nodes: Array<Node>, prev: Array<U32>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +p: U32, +id: U32) -> Beach:
  match head:
    case True{}:
      Beach{nodes, prev, next, live, id, last}
    case False{}:
      Beach{nodes, prev, Array.set(U32, next, p, id), live, first, last}

def linked_before(got: Array<U32> & U32, nodes: Array<Node>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +pos: U32, +id: U32) -> Beach:
  (prev, +p) = got
  linked_after(U32.is_eq(p, nil()), nodes, Array.set(U32, Array.set(U32, prev, id, p), pos, id), Array.set(U32, next, id, pos),
    live, first, last, p, id)

def link(at_end: Bool, nodes: Array<Node>, prev: Array<U32>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +pos: U32, +id: U32) -> Beach:
  match at_end:
    case True{}:
      linked_at_end(U32.is_eq(last, nil()), nodes, prev, next, live, first, last, id)
    case False{}:
      linked_before(prev[pos], nodes, next, live, first, last, pos, id)

# std::map::insert(hint, node) with a valid hint: node n goes right before node `pos` (nil = at the end).
def beach_insert(b: Beach, +pos: U32, +n: Node) -> Beach:
  match b:
    case Beach{nodes, prev, next, live, +first, +last}:
      +id = node_id(n)
      link(U32.is_eq(pos, nil()), Array.set(Node, nodes, id, n), prev, next, Array.set(U32, live, id, 1), first, last, pos, id)

def unlinked_right(tail: Bool, b: Beach, +p: U32, +q: U32) -> Beach:
  match tail:
    case True{}:
      match b:
        case Beach{nodes, prev, next, live, +first, _}:
          Beach{nodes, prev, next, live, first, p}
    case False{}:
      match b:
        case Beach{nodes, prev, next, live, +first, +last}:
          Beach{nodes, Array.set(U32, prev, q, p), next, live, first, last}

def unlinked_left(head: Bool, nodes: Array<Node>, prev: Array<U32>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +p: U32, +q: U32) -> Beach:
  match head:
    case True{}:
      Beach{nodes, prev, next, live, q, last}
    case False{}:
      Beach{nodes, prev, Array.set(U32, next, p, q), live, first, last}

def erase_next(got: Array<U32> & U32, nodes: Array<Node>, prev: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +p: U32) -> Beach:
  (next, +q) = got
  unlinked_right(U32.is_eq(q, nil()), unlinked_left(U32.is_eq(p, nil()), nodes, prev, next, live, first, last, p, q), p, q)

def erase_prev(got: Array<U32> & U32, nodes: Array<Node>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +id: U32) -> Beach:
  (prev, +p) = got
  erase_next(next[id], nodes, prev, live, first, last, p)

def erase_if(dead: Bool, nodes: Array<Node>, prev: Array<U32>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +id: U32) -> Beach:
  match dead:
    case True{}:
      Beach{nodes, prev, next, live, first, last}
    case False{}:
      erase_prev(prev[id], nodes, next, Array.set(U32, live, id, 0), first, last, id)

def erase_live(got: Array<U32> & U32, nodes: Array<Node>, prev: Array<U32>, next: Array<U32>, +first: U32, +last: U32, +id: U32) -> Beach:
  (live, +alive) = got
  erase_if(U32.is_zero(alive), nodes, prev, next, live, first, last, id)

# beach_line_.erase(node): a node not in the line is left alone.
def beach_erase(b: Beach, +id: U32) -> Beach:
  match b:
    case Beach{nodes, prev, next, live, +first, +last}:
      erase_live(live[id], nodes, prev, next, first, last, id)

def with_circle(+c: U32, n: Node) -> Node:
  match n:
    case Node{+l, +r, +e, _, +id}:
      Node{l, r, e, c, id}

def circle_written(got: Array<Node> & Node, prev: Array<U32>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +id: U32, +c: U32) -> Beach:
  (nodes, n) = got
  Beach{Array.set(Node, nodes, id, with_circle(c, n)), prev, next, live, first, last}

def beach_set_circle(b: Beach, +id: U32, +c: U32) -> Beach:
  match b:
    case Beach{nodes, prev, next, live, +first, +last}:
      circle_written(Array.get(Node, nodes, id), prev, next, live, first, last, id, c)

def with_right_edge(+r: VP.Site, +e: U32, n: Node) -> Node:
  match n:
    case Node{+l, _, _, +c, +id}:
      Node{l, r, e, c, id}

def edge_written(got: Array<Node> & Node, prev: Array<U32>, next: Array<U32>, live: Array<U32>, +first: U32, +last: U32, +id: U32, +r: VP.Site, +e: U32) -> Beach:
  (nodes, n) = got
  Beach{Array.set(Node, nodes, id, with_right_edge(r, e, n)), prev, next, live, first, last}

def beach_set_right_edge(b: Beach, +id: U32, +r: VP.Site, +e: U32) -> Beach:
  match b:
    case Beach{nodes, prev, next, live, +first, +last}:
      edge_written(Array.get(Node, nodes, id), prev, next, live, first, last, id, r, e)

# A lower_bound walk position: the node id and whether its key is less than the searched key.
type Probe is Type:
  Probe{b: Beach, id: U32, less: Bool}

def probe_less(none: Bool, +n: Node, +kl: VP.Site, +kr: VP.Site) -> Bool:
  match none:
    case True{}:
      False{}
    case False{}:
      VP.node_less(node_left(n), node_right(n), kl, kr)

def probe_read(got: Beach & Node, +id: U32, +kl: VP.Site, +kr: VP.Site) -> Probe:
  (b, +n) = got
  Probe{b, id, probe_less(U32.is_eq(id, nil()), n, kl, kr)}

def probe_at(got: Beach & U32, +kl: VP.Site, +kr: VP.Site) -> Probe:
  (b, +id) = got
  probe_read(beach_node(b, id), id, kl, kr)

def lower_walk(fuel: Nat, p: Probe, +kl: VP.Site, +kr: VP.Site) -> Beach & U32:
  match fuel:
    case 0n:
      match p:
        case Probe{b, +id, _}:
          (b, id)
    case 1n+f:
      match p:
        case Probe{b, +id, less}:
          match less:
            case True{}:
              lower_walk(f, probe_at(beach_after(b, id), kl, kr), kl, kr)
            case False{}:
              (b, id)

# beach_line_.lower_bound(key): the first node not less than the key (nil at the end).
def beach_lower(b: Beach, +kl: VP.Site, +kr: VP.Site) -> Beach & U32:
  lower_walk(1048576n, probe_at(beach_first(b), kl, kr), kl, kr)

def event_circle(e: Pending) -> VP.Circle:
  match e:
    case Pending{+c, _, _}:
      c

def event_lt_second(got: Array<Pending> & Pending, +a: Pending) -> Array<Pending> & Bool:
  (evs, b) = got
  (evs, VP.circle_less(event_circle(b), event_circle(a)))

def event_lt_first(got: Array<Pending> & Pending, +j: U32) -> Array<Pending> & Bool:
  (evs, a) = got
  event_lt_second(Array.get(Pending, evs, j), a)

def event_lt_ids(evs: Array<Pending>, +i: U32, +j: U32) -> Array<Pending> & Bool:
  event_lt_first(Array.get(Pending, evs, i), j)

# The priority queue's order: event i sorts below event j when j's circle comes first.
def event_lt(evs: Array<Pending>, i: U32, j: U32) -> Array<Pending> & Bool:
  event_lt_ids(evs, i, j)

def pushed(w: SH.Work<Array<Pending>>, +size: U32, +count: U32) -> Queue:
  match w:
    case SH.Work{evs, heap}:
      Queue{evs, heap, (size + 1 : U32), (count + 1 : U32)}

# ordered_queue::push: returns the queue and the new event's id.
def push_event(q: Queue, +c: VP.Circle, +node: U32) -> Queue & U32:
  match q:
    case Queue{evs, heap, +size, +count}:
      evs2 = Array.set(Pending, evs, count, Pending{c, True{}, node})
      heap2 = Array.set(U32, heap, size, count)
      (pushed(SH.push_heap(~Array<Pending>, ~event_lt, evs2, heap2, 0, (size + 1 : U32)), size, count), count)

def popped(w: SH.Work<Array<Pending>>, +size: U32, +count: U32) -> Queue:
  match w:
    case SH.Work{evs, heap}:
      Queue{evs, heap, (size - 1 : U32), count}

# ordered_queue::pop.
def pop_event(q: Queue) -> Queue:
  match q:
    case Queue{evs, heap, +size, +count}:
      popped(SH.pop_heap(~Array<Pending>, ~event_lt, evs, heap, 0, size), size, count)

def deactivated(got: Array<Pending> & Pending, heap: Array<U32>, +size: U32, +count: U32, +id: U32) -> Queue:
  (evs, e) = got
  match e:
    case Pending{+c, _, +n}:
      Queue{Array.set(Pending, evs, id, Pending{c, False{}, n}), heap, size, count}

def deactivate_if(has: Bool, q: Queue, +id: U32) -> Queue:
  match has:
    case True{}:
      match q:
        case Queue{evs, heap, +size, +count}:
          deactivated(Array.get(Pending, evs, id), heap, size, count, id)
    case False{}:
      q

def top_read(got: Array<Pending> & Pending, heap: Array<U32>, +size: U32, +count: U32) -> Queue & Pending:
  (evs, +e) = got
  (Queue{evs, heap, size, count}, e)

def top_event(got: Array<U32> & U32, evs: Array<Pending>, +size: U32, +count: U32) -> Queue & Pending:
  (heap, +id) = got
  top_read(Array.get(Pending, evs, id), heap, size, count)

# The queue's top event (the queue must not be empty).
def top(q: Queue) -> Queue & Pending:
  match q:
    case Queue{evs, heap, +size, +count}:
      top_event(Array.get(U32, heap, 0), evs, size, count)

def queue_size(q: Queue) -> Queue & U32:
  match q:
    case Queue{evs, heap, +size, +count}:
      (Queue{evs, heap, size, count}, size)

def event_active(e: Pending) -> Bool:
  match e:
    case Pending{_, +a, _}:
      a

type Head is Type:
  Head{q: Queue, stale: Bool}

def head_of(got: Queue & Pending) -> Head:
  (q, e) = got
  Head{q, Bool.not(event_active(e))}

def head_check(empty: Bool, q: Queue) -> Head:
  match empty:
    case True{}:
      Head{q, False{}}
    case False{}:
      head_of(top(q))

def head_nonempty(got: Queue & U32) -> Head:
  (q, +size) = got
  head_check(U32.is_zero(size), q)

# while (!empty && !top.is_active) pop.
def drop_inactive(n: Nat, h: Head) -> Queue:
  match n:
    case 0n:
      match h:
        case Head{q, _}:
          q
    case 1n+p:
      match h:
        case Head{q, stale}:
          match stale:
            case True{}:
              drop_inactive(p, head_nonempty(queue_size(pop_event(q))))
            case False{}:
              q

def deactivated_node(got: Beach & Node, q: Queue, +ends: List<&2, End>, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>, +id: U32) -> Sweep:
  (beach, +n) = got
  +c = node_circle(n)
  Sweep{beach_set_circle(beach, id, nil()), deactivate_if(Bool.not(U32.is_eq(c, nil())), q, c), ends, d, ids, log}

def sweep_deactivate(s: Sweep, +id: U32) -> Sweep:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      deactivated_node(beach_node(beach, id), q, ends, d, ids, log, id)

def resweep_node(got: Beach & Node, q: Queue, +ends: List<&2, End>, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>) -> Sweep & Node:
  (beach, +n) = got
  (Sweep{beach, q, ends, d, ids, log}, n)

def resweep_id(got: Beach & U32, q: Queue, +ends: List<&2, End>, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>) -> Sweep & U32:
  (beach, +i) = got
  (Sweep{beach, q, ends, d, ids, log}, i)

def sweep_node(s: Sweep, +id: U32) -> Sweep & Node:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      resweep_node(beach_node(beach, id), q, ends, d, ids, log)

def sweep_before(s: Sweep, +id: U32) -> Sweep & Node:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      resweep_node(beach_before(beach, id), q, ends, d, ids, log)

def sweep_last(s: Sweep) -> Sweep & Node:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      resweep_node(beach_last(beach), q, ends, d, ids, log)

def sweep_first(s: Sweep) -> Sweep & U32:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      resweep_id(beach_first(beach), q, ends, d, ids, log)

def sweep_after(s: Sweep, +id: U32) -> Sweep & U32:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      resweep_id(beach_after(beach, id), q, ends, d, ids, log)

def sweep_lower(s: Sweep, +kl: VP.Site, +kr: VP.Site) -> Sweep & U32:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      resweep_id(beach_lower(beach, kl, kr), q, ends, d, ids, log)

def activated(got: Queue & U32, beach: Beach, +ends: List<&2, End>, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>, +node: U32) -> Sweep:
  (q, +e) = got
  Sweep{beach_set_circle(beach, node, e), q, ends, d, ids, log}

def activate_with(m: Maybe<&2, VP.Circle>, s: Sweep, +node: U32) -> Sweep:
  match m:
    case None{}:
      s
    case Some{+c}:
      match s:
        case Sweep{beach, q, +ends, d, +ids, +log}:
          activated(push_event(q, c, node), beach, ends, d, ids, log, node)

# activate_circle_event(site1, site2, site3, bisector_node).
def activate(s: Sweep, +s1: VP.Site, +s2: VP.Site, +s3: VP.Site, +node: U32) -> Sweep:
  activate_with(VL.circle_formation(s1, s2, s3), s, node)

type Placed is Type:
  Placed{s: Sweep, pos: U32}

type Arc is Type:
  Arc{beach: Beach, ends: List<&2, End>, pos: U32, ids: U32}

def arc_segment_node(seg: Bool, beach: Beach, +ends: List<&2, End>, +site: VP.Site, +pos: U32, +ids: U32) -> Arc:
  match seg:
    case True{}:
      +mid = {Node{site, VP.inverse(site), nil(), nil(), ids} : Node}
      Arc{beach_insert(beach, pos, mid), End{VP.point1(site), ids} <> ends, ids, (ids + 1 : U32)}
    case False{}:
      Arc{beach, ends, pos, ids}

def arc_left(arc: Arc, q: Queue, d: VD.Diagram, +log: List<&2, VP.Circle>, +arc1: VP.Site, +site: VP.Site, +e: U32) -> Placed:
  match arc:
    case Arc{beach, +ends, +pos, +ids}:
      Placed{Sweep{beach_insert(beach, pos, Node{arc1, site, e, nil(), ids}), q, ends, d, (ids + 1 : U32), log}, ids}

def arc_edges(got: VD.Diagram & U32, beach: Beach, q: Queue, +ends: List<&2, End>, +ids: U32, +log: List<&2, VP.Circle>, +arc1: VP.Site, +arc2: VP.Site, +site: VP.Site, +pos: U32) -> Placed:
  (d, +e) = got
  +seg = VP.is_segment(site)
  +right = {Node{VP.inverse_if(seg, site), arc2, (e + 1 : U32), nil(), ids} : Node}
  arc_left(arc_segment_node(seg, beach_insert(beach, pos, right), ends, site, ids, (ids + 1 : U32)), q, d, log, arc1, site, e)

# insert_new_arc(site_arc1, site_arc2, site_event, position): returns the new left node's id.
def insert_arc(s: Sweep, +arc1: VP.Site, +arc2: VP.Site, +site: VP.Site, +pos: U32) -> Placed:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      arc_edges(VD.insert_edge(d, arc2, site), beach, q, ends, ids, log, arc1, arc2, site, pos)

def site_end_placed(p: Placed, +l: VP.Site, +r: VP.Site, +site: VP.Site) -> Placed:
  match p:
    case Placed{s, +pos}:
      Placed{activate(s, l, r, site, pos), pos}

# The right_it == end branch of process_site_event.
def site_at_end(got: Sweep & Node, +site: VP.Site) -> Placed:
  (s, +left) = got
  +arc = node_right(left)
  site_end_placed(insert_arc(s, arc, arc, site, nil()), node_left(left), arc, site)

def site_begin_placed(p: Placed, +n: Node, +site: VP.Site, +right: U32) -> Placed:
  match p:
    case Placed{s, +left}:
      Placed{activate(s, VP.inverse_if(VP.is_segment(site), site), node_left(n), node_right(n), right), left}

# The right_it == begin branch.
def site_at_begin(got: Sweep & Node, +site: VP.Site, +right: U32) -> Placed:
  (s, +n) = got
  site_begin_placed(insert_arc(s, node_left(n), node_left(n), site, right), n, site, right)

def site_between_placed(p: Placed, +ln: Node, +rn: Node, +site: VP.Site, +right: U32) -> Placed:
  match p:
    case Placed{s, +fresh}:
      s1 = activate(s, node_left(ln), node_right(ln), site, fresh)
      Placed{activate(s1, VP.inverse_if(VP.is_segment(site), site), node_left(rn), node_right(rn), right), fresh}

def site_between_nodes(got: Sweep & Node, +rn: Node, +site: VP.Site, +right: U32) -> Placed:
  (s, +ln) = got
  site_between_placed(insert_arc(sweep_deactivate(s, right), node_right(ln), node_left(rn), site, right), ln, rn, site, right)

# The middle branch.
def site_between(got: Sweep & Node, +site: VP.Site, +right: U32) -> Placed:
  (s, +rn) = got
  site_between_nodes(sweep_before(s, right), rn, site, right)

def site_not_end(at_begin: Bool, s: Sweep, +site: VP.Site, +right: U32) -> Placed:
  match at_begin:
    case True{}:
      site_at_begin(sweep_node(s, right), site, right)
    case False{}:
      site_between(sweep_node(s, right), site, right)

def site_placed(at_end: Bool, +at_begin: Bool, s: Sweep, +site: VP.Site, +right: U32) -> Placed:
  match at_end:
    case True{}:
      site_at_end(sweep_last(s), site)
    case False{}:
      site_not_end(at_begin, s, site, right)

def place_one(got: Sweep & U32, +site: VP.Site, +right: U32) -> Placed:
  (s, +first) = got
  site_placed(U32.is_eq(right, nil()), U32.is_eq(right, first), s, site, right)

def place_sites(group: List<&2, VP.Site>, p: Placed) -> Sweep:
  match group:
    case Nil{}:
      match p:
        case Placed{s, _}:
          s
    case Con{+site, +rest}:
      match p:
        case Placed{s, +right}:
          place_sites(rest, place_one(sweep_first(s), site, right))

def same_point(+p: VP.Pt, +e: End) -> Bool:
  match e:
    case End{+q, _}:
      VP.pt_eq(p, q)

def end_node(e: End) -> U32:
  match e:
    case End{_, +n}:
      n

def prepend_end(+e: End, got: List<&2, End> & Beach) -> List<&2, End> & Beach:
  (ends, beach) = got
  (e <> ends, beach)

def head_at(l: List<&2, End>, +p: VP.Pt) -> Bool:
  match l:
    case Nil{}:
      False{}
    case Con{+e, _}:
      same_point(p, e)

def drop_go(ends: List<&2, End>, here: Bool, +p: VP.Pt, beach: Beach) -> List<&2, End> & Beach:
  match ends:
    case Nil{}:
      (Nil{}, beach)
    case Con{+e, +rest}:
      match here:
        case True{}:
          drop_go(rest, head_at(rest, p), p, beach_erase(beach, end_node(e)))
        case False{}:
          prepend_end(e, drop_go(rest, head_at(rest, p), p, beach))

def drop_ends(+ends: List<&2, End>, +p: VP.Pt, beach: Beach) -> List<&2, End> & Beach:
  drop_go(ends, head_at(ends, p), p, beach)

def ends_removed(got: List<&2, End> & Beach, q: Queue, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>) -> Sweep:
  (+ends, beach) = got
  Sweep{beach, q, ends, d, ids, log}

# At a point site, the beach line nodes of segments ending there are erased.
def remove_ends(point: Bool, s: Sweep, +p: VP.Pt) -> Sweep:
  match point:
    case True{}:
      match s:
        case Sweep{beach, q, +ends, d, +ids, +log}:
          ends_removed(drop_ends(ends, p, beach), q, d, ids, log)
    case False{}:
      s

def same_start_segment(+first: VP.Site, +s: VP.Site) -> Bool:
  VP.is_segment(s) && VP.pt_eq(VP.point0(s), VP.point0(first))

type Split is Data:
  Split{group: List<&2, VP.Site>, rest: List<&2, VP.Site>}

def grow(+s: VP.Site, sp: Split) -> Split:
  match sp:
    case Split{+g, +r}:
      Split{s <> g, r}

def take_segments(l: List<&2, VP.Site>, +first: VP.Site) -> Split:
  match l:
    case Nil{}:
      Split{Nil{}, Nil{}}
    case Con{+s, +rest}:
      Bool.pick(Split, same_start_segment(first, s), grow(s, take_segments(rest, first)), Split{Nil{}, s <> rest})

# The sites process_site_event handles at once: a point alone, or a segment with the following segments that start
# at the same point.
def site_group(point: Bool, +first: VP.Site, +rest: List<&2, VP.Site>) -> Split:
  match point:
    case True{}:
      Split{[first], rest}
    case False{}:
      grow(first, take_segments(rest, first))

def lower_placed(got: Sweep & U32) -> Placed:
  (s, +pos) = got
  Placed{s, pos}

def group_placed(sp: Split, s: Sweep, +first: VP.Site) -> Sweep & List<&2, VP.Site>:
  match sp:
    case Split{+group, +rest}:
      (place_sites(group, lower_placed(sweep_lower(s, first, first))), rest)

# process_site_event: returns the sweep and the remaining site events.
def process_site(s: Sweep, +first: VP.Site, +rest: List<&2, VP.Site>) -> Sweep & List<&2, VP.Site>:
  +point = VP.is_point(first)
  group_placed(site_group(point, first, rest), remove_ends(point, s, VP.point0(first)), first)

def circle_site3(+s1: VP.Site, +s3: VP.Site) -> VP.Site:
  VP.inverse_if(VP.is_point(s1) && VP.is_segment(s3) && VP.pt_eq(VP.end(s3), VP.point0(s1)), s3)

def circle_left_node(got: Sweep & Node, +first: U32, +s1: VP.Site, +s3: VP.Site) -> Sweep:
  (s, +before) = got
  activate(s, node_left(before), s1, s3, first)

def circle_left(begin: Bool, s: Sweep, +first: U32, +last: U32, +s1: VP.Site, +s3: VP.Site) -> Sweep:
  match begin:
    case True{}:
      s
    case False{}:
      circle_left_node(sweep_before(sweep_deactivate(s, first), first), first, s1, s3)

def circle_right_node(got: Sweep & Node, +next: U32, +s1: VP.Site, +s3: VP.Site) -> Sweep:
  (s, +n) = got
  activate(s, s1, s3, node_right(n), next)

def circle_right(end: Bool, s: Sweep, +next: U32, +s1: VP.Site, +s3: VP.Site) -> Sweep:
  match end:
    case True{}:
      s
    case False{}:
      circle_right_node(sweep_node(sweep_deactivate(s, next), next), next, s1, s3)

def circle_after_next(got: Sweep & U32, +begin: Bool, +first: Node, +last: U32, +s1: VP.Site, +s3: VP.Site) -> Sweep:
  (s, +next) = got
  circle_right(U32.is_eq(next, nil()), circle_left(begin, s, node_id(first), last, s1, s3), next, s1, s3)

def circle_after_first(got: Sweep & U32, +first: Node, +last: U32, +s1: VP.Site, +s3: VP.Site) -> Sweep:
  (s, +head) = got
  circle_after_next(sweep_after(s, node_id(first)), U32.is_eq(head, node_id(first)), first, last, s1, s3)

def circle_after(s: Sweep, +first: Node, +last: U32, +s1: VP.Site, +s3: VP.Site) -> Sweep:
  circle_after_first(sweep_first(s), first, last, s1, s3)

def circle_edge(got: VD.Diagram & U32, beach: Beach, q: Queue, +ends: List<&2, End>, +ids: U32, +log: List<&2, VP.Circle>, +first: Node, +last: U32, +s1: VP.Site, +s3: VP.Site) -> Sweep:
  (d, +e) = got
  b1 = beach_erase(beach_set_right_edge(beach, node_id(first), s3, e), last)
  circle_after(Sweep{b1, pop_event(q), ends, d, ids, log}, first, last, s1, s3)

def circle_first(got: Beach & Node, +ln: Node, q: Queue, +ends: List<&2, End>, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>, +c: VP.Circle, +last: U32) -> Sweep:
  (beach, +first) = got
  +s1 = node_left(first)
  +s3 = circle_site3(s1, node_right(ln))
  circle_edge(VD.insert_vertex(d, s1, s3, c, node_edge(first), node_edge(ln)), beach, q, ends, ids, c <> log, first, last, s1, s3)

def circle_last(got: Beach & Node, q: Queue, +ends: List<&2, End>, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>, +c: VP.Circle, +last: U32) -> Sweep:
  (beach, +ln) = got
  circle_first(beach_before(beach, last), ln, q, ends, d, ids, log, c, last)

def circle_nodes(got: Queue & Pending, beach: Beach, +ends: List<&2, End>, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>) -> Sweep:
  (q, ev) = got
  match ev:
    case Pending{+c, _, +last}:
      circle_last(beach_node(beach, last), q, ends, d, ids, log, c, last)

# process_circle_event (on the queue's top event).
def process_circle(s: Sweep) -> Sweep:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      circle_nodes(top(q), beach, ends, d, ids, log)

def sweep_size_got(got: Queue & U32, beach: Beach, +ends: List<&2, End>, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>) -> Sweep & U32:
  (q, +size) = got
  (Sweep{beach, q, ends, d, ids, log}, size)

def sweep_queue_size(s: Sweep) -> Sweep & U32:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      sweep_size_got(queue_size(q), beach, ends, d, ids, log)

def clean_queue(s: Sweep, +fuel: U32) -> Sweep:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      Sweep{beach, drop_inactive(U32.to_nat(fuel), head_nonempty(queue_size(q))), ends, d, ids, log}

def site_first(got: Queue & Pending, beach: Beach, +ends: List<&2, End>, d: VD.Diagram, +ids: U32, +log: List<&2, VP.Circle>, +site: VP.Site) -> Sweep & Bool:
  (q, ev) = got
  (Sweep{beach, q, ends, d, ids, log}, VP.site_before_circle(site, event_circle(ev)))

def site_or_circle(s: Sweep, +site: VP.Site) -> Sweep & Bool:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      site_first(top(q), beach, ends, d, ids, log, site)

# One iteration of construct's loop, given whether the circle queue is empty.
type Step is Type:
  Step{s: Sweep, sites: List<&2, VP.Site>, done: Bool}

def step_site(got: Sweep & List<&2, VP.Site>) -> Step:
  (s, +rest) = got
  Step{s, rest, False{}}

def step_circle(s: Sweep, +sites: List<&2, VP.Site>) -> Step:
  Step{process_circle(s), sites, False{}}

def step_choose(site_first: Bool, s: Sweep, +site: VP.Site, +rest: List<&2, VP.Site>) -> Step:
  match site_first:
    case True{}:
      step_site(process_site(s, site, rest))
    case False{}:
      step_circle(s, site <> rest)

def step_choice(got: Sweep & Bool, +site: VP.Site, +rest: List<&2, VP.Site>) -> Step:
  (s, +site_first) = got
  step_choose(site_first, s, site, rest)

def step_with_sites(empty_queue: Bool, s: Sweep, +site: VP.Site, +rest: List<&2, VP.Site>) -> Step:
  match empty_queue:
    case True{}:
      step_site(process_site(s, site, rest))
    case False{}:
      step_choice(site_or_circle(s, site), site, rest)

def step_no_sites(empty_queue: Bool, s: Sweep) -> Step:
  match empty_queue:
    case True{}:
      Step{s, Nil{}, True{}}
    case False{}:
      step_circle(s, Nil{})

def step_sites(sites: List<&2, VP.Site>, +empty_queue: Bool, s: Sweep) -> Step:
  match sites:
    case Nil{}:
      step_no_sites(empty_queue, s)
    case Con{+site, +rest}:
      step_with_sites(empty_queue, s, site, rest)

def step_sized(got: Sweep & U32, +sites: List<&2, VP.Site>) -> Step:
  (s, +size) = got
  step_sites(sites, U32.is_zero(size), s)

def cleaned(st: Step, +fuel: U32) -> Step:
  match st:
    case Step{s, +sites, +done}:
      Step{clean_queue(s, fuel), sites, done}

def sweep_loop(n: Nat, st: Step, +fuel: U32) -> Sweep:
  match n:
    case 0n:
      match st:
        case Step{s, _, _}:
          s
    case 1n+p:
      match st:
        case Step{s, +sites, done}:
          match done:
            case True{}:
              s
            case False{}:
              sweep_loop(p, cleaned(step_sized(sweep_queue_size(s), sites), fuel), fuel)

def vertical_run(l: List<&2, VP.Site>, +x: U32, +k: U32) -> U32:
  match l:
    case Nil{}:
      k
    case Con{+s, +rest}:
      Bool.pick(U32, U32.is_eq(VP.site_x0(s), x) && VP.is_vertical(s), vertical_run(rest, x, (k + 1 : U32)), k)

def collinear_got(got: VD.Diagram & U32, beach: Beach, q: Queue, +ends: List<&2, End>, +ids: U32, +log: List<&2, VP.Circle>, +a: VP.Site, +b: VP.Site) -> Sweep:
  (d, +e) = got
  Sweep{beach_insert(beach, nil(), Node{a, b, e, nil(), ids}), q, ends, d, (ids + 1 : U32), log}

def collinear_edge(s: Sweep, +a: VP.Site, +m: Maybe<&2, VP.Site>) -> Sweep:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      +b = Maybe.default(&2, VP.Site, m, dummy_site())
      collinear_got(VD.insert_edge(d, a, b), beach, q, ends, ids, log, a, b)

# init_beach_line_collinear_sites: one node per consecutive pair of the first k + 1 sites, appended in order.
def collinear_nodes(k: Nat, l: List<&2, VP.Site>, s: Sweep) -> Sweep:
  match k:
    case 0n:
      s
    case 1n+p:
      match l:
        case Nil{}:
          s
        case Con{+a, +rest}:
          collinear_nodes(p, rest, collinear_edge(s, a, List.head(&2, VP.Site, rest)))

def default_start(placed: Placed) -> Sweep:
  match placed:
    case Placed{s, _}:
      s

def init_skip(one: Bool, +skip: U32, s: Sweep, +first: VP.Site, +second: VP.Site, +all: List<&2, VP.Site>) -> Step:
  match one:
    case True{}:
      Step{default_start(insert_arc(s, first, first, second, nil())), List.drop(&2, VP.Site, all, 2n), False{}}
    case False{}:
      Step{collinear_nodes(U32.to_nat((skip - 1 : U32)), all, s), List.drop(&2, VP.Site, all, U32.to_nat(skip)), False{}}

def init_many(+skip: U32, s: Sweep, +first: VP.Site, +second: VP.Site, +all: List<&2, VP.Site>) -> Step:
  init_skip(U32.is_eq(skip, 1), skip, s, first, second, all)

def init_single(s: Sweep, +first: VP.Site) -> Sweep:
  match s:
    case Sweep{beach, q, +ends, d, +ids, +log}:
      Sweep{beach, q, ends, VD.single_site(d, first), ids, log}

def init_rest(rest: List<&2, VP.Site>, s: Sweep, +first: VP.Site, +all: List<&2, VP.Site>) -> Step:
  match rest:
    case Nil{}:
      Step{init_single(s, first), Nil{}, False{}}
    case Con{+second, _}:
      init_many(vertical_run(all, VP.site_x0(first), 0), s, first, second, all)

# init_beach_line.
def init_beach(sites: List<&2, VP.Site>, s: Sweep) -> Step:
  match sites:
    case Nil{}:
      Step{s, Nil{}, True{}}
    case Con{+first, +rest}:
      init_rest(rest, s, first, first <> rest)

def site_pair(got: Array<VP.Site> & VP.Site, +x: VP.Site) -> Array<VP.Site> & VP.Site & VP.Site:
  (a, +y) = got
  (a, (x, y))

def site_second(got: Array<VP.Site> & VP.Site, +x: VP.Site) -> Array<VP.Site> & Bool:
  (a, +y) = got
  (a, VP.site_less(x, y))

def site_first_got(got: Array<VP.Site> & VP.Site, +j: U32) -> Array<VP.Site> & Bool:
  (a, +x) = got
  site_second(Array.get(VP.Site, a, j), x)

def site_lt_ids(a: Array<VP.Site>, +i: U32, +j: U32) -> Array<VP.Site> & Bool:
  site_first_got(Array.get(VP.Site, a, i), j)

# event_comparison_predicate on site handles, for std::sort.
def site_lt(a: Array<VP.Site>, i: U32, j: U32) -> Array<VP.Site> & Bool:
  site_lt_ids(a, i, j)

def with_sorted(+k: U32, s: VP.Site) -> VP.Site:
  match s:
    case VP.Site{+x0, +y0, +x1, +y1, _, +i, +f}:
      VP.Site{x0, y0, x1, y1, k, i, f}

def array_list(a: Array<U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match a:
    case ALeaf{+x}:
      x <> acc
    case ANode{xs, ys}:
      array_list(xs, array_list(ys, acc))

def kept(keep: Bool, +k: U32, +s: VP.Site, +acc: List<&2, VP.Site>) -> List<&2, VP.Site>:
  match keep:
    case True{}:
      with_sorted(k, s) <> acc
    case False{}:
      acc

# std::unique over the sorted sites (the first of equal sites stays), with sorted_index set; `got` holds the site of
# the handle before `hs`, and `acc` the kept sites in reverse.
def unique_loop(hs: List<&2, U32>, got: Array<VP.Site> & VP.Site, +k: U32, +prev: VP.Site, +first: Bool, +acc: List<&2, VP.Site>) -> List<&2, VP.Site>:
  match hs:
    case Nil{}:
      (_, +s) = got
      List.reverse(&2, VP.Site, kept(first || Bool.not(VP.same_site(prev, s)), k, s, acc))
    case Con{+h, +rest}:
      (a, +s) = got
      +keep = first || Bool.not(VP.same_site(prev, s))
      unique_loop(rest, Array.get(VP.Site, a, h), FW.pick(keep, (k + 1 : U32), k), Bool.pick(VP.Site, keep, s, prev), False{},
        kept(keep, k, s, acc))

def unique_start(hs: List<&2, U32>, a: Array<VP.Site>) -> List<&2, VP.Site>:
  match hs:
    case Nil{}:
      Nil{}
    case Con{+h, +rest}:
      unique_loop(rest, Array.get(VP.Site, a, h), 0, dummy_site(), True{}, Nil{})

def take_handles(l: List<&2, U32>, +n: U32) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+h, +rest}:
      Bool.pick(List<&2, U32>, U32.is_zero(n), Nil{}, h <> take_handles(rest, (n - 1 : U32)))

def sorted_unique(w: SH.Work<Array<VP.Site>>, +n: U32) -> List<&2, VP.Site>:
  match w:
    case SH.Work{a, handles}:
      unique_start(take_handles(array_list(handles, Nil{}), n), a)

def point_site(+p: VP.Pt, +index: U32, +cat: U32) -> VP.Site:
  match p:
    case VP.Pt{+x, +y}:
      VP.Site{x, y, x, y, 0, index, cat}

def segment_sites(+seg: Segment, +index: U32) -> List<&2, VP.Site>:
  match seg:
    case Segment{+x0, +y0, +x1, +y1}:
      +p1 = {VP.Pt{x0, y0} : VP.Pt}
      +p2 = {VP.Pt{x1, y1} : VP.Pt}
      +ordered = VP.point_less(p1, p2)
      +whole = Bool.pick(VP.Site, ordered, VP.Site{x0, y0, x1, y1, 0, index, 8}, VP.Site{x1, y1, x0, y0, 0, index, 9})
      [point_site(p1, index, 1), point_site(p2, index, 2), whole]

def segment_input(segments: List<&2, Segment>, +index: U32) -> List<&2, VP.Site>:
  match segments:
    case Nil{}:
      Nil{}
    case Con{+seg, +rest}:
      List.append(&2, VP.Site, segment_sites(seg, index), segment_input(rest, (index + 1 : U32)))

# insert_point for every point, then insert_segment for every segment: the site events in input order.
def input_sites(points: List<&2, VP.Pt>, +segments: List<&2, Segment>, +index: U32) -> List<&2, VP.Site>:
  match points:
    case Nil{}:
      segment_input(segments, index)
    case Con{+p, +rest}:
      point_site(p, index, 0) <> input_sites(rest, segments, (index + 1 : U32))

type Filled is Type:
  Filled{sites: Array<VP.Site>, handles: Array<U32>, n: U32}

def fill_sites(l: List<&2, VP.Site>, a: Array<VP.Site>, h: Array<U32>, +i: U32) -> Filled:
  match l:
    case Nil{}:
      Filled{a, h, i}
    case Con{+s, +rest}:
      fill_sites(rest, Array.set(VP.Site, a, i, s), Array.set(U32, h, i, i), (i + 1 : U32))

def depth_for(+n: U32) -> Nat:
  U32.to_nat((U32.from_nat(U32.log2((n + 1 : U32))) + 1 : U32))

def sort_filled(+windows: Bool, f: Filled) -> List<&2, VP.Site>:
  match f:
    case Filled{a, h, +n}:
      sorted_unique(SS.sort_for(~Array<VP.Site>, ~site_lt, windows, a, h, 0, n), n)

# init_sites_queue: the site events sorted by the platform's std::sort, then std::unique.
def site_events(+windows: Bool, +input: List<&2, VP.Site>, +n: U32) -> List<&2, VP.Site>:
  +d = depth_for(n)
  sort_filled(windows, fill_sites(input, Array.new(VP.Site, d, dummy_site()), Array.new(U32, d, 0), 0))

def sweep_built(s: Sweep, +sites: List<&2, VP.Site>) -> Built:
  match s:
    case Sweep{_, _, _, d, _, +log}:
      Built{sites, List.reverse(&2, VP.Circle, log), VD.build(d)}

def events_depth(+n: U32) -> Nat:
  U32.to_nat((U32.from_nat(U32.log2(((n * 16 : U32) + 16 : U32))) + 1 : U32))

def fresh(+n: U32) -> Sweep:
  +d = events_depth(n)
  Sweep{beach_new(n), Queue{Array.new(Pending, d, Pending{VP.Circle{FR.zero(), FR.zero(), FR.zero()}, False{}, nil()}), Array.new(U32, d, 0), 0, 0}, Nil{}, VD.empty(n), 0, Nil{}}

def length32(l: List<&2, VP.Site>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      length32(rest, (acc + 1 : U32))

def run_sorted(+sites: List<&2, VP.Site>) -> Built:
  +n = length32(sites, 0)
  +fuel = ((n * 64 : U32) + 64 : U32)
  sweep_built(sweep_loop(U32.to_nat(fuel), init_beach(sites, fresh(n)), fuel), sites)

# construct_voronoi(points, segments): the builder run of the platform (`windows` picks the site sort).
def construct(+windows: Bool, +points: List<&2, VP.Pt>, +segments: List<&2, Segment>) -> Built:
  +input = input_sites(points, segments, 0)
  run_sorted(site_events(windows, input, length32(input, 0)))
