import Base
import ../worldsim/tiles/table.bend as TileTable

# The landmasses of a world (docs/config.md section 4 G): the maximal sets of land tiles joined through their 4
# orthogonal neighbours, found by a union-find over each row's runs of land and numbered in scan order.

# Tiles x0..x1 of a row (inclusive) in landmass `mass` (a run id until the landmasses are numbered).
type Run is Data:
  Run{x0: U32, x1: U32, mass: U32}

# A landmass: its tile count and inclusive tile bounds.
type Mass is Data:
  Mass{area: U32, tx0: U32, ty0: U32, tx1: U32, ty1: U32}

# Per row its runs, and per landmass its tiles and bounds.
type Masses is Data:
  Masses{width: U32, rows: TileTable.Tree<List<&2, Run>>, masses: TileTable.Tree<Mass>}

def none() -> U32:
  4294967295

def depth_loop(n: Nat, +size: U32, +d: Nat) -> Nat:
  match n:
    case 0n:
      d
    case 1n+p:
      Bool.pick(Nat, (U32.from_nat(Nat.pow(2n, d)) >= size : U32), d, depth_loop(p, size, Nat.add(d, 1n)))

def depth_of(+size: U32) -> Nat:
  depth_loop(24n, size, 0n)

def first_word(words: List<&2, U32>) -> U32:
  match words:
    case Nil{}:
      0
    case Con{+word, _}:
      word

def later_words(words: List<&2, U32>) -> List<&2, U32>:
  match words:
    case Nil{}:
      Nil{}
    case Con{_, rest}:
      rest

def next_words(refill: Bool, +words: List<&2, U32>) -> List<&2, U32>:
  match refill:
    case True{}:
      later_words(words)
    case False{}:
      words

def next_bits(refill: Bool, +words: List<&2, U32>, +bits: U32) -> U32:
  match refill:
    case True{}:
      first_word(words)
    case False{}:
      (bits >> 1n : U32)

def pushed(closes: Bool, +x0: U32, +x1: U32, +id: U32, row: List<&2, Run>) -> List<&2, Run>:
  match closes:
    case True{}:
      Run{x0, x1, id} <> row
    case False{}:
      row

def ended(last: Bool, +row: List<&2, Run>, rows: List<&2, List<&2, Run>>) -> List<&2, List<&2, Run>>:
  match last:
    case True{}:
      List.reverse(&2, Run, row) <> rows
    case False{}:
      rows

# The runs of every row, the rows in reverse order (each row's runs by x), and the run count.
type Scanned is Data:
  Scanned{rows: List<&2, List<&2, Run>>, runs: U32}

def runs_loop(n: Nat, +words: List<&2, U32>, +bits: U32, +k: U32, +x: U32, +start: U32, +id: U32, +w: U32, +row: List<&2, Run>, rows: List<&2, List<&2, Run>>) -> Scanned:
  match n:
    case 0n:
      Scanned{rows, id}
    case 1n+p:
      +land = U32.is_eq((bits .&. 1 : U32), 1)
      +open = U32.is_ne(start, none())
      +last = U32.is_eq(x, (w - 1 : U32))
      +from = Bool.pick(U32, open, start, x)
      +closes = Bool.pick(Bool, land, last, open)
      +row_after = pushed(closes, from, Bool.pick(U32, land, x, (x - 1 : U32)), id, row)
      +refill = U32.is_eq(k, 1)
      runs_loop(p, next_words(refill, words), next_bits(refill, words, bits), Bool.pick(U32, refill, 32, (k - 1 : U32)), Bool.pick(U32, last, 0, (x + 1 : U32)),
        Bool.pick(U32, land && Bool.not(last), from, none()), (id + Bool.to_u32(closes) : U32), w, Bool.pick(List<&2, Run>, last, Nil{}, row_after), ended(last, row_after, rows))

# A union-find root search: a node, the stored word of its parent (0 for a root, else the parent + 1) and whether it
# is a root.
type Probe is Type:
  Probe{parent: Array<U32>, x: U32, up: U32, root: Bool}

def probe(got: Array<U32> & U32, +x: U32) -> Probe:
  (parent, +up) = got
  Probe{parent, x, up, U32.is_zero(up)}

def root_loop(n: Nat, pr: Probe) -> Array<U32> & U32:
  match n pr:
    case _ Probe{parent, +x, _, True{}}:
      (parent, x)
    case 0n Probe{parent, +x, _, False{}}:
      (parent, x)
    case 1n+p Probe{parent, _, +up, False{}}:
      root_loop(p, probe(parent[(up - 1 : U32)], (up - 1 : U32)))

def root(parent: Array<U32>, +x: U32, +fuel: Nat) -> Array<U32> & U32:
  root_loop(fuel, probe(parent[x], x))

def link(got: Array<U32> & U32, +ra: U32) -> Array<U32>:
  (parent, +rb) = got
  parent[U32.max(ra, rb)] <- Bool.pick(U32, U32.is_eq(ra, rb), 0, (U32.min(ra, rb) + 1 : U32))

def link_roots(got: Array<U32> & U32, +b: U32, +fuel: Nat) -> Array<U32>:
  (parent, +ra) = got
  link(root(parent, b, fuel), ra)

def joined(overlap: Bool, parent: Array<U32>, +a: U32, +b: U32, +fuel: Nat) -> Array<U32>:
  match overlap:
    case True{}:
      link_roots(root(parent, a, fuel), b, fuel)
    case False{}:
      parent

def merged(n: Nat, runs: List<&2, Run>, above: List<&2, Run>, parent: Array<U32>, +fuel: Nat) -> Array<U32>:
  match n runs above:
    case 1n+p Con{Run{+s, +e, +id}, +rs} Con{Run{+a0, +a1, +aid}, +rest}:
      +overlap = (a0 <= e : U32) && (s <= a1 : U32)
      merged(p, Bool.pick(List<&2, Run>, (e <= a1 : U32), rs, Run{s, e, id} <> rs), Bool.pick(List<&2, Run>, (a1 <= e : U32), rest, Run{a0, a1, aid} <> rest),
        joined(overlap, parent, id, aid, fuel), fuel)
    case _ _ _:
      parent

def united(rows: List<&2, List<&2, Run>>, +above: List<&2, Run>, parent: Array<U32>, +fuel: Nat) -> Array<U32>:
  match rows:
    case Nil{}:
      parent
    case Con{+row, rest}:
      +steps = Nat.add(List.length(&2, Run, row), List.length(&2, Run, above))
      united(rest, row, merged(Nat.add(steps, 1n), row, above, parent, fuel), fuel)

# Numbering the landmasses: the union-find array (a run already numbered holds its landmass), the landmasses' cells (8
# words each: area, tx0, ty0, tx1, ty1), their count, the current row's runs (newest first) and the rows done (newest
# first).
type Labels is Type:
  Labels{parent: Array<U32>, cells: Array<U32>, count: U32, row: List<&2, Run>, rows: List<&2, List<&2, Run>>}

def fresh(cells: Array<U32>, +m: U32, +s: U32, +e: U32, +y: U32) -> Array<U32>:
  +base = (m * 8 : U32)
  cells[base] <- (e - s + 1 : U32)
  cells[(base + 1 : U32)] <- s
  cells[(base + 2 : U32)] <- y
  cells[(base + 3 : U32)] <- e
  cells[(base + 4 : U32)] <- y

def grown_right(got: Array<U32> & U32, +base: U32, +e: U32, +y: U32) -> Array<U32>:
  (cells, +x1) = got
  cells[(base + 3 : U32)] <- U32.max(x1, e)
  cells[(base + 4 : U32)] <- y

def grown_left(got: Array<U32> & U32, +base: U32, +s: U32, +e: U32, +y: U32) -> Array<U32>:
  (cells, +x0) = got
  cells[(base + 1 : U32)] <- U32.min(x0, s)
  grown_right(cells[(base + 3 : U32)], base, e, y)

def grown_area(got: Array<U32> & U32, +base: U32, +s: U32, +e: U32, +y: U32) -> Array<U32>:
  (cells, +area) = got
  cells[base] <- (area + e - s + 1 : U32)
  grown_left(cells[(base + 1 : U32)], base, s, e, y)

def grown(cells: Array<U32>, +m: U32, +s: U32, +e: U32, +y: U32) -> Array<U32>:
  grown_area(cells[(m * 8 : U32)], (m * 8 : U32), s, e, y)

def joined_mass(got: Array<U32> & U32, cells: Array<U32>, +count: U32, +row: List<&2, Run>, +rows: List<&2, List<&2, Run>>, +s: U32, +e: U32, +id: U32, +y: U32) -> Labels:
  (parent, +m) = got
  parent[id] <- m
  Labels{parent, grown(cells, m, s, e, y), count, Run{s, e, m} <> row, rows}

def labelled_at(is_root: Bool, parent: Array<U32>, +up: U32, cells: Array<U32>, +count: U32, +row: List<&2, Run>, +rows: List<&2, List<&2, Run>>, +s: U32, +e: U32, +id: U32, +y: U32) -> Labels:
  match is_root:
    case True{}:
      parent[id] <- count
      Labels{parent, fresh(cells, count, s, e, y), (count + 1 : U32), Run{s, e, count} <> row, rows}
    case False{}:
      joined_mass(parent[(up - 1 : U32)], cells, count, row, rows, s, e, id, y)

def labelled_run(got: Array<U32> & U32, cells: Array<U32>, +count: U32, +row: List<&2, Run>, +rows: List<&2, List<&2, Run>>, +s: U32, +e: U32, +id: U32, +y: U32) -> Labels:
  (parent, +up) = got
  labelled_at(U32.is_zero(up), parent, up, cells, count, row, rows, s, e, id, y)

def labelled(st: Labels, +s: U32, +e: U32, +id: U32, +y: U32) -> Labels:
  match st:
    case Labels{parent, cells, +count, +row, +rows}:
      labelled_run(parent[id], cells, count, row, rows, s, e, id, y)

def row_done(st: Labels) -> Labels:
  match st:
    case Labels{parent, cells, +count, +row, +rows}:
      Labels{parent, cells, count, Nil{}, List.reverse(&2, Run, row) <> rows}

def labelled_row(runs: List<&2, Run>, +y: U32, st: Labels) -> Labels:
  match runs:
    case Nil{}:
      row_done(st)
    case Con{Run{+s, +e, +id}, rest}:
      labelled_row(rest, y, labelled(st, s, e, id, y))

def labelled_rows(rows: List<&2, List<&2, Run>>, +y: U32, st: Labels) -> Labels:
  match rows:
    case Nil{}:
      st
    case Con{+row, rest}:
      labelled_rows(rest, (y + 1 : U32), labelled_row(row, y, st))

def cells_loop(n: Nat, got: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, acc)
    case 1n+p:
      (cells, +v) = got
      cells_loop(p, cells[(i + 1 : U32)], (i + 1 : U32), v <> acc)

def masses_of(words: List<&2, U32>) -> List<&2, Mass>:
  match words:
    case Con{+area, Con{+tx0, Con{+ty0, Con{+tx1, Con{+ty1, Con{_, Con{_, Con{_, rest}}}}}}}}:
      Mass{area, tx0, ty0, tx1, ty1} <> masses_of(rest)
    case _:
      Nil{}

def masses_from(+w: U32, st: Labels) -> Masses:
  match st:
    case Labels{_, cells, +count, _, +rows}:
      Masses{w, TileTable.from_list(~List<&2, Run>, List.reverse(&2, List<&2, Run>, rows), Nil{}),
        TileTable.from_list(~Mass, masses_of(cells_loop(U32.to_nat((count * 8 : U32)), cells[0], 0, Nil{})), Mass{0, 0, 0, 0, 0})}

def labelled_scan(+w: U32, s: Scanned) -> Masses:
  match s:
    case Scanned{+rows_back, +runs}:
      +rows = List.reverse(&2, List<&2, Run>, rows_back)
      +depth = depth_of((runs + 1 : U32))
      +fuel = U32.to_nat((runs + 1 : U32))
      masses_from(w, labelled_rows(rows, 0, Labels{united(rows, Nil{}, [0 : U32^depth], fuel), [0 : U32^(Nat.add(depth, 3n))], 0, Nil{}, Nil{}}))

# The landmasses of a w x h world from its land bits (bit b of word j is tile 32j + b, filters/world.bend land_bits).
def of_land(+land: List<&2, U32>, +w: U32, +h: U32) -> Masses:
  labelled_scan(w, runs_loop(U32.to_nat((w * h : U32)), later_words(land), first_word(land), 32, 0, none(), 0, w, Nil{}, Nil{}))

def run_mass(runs: List<&2, Run>, +x: U32) -> U32:
  match runs:
    case Nil{}:
      none()
    case Con{Run{+x0, +x1, +m}, rest}:
      Bool.pick(U32, (x0 <= x : U32) && (x <= x1 : U32), m, run_mass(rest, x))

# The landmass of tile `tile` (ty*W + tx), none() off land.
def mass_at(+masses: Masses, +tile: U32) -> U32:
  match masses:
    case Masses{+w, +rows, _}:
      run_mass(TileTable.at(~List<&2, Run>, rows, (tile / w : U32)), (tile % w : U32))

# Landmass m's tiles and bounds.
def mass(+masses: Masses, +m: U32) -> Mass:
  match masses:
    case Masses{_, _, +table}:
      TileTable.at(~Mass, table, m)
