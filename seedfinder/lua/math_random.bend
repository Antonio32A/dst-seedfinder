import Base
import ../rng/pcg.bend as Pcg

# DST's math.random on the PCG32 stream (research/rng.md §5, §10): r = fl(x / (2^32 - 1)) for the raw output x;
# math.random(u) = floor(r * u) + 1 and math.random(m, n) = floor(r * (n - m + 1)) + m, with floor(r * k) computed
# exactly with U32 operations (ref/dst_rng.c dst_scale_exact32). One draw each; r can be 1.0 (x = 2^32 - 1), which
# gives u + 1 and n + 1, as in the game.

# floor(fl(r * k)) and whether fl(r * k) is an integer.
type Scaled is Data:
  Scaled{floor: U32, exact: Bool}

def lsr(+x: U32, +s: U32) -> U32:
  Bool.pick(U32, (s >= 32 : U32), 0, (x >> U32.to_nat((s .&. 31 : U32)) : U32))

def lsl(+x: U32, +s: U32) -> U32:
  Bool.pick(U32, (s >= 32 : U32), 0, (x << U32.to_nat((s .&. 31 : U32)) : U32))

def low_mask(+bits: U32) -> U32:
  (lsl(1, bits) - 1 : U32)

def floor_log2_loop(n: Nat, +x: U32, +e: U32) -> U32:
  match n:
    case 0n:
      e
    case 1n+p:
      floor_log2_loop(p, (x >> 1n : U32), (e + Bool.to_u32((x >= 2 : U32)) : U32))

def bit_length(+x: U32) -> U32:
  Bool.pick(U32, U32.is_zero(x), 0, (floor_log2_loop(32n, x, 0) + 1 : U32))

def mul_mid(+a: U32, +b: U32) -> U32:
  +ll = ((a .&. 65535 : U32) * (b .&. 65535 : U32) : U32)
  (((ll >> 16n) + (((a .&. 65535 : U32) * (b >> 16n) : U32) .&. 65535 : U32) : U32) + (((a >> 16n) * (b .&. 65535 : U32) : U32) .&. 65535 : U32) : U32)

# The high word of the 64-bit product a * b.
def mul_hi(+a: U32, +b: U32) -> U32:
  +lh = ((a .&. 65535 : U32) * (b >> 16n) : U32)
  +hl = ((a >> 16n) * (b .&. 65535 : U32) : U32)
  (((((a >> 16n) * (b >> 16n) : U32) + (lh >> 16n) : U32) + (hl >> 16n) : U32) + (mul_mid(a, b) >> 16n) : U32)

def shifted_floor(+q0: U32, +q1: U32, +q2: U32, +s: U32) -> U32:
  +high = lsr(q2, (s - 64 : U32))
  +middle = (lsr(q1, (s - 32 : U32)) .|. lsl(q2, (64 - s : U32)) : U32)
  +low = (lsr(q0, s) .|. lsl(q1, (32 - s : U32)) : U32)
  Bool.pick(U32, (s >= 64 : U32), high, Bool.pick(U32, (s >= 32 : U32), middle, low))

def shifted_exact(+q0: U32, +q1: U32, +q2: U32, +s: U32) -> Bool:
  +high = Bool.and(Bool.and(U32.is_zero(q0), U32.is_zero(q1)), U32.is_zero((q2 .&. low_mask((s - 64 : U32)) : U32)))
  +middle = Bool.and(U32.is_zero(q0), U32.is_zero((q1 .&. low_mask((s - 32 : U32)) : U32)))
  Bool.pick(Bool, (s >= 64 : U32), high, Bool.pick(Bool, (s >= 32 : U32), middle, U32.is_zero((q0 .&. low_mask(s) : U32))))

def rounded(+t0: U32, +t1: U32, +t2: U32, +d: U32, +z: U32) -> Scaled:
  +q0 = (lsr(t0, d) .|. lsl(t1, (32 - d : U32)) : U32)
  +q1 = (lsr(t1, d) .|. lsl(t2, (32 - d : U32)) : U32)
  +q2 = lsr(t2, d)
  +round_bit = Bool.not(U32.is_zero((lsr(t0, (d - 1 : U32)) .&. 1 : U32)))
  +sticky = Bool.not(U32.is_zero((t0 .&. low_mask((d - 1 : U32)) : U32)))
  +up = Bool.to_u32(Bool.and(Bool.and(Bool.not(U32.is_zero(d)), round_bit), Bool.or(sticky, U32.is_eq((q0 .&. 1 : U32), 1))))
  +r0 = (q0 + up : U32)
  +r1 = (q1 + Bool.to_u32((r0 < up : U32)) : U32)
  +r2 = (q2 + Bool.to_u32(Bool.and(U32.is_zero(r1), (r0 < up : U32))) : U32)
  Scaled{shifted_floor(r0, r1, r2, ((53 + z : U32) - d : U32)), shifted_exact(r0, r1, r2, ((53 + z : U32) - d : U32))}

def product(+r_lo: U32, +r_hi: U32, +k: U32, +z: U32) -> Scaled:
  +t0 = (r_lo * k : U32)
  +t1 = (mul_hi(r_lo, k) + (r_hi * k : U32) : U32)
  +t2 = (mul_hi(r_hi, k) + Bool.to_u32((t1 < (r_hi * k : U32) : U32)) : U32)
  +bits = Bool.pick(U32, U32.is_zero(t2), Bool.pick(U32, U32.is_zero(t1), bit_length(t0), (32 + bit_length(t1) : U32)), (64 + bit_length(t2) : U32))
  rounded(t0, t1, t2, Bool.pick(U32, (bits > 53 : U32), (bits - 53 : U32), 0), z)

def mantissa_times(+x: U32, +k: U32) -> Scaled:
  +z = (31 - (bit_length(x) - 1 : U32) : U32)
  +y = lsl(x, z)
  +round_bit = ((y >> 10n) .&. 1 : U32)
  +r_lo = ((((y << 21n) .|. (y >> 11n)) : U32) + round_bit : U32)
  product(r_lo, ((y >> 11n) + Bool.to_u32((r_lo < round_bit : U32)) : U32), k, z)

# fl(fl(x / (2^32 - 1)) * k) as Scaled, for any k (the product is rounded like mulsd).
def scale(+x: U32, +k: U32) -> Scaled:
  Bool.pick(Scaled, U32.is_zero(x), Scaled{0, True{}}, Bool.pick(Scaled, U32.is_eq(x, 4294967295), Scaled{k, True{}}, mantissa_times(x, k)))

def floor_of(+s: Scaled) -> U32:
  match s:
    case Scaled{+f, _}:
      f

def upto_drawn(got: U32 & Pcg.Rng, +u: U32) -> U32 & Pcg.Rng:
  (x, s) = got
  ((floor_of(scale(x, u)) + 1 : U32), s)

# math.random(u) for u >= 1: 1 .. u (u + 1 when the draw is 2^32 - 1).
def random_upto(s: Pcg.Rng, +u: U32) -> U32 & Pcg.Rng:
  upto_drawn(Pcg.draw(s), u)

def range_drawn(got: U32 & Pcg.Rng, +m: U32, +n: U32) -> U32 & Pcg.Rng:
  (x, s) = got
  ((floor_of(scale(x, ((n - m : U32) + 1 : U32))) + m : U32), s)

# math.random(m, n) for m <= n as int32 (m may be negative in two's complement; n - m + 1 < 2^31).
def random_range(s: Pcg.Rng, +m: U32, +n: U32) -> U32 & Pcg.Rng:
  range_drawn(Pcg.draw(s), m, n)
