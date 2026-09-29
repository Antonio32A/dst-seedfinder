import Base
import ../../rng/pcg.bend as Pcg
import ../tiles/sitetiles.bend as SiteTiles
import ./cells.bend as CaveCells
import ./shuffle.bend as CaveShuffle

# GetPointsForMetaMaze (Maze_MetaMaze): a depth-first random walk over the cells of cs x cs tiles of the maze grid that
# are free of "not maze" tiles. It opens the wall between consecutive cells, backtracks through a stack, and reports for
# every cell its set of open sides (bit 0 +y, 1 +x, 2 -y, 3 -x), negated for the dead ends that survive PruneDeadEnds.
# A cell is packed as x | y << 16.

type Dims is Data:
  Dims{w: U32, h: U32, windows: Bool}

type Walk is Type:
  Walk{cells: Array<U32>, stack: List<&2, U32>, dead: List<&2, U32>, cur: U32, steps: U32, fwd: Bool, rng: Pcg.Rng}

# A cell of the result: the key (open sides, negative for a dead end) and the packed cell.
type Keyed is Data:
  Keyed{key: U32, cell: U32}

def unpack_x(+p: U32) -> U32:
  SiteTiles.unpack_x(p)

def unpack_y(+p: U32) -> U32:
  SiteTiles.unpack_y(p)

def pack(+x: U32, +y: U32) -> U32:
  SiteTiles.pack(x, y)

def free_add(ok: Bool, +c: U32, nb: List<&2, U32>, +packed: U32) -> List<&2, U32>:
  match ok:
    case True{}:
      List.append(&2, U32, nb, packed <> Nil{})
    case False{}:
      nb

def free_got(got: Array<U32> & U32, nb: List<&2, U32>, +bounds: Bool, +packed: U32) -> Array<U32> & List<&2, U32>:
  (cells, +c) = got
  (cells, free_add(bounds && U32.is_zero((CaveCells.hi_of(c) .&. 80 : U32)), c, nb, packed))

def free_at(+bounds: Bool, cells: Array<U32>, nb: List<&2, U32>, +w: U32, +x: U32, +y: U32) -> Array<U32> & List<&2, U32>:
  free_got(cells[CaveCells.index(Bool.pick(U32, bounds, x, 0), Bool.pick(U32, bounds, y, 0), w)], nb, bounds, pack(x, y))

def free_next(got: Array<U32> & List<&2, U32>, bounds: Bool, +w: U32, +x: U32, +y: U32) -> Array<U32> & List<&2, U32>:
  (cells, nb) = got
  free_at(bounds, cells, nb, w, x, y)

# Maze_Neighbours: the four neighbours in the grid not yet visited (hi & 0x50 == 0): up, down, right, left.
def free_neighbours(cells: Array<U32>, +w: U32, +h: U32, +x: U32, +y: U32) -> Array<U32> & List<&2, U32>:
  free_next(free_next(free_next(free_at((0 < y : U32), cells, Nil{}, w, x, (y - 1 : U32)), (y + 1 < h : U32), w, x, (y + 1 : U32)),
    (x + 1 < w : U32), w, (x + 1 : U32), y), (0 < x : U32), w, (x - 1 : U32), y)

# OpenWall: the wall bits removed from the walker's cell and from the next cell for a step to the next cell.
def cur_wall_mask(+cx: U32, +cy: U32, +nx: U32, +ny: U32) -> U32:
  Bool.pick(U32, (cy < ny : U32), 254, Bool.pick(U32, (nx < cx : U32), 247, Bool.pick(U32, (cx < nx : U32), 253, 251)))

def next_wall_mask(+cx: U32, +cy: U32, +nx: U32, +ny: U32) -> U32:
  Bool.pick(U32, (cy < ny : U32), 251, Bool.pick(U32, (nx < cx : U32), 253, Bool.pick(U32, (cx < nx : U32), 247, 254)))

def open_wall(cells: Array<U32>, +cur: U32, +nxt: U32, +w: U32) -> Array<U32>:
  +ci = CaveCells.index(unpack_x(cur), unpack_y(cur), w)
  +ni = CaveCells.index(unpack_x(nxt), unpack_y(nxt), w)
  +cm = cur_wall_mask(unpack_x(cur), unpack_y(cur), unpack_x(nxt), unpack_y(nxt))
  +nm = next_wall_mask(unpack_x(cur), unpack_y(cur), unpack_x(nxt), unpack_y(nxt))
  CaveCells.and_hi(CaveCells.and_hi(CaveCells.set_lo(cells, ni, 5), ci, cm), ni, nm)

def last_of(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{+x, Nil{}}:
      x
    case Con{_, rest}:
      last_of(rest)

def without_last(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, Nil{}}:
      Nil{}
    case Con{+x, rest}:
      x <> without_last(rest)

def dead_add(fwd: Bool, +cur: U32, dead: List<&2, U32>) -> List<&2, U32>:
  match fwd:
    case True{}:
      cur <> dead
    case False{}:
      dead

# Backtracks to the cell on top of the stack (a dead end when the walk just arrived at the cell), or stops when the stack
# is empty.
def advance_back(cells: Array<U32>, stack: List<&2, U32>, dead: List<&2, U32>, +cur: U32, +steps: U32, +fwd: Bool, rng: Pcg.Rng) -> Walk & Bool:
  match stack:
    case Nil{}:
      (Walk{cells, Nil{}, dead, cur, steps, fwd, rng}, False{})
    case Con{+top, rest}:
      (Walk{cells, rest, dead_add(fwd, cur, dead), top, steps, False{}, rng}, True{})

def stack_after(again: Bool, +cur: U32, stack: List<&2, U32>) -> List<&2, U32>:
  match again:
    case True{}:
      cur <> stack
    case False{}:
      stack

def advance_forward(sh: CaveShuffle.Shuffled, cells: Array<U32>, stack: List<&2, U32>, dead: List<&2, U32>, +cur: U32, +steps: U32, +w: U32) -> Walk & Bool:
  match sh:
    case CaveShuffle.Shuffled{+nbs, rng}:
      +nxt = last_of(nbs)
      (Walk{CaveCells.or_hi(open_wall(cells, cur, nxt, w), CaveCells.index(unpack_x(nxt), unpack_y(nxt), w), 16),
        stack_after(Bool.not(List.is_empty(&2, U32, without_last(nbs))), cur, cur <> stack), dead, nxt, (steps + 1 : U32), True{}, rng}, True{})

def advance_branch(none: Bool, cells: Array<U32>, +nb: List<&2, U32>, stack: List<&2, U32>, dead: List<&2, U32>, +cur: U32, +steps: U32, +fwd: Bool,
    rng: Pcg.Rng, +d: Dims) -> Walk & Bool:
  match none:
    case True{}:
      advance_back(cells, stack, dead, cur, steps, fwd, rng)
    case False{}:
      match d:
        case Dims{+w, _, +windows}:
          advance_forward(CaveShuffle.small(windows, nb, rng), cells, stack, dead, cur, steps, w)

def advance_open(got: Array<U32> & List<&2, U32>, stack: List<&2, U32>, dead: List<&2, U32>, +cur: U32, +steps: U32, +fwd: Bool, rng: Pcg.Rng,
    +d: Dims) -> Walk & Bool:
  (cells, +nb) = got
  match d:
    case Dims{+w, _, _}:
      advance_branch(List.is_empty(&2, U32, nb), CaveCells.set_lo(cells, CaveCells.index(unpack_x(cur), unpack_y(cur), w), 5), nb, stack, dead, cur, steps, fwd, rng, d)

def advance_gate(halt: Bool, cells: Array<U32>, stack: List<&2, U32>, dead: List<&2, U32>, +cur: U32, +steps: U32, +fwd: Bool, rng: Pcg.Rng,
    +d: Dims) -> Walk & Bool:
  match halt:
    case True{}:
      (Walk{cells, stack, dead, cur, steps, fwd, rng}, False{})
    case False{}:
      match d:
        case Dims{+w, +h, _}:
          advance_open(free_neighbours(cells, w, h, unpack_x(cur), unpack_y(cur)), stack, dead, cur, steps, fwd, rng, d)

# One iteration of the walk; False when it ends.
def advance(wk: Walk, +d: Dims) -> Walk & Bool:
  match wk:
    case Walk{cells, +stack, dead, +cur, +steps, fwd, rng}:
      advance_gate(List.is_empty(&2, U32, stack) && Bool.not(U32.is_eq(steps, 1)), cells, stack, dead, cur, steps, fwd, rng, d)

def walk(n: Nat, got: Walk & Bool, +d: Dims) -> Walk & Bool:
  match n:
    case 0n:
      got
    case 1n+p:
      (wk, go) = got
      match go:
        case False{}:
          (wk, False{})
        case True{}:
          walk(p, advance(wk, d), d)

# The cell at the side opposite the open side d of cell (x, y) (Maze_IndexOppositeOpening).
def opposite(+d: U32, +x: U32, +y: U32, +w: U32) -> U32:
  match d:
    case 2:
      ((x - 1 : U32) + y * w : U32)
    case 4:
      (x + (y + 1 : U32) * w : U32)
    case 1:
      (x + (y - 1 : U32) * w : U32)
    case _:
      ((x + 1 : U32) + y * w : U32)

def popcount4(+m: U32) -> U32:
  ((m .&. 1) + ((m >> 1n) .&. 1) + ((m >> 2n) .&. 1) + ((m >> 3n) .&. 1) : U32)

def sides_of(+c: U32) -> U32:
  ((CaveCells.hi_of(c) .^. 15) .&. 15 : U32)

def prune_test(got: Array<U32> & U32, +inside: Bool, acc: List<&2, U32>, +p: U32) -> Array<U32> & List<&2, U32>:
  (cells, +c) = got
  (cells, SiteTiles.add_if(inside && U32.is_eq(popcount4(CaveCells.hi_of(c)), 2), p, acc))

def prune_cell(got: Array<U32> & U32, +p: U32, +w: U32, +h: U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  (cells, +c) = got
  +idx = opposite(sides_of(c), unpack_x(p), unpack_y(p), w)
  +inside = (idx < (w * h : U32) : U32)
  prune_test(cells[Bool.pick(U32, inside, idx, 0)], inside, acc, p)

# PruneDeadEnds: the dead ends whose opposite cell has exactly two walls left.
def prune(dead: List<&2, U32>, got: Array<U32> & List<&2, U32>, +w: U32, +h: U32) -> Array<U32> & List<&2, U32>:
  match dead:
    case Nil{}:
      got
    case Con{+p, rest}:
      (cells, acc) = got
      prune(rest, prune_cell(cells[CaveCells.index(unpack_x(p), unpack_y(p), w)], p, w, h, acc), w, h)

def member(xs: List<&2, U32>, +p: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+x, rest}:
      U32.is_eq(x, p) || member(rest, p)

def keyed_add(hit: Bool, +k: Keyed, acc: List<&2, Keyed>) -> List<&2, Keyed>:
  match hit:
    case True{}:
      k <> acc
    case False{}:
      acc

def out_cell(got: Array<U32> & U32, +kept: List<&2, U32>, +j: U32, +i: U32, acc: List<&2, Keyed>) -> Array<U32> & List<&2, Keyed>:
  (cells, +c) = got
  (cells, keyed_add(U32.is_zero((CaveCells.hi_of(c) .&. 64 : U32)) && Bool.not(U32.is_zero(sides_of(c))),
    Keyed{Bool.pick(U32, member(kept, pack(j, i)), (0 - sides_of(c) : U32), sides_of(c)), pack(j, i)}, acc))

def out_row(n: Nat, got: Array<U32> & List<&2, Keyed>, +kept: List<&2, U32>, +j: U32, +i: U32, +w: U32) -> Array<U32> & List<&2, Keyed>:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, acc) = got
      out_row(p, out_cell(cells[CaveCells.index(j, i, w)], kept, j, i, acc), kept, (j + 1 : U32), i, w)

def out_rows(n: Nat, got: Array<U32> & List<&2, Keyed>, +kept: List<&2, U32>, +i: U32, +w: U32) -> Array<U32> & List<&2, Keyed>:
  match n:
    case 0n:
      got
    case 1n+p:
      out_rows(p, out_row(U32.to_nat(w), got, kept, 0, i, w), kept, (i + 1 : U32), w)

def key_of(+k: Keyed) -> U32:
  match k:
    case Keyed{+key, _}:
      key

def bucket(xs: List<&2, Keyed>, +key: U32) -> List<&2, Keyed>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+k, rest}:
      keyed_add(U32.is_eq(key_of(k), key), k, bucket(rest, key))

# The cells ordered by ascending key (the std::map<int, ...> order), scan order within a key.
def by_key(n: Nat, +xs: List<&2, Keyed>, +key: U32) -> List<&2, Keyed>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      List.append(&2, Keyed, bucket(xs, key), by_key(p, xs, (key + 1 : U32)))

type Build is Type:
  Build{g: Array<U32>, g2: Array<U32>, free: List<&2, U32>}

def build_write(got: Array<U32> & Bool, g2: Array<U32>, free: List<&2, U32>, +j: U32, +i: U32, +w2: U32) -> Build:
  (g, +blocked) = got
  g2[CaveCells.index(j, i, w2)] <- CaveCells.with_hi(5, Bool.pick(U32, blocked, 255, 175))
  Build{g, g2, SiteTiles.add_if(Bool.not(blocked), pack(j, i), free)}

def build_cell(b: Build, +j: U32, +i: U32, +w: U32, +w2: U32, +cs: U32) -> Build:
  match b:
    case Build{g, g2, free}:
      build_write(CaveCells.block_blocked(g, j, i, cs, w), g2, free, j, i, w2)

def build_row(n: Nat, b: Build, +j: U32, +i: U32, +w: U32, +w2: U32, +cs: U32) -> Build:
  match n:
    case 0n:
      b
    case 1n+p:
      build_row(p, build_cell(b, j, i, w, w2, cs), (j + 1 : U32), i, w, w2, cs)

def build_rows(n: Nat, b: Build, +i: U32, +w: U32, +w2: U32, +cs: U32) -> Build:
  match n:
    case 0n:
      b
    case 1n+p:
      build_rows(p, build_row(U32.to_nat(w2), b, 0, i, w, w2, cs), (i + 1 : U32), w, w2, cs)

# The cells of the walk and the PCG state.
type Meta is Data:
  Meta{points: List<&2, Keyed>, rng: Pcg.Rng}

def meta_points(got: Array<U32> & List<&2, Keyed>, rng: Pcg.Rng) -> Meta:
  (_, points) = got
  Meta{by_key(31n, List.reverse(&2, Keyed, points), 4294967281), rng}

def meta_scan(got: Array<U32> & List<&2, U32>, rng: Pcg.Rng, +w2: U32, +h2: U32) -> Meta:
  (cells, kept) = got
  meta_points(out_rows(U32.to_nat(h2), (cells, Nil{}), List.reverse(&2, U32, kept), 0, w2), rng)

def meta_pruned(got: Walk & Bool, +w2: U32, +h2: U32) -> Meta:
  (wk, _) = got
  match wk:
    case Walk{cells, _, dead, _, _, _, rng}:
      meta_scan(prune(List.reverse(&2, U32, dead), (cells, Nil{}), w2, h2), rng, w2, h2)

def meta_walk(sh: CaveShuffle.Shuffled, g2: Array<U32>, +d: Dims) -> Meta:
  match sh:
    case CaveShuffle.Shuffled{+pts, rng}:
      match d:
        case Dims{+w2, +h2, _}:
          meta_pruned(walk(U32.to_nat((w2 * h2 * 4 + 4 : U32)), (Walk{CaveCells.or_hi(g2, CaveCells.index(unpack_x(last_of(pts)), unpack_y(last_of(pts)), w2), 16),
            Nil{}, Nil{}, last_of(pts), 1, True{}, rng}, True{}), d), w2, h2)

def meta_free(empty: Bool, sh: CaveShuffle.Shuffled, g2: Array<U32>, +d: Dims) -> Meta:
  match empty:
    case True{}:
      match sh:
        case CaveShuffle.Shuffled{_, rng}:
          Meta{Nil{}, rng}
    case False{}:
      meta_walk(sh, g2, d)

def meta_built(b: Build, rng: Pcg.Rng, +d: Dims) -> Meta:
  match b:
    case Build{_, g2, +free}:
      match d:
        case Dims{_, _, +windows}:
          meta_free(List.is_empty(&2, U32, free), CaveShuffle.large(windows, List.reverse(&2, U32, free), rng), g2, d)

# GetPointsForMetaMaze on the maze grid `g` (width w) sampled to w2 x h2 cells of cs x cs. The cells (x = j, y = i in the
# sampled grid) come in ascending key order; the caller scales them by cs. An empty maze area gives no cells and no draws.
def meta_maze(+windows: Bool, g: Array<U32>, +w: U32, +w2: U32, +h2: U32, +cs: U32, rng: Pcg.Rng) -> Meta:
  meta_built(build_rows(U32.to_nat(h2), Build{g, CaveCells.new(w2, h2, 65535), Nil{}}, 0, w, w2, cs), rng, Dims{w2, h2, windows})
