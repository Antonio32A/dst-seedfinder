import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../lua/sort.bend as LuaSort
import ../storygen/graph.bend as StoryGraph
import ../storygen/order.bend as StoryOrder
import ../storygen/region.bend as StoryRegion
import ../worldsim/cave/maze.bend as WorldCaveMaze

# The cells of a meta maze as the Lua side of forest_map.Generate reads them (xs[idx], ys[idx], types[idx] with idx from
# 1), and the `distances` table sorted by the squared distance to the maze entrance's centroid.

def found_nth(found: List<&2, WorldCaveMaze.Found>, +k: U32) -> WorldCaveMaze.Found:
  match found:
    case Nil{}:
      WorldCaveMaze.Found{0, 0, 0}
    case Con{+f, rest}:
      Bool.pick(WorldCaveMaze.Found, U32.is_zero(k), f, found_nth(rest, (k - 1 : U32)))

# The cell idx (1-based).
def cell(+found: List<&2, WorldCaveMaze.Found>, +idx: U32) -> WorldCaveMaze.Found:
  found_nth(found, (idx - 1 : U32))

def key_of(+f: WorldCaveMaze.Found) -> U32:
  match f:
    case WorldCaveMaze.Found{+key, _, _}:
      key

def x_of(+f: WorldCaveMaze.Found) -> U32:
  match f:
    case WorldCaveMaze.Found{_, +x, _}:
      x

def y_of(+f: WorldCaveMaze.Found) -> U32:
  match f:
    case WorldCaveMaze.Found{_, _, +y}:
      y

# math.abs(types[idx])
def magnitude(+key: U32) -> U32:
  Bool.pick(U32, (key >= 2147483648 : U32), (0 - key : U32), key)

# types[idx] > 0
def positive(+key: U32) -> Bool:
  Bool.not(U32.is_zero(key)) && (key < 2147483648 : U32)

# A cell with a single exit.
def is_end(+m: U32) -> Bool:
  U32.is_eq(m, 1) || U32.is_eq(m, 2) || U32.is_eq(m, 4) || U32.is_eq(m, 8)

def with_key(found: List<&2, WorldCaveMaze.Found>, +k: U32, +key: U32) -> List<&2, WorldCaveMaze.Found>:
  match found:
    case Nil{}:
      Nil{}
    case Con{+f, +rest}:
      Bool.pick(WorldCaveMaze.Found, U32.is_zero(k), WorldCaveMaze.Found{key, x_of(f), y_of(f)}, f) <> with_key(rest, (k - 1 : U32), key)

# types[idx] = key
def keyed(found: List<&2, WorldCaveMaze.Found>, +idx: U32, +key: U32) -> List<&2, WorldCaveMaze.Found>:
  with_key(found, (idx - 1 : U32), key)

def ends_add(single: Bool, +idx: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match single:
    case True{}:
      idx <> tail
    case False{}:
      tail

# The idx of the single-exit cells in the order of `order`.
def ends(order: List<&2, U32>, +found: List<&2, WorldCaveMaze.Found>) -> List<&2, U32>:
  match order:
    case Nil{}:
      Nil{}
    case Con{+idx, rest}:
      ends_add(is_end(magnitude(key_of(cell(found, idx)))), idx, ends(rest, found))

def without_nth(xs: List<&2, U32>, +k: U32) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, +rest}:
      Bool.pick(List<&2, U32>, U32.is_zero(k), rest, x <> without_nth(rest, (k - 1 : U32)))

def last_of(+xs: List<&2, U32>) -> U32:
  StoryOrder.nth_or_last(xs, (U32.from_nat(List.length(&2, U32, xs)) - 1 : U32), 0)

type Dist is Data:
  Dist{keys: List<&2, F64Repr.F64>}

def key_nth(keys: List<&2, F64Repr.F64>, +k: U32) -> F64Repr.F64:
  match keys:
    case Nil{}:
      F64Repr.zero()
    case Con{+d, rest}:
      F64Repr.pick(U32.is_zero(k), d, key_nth(rest, (k - 1 : U32)))

def dist_lt(d: Dist, a: U32, b: U32) -> Dist & Bool:
  match d:
    case Dist{+keys}:
      (Dist{keys}, F64Cmp.lt(key_nth(keys, (a - 1 : U32)), key_nth(keys, (b - 1 : U32))))

def squared(+cx: F64Repr.F64, +cy: F64Repr.F64, +x: U32, +y: U32) -> F64Repr.F64:
  +dx = F64Arith.sub(cx, F64Repr.from_i32(x))
  +dy = F64Arith.sub(cy, F64Repr.from_i32(y))
  F64Arith.add(F64Arith.mul(dx, dx), F64Arith.mul(dy, dy))

def dist_keys(found: List<&2, WorldCaveMaze.Found>, +cx: F64Repr.F64, +cy: F64Repr.F64) -> List<&2, F64Repr.F64>:
  match found:
    case Nil{}:
      Nil{}
    case Con{+f, rest}:
      squared(cx, cy, x_of(f), y_of(f)) <> dist_keys(rest, cx, cy)

def indices(n: Nat, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      i <> indices(p, (i + 1 : U32))

def sorted_read(n: Nat, w: LuaSort.Sorting<Dist>) -> List<&2, U32>:
  match w:
    case LuaSort.Sorting{_, items, _}:
      StoryRegion.read_list(n, items[1], 1)

# table.sort(distances, function(a, b) return a.dist < b.dist end) over the cells: the idx in sorted order.
def sorted(+found: List<&2, WorldCaveMaze.Found>, +cx: F64Repr.F64, +cy: F64Repr.F64) -> List<&2, U32>:
  +n = U32.from_nat(List.length(&2, WorldCaveMaze.Found, found))
  sorted_read(U32.to_nat(n), LuaSort.sort(~Dist, ~dist_lt, Dist{dist_keys(found, cx, cy)}, StoryRegion.fill_from(indices(U32.to_nat(n), 1), [0 : U32^10n], 1), n, StoryGraph.none()))
