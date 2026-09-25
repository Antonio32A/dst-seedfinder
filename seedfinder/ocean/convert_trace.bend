import Base
import ../rng/pcg.bend as R
import ../trace/canon.bend as CN
import ../worldsim/grid.bend as GR
import ../worldsim/tiles/input.bend as TN
import ./rows.bend as ORW
import ./convert.bend as OV
import ./convert_fills.bend as OF
import ./convert_blend.bend as OB

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

def last_line(got: GR.Grid & String) -> List<&2, String>:
  (_, +line) = got
  [line]

def after_void(got: GR.Grid & R.Rng, +c: Ctx) -> List<&2, String>:
  (g, rng) = got
  match c:
    case Ctx{+seed, +a, _}:
      last_line(ORW.digest(g, a, "void", R.counter(seed, rng)))

def after_shore(got: GR.Grid & String, rng: R.Rng, +c: Ctx) -> List<&2, String>:
  (g, +line) = got
  line <> after_void(OV.void_outline(g, rng), c)

def after_blend(got: GR.Grid & String, rng: R.Rng, +c: Ctx) -> List<&2, String>:
  (g, +line) = got
  line <> after_shore(ORW.digest(OV.shoreline(g), ctx_a(c), "shoreline", ctx_ctr(c)), rng, c)

def blend_line(+c: Ctx, +k: U32, +n: U32, +h: GR.Hash) -> String:
  CN.record("oblend", [CN.field("a", ctx_a(c)), CN.number("k", k), CN.number("n", n), CN.field("hash", ORW.hash_text(h))])

def hashed_el(got: Array<U32> & GR.Hash, g: GR.Grid, rng: R.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (o, +h) = got
  blend_line(c, 2, n, h) <> after_blend(ORW.digest(OB.apply(g, o), ctx_a(c), "blend", ctx_ctr(c)), rng, c)

def hashed_g(got: Array<U32> & GR.Hash, g: GR.Grid, rng: R.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (o, +h) = got
  blend_line(c, 1, n, h) <> hashed_el(OB.map_hash(o, OB.el_base(n), n), g, rng, c, n)

def hashed_cm(got: Array<U32> & GR.Hash, g: GR.Grid, rng: R.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (o, +h) = got
  blend_line(c, 0, n, h) <> hashed_g(OB.map_hash(o, OB.g_base(n), n), g, rng, c, n)

def mapped(got: GR.Grid & Array<U32>, rng: R.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (g, o) = got
  hashed_cm(OB.map_hash(o, OB.cm_base(n), n), g, rng, c, n)

# OV.blend is OB.apply after OB.maps; the trace hashes the maps in between.
def noise_line(got: GR.Grid & String, rng: R.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (g, +line) = got
  line <> mapped(OB.maps(g), rng, c, n)

def after_noise(got: GR.Grid & R.Rng, +c: Ctx, +n: U32) -> List<&2, String>:
  (g, +rng) = got
  match c:
    case Ctx{+seed, +a, _}:
      +ctr = R.counter(seed, rng)
      noise_line(ORW.digest(g, a, "noise", ctr), rng, Ctx{seed, a, ctr}, n)

def after_fills(got: GR.Grid & String, +c: Ctx, +n: U32) -> List<&2, String>:
  (g, +line) = got
  match c:
    case Ctx{+seed, _, +ctr}:
      line <> after_noise(OV.noise(g, R.at_counter(seed, ctr)), c, n)

def attempt(+sequential: Bool, +seed: U32, +a: String, +lines: List<&2, String>) -> List<&2, String>:
  +oin = ORW.input(a, lines)
  +w = TN.num("w", oin)
  +h = TN.num("h", oin)
  +ctr = TN.num("ctr", ORW.digest_record(a, "\"prefill\"", lines))
  filled = OF.fills_with(ORW.grid(a, "\"prefill\"", w, h, lines), sequential)
  after_fills(ORW.digest(filled, a, "fills", ctr), Ctx{seed, a, ctr}, (w * h : U32))

def attempts(as: List<&2, String>, +sequential: Bool, +seed: U32, +lines: List<&2, String>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case Con{+a, rest}:
      List.append(&2, String, attempt(sequential, seed, a, lines), attempts(rest, sequential, seed, lines))

# The stage's records for a seed and the lines of its input (the conversion does not depend on the platform).
def run_with(+sequential: Bool, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  attempts(ORW.attempts(lines), sequential, seed, lines)

def run(+seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  run_with(False{}, seed, windows, lines)
