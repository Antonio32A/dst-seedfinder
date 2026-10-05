import Base
import ./world.bend as FilterWorld
import ./anchor.bend as Anchor
import ./dijkstra.bend as Dijkstra
import ./parse.bend as Parse

# The tiles rule (criteria.py check_tiles): a 4-neighbour BFS through any tile, from every land tile of the `from`
# types at once (in tile order) to the first land tile of the `to` types that the queue reaches.
# cells: 4 words per tile: kind (bit 0 start, bit 1 goal), steps + 1 (0 unseen), origin.

type Found is Data:
  Found{steps: U32, origin: U32, goal: U32}

def ids_from(names: List<&2, U32>, +tile_ids: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match names:
    case Nil{}:
      acc
    case Con{+name, rest}:
      +id = Maybe.default(&2, U32, List.get(&2, U32, tile_ids, U32.to_nat(name)), 65535)
      ids_from(rest, tile_ids, Bool.pick(List<&2, U32>, U32.is_eq(id, 65535), acc, id <> acc))

# The world tile ids of vocabulary tiles (tiles the world's map lacks contribute nothing).
def ids_of(+tile_ids: List<&2, U32>, names: List<&2, U32>) -> List<&2, U32>:
  ids_from(names, tile_ids, Nil{})

def kind_of(+tile: U32, +from: List<&2, U32>, +to: List<&2, U32>) -> U32:
  +land = FilterWorld.is_land_tile(tile)
  (Bool.to_u32(land && Parse.contains_id(from, tile)) .|. (Bool.to_u32(land && Parse.contains_id(to, tile)) << 1n) : U32)

type Setup is Type:
  Setup{cells: Array<U32>, queue: Array<U32>, tail: U32}

def write_kind(cells: Array<U32>, +i: U32, +kind: U32, +start: Bool) -> Array<U32>:
  Dijkstra.write_words(cells, (i * 4 : U32), [kind, Bool.to_u32(start), i])

def marked(s: Setup, +i: U32, +kind: U32) -> Setup:
  match s:
    case Setup{cells, queue, +tail}:
      +start = U32.is_eq((kind .&. 1 : U32), 1)
      Setup{write_kind(cells, i, kind, start), queue[tail] <- i, (tail + Bool.to_u32(start) : U32)}

def mark_pair(s: Setup, +i: U32, +word: U32, +from: List<&2, U32>, +to: List<&2, U32>) -> Setup:
  marked(marked(s, i, kind_of((word .&. 65535 : U32), from, to)), (i + 1 : U32), kind_of((word >> 16n : U32), from, to))

def mark_all(words: List<&2, U32>, s: Setup, +i: U32, +count: U32, +from: List<&2, U32>, +to: List<&2, U32>) -> Setup:
  match words:
    case Nil{}:
      s
    case Con{+word, rest}:
      mark_all(rest, mark_pair(s, i, word, from, to), (i + 2 : U32), count, from, to)

# The BFS state: cells, queue, its head and tail, and the result once a goal is popped.
type Walk is Type:
  Walk{cells: Array<U32>, queue: Array<U32>, head: U32, tail: U32, found: Maybe<&2, Found>}

def offsets_x() -> List<&2, U32>:
  [0, 1, 0, 4294967295]

def offsets_y() -> List<&2, U32>:
  [1, 0, 4294967295, 0]

def visit_fresh(fresh: Bool, cells: Array<U32>, queue: Array<U32>, +n: U32, +steps: U32, +origin: U32, +tail: U32) -> Walk:
  match fresh:
    case True{}:
      Walk{Dijkstra.write_words(cells, (n * 4 + 1 : U32), [(steps + 2 : U32), origin]), queue[tail] <- n, 0, (tail + 1 : U32), None{}}
    case False{}:
      Walk{cells, queue, 0, tail, None{}}

def visit_one(got: Array<U32> & U32, queue: Array<U32>, +n: U32, +steps: U32, +origin: U32, +tail: U32) -> Walk:
  (cells, +seen) = got
  visit_fresh(U32.is_zero(seen), cells, queue, n, steps, origin, tail)

def visit_in(inside: Bool, cells: Array<U32>, queue: Array<U32>, +n: U32, +steps: U32, +origin: U32, +tail: U32) -> Walk:
  match inside:
    case True{}:
      visit_one(cells[(n * 4 + 1 : U32)], queue, n, steps, origin, tail)
    case False{}:
      Walk{cells, queue, 0, tail, None{}}

def with_head(w: Walk, +head: U32) -> Walk:
  match w:
    case Walk{cells, queue, _, +tail, found}:
      Walk{cells, queue, head, tail, found}

def neighbours(dxs: List<&2, U32>, dys: List<&2, U32>, w: Walk, +x: U32, +y: U32, +width: U32, +height: U32, +steps: U32, +origin: U32) -> Walk:
  match dxs dys w:
    case Con{+dx, xs} Con{+dy, ys} Walk{cells, queue, +head, +tail, _}:
      +nx = (x + dx : U32)
      +ny = (y + dy : U32)
      neighbours(xs, ys, with_head(visit_in((nx < width : U32) && (ny < height : U32), cells, queue, (ny * width + nx : U32), steps, origin, tail), head), x, y, width, height, steps, origin)
    case _ _ other:
      other

def goal_or_expand(goal: Bool, cells: Array<U32>, queue: Array<U32>, +i: U32, +head: U32, +tail: U32, +width: U32, +height: U32, +steps: U32, +origin: U32) -> Walk:
  match goal:
    case True{}:
      Walk{cells, queue, head, tail, Some{Found{steps, origin, i}}}
    case False{}:
      neighbours(offsets_x(), offsets_y(), Walk{cells, queue, head, tail, None{}}, (i % width : U32), (i / width : U32), width, height, steps, origin)

def expand_tile(got: Array<U32> & List<&2, U32>, queue: Array<U32>, +i: U32, +head: U32, +tail: U32, +width: U32, +height: U32) -> Walk:
  (cells, words) = got
  match words:
    case Con{+kind, Con{+seen, Con{+origin, _}}}:
      goal_or_expand(U32.is_eq((kind .&. 2 : U32), 2), cells, queue, i, head, tail, width, height, (seen - 1 : U32), origin)
    case _:
      Walk{cells, queue, head, tail, None{}}

def popped(got: Array<U32> & U32, cells: Array<U32>, +head: U32, +tail: U32, +width: U32, +height: U32) -> Walk:
  (queue, +i) = got
  expand_tile(Dijkstra.read_words(cells, (i * 4 : U32), 3n), queue, i, (head + 1 : U32), tail, width, height)

def unreachable() -> Found:
  Found{4294967295, 0, 0}

def bfs_step(more: Bool, cells: Array<U32>, queue: Array<U32>, +head: U32, +tail: U32, +width: U32, +height: U32) -> Walk:
  match more:
    case True{}:
      popped(queue[head], cells, head, tail, width, height)
    case False{}:
      Walk{cells, queue, head, tail, Some{unreachable()}}

def bfs(n: Nat, w: Walk, +width: U32, +height: U32) -> Walk:
  match n w:
    case 1n+k Walk{cells, queue, +head, +tail, None{}}:
      bfs(k, bfs_step((head < tail : U32), cells, queue, head, tail, width, height), width, height)
    case _ other:
      other

def found_path(+f: Found) -> Maybe<&2, Found>:
  match f:
    case Found{+steps, _, _}:
      Bool.pick(Maybe<&2, Found>, U32.is_eq(steps, 4294967295), None{}, Some{f})

def result_of(w: Walk) -> Maybe<&2, Found>:
  match w:
    case Walk{_, _, _, _, Some{+f}}:
      found_path(f)
    case _:
      None{}

def walk_of(s: Setup) -> Walk:
  match s:
    case Setup{cells, queue, +tail}:
      Walk{cells, queue, 0, tail, None{}}

# The shortest 4-neighbour step count from a `from` tile to a `to` tile (vocabulary tile names), with the start
# tile owning the BFS region and the goal reached first.
def nearest(+world: FilterWorld.World, +from: List<&2, U32>, +to: List<&2, U32>) -> Maybe<&2, Found>:
  match world:
    case FilterWorld.World{_, +w, +h, +tile_ids, _, _, +tiles, _}:
      +depth = Anchor.depth_of((w * h : U32))
      setup = mark_all(tiles, Setup{[0 : U32^(Nat.add(depth, 3n))], [0 : U32^(Nat.add(depth, 1n))], 0}, 0, (w * h : U32), ids_of(tile_ids, from), ids_of(tile_ids, to))
      result_of(bfs(U32.to_nat((w * h + 2 : U32)), walk_of(setup), w, h))
