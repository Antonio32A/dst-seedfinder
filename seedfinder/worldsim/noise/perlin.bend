import Base
import ../../f64/repr.bend as F64Repr
import ../../f64/arith.bend as F64Arith
import ../../f64/word.bend as F64Word
import ../../data/constants.bend as Constants

# ImprovedNoise (Ken Perlin's 2002 noise, as in the game binary and worldsim/src/tiles.cpp) in exact soft doubles,
# with the operation order of the binary. The permutation lives in a 256-slot array (indexes wrap, so p[i + 256] is
# p[i]); callers thread it through.

def fill_perm(units: List<&2, U32>, perm: Array<U32>, +i: U32) -> Array<U32>:
  match units:
    case Nil{}:
      perm
    case Con{+u, rest}:
      perm[i] <- (u .&. 255 : U32)
      perm[(i + 1 : U32)] <- (u >> 8n : U32)
      fill_perm(rest, perm, (i + 2 : U32))

# The permutation table p[0..255].
def permutation() -> Array<U32>:
  fill_perm(List.drop(&2, U32, Constants.perlin(0), 0n), [0 : U32^8n], 0)

def gather_loop(idx: List<&2, U32>, got: Array<U32> & U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match idx:
    case Nil{}:
      (perm, +v) = got
      (perm, List.reverse(&2, U32, v <> acc))
    case Con{+i, rest}:
      (perm, +v) = got
      gather_loop(rest, perm[i], v <> acc)

# p[i] for each index, in order (at least one index).
def gather(perm: Array<U32>, +first: U32, idx: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  gather_loop(idx, perm[first], Nil{})

def f64_of(+hi: U32) -> F64Repr.F64:
  F64Repr.F64{hi, 0}

def fade(+t: F64Repr.F64) -> F64Repr.F64:
  F64Arith.mul(F64Arith.mul(F64Arith.mul(t, t), t), F64Arith.add(F64Arith.mul(F64Arith.sub(F64Arith.mul(t, f64_of(1075314688)), f64_of(1076756480)), t), f64_of(1076101120)))

def grad(+h: U32, +x: F64Repr.F64, +y: F64Repr.F64, +z: F64Repr.F64) -> F64Repr.F64:
  +k = (h .&. 15 : U32)
  +u = Bool.pick(F64Repr.F64, (k > 7 : U32), y, x)
  +v = Bool.pick(F64Repr.F64, (k > 3 : U32), Bool.pick(F64Repr.F64, U32.is_eq((h .&. 13 : U32), 12), x, z), y)
  F64Arith.add(Bool.pick(F64Repr.F64, U32.is_ne((h .&. 1 : U32), 0), F64Repr.neg(u), u), Bool.pick(F64Repr.F64, U32.is_ne((h .&. 2 : U32), 0), F64Repr.neg(v), v))

def lerp(+t: F64Repr.F64, +a: F64Repr.F64, +b: F64Repr.F64) -> F64Repr.F64:
  F64Arith.add(F64Arith.mul(F64Arith.sub(b, a), t), a)

type Frac is Data:
  Frac{x: F64Repr.F64, y: F64Repr.F64, z: F64Repr.F64}

def blend(hashes: List<&2, U32>, +f: Frac) -> F64Repr.F64:
  match hashes:
    case Con{+aa, Con{+ba, Con{+ab, Con{+bb, Con{+aa1, Con{+ba1, Con{+ab1, Con{+bb1, _}}}}}}}}:
      match f:
        case Frac{+x, +y, +z}:
          +u = fade(x)
          +v = fade(y)
          +x1 = F64Arith.sub(x, F64Repr.one())
          +y1 = F64Arith.sub(y, F64Repr.one())
          +z1 = F64Arith.sub(z, F64Repr.one())
          +l1 = lerp(u, grad(aa1, x, y, z1), grad(ba1, x1, y, z1))
          +l0 = lerp(u, grad(aa, x, y, z), grad(ba, x1, y, z))
          +m0 = lerp(v, l0, lerp(u, grad(ab, x, y1, z), grad(bb, x1, y1, z)))
          +m1 = lerp(v, l1, lerp(u, grad(ab1, x, y1, z1), grad(bb1, x1, y1, z1)))
          +zf = F64Arith.add(F64Arith.mul(F64Arith.sub(F64Arith.mul(z, f64_of(1075314688)), f64_of(1076756480)), z), f64_of(1076101120))
          F64Arith.mul(F64Arith.add(F64Arith.add(F64Arith.mul(F64Arith.mul(F64Arith.mul(F64Arith.mul(F64Arith.sub(m1, m0), z), z), z), zf), m0), F64Repr.one()), F64Repr.half())
    case _:
      F64Repr.zero()

def corners_got(got: Array<U32> & List<&2, U32>, +f: Frac) -> Array<U32> & F64Repr.F64:
  (perm, +hashes) = got
  (perm, blend(hashes, f))

def rows_got(got: Array<U32> & List<&2, U32>, +zi: U32, +f: Frac) -> Array<U32> & F64Repr.F64:
  (perm, +rows) = got
  match rows:
    case Con{+pa, Con{+pa1, Con{+pb, Con{+pb1, _}}}}:
      +aa = (pa + zi : U32)
      +ab = (pa1 + zi : U32)
      +ba = (pb + zi : U32)
      +bb = (pb1 + zi : U32)
      corners_got(gather(perm, aa, [ba, ab, bb, (aa + 1 : U32), (ba + 1 : U32), (ab + 1 : U32), (bb + 1 : U32)]), f)
    case _:
      (perm, F64Repr.zero())

def columns_got(got: Array<U32> & List<&2, U32>, +yi: U32, +zi: U32, +f: Frac) -> Array<U32> & F64Repr.F64:
  (perm, +cols) = got
  match cols:
    case Con{+px, Con{+px1, _}}:
      +a = (px + yi : U32)
      +b = (px1 + yi : U32)
      rows_got(gather(perm, a, [(a + 1 : U32), b, (b + 1 : U32)]), zi, f)
    case _:
      (perm, F64Repr.zero())

def cell_of(+v: F64Repr.F64) -> U32:
  (F64Repr.to_i32(F64Repr.floor(v)) .&. 255 : U32)

def fraction(+v: F64Repr.F64) -> F64Repr.F64:
  F64Arith.sub(v, F64Repr.floor(v))

# ImprovedNoise(x, y, z), in [0, 1]: ((noise + 1) * 0.5).
def noise(perm: Array<U32>, +x: F64Repr.F64, +y: F64Repr.F64, +z: F64Repr.F64) -> Array<U32> & F64Repr.F64:
  +xi = cell_of(x)
  columns_got(gather(perm, xi, [(xi + 1 : U32)]), cell_of(y), cell_of(z), Frac{fraction(x), fraction(y), fraction(z)})

def fade_eighths(+j: U32) -> U32:
  match j:
    case 0:
      0
    case 1:
      263
    case 2:
      1696
    case 3:
      4509
    case 4:
      8192
    case 5:
      11875
    case 6:
      14688
    case _:
      16121

def grad_eighths(+h: U32, +x: U32, +y: U32) -> U32:
  +k = (h .&. 15 : U32)
  +u = Bool.pick(U32, (k > 7 : U32), y, x)
  +v = Bool.pick(U32, (k > 3 : U32), Bool.pick(U32, U32.is_eq((h .&. 13 : U32), 12), x, 0), y)
  (Bool.pick(U32, U32.is_ne((h .&. 1 : U32), 0), (0 - u : U32), u) + Bool.pick(U32, U32.is_ne((h .&. 2 : U32), 0), (0 - v : U32), v) : U32)

def lerp_eighths(+t: U32, +a: U32, +b: U32) -> U32:
  ((a * (16384 - t : U32)) + (b * t) : U32)

def unit_of(+n: U32) -> F64Repr.F64:
  +lz = F64Word.clz32(n)
  +m = F64Word.shl(n, lz)
  F64Repr.pick(U32.is_zero(n), F64Repr.one(), F64Repr.F64{(((1022 - lz : U32) << 20n) .|. ((m >> 11n) .&. F64Repr.frac_mask()) : U32), (m << 21n : U32)})

def eighths_got(got: Array<U32> & List<&2, U32>, +fx: U32, +fy: U32) -> Array<U32> & F64Repr.F64:
  (perm, +hashes) = got
  match hashes:
    case Con{+aa, Con{+ba, Con{+ab, Con{+bb, _}}}}:
      +u = fade_eighths(fx)
      +x1 = (fx - 8 : U32)
      +y1 = (fy - 8 : U32)
      +l0 = lerp_eighths(u, grad_eighths(aa, fx, fy), grad_eighths(ba, x1, fy))
      +l1 = lerp_eighths(u, grad_eighths(ab, fx, y1), grad_eighths(bb, x1, y1))
      (perm, unit_of((lerp_eighths(fade_eighths(fy), l0, l1) + 2147483648 : U32)))
    case _:
      (perm, F64Repr.zero())

def eighths_rows(got: Array<U32> & List<&2, U32>, +fx: U32, +fy: U32) -> Array<U32> & F64Repr.F64:
  (perm, +rows) = got
  match rows:
    case Con{+aa, Con{+ab, Con{+ba, Con{+bb, _}}}}:
      eighths_got(gather(perm, aa, [ba, ab, bb]), fx, fy)
    case _:
      (perm, F64Repr.zero())

def eighths_columns(got: Array<U32> & List<&2, U32>, +yi: U32, +fx: U32, +fy: U32) -> Array<U32> & F64Repr.F64:
  (perm, +cols) = got
  match cols:
    case Con{+px, Con{+px1, _}}:
      +a = (px + yi : U32)
      +b = (px1 + yi : U32)
      eighths_rows(gather(perm, a, [(a + 1 : U32), b, (b + 1 : U32)]), fx, fy)
    case _:
      (perm, F64Repr.zero())

# ImprovedNoise(x / 8, y / 8, 0) for integers x, y < 2^24, bit-identical to `noise`: on these inputs every double
# operation of `noise` is exact, so the value is N / 2^32, with N from wrapping U32 arithmetic on grads in eighths and
# fades in units of 2^-14. The noise is never below 1/16 here, so N = 0 is the wrapped 2^32 (1.0). Checked over the
# whole input period.
def noise_eighths(perm: Array<U32>, +x: U32, +y: U32) -> Array<U32> & F64Repr.F64:
  +xi = ((x >> 3n) .&. 255 : U32)
  eighths_columns(gather(perm, xi, [(xi + 1 : U32)]), ((y >> 3n) .&. 255 : U32), (x .&. 7 : U32), (y .&. 7 : U32))

def value_of(got: Array<U32> & F64Repr.F64) -> F64Repr.F64:
  (_, +v) = got
  v

# noise_eighths on a fresh permutation (one-off values, laws).
def eighths_value(+x: U32, +y: U32) -> F64Repr.F64:
  value_of(noise_eighths(permutation(), x, y))
