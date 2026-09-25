import Base
import ./word.bend as FW
import ./repr.bend as FR

# IEEE comparisons (false when either side is NaN, +0 == -0), std::min/std::max, and Boost.Polygon's
# ulp_comparison<fpt64>.

def key_hi(+h: U32) -> U32:
  FW.pick((h >= FR.sign_mask() : U32), U32.not(h), (h .|. FR.sign_mask() : U32))

def key_lo(+h: U32, +l: U32) -> U32:
  FW.pick((h >= FR.sign_mask() : U32), U32.not(l), l)

def unordered(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Bool:
  FR.is_nan_words(ah, al) || FR.is_nan_words(bh, bl)

def both_zero(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Bool:
  FR.is_zero_words(ah, al) && FR.is_zero_words(bh, bl)

def lt_words(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Bool:
  +ordered_lt = FW.lt64(key_hi(ah), key_lo(ah, al), key_hi(bh), key_lo(bh, bl))
  Bool.not(unordered(ah, al, bh, bl)) && Bool.not(both_zero(ah, al, bh, bl)) && ordered_lt

def le_words(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Bool:
  +ordered_le = FW.le64(key_hi(ah), key_lo(ah, al), key_hi(bh), key_lo(bh, bl))
  Bool.not(unordered(ah, al, bh, bl)) && (both_zero(ah, al, bh, bl) || ordered_le)

def eq_words(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Bool:
  +same = U32.is_eq(ah, bh) && U32.is_eq(al, bl)
  Bool.not(unordered(ah, al, bh, bl)) && (both_zero(ah, al, bh, bl) || same)

def lt(a: FR.F64, b: FR.F64) -> Bool:
  match a:
    case FR.F64{+ah, +al}:
      match b:
        case FR.F64{+bh, +bl}:
          lt_words(ah, al, bh, bl)

def le(a: FR.F64, b: FR.F64) -> Bool:
  match a:
    case FR.F64{+ah, +al}:
      match b:
        case FR.F64{+bh, +bl}:
          le_words(ah, al, bh, bl)

def eq(a: FR.F64, b: FR.F64) -> Bool:
  match a:
    case FR.F64{+ah, +al}:
      match b:
        case FR.F64{+bh, +bl}:
          eq_words(ah, al, bh, bl)

def gt(a: FR.F64, b: FR.F64) -> Bool:
  lt(b, a)

def ge(a: FR.F64, b: FR.F64) -> Bool:
  le(b, a)

def ne(a: FR.F64, b: FR.F64) -> Bool:
  Bool.not(eq(a, b))

# std::min(a, b) = (b < a) ? b : a and std::max(a, b) = (a < b) ? b : a.
def min(+a: FR.F64, +b: FR.F64) -> FR.F64:
  FR.pick(lt(b, a), b, a)

def max(+a: FR.F64, +b: FR.F64) -> FR.F64:
  FR.pick(lt(a, b), b, a)

def ulp_key_hi(+h: U32, +l: U32) -> U32:
  FW.pick((h < FR.sign_mask() : U32), (FR.sign_mask() - h - FW.nonzero(l) : U32), h)

def ulp_key_lo(+h: U32, +l: U32) -> U32:
  FW.pick((h < FR.sign_mask() : U32), (0 - l : U32), l)

def within(+dh: U32, +dl: U32, +max_ulps: U32) -> Bool:
  U32.is_zero(dh) && (dl <= max_ulps : U32)

def ulp_result(close: Bool, a_more: Bool) -> Cmp:
  match close:
    case True{}:
      EQ{}
    case False{}:
      match a_more:
        case True{}:
          LT{}
        case False{}:
          GT{}

def ulp_keys(+ka_h: U32, +ka_l: U32, +kb_h: U32, +kb_l: U32, +max_ulps: U32) -> Cmp:
  +a_more = FW.lt64(kb_h, kb_l, ka_h, ka_l)
  +dh = FW.pick(a_more, FW.sub_hi(ka_h, ka_l, kb_h, kb_l), FW.sub_hi(kb_h, kb_l, ka_h, ka_l))
  +dl = FW.pick(a_more, (ka_l - kb_l : U32), (kb_l - ka_l : U32))
  ulp_result(within(dh, dl, max_ulps), a_more)

# Boost.Polygon ulp_comparison<fpt64>()(a, b, max_ulps): EQ{} within max_ulps, else LT{} when a < b, GT{} when
# a > b, on the sign-magnitude integer order of the bits.
def ulp_cmp(a: FR.F64, b: FR.F64, +max_ulps: U32) -> Cmp:
  match a:
    case FR.F64{+ah, +al}:
      match b:
        case FR.F64{+bh, +bl}:
          ulp_keys(ulp_key_hi(ah, al), ulp_key_lo(ah, al), ulp_key_hi(bh, bl), ulp_key_lo(bh, bl), max_ulps)

def distance_keys(+ka_h: U32, +ka_l: U32, +kb_h: U32, +kb_l: U32) -> FW.W64:
  +a_more = FW.lt64(kb_h, kb_l, ka_h, ka_l)
  FW.W64{FW.pick(a_more, FW.sub_hi(ka_h, ka_l, kb_h, kb_l), FW.sub_hi(kb_h, kb_l, ka_h, ka_l)),
    FW.pick(a_more, (ka_l - kb_l : U32), (kb_l - ka_l : U32))}

# The unsigned distance between the ulp_comparison keys of a and b.
def ulp_distance(a: FR.F64, b: FR.F64) -> FW.W64:
  match a:
    case FR.F64{+ah, +al}:
      match b:
        case FR.F64{+bh, +bl}:
          distance_keys(ulp_key_hi(ah, al), ulp_key_lo(ah, al), ulp_key_hi(bh, bl), ulp_key_lo(bh, bl))
