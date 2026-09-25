import Base
import ./bignum.bend as BN
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC

# The double nearest to a JSON number (round half to even, like Python's float()), for numbers whose text passed the
# JSON grammar. `finite` is False when the value rounds past the largest double.
type Parsed is Data:
  Parsed{finite: Bool, value: FR.F64}

type Digits is Data:
  Digits{negative: Bool, mantissa: List<&2, U32>, fraction: Nat, exponent_negative: Bool, exponent: Nat, count: Nat}

def exponent_cap() -> Nat:
  100000n

def digit_of(+code: U32) -> U32:
  (code - 48 : U32)

def exponent_digits(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+code}, rest}:
      exponent_digits(rest, Nat.min(Nat.add(Nat.mul(acc, 10n), U32.to_nat(digit_of(code))), exponent_cap()))

def with_exponent(d: Digits, +negative: Bool, +exponent: Nat) -> Digits:
  match d:
    case Digits{+sign, +mantissa, +fraction, _, _, +count}:
      Digits{sign, mantissa, fraction, negative, exponent, count}

def exponent_part(d: Digits, s: String) -> Digits:
  match s:
    case SCon{Chr{45}, rest}:
      with_exponent(d, True{}, exponent_digits(rest, 0n))
    case SCon{Chr{43}, rest}:
      with_exponent(d, False{}, exponent_digits(rest, 0n))
    case rest:
      with_exponent(d, False{}, exponent_digits(rest, 0n))

def with_digit(d: Digits, +code: U32, +in_fraction: Bool) -> Digits:
  match d:
    case Digits{+sign, +mantissa, +fraction, +en, +exponent, +count}:
      +significant = Bool.not(BN.is_zero(mantissa)) || Bool.not(U32.is_eq(code, 48))
      Digits{sign, BN.add(BN.mul_small(mantissa, 10), BN.of_u32(digit_of(code))),
        Bool.pick(Nat, in_fraction, Nat.add(fraction, 1n), fraction), en, exponent,
        Bool.pick(Nat, significant, Nat.add(count, 1n), count)}

def negated(d: Digits) -> Digits:
  match d:
    case Digits{_, +mantissa, +fraction, +en, +exponent, +count}:
      Digits{True{}, mantissa, fraction, en, exponent, count}

def scan_digits(s: String, d: Digits, +in_fraction: Bool) -> Digits:
  match s:
    case SNil{}:
      d
    case SCon{Chr{45}, rest}:
      scan_digits(rest, negated(d), in_fraction)
    case SCon{Chr{46}, rest}:
      scan_digits(rest, d, True{})
    case SCon{Chr{101}, rest}:
      exponent_part(d, rest)
    case SCon{Chr{69}, rest}:
      exponent_part(d, rest)
    case SCon{Chr{+code}, rest}:
      scan_digits(rest, with_digit(d, code, in_fraction), in_fraction)

def signed(+negative: Bool, a: FR.F64) -> FR.F64:
  match a:
    case FR.F64{+h, +l}:
      FR.F64{(h .|. Bool.pick(U32, negative, 2147483648, 0) : U32), l}

def infinite(+negative: Bool) -> Parsed:
  Parsed{False{}, signed(negative, FR.F64{2146435072, 0})}

def zero_of(+negative: Bool) -> Parsed:
  Parsed{True{}, signed(negative, FR.zero())}

def offset() -> Nat:
  2000n

def bits_of_kept(+kept: List<&2, U32>, +biased: U32, +normal: Bool) -> FR.F64:
  +high = BN.word(kept, 1n)
  +low = BN.word(kept, 0n)
  Bool.pick(FR.F64, normal, FR.F64{(((biased - 1) << 20n) + high : U32), low}, FR.F64{high, low})

def is_half_up(+rest: List<&2, U32>, +drop: Nat, +sticky: Bool, +odd: U32) -> Bool:
  +half = BN.shl([1], Nat.sub(drop, 1n))
  +c = BN.compare(rest, half)
  Bool.not(Nat.is_eq(drop, 0n)) && (U32.is_eq(c, 2) || (U32.is_eq(c, 1) && (sticky || U32.is_eq(odd, 1))))

def rounded_kept(+q: List<&2, U32>, +drop: Nat, +sticky: Bool) -> List<&2, U32>:
  +kept = BN.shr(q, drop)
  +up = is_half_up(BN.low_bits(q, drop), drop, sticky, BN.bit(kept, 0n))
  Bool.pick(List<&2, U32>, up, BN.add(kept, [1]), kept)

def pack(+negative: Bool, +kept: List<&2, U32>, +biased: U32, +normal: Bool) -> Parsed:
  +carried = normal && Nat.is_eq(BN.bit_length(kept), 54n)
  +exponent = (biased + Bool.to_u32(carried) : U32)
  +value = bits_of_kept(Bool.pick(List<&2, U32>, carried, BN.shr(kept, 1n), kept), exponent, normal)
  Bool.pick(Parsed, normal && (exponent >= 2047 : U32), infinite(negative), Parsed{True{}, signed(negative, value)})

# The double of q * 2^(position - offset - (bits(q) - 1)): `position` is the exponent of q's top bit plus offset().
def from_quotient(+negative: Bool, +q: List<&2, U32>, +sticky: Bool, +position: Nat) -> Parsed:
  +t = BN.bit_length(q)
  +normal = Nat.is_ge(position, Nat.sub(offset(), 1022n))
  +drop = Bool.pick(Nat, normal, Nat.sub(t, 53n), Nat.sub(Nat.add(t, offset()), Nat.add(1075n, position)))
  +biased = U32.from_nat(Nat.sub(Nat.add(position, 1023n), offset()))
  pack(negative, rounded_kept(q, drop, sticky), biased, normal)

def from_division(+negative: Bool, division: BN.Division, +up: Nat, +down: Nat) -> Parsed:
  match division:
    case BN.Division{+q, +r}:
      +t = BN.bit_length(q)
      from_quotient(negative, q, Bool.not(BN.is_zero(r)), Nat.sub(Nat.add(Nat.add(t, offset()), down), Nat.add(up, 1n)))

def ratio(+negative: Bool, +num: List<&2, U32>, +den: List<&2, U32>, +up: Nat, +down: Nat) -> Parsed:
  from_division(negative, BN.divide(BN.shl(num, up), BN.shl(den, down)), up, down)

# The double nearest to num / den (num, den > 0), from a quotient of 55 or 56 bits and a sticky remainder.
def nearest(+negative: Bool, +num: List<&2, U32>, +den: List<&2, U32>) -> Parsed:
  +a = BN.bit_length(num)
  +b = BN.bit_length(den)
  ratio(negative, num, den, Nat.sub(Nat.add(b, 55n), a), Nat.sub(a, Nat.add(b, 55n)))

def by_size(+size: U32, +negative: Bool, +mantissa: List<&2, U32>, +up: Nat, +down: Nat) -> Parsed:
  match size:
    case 0:
      zero_of(negative)
    case 1:
      infinite(negative)
    case _:
      nearest(negative, BN.times_pow10(mantissa, Nat.sub(up, Nat.min(up, down))), BN.pow10(Nat.sub(down, Nat.min(up, down))))

def size_class(+zero: Bool, +magnitude_up: Nat, +down: Nat) -> U32:
  Bool.pick(U32, zero || Nat.is_gt(Nat.sub(down, magnitude_up), 400n), 0,
    Bool.pick(U32, Nat.is_gt(Nat.sub(magnitude_up, down), 330n), 1, 2))

def scaled_value(d: Digits) -> Parsed:
  match d:
    case Digits{+negative, +mantissa, +fraction, +en, +exponent, +count}:
      +up = Bool.pick(Nat, en, 0n, exponent)
      +down = Nat.add(fraction, Bool.pick(Nat, en, exponent, 0n))
      by_size(size_class(BN.is_zero(mantissa), Nat.add(count, up), down), negative, mantissa, up, down)

# The double of a JSON number text (already checked against the JSON grammar).
def parse(+text: String) -> Parsed:
  scaled_value(scan_digits(text, Digits{False{}, Nil{}, 0n, False{}, 0n, 0n}, False{}))
