import Base
import ./bignum.bend as BigNum
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp

# An exact walk length q + 4*sqrt(2)*b (docs/config.md section 5): q = the offsets plus 4 per orthogonal step, as a
# 96-bit fixed-point number with 64 fraction bits (q2 the integer part, q1 q0 the fraction words), which holds every
# offset double >= 2^-11 exactly; b the number of diagonal steps.
type Length is Data:
  Length{q2: U32, q1: U32, q0: U32, b: U32}

# A bound (distance, within, max) as a length: its double truncated to 64 fraction bits, and whether bits were lost.
type Bound is Data:
  Bound{length: Length, inexact: Bool}

def zero() -> Length:
  Length{0, 0, 0, 0}

def carry(+sum: U32, +a: U32) -> U32:
  Bool.to_u32((sum < a : U32))

# a + b.
def plus(a: Length, b: Length) -> Length:
  match a b:
    case Length{+a2, +a1, +a0, +ab} Length{+b2, +b1, +b0, +bb}:
      +s0 = (a0 + b0 : U32)
      +c0 = carry(s0, a0)
      +t1 = (a1 + b1 : U32)
      +s1 = (t1 + c0 : U32)
      +c1 = (carry(t1, a1) + carry(s1, t1) : U32)
      Length{(a2 + b2 + c1 : U32), s1, s0, (ab + bb : U32)}

# a plus `orthogonal` steps of 4 and `diagonal` steps of 4*sqrt(2).
def stepped(a: Length, +orthogonal: U32, +diagonal: U32) -> Length:
  match a:
    case Length{+q2, +q1, +q0, +b}:
      Length{(q2 + orthogonal * 4 : U32), q1, q0, (b + diagonal : U32)}

def mul_hi(+a: U32, +b: U32) -> U32:
  +al = (a .&. 65535 : U32)
  +ah = (a >> 16n : U32)
  +bl = (b .&. 65535 : U32)
  +bh = (b >> 16n : U32)
  +lh = (al * bh : U32)
  +hl = (ah * bl : U32)
  +mid = (((al * bl) >> 16n) + (lh .&. 65535) + (hl .&. 65535) : U32)
  (ah * bh + (lh >> 16n) + (hl >> 16n) + (mid >> 16n) : U32)

def root2_hi() -> U32:
  2821167519

def root2_lo() -> U32:
  3472040994

type Approx is Data:
  Approx{hi: U32, lo: U32}

# floor(length * 2^32) minus less than 4: the heap key, exact enough that keys 4 apart order their lengths.
def key(l: Length) -> Approx:
  match l:
    case Length{+q2, +q1, _, +b}:
      +l1 = (b * root2_hi() : U32)
      +h1 = mul_hi(b, root2_hi())
      +h2 = mul_hi(b, root2_lo())
      +frac = (l1 + h2 : U32)
      +whole = (q2 + b * 5 + h1 + carry(frac, l1) : U32)
      +lo = (q1 + frac : U32)
      Approx{(whole + carry(lo, q1) : U32), lo}

def key_less(+a: Approx, +b: Approx) -> Bool:
  match a b:
    case Approx{+ah, +al} Approx{+bh, +bl}:
      (ah < bh : U32) || (U32.is_eq(ah, bh) && (al < bl : U32))

def key_plus(+k: Approx, +units: U32) -> Approx:
  match k:
    case Approx{+hi, +lo}:
      +sum = (lo + units : U32)
      Approx{(hi + carry(sum, lo) : U32), sum}

def words_compare(+a2: U32, +a1: U32, +a0: U32, +b2: U32, +b1: U32, +b0: U32) -> U32:
  Bool.pick(U32, (a2 < b2 : U32), 0, Bool.pick(U32, (a2 > b2 : U32), 2,
    Bool.pick(U32, (a1 < b1 : U32), 0, Bool.pick(U32, (a1 > b1 : U32), 2,
      Bool.pick(U32, (a0 < b0 : U32), 0, Bool.pick(U32, (a0 > b0 : U32), 2, 1))))))

def big_of(+q2: U32, +q1: U32, +q0: U32) -> List<&2, U32>:
  BigNum.add(BigNum.of_u32(q0), BigNum.add(BigNum.shl(BigNum.of_u32(q1), 32n), BigNum.shl(BigNum.of_u32(q2), 64n)))

def rational_wins(+difference: List<&2, U32>, +c: U32) -> Bool:
  +square = BigNum.mul(difference, difference)
  +c2 = BigNum.shl(BigNum.mul_small(BigNum.mul(BigNum.of_u32(c), BigNum.of_u32(c)), 32), 128n)
  U32.is_eq(BigNum.compare(square, c2), 2)

def mixed_sign(+q_order: U32, +difference: List<&2, U32>, +b_order: U32, +c: U32) -> U32:
  Bool.pick(U32, U32.is_eq(q_order, 1) || U32.is_eq(q_order, b_order), b_order,
    Bool.pick(U32, rational_wins(difference, c), q_order, b_order))

def exact_compare(a: Length, b: Length) -> U32:
  match a b:
    case Length{+a2, +a1, +a0, +ab} Length{+b2, +b1, +b0, +bb}:
      +q_order = words_compare(a2, a1, a0, b2, b1, b0)
      +big_a = big_of(a2, a1, a0)
      +big_b = big_of(b2, b1, b0)
      +difference = Bool.pick(List<&2, U32>, U32.is_eq(q_order, 2), BigNum.sub(big_a, big_b), BigNum.sub(big_b, big_a))
      +b_order = Bool.pick(U32, (ab < bb : U32), 0, Bool.pick(U32, (ab > bb : U32), 2, 1))
      +c = Bool.pick(U32, (ab < bb : U32), (bb - ab : U32), (ab - bb : U32))
      Bool.pick(U32, U32.is_eq(b_order, 1), q_order, mixed_sign(q_order, difference, b_order, c))

# 0 when the keys order a before b, 2 when after, 1 when they are too close to tell.
def keys_decide(+ka: Approx, +kb: Approx) -> U32:
  Bool.pick(U32, key_less(key_plus(ka, 4), kb), 0, Bool.pick(U32, key_less(key_plus(kb, 4), ka), 2, 1))

def near_compare(+decided: U32, a: Length, b: Length) -> U32:
  match decided:
    case 0:
      0
    case 2:
      2
    case _:
      exact_compare(a, b)

def same_diagonals(+a: Length, +b: Length) -> Bool:
  match a b:
    case Length{_, _, _, +ab} Length{_, _, _, +bb}:
      U32.is_eq(ab, bb)

def rational_compare(a: Length, b: Length) -> U32:
  match a b:
    case Length{+a2, +a1, +a0, _} Length{+b2, +b1, +b0, _}:
      words_compare(a2, a1, a0, b2, b1, b0)

def compare_by(same: Bool, a: Length, b: Length, +ka: Approx, +kb: Approx) -> U32:
  match same:
    case True{}:
      rational_compare(a, b)
    case False{}:
      near_compare(keys_decide(ka, kb), a, b)

# 0 when a < b, 1 when a = b, 2 when a > b, exactly, given the keys of a and b.
def compare_keyed(+a: Length, +b: Length, +ka: Approx, +kb: Approx) -> U32:
  compare_by(same_diagonals(a, b), a, b, ka, kb)

def compare_unkeyed(same: Bool, a: Length, b: Length) -> U32:
  match same:
    case True{}:
      rational_compare(a, b)
    case False{}:
      +x = a
      +y = b
      near_compare(keys_decide(key(x), key(y)), x, y)

# 0 when a < b, 1 when a = b, 2 when a > b, exactly.
def compare(+a: Length, +b: Length) -> U32:
  compare_unkeyed(same_diagonals(a, b), a, b)

def is_lt(+a: Length, +b: Length) -> Bool:
  U32.is_zero(compare(a, b))

def length_of_scaled(+scaled: List<&2, U32>) -> Length:
  +fixed = BigNum.shr(scaled, 1010n)
  Length{BigNum.word(fixed, 2n), BigNum.word(fixed, 1n), BigNum.word(fixed, 0n), 0}

# The length of an offset double (>= 0): exact for doubles >= 2^-11, truncated below.
def of_double(+d: F64Repr.F64) -> Length:
  length_of_scaled(BigNum.of_double(d))

# A double bound as a length plus the flag for lost bits.
def bound_of(+d: F64Repr.F64) -> Bound:
  +scaled = BigNum.of_double(d)
  Bound{length_of_scaled(scaled), Bool.not(BigNum.is_zero(BigNum.low_bits(scaled, 1010n)))}

# length <= bound, exactly (a length is 0 or at least 2^-11, so lost bits of a tiny bound never matter).
def within_max(+l: Length, b: Bound) -> Bool:
  match b:
    case Bound{+bound, _}:
      Bool.not(U32.is_eq(compare(l, bound), 2))

# length >= bound, exactly.
def within_min(+l: Length, b: Bound) -> Bool:
  match b:
    case Bound{+bound, +inexact}:
      +order = compare(l, bound)
      Bool.pick(Bool, inexact, U32.is_eq(order, 2), Bool.not(U32.is_zero(order)))

def thousand_root2() -> List<&2, U32>:
  [10257, 37647, 10220, 26053, 6208, 55984, 5656]

def rounded_of(+scaled: List<&2, U32>, +exact: Bool) -> Nat:
  +whole = BigNum.shr(scaled, 96n)
  +rest = BigNum.low_bits(scaled, 96n)
  +half = BigNum.shl([1], 95n)
  +order = BigNum.compare(rest, half)
  +up = U32.is_eq(order, 2) || (U32.is_eq(order, 1) && (Bool.not(exact) || U32.is_eq(BigNum.bit(whole, 0n), 1)))
  +n = BigNum.add(whole, Bool.pick(List<&2, U32>, up, [1], Nil{}))
  Nat.add(U32.to_nat(BigNum.word(n, 0n)), Nat.mul(U32.to_nat(BigNum.word(n, 1n)), Nat.mul(65536n, 65536n)))

# round(length * 1000), half to even (only a length without diagonals can be a tie).
def thousandths(l: Length) -> Nat:
  match l:
    case Length{+q2, +q1, +q0, +b}:
      +rational = BigNum.shl(BigNum.mul_small(big_of(q2, q1, q0), 1000), 32n)
      rounded_of(BigNum.add(rational, BigNum.mul(BigNum.of_u32(b), thousand_root2())), U32.is_zero(b))
