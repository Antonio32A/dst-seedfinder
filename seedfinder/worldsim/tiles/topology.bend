import Base
import ./table.bend as TileTable
import ./world.bend as TileWorld

# Graph and task relations of the committed map (tiles.cpp): GraphAdjacent, SameTask, SharesTaskThroughGraph.

def contains_loop(xs: List<&2, U32>, found: Bool, +v: U32) -> Bool:
  match xs:
    case Nil{}:
      found
    case Con{+x, rest}:
      match found:
        case True{}:
          True{}
        case False{}:
          contains_loop(rest, U32.is_eq(x, v), v)

def contains(xs: List<&2, U32>, +v: U32) -> Bool:
  contains_loop(xs, False{}, v)

# The out-edge targets of vertex v, in Boost order.
def neighbours(+w: TileWorld.World, +v: U32) -> List<&2, U32>:
  match w:
    case TileWorld.World{_, _, _, _, _, +adjacency, _, _, _}:
      TileTable.at(~List<&2, U32>, adjacency, v)

# GraphAdjacent(u, v): v is a target of one of u's out-edges.
def adjacent(+w: TileWorld.World, +u: U32, +v: U32) -> Bool:
  Bool.not(TileWorld.is_none(v)) && contains(neighbours(w, u), v)

def is_blank_or_random(+n: TileWorld.Node) -> Bool:
  match n:
    case TileWorld.Node{_, +kind, _, _, _, _, _, _, _, _}:
      U32.is_eq((kind .&. 4294967293 : U32), 1)

def kind_of(+n: TileWorld.Node) -> U32:
  match n:
    case TileWorld.Node{_, +kind, _, _, _, _, _, _, _, _}:
      kind

def flags_of(+n: TileWorld.Node) -> U32:
  match n:
    case TileWorld.Node{_, _, _, _, +flags, _, _, _, _, _}:
      flags

def tile_of(+n: TileWorld.Node) -> U32:
  match n:
    case TileWorld.Node{_, _, _, +tile, _, _, _, _, _, _}:
      tile

def parent_site_of(+n: TileWorld.Node) -> U32:
  match n:
    case TileWorld.Node{_, _, _, _, _, +parent, _, _, +parent_site, _}:
      Bool.pick(U32, TileWorld.is_none(parent), TileWorld.none(), parent_site)

def same_task_rest(+an: U32, +pa: U32, +ga: U32, +bn: U32, +pb: U32, +gb: U32) -> Bool:
  +pa_none = TileWorld.is_none(pa)
  +pb_none = TileWorld.is_none(pb)
  U32.is_eq(pb, pa) || U32.is_eq(an, pb) || U32.is_eq(bn, pa)
    || (Bool.not(pb_none) && U32.is_eq(an, gb))
    || (Bool.not(pa_none) && U32.is_eq(bn, ga))
    || (Bool.not(pb_none) && U32.is_eq(pa, gb))
    || (Bool.not(pa_none) && (U32.is_eq(pb, ga) || (Bool.not(pb_none) && U32.is_eq(gb, ga) && Bool.not(TileWorld.is_none(gb)))))

# SameTask(a, b) (no node is ever force-disconnected on the default path).
def same_task(+a: TileWorld.Node, +b: TileWorld.Node) -> Bool:
  match a:
    case TileWorld.Node{+an, _, _, _, _, +pa, +ga, _, _, _}:
      match b:
        case TileWorld.Node{+bn, _, _, _, _, +pb, +gb, _, _, _}:
          same_task_rest(an, pa, ga, bn, pb, gb)

def any_same_loop(vs: List<&2, U32>, found: Bool, +w: TileWorld.World, +n: TileWorld.Node) -> Bool:
  match vs:
    case Nil{}:
      found
    case Con{+v, rest}:
      match found:
        case True{}:
          True{}
        case False{}:
          any_same_loop(rest, same_task(n, TileWorld.node(w, v)), w, n)

def any_same_task(+w: TileWorld.World, +n: TileWorld.Node, vs: List<&2, U32>) -> Bool:
  any_same_loop(vs, False{}, w, n)

def adjacent_or_same(adj: Bool, +a: TileWorld.Node, +b: TileWorld.Node) -> Bool:
  match adj:
    case True{}:
      True{}
    case False{}:
      same_task(a, b)

def any_adjacent_loop(ks: List<&2, U32>, found: Bool, +w: TileWorld.World, +i: U32, +a: TileWorld.Node) -> Bool:
  match ks:
    case Nil{}:
      found
    case Con{+k, rest}:
      match found:
        case True{}:
          True{}
        case False{}:
          any_adjacent_loop(rest, adjacent_or_same(adjacent(w, i, k), a, TileWorld.node(w, k)), w, i, a)

def any_adjacent_or_same(+w: TileWorld.World, +i: U32, +a: TileWorld.Node, ks: List<&2, U32>) -> Bool:
  any_adjacent_loop(ks, False{}, w, i, a)

def through_parents(hit: Bool, +w: TileWorld.World, +i: U32, +j: U32, +a: TileWorld.Node, +b: TileWorld.Node) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      +pva = parent_site_of(a)
      adjacent(w, i, parent_site_of(b)) || (Bool.not(TileWorld.is_none(pva)) && adjacent(w, j, pva))

def through_j(hit: Bool, +w: TileWorld.World, +i: U32, +j: U32, +a: TileWorld.Node, +b: TileWorld.Node) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      through_parents(any_adjacent_or_same(w, i, a, neighbours(w, j)), w, i, j, a, b)

def through_i(hit: Bool, +w: TileWorld.World, +i: U32, +j: U32, +a: TileWorld.Node, +b: TileWorld.Node) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      through_j(any_same_task(w, b, neighbours(w, i)), w, i, j, a, b)

# SharesTaskThroughGraph(i, j) for the sites i and j (each test only runs when the ones before it failed).
def shares_task(+w: TileWorld.World, +i: U32, +j: U32) -> Bool:
  +a = TileWorld.node(w, i)
  +b = TileWorld.node(w, j)
  through_i(same_task(a, b), w, i, j, a, b)
