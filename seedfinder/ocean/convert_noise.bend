import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../f32/ops.bend as F32Ops
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../data/constants.bend as Constants
import ../data/enums.bend as Enums
import ../data/ocean_convert.bend as OceanConvertData
import ../worldsim/grid.bend as Grid
import ../worldsim/noise/perlin.bend as Perlin
import ./convert_plane.bend as ConvertPlane
import ./convert_fills.bend as ConvertFills

# Ocean_ConvertImpassibleToWater's do_noise: six math.random offsets, then every IMPASSABLE tile becomes OCEAN_SWELL
# when simplexnoise2d over the water noise is above init_level_medium, else OCEAN_HAZARDOUS when the shipgrave noise
# is above init_level_grave, else OCEAN_ROUGH. simplexnoise2d(x, y, n, p) sums perlin(f * x, f * y, 0) with
# amplitudes 1, p, p^2, ... and frequencies 2, 4, ... and divides by the amplitude sum.
#
# Exactness: everything that depends on one column or one row alone (nx, the scaled input, each octave's floor,
# fraction and fade) is computed once in exact soft doubles. Per tile the octave sum runs in F32 from those values
# (with z = 0 ImprovedNoise is (m0 + 1) / 2, the z-lerp adds an exact zero) and is compared with the threshold on
# the sum, c = amps * (2 * level - 1). The F32 sum is within 2^-15 of the double one (proof and measurement in
# .scratch/port/status/M10_convert.md), so a sum more than 2^-12 away from c decides the comparison; a tile inside
# that band runs the exact soft-double simplexnoise2d, division included.

# The band half-width 2^-12.
def margin() -> F64Repr.F64:
  F64Repr.F64{1060110336, 0}

type Offsets is Data:
  Offsets{water_x: F64Repr.F64, water_y: F64Repr.F64, grave_x: F64Repr.F64, grave_y: F64Repr.F64}

def offset_drawn(got: U32 & Pcg.Rng) -> F64Repr.F64 & Pcg.Rng:
  (+v, rng) = got
  (F64Repr.from_i32(v), rng)

def draw_offset(rng: Pcg.Rng, +n: U32) -> F64Repr.F64 & Pcg.Rng:
  offset_drawn(MathRandom.random_range(rng, (0 - n : U32), n))

def offsets_gy(got: F64Repr.F64 & Pcg.Rng, +wx: F64Repr.F64, +wy: F64Repr.F64, +gx: F64Repr.F64) -> Offsets & Pcg.Rng:
  (+gy, rng) = got
  (Offsets{wx, wy, gx, gy}, rng)

def offsets_gx(got: F64Repr.F64 & Pcg.Rng, +wx: F64Repr.F64, +wy: F64Repr.F64, +h: U32) -> Offsets & Pcg.Rng:
  (+gx, rng) = got
  offsets_gy(draw_offset(rng, h), wx, wy, gx)

def offsets_cy(got: F64Repr.F64 & Pcg.Rng, +wx: F64Repr.F64, +wy: F64Repr.F64, +w: U32, +h: U32) -> Offsets & Pcg.Rng:
  (_, rng) = got
  offsets_gx(draw_offset(rng, w), wx, wy, h)

def offsets_cx(got: F64Repr.F64 & Pcg.Rng, +wx: F64Repr.F64, +wy: F64Repr.F64, +h: U32, +w: U32) -> Offsets & Pcg.Rng:
  (_, rng) = got
  offsets_cy(draw_offset(rng, h), wx, wy, w, h)

def offsets_wy(got: F64Repr.F64 & Pcg.Rng, +wx: F64Repr.F64, +w: U32, +h: U32) -> Offsets & Pcg.Rng:
  (+wy, rng) = got
  offsets_cx(draw_offset(rng, w), wx, wy, h, w)

def offsets_wx(got: F64Repr.F64 & Pcg.Rng, +w: U32, +h: U32) -> Offsets & Pcg.Rng:
  (+wx, rng) = got
  offsets_wy(draw_offset(rng, h), wx, w, h)

# The water, coral and shipgrave offsets, math.random(-w, w) then math.random(-h, h) each (the coral ones unused).
def offsets(rng: Pcg.Rng, +w: U32, +h: U32) -> Offsets & Pcg.Rng:
  offsets_wx(draw_offset(rng, w), w, h)

# One noise's table layout and thresholds: octave count n, persistence, level, the table offsets of its per-column
# entries (n x 2 words), inputs (2 words), per-row entries and inputs, and in F32 the persistence, the threshold on
# the sum c, the band half-width and the amplitude sum.
type Field is Data:
  Field{n: U32, pers_hi: U32, pers_lo: U32, level_hi: U32, level_lo: U32, cols: U32, colx: U32, rows: U32, rowy: U32, persf: F32, c: F32, m: F32, amps: F32}

def octave_count(+octaves: U32) -> U32:
  (Bool.pick(U32, (octaves > 2 : U32), (octaves - 1 : U32), 1) + 1 : U32)

def f64_of(bits: U32 & U32) -> F64Repr.F64:
  (+hi, +lo) = bits
  F64Repr.F64{hi, lo}

def amps_go(n: Nat, +amp: F64Repr.F64, +pers: F64Repr.F64, +acc: F64Repr.F64) -> F64Repr.F64:
  match n:
    case 0n:
      acc
    case 1n+p:
      amps_go(p, F64Arith.mul(amp, pers), pers, F64Arith.add(acc, amp))

def packed(+pers: F64Repr.F64, +level: F64Repr.F64, +n: U32, +cols: U32, +colx: U32, +rows: U32, +rowy: U32, +persf: F32, +c: F32, +amps: F32) -> Field:
  match pers level:
    case F64Repr.F64{+ph, +pl} F64Repr.F64{+lh, +ll}:
      Field{n, ph, pl, lh, ll, cols, colx, rows, rowy, persf, c, F32Ops.from_f64(margin()), amps}

def field_at(+n: U32, +pers: F64Repr.F64, +level: F64Repr.F64, +base: U32, +w: U32, +h: U32) -> Field:
  +colx = (base + w * n * 2 : U32)
  +rows = (colx + w * 2 : U32)
  +rowy = (rows + h * n * 2 : U32)
  +amps = amps_go(U32.to_nat(n), F64Repr.one(), pers, F64Repr.zero())
  +c = F64Arith.mul(amps, F64Arith.sub(F64Arith.mul(F64Repr.two(), level), F64Repr.one()))
  packed(pers, level, n, base, colx, rows, rowy, F32Ops.from_f64(pers), F32Ops.from_f64(c), F32Ops.from_f64(amps))

def field_size(+f: Field, +h: U32) -> U32:
  match f:
    case Field{_, _, _, _, _, +cols, _, _, +rowy, _, _, _, _}:
      (rowy + h * 2 - cols : U32)

def t_base() -> U32:
  0

def perm_base() -> U32:
  65536

def fields_base() -> U32:
  65792

def water_field(+w: U32, +h: U32) -> Field:
  field_at(octave_count(OceanConvertData.noise_octave_water()), f64_of(OceanConvertData.noise_persistence_water()), f64_of(OceanConvertData.init_level_medium()),
    fields_base(), w, h)

def grave_base(+w: U32, +h: U32) -> U32:
  (fields_base() + field_size(water_field(w, h), h) : U32)

def grave_field(+w: U32, +h: U32) -> Field:
  field_at(octave_count(OceanConvertData.noise_octave_grave()), f64_of(OceanConvertData.noise_persistence_grave()), f64_of(OceanConvertData.init_level_grave()),
    grave_base(w, h), w, h)

# A gradient code's (x, y) coefficients for z = 0, each plus one, in 2 bits each: grad(h, x, y, 0) = cx * x + cy * y.
def coef(+k: U32) -> U32:
  +ax = Bool.to_u32((k < 8 : U32))
  +bx = Bool.to_u32(U32.is_eq(k, 12) || U32.is_eq(k, 14))
  +by = Bool.to_u32((k < 4 : U32))
  +na = (k .&. 1 : U32)
  +nb = ((k >> 1n) .&. 1 : U32)
  +cx = (1 + ax + bx - 2 * ax * na - 2 * bx * nb : U32)
  +cy = (1 + (1 - ax) + by - 2 * (1 - ax) * na - 2 * by * nb : U32)
  (cx .|. (cy << 2n) : U32)

def perm_at(t: Array<U32>, +i: U32) -> Array<U32> & U32:
  t[(perm_base() + (i .&. 255) : U32)]

type Coefs is Data:
  Coefs{low: U32, high: U32}

def coefs_go(n: Nat, +k: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      coefs_go(p, (k + 1 : U32), (acc .|. (coef(k) << U32.to_nat(((k .&. 7) * 4 : U32))) : U32))

def coefs() -> Coefs:
  Coefs{coefs_go(8n, 0, 0), coefs_go(8n, 8, 0)}

def coded(+cs: Coefs, +v: U32) -> U32:
  match cs:
    case Coefs{+low, +high}:
      +k = (v .&. 15 : U32)
      ((Bool.pick(U32, (k < 8 : U32), low, high) >> U32.to_nat(((k .&. 7) * 4 : U32))) .&. 15 : U32)

def hash_bb(got: Array<U32> & U32, +i: U32, +packed: U32, +cs: Coefs) -> Array<U32>:
  (t, +v) = got
  t[i] <- (packed .|. (coded(cs, v) << 12n) : U32)

def hash_ab(got: Array<U32> & U32, +i: U32, +bb: U32, +packed: U32, +cs: Coefs) -> Array<U32>:
  (t, +v) = got
  hash_bb(perm_at(t, bb), i, (packed .|. (coded(cs, v) << 8n) : U32), cs)

def hash_ba(got: Array<U32> & U32, +i: U32, +ab: U32, +bb: U32, +packed: U32, +cs: Coefs) -> Array<U32>:
  (t, +v) = got
  hash_ab(perm_at(t, ab), i, bb, (packed .|. (coded(cs, v) << 4n) : U32), cs)

def hash_aa(got: Array<U32> & U32, +i: U32, +ba: U32, +ab: U32, +bb: U32, +cs: Coefs) -> Array<U32>:
  (t, +v) = got
  hash_ba(perm_at(t, ba), i, ab, bb, coded(cs, v), cs)

def corner_bb(got: Array<U32> & U32, +i: U32, +aa: U32, +ba: U32, +ab: U32, +cs: Coefs) -> Array<U32>:
  (t, +bb) = got
  hash_aa(perm_at(t, aa), i, ba, ab, bb, cs)

def corner_ba(got: Array<U32> & U32, +i: U32, +aa: U32, +ab: U32, +b: U32, +cs: Coefs) -> Array<U32>:
  (t, +ba) = got
  corner_bb(perm_at(t, (b + 1 : U32)), i, aa, ba, ab, cs)

def corner_ab(got: Array<U32> & U32, +i: U32, +aa: U32, +b: U32, +cs: Coefs) -> Array<U32>:
  (t, +ab) = got
  corner_ba(perm_at(t, b), i, aa, ab, b, cs)

def corner_aa(got: Array<U32> & U32, +i: U32, +a: U32, +b: U32, +cs: Coefs) -> Array<U32>:
  (t, +aa) = got
  corner_ab(perm_at(t, (a + 1 : U32)), i, aa, b, cs)

def hash_entry(t: Array<U32>, +i: U32, +px: U32, +px1: U32, +cs: Coefs) -> Array<U32>:
  +y = (i .&. 255 : U32)
  +a = (px + y : U32)
  corner_aa(perm_at(t, a), i, a, (px1 + y : U32), cs)

def hash_row(n: Nat, t: Array<U32>, +i: U32, +px: U32, +px1: U32, +cs: Coefs) -> Array<U32>:
  match n:
    case 0n:
      t
    case 1n+p:
      hash_row(p, hash_entry(t, i, px, px1, cs), (i + 1 : U32), px, px1, cs)

def hash_px1(got: Array<U32> & U32, +x: U32, +px: U32, +cs: Coefs) -> Array<U32>:
  (t, +px1) = got
  hash_row(256n, t, (x << 8n : U32), px, px1, cs)

def hash_px(got: Array<U32> & U32, +x: U32, +cs: Coefs) -> Array<U32>:
  (t, +px) = got
  hash_px1(perm_at(t, (x + 1 : U32)), x, px, cs)

def hash_go(n: Nat, t: Array<U32>, +x: U32, +cs: Coefs) -> Array<U32>:
  match n:
    case 0n:
      t
    case 1n+p:
      hash_go(p, hash_px(perm_at(t, x), x, cs), (x + 1 : U32), cs)

# The 256 x 256 table of packed corner coefficients (4 bits per corner: aa, ba, ab, bb) for cell pairs (X, Y).
def hash_table(n: Nat, t: Array<U32>, +x: U32) -> Array<U32>:
  hash_go(n, t, x, coefs())

def put_f64(t: Array<U32>, +i: U32, +v: F64Repr.F64) -> Array<U32>:
  match v:
    case F64Repr.F64{+hi, +lo}:
      t[i] <- hi
      t[(i + 1 : U32)] <- lo

def two24() -> F64Repr.F64:
  F64Repr.F64{1097859072, 0}

def axis_octaves(n: Nat, t: Array<U32>, +i: U32, +v: F64Repr.F64, +freq: F64Repr.F64) -> Array<U32>:
  match n:
    case 0n:
      t
    case 1n+p:
      +s = F64Arith.mul(freq, v)
      +whole = F64Repr.floor(s)
      +frac = F64Arith.sub(s, whole)
      t[i] <- (((F64Repr.to_i32(whole) .&. 255) << 24n) .|. F64Repr.to_i32(F64Arith.mul(frac, two24())) : U32)
      t[(i + 1 : U32)] <- F64Repr.to_f32_bits(Perlin.fade(frac))
      axis_octaves(p, t, (i + 2 : U32), v, F64Arith.mul(freq, F64Repr.two()))

def axis_input(+k: U32, +size: U32, +scale: F64Repr.F64, +offset: F64Repr.F64) -> F64Repr.F64:
  F64Arith.mul(scale, F64Arith.add(F64Arith.sub(F64Arith.div(F64Repr.from_u32(k), F64Repr.from_u32(size)), F64Repr.half()), offset))

# Per column (or row) k: the scaled input scale * (k / size - 0.5 + offset), and per octave the cell index (the top
# 8 bits) with the fraction truncated to 24 bits, and the fade of the fraction as F32 bits.
def axis(n: Nat, t: Array<U32>, +k: U32, +size: U32, +octaves: U32, +scale: F64Repr.F64, +offset: F64Repr.F64, +entries: U32, +inputs: U32) -> Array<U32>:
  match n:
    case 0n:
      t
    case 1n+p:
      +v = axis_input(k, size, scale, offset)
      filled = axis_octaves(U32.to_nat(octaves), put_f64(t, (inputs + k * 2 : U32), v), (entries + k * octaves * 2 : U32), v, F64Repr.two())
      axis(p, filled, (k + 1 : U32), size, octaves, scale, offset, entries, inputs)

def axis_of(t: Array<U32>, +f: Field, +size: U32, +scale: F64Repr.F64, +offset: F64Repr.F64, +columns: Bool) -> Array<U32>:
  match f:
    case Field{+n, _, _, _, _, +cols, +colx, +rows, +rowy, _, _, _, _}:
      +entries = Bool.pick(U32, columns, cols, rows)
      +inputs = Bool.pick(U32, columns, colx, rowy)
      axis(U32.to_nat(size), t, 0, size, n, scale, offset, entries, inputs)

def table_size(+w: U32, +h: U32) -> U32:
  (grave_base(w, h) + field_size(grave_field(w, h), h) : U32)

def results_size(+w: U32, +h: U32) -> U32:
  (ConvertPlane.size(ConvertPlane.geo(w, h)) * 7 : U32)

def blank(+size: U32) -> Array<U32>:
  Grid.alloc(Grid.depth_for(24n, size, 0n, 1), 0)

def water_axis(t: Array<U32>, +w: U32, +h: U32, +o: Offsets, +columns: Bool) -> Array<U32>:
  match o:
    case Offsets{+wx, +wy, _, _}:
      +size = Bool.pick(U32, columns, w, h)
      axis_of(t, water_field(w, h), size, f64_of(OceanConvertData.noise_scale_water()), Bool.pick(F64Repr.F64, columns, wx, wy), columns)

def grave_axis(t: Array<U32>, +w: U32, +h: U32, +o: Offsets, +columns: Bool) -> Array<U32>:
  match o:
    case Offsets{_, _, +gx, +gy}:
      +size = Bool.pick(U32, columns, w, h)
      axis_of(t, grave_field(w, h), size, f64_of(OceanConvertData.noise_scale_grave()), Bool.pick(F64Repr.F64, columns, gx, gy), columns)

# One of the table's eight independent parts: job 0..3 a quarter of the hash table, 4..7 the water columns and
# rows, the shipgrave columns and rows.
def table_job(+job: U32, t: Array<U32>, +w: U32, +h: U32, +o: Offsets) -> Array<U32>:
  match job:
    case 4:
      water_axis(t, w, h, o, True{})
    case 5:
      water_axis(t, w, h, o, False{})
    case 6:
      grave_axis(t, w, h, o, True{})
    case 7:
      grave_axis(t, w, h, o, False{})
    case _:
      hash_go(64n, t, (job * 64 : U32), coefs())

def table_par(+d: Nat, got: Array<U32> & Array<U32>, +job: U32, +w: U32, +h: U32, +o: Offsets) -> Array<U32>:
  match d:
    case 0n:
      (t, other) = got
      Array.join(U32, table_job(job, t, w, h, o), other)
    case 1n+p:
      (a, b) = got
      l r = table_par(p, Array.fork(U32, a), job, w, h, o) table_par(p, Array.fork(U32, b), (job + (1 << p) : U32), w, h, o)
      Array.join(U32, l, r)

# The noise table: the 2-D hash table (the four corner gradient codes of each cell pair, z = 0), the permutation, and
# both noises' column and row entries, built by eight parallel jobs.
def table(+w: U32, +h: U32, +o: Offsets) -> Array<U32>:
  perm = Perlin.fill_perm(List.drop(&2, U32, Constants.perlin(0), 0n), blank((table_size(w, h) + results_size(w, h) : U32)), perm_base())
  table_par(3n, Array.fork(U32, perm), 0, w, h, o)

def coef_f(+h: U32, +sh: Nat) -> F32:
  F32Ops.sub(F32Ops.from_u32(((h >> sh) .&. 3 : U32)), 1.0)

def grad(+h: U32, +sh: Nat, +x: F32, +y: F32) -> F32:
  F32Ops.add(F32Ops.mul(coef_f(h, sh), x), F32Ops.mul(coef_f(h, 2n+sh), y))

def lerp(+t: F32, +a: F32, +b: F32) -> F32:
  F32Ops.add(F32Ops.mul(F32Ops.sub(b, a), t), a)

# ImprovedNoise's m0 (the z = 0 layer before (n + 1) / 2) in F32 from the packed corner coefficients.
def layer(+h: U32, +x: F32, +u: F32, +y: F32, +v: F32) -> F32:
  +x1 = F32Ops.sub(x, 1.0)
  +y1 = F32Ops.sub(y, 1.0)
  +l0 = lerp(u, grad(h, 0n, x, y), grad(h, 4n, x1, y))
  +l1 = lerp(u, grad(h, 8n, x, y1), grad(h, 12n, x1, y1))
  lerp(v, l0, l1)

def unit24() -> F32:
  F32Ops.from_bits(864026624)

def fraction(+word: U32) -> F32:
  F32Ops.mul(F32Ops.from_u32((word .&. 16777215 : U32)), unit24())

# Per octave: the amplitude, the persistence, c and the band half-width.
type Step is Data:
  Step{amp: F32, pers: F32, c: F32, m: F32}

# The running sum, the amplitude still to come and whether the sum is still within reach of c.
type Acc is Data:
  Acc{s: F32, rem: F32, open: Bool}

def summed(+s: F32, +rem: F32, +st: Step) -> Acc:
  match st:
    case Step{_, _, +c, +m}:
      +d = F32Ops.sub(s, c)
      +bound = F32Ops.add(rem, m)
      Acc{s, rem, F32Ops.le(d, bound) && F32Ops.le(F32Ops.sub(0.0, bound), d)}

def oct_t(got: Array<U32> & U32, +cw: U32, +uf: F32, +rw: U32, +vf: F32, +s: F32, +rem: F32, +st: Step) -> Array<U32> & Acc:
  (t, +h) = got
  match st:
    case Step{+amp, _, _, _}:
      +m0 = layer(h, fraction(cw), uf, fraction(rw), vf)
      (t, summed(F32Ops.add(s, F32Ops.mul(amp, m0)), F32Ops.sub(rem, amp), st))

def oct_v(got: Array<U32> & U32, +cw: U32, +uf: F32, +rw: U32, +s: F32, +rem: F32, +st: Step) -> Array<U32> & Acc:
  (t, +vb) = got
  +k = (t_base() + (((cw >> 16n) .&. 65280) .|. (rw >> 24n)) : U32)
  oct_t(t[k], cw, uf, rw, F32Ops.from_bits(vb), s, rem, st)

def oct_r(got: Array<U32> & U32, +cw: U32, +uf: F32, +ri: U32, +s: F32, +rem: F32, +st: Step) -> Array<U32> & Acc:
  (t, +rw) = got
  oct_v(t[(ri + 1 : U32)], cw, uf, rw, s, rem, st)

def oct_u(got: Array<U32> & U32, +cw: U32, +ri: U32, +s: F32, +rem: F32, +st: Step) -> Array<U32> & Acc:
  (t, +ub) = got
  oct_r(t[ri], cw, F32Ops.from_bits(ub), ri, s, rem, st)

def oct_c(got: Array<U32> & U32, +ci: U32, +ri: U32, +s: F32, +rem: F32, +st: Step) -> Array<U32> & Acc:
  (t, +cw) = got
  oct_u(t[(ci + 1 : U32)], cw, ri, s, rem, st)

def next_step(+st: Step) -> Step:
  match st:
    case Step{+amp, +pers, +c, +m}:
      Step{F32Ops.mul(amp, pers), pers, c, m}

def approx_go(n: Nat, got: Array<U32> & Acc, +ci: U32, +ri: U32, +st: Step) -> Array<U32> & Acc:
  match n:
    case 0n:
      got
    case 1n+p:
      (t, +acc) = got
      match acc:
        case Acc{+s, +rem, +open}:
          match open:
            case True{}:
              approx_go(p, oct_c(t[ci], ci, ri, s, rem, st), (ci + 2 : U32), (ri + 2 : U32), next_step(st))
            case False{}:
              (t, Acc{s, rem, False{}})
def simplex_go(n: Nat, got: Array<U32> & F64Repr.F64, +x: F64Repr.F64, +y: F64Repr.F64, +freq: F64Repr.F64, +amp: F64Repr.F64, +noise: F64Repr.F64, +amps: F64Repr.F64, +pers: F64Repr.F64) -> Array<U32> & F64Repr.F64:
  match n:
    case 0n:
      (perm, +v) = got
      (perm, F64Arith.div(F64Arith.add(noise, F64Arith.mul(amp, v)), F64Arith.add(amps, amp)))
    case 1n+p:
      (perm, +v) = got
      next = Perlin.noise(perm, F64Arith.mul(freq, x), F64Arith.mul(freq, y), F64Repr.zero())
      simplex_go(p, next, x, y, F64Arith.mul(freq, F64Repr.two()), F64Arith.mul(amp, pers), F64Arith.add(noise, F64Arith.mul(amp, v)), F64Arith.add(amps, amp), pers)

# simplexnoise2d(x, y, octaves, persistence) in exact soft doubles (n = the loop's octave count).
def simplex(+n: U32, +x: F64Repr.F64, +y: F64Repr.F64, +pers: F64Repr.F64) -> F64Repr.F64:
  first = Perlin.noise(Perlin.permutation(), F64Arith.mul(F64Repr.two(), x), F64Arith.mul(F64Repr.two(), y), F64Repr.zero())
  +four = F64Arith.mul(F64Repr.two(), F64Repr.two())
  Pair.snd(Array<U32>, F64Repr.F64, simplex_go(U32.to_nat((n - 1 : U32)), first, x, y, four, F64Repr.one(), F64Repr.zero(), F64Repr.zero(), pers))

def exact_y1(got: Array<U32> & U32, +f: Field, +x: F64Repr.F64, +yh: U32) -> Array<U32> & Bool:
  (t, +yl) = got
  match f:
    case Field{+n, +ph, +pl, +lh, +ll, _, _, _, _, _, _, _, _}:
      (t, F64Cmp.gt(simplex(n, x, F64Repr.F64{yh, yl}, F64Repr.F64{ph, pl}), F64Repr.F64{lh, ll}))

def exact_y0(got: Array<U32> & U32, +f: Field, +x: F64Repr.F64, +yi: U32) -> Array<U32> & Bool:
  (t, +yh) = got
  exact_y1(t[(yi + 1 : U32)], f, x, yh)

def exact_x1(got: Array<U32> & U32, +f: Field, +xh: U32, +yi: U32) -> Array<U32> & Bool:
  (t, +xl) = got
  exact_y0(t[yi], f, F64Repr.F64{xh, xl}, yi)

def exact_x0(got: Array<U32> & U32, +f: Field, +xi: U32, +yi: U32) -> Array<U32> & Bool:
  (t, +xh) = got
  exact_x1(t[(xi + 1 : U32)], f, xh, yi)

def exact(t: Array<U32>, +f: Field, +x: U32, +y: U32) -> Array<U32> & Bool:
  match f:
    case Field{_, _, _, _, _, _, +colx, _, +rowy, _, _, _, _}:
      +xi = (colx + x * 2 : U32)
      exact_x0(t[xi], f, xi, (rowy + y * 2 : U32))

def code_of(got: Array<U32> & Acc, +f: Field) -> Array<U32> & U32:
  (t, +acc) = got
  match acc:
    case Acc{+s, _, +open}:
      match f:
        case Field{_, _, _, _, _, _, _, _, _, _, +c, _, _}:
          (t, Bool.pick(U32, open, 2, Bool.to_u32(Bool.not(F32Ops.le(s, c)))))

# simplexnoise2d(...) > level for the tile (x, y) of the field as far as the F32 octave sum decides it: 1 above,
# 0 not above, 2 undecided (within the band after the last octave). The sum stops as soon as the amplitude still to
# come cannot bring it within the band around c.
def above(t: Array<U32>, +f: Field, +x: U32, +y: U32) -> Array<U32> & U32:
  match f:
    case Field{+n, _, _, _, _, +cols, _, +rows, _, +persf, +c, +m, +amps}:
      +ci = (cols + x * n * 2 : U32)
      +ri = (rows + y * n * 2 : U32)
      +start = {Acc{0.0, amps, True{}} : Acc}
      code_of(approx_go(U32.to_nat(n), (t, start), ci, ri, Step{1.0, persf, c, m}), f)

def grave_code(got: Array<U32> & U32) -> Array<U32> & U32:
  (t, +gc) = got
  (t, Bool.pick(U32, U32.is_eq(gc, 1), 2, Bool.pick(U32, U32.is_eq(gc, 2), 3, 0)))

def grave_if(below: Bool, t: Array<U32>, +wc: U32, +gf: Field, +x: U32, +y: U32) -> Array<U32> & U32:
  match below:
    case True{}:
      grave_code(above(t, gf, x, y))
    case False{}:
      (t, Bool.pick(U32, U32.is_eq(wc, 1), 1, 3))

def water_then(got: Array<U32> & U32, +gf: Field, +x: U32, +y: U32) -> Array<U32> & U32:
  (t, +wc) = got
  grave_if(U32.is_eq(wc, 0), t, wc, gf, x, y)

# The tile's class as far as the F32 sums decide it: 1 OCEAN_SWELL, 2 OCEAN_HAZARDOUS, 0 OCEAN_ROUGH, 3 undecided.
def cell_code(t: Array<U32>, +wf: Field, +gf: Field, +x: U32, +y: U32) -> Array<U32> & U32:
  water_then(above(t, wf, x, y), gf, x, y)

def mark(got: Array<U32> & U32, +slot: U32, +bit: U32) -> Array<U32>:
  (t, +v) = got
  t[slot] <- (v .|. (1 << U32.to_nat(bit)) : U32)

def mark_if(hit: Bool, t: Array<U32>, +slot: U32, +bit: U32) -> Array<U32>:
  match hit:
    case True{}:
      mark(t[slot], slot, bit)
    case False{}:
      t

# The swell, hazardous and undecided planes sit 4, 5 and 6 planes after the impassable plane (the first of its
# four-plane extraction block).
type Out is Data:
  Out{swell: U32, hazard: U32, open: U32}

def marked(got: Array<U32> & U32, +at: U32, +bit: U32, +o: Out) -> Array<U32>:
  (t, +c) = got
  match o:
    case Out{+sg, +hg, +og}:
      swelled = mark_if(U32.is_eq(c, 1), t, (at + sg : U32), bit)
      hazard = mark_if(U32.is_eq(c, 2), swelled, (at + hg : U32), bit)
      mark_if(U32.is_eq(c, 3), hazard, (at + og : U32), bit)

def cell_if(hit: Bool, t: Array<U32>, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +bit: U32, +o: Out) -> Array<U32>:
  match hit:
    case True{}:
      marked(cell_code(t, wf, gf, x, y), at, bit, o)
    case False{}:
      t

def bits_go(n: Nat, t: Array<U32>, +word: U32, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +bit: U32, +o: Out) -> Array<U32>:
  match n:
    case 0n:
      t
    case 1n+p:
      +hit = U32.is_ne(((word >> U32.to_nat(bit)) .&. 1 : U32), 0)
      bits_go(p, cell_if(hit, t, wf, gf, x, y, at, bit, o), word, wf, gf, (x + 1 : U32), y, at, (bit + 1 : U32), o)

def word_if(hit: Bool, t: Array<U32>, +word: U32, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +o: Out) -> Array<U32>:
  match hit:
    case True{}:
      bits_go(32n, t, word, wf, gf, x, y, at, 0, o)
    case False{}:
      t

def word_read(got: Array<U32> & U32, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +o: Out) -> Array<U32>:
  (t, +word) = got
  word_if(U32.is_ne(word, 0), t, word, wf, gf, x, y, at, o)

def words_go(n: Nat, t: Array<U32>, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +o: Out) -> Array<U32>:
  match n:
    case 0n:
      t
    case 1n+p:
      words_go(p, word_read(t[at], wf, gf, x, y, at, o), wf, gf, (x + 32 : U32), y, (at + 1 : U32), o)

def rows_go(n: Nat, t: Array<U32>, +wf: Field, +gf: Field, +y: U32, +at: U32, +ww: U32, +o: Out) -> Array<U32>:
  match n:
    case 0n:
      t
    case 1n+p:
      rows_go(p, words_go(U32.to_nat(ww), t, wf, gf, 0, y, at, o), wf, gf, (y + 1 : U32), (at + ww : U32), ww, o)

def leaf(got: Array<U32> & Array<U32>, +n: Nat, +wf: Field, +gf: Field, +y: U32, +at: U32, +ww: U32, +o: Out) -> Array<U32>:
  (t, other) = got
  Array.join(U32, rows_go(n, t, wf, gf, y, at, ww, o), other)

# The map's rows split over a balanced fork tree; the leaves share the table (Array.fork), read the impassable
# plane's words, the hash, column and row entries, and set their own rows' bits of the result planes.
def par(+d: Nat, got: Array<U32> & Array<U32>, +n: Nat, +wf: Field, +gf: Field, +y: U32, +at: U32, +ww: U32, +o: Out) -> Array<U32>:
  match d:
    case 0n:
      leaf(got, n, wf, gf, y, at, ww, o)
    case 1n+p:
      (a, b) = got
      +half = Nat.div(n, 2n)
      +yb = (y + U32.from_nat(half) : U32)
      +ab = (at + U32.from_nat(half) * ww : U32)
      l r = par(p, Array.fork(U32, a), half, wf, gf, y, at, ww, o) par(p, Array.fork(U32, b), Nat.sub(n, half), wf, gf, yb, ab, ww, o)
      Array.join(U32, l, r)

def open_gap(+o: Out) -> U32:
  match o:
    case Out{_, _, +og}:
      og

def grave_exact(got: Array<U32> & Bool) -> Array<U32> & U32:
  (t, +hit) = got
  (t, Bool.pick(U32, hit, 2, 0))

def water_exact(got: Array<U32> & Bool, +gf: Field, +x: U32, +y: U32) -> Array<U32> & U32:
  (t, +hit) = got
  match hit:
    case True{}:
      (t, 1)
    case False{}:
      grave_exact(exact(t, gf, x, y))

def fix_if(hit: Bool, t: Array<U32>, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +bit: U32, +o: Out) -> Array<U32>:
  match hit:
    case True{}:
      marked(water_exact(exact(t, wf, x, y), gf, x, y), at, bit, o)
    case False{}:
      t

def fix_bits(n: Nat, t: Array<U32>, +word: U32, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +bit: U32, +o: Out) -> Array<U32>:
  match n:
    case 0n:
      t
    case 1n+p:
      +hit = U32.is_ne(((word >> U32.to_nat(bit)) .&. 1 : U32), 0)
      fix_bits(p, fix_if(hit, t, wf, gf, x, y, at, bit, o), word, wf, gf, (x + 1 : U32), y, at, (bit + 1 : U32), o)

def fix_word_if(hit: Bool, t: Array<U32>, +word: U32, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +o: Out) -> Array<U32>:
  match hit:
    case True{}:
      fix_bits(32n, t, word, wf, gf, x, y, at, 0, o)
    case False{}:
      t

def fix_word(got: Array<U32> & U32, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +o: Out) -> Array<U32>:
  (t, +word) = got
  fix_word_if(U32.is_ne(word, 0), t, word, wf, gf, x, y, at, o)

def fix_go(n: Nat, t: Array<U32>, +wf: Field, +gf: Field, +x: U32, +y: U32, +at: U32, +ww: U32, +o: Out) -> Array<U32>:
  match n:
    case 0n:
      t
    case 1n+p:
      +wrap = U32.is_eq((x + 32 : U32), (ww * 32 : U32))
      next = fix_word(t[(at + open_gap(o) : U32)], wf, gf, x, y, at, o)
      fix_go(p, next, wf, gf, Bool.pick(U32, wrap, 0, (x + 32 : U32)), Bool.pick(U32, wrap, (y + 1 : U32), y), (at + 1 : U32), ww, o)

def is_impassable_cell(+cell: U32) -> U32:
  Bool.to_u32(U32.is_eq(Grid.tile_of(cell), Enums.tile_impassable()))

def rough(+cell: U32) -> U32:
  ConvertFills.set_tile(Enums.tile_ocean_rough(), cell)

def swell(+cell: U32) -> U32:
  ConvertFills.set_tile(Enums.tile_ocean_swell(), cell)

def hazardous(+cell: U32) -> U32:
  ConvertFills.set_tile(Enums.tile_ocean_hazardous(), cell)

def fork_depth() -> Nat:
  7n

def painted(got: Array<U32> & Array<U32>, +g: ConvertPlane.Geo, +k: U32) -> Grid.Grid:
  (t, cells) = got
  +p = ConvertPlane.size(g)
  roughs = ConvertPlane.minus(ConvertPlane.minus(t, g, k, (k + 4 * p : U32)), g, k, (k + 5 * p : U32))
  swells = ConvertPlane.paint(~(c => rough(c)), roughs, cells, g, k)
  hazards = ConvertPlane.paint2(~(c => swell(c)), swells, g, (k + 4 * p : U32))
  ConvertFills.painted(ConvertPlane.paint2(~(c => hazardous(c)), hazards, g, (k + 5 * p : U32)), g)

def classified(got: Array<U32> & Array<U32>, +g: ConvertPlane.Geo, +k: U32) -> Grid.Grid:
  (cells, t) = got
  match g:
    case ConvertPlane.Geo{+w, +h, +ww, _}:
      +p = ConvertPlane.size(g)
      +o = {Out{(4 * p : U32), (5 * p : U32), (6 * p : U32)} : Out}
      done = par(fork_depth(), Array.fork(U32, t), U32.to_nat(h), water_field(w, h), grave_field(w, h), 0, k, ww, o)
      fixed = fix_go(U32.to_nat(p), done, water_field(w, h), grave_field(w, h), 0, 0, k, ww, o)
      painted((fixed, cells), g, k)

def drawn(got: Offsets & Pcg.Rng, cells: Array<U32>, +w: U32, +h: U32) -> Grid.Grid & Pcg.Rng:
  (+o, rng) = got
  +g = ConvertPlane.geo(w, h)
  +k = table_size(w, h)
  (classified(ConvertPlane.extract(~(c => is_impassable_cell(c)), cells, table(w, h, o), g, k), g, k), rng)

# do_noise: the six offset draws, then each IMPASSABLE tile becomes OCEAN_SWELL, OCEAN_HAZARDOUS or OCEAN_ROUGH.
def noise(g: Grid.Grid, rng: Pcg.Rng) -> Grid.Grid & Pcg.Rng:
  match g:
    case Grid.Grid{cells, +w, +h}:
      drawn(offsets(rng, w, h), cells, w, h)
