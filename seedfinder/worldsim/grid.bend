import Base
import ../rng/pcg.bend as Pcg

# The WorldSim tile map and flag map in one flat array: cell y * width + x holds the tile in the low 16 bits and the
# flags in the high 16 bits. The flags' variant nibble (0x0f00, drawn by ConvertToTileMap) is not stored: only the
# encoded map reads it, and `flags_digest` replays it from the PCG stream.
type Grid is Type:
  Grid{cells: Array<U32>, width: U32, height: U32}

def reserved_flag() -> U32:
  16384

def disconnected_flag() -> U32:
  8192

def line_flag() -> U32:
  32768

def tile_of(+cell: U32) -> U32:
  (cell .&. 65535 : U32)

def flags_of(+cell: U32) -> U32:
  (cell >> 16n : U32)

def cell(+tile: U32, +flags: U32) -> U32:
  ((flags << 16n) .|. (tile .&. 65535 : U32) : U32)

def index(+x: U32, +y: U32, +width: U32) -> U32:
  (y * width + x : U32)

def alloc_big(big: Bool, +fill: U32) -> Array<U32>:
  match big:
    case True{}:
      [fill : U32^22n]
    case False{}:
      [fill : U32^20n]

def alloc_19(fits: Bool, +d: Nat, +fill: U32) -> Array<U32>:
  match fits:
    case True{}:
      [fill : U32^19n]
    case False{}:
      alloc_big(Nat.is_gt(d, 20n), fill)

def alloc_18(fits: Bool, +d: Nat, +fill: U32) -> Array<U32>:
  match fits:
    case True{}:
      [fill : U32^18n]
    case False{}:
      alloc_19(Nat.is_le(d, 19n), d, fill)

def alloc_14(fits: Bool, +d: Nat, +fill: U32) -> Array<U32>:
  match fits:
    case True{}:
      [fill : U32^14n]
    case False{}:
      alloc_18(Nat.is_le(d, 18n), d, fill)

def alloc_12(fits: Bool, +d: Nat, +fill: U32) -> Array<U32>:
  match fits:
    case True{}:
      [fill : U32^12n]
    case False{}:
      alloc_14(Nat.is_le(d, 14n), d, fill)

# An array of at least 2^d slots, all `fill` (fixed sizes: Bend builds a literal depth as one flat block, a computed
# depth node by node).
def alloc(+d: Nat, +fill: U32) -> Array<U32>:
  alloc_12(Nat.is_le(d, 12n), d, fill)

def depth_for(n: Nat, +count: U32, +d: Nat, +size: U32) -> Nat:
  match n:
    case 0n:
      d
    case 1n+p:
      depth_for(p, count, Bool.pick(Nat, (size >= count : U32), d, 1n+d), (size * 2 : U32))

# A width x height map with every cell set to `fill`.
def new(+width: U32, +height: U32, +fill: U32) -> Grid:
  Grid{alloc(depth_for(24n, (width * height : U32), 0n, 1), fill), width, height}

def got_cell(got: Array<U32> & U32, +width: U32, +height: U32) -> Grid & U32:
  (cells, +v) = got
  (Grid{cells, width, height}, v)

# The cell at flat index i.
def get(g: Grid, +i: U32) -> Grid & U32:
  match g:
    case Grid{cells, +width, +height}:
      got_cell(cells[i], width, height)

def put(g: Grid, +i: U32, +v: U32) -> Grid:
  match g:
    case Grid{cells, +width, +height}:
      cells[i] <- v
      Grid{cells, width, height}

def size(g: Grid) -> Grid & U32:
  match g:
    case Grid{cells, +width, +height}:
      (Grid{cells, width, height}, (width * height : U32))

type Hash is Data:
  Hash{hi: U32, lo: U32}

def fnv_offset() -> Hash:
  Hash{3421674724, 2216829733}

def fnv_mul_hi(+lo: U32) -> U32:
  (((lo >> 16n) * 435 + (((lo .&. 65535) * 435) >> 16n)) >> 16n : U32)

# FNV-1a 64 step on one byte: h = (h ^ b) * 1099511628211, the prime being 2^40 + 435.
def fnv_byte(h: Hash, +b: U32) -> Hash:
  match h:
    case Hash{+hi, +lo}:
      +x = (lo .^. (b .&. 255) : U32)
      Hash{(hi * 435 + fnv_mul_hi(x) + (x << 8n) : U32), (x * 435 : U32)}

def fnv_u16(h: Hash, +v: U32) -> Hash:
  fnv_byte(fnv_byte(h, v), (v >> 8n : U32))

def fnv_u32(h: Hash, +v: U32) -> Hash:
  fnv_u16(fnv_u16(h, v), (v >> 16n : U32))

def tiles_loop(n: Nat, got: Array<U32> & U32, +i: U32, h: Hash) -> Array<U32> & Hash:
  match n:
    case 0n:
      (cells, _) = got
      (cells, h)
    case 1n+p:
      (cells, +v) = got
      tiles_loop(p, cells[(i + 1 : U32)], (i + 1 : U32), fnv_u16(h, (v .&. 65535 : U32)))

def flags_loop(n: Nat, got: Array<U32> & U32, +i: U32, h: Hash, drawn: U32 & Pcg.Rng) -> Array<U32> & Hash:
  match n:
    case 0n:
      (cells, _) = got
      (cells, h)
    case 1n+p:
      (cells, +v) = got
      (+out, rng) = drawn
      flags_loop(p, cells[(i + 1 : U32)], (i + 1 : U32), fnv_u16(h, ((v >> 16n) .|. ((out .&. 15) << 8n) : U32)), Pcg.draw(rng))

def header(+width: U32, +height: U32) -> Hash:
  fnv_u32(fnv_u32(fnv_offset(), width), height)

def tiles_done(r: Array<U32> & Hash, +width: U32, +height: U32) -> Grid & Hash:
  (cells, h) = r
  (Grid{cells, width, height}, h)

# FNV-1a 64 of width, height and every cell's tile (the oracle's tile map digest).
def tiles_digest(g: Grid) -> Grid & Hash:
  match g:
    case Grid{cells, +width, +height}:
      tiles_done(tiles_loop(U32.to_nat((width * height : U32)), cells[0], 0, header(width, height)), width, height)

# The flag map digest, with each cell's variant nibble drawn as pcg32_boundedrand(16) from `rng` in cell order
# (the state before ConvertToTileMap).
def flags_digest(g: Grid, rng: Pcg.Rng) -> Grid & Hash:
  match g:
    case Grid{cells, +width, +height}:
      tiles_done(flags_loop(U32.to_nat((width * height : U32)), cells[0], 0, header(width, height), Pcg.draw(rng)), width, height)
