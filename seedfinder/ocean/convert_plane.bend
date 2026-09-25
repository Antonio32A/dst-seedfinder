import Base
import ../worldsim/grid.bend as GR

# Bit planes over the tile map for Ocean_ConvertImpassibleToWater's neighbourhood tests, stored in flat arrays: the
# plane at base b holds row y's words at b + y * ww .. b + y * ww + ww - 1, bit x of the row in word x >> 5 at bit
# x & 31, bits past the map width clear. Rows and columns past the map's edges read as clear.

# Map width and height, words per row and the mask of a row's last word.
type Geo is Data:
  Geo{w: U32, h: U32, ww: U32, last: U32}

def words_of(+w: U32) -> U32:
  ((w + 31) >> 5n : U32)

def geo(+w: U32, +h: U32) -> Geo:
  +ww = words_of(w)
  Geo{w, h, ww, ((1 << U32.to_nat((w - (ww - 1) * 32 : U32))) - 1 : U32)}

# The words of one plane.
def size(+g: Geo) -> U32:
  match g:
    case Geo{_, +h, +ww, _}:
      (h * ww : U32)

def blank(+n: U32) -> Array<U32>:
  GR.alloc(GR.depth_for(24n, n, 0n, 1), 0)

# An array for k planes, all clear.
def arena(+g: Geo, +k: U32) -> Array<U32>:
  blank((size(g) * k : U32))

def base(+g: Geo, +k: U32) -> U32:
  (size(g) * k : U32)

# op 0: dst | src, 1: dst & src, 2: dst & ~src, 3: src.
def combined(+op: U32, +d: U32, +s: U32) -> U32:
  Bool.pick(U32, U32.is_eq(op, 0), (d .|. s : U32), Bool.pick(U32, U32.is_eq(op, 1), (d .&. s : U32),
    Bool.pick(U32, U32.is_eq(op, 2), (d .&. U32.not(s) : U32), s)))

def combine_dst(got: Array<U32> & U32, +op: U32, +s: U32, +d: U32) -> Array<U32>:
  (a, +dv) = got
  a[d] <- combined(op, dv, s)

def combine_src(got: Array<U32> & U32, +op: U32, +d: U32) -> Array<U32>:
  (a, +sv) = got
  combine_dst(a[d], op, sv, d)

def combine_go(n: Nat, a: Array<U32>, +op: U32, +d: U32, +s: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      combine_go(p, combine_src(a[s], op, d), op, (d + 1 : U32), (s + 1 : U32))

def combine(a: Array<U32>, +g: Geo, +op: U32, +dst: U32, +src: U32) -> Array<U32>:
  combine_go(U32.to_nat(size(g)), a, op, dst, src)

# dst |= src.
def union(a: Array<U32>, +g: Geo, +dst: U32, +src: U32) -> Array<U32>:
  combine(a, g, 0, dst, src)

# dst &= src.
def inter(a: Array<U32>, +g: Geo, +dst: U32, +src: U32) -> Array<U32>:
  combine(a, g, 1, dst, src)

# dst &= ~src.
def minus(a: Array<U32>, +g: Geo, +dst: U32, +src: U32) -> Array<U32>:
  combine(a, g, 2, dst, src)

def copy(a: Array<U32>, +g: Geo, +dst: U32, +src: U32) -> Array<U32>:
  combine(a, g, 3, dst, src)

def clear_go(n: Nat, a: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      a[i] <- 0
      clear_go(p, a, (i + 1 : U32))

def clear(a: Array<U32>, +g: Geo, +dst: U32) -> Array<U32>:
  clear_go(U32.to_nat(size(g)), a, dst)

# A plane shift: source bit (x - dx, y - dy) with dx = s (east) or -s (west, `west`), 0 <= s < 32, and dy any.
type Shift is Data:
  Shift{s: U32, west: Bool, dy: U32}

def shifted(+sh: Shift, +v0: U32, +v1: U32) -> U32:
  match sh:
    case Shift{+s, +west, _}:
      +back = U32.to_nat((32 - s : U32))
      Bool.pick(U32, west, ((v0 >> U32.to_nat(s)) .|. (v1 << back) : U32), ((v0 << U32.to_nat(s)) .|. (v1 >> back) : U32))

type Spot is Data:
  Spot{i: U32, y: U32, j: U32}

def spot_next(+p: Spot, +ww: U32) -> Spot:
  match p:
    case Spot{+i, +y, +j}:
      +wrap = U32.is_eq((j + 1 : U32), ww)
      Spot{(i + 1 : U32), Bool.pick(U32, wrap, (y + 1 : U32), y), Bool.pick(U32, wrap, 0, (j + 1 : U32))}

def or_word(got: Array<U32> & U32, +v: U32, +d: U32) -> Array<U32>:
  (a, +dv) = got
  a[d] <- (dv .|. v : U32)

def shift_v1(got: Array<U32> & U32, +g: Geo, +sh: Shift, +dst: U32, +p: Spot, +v0: U32, +live: Bool, +near: Bool) -> Array<U32>:
  (a, +v1) = got
  match g:
    case Geo{_, _, +ww, +last}:
      match p:
        case Spot{+i, _, +j}:
          +raw = shifted(sh, Bool.pick(U32, live, v0, 0), Bool.pick(U32, live && near, v1, 0))
          or_word(a[(dst + i : U32)], Bool.pick(U32, U32.is_eq((j + 1 : U32), ww), (raw .&. last : U32), raw), (dst + i : U32))

def shift_v0(got: Array<U32> & U32, +g: Geo, +sh: Shift, +dst: U32, +row: U32, +p: Spot, +live: Bool) -> Array<U32>:
  (a, +v0) = got
  match g:
    case Geo{_, _, +ww, _}:
      match sh:
        case Shift{_, +west, _}:
          match p:
            case Spot{_, _, +j}:
              +near = Bool.pick(Bool, west, (j + 1 < ww : U32), (j > 0 : U32))
              +k = Bool.pick(U32, west, (j + 1 : U32), (j - 1 : U32))
              shift_v1(a[(row + k : U32)], g, sh, dst, p, v0, live, near)

def shift_word(a: Array<U32>, +g: Geo, +sh: Shift, +dst: U32, +src: U32, +p: Spot) -> Array<U32>:
  match g:
    case Geo{_, +h, +ww, _}:
      match sh:
        case Shift{_, _, +dy}:
          match p:
            case Spot{_, +y, +j}:
              +sy = (y - dy : U32)
              +row = (src + sy * ww : U32)
              shift_v0(a[(row + j : U32)], g, sh, dst, row, p, (sy < h : U32))

def shift_go(n: Nat, a: Array<U32>, +g: Geo, +sh: Shift, +dst: U32, +src: U32, +p: Spot) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+k:
      match g:
        case Geo{_, _, +ww, _}:
          shift_go(k, shift_word(a, g, sh, dst, src, p), g, sh, dst, src, spot_next(p, ww))

# dst |= src shifted (dst and src distinct).
def or_shift(a: Array<U32>, +g: Geo, +dst: U32, +src: U32, +sh: Shift) -> Array<U32>:
  shift_go(U32.to_nat(size(g)), a, g, sh, dst, src, Spot{0, 0, 0})

def hwin_go(n: Nat, a: Array<U32>, +g: Geo, +dst: U32, +src: U32, +s: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      east = or_shift(a, g, dst, src, Shift{s, False{}, 0})
      hwin_go(p, or_shift(east, g, dst, src, Shift{s, True{}, 0}), g, dst, src, (s + 1 : U32))

# dst = cells with a src cell within r columns (r < 32).
def hwindow(a: Array<U32>, +g: Geo, +dst: U32, +src: U32, +r: U32) -> Array<U32>:
  hwin_go(U32.to_nat(r), copy(a, g, dst, src), g, dst, src, 1)

def vwin_go(n: Nat, a: Array<U32>, +g: Geo, +dst: U32, +src: U32, +d: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      south = or_shift(a, g, dst, src, Shift{0, False{}, d})
      vwin_go(p, or_shift(south, g, dst, src, Shift{0, False{}, (0 - d : U32)}), g, dst, src, (d + 1 : U32))

# dst = cells with a src cell within r rows.
def vwindow(a: Array<U32>, +g: Geo, +dst: U32, +src: U32, +r: U32) -> Array<U32>:
  vwin_go(U32.to_nat(r), copy(a, g, dst, src), g, dst, src, 1)

# dst = cells with a src cell within Chebyshev distance r (tmp is scratch; all three distinct).
def square(a: Array<U32>, +g: Geo, +dst: U32, +src: U32, +tmp: U32, +r: U32) -> Array<U32>:
  vwindow(hwindow(a, g, tmp, src, r), g, dst, tmp, r)

def any_go(n: Nat, got: Array<U32> & U32, +i: U32, +acc: U32) -> Array<U32> & Bool:
  match n:
    case 0n:
      (a, +v) = got
      (a, U32.is_ne((acc .|. v : U32), 0))
    case 1n+p:
      (a, +v) = got
      any_go(p, a[(i + 1 : U32)], (i + 1 : U32), (acc .|. v : U32))

# Whether the plane at src has a set bit.
def any(a: Array<U32>, +g: Geo, +src: U32) -> Array<U32> & Bool:
  any_go(U32.to_nat((size(g) - 1 : U32)), a[src], src, 0)

type Words is Data:
  Words{a: U32, b: U32, c: U32, d: U32}

def add_bits(+w: Words, +k: U32, +bit: Nat) -> Words:
  match w:
    case Words{+a, +b, +c, +d}:
      Words{(a .|. ((k .&. 1) << bit) : U32), (b .|. (((k >> 1n) .&. 1) << bit) : U32),
        (c .|. (((k >> 2n) .&. 1) << bit) : U32), (d .|. (((k >> 3n) .&. 1) << bit) : U32)}

def bits_loop(~cls: U32 -> U32, n: Nat, got: Array<U32> & U32, +i: U32, +bit: Nat, +w: Words) -> Array<U32> & Words:
  match n:
    case 0n:
      (cells, _) = got
      (cells, w)
    case 1n+p:
      (cells, +v) = got
      bits_loop(~cls, p, cells[(i + 1 : U32)], (i + 1 : U32), 1n+bit, add_bits(w, cls(v), bit))

def put_words(got: Array<U32> & Words, a: Array<U32>, +at: U32, +stride: U32) -> Array<U32> & Array<U32>:
  (cells, +w) = got
  match w:
    case Words{+wa, +wb, +wc, +wd}:
      a[at] <- wa
      a[(at + stride : U32)] <- wb
      a[(at + stride * 2 : U32)] <- wc
      a[(at + stride * 3 : U32)] <- wd
      (cells, a)

def min32(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a < b : U32), a, b)

def extract_go(~cls: U32 -> U32, n: Nat, got: Array<U32> & Array<U32>, +g: Geo, +at: U32, +i: U32, +x: U32) -> Array<U32> & Array<U32>:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, a) = got
      match g:
        case Geo{+w, _, _, _}:
          +k = min32((w - x : U32), 32)
          +wrap = U32.is_eq((x + k : U32), w)
          next = bits_loop(~cls, U32.to_nat(k), cells[i], i, 0n, Words{0, 0, 0, 0})
          extract_go(~cls, p, put_words(next, a, at, size(g)), g, (at + 1 : U32), (i + k : U32), Bool.pick(U32, wrap, 0, (x + k : U32)))

# The four planes from `at` on (one plane apart) of the cells whose class mask cls(cell) has bit 0 .. 3 set.
def extract(~cls: U32 -> U32, cells: Array<U32>, a: Array<U32>, +g: Geo, +at: U32) -> Array<U32> & Array<U32>:
  extract_go(~cls, U32.to_nat(size(g)), (cells, a), g, at, 0, 0)

def write_with(~f: U32 -> U32, got: Array<U32> & U32, +i: U32) -> Array<U32>:
  (cells, +v) = got
  cells[i] <- f(v)

def paint_bit(~f: U32 -> U32, hit: Bool, cells: Array<U32>, +i: U32) -> Array<U32>:
  match hit:
    case True{}:
      write_with(~f, cells[i], i)
    case False{}:
      cells

def paint_bits(~f: U32 -> U32, n: Nat, cells: Array<U32>, +word: U32, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      cells
    case 1n+p:
      paint_bits(~f, p, paint_bit(~f, U32.is_ne((word .&. 1 : U32), 0), cells, i), (word >> 1n : U32), (i + 1 : U32))

def paint_word(~f: U32 -> U32, hit: Bool, cells: Array<U32>, +word: U32, +i: U32) -> Array<U32>:
  match hit:
    case True{}:
      paint_bits(~f, 32n, cells, word, i)
    case False{}:
      cells

def paint_got(~f: U32 -> U32, got: Array<U32> & U32, cells: Array<U32>, +i: U32) -> Array<U32> & Array<U32>:
  (a, +word) = got
  (a, paint_word(~f, U32.is_ne(word, 0), cells, word, i))

def paint_go(~f: U32 -> U32, n: Nat, got: Array<U32> & Array<U32>, +g: Geo, +at: U32, +i: U32, +x: U32) -> Array<U32> & Array<U32>:
  match n:
    case 0n:
      got
    case 1n+p:
      (a, cells) = got
      match g:
        case Geo{+w, _, _, _}:
          +wrap = (x + 32 >= w : U32)
          next = paint_got(~f, a[at], cells, i)
          paint_go(~f, p, next, g, (at + 1 : U32), Bool.pick(U32, wrap, (i + w - x : U32), (i + 32 : U32)), Bool.pick(U32, wrap, 0, (x + 32 : U32)))

# Every cell of the plane at src becomes f(cell).
def paint(~f: U32 -> U32, a: Array<U32>, cells: Array<U32>, +g: Geo, +src: U32) -> Array<U32> & Array<U32>:
  paint_go(~f, U32.to_nat(size(g)), (a, cells), g, src, 0, 0)

# paint on an (array, cells) pair.
def paint2(~f: U32 -> U32, got: Array<U32> & Array<U32>, +g: Geo, +src: U32) -> Array<U32> & Array<U32>:
  paint_go(~f, U32.to_nat(size(g)), got, g, src, 0, 0)

def nz_bits(n: Nat, got: Array<U32> & U32, +i: U32, +bit: Nat, +word: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      (a, _) = got
      (a, word)
    case 1n+p:
      (a, +v) = got
      nz_bits(p, a[(i + 1 : U32)], (i + 1 : U32), 1n+bit, (word .|. (Bool.to_u32(U32.is_ne(v, 0)) << bit) : U32))

def nz_put(got: Array<U32> & U32, +at: U32) -> Array<U32>:
  (a, +word) = got
  a[at] <- word

def nz_go(n: Nat, a: Array<U32>, +g: Geo, +at: U32, +i: U32, +x: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      match g:
        case Geo{+w, _, _, _}:
          +k = min32((w - x : U32), 32)
          +wrap = U32.is_eq((x + k : U32), w)
          done = nz_put(nz_bits(U32.to_nat(k), a[i], i, 0n, 0), at)
          nz_go(p, done, g, (at + 1 : U32), (i + k : U32), Bool.pick(U32, wrap, 0, (x + k : U32)))

# The plane at dst of the nonzero words among the w * h values (row-major) from src on.
def nonzero(a: Array<U32>, +g: Geo, +dst: U32, +src: U32) -> Array<U32>:
  nz_go(U32.to_nat(size(g)), a, g, dst, src, 0)

def spread_word(got: Array<U32> & U32, +dst: U32, +i: U32, +j: U32, +g: Geo, +mid: U32) -> Array<U32>:
  (a, +right) = got
  match g:
    case Geo{_, _, +ww, +last}:
      +inner = (j + 1 < ww : U32)
      +hit = U32.is_ne((mid .|. Bool.pick(U32, inner, right, 0) : U32), 0)
      a[(dst + i : U32)] <- Bool.pick(U32, hit, Bool.pick(U32, inner, 4294967295, last), 0)

def spread_mid(got: Array<U32> & U32, +src: U32, +dst: U32, +i: U32, +j: U32, +g: Geo, +left: U32) -> Array<U32>:
  (a, +mid) = got
  spread_word(a[(src + i + 1 : U32)], dst, i, j, g, (mid .|. left : U32))

def spread_left(got: Array<U32> & U32, +src: U32, +dst: U32, +i: U32, +j: U32, +g: Geo) -> Array<U32>:
  (a, +left) = got
  spread_mid(a[(src + i : U32)], src, dst, i, j, g, Bool.pick(U32, (j > 0 : U32), left, 0))

def spread_go(n: Nat, a: Array<U32>, +src: U32, +dst: U32, +i: U32, +j: U32, +g: Geo) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      match g:
        case Geo{_, _, +ww, _}:
          +wrap = U32.is_eq((j + 1 : U32), ww)
          spread_go(p, spread_left(a[(src + i - 1 : U32)], src, dst, i, j, g), src, dst, (i + 1 : U32), Bool.pick(U32, wrap, 0, (j + 1 : U32)), g)

# dst word (y, j) is all set (up to the width) when any of src words (y, j - 1), (y, j), (y, j + 1) is nonzero, so
# it covers every cell within 32 columns of a src cell (dst and src distinct).
def word_spread(a: Array<U32>, +g: Geo, +dst: U32, +src: U32) -> Array<U32>:
  spread_go(U32.to_nat(size(g)), a, src, dst, 0, 0, g)

def vstep(a: Array<U32>, +g: Geo, +dst: U32, +src: U32, +k: U32) -> Array<U32>:
  south = or_shift(copy(a, g, dst, src), g, dst, src, Shift{0, False{}, k})
  or_shift(south, g, dst, src, Shift{0, False{}, (0 - k : U32)})

def vstep_if(more: Bool, a: Array<U32>, +g: Geo, +dst: U32, +src: U32, +k: U32) -> Array<U32>:
  match more:
    case True{}:
      vstep(a, g, dst, src, k)
    case False{}:
      a

def copy_if(go: Bool, a: Array<U32>, +g: Geo, +dst: U32, +src: U32) -> Array<U32>:
  match go:
    case True{}:
      copy(a, g, dst, src)
    case False{}:
      a

def vspread_go(n: Nat, a: Array<U32>, +g: Geo, +cur: U32, +other: U32, +reach: U32, +r: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      (a, cur)
    case 1n+p:
      +k = min32((reach + 1 : U32), (r - reach : U32))
      +more = (reach < r : U32)
      +next = Bool.pick(U32, more, other, cur)
      stepped = vstep_if(more, a, g, other, cur, k)
      vspread_go(p, stepped, g, next, Bool.pick(U32, more, cur, other), (reach + k : U32), r)

def vspread_done(got: Array<U32> & U32, +g: Geo, +dst: U32) -> Array<U32>:
  (a, +at) = got
  copy_if(Bool.not(U32.is_eq(at, dst)), a, g, dst, at)

# dst = cells with a src cell within r rows, by doubling (radius 1, 3, 7, ..); tmp is scratch, src is kept.
def vspread(a: Array<U32>, +g: Geo, +dst: U32, +src: U32, +tmp: U32, +r: U32) -> Array<U32>:
  vspread_done(vspread_go(6n, vstep(a, g, dst, src, 1), g, dst, tmp, 1, r), g, dst)
