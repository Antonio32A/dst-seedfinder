import Base
import ../grid.bend as Grid

# Maze cells: a u16 per cell in a flat Array<U32> of width w, the cell value in the low byte and the flags in the high
# byte (bit 6 = not part of the maze, bits 4 = visited, bits 0-3 = the four walls).

def lo_of(+c: U32) -> U32:
  (c .&. 255 : U32)

def hi_of(+c: U32) -> U32:
  ((c >> 8n) .&. 255 : U32)

def with_lo(+c: U32, +lo: U32) -> U32:
  ((c .&. 65280) .|. lo : U32)

def with_hi(+c: U32, +hi: U32) -> U32:
  ((c .&. 255) .|. (hi << 8n) : U32)

def index(+x: U32, +y: U32, +w: U32) -> U32:
  Grid.index(x, y, w)

# An array of at least w * h cells, all `fill`.
def new(+w: U32, +h: U32, +fill: U32) -> Array<U32>:
  Grid.alloc(Grid.depth_for(24n, (w * h : U32), 0n, 1), fill)

def set_lo_got(got: Array<U32> & U32, +i: U32, +lo: U32) -> Array<U32>:
  (cells, +c) = got
  cells[i] <- with_lo(c, lo)

# cells[i].lo = lo, keeping the flags.
def set_lo(cells: Array<U32>, +i: U32, +lo: U32) -> Array<U32>:
  set_lo_got(cells[i], i, lo)

def or_hi_got(got: Array<U32> & U32, +i: U32, +bits: U32) -> Array<U32>:
  (cells, +c) = got
  cells[i] <- with_hi(c, (hi_of(c) .|. bits : U32))

def and_hi_got(got: Array<U32> & U32, +i: U32, +bits: U32) -> Array<U32>:
  (cells, +c) = got
  cells[i] <- with_hi(c, (hi_of(c) .&. bits : U32))

# cells[i].hi |= bits, and cells[i].hi &= bits.
def or_hi(cells: Array<U32>, +i: U32, +bits: U32) -> Array<U32>:
  or_hi_got(cells[i], i, bits)

def and_hi(cells: Array<U32>, +i: U32, +bits: U32) -> Array<U32>:
  and_hi_got(cells[i], i, bits)

def blocked_bit(got: Array<U32> & U32, +blocked: U32) -> Array<U32> & U32:
  (cells, +c) = got
  (cells, (blocked .|. (hi_of(c) .&. 64) : U32))

# Whether any cell of the cs x cs block at cell (j, i) of the cs-sampled grid has hi bit 6 set (the block's rows are
# read with the true row stride w).
def block_bits(n: Nat, got: Array<U32> & U32, +j: U32, +i: U32, +cs: U32, +w: U32, +k: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, +bits) = got
      block_bits(p, blocked_bit(cells[index((j * cs + k % cs : U32), (i * cs + k / cs : U32), w)], bits), j, i, cs, w, (k + 1 : U32))

def blocked_of(got: Array<U32> & U32) -> Array<U32> & Bool:
  (cells, +bits) = got
  (cells, Bool.not(U32.is_zero(bits)))

def block_blocked(cells: Array<U32>, +j: U32, +i: U32, +cs: U32, +w: U32) -> Array<U32> & Bool:
  blocked_of(block_bits(U32.to_nat((cs * cs : U32)), (cells, 0), j, i, cs, w, 0))
