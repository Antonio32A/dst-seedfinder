import Base
import ../trace/canon.bend as Canon
import ../worldsim/grid.bend as Grid
import ../worldsim/tiles/input.bend as TileInput

# The ocean trace stages' inputs, read back from the oracle's `ocean` records, and the
# `odig` record they print.

def cell_of(+tiles: String, +flags: String) -> U32:
  Grid.cell(TileInput.hex_loop(4n, tiles, 0), (TileInput.hex_loop(4n, flags, 0) .&. 61695 : U32))

def row_loop(n: Nat, g: Grid.Grid, +tiles: String, +flags: String, +i: U32) -> Grid.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      row_loop(p, Grid.put(g, i, cell_of(tiles, flags)), String.drop(tiles, 4n), String.drop(flags, 4n), (i + 1 : U32))

def rows_loop(recs: List<&2, List<&2, String>>, g: Grid.Grid, +w: U32, +tile_key: String, +flag_key: String) -> Grid.Grid:
  match recs:
    case Nil{}:
      g
    case Con{+fields, rest}:
      +y = TileInput.num("y", fields)
      filled = row_loop(U32.to_nat(w), g, TileInput.text(tile_key, fields), TileInput.text(flag_key, fields), (y * w : U32))
      rows_loop(rest, filled, w, tile_key, flag_key)

def keep_at(recs: List<&2, List<&2, String>>, +at: String) -> List<&2, List<&2, String>>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      TileInput.keep_if(String.eq(TileInput.text("at", fields), at), fields, keep_at(rest, at))

# The `orow` records of attempt a at `at` (quoted, e.g. "\"land\"").
def rows(+a: String, +at: String, +lines: List<&2, String>) -> List<&2, List<&2, String>>:
  keep_at(TileInput.of_attempt("orow", a, lines), at)

# The w x h grid of the tiles and flags in those rows.
def grid(+a: String, +at: String, +w: U32, +h: U32, +lines: List<&2, String>) -> Grid.Grid:
  rows_loop(rows(a, at, lines), Grid.new(w, h, 0), w, "tiles", "flags")

# The node-id map in those rows, one id per cell.
def ids(+a: String, +at: String, +w: U32, +h: U32, +lines: List<&2, String>) -> Grid.Grid:
  rows_loop(rows(a, at, lines), Grid.new(w, h, 0), w, "ids", "")

def attempts_of(recs: List<&2, List<&2, String>>) -> List<&2, String>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      TileInput.text("a", fields) <> attempts_of(rest)

# The attempts that reached the ocean stage, in order.
def attempts(+lines: List<&2, String>) -> List<&2, String>:
  attempts_of(Canon.records("oin", lines))

# The `oin` record of attempt a.
def input(+a: String, +lines: List<&2, String>) -> List<&2, String>:
  TileInput.first_fields(TileInput.of_attempt("oin", a, lines))

def at_scan(recs: List<&2, List<&2, String>>, +at: String) -> List<&2, String>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      Bool.pick(List<&2, String>, String.eq(TileInput.text("at", fields), at), fields, at_scan(rest, at))

# The `odig` record of attempt a at `at` (Nil when absent).
def digest_record(+a: String, +at: String, +lines: List<&2, String>) -> List<&2, String>:
  at_scan(TileInput.of_attempt("odig", a, lines), at)

def hash_text(+h: Grid.Hash) -> String:
  match h:
    case Grid.Hash{+hi, +lo}:
      Canon.hex64(hi, lo)

def digest_done(got: Grid.Grid & Grid.Hash, +a: String, +at: String, +ctr: U32, +tiles: Grid.Hash) -> Grid.Grid & String:
  (g, +flags) = got
  match g:
    case Grid.Grid{cells, +w, +h}:
      (Grid.Grid{cells, w, h}, Canon.record("odig", [Canon.field("a", a), Canon.field("at", Canon.quoted(at)), Canon.number("ctr", ctr),
        Canon.number("w", w), Canon.number("h", h), Canon.field("tiles", hash_text(tiles)), Canon.field("mflags", hash_text(flags))]))

def flags_hash_loop(n: Nat, got: Array<U32> & U32, +i: U32, h: Grid.Hash) -> Array<U32> & Grid.Hash:
  match n:
    case 0n:
      (cells, _) = got
      (cells, h)
    case 1n+p:
      (cells, +v) = got
      flags_hash_loop(p, cells[(i + 1 : U32)], (i + 1 : U32), Grid.fnv_u16(h, (v >> 16n : U32)))

def flags_hashed(r: Array<U32> & Grid.Hash, +w: U32, +h: U32) -> Grid.Grid & Grid.Hash:
  (cells, hash) = r
  (Grid.Grid{cells, w, h}, hash)

# FNV-1a 64 of width, height and every cell's flags without the variant nibble (the oracle's `mflags`).
def flags_hash(g: Grid.Grid) -> Grid.Grid & Grid.Hash:
  match g:
    case Grid.Grid{cells, +w, +h}:
      flags_hashed(flags_hash_loop(U32.to_nat((w * h : U32)), cells[0], 0, Grid.header(w, h)), w, h)

def digest_tiles(got: Grid.Grid & Grid.Hash, +a: String, +at: String, +ctr: U32) -> Grid.Grid & String:
  (g, +tiles) = got
  digest_done(flags_hash(g), a, at, ctr, tiles)

# The `odig` record for the grid now (`ctr` = the draw counter): width, height, tile and masked flag digests.
def digest(g: Grid.Grid, +a: String, +at: String, +ctr: U32) -> Grid.Grid & String:
  digest_tiles(Grid.tiles_digest(g), a, at, ctr)
