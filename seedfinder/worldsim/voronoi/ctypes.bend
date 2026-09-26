import Base
import ../../f64/word.bend as F64Word
import ../../f64/repr.bend as F64Repr
import ../../f64/arith.bend as F64Arith
import ../../f64/cmp.bend as F64Cmp

# Boost.Polygon 1.52 voronoi_ctypes.hpp for the int32 instantiation: int64 on (hi, lo) words (int_x2_type),
# extended_int<64> (`Big`, Boost's own chunk algorithms, including their non-normalised results), and
# extended_exponent_fpt<double> (`Efpt`). Signed 32-bit values are two's complement U32.

def is_neg32(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

def abs32(+x: U32) -> U32:
  F64Word.pick(is_neg32(x), (0 - x : U32), x)

# a < b as int32.
def lt_i32(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648 : U32) < (b .^. 2147483648 : U32) : U32)

# static_cast<int64>(x) of an int32.
def widen(+x: U32) -> F64Word.W64:
  F64Word.W64{F64Word.pick(is_neg32(x), 4294967295, 0), x}

def add64(a: F64Word.W64, b: F64Word.W64) -> F64Word.W64:
  match a:
    case F64Word.W64{+ah, +al}:
      match b:
        case F64Word.W64{+bh, +bl}:
          F64Word.W64{F64Word.add_hi(ah, al, bh, bl), (al + bl : U32)}

def sub64(a: F64Word.W64, b: F64Word.W64) -> F64Word.W64:
  match a:
    case F64Word.W64{+ah, +al}:
      match b:
        case F64Word.W64{+bh, +bl}:
          F64Word.W64{F64Word.sub_hi(ah, al, bh, bl), (al - bl : U32)}

def neg64(a: F64Word.W64) -> F64Word.W64:
  sub64(F64Word.W64{0, 0}, a)

# static_cast<int64>(a) - static_cast<int64>(b) of two int32.
def dif32(+a: U32, +b: U32) -> F64Word.W64:
  sub64(widen(a), widen(b))

def is_neg64(a: F64Word.W64) -> Bool:
  match a:
    case F64Word.W64{+h, _}:
      is_neg32(h)

def is_zero64(a: F64Word.W64) -> Bool:
  match a:
    case F64Word.W64{+h, +l}:
      U32.is_zero((h .|. l : U32))

def pick64(c: Bool, a: F64Word.W64, b: F64Word.W64) -> F64Word.W64:
  match c:
    case True{}:
      a
    case False{}:
      b

def abs64(+a: F64Word.W64) -> F64Word.W64:
  pick64(is_neg64(a), neg64(a), a)

# The low 64 bits of a * b (uint64 multiplication).
def mul64(a: F64Word.W64, b: F64Word.W64) -> F64Word.W64:
  match a:
    case F64Word.W64{+ah, +al}:
      match b:
        case F64Word.W64{+bh, +bl}:
          F64Word.W64{(F64Word.mul_hi(al, bl) + (al * bh) + (ah * bl) : U32), (al * bl : U32)}

def lt_u64(a: F64Word.W64, b: F64Word.W64) -> Bool:
  match a:
    case F64Word.W64{+ah, +al}:
      match b:
        case F64Word.W64{+bh, +bl}:
          F64Word.lt64(ah, al, bh, bl)

# static_cast<double>(uint64).
def u64_to_f64(a: F64Word.W64) -> F64Repr.F64:
  match a:
    case F64Word.W64{+h, +l}:
      F64Repr.from_u64(h, l)

# static_cast<double>(int32).
def i32_to_f64(+x: U32) -> F64Repr.F64:
  F64Repr.from_i32(x)

# extended_int<64>: `count` is the signed chunk count (int32), `chunks` the |count| chunks, least significant first.
type Big is Data:
  Big{count: U32, chunks: List<&2, U32>}

def max_chunks() -> U32:
  64

def big_zero() -> Big:
  Big{0, Nil{}}

def one_chunk(nonzero: Bool, +x: U32) -> List<&2, U32>:
  match nonzero:
    case True{}:
      [x]
    case False{}:
      Nil{}

def signed_count(neg: Bool, +size: U32) -> U32:
  F64Word.pick(neg, (0 - size : U32), size)

# extended_int(int32).
def big_of_i32(+x: U32) -> Big:
  +nonzero = Bool.not(U32.is_zero(x))
  Big{signed_count(is_neg32(x), Bool.to_u32(nonzero)), one_chunk(nonzero, abs32(x))}

def i64_chunks(+h: U32, +l: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_zero(h), one_chunk(Bool.not(U32.is_zero(l)), l), [l, h])

def i64_size(+h: U32, +l: U32) -> U32:
  F64Word.pick(U32.is_zero(h), Bool.to_u32(Bool.not(U32.is_zero(l))), 2)

def big_of_magnitude(neg: Bool, m: F64Word.W64) -> Big:
  match m:
    case F64Word.W64{+h, +l}:
      Big{signed_count(neg, i64_size(h, l)), i64_chunks(h, l)}

# extended_int(int64).
def big_of_i64(+x: F64Word.W64) -> Big:
  big_of_magnitude(is_neg64(x), abs64(x))

def big_count(b: Big) -> U32:
  match b:
    case Big{+count, _}:
      count

def big_size(b: Big) -> U32:
  abs32(big_count(b))

def big_is_neg(b: Big) -> Bool:
  is_neg32(big_count(b))

def big_is_zero(b: Big) -> Bool:
  U32.is_zero(big_count(b))

def big_is_pos(+b: Big) -> Bool:
  Bool.not(big_is_neg(b)) && Bool.not(big_is_zero(b))

# operator-(): the count negated.
def big_neg(b: Big) -> Big:
  match b:
    case Big{+count, +chunks}:
      Big{(0 - count : U32), chunks}

def big_negate_if(c: Bool, +b: Big) -> Big:
  Bool.pick(Big, c, big_neg(b), b)

def length32(l: List<&2, U32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{_, rest}:
      length32(rest, (acc + 1 : U32))

# The first n chunks of l, padded with zero chunks.
def zeros(n: Nat) -> List<&2, U32>:
  List.replicate(U32, n, 0)

def take_pad_go(l: List<&2, U32>, stop: Bool, +n: U32) -> List<&2, U32>:
  match l:
    case Nil{}:
      zeros(U32.to_nat(n))
    case Con{+x, rest}:
      match stop:
        case True{}:
          Nil{}
        case False{}:
          x <> take_pad_go(rest, U32.is_eq(n, 1), (n - 1 : U32))

def take_pad(+l: List<&2, U32>, +n: U32) -> List<&2, U32>:
  take_pad_go(l, U32.is_zero(n), n)

def chunk_at(l: List<&2, U32>, +i: U32) -> U32:
  match l:
    case Nil{}:
      0
    case Con{+x, rest}:
      F64Word.pick(U32.is_zero(i), x, chunk_at(rest, (i - 1 : U32)))

def carry_tail(+c: U32) -> List<&2, U32>:
  one_chunk(Bool.not(U32.is_zero(c)), c)

def add_carry(l: List<&2, U32>, +c: U32) -> List<&2, U32>:
  match l:
    case Nil{}:
      carry_tail(c)
    case Con{+x, rest}:
      +s = (x + c : U32)
      s <> add_carry(rest, F64Word.carry(s, x))

def add_lists(a: List<&2, U32>, b: List<&2, U32>, +c: U32) -> List<&2, U32>:
  match a:
    case Nil{}:
      add_carry(b, c)
    case Con{+x, xs}:
      match b:
        case Nil{}:
          add_carry(x <> xs, c)
        case Con{+y, ys}:
          +s1 = (x + y : U32)
          +s = (s1 + c : U32)
          s <> add_lists(xs, ys, (F64Word.carry(s1, x) + F64Word.carry(s, s1) : U32))

# The private add(c1, sz1, c2, sz2): the larger size, plus a carry chunk below N.
def add_magnitudes(+c1: List<&2, U32>, +c2: List<&2, U32>) -> Big:
  +sum = add_lists(c1, c2, 0)
  +count = U32.min(length32(sum, 0), max_chunks())
  Big{count, take_pad(sum, count)}

def sub_lists(a: List<&2, U32>, b: List<&2, U32>, +bw: U32) -> List<&2, U32>:
  match a:
    case Nil{}:
      Nil{}
    case Con{+x, xs}:
      match b:
        case Nil{}:
          (x - bw : U32) <> sub_lists(xs, Nil{}, F64Word.borrow(x, bw))
        case Con{+y, ys}:
          +out = Bool.or((x < y : U32), Bool.and(U32.is_eq(x, y), Bool.not(U32.is_zero(bw))))
          (x - y - bw : U32) <> sub_lists(xs, ys, Bool.to_u32(out))

# The subtraction loop of the private dif: (c1 - c2) mod 2^(32 sz1), count = sz1 - 1, plus one if the top chunk is set.
def dif_body(+c1: List<&2, U32>, +c2: List<&2, U32>) -> Big:
  +digits = sub_lists(c1, c2, 0)
  +sz1 = length32(c1, 0)
  +count = ((sz1 - 1 : U32) + F64Word.nonzero(chunk_at(digits, (sz1 - 1 : U32))) : U32)
  Big{count, take_pad(digits, count)}

type Cut is Data:
  Cut{size: U32, less: Bool}

def top_cut(ra: List<&2, U32>, rb: List<&2, U32>, +n: U32) -> Cut:
  match ra:
    case Nil{}:
      Cut{0, False{}}
    case Con{+x, xs}:
      match rb:
        case Nil{}:
          Cut{n, False{}}
        case Con{+y, ys}:
          Bool.pick(Cut, U32.is_eq(x, y), top_cut(xs, ys, (n - 1 : U32)), Cut{n, (x < y : U32)})

def dif_ordered(less: Bool, +a: List<&2, U32>, +b: List<&2, U32>) -> Big:
  match less:
    case True{}:
      big_neg(dif_body(b, a))
    case False{}:
      dif_body(a, b)

def dif_cut_sized(equal: Bool, +less: Bool, +size: U32, +c1: List<&2, U32>, +c2: List<&2, U32>) -> Big:
  match equal:
    case True{}:
      big_zero()
    case False{}:
      dif_ordered(less, take_pad(c1, size), take_pad(c2, size))

def dif_cut(cut: Cut, +c1: List<&2, U32>, +c2: List<&2, U32>) -> Big:
  match cut:
    case Cut{+size, +less}:
      dif_cut_sized(U32.is_zero(size), less, size, c1, c2)

def dif_same_size(same: Bool, +s1: U32, +c1: List<&2, U32>, +c2: List<&2, U32>) -> Big:
  match same:
    case True{}:
      dif_cut(top_cut(List.reverse(&2, U32, c1), List.reverse(&2, U32, c2), s1), c1, c2)
    case False{}:
      dif_body(c1, c2)

def dif_shorter(shorter: Bool, +s1: U32, +s2: U32, +c1: List<&2, U32>, +c2: List<&2, U32>) -> Big:
  match shorter:
    case True{}:
      big_neg(dif_body(c2, c1))
    case False{}:
      dif_same_size(U32.is_eq(s1, s2), s1, c1, c2)

def dif_sized(+s1: U32, +s2: U32, +c1: List<&2, U32>, +c2: List<&2, U32>) -> Big:
  dif_shorter((s1 < s2 : U32), s1, s2, c1, c2)

# The private dif(c1, sz1, c2, sz2) with rec = false.
def dif_magnitudes(+c1: List<&2, U32>, +c2: List<&2, U32>) -> Big:
  dif_sized(length32(c1, 0), length32(c2, 0), c1, c2)

def mul_row(l: List<&2, U32>, +d: U32, +c: U32) -> List<&2, U32>:
  match l:
    case Nil{}:
      [c]
    case Con{+x, rest}:
      +lo = (d * x : U32)
      +s = (lo + c : U32)
      s <> mul_row(rest, d, (F64Word.mul_hi(d, x) + F64Word.carry(s, lo) : U32))

def mul_lists(a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  match a:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      add_lists(mul_row(b, x, 0), 0 <> mul_lists(rest, b), 0)

# The private mul(c1, sz1, c2, sz2): min(N, sz1 + sz2 - 1) chunks, plus a carry chunk below N.
def mul_magnitudes(+c1: List<&2, U32>, +c2: List<&2, U32>) -> Big:
  +product = mul_lists(c1, c2)
  +base = U32.min(((length32(c1, 0) + length32(c2, 0) : U32) - 1 : U32), max_chunks())
  +count = (base + Bool.to_u32(Bool.not(U32.is_eq(base, max_chunks())) && Bool.not(U32.is_zero(chunk_at(product, base)))) : U32)
  Big{count, take_pad(product, count)}

def signs_differ(+a: U32, +b: U32) -> Bool:
  Bool.xor(is_neg32(a), is_neg32(b))

def mixed_signs(differ: Bool, +la: List<&2, U32>, +lb: List<&2, U32>) -> Big:
  match differ:
    case True{}:
      dif_magnitudes(la, lb)
    case False{}:
      add_magnitudes(la, lb)

def add_nonzero(+ca: U32, +la: List<&2, U32>, +cb: U32, +lb: List<&2, U32>) -> Big:
  big_negate_if(is_neg32(ca), mixed_signs(signs_differ(ca, cb), la, lb))

def dif_nonzero(+ca: U32, +la: List<&2, U32>, +cb: U32, +lb: List<&2, U32>) -> Big:
  big_negate_if(is_neg32(ca), mixed_signs(Bool.not(signs_differ(ca, cb)), la, lb))

def add_right(zero_b: Bool, +ca: U32, +la: List<&2, U32>, +cb: U32, +lb: List<&2, U32>) -> Big:
  match zero_b:
    case True{}:
      Big{ca, la}
    case False{}:
      add_nonzero(ca, la, cb, lb)

def dif_right(zero_b: Bool, +ca: U32, +la: List<&2, U32>, +cb: U32, +lb: List<&2, U32>) -> Big:
  match zero_b:
    case True{}:
      Big{ca, la}
    case False{}:
      dif_nonzero(ca, la, cb, lb)

def add_left(zero_a: Bool, +ca: U32, +la: List<&2, U32>, +cb: U32, +lb: List<&2, U32>) -> Big:
  match zero_a:
    case True{}:
      Big{cb, lb}
    case False{}:
      add_right(U32.is_zero(cb), ca, la, cb, lb)

# extended_int::add(e1, e2), operator+.
def big_add(a: Big, b: Big) -> Big:
  match a:
    case Big{+ca, +la}:
      match b:
        case Big{+cb, +lb}:
          add_left(U32.is_zero(ca), ca, la, cb, lb)

def dif_left(zero_a: Bool, +ca: U32, +la: List<&2, U32>, +cb: U32, +lb: List<&2, U32>) -> Big:
  match zero_a:
    case True{}:
      Big{(0 - cb : U32), lb}
    case False{}:
      dif_right(U32.is_zero(cb), ca, la, cb, lb)

# extended_int::dif(e1, e2), operator-.
def big_sub(a: Big, b: Big) -> Big:
  match a:
    case Big{+ca, +la}:
      match b:
        case Big{+cb, +lb}:
          dif_left(U32.is_zero(ca), ca, la, cb, lb)

def mul_nonzero(zero: Bool, +ca: U32, +la: List<&2, U32>, +cb: U32, +lb: List<&2, U32>) -> Big:
  match zero:
    case True{}:
      big_zero()
    case False{}:
      big_negate_if(signs_differ(ca, cb), mul_magnitudes(la, lb))

# extended_int::mul(e1, e2), operator*.
def big_mul(a: Big, b: Big) -> Big:
  match a:
    case Big{+ca, +la}:
      match b:
        case Big{+cb, +lb}:
          mul_nonzero(U32.is_zero(ca) || U32.is_zero(cb), ca, la, cb, lb)

# operator*(int32).
def big_mul_i32(a: Big, +x: U32) -> Big:
  big_mul(a, big_of_i32(x))

def pow32() -> F64Repr.F64:
  F64Repr.F64{1106247680, 0}

def chunk_f64(+x: U32) -> F64Repr.F64:
  F64Repr.from_u32(x)

def shifted_in(+acc: F64Repr.F64, +x: U32) -> F64Repr.F64:
  F64Arith.add(F64Arith.mul(acc, pow32()), chunk_f64(x))

type Split is Data:
  Split{value: F64Repr.F64, exp: U32}

def top_three(+size: U32, +top: List<&2, U32>) -> Split:
  +first = chunk_at(top, 0)
  Split{shifted_in(shifted_in(chunk_f64(first), chunk_at(top, 1)), chunk_at(top, 2)), ((size - 3 : U32) << 5n : U32)}

def split_small(+size: U32, +top: List<&2, U32>) -> Split:
  +low = chunk_at(top, 0)
  +two = shifted_in(chunk_f64(low), chunk_at(top, 1))
  Bool.pick(Split, U32.is_eq(size, 1), Split{chunk_f64(low), 0}, Split{two, 0})

def split_route(small: Bool, +size: U32, +top: List<&2, U32>) -> Split:
  match small:
    case True{}:
      Bool.pick(Split, U32.is_zero(size), Split{F64Repr.zero(), 0}, split_small(size, top))
    case False{}:
      top_three(size, top)

def split_sized(+size: U32, +top: List<&2, U32>) -> Split:
  split_route((size < 3 : U32), size, top)

def negate_split(neg: Bool, s: Split) -> Split:
  match s:
    case Split{+value, +exp}:
      Split{F64Repr.pick(neg, F64Repr.neg(value), value), exp}

# extended_int::p(): the top chunks as a double (converted the way Boost does, with its roundings) and a binary exponent.
def big_split(b: Big) -> Split:
  match b:
    case Big{+count, +chunks}:
      negate_split(is_neg32(count), split_sized(abs32(count), List.reverse(&2, U32, chunks)))

# extended_int::d() (to_fpt of a big int).
def split_to_f64(s: Split) -> F64Repr.F64:
  match s:
    case Split{+value, +exp}:
      F64Repr.ldexp(value, exp)

def big_to_f64(b: Big) -> F64Repr.F64:
  split_to_f64(big_split(b))

# extended_exponent_fpt<double>: val in [0.5, 1) (or 0), exp an int.
type Efpt is Data:
  Efpt{val: F64Repr.F64, exp: U32}

def frexp_into(f: F64Repr.Frexp, +exp: U32) -> Efpt:
  match f:
    case F64Repr.Frexp{+m, +e}:
      Efpt{m, (e + exp : U32)}

# extended_exponent_fpt(val, exp).
def efpt(+val: F64Repr.F64, +exp: U32) -> Efpt:
  frexp_into(F64Repr.frexp(val), exp)

def efpt_of(+val: F64Repr.F64) -> Efpt:
  efpt(val, 0)

# to_efpt of a big int: extended_exponent_fpt(p.first, p.second).
def split_to_efpt(s: Split) -> Efpt:
  match s:
    case Split{+value, +exp}:
      efpt(value, exp)

def big_to_efpt(b: Big) -> Efpt:
  split_to_efpt(big_split(b))

def efpt_val(a: Efpt) -> F64Repr.F64:
  match a:
    case Efpt{+val, _}:
      val

def efpt_is_pos(a: Efpt) -> Bool:
  F64Cmp.lt(F64Repr.zero(), efpt_val(a))

def efpt_is_neg(a: Efpt) -> Bool:
  F64Cmp.lt(efpt_val(a), F64Repr.zero())

def efpt_is_zero(a: Efpt) -> Bool:
  F64Cmp.eq(efpt_val(a), F64Repr.zero())

def efpt_neg(a: Efpt) -> Efpt:
  match a:
    case Efpt{+val, +exp}:
      efpt(F64Repr.neg(val), exp)

def far_above(+e: U32, +f: U32) -> Bool:
  lt_i32((f + 54 : U32), e)

def efpt_aligned_sum(+big_val: F64Repr.F64, +big_exp: U32, +small_val: F64Repr.F64, +small_exp: U32) -> Efpt:
  efpt(F64Arith.add(F64Repr.ldexp(big_val, (big_exp - small_exp : U32)), small_val), small_exp)

def efpt_add_words(+av: F64Repr.F64, +ae: U32, +bv: F64Repr.F64, +be: U32) -> Efpt:
  +keep_b = F64Cmp.eq(av, F64Repr.zero()) || far_above(be, ae)
  +keep_a = F64Cmp.eq(bv, F64Repr.zero()) || far_above(ae, be)
  +a_first = Bool.not(lt_i32(ae, be))
  +sum = Bool.pick(Efpt, a_first, efpt_aligned_sum(av, ae, bv, be), efpt_aligned_sum(bv, be, av, ae))
  Bool.pick(Efpt, keep_b, Efpt{bv, be}, Bool.pick(Efpt, keep_a, Efpt{av, ae}, sum))

# extended_exponent_fpt::operator+.
def efpt_add(a: Efpt, b: Efpt) -> Efpt:
  match a:
    case Efpt{+av, +ae}:
      match b:
        case Efpt{+bv, +be}:
          efpt_add_words(av, ae, bv, be)

def efpt_sub_words(+av: F64Repr.F64, +ae: U32, +bv: F64Repr.F64, +be: U32) -> Efpt:
  +keep_b = F64Cmp.eq(av, F64Repr.zero()) || far_above(be, ae)
  +keep_a = F64Cmp.eq(bv, F64Repr.zero()) || far_above(ae, be)
  +a_first = Bool.not(lt_i32(ae, be))
  +high_a = efpt(F64Arith.sub(F64Repr.ldexp(av, (ae - be : U32)), bv), be)
  +high_b = efpt(F64Arith.add(F64Repr.ldexp(F64Repr.neg(bv), (be - ae : U32)), av), ae)
  Bool.pick(Efpt, keep_b, efpt(F64Repr.neg(bv), be), Bool.pick(Efpt, keep_a, Efpt{av, ae}, Bool.pick(Efpt, a_first, high_a, high_b)))

# extended_exponent_fpt::operator-.
def efpt_sub(a: Efpt, b: Efpt) -> Efpt:
  match a:
    case Efpt{+av, +ae}:
      match b:
        case Efpt{+bv, +be}:
          efpt_sub_words(av, ae, bv, be)

# extended_exponent_fpt::operator*.
def efpt_mul(a: Efpt, b: Efpt) -> Efpt:
  match a:
    case Efpt{+av, +ae}:
      match b:
        case Efpt{+bv, +be}:
          efpt(F64Arith.mul(av, bv), (ae + be : U32))

# extended_exponent_fpt::operator/.
def efpt_div(a: Efpt, b: Efpt) -> Efpt:
  match a:
    case Efpt{+av, +ae}:
      match b:
        case Efpt{+bv, +be}:
          efpt(F64Arith.div(av, bv), (ae - be : U32))

def arithmetic_half(+e: U32) -> U32:
  ((e >> 1n) .|. (e .&. 2147483648) : U32)

# extended_exponent_fpt::sqrt(): an odd exponent moves one factor 2 into the value first.
def efpt_sqrt(a: Efpt) -> Efpt:
  match a:
    case Efpt{+val, +exp}:
      +odd = Bool.not(U32.is_zero((exp .&. 1 : U32)))
      efpt(F64Arith.sqrt(F64Repr.pick(odd, F64Arith.mul(val, F64Repr.two()), val)), arithmetic_half(F64Word.pick(odd, (exp - 1 : U32), exp)))

# extended_exponent_fpt::d() (to_fpt of an efpt).
def efpt_to_f64(a: Efpt) -> F64Repr.F64:
  match a:
    case Efpt{+val, +exp}:
      F64Repr.ldexp(val, exp)
