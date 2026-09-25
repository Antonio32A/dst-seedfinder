import Base

type W64 is Data:
  W64{hi: U32, lo: U32}

# Word-level helpers for the soft float64 kit: branchless selects, carries, 32x32 products, leading-zero counts
# and 64-bit shifts on (hi, lo) pairs. Shift counts are masked, so any U32 count is safe (0 past the width).

def pick(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def nonzero(+x: U32) -> U32:
  Bool.to_u32(Bool.not(U32.is_zero(x)))

def carry(+sum: U32, +a: U32) -> U32:
  Bool.to_u32((sum < a : U32))

def borrow(+a: U32, +b: U32) -> U32:
  Bool.to_u32((a < b : U32))

def shl(+x: U32, +k: U32) -> U32:
  pick((k < 32 : U32), (x << U32.to_nat((k .&. 31 : U32)) : U32), 0)

def shr(+x: U32, +k: U32) -> U32:
  pick((k < 32 : U32), (x >> U32.to_nat((k .&. 31 : U32)) : U32), 0)

def mul_hi(+a: U32, +b: U32) -> U32:
  +al = (a .&. 65535 : U32)
  +ah = (a >> 16n : U32)
  +bl = (b .&. 65535 : U32)
  +bh = (b >> 16n : U32)
  +t = (((al * bl) >> 16n) + (al * bh) : U32)
  +t2 = ((ah * bl) + (t .&. 65535) : U32)
  ((ah * bh) + (t >> 16n) + (t2 >> 16n) : U32)

# mul_hi through Nat products of at most 48 bits: two native multiplies in compiled code (clang drops the Nat
# overflow checks), the same values as mul_hi. Nat is unary in the proof checker, so laws never reach this.
def mul_hi_nat(+a: U32, +b: U32) -> U32:
  +x = U32.to_nat(a)
  +low = Nat.div(Nat.mul(x, U32.to_nat((b .&. 65535 : U32))), 65536n)
  U32.from_nat(Nat.div(Nat.add(Nat.mul(x, U32.to_nat((b >> 16n : U32))), low), 65536n))

def clz32(+x: U32) -> U32:
  +c16 = (x < 65536 : U32)
  +x1 = pick(c16, (x << 16n : U32), x)
  +c8 = (x1 < 16777216 : U32)
  +x2 = pick(c8, (x1 << 8n : U32), x1)
  +c4 = (x2 < 268435456 : U32)
  +x3 = pick(c4, (x2 << 4n : U32), x2)
  +c2 = (x3 < 1073741824 : U32)
  +x4 = pick(c2, (x3 << 2n : U32), x3)
  (pick(c16, 16, 0) + pick(c8, 8, 0) + pick(c4, 4, 0) + pick(c2, 2, 0) + Bool.to_u32((x4 < 2147483648 : U32))
    + Bool.to_u32(U32.is_zero(x)) : U32)

def clz64(+h: U32, +l: U32) -> U32:
  pick(U32.is_zero(h), (32 + clz32(l) : U32), clz32(h))

def shl_hi(+h: U32, +l: U32, +k: U32) -> U32:
  pick((k < 32 : U32), (shl(h, k) .|. shr(l, (32 - k : U32)) : U32), shl(l, (k - 32 : U32)))

def shl_lo(+l: U32, +k: U32) -> U32:
  shl(l, k)

def shr_hi(+h: U32, +d: U32) -> U32:
  shr(h, d)

def shr_lo(+h: U32, +l: U32, +d: U32) -> U32:
  pick((d < 32 : U32), (shr(l, d) .|. shl(h, (32 - d : U32)) : U32), shr(h, (d - 32 : U32)))

def lost_bits(+h: U32, +l: U32, +d: U32) -> U32:
  +mid = (l .|. shl(h, (64 - d : U32)) : U32)
  pick((d < 32 : U32), shl(l, (32 - d : U32)), pick((d < 64 : U32), mid, (h .|. l : U32)))

def shr_jam_lo(+h: U32, +l: U32, +d: U32) -> U32:
  (shr_lo(h, l, d) .|. nonzero(lost_bits(h, l, d)) : U32)

def add_hi(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> U32:
  (ah + bh + carry((al + bl : U32), al) : U32)

def sub_hi(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> U32:
  (ah - bh - borrow(al, bl) : U32)

def lt64(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Bool:
  (ah < bh : U32) || (U32.is_eq(ah, bh) && (al < bl : U32))

def le64(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Bool:
  (ah < bh : U32) || (U32.is_eq(ah, bh) && (al <= bl : U32))

type W128 is Data:
  W128{w3: U32, w2: U32, w1: U32, w0: U32}

def word_at(+i: U32, +x3: U32, +x2: U32, +x1: U32, +x0: U32) -> U32:
  pick(U32.is_zero(i), x0, pick(U32.is_eq(i, 1), x1, pick(U32.is_eq(i, 2), x2, pick(U32.is_eq(i, 3), x3, 0))))

def shl_word(+j: U32, +q: U32, +r: U32, +x3: U32, +x2: U32, +x1: U32, +x0: U32) -> U32:
  (shl(word_at((j - q : U32), x3, x2, x1, x0), r) .|. shr(word_at((j - q - 1 : U32), x3, x2, x1, x0), (32 - r : U32)) : U32)

def shl128_words(+x3: U32, +x2: U32, +x1: U32, +x0: U32, +k: U32) -> W128:
  +q = (k >> 5n : U32)
  +r = (k .&. 31 : U32)
  W128{shl_word(3, q, r, x3, x2, x1, x0), shl_word(2, q, r, x3, x2, x1, x0), shl_word(1, q, r, x3, x2, x1, x0),
    shl_word(0, q, r, x3, x2, x1, x0)}

def shr_word(+j: U32, +q: U32, +r: U32, +x3: U32, +x2: U32, +x1: U32, +x0: U32) -> U32:
  (shr(word_at((j + q : U32), x3, x2, x1, x0), r) .|. shl(word_at((j + q + 1 : U32), x3, x2, x1, x0), (32 - r : U32)) : U32)

def lost_mask(+base: U32, +d: U32) -> U32:
  +n = pick((d <= base : U32), 0, pick(((d - base) > 32 : U32), 32, (d - base : U32)))
  (shl(1, n) - 1 : U32)

def shr128_jam_words(+x3: U32, +x2: U32, +x1: U32, +x0: U32, +d: U32) -> W128:
  +q = (d >> 5n : U32)
  +r = (d .&. 31 : U32)
  +lost = ((x0 .&. lost_mask(0, d)) .|. (x1 .&. lost_mask(32, d)) .|. (x2 .&. lost_mask(64, d)) .|. (x3 .&. lost_mask(96, d)) : U32)
  W128{shr_word(3, q, r, x3, x2, x1, x0), shr_word(2, q, r, x3, x2, x1, x0), shr_word(1, q, r, x3, x2, x1, x0),
    (shr_word(0, q, r, x3, x2, x1, x0) .|. nonzero(lost) : U32)}

def shl128(x: W128, +k: U32) -> W128:
  match x:
    case W128{+x3, +x2, +x1, +x0}:
      shl128_words(x3, x2, x1, x0, k)

def shr128_jam(x: W128, +d: U32) -> W128:
  match x:
    case W128{+x3, +x2, +x1, +x0}:
      shr128_jam_words(x3, x2, x1, x0, d)

def clz128(+x3: U32, +x2: U32, +x1: U32, +x0: U32) -> U32:
  pick(Bool.not(U32.is_zero(x3)), clz32(x3), pick(Bool.not(U32.is_zero(x2)), (32 + clz32(x2) : U32),
    pick(Bool.not(U32.is_zero(x1)), (64 + clz32(x1) : U32), (96 + clz32(x0) : U32))))

def mul128(+a1: U32, +a0: U32, +b1: U32, +b0: U32) -> W128:
  +p01l = (a0 * b1 : U32)
  +p10l = (a1 * b0 : U32)
  +p11l = (a1 * b1 : U32)
  +p00h = mul_hi(a0, b0)
  +p01h = mul_hi(a0, b1)
  +p10h = mul_hi(a1, b0)
  +p11h = mul_hi(a1, b1)
  +t1a = (p00h + p01l : U32)
  +t1 = (t1a + p10l : U32)
  +c1 = (carry(t1a, p00h) + carry(t1, t1a) : U32)
  +t2a = (p11l + p01h : U32)
  +t2b = (t2a + p10h : U32)
  +t2 = (t2b + c1 : U32)
  W128{(p11h + carry(t2a, p11l) + carry(t2b, t2a) + carry(t2, t2b) : U32), t2, t1, (a0 * b0 : U32)}

def add128_words(+x3: U32, +x2: U32, +x1: U32, +x0: U32, +y3: U32, +y2: U32, +y1: U32, +y0: U32) -> W128:
  +s0 = (x0 + y0 : U32)
  +c0 = carry(s0, x0)
  +s1a = (x1 + y1 : U32)
  +s1 = (s1a + c0 : U32)
  +c1 = (carry(s1a, x1) + carry(s1, s1a) : U32)
  +s2a = (x2 + y2 : U32)
  +s2 = (s2a + c1 : U32)
  +c2 = (carry(s2a, x2) + carry(s2, s2a) : U32)
  W128{(x3 + y3 + c2 : U32), s2, s1, s0}

def sub128_words(+x3: U32, +x2: U32, +x1: U32, +x0: U32, +y3: U32, +y2: U32, +y1: U32, +y0: U32) -> W128:
  +b0 = borrow(x0, y0)
  +d1a = (x1 - y1 : U32)
  +b1 = (borrow(x1, y1) + borrow(d1a, b0) : U32)
  +d2a = (x2 - y2 : U32)
  +b2 = (borrow(x2, y2) + borrow(d2a, b1) : U32)
  W128{(x3 - y3 - b2 : U32), (d2a - b1 : U32), (d1a - b0 : U32), (x0 - y0 : U32)}

def lt128_words(+x3: U32, +x2: U32, +x1: U32, +x0: U32, +y3: U32, +y2: U32, +y1: U32, +y0: U32) -> Bool:
  lt64(x3, x2, y3, y2) || (U32.is_eq(x3, y3) && U32.is_eq(x2, y2) && lt64(x1, x0, y1, y0))
