import Base
import ../../f32/powf.bend as Powf
import ../../rng/pcg.bend as Pcg
import ../tiles/sitetiles.bend as SiteTiles
import ./cells.bend as CaveCells
import ./shuffle.bend as CaveShuffle

# The growing-tree maze (Maze_GrowingTree, cell size 2, types 3..5): the maze grid G is down-sampled to cells of cs x cs
# (reading G's value byte at the flat index (w * i + j) * cs, which is not the block's cell: the game's bug is
# reproduced), a random unblocked cell is carved, and then repeatedly a cell of the active list is picked with the weight
# powf(u / 2^32, e^-val), carved when it touches exactly one carved cell (and, for type 3, none of the two diagonals
# beyond it), else marked as a wall. A cell is packed as x | y << 16.

type Rules is Data:
  Rules{w: U32, h: U32, windows: Bool, strict: Bool, expo: U32}

type Tree is Type:
  Tree{cells: Array<U32>, active: List<&2, U32>, rng: Pcg.Rng}

def unpack_x(+p: U32) -> U32:
  SiteTiles.unpack_x(p)

def unpack_y(+p: U32) -> U32:
  SiteTiles.unpack_y(p)

def pack(+x: U32, +y: U32) -> U32:
  SiteTiles.pack(x, y)

def try_hit(hit: Bool, cells: Array<U32>, nb: List<&2, U32>, +c: U32, +i: U32, +packed: U32) -> Array<U32> & List<&2, U32>:
  match hit:
    case False{}:
      (cells, nb)
    case True{}:
      cells[i] <- CaveCells.with_lo(c, 3)
      (cells, List.append(&2, U32, nb, packed <> Nil{}))

def try_got(got: Array<U32> & U32, nb: List<&2, U32>, +i: U32, +packed: U32) -> Array<U32> & List<&2, U32>:
  (cells, +c) = got
  try_hit(U32.is_eq((c .&. 16639 : U32), 4), cells, nb, c, i, packed)

def try_if(ok: Bool, cells: Array<U32>, nb: List<&2, U32>, +w: U32, +x: U32, +y: U32) -> Array<U32> & List<&2, U32>:
  match ok:
    case False{}:
      (cells, nb)
    case True{}:
      try_got(cells[CaveCells.index(x, y, w)], nb, CaveCells.index(x, y, w), pack(x, y))

def try_next(got: Array<U32> & List<&2, U32>, ok: Bool, +w: U32, +x: U32, +y: U32) -> Array<U32> & List<&2, U32>:
  (cells, nb) = got
  try_if(ok, cells, nb, w, x, y)

# The carvable neighbours of (x, y) (left, right, up, down) marked 3.
def neighbours(cells: Array<U32>, +w: U32, +h: U32, +x: U32, +y: U32) -> Array<U32> & List<&2, U32>:
  try_next(try_next(try_next(try_if((0 < x : U32), cells, Nil{}, w, (x - 1 : U32), y), (x + 1 < w : U32), w, (x + 1 : U32), y),
    (0 < y : U32), w, x, (y - 1 : U32)), (y + 1 < h : U32), w, x, (y + 1 : U32))

def carve_join(sh: CaveShuffle.Shuffled, cells: Array<U32>, active: List<&2, U32>) -> Tree:
  match sh:
    case CaveShuffle.Shuffled{nbs, rng}:
      Tree{cells, List.append(&2, U32, active, nbs), rng}

def carve_shuffle(got: Array<U32> & List<&2, U32>, active: List<&2, U32>, rng: Pcg.Rng, +windows: Bool) -> Tree:
  (cells, nb) = got
  carve_join(CaveShuffle.small(windows, nb, rng), cells, active)

def carve_marked(cells: Array<U32>, active: List<&2, U32>, rng: Pcg.Rng, +x: U32, +y: U32, +r: Rules) -> Tree:
  match r:
    case Rules{+w, +h, +windows, _, _}:
      carve_shuffle(neighbours(cells, w, h, x, y), active, rng, windows)

# Carve(c): the cell becomes 2 and its uncarved neighbours join the active list in shuffled order.
def carve(t: Tree, +c: U32, +r: Rules) -> Tree:
  match t:
    case Tree{cells, active, rng}:
      match r:
        case Rules{+w, _, _, _, _}:
          carve_marked(CaveCells.set_lo(cells, CaveCells.index(unpack_x(c), unpack_y(c), w), 2), active, rng, unpack_x(c), unpack_y(c), r)

def offset_x(+k: U32) -> U32:
  match k:
    case 0:
      4294967295
    case 1:
      1
    case 2:
      0
    case 3:
      0
    case 4:
      4294967295
    case 5:
      1
    case 6:
      4294967295
    case _:
      1

def offset_y(+k: U32) -> U32:
  match k:
    case 0:
      0
    case 1:
      0
    case 2:
      4294967295
    case 3:
      1
    case 4:
      4294967295
    case 5:
      4294967295
    case 6:
      1
    case _:
      1

def probe_bit(ok: Bool, got: Array<U32> & U32, +bit: U32, +mask: U32) -> Array<U32> & U32:
  (cells, +c) = got
  (cells, (mask .|. Bool.pick(U32, ok && U32.is_eq(CaveCells.lo_of(c), 2), bit, 0) : U32))

# Bit k of the result: the in-bounds cell at offset k (left, right, up, down, up-left, up-right, down-left, down-right)
# holds 2. The first n offsets are probed.
def probe_mask(n: Nat, got: Array<U32> & U32, +w: U32, +h: U32, +x: U32, +y: U32, +k: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, +mask) = got
      +nx = (x + offset_x(k) : U32)
      +ny = (y + offset_y(k) : U32)
      +ok = (nx < w : U32) && (ny < h : U32)
      probe_mask(p, probe_bit(ok, cells[CaveCells.index(Bool.pick(U32, ok, nx, 0), Bool.pick(U32, ok, ny, 0), w)], (1 << U32.to_nat(k) : U32), mask), w, h, x, y, (k + 1 : U32))

def is_single(+m: U32) -> Bool:
  U32.is_eq(m, 1) || U32.is_eq(m, 2) || U32.is_eq(m, 4) || U32.is_eq(m, 8)

# The diagonal bits beyond the single carved neighbour m.
def far_bits(+m: U32) -> U32:
  match m:
    case 1:
      160
    case 2:
      80
    case 4:
      192
    case _:
      48

def carvable(strict: Bool, +mask: U32) -> Bool:
  match strict:
    case False{}:
      is_single((mask .&. 15 : U32))
    case True{}:
      is_single((mask .&. 15 : U32)) && U32.is_zero((mask .&. far_bits((mask .&. 15 : U32)) : U32))

def carvable_of(got: Array<U32> & U32, strict: Bool) -> Array<U32> & Bool:
  (cells, +mask) = got
  (cells, carvable(strict, mask))

def can_carve(cells: Array<U32>, +x: U32, +y: U32, +r: Rules) -> Array<U32> & Bool:
  match r:
    case Rules{+w, +h, _, +strict, _}:
      carvable_of(probe_mask(8n, (cells, 0), w, h, x, y, 0), strict)

def remove_step(got: List<&2, U32> & U32, +h: U32) -> List<&2, U32> & U32:
  (rest, +e) = got
  (h <> rest, e)

# List.remove: the k-th item and the list without it.
def remove_at(k: Nat, xs: List<&2, U32>) -> List<&2, U32> & U32:
  match k xs:
    case 0n Nil{}:
      (Nil{}, 0)
    case 0n Con{+h, t}:
      (t, h)
    case 1n+p Nil{}:
      (Nil{}, 0)
    case 1n+p Con{+h, t}:
      remove_step(remove_at(p, t), h)

def width_of(+r: Rules) -> U32:
  match r:
    case Rules{+w, _, _, _, _}:
      w

def pick_index(+u: U32, +size: U32, +r: Rules) -> U32:
  match r:
    case Rules{_, _, +windows, _, +expo}:
      Powf.maze_pick(windows, u, expo, size)

def pop_apply(ok: Bool, cells: Array<U32>, active: List<&2, U32>, rng: Pcg.Rng, +cell: U32, +r: Rules) -> Tree:
  match ok:
    case True{}:
      carve(Tree{cells, active, rng}, cell, r)
    case False{}:
      Tree{CaveCells.set_lo(cells, CaveCells.index(unpack_x(cell), unpack_y(cell), width_of(r)), 1), active, rng}

def pop_test(got: Array<U32> & Bool, active: List<&2, U32>, rng: Pcg.Rng, +cell: U32, +r: Rules) -> Tree:
  (cells, ok) = got
  pop_apply(ok, cells, active, rng, cell, r)

def pop_removed(removed: List<&2, U32> & U32, cells: Array<U32>, rng: Pcg.Rng, +r: Rules) -> Tree:
  (active, +cell) = removed
  pop_test(can_carve(cells, unpack_x(cell), unpack_y(cell), r), active, rng, cell, r)

def pop_drawn(drawn: U32 & Pcg.Rng, cells: Array<U32>, +active: List<&2, U32>, +r: Rules) -> Tree:
  (+u, rng) = drawn
  pop_removed(remove_at(U32.to_nat(pick_index(u, U32.from_nat(List.length(&2, U32, active)), r)), active), cells, rng, r)

# One pop of the active list: a raw pcg32 draw, the weighted pick and the carve test.
def pop(t: Tree, +r: Rules) -> Tree:
  match t:
    case Tree{cells, +active, rng}:
      pop_drawn(Pcg.draw(rng), cells, active, r)

def keep_going(t: Tree) -> Tree & Bool:
  match t:
    case Tree{cells, +active, rng}:
      (Tree{cells, active, rng}, Bool.not(List.is_empty(&2, U32, active)))

# Pops while the active list is not empty, at most n times.
def pops(n: Nat, got: Tree & Bool, +r: Rules) -> Tree & Bool:
  match n:
    case 0n:
      got
    case 1n+p:
      (t, go) = got
      match go:
        case False{}:
          (t, False{})
        case True{}:
          pops(p, keep_going(pop(t, r)), r)

def popcount4(+m: U32) -> U32:
  ((m .&. 1) + ((m >> 1n) .&. 1) + ((m >> 2n) .&. 1) + ((m >> 3n) .&. 1) : U32)

# The cell next to (x, y) in the direction of its single carved neighbour m (1 left, 2 right, 4 up, 8 down).
def neighbour_of(+m: U32, +x: U32, +y: U32) -> U32:
  match m:
    case 1:
      pack((x - 1 : U32), y)
    case 2:
      pack((x + 1 : U32), y)
    case 4:
      pack(x, (y - 1 : U32))
    case _:
      pack(x, (y + 1 : U32))

def dead_neighbour(got: Array<U32> & U32, +x: U32, +y: U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  (cells, +m) = got
  (cells, SiteTiles.add_if(U32.is_eq(popcount4(m), 2), pack(x, y), acc))

def dead_probe(single: Bool, cells: Array<U32>, +m: U32, +x: U32, +y: U32, +r: Rules, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match single:
    case False{}:
      (cells, acc)
    case True{}:
      match r:
        case Rules{+w, +h, _, _, _}:
          dead_neighbour(probe_mask(4n, (cells, 0), w, h, unpack_x(neighbour_of(m, x, y)), unpack_y(neighbour_of(m, x, y)), 0), x, y, acc)

def dead_single(got: Array<U32> & U32, +x: U32, +y: U32, +r: Rules, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  (cells, +m) = got
  dead_probe(U32.is_eq(popcount4(m), 1), cells, m, x, y, r, acc)

def dead_masked(carved: Bool, cells: Array<U32>, +x: U32, +y: U32, +r: Rules, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match carved:
    case False{}:
      (cells, acc)
    case True{}:
      match r:
        case Rules{+w, +h, _, _, _}:
          dead_single(probe_mask(4n, (cells, 0), w, h, x, y, 0), x, y, r, acc)

def dead_lo(got: Array<U32> & U32, +x: U32, +y: U32, +r: Rules, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  (cells, +c) = got
  dead_masked(U32.is_eq(CaveCells.lo_of(c), 2), cells, x, y, r, acc)

def dead_row(n: Nat, got: Array<U32> & List<&2, U32>, +x: U32, +y: U32, +r: Rules) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, acc) = got
      dead_row(p, dead_lo(cells[CaveCells.index(x, y, width_of(r))], x, y, r, acc), (x + 1 : U32), y, r)

def dead_rows(n: Nat, got: Array<U32> & List<&2, U32>, +y: U32, +r: Rules) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      got
    case 1n+p:
      dead_rows(p, dead_row(U32.to_nat(width_of(r)), got, 0, y, r), (y - 1 : U32), r)

# Maze_GT_CollectDeadEnds: the carved cells with one carved neighbour whose neighbour has exactly two, rows from the
# bottom up, as packed cells of the sampled grid.
def dead_ends(cells: Array<U32>, +h: U32, +r: Rules) -> Array<U32> & List<&2, U32>:
  dead_rows(U32.to_nat(h), (cells, Nil{}), (h - 1 : U32), r)

type Build is Type:
  Build{g: Array<U32>, g2: Array<U32>, free: List<&2, U32>}

def build_write(+blocked: Bool, got: Array<U32> & U32, g2: Array<U32>, free: List<&2, U32>, +j: U32, +i: U32, +w2: U32) -> Build:
  (g, +c) = got
  g2[CaveCells.index(j, i, w2)] <- CaveCells.with_hi(CaveCells.lo_of(c), Bool.pick(U32, blocked, 255, 175))
  Build{g, g2, SiteTiles.add_if(Bool.not(blocked), pack(j, i), free)}

def build_sample(got: Array<U32> & Bool, g2: Array<U32>, free: List<&2, U32>, +j: U32, +i: U32, +w: U32, +w2: U32, +cs: U32) -> Build:
  (g, blocked) = got
  build_write(blocked, g[((w * i + j) * cs : U32)], g2, free, j, i, w2)

def build_cell(b: Build, +j: U32, +i: U32, +w: U32, +w2: U32, +cs: U32) -> Build:
  match b:
    case Build{g, g2, free}:
      build_sample(CaveCells.block_blocked(g, j, i, cs, w), g2, free, j, i, w, w2, cs)

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

type Both is Type:
  Both{g: Array<U32>, g2: Array<U32>}

def spread(n: Nat, g: Array<U32>, +k: U32, +i: U32, +j: U32, +w: U32, +cs: U32, +lo: U32) -> Array<U32>:
  match n:
    case 0n:
      g
    case 1n+p:
      spread(p, CaveCells.set_lo(g, CaveCells.index((j * cs + k % cs : U32), (i * cs + k / cs : U32), w), lo), (k + 1 : U32), i, j, w, cs, lo)

def spread_got(got: Array<U32> & U32, g: Array<U32>, +i: U32, +j: U32, +w: U32, +cs: U32) -> Both:
  (g2, +c) = got
  Both{spread(U32.to_nat((cs * cs : U32)), g, 0, i, j, w, cs, Bool.pick(U32, U32.is_eq(CaveCells.lo_of(c), 4), 1, CaveCells.lo_of(c))), g2}

def spread_cell(b: Both, +i: U32, +j: U32, +w: U32, +w2: U32, +cs: U32) -> Both:
  match b:
    case Both{g, g2}:
      spread_got(g2[CaveCells.index(j, i, w2)], g, i, j, w, cs)

def spread_row(n: Nat, b: Both, +i: U32, +j: U32, +w: U32, +w2: U32, +cs: U32) -> Both:
  match n:
    case 0n:
      b
    case 1n+p:
      spread_row(p, spread_cell(b, i, j, w, w2, cs), i, (j + 1 : U32), w, w2, cs)

def spread_rows(n: Nat, b: Both, +i: U32, +w: U32, +w2: U32, +cs: U32) -> Both:
  match n:
    case 0n:
      b
    case 1n+p:
      spread_rows(p, spread_row(U32.to_nat(w2), b, i, 0, w, w2, cs), (i + 1 : U32), w, w2, cs)

# The maze grid with the sampled cells' values spread back over their blocks, the dead ends (packed cells of the sampled
# grid, in Maze_GT_CollectDeadEnds order) and the PCG state.
type Grown is Type:
  Grown{g: Array<U32>, dead: List<&2, U32>, rng: Pcg.Rng}

def grown_of(b: Both, dead: List<&2, U32>, rng: Pcg.Rng) -> Grown:
  match b:
    case Both{g, _}:
      Grown{g, List.reverse(&2, U32, dead), rng}

def grown_spread(got: Array<U32> & List<&2, U32>, g: Array<U32>, rng: Pcg.Rng, +w: U32, +w2: U32, +h2: U32, +cs: U32) -> Grown:
  (cells, dead) = got
  grown_of(spread_rows(U32.to_nat(h2), Both{g, cells}, 0, w, w2, cs), dead, rng)

def grown_finish(got: Tree & Bool, g: Array<U32>, +w: U32, +w2: U32, +h2: U32, +cs: U32, +r: Rules) -> Grown:
  (t, _) = got
  match t:
    case Tree{cells, _, rng}:
      grown_spread(dead_ends(cells, h2, r), g, rng, w, w2, h2, cs)

def grown_first(pts: List<&2, U32>, g: Array<U32>, g2: Array<U32>, rng: Pcg.Rng, +w: U32, +w2: U32, +h2: U32, +cs: U32, +r: Rules) -> Grown:
  match pts:
    case Nil{}:
      grown_finish((Tree{g2, Nil{}, rng}, False{}), g, w, w2, h2, cs, r)
    case Con{+first, _}:
      grown_finish(pops(U32.to_nat((w2 * h2 : U32)), keep_going(carve(Tree{g2, Nil{}, rng}, first, r)), r), g, w, w2, h2, cs, r)

def grown_shuffled(sh: CaveShuffle.Shuffled, g: Array<U32>, g2: Array<U32>, +w: U32, +w2: U32, +h2: U32, +cs: U32, +r: Rules) -> Grown:
  match sh:
    case CaveShuffle.Shuffled{pts, rng}:
      grown_first(pts, g, g2, rng, w, w2, h2, cs, r)

def grown_built(b: Build, rng: Pcg.Rng, +windows: Bool, +w: U32, +w2: U32, +h2: U32, +cs: U32, +r: Rules) -> Grown:
  match b:
    case Build{g, g2, free}:
      grown_shuffled(CaveShuffle.large(windows, List.reverse(&2, U32, free), rng), g, g2, w, w2, h2, cs, r)

# Maze_GrowingTree on the maze grid `g` (width w) sampled to w2 x h2 cells of cs x cs; `expo` is the maze exponent
# (float)pow(e, -val) as float bits and `strict` selects the type 3 carve test.
def grow(+windows: Bool, g: Array<U32>, +w: U32, +w2: U32, +h2: U32, +cs: U32, +expo: U32, +strict: Bool, rng: Pcg.Rng) -> Grown:
  grown_built(build_rows(U32.to_nat(h2), Build{g, CaveCells.new(w2, h2, 65535), Nil{}}, 0, w, w2, cs), rng, windows, w, w2, h2, cs,
    Rules{w2, h2, windows, strict, expo})
