// F64 fast paths
// ==============
// The soft F64 (f64/arith.bend, f64/cmp.bend, f64/repr.bend) on the FPU wherever IEEE-754 round to nearest even
// fixes every result bit: finite operands, a nonzero divisor, a sqrt argument that is not below zero, a conversion
// in range. None of those makes a NaN, so no platform's NaN rules apply. Every other input answers 0 and runs the
// Bend body. Each fast path is the first thing its def's spin tries (SPIN_FAST); the JS target, the laws and
// SPIN(def) keep the Bend body, and `seedfinder selftest` compares the two.

#include <math.h>
#include <stdint.h>
#include <string.h>

static double f64_of(u32 h, u32 l) {
  u64 u = (u64)h << 32 | l;
  double d;
  memcpy(&d, &u, 8);
  return d;
}

static Term f64_put(THR Term* o, double d) {
  u64 u;
  memcpy(&u, &d, 8);
  o[0] = (u32)(u >> 32);
  o[1] = (u32)u;
  return 1;
}

static Term f64_put_word(THR Term* o, u32 w) {
  o[0] = w;
  return 1;
}

static bool f64_finite(u32 h) {
  return (h & 0x7ff00000u) != 0x7ff00000u;
}

static bool f64_nonzero(u32 h, u32 l) {
  return ((h & 0x7fffffffu) | l) != 0;
}

static Term SPIN_FAST(f64/arith:add)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl) {
  return f64_finite(ah) && f64_finite(bh) && f64_put(o, f64_of(ah, al) + f64_of(bh, bl));
}

static Term SPIN_FAST(f64/arith:sub)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl) {
  return f64_finite(ah) && f64_finite(bh) && f64_put(o, f64_of(ah, al) - f64_of(bh, bl));
}

static Term SPIN_FAST(f64/arith:mul)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl) {
  return f64_finite(ah) && f64_finite(bh) && f64_put(o, f64_of(ah, al) * f64_of(bh, bl));
}

static Term SPIN_FAST(f64/arith:div)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl) {
  return f64_finite(ah) && f64_finite(bh) && f64_nonzero(bh, bl) && f64_put(o, f64_of(ah, al) / f64_of(bh, bl));
}

static Term SPIN_FAST(f64/arith:sqrt)(Env e, THR Term* o, u32 h, u32 l) {
  return f64_finite(h) && (h >> 31 == 0 || !f64_nonzero(h, l)) && f64_put(o, sqrt(f64_of(h, l)));
}

static Term SPIN_FAST(f64/arith:fma)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl, u32 ch, u32 cl) {
  return f64_finite(ah) && f64_finite(bh) && f64_finite(ch)
    && f64_put(o, fma(f64_of(ah, al), f64_of(bh, bl), f64_of(ch, cl)));
}

static Term SPIN_FAST(f64/cmp:lt_words)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl) {
  return f64_put_word(o, f64_of(ah, al) < f64_of(bh, bl));
}

static Term SPIN_FAST(f64/cmp:le_words)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl) {
  return f64_put_word(o, f64_of(ah, al) <= f64_of(bh, bl));
}

static Term SPIN_FAST(f64/cmp:eq_words)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl) {
  return f64_put_word(o, f64_of(ah, al) == f64_of(bh, bl));
}

static Term SPIN_FAST(f64/repr:from_u32_signed)(Env e, THR Term* o, u32 sign, u32 x) {
  return f64_put(o, sign & 1 ? -(double)x : (double)x);
}

static Term SPIN_FAST(f64/repr:to_i32_words)(Env e, THR Term* o, u32 h, u32 l) {
  return (h >> 20 & 0x7ffu) < 1054 && f64_put_word(o, (u32)(int32_t)f64_of(h, l));
}

static Term SPIN_FAST(f64/repr:floor_words)(Env e, THR Term* o, u32 h, u32 l) {
  return f64_finite(h) && f64_put(o, floor(f64_of(h, l)));
}

static Term SPIN_FAST(f64/repr:ceil_words)(Env e, THR Term* o, u32 h, u32 l) {
  return f64_finite(h) && f64_put(o, ceil(f64_of(h, l)));
}

// The check: n operand sets (raw bits; subnormal, near-overflow, near-integer and close exponents; cancelling sums and
// products; infinities and NaNs) through every fast path and its Bend body; the count of answered results that differ.

typedef Term (*F64Unary)(Env e, THR Term* o, u32 h, u32 l);
typedef Term (*F64Binary)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl);
typedef Term (*F64Ternary)(Env e, THR Term* o, u32 ah, u32 al, u32 bh, u32 bl, u32 ch, u32 cl);

typedef struct {
  F64Unary fast, body;
  int words;
} F64UnaryPath;

typedef struct {
  F64Binary fast, body;
  int words;
} F64BinaryPath;

static const F64UnaryPath f64_unary[] = {
  {SPIN_FAST(f64/arith:sqrt), SPIN(f64/arith:sqrt), 2},
  {SPIN_FAST(f64/repr:from_u32_signed), SPIN(f64/repr:from_u32_signed), 2},
  {SPIN_FAST(f64/repr:to_i32_words), SPIN(f64/repr:to_i32_words), 1},
  {SPIN_FAST(f64/repr:floor_words), SPIN(f64/repr:floor_words), 2},
  {SPIN_FAST(f64/repr:ceil_words), SPIN(f64/repr:ceil_words), 2},
};

static const F64BinaryPath f64_binary[] = {
  {SPIN_FAST(f64/arith:add), SPIN(f64/arith:add), 2},
  {SPIN_FAST(f64/arith:sub), SPIN(f64/arith:sub), 2},
  {SPIN_FAST(f64/arith:mul), SPIN(f64/arith:mul), 2},
  {SPIN_FAST(f64/arith:div), SPIN(f64/arith:div), 2},
  {SPIN_FAST(f64/cmp:lt_words), SPIN(f64/cmp:lt_words), 1},
  {SPIN_FAST(f64/cmp:le_words), SPIN(f64/cmp:le_words), 1},
  {SPIN_FAST(f64/cmp:eq_words), SPIN(f64/cmp:eq_words), 1},
};

static const F64Ternary f64_fma_fast = SPIN_FAST(f64/arith:fma), f64_fma_body = SPIN(f64/arith:fma);

static u64 f64_next(u64* rng) {
  *rng ^= *rng << 13;
  *rng ^= *rng >> 7;
  *rng ^= *rng << 17;
  return *rng;
}

static u64 f64_operand(u64* rng) {
  u64 r = f64_next(rng), m = f64_next(rng), sig = m & 0x800FFFFFFFFFFFFFull;
  switch (r & 7) {
    case 0: return m;
    case 1: return sig | (r >> 8 & 3) << 52;
    case 2: return sig | (2040 + (r >> 8 & 7)) << 52;
    case 3: return (m & 0x8000000000000FFFull) | (991 + (r >> 8 & 63)) << 52;
    case 4: return (m & 0x80000000000000FFull) | (1000 + (r >> 8 & 63)) << 52;
    case 5: return sig | (959 + (r >> 8 & 127)) << 52;
    case 6: return sig | (r >> 8) % 2047 << 52;
    default: return (m & 0x8000000000000000ull) | 0x7FF0000000000000ull | (r >> 8 & 1 ? m & 0xFFFFFFFFFFFFFull : 0);
  }
}

static u64 f64_bits(double d) {
  u64 u;
  memcpy(&u, &d, 8);
  return u;
}

static u64 f64_differs(Term answered, const Term* got, Term body, const Term* want, int words) {
  return answered && (body != 1 || got[0] != want[0] || (words == 2 && got[1] != want[1]));
}

static u64 f64_check_set(Env e, u64* rng, u64 i) {
  u64 a = f64_operand(rng), b = f64_operand(rng), c = f64_operand(rng), differ = 0;
  if (i & 1) {
    b = (a & 0xFFFFFFFFFFF00000ull) ^ (b & 0xFFFFF) ^ (f64_next(rng) & 0x8000000000000000ull);
  }
  if (i % 5 == 0) {
    b = a ^ (f64_next(rng) & 0x8000000000000000ull);
  }
  if (i % 3 == 0) {
    c = f64_bits(f64_of(a >> 32, (u32)a) * f64_of(b >> 32, (u32)b)) ^ 0x8000000000000000ull ^ (f64_next(rng) & 0xF);
  }
  u32 ah = a >> 32, al = (u32)a, bh = b >> 32, bl = (u32)b, ch = c >> 32, cl = (u32)c;
  Term got[2] = {0, 0}, want[2] = {0, 0};
  for (size_t k = 0; k < sizeof f64_unary / sizeof f64_unary[0]; k++) {
    const F64UnaryPath* p = &f64_unary[k];
    Term answered = p->fast(e, got, ah, al);
    differ += f64_differs(answered, got, answered ? p->body(e, want, ah, al) : 0, want, p->words);
  }
  for (size_t k = 0; k < sizeof f64_binary / sizeof f64_binary[0]; k++) {
    const F64BinaryPath* p = &f64_binary[k];
    Term answered = p->fast(e, got, ah, al, bh, bl);
    differ += f64_differs(answered, got, answered ? p->body(e, want, ah, al, bh, bl) : 0, want, p->words);
  }
  Term answered = f64_fma_fast(e, got, ah, al, bh, bl, ch, cl);
  return differ + f64_differs(answered, got, answered ? f64_fma_body(e, want, ah, al, bh, bl, ch, cl) : 0, want, 2);
}

Term native_f64_check_run(Env e, Term* f, IoWork* w) {
  u64 rng = 0x9E3779B97F4A7C15ull, differ = 0;
  for (u64 i = 0; i < (u32)f[0]; i++) {
    differ += f64_check_set(e, &rng, i);
  }
  return (Term)(u32)(differ < 0xFFFFFFFFull ? differ : 0xFFFFFFFFull);
}

static void __attribute__((constructor)) native_f64_use(void) {
  io_eff(CID(native_f64_check), native_f64_check_run);
}
