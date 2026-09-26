import Base
import ../rng/pcg.bend as Pcg
import ../trace/canon.bend as Canon
import ../worldsim/grid.bend as Grid
import ../worldsim/tiles/input.bend as TileInput
import ./rows.bend as OceanRows
import ./convert.bend as OceanConvert
import ./convert_fills.bend as ConvertFills
import ./convert_blend.bend as ConvertBlend

# Trace stage `oconvert`: Ocean_ConvertImpassibleToWater from the oracle's map after the prefill, per attempt the
# `odig` digests after the fills, the noise, the blend, the shoreline and the void outline, and the three blended maps'
# `oblend` records (without the informative sum). Stage `oconvert_seq` forces the row-major square fill.

type Ctx is Data:
  Ctx{seed: U32, a: String, ctr: U32}

def ctx_a(+c: Ctx) -> String:
  match c:
    case Ctx{_, +a, _}:
      a

def ctx_ctr(+c: Ctx) -> U32:
  match c:
    case Ctx{_, _, +ctr}:
      ctr

def last_line(got: Grid.Grid & String) -> List<&2, String>:
  (_, +line) = got
  [line]

def after_void(got: Grid.Grid & Pcg.Rng, +c: Ctx) -> List<&2, String>:
  (g, rng) = got
  match c:
    case Ctx{+seed, +a, _}:
      last_line(OceanRows.digest(g, a, "void", Pcg.counter(seed, rng)))

def after_shore(got: Grid.Grid & String, rng: Pcg.Rng, +c: Ctx) -> List<&2, String>:
  (g, +line) = got
  line <> after_void(OceanConvert.void_outline(g, rng), c)

def after_blend(got: Grid.Grid & String, rng: Pcg.Rng, +c: Ctx) -> List<&2, String>:
  (g, +line) = got
  line <> after_shore(OceanRows.digest(OceanConvert.shoreline(g), ctx_a(c), "shoreline", ctx_ctr(c)), rng, c)

def blend_line(+c: Ctx, +k: U32, +n: U32, +h: Grid.Hash) -> String:
  Canon.record("oblend", [Canon.field("a", ctx_a(c)), Canon.number("k", k), Canon.number("n", n), Canon.field("hash", OceanRows.hash_text(h))])

def hashed_el(got: Array<U32> & Grid.Hash, g: Grid.Grid, rng: Pcg.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (o, +h) = got
  blend_line(c, 2, n, h) <> after_blend(OceanRows.digest(ConvertBlend.apply(g, o), ctx_a(c), "blend", ctx_ctr(c)), rng, c)

def hashed_g(got: Array<U32> & Grid.Hash, g: Grid.Grid, rng: Pcg.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (o, +h) = got
  blend_line(c, 1, n, h) <> hashed_el(ConvertBlend.map_hash(o, ConvertBlend.el_base(n), n), g, rng, c, n)

def hashed_cm(got: Array<U32> & Grid.Hash, g: Grid.Grid, rng: Pcg.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (o, +h) = got
  blend_line(c, 0, n, h) <> hashed_g(ConvertBlend.map_hash(o, ConvertBlend.g_base(n), n), g, rng, c, n)

def mapped(got: Grid.Grid & Array<U32>, rng: Pcg.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (g, o) = got
  hashed_cm(ConvertBlend.map_hash(o, ConvertBlend.cm_base(n), n), g, rng, c, n)

# OceanConvert.blend is ConvertBlend.apply after ConvertBlend.maps; the trace hashes the maps in between.
def noise_line(got: Grid.Grid & String, rng: Pcg.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (g, +line) = got
  line <> mapped(ConvertBlend.maps(g), rng, c, n)

def after_noise(got: Grid.Grid & Pcg.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (g, +rng) = got
  match c:
    case Ctx{+seed, +a, _}:
      +ctr = Pcg.counter(seed, rng)
      noise_line(OceanRows.digest(g, a, "noise", ctr), rng, Ctx{seed, a, ctr}, n)

def after_fills(got: Grid.Grid & String, +c: Ctx, +n: U32) -> List<&2, String>:
  (g, +line) = got
  match c:
    case Ctx{+seed, _, +ctr}:
      line <> after_noise(OceanConvert.noise(g, Pcg.at_counter(seed, ctr)), c, n)

def attempt(+sequential: Bool, +seed: U32, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  +oin = OceanRows.input(a, lines)
  +w = TileInput.num("w", oin)
  +h = TileInput.num("h", oin)
  +ctr = TileInput.num("ctr", OceanRows.digest_record(a, "\"prefill\"", lines))
  filled = ConvertFills.fills_with(OceanRows.grid(a, "\"prefill\"", w, h, lines), sequential)
  after_fills(OceanRows.digest(filled, a, "fills", ctr), Ctx{seed, a, ctr}, (w * h : U32))

def attempts(as: List<&2, String>, +sequential: Bool, +seed: U32, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, attempt(sequential, seed, a, lines), attempts(rest, sequential, seed, lines))

# The stage's records for a seed and the lines of its input (the conversion does not depend on the platform).
def run_with(+sequential: Bool, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  attempts(OceanRows.attempts(lines), sequential, seed, lines)

def run(+seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  run_with(False{}, seed, windows, lines)
