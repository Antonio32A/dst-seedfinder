import Base
import ../trace/canon.bend as CN
import ../worldsim/grid.bend as GR
import ../worldsim/tiles/input.bend as TN

# The ocean trace stages' inputs, read back from lane G's oracle `ocean` records (.scratch/port/status/M10.md), and
# the `odig` record they print.

def cell_of(+tiles: String, +flags: String) -> U32:
  GR.cell(TN.hex_loop(4n, tiles, 0), (TN.hex_loop(4n, flags, 0) .&. 61695 : U32))

def row_loop(n: Nat, g: GR.Grid, +tiles: String, +flags: String, +i: U32) -> GR.Grid:
  match n:
    case 0n:
      g
    case 1n+p:
      row_loop(p, GR.put(g, i, cell_of(tiles, flags)), String.drop(tiles, 4n), String.drop(flags, 4n), (i + 1 : U32))

def rows_loop(recs: List<&2, List<&2, String>>, g: GR.Grid, +w: U32, +tile_key: String, +flag_key: String) -> GR.Grid:
  match recs:
    case Nil{}:
      g
    case Con{+fields, rest}:
      +y = TN.num("y", fields)
      filled = row_loop(U32.to_nat(w), g, TN.text(tile_key, fields), TN.text(flag_key, fields), (y * w : U32))
      rows_loop(rest, filled, w, tile_key, flag_key)

def keep_at(recs: List<&2, List<&2, String>>, +at: String) -> List<&2, List<&2, String>>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      TN.keep_if(String.eq(TN.text("at", fields), at), fields, keep_at(rest, at))

# The `orow` records of attempt a at `at` (quoted, e.g. "\"land\"").
def rows(+a: String, +at: String, +lines: List<&2, String>) -> List<&2, List<&2, String>>:
  keep_at(TN.of_attempt("orow", a, lines), at)

# The w x h grid of the tiles and flags in those rows.
def grid(+a: String, +at: String, +w: U32, +h: U32, +lines: List<&2, String>) -> GR.Grid:
  rows_loop(rows(a, at, lines), GR.new(w, h, 0), w, "tiles", "flags")

# The node-id map in those rows, one id per cell.
def ids(+a: String, +at: String, +w: U32, +h: U32, +lines: List<&2, String>) -> GR.Grid:
  rows_loop(rows(a, at, lines), GR.new(w, h, 0), w, "ids", "")

def attempts_of(recs: List<&2, List<&2, String>>) -> List<&2, String>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      TN.text("a", fields) <> attempts_of(rest)

# The attempts that reached the ocean stage, in order.
def attempts(+lines: List<&2, String>) -> List<&2, String>:
  attempts_of(CN.records("oin", lines))

# The `oin` record of attempt a.
def input(+a: String, +lines: List<&2, String>) -> List<&2, String>:
  TN.first_fields(TN.of_attempt("oin", a, lines))

def at_scan(recs: List<&2, List<&2, String>>, +at: String) -> List<&2, String>:
  match recs:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      Bool.pick(List<&2, String>, String.eq(TN.text("at", fields), at), fields, at_scan(rest, at))

# The `odig` record of attempt a at `at` (Nil when absent).
def digest_record(+a: String, +at: String, +lines: List<&2, String>) -> List<&2, String>:
  at_scan(TN.of_attempt("odig", a, lines), at)

def hash_text(+h: GR.Hash) -> String:
  match h:
    case GR.Hash{+hi, +lo}:
      CN.hex64(hi, lo)

def digest_done(got: GR.Grid & GR.Hash, +a: String, +at: String, +ctr: U32, +tiles: GR.Hash) -> GR.Grid & String:
  (g, +flags) = got
  match g:
    case GR.Grid{cells, +w, +h}:
      (GR.Grid{cells, w, h}, CN.record("odig", [CN.field("a", a), CN.field("at", CN.quoted(at)), CN.number("ctr", ctr),
        CN.number("w", w), CN.number("h", h), CN.field("tiles", hash_text(tiles)), CN.field("mflags", hash_text(flags))]))

def flags_hash_loop(n: Nat, got: Array<U32> & U32, +i: U32, h: GR.Hash) -> Array<U32> & GR.Hash:
  match n:
    case 0n:
      (cells, _) = got
      (cells, h)
    case 1n+p:
      (cells, +v) = got
      flags_hash_loop(p, cells[(i + 1 : U32)], (i + 1 : U32), GR.fnv_u16(h, (v >> 16n : U32)))

def flags_hashed(r: Array<U32> & GR.Hash, +w: U32, +h: U32) -> GR.Grid & GR.Hash:
  (cells, hash) = r
  (GR.Grid{cells, w, h}, hash)

# FNV-1a 64 of width, height and every cell's flags without the variant nibble (the oracle's `mflags`).
def flags_hash(g: GR.Grid) -> GR.Grid & GR.Hash:
  match g:
    case GR.Grid{cells, +w, +h}:
      flags_hashed(flags_hash_loop(U32.to_nat((w * h : U32)), cells[0], 0, GR.header(w, h)), w, h)

def digest_tiles(got: GR.Grid & GR.Hash, +a: String, +at: String, +ctr: U32) -> GR.Grid & String:
  (g, +tiles) = got
  digest_done(flags_hash(g), a, at, ctr, tiles)

# The `odig` record for the grid now (`ctr` = the draw counter): width, height, tile and masked flag digests.
def digest(g: GR.Grid, +a: String, +at: String, +ctr: U32) -> GR.Grid & String:
  digest_tiles(GR.tiles_digest(g), a, at, ctr)
