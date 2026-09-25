import Base
import ../f64/repr.bend as FR

# Natural numbers of any size as little-endian lists of 16-bit limbs (each in a U32), without high zero limbs, so
# zero is Nil. Every product of two limbs plus two carries fits in a U32.

def limb_mask() -> U32:
  65535

def trim_top(+low: U32, high: List<&2, U32>) -> List<&2, U32>:
  match high:
    case Nil{}:
      Bool.pick(List<&2, U32>, U32.is_zero(low), Nil{}, [low])
    case more:
      low <> more

def trimmed(limbs: List<&2, U32>) -> List<&2, U32>:
  match limbs:
    case Nil{}:
      Nil{}
    case Con{+low, rest}:
      trim_top(low, trimmed(rest))

# The number n.
def of_u32(+n: U32) -> List<&2, U32>:
  trimmed([(n .&. limb_mask() : U32), (n >> 16n : U32)])

def is_zero(a: List<&2, U32>) -> Bool:
  List.is_empty(&2, U32, a)

def add_carry(a: List<&2, U32>, b: List<&2, U32>, +carry: U32) -> List<&2, U32>:
  match a b:
    case Nil{} Nil{}:
      Bool.pick(List<&2, U32>, U32.is_zero(carry), Nil{}, [carry])
    case Con{+x, xs} Nil{}:
      +t = (x + carry : U32)
      (t .&. limb_mask() : U32) <> add_carry(xs, Nil{}, (t >> 16n : U32))
    case Nil{} Con{+y, ys}:
      +t = (y + carry : U32)
      (t .&. limb_mask() : U32) <> add_carry(Nil{}, ys, (t >> 16n : U32))
    case Con{+x, xs} Con{+y, ys}:
      +t = (x + y + carry : U32)
      (t .&. limb_mask() : U32) <> add_carry(xs, ys, (t >> 16n : U32))

# a + b.
def add(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  add_carry(a, b, 0)

def sub_borrow(a: List<&2, U32>, b: List<&2, U32>, +borrow: U32) -> List<&2, U32>:
  match a b:
    case Nil{} _:
      Nil{}
    case Con{+x, xs} Nil{}:
      +t = (x + 65536 - borrow : U32)
      (t .&. limb_mask() : U32) <> sub_borrow(xs, Nil{}, (1 - (t >> 16n) : U32))
    case Con{+x, xs} Con{+y, ys}:
      +t = (x + 65536 - y - borrow : U32)
      (t .&. limb_mask() : U32) <> sub_borrow(xs, ys, (1 - (t >> 16n) : U32))

# a - b for a >= b.
def sub(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  trimmed(sub_borrow(a, b, 0))

def cmp_limbs(a: List<&2, U32>, b: List<&2, U32>, +below: U32) -> U32:
  match a b:
    case Nil{} Nil{}:
      below
    case Nil{} _:
      0
    case _ Nil{}:
      2
    case Con{+x, xs} Con{+y, ys}:
      cmp_limbs(xs, ys, Bool.pick(U32, (x < y : U32), 0, Bool.pick(U32, (x > y : U32), 2, below)))

# 0 when a < b, 1 when a = b, 2 when a > b.
def compare(a: List<&2, U32>, b: List<&2, U32>) -> U32:
  cmp_limbs(a, b, 1)

def is_ge(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  (compare(a, b) >= 1 : U32)

def mul_small_carry(a: List<&2, U32>, +m: U32, +carry: U32) -> List<&2, U32>:
  match a:
    case Nil{}:
      Bool.pick(List<&2, U32>, U32.is_zero(carry), Nil{}, [carry])
    case Con{+x, xs}:
      +t = (x * m + carry : U32)
      (t .&. limb_mask() : U32) <> mul_small_carry(xs, m, (t >> 16n : U32))

# a * m for m < 65536.
def mul_small(a: List<&2, U32>, +m: U32) -> List<&2, U32>:
  trimmed(mul_small_carry(a, m, 0))

def shifted_limb(a: List<&2, U32>) -> List<&2, U32>:
  match a:
    case Nil{}:
      Nil{}
    case more:
      0 <> more

def mul_rows(a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  match a:
    case Nil{}:
      Nil{}
    case Con{+x, xs}:
      add(mul_small(b, x), shifted_limb(mul_rows(xs, b)))

# a * b.
def mul(a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  mul_rows(a, b)

def shl_bits(a: List<&2, U32>, +k: Nat, +carry: U32) -> List<&2, U32>:
  match a:
    case Nil{}:
      Bool.pick(List<&2, U32>, U32.is_zero(carry), Nil{}, [carry])
    case Con{+x, xs}:
      +t = ((x << k) .|. carry : U32)
      (t .&. limb_mask() : U32) <> shl_bits(xs, k, (t >> 16n : U32))

def shl_limbs(n: Nat, a: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      shl_limbs(p, shifted_limb(a))

# a * 2^n.
def shl(a: List<&2, U32>, +n: Nat) -> List<&2, U32>:
  trimmed(shl_limbs(Nat.div(n, 16n), shl_bits(a, Nat.mod(n, 16n), 0)))

def top_bits(+x: U32) -> Nat:
  Bool.pick(Nat, U32.is_zero(x), 0n, Nat.add(U32.log2(x), 1n))

def bits_of(a: List<&2, U32>, +count: Nat) -> Nat:
  match a:
    case Nil{}:
      0n
    case Con{+x, Nil{}}:
      Nat.add(count, top_bits(x))
    case Con{_, xs}:
      bits_of(xs, Nat.add(count, 16n))

# The number of bits of a (0 for zero).
def bit_length(a: List<&2, U32>) -> Nat:
  bits_of(a, 0n)

def low_word_of(a: List<&2, U32>) -> U32:
  match a:
    case Nil{}:
      0
    case Con{+x, Nil{}}:
      x
    case Con{+x, Con{+y, _}}:
      (x .|. (y << 16n) : U32)

def drop_two(a: List<&2, U32>) -> List<&2, U32>:
  List.drop(&2, U32, a, 2n)

# The low 32 bits of a.
def low_word(a: List<&2, U32>) -> U32:
  low_word_of(a)

# The bits 32..63 of a.
def high_word(+a: List<&2, U32>) -> U32:
  low_word_of(drop_two(a))

def bit_at(a: List<&2, U32>, +k: Nat) -> U32:
  +limb = Maybe.default(&2, U32, List.get(&2, U32, a, Nat.div(k, 16n)), 0)
  ((limb >> Nat.mod(k, 16n)) .&. 1 : U32)

def with_bit(+r: List<&2, U32>, +bit: U32) -> List<&2, U32>:
  add(shl(r, 1n), of_u32(bit))

type Division is Data:
  Division{quotient: List<&2, U32>, remainder: List<&2, U32>}

def division_step(+d: List<&2, U32>, q: List<&2, U32>, +r: List<&2, U32>) -> Division:
  +fits = is_ge(r, d)
  Division{with_bit(q, Bool.to_u32(fits)), Bool.pick(List<&2, U32>, fits, sub(r, d), r)}

def divide_loop(n: Nat, +a: List<&2, U32>, +d: List<&2, U32>, state: Division) -> Division:
  match n state:
    case 0n _:
      state
    case 1n+(+p) Division{q, +r}:
      divide_loop(p, a, d, division_step(d, q, with_bit(r, bit_at(a, p))))

# floor(a / d) and a mod d for d > 0, one bit per step.
def divide(+a: List<&2, U32>, +d: List<&2, U32>) -> Division:
  divide_loop(bit_length(a), a, d, Division{Nil{}, Nil{}})

def ten_power(n: Nat, a: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      ten_power(p, mul_small(a, 10))

# 10^n.
def pow10(+n: Nat) -> List<&2, U32>:
  ten_power(n, [1])

# a * 10^n.
def times_pow10(a: List<&2, U32>, +n: Nat) -> List<&2, U32>:
  ten_power(n, a)

def shr_bits(a: List<&2, U32>, +k: Nat) -> List<&2, U32>:
  match a:
    case Nil{}:
      Nil{}
    case Con{+x, Nil{}}:
      [(x >> k : U32)]
    case Con{+x, Con{+y, rest}}:
      (((x >> k) .|. (y << Nat.sub(16n, k))) .&. limb_mask() : U32) <> shr_bits(Con{y, rest}, k)

# floor(a / 2^n).
def shr(a: List<&2, U32>, +n: Nat) -> List<&2, U32>:
  trimmed(shr_bits(List.drop(&2, U32, a, Nat.div(n, 16n)), Nat.mod(n, 16n)))

# a mod 2^n.
def low_bits(+a: List<&2, U32>, +n: Nat) -> List<&2, U32>:
  sub(a, shl(shr(a, n), n))

# The bit k of a (0 or 1).
def bit(+a: List<&2, U32>, +k: Nat) -> U32:
  bit_at(a, k)

# The 32-bit word k of a (bits 32k..32k+31).
def word(+a: List<&2, U32>, +k: Nat) -> U32:
  low_word_of(List.drop(&2, U32, a, Nat.mul(k, 2n)))

def double_mantissa(+ah: U32, +al: U32) -> List<&2, U32>:
  +e = ((ah >> 20n) .&. 2047 : U32)
  +fh = ((ah .&. 1048575) .|. Bool.pick(U32, U32.is_zero(e), 0, 1048576) : U32)
  add(of_u32(al), shl(of_u32(fh), 32n))

def double_exponent(+ah: U32) -> U32:
  +e = ((ah >> 20n) .&. 2047 : U32)
  Bool.pick(U32, U32.is_zero(e), 1, e)

# The exact value of |d| times 2^1074 for a finite double d, a natural number.
def of_double(d: FR.F64) -> List<&2, U32>:
  match d:
    case FR.F64{+ah, +al}:
      shl(double_mantissa(ah, al), U32.to_nat((double_exponent(ah) - 1 : U32)))
