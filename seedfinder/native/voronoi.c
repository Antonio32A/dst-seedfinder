// Native Voronoi
// ==============
// worldsim/voronoi (BuildVoronoi: the Boost.Polygon 1.52 builder, its polygons and states), the sizing of
// worldsim/commit.bend and the tile cells of gen/world.bend in IEEE doubles and floats, bit for bit: the same
// operations in the same order, the same std::sort of the platform, the same heap and the same array wrap-around.
// Words in: the KK pass's input words (kk.c's, which it runs first) and the plan (windows, world size, whether the pass
// is the last one, then each site's kind and centroid bits). Words out (a new array): the word count, the KK output
// words, the last-pass flag, the pass's polygons, then after the last pass Commit's polygons, ConvertToTileMap's
// polygons and its cells.

#pragma STDC FP_CONTRACT OFF
#pragma clang fp contract(off)

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define VN_NIL 0xffffffffu
#define VN_CHUNKS 64

static uint64_t vn_bits(double x) { uint64_t u; memcpy(&u, &x, 8); return u; }
static double vn_dbl(uint64_t u) { double x; memcpy(&x, &u, 8); return x; }
static float vn_flt(u32 b) { float f; memcpy(&f, &b, 4); return f; }
static u32 vn_fbits(float f) { u32 b; memcpy(&b, &f, 4); return b; }

static int32_t vn_to_i32(double x) { return x > -2147483649.0 && x < 2147483648.0 ? (int32_t)x : INT32_MIN; }
static int32_t vn_ftoi(float x) { return vn_to_i32((double)x); }

static u32 vn_f32_of(double x) {
  uint64_t b = vn_bits(x);
  if ((b & 0x7fffffffffffffffull) > 0x7ff0000000000000ull)
    return ((u32)(b >> 32) & 0x80000000u) | 0x7fc00000u | ((u32)(b >> 29) & 0x7fffffu);
  return vn_fbits((float)x);
}

static double vn_f64_of(u32 b) {
  if ((b & 0x7fffffffu) > 0x7f800000u)
    return vn_dbl((uint64_t)(b & 0x80000000u) << 32 | 0x7ff8000000000000ull | (uint64_t)(b & 0x7fffffu) << 29);
  return (double)vn_flt(b);
}

static float vn_float_of(double x) { return vn_flt(vn_f32_of(x)); }

static double vn_max(double a, double b) { return a < b ? b : a; }
static int vn_finite(double x) { return fabs(x) <= 0x1.fffffffffffffp+1023; }

static int vn_ulp_cmp(double a, double b, uint64_t ulps) {
  uint64_t ka = vn_bits(a), kb = vn_bits(b);
  if (ka < 0x8000000000000000ull) ka = 0x8000000000000000ull - ka;
  if (kb < 0x8000000000000000ull) kb = 0x8000000000000000ull - kb;
  if (ka > kb) return ka - kb <= ulps ? 0 : -1;
  return kb - ka <= ulps ? 0 : 1;
}

static double vn_ldexp(double x, u32 n) { return isfinite(x) && x != 0.0 ? ldexp(x, (int32_t)n) : x + x; }

static double vn_frexp(double x, u32* e) {
  int k = 0;
  double m = isfinite(x) && x != 0.0 ? frexp(x, &k) : x + x;
  *e = (u32)k;
  return m;
}

// extended_int<64> with Boost's chunk algorithms (results left as Boost leaves them, not normalised)
// ----------------------------------------------------------------------------------------------------

typedef struct { int32_t count; u32 c[VN_CHUNKS]; } VnBig;

static u32 vn_big_size(const VnBig* b) { return b->count < 0 ? 0u - (u32)b->count : (u32)b->count; }

static VnBig vn_big_i32(int32_t x) {
  VnBig b;
  b.count = x ? (x < 0 ? -1 : 1) : 0;
  b.c[0] = x < 0 ? 0u - (u32)x : (u32)x;
  return b;
}

static VnBig vn_big_i64(int64_t x) {
  VnBig b;
  uint64_t m = x < 0 ? 0 - (uint64_t)x : (uint64_t)x;
  u32 size = (m >> 32) ? 2 : ((u32)m ? 1 : 0);
  b.c[0] = (u32)m; b.c[1] = (u32)(m >> 32);
  b.count = x < 0 ? -(int32_t)size : (int32_t)size;
  return b;
}

static VnBig vn_big_neg(VnBig b) { b.count = -b.count; return b; }

static VnBig vn_add_mag(const u32* a, u32 sa, const u32* b, u32 sb) {
  VnBig r;
  u32 n = sa > sb ? sa : sb, carry = 0, sum[VN_CHUNKS + 1];
  for (u32 i = 0; i < n; i++) {
    u64 s = (u64)(i < sa ? a[i] : 0) + (i < sb ? b[i] : 0) + carry;
    sum[i] = (u32)s; carry = (u32)(s >> 32);
  }
  if (carry) sum[n++] = carry;
  r.count = (int32_t)(n < VN_CHUNKS ? n : VN_CHUNKS);
  memcpy(r.c, sum, (size_t)r.count * 4);
  return r;
}

static VnBig vn_dif_body(const u32* a, u32 sa, const u32* b, u32 sb) {
  VnBig r;
  u32 bw = 0;
  for (u32 i = 0; i < sa; i++) {
    u32 x = a[i], y = i < sb ? b[i] : 0;
    r.c[i] = x - y - bw;
    bw = x < y || (x == y && bw);
  }
  r.count = (int32_t)(sa - 1 + (r.c[sa - 1] != 0));
  return r;
}

static VnBig vn_dif_mag(const u32* a, u32 sa, const u32* b, u32 sb) {
  if (sa < sb) return vn_big_neg(vn_dif_body(b, sb, a, sa));
  if (sa > sb) return vn_dif_body(a, sa, b, sb);
  u32 size = sa;
  while (size && a[size - 1] == b[size - 1]) size--;
  if (!size) return vn_big_i32(0);
  return a[size - 1] < b[size - 1] ? vn_big_neg(vn_dif_body(b, size, a, size)) : vn_dif_body(a, size, b, size);
}

static VnBig vn_mul_mag(const u32* a, u32 sa, const u32* b, u32 sb) {
  VnBig r;
  u32 prod[2 * VN_CHUNKS] = {0};
  for (u32 i = 0; i < sa; i++) {
    u64 carry = 0;
    for (u32 j = 0; j < sb; j++) {
      u64 t = (u64)a[i] * b[j] + prod[i + j] + carry;
      prod[i + j] = (u32)t; carry = t >> 32;
    }
    prod[i + sb] = (u32)carry;
  }
  u32 base = sa + sb - 1 < VN_CHUNKS ? sa + sb - 1 : VN_CHUNKS;
  r.count = (int32_t)(base + (base != VN_CHUNKS && prod[base] != 0));
  memcpy(r.c, prod, (size_t)r.count * 4);
  return r;
}

static VnBig vn_big_add(VnBig a, VnBig b) {
  if (!a.count) return b;
  if (!b.count) return a;
  VnBig r = (a.count < 0) != (b.count < 0) ? vn_dif_mag(a.c, vn_big_size(&a), b.c, vn_big_size(&b))
                                            : vn_add_mag(a.c, vn_big_size(&a), b.c, vn_big_size(&b));
  return a.count < 0 ? vn_big_neg(r) : r;
}

static VnBig vn_big_sub(VnBig a, VnBig b) {
  if (!a.count) return vn_big_neg(b);
  if (!b.count) return a;
  VnBig r = (a.count < 0) != (b.count < 0) ? vn_add_mag(a.c, vn_big_size(&a), b.c, vn_big_size(&b))
                                            : vn_dif_mag(a.c, vn_big_size(&a), b.c, vn_big_size(&b));
  return a.count < 0 ? vn_big_neg(r) : r;
}

static VnBig vn_big_mul(VnBig a, VnBig b) {
  if (!a.count || !b.count) return vn_big_i32(0);
  VnBig r = vn_mul_mag(a.c, vn_big_size(&a), b.c, vn_big_size(&b));
  return (a.count < 0) != (b.count < 0) ? vn_big_neg(r) : r;
}

static VnBig vn_big_mul_i32(VnBig a, int32_t x) { return vn_big_mul(a, vn_big_i32(x)); }

static double vn_big_split(const VnBig* b, u32* exp) {
  u32 s = vn_big_size(b);
  double v = 0.0;
  *exp = 0;
  if (s == 1) v = (double)b->c[0];
  else if (s == 2) v = (double)b->c[1] * 4294967296.0 + (double)b->c[0];
  else if (s > 2) {
    v = ((double)b->c[s - 1] * 4294967296.0 + (double)b->c[s - 2]) * 4294967296.0 + (double)b->c[s - 3];
    *exp = (s - 3) << 5;
  }
  return b->count < 0 ? -v : v;
}

static double vn_big_f64(VnBig b) { u32 e; double v = vn_big_split(&b, &e); return vn_ldexp(v, e); }

// extended_exponent_fpt<double>
// -----------------------------

typedef struct { double v; u32 e; } VnEf;

static VnEf vn_ef(double v, u32 e) { u32 k; double m = vn_frexp(v, &k); return (VnEf){m, k + e}; }
static VnEf vn_big_ef(VnBig b) { u32 e; double v = vn_big_split(&b, &e); return vn_ef(v, e); }
static int vn_far_above(u32 e, u32 f) { return (int32_t)(f + 54) < (int32_t)e; }

static VnEf vn_ef_add(VnEf a, VnEf b) {
  if (a.v == 0.0 || vn_far_above(b.e, a.e)) return b;
  if (b.v == 0.0 || vn_far_above(a.e, b.e)) return a;
  return (int32_t)a.e >= (int32_t)b.e ? vn_ef(vn_ldexp(a.v, a.e - b.e) + b.v, b.e) : vn_ef(vn_ldexp(b.v, b.e - a.e) + a.v, a.e);
}

static VnEf vn_ef_sub(VnEf a, VnEf b) {
  if (a.v == 0.0 || vn_far_above(b.e, a.e)) return vn_ef(-b.v, b.e);
  if (b.v == 0.0 || vn_far_above(a.e, b.e)) return a;
  return (int32_t)a.e >= (int32_t)b.e ? vn_ef(vn_ldexp(a.v, a.e - b.e) - b.v, b.e) : vn_ef(vn_ldexp(-b.v, b.e - a.e) + a.v, a.e);
}

static VnEf vn_ef_mul(VnEf a, VnEf b) { return vn_ef(a.v * b.v, a.e + b.e); }
static VnEf vn_ef_div(VnEf a, VnEf b) { return vn_ef(a.v / b.v, a.e - b.e); }

static VnEf vn_ef_sqrt(VnEf a) {
  int odd = a.e & 1;
  u32 e = odd ? a.e - 1 : a.e;
  return vn_ef(sqrt(odd ? a.v * 2.0 : a.v), e >> 1 | (e & 0x80000000u));
}

static double vn_ef_f64(VnEf a) { return vn_ldexp(a.v, a.e); }

static int vn_ef_same_sign(VnEf a, VnEf b) { return (!(a.v < 0.0) && !(b.v < 0.0)) || (!(0.0 < a.v) && !(0.0 < b.v)); }

// robust_fpt, robust_dif and robust_sqrt_expr
// -------------------------------------------

typedef struct { double v, e; } VnRf;
typedef struct { VnRf p, n; } VnRd;

static VnRf vn_rf(double v) { return (VnRf){v, 0.0}; }
static VnRf vn_rfe(double v, double e) { return (VnRf){v, e}; }
static int vn_same_signs(double a, double b) { return (!(a < 0.0) && !(b < 0.0)) || (!(0.0 < a) && !(0.0 < b)); }
static double vn_cancel(double num, double sum) { double t = num / sum; return (t < 0.0 ? -t : t) + 1.0; }

static VnRf vn_rf_add(VnRf a, VnRf b) {
  double s = a.v + b.v;
  return (VnRf){s, vn_same_signs(a.v, b.v) ? vn_max(a.e, b.e) + 1.0 : vn_cancel(a.v * a.e - b.v * b.e, s)};
}

static VnRf vn_rf_sub(VnRf a, VnRf b) {
  double d = a.v - b.v;
  return (VnRf){d, vn_same_signs(a.v, -b.v) ? vn_max(a.e, b.e) + 1.0 : vn_cancel(a.v * a.e + b.v * b.e, d)};
}

static VnRf vn_rf_mul(VnRf a, VnRf b) { return (VnRf){a.v * b.v, (a.e + b.e) + 1.0}; }
static VnRf vn_rf_div(VnRf a, VnRf b) { return (VnRf){a.v / b.v, (a.e + b.e) + 1.0}; }
static VnRf vn_rf_div_assign(VnRf a, VnRf b) { return (VnRf){a.v / b.v, a.e + (b.e + 1.0)}; }
static VnRf vn_rf_sqrt(VnRf a) { return (VnRf){sqrt(a.v), a.e * 0.5 + 1.0}; }
static VnRf vn_rf_neg(VnRf a) { return (VnRf){-a.v, a.e}; }
static int vn_rf_exact(VnRf a) { return 64.0 < a.e; }

static VnRd vn_rd_zero(void) { return (VnRd){{0.0, 0.0}, {0.0, 0.0}}; }
static VnRf vn_rd_dif(VnRd d) { return vn_rf_sub(d.p, d.n); }

static VnRd vn_rd_add_rf(VnRd d, VnRf x) {
  if (!(x.v < 0.0)) d.p = vn_rf_add(d.p, x);
  else d.n = vn_rf_sub(d.n, x);
  return d;
}

static VnRd vn_rd_sub_rf(VnRd d, VnRf x) {
  if (!(x.v < 0.0)) d.n = vn_rf_add(d.n, x);
  else d.p = vn_rf_sub(d.p, x);
  return d;
}

static VnRd vn_rd_add(VnRd a, VnRd b) { return (VnRd){vn_rf_add(a.p, b.p), vn_rf_add(a.n, b.n)}; }
static VnRd vn_rd_sub(VnRd a, VnRd b) { return (VnRd){vn_rf_add(a.p, b.n), vn_rf_add(a.n, b.p)}; }

static VnRd vn_rd_mul_rf(VnRd d, VnRf x) {
  if (!(x.v < 0.0)) return (VnRd){vn_rf_mul(d.p, x), vn_rf_mul(d.n, x)};
  return (VnRd){vn_rf_mul(vn_rf_neg(d.n), x), vn_rf_mul(vn_rf_neg(d.p), x)};
}

static VnRd vn_rf_mul_rd(VnRf x, VnRd d) {
  if (!(x.v < 0.0)) return (VnRd){vn_rf_mul(x, d.p), vn_rf_mul(x, d.n)};
  return (VnRd){vn_rf_mul(vn_rf_neg(x), d.n), vn_rf_mul(vn_rf_neg(x), d.p)};
}

static VnRd vn_rd_div_assign(VnRd d, VnRf x) {
  if (!(x.v < 0.0)) return (VnRd){vn_rf_div_assign(d.p, x), vn_rf_div_assign(d.n, x)};
  return (VnRd){vn_rf_div_assign(d.n, vn_rf_neg(x)), vn_rf_div_assign(d.p, vn_rf_neg(x))};
}

static VnRd vn_rd_positive(VnRd d) { return d.p.v < d.n.v ? (VnRd){d.n, d.p} : d; }
static double vn_rd_value(VnRd d) { return vn_rd_dif(d).v; }
static int vn_rd_exact(VnRd d) { return vn_rf_exact(vn_rd_dif(d)); }

static VnEf vn_eval1(VnBig a0, VnBig b0) { return vn_ef_mul(vn_big_ef(a0), vn_ef_sqrt(vn_big_ef(b0))); }
static VnBig vn_sqr_times(VnBig a, VnBig b) { return vn_big_mul(vn_big_mul(a, a), b); }

static VnEf vn_eval2(VnBig a0, VnBig a1, VnBig b0, VnBig b1) {
  VnEf a = vn_eval1(a0, b0), b = vn_eval1(a1, b1);
  if (vn_ef_same_sign(a, b)) return vn_ef_add(a, b);
  return vn_ef_div(vn_big_ef(vn_big_sub(vn_sqr_times(a0, b0), vn_sqr_times(a1, b1))), vn_ef_sub(a, b));
}

static VnEf vn_eval3(VnBig a0, VnBig a1, VnBig a2, VnBig b0, VnBig b1, VnBig b2) {
  VnEf a = vn_eval2(a0, a1, b0, b1), b = vn_eval1(a2, b2);
  if (vn_ef_same_sign(a, b)) return vn_ef_add(a, b);
  VnBig ta3 = vn_big_sub(vn_big_add(vn_sqr_times(a0, b0), vn_sqr_times(a1, b1)), vn_sqr_times(a2, b2));
  VnBig ta4 = vn_big_mul_i32(vn_big_mul(a0, a1), 2);
  return vn_ef_div(vn_eval2(ta3, ta4, vn_big_i32(1), vn_big_mul(b0, b1)), vn_ef_sub(a, b));
}

static VnEf vn_eval4(VnBig a0, VnBig a1, VnBig a2, VnBig a3, VnBig b0, VnBig b1, VnBig b2, VnBig b3) {
  VnEf a = vn_eval2(a0, a1, b0, b1), b = vn_eval2(a2, a3, b2, b3);
  if (vn_ef_same_sign(a, b)) return vn_ef_add(a, b);
  VnBig ta0 = vn_big_sub(vn_big_sub(vn_big_add(vn_sqr_times(a0, b0), vn_sqr_times(a1, b1)), vn_sqr_times(a2, b2)), vn_sqr_times(a3, b3));
  VnBig ta1 = vn_big_mul_i32(vn_big_mul(a0, a1), 2);
  VnBig ta2 = vn_big_mul_i32(vn_big_mul(a2, a3), -2);
  return vn_ef_div(vn_eval3(ta0, ta1, ta2, vn_big_i32(1), vn_big_mul(b0, b1), vn_big_mul(b2, b3)), vn_ef_sub(a, b));
}

// Sites, circle events and the predicates
// ---------------------------------------

typedef struct { int32_t x, y; } VnPt;
typedef struct { int32_t x0, y0, x1, y1; u32 sorted, initial, flags; } VnSite;
typedef struct { double x, y, lx; } VnCircle;

enum { VN_RIGHT = -1, VN_LEFT = 1, VN_LESS = -1, VN_UNDEFINED = 0, VN_MORE = 1 };

static int vn_is_inverse(VnSite s) { return (s.flags & 32) != 0; }
static VnSite vn_inverse(VnSite s) { s.flags ^= 32; return s; }
static VnSite vn_inverse_if(int c, VnSite s) { return c ? vn_inverse(s) : s; }
static int vn_is_segment(VnSite s) { return s.x0 != s.x1 || s.y0 != s.y1; }
static int vn_is_point(VnSite s) { return !vn_is_segment(s); }
static int vn_is_vertical(VnSite s) { return s.x0 == s.x1; }
static VnPt vn_p0(VnSite s) { return (VnPt){s.x0, s.y0}; }
static VnPt vn_p1(VnSite s) { return (VnPt){s.x1, s.y1}; }
static VnPt vn_start(VnSite s) { return vn_is_inverse(s) ? vn_p1(s) : vn_p0(s); }
static VnPt vn_end(VnSite s) { return vn_is_inverse(s) ? vn_p0(s) : vn_p1(s); }
static int vn_pt_eq(VnPt a, VnPt b) { return a.x == b.x && a.y == b.y; }
static int vn_same_site(VnSite a, VnSite b) { return vn_pt_eq(vn_p0(a), vn_p0(b)) && vn_pt_eq(vn_p1(a), vn_p1(b)); }
static int64_t vn_d(int32_t a, int32_t b) { return (int64_t)a - (int64_t)b; }
static uint64_t vn_mag(int64_t x) { return x < 0 ? 0 - (uint64_t)x : (uint64_t)x; }

static double vn_cross(int64_t a1, int64_t b1, int64_t a2, int64_t b2) {
  uint64_t l = vn_mag(a1) * vn_mag(b2), r = vn_mag(b1) * vn_mag(a2);
  int first = (a1 < 0) ^ (b2 < 0), second = (a2 < 0) ^ (b1 < 0);
  if (first) return second ? (r < l ? -(double)(l - r) : (double)(r - l)) : -(double)(l + r);
  return second ? (double)(l + r) : (l < r ? -(double)(r - l) : (double)(l - r));
}

static int vn_orientation_of(double v) { return v == 0.0 ? 0 : (v < 0.0 ? VN_RIGHT : VN_LEFT); }

static int vn_orientation(VnPt p1, VnPt p2, VnPt p3) {
  return vn_orientation_of(vn_cross(vn_d(p1.x, p2.x), vn_d(p1.y, p2.y), vn_d(p2.x, p3.x), vn_d(p2.y, p3.y)));
}

static int vn_point_less(VnPt a, VnPt b) { return a.x == b.x ? a.y < b.y : a.x < b.x; }

static int vn_site_less(VnSite l, VnSite r) {
  if (l.x0 != r.x0) return l.x0 < r.x0;
  if (vn_is_point(l)) return vn_is_point(r) ? l.y0 < r.y0 : (vn_is_vertical(r) ? l.y0 <= r.y0 : 1);
  if (vn_is_vertical(r)) return vn_is_vertical(l) ? l.y0 < r.y0 : 0;
  if (vn_is_vertical(l)) return 1;
  return l.y0 == r.y0 ? vn_orientation(vn_p1(l), vn_p0(l), vn_p1(r)) == VN_LEFT : l.y0 < r.y0;
}

static int vn_ulp_less(int x, int y) { return x == 0 ? y == -1 : x == -1; }

static int vn_site_before_circle(VnSite s, VnCircle c) {
  return vn_ulp_less(vn_ulp_cmp((double)s.x0, c.lx, 64), vn_ulp_cmp((double)s.y0, c.y, 64));
}

static int vn_circle_less(VnCircle a, VnCircle b) {
  return vn_ulp_less(vn_ulp_cmp(a.lx, b.lx, 128), vn_ulp_cmp(a.y, b.y, 128));
}

static double vn_dist_point_arc(VnSite s, VnPt p) {
  double dx = (double)s.x0 - (double)p.x, dy = (double)s.y0 - (double)p.y;
  return (dx * dx + dy * dy) / (2.0 * dx);
}

static double vn_dist_segment_arc(VnSite s, VnPt p) {
  if (vn_is_vertical(s)) return ((double)s.x0 - (double)p.x) * 0.5;
  VnPt s0 = vn_start(s), s1 = vn_end(s);
  double a1 = (double)s1.x - (double)s0.x, b1 = (double)s1.y - (double)s0.y;
  double k = sqrt(a1 * a1 + b1 * b1);
  double c = vn_cross(vn_d(s1.x, s0.x), vn_d(s1.y, s0.y), vn_d(p.x, s0.x), vn_d(p.y, s0.y));
  return (!(b1 < 0.0) ? 1.0 / (b1 + k) : (k - b1) / (a1 * a1)) * c;
}

static int vn_fast_ps(VnSite left, VnSite right, VnSite fresh, int reverse) {
  VnPt sp = vn_p0(left), ss = vn_start(right), se = vn_end(right), np = vn_p0(fresh);
  if (vn_orientation(ss, se, np) != VN_RIGHT) return vn_is_inverse(right) ? VN_MORE : VN_LESS;
  if (vn_is_vertical(right)) return np.y < sp.y && !reverse ? VN_MORE : (sp.y < np.y && reverse ? VN_LESS : VN_UNDEFINED);
  double dif_x = (double)np.x - (double)sp.x, dif_y = (double)np.y - (double)sp.y;
  double a = (double)se.x - (double)ss.x, b = (double)se.y - (double)ss.y;
  if (vn_orientation_of(vn_cross(vn_d(se.x, ss.x), vn_d(se.y, ss.y), vn_d(np.x, sp.x), vn_d(np.y, sp.y))) == VN_LEFT) {
    if (vn_is_inverse(right)) return reverse ? VN_UNDEFINED : VN_MORE;
    return reverse ? VN_LESS : VN_UNDEFINED;
  }
  double lhs = a * (dif_y + dif_x) * (dif_y - dif_x), rhs = 2.0 * b * dif_x * dif_y;
  int c = vn_ulp_cmp(lhs, rhs, 4);
  return c != 0 && ((c == 1) ^ reverse) ? (reverse ? VN_LESS : VN_MORE) : VN_UNDEFINED;
}

static int vn_ps(VnSite left, VnSite right, VnSite fresh, int reverse) {
  int fast = vn_fast_ps(left, right, fresh, reverse);
  if (fast != VN_UNDEFINED) return fast == VN_LESS;
  return reverse ^ (vn_dist_point_arc(left, vn_p0(fresh)) < vn_dist_segment_arc(right, vn_p0(fresh)));
}

static int vn_pp(VnSite left, VnSite right, VnSite fresh) {
  VnPt lp = vn_p0(left), rp = vn_p0(right), np = vn_p0(fresh);
  if (rp.x < lp.x) { if (np.y <= lp.y) return 0; }
  else if (lp.x < rp.x) { if (rp.y <= np.y) return 1; }
  else return (int64_t)lp.y + (int64_t)rp.y < (int64_t)np.y + (int64_t)np.y;
  return vn_dist_point_arc(left, np) < vn_dist_point_arc(right, np);
}

static int vn_ss(VnSite left, VnSite right, VnSite fresh) {
  if (vn_same_site(left, right)) return vn_orientation(vn_p0(left), vn_p1(left), vn_p0(fresh)) == VN_LEFT;
  return vn_dist_segment_arc(left, vn_p0(fresh)) < vn_dist_segment_arc(right, vn_p0(fresh));
}

static int vn_distance_less(VnSite left, VnSite right, VnSite fresh) {
  if (vn_is_point(left)) return vn_is_point(right) ? vn_pp(left, right, fresh) : vn_ps(left, right, fresh, 0);
  return vn_is_point(right) ? vn_ps(right, left, fresh, 1) : vn_ss(left, right, fresh);
}

typedef struct { int32_t y, tag; } VnYTag;

static VnYTag vn_comparison_y(VnSite l, VnSite r, int is_new) {
  if (l.sorted == r.sorted) return (VnYTag){l.y0, 0};
  if ((int32_t)r.sorted < (int32_t)l.sorted)
    return (VnYTag){!is_new && vn_is_segment(l) && vn_is_vertical(l) ? l.y1 : l.y0, 1};
  return (VnYTag){r.y0, -1};
}

static int vn_node_less(VnSite l1, VnSite r1, VnSite l2, VnSite r2) {
  VnSite site1 = (int32_t)r1.sorted < (int32_t)l1.sorted ? l1 : r1, site2 = (int32_t)r2.sorted < (int32_t)l2.sorted ? l2 : r2;
  if (site1.x0 < site2.x0) return vn_distance_less(l1, r1, site2);
  if (site2.x0 < site1.x0) return !vn_distance_less(l2, r2, site1);
  int32_t k1 = (int32_t)site1.sorted, k2 = (int32_t)site2.sorted;
  if (k1 == k2) {
    VnYTag a = vn_comparison_y(l1, r1, 1), b = vn_comparison_y(l2, r2, 1);
    return a.y < b.y || (a.y == b.y && a.tag < b.tag);
  }
  if (k1 < k2) {
    VnYTag y1 = vn_comparison_y(l1, r1, 0), y2 = vn_comparison_y(l2, r2, 1);
    return y1.y == y2.y ? vn_is_point(site1) && y1.tag < 0 : y1.y < y2.y;
  }
  VnYTag y1 = vn_comparison_y(l1, r1, 1), y2 = vn_comparison_y(l2, r2, 0);
  return y1.y == y2.y ? !vn_is_point(site2) || 0 < y2.tag : y1.y < y2.y;
}

static int vn_exists_ppp(VnSite s1, VnSite s2, VnSite s3) {
  return vn_orientation(vn_p0(s1), vn_p0(s2), vn_p0(s3)) == VN_RIGHT;
}

static int vn_exists_pps(VnSite s1, VnSite s2, VnSite s3, int index) {
  if (index == 2) return !(vn_pt_eq(vn_start(s3), vn_p0(s1)) && vn_pt_eq(vn_end(s3), vn_p0(s2)));
  int o1 = vn_orientation(vn_p0(s1), vn_p0(s2), vn_start(s3)), o2 = vn_orientation(vn_p0(s1), vn_p0(s2), vn_end(s3));
  if (index == 1 && s2.x0 <= s1.x0) return o1 == VN_RIGHT;
  if (index == 3 && s1.x0 <= s2.x0) return o2 == VN_RIGHT;
  return o1 == VN_RIGHT || o2 == VN_RIGHT;
}

static int vn_exists_pss(VnSite s1, VnSite s2, VnSite s3, int index) {
  if (vn_same_site(s2, s3)) return 0;
  if (index != 2) return 1;
  int i2 = vn_is_inverse(s2), i3 = vn_is_inverse(s3);
  int turn = vn_orientation(vn_start(s2), vn_p0(s1), vn_end(s3)) != VN_RIGHT;
  return !(!i2 && i3) && !(!(i2 ^ i3) && turn);
}

static int vn_exists_sss(VnSite s1, VnSite s2, VnSite s3) { return !vn_same_site(s1, s2) && !vn_same_site(s2, s3); }

// mp_circle_formation_functor: the exact recomputation
// ----------------------------------------------------

static VnBig vn_bi(int32_t x) { return vn_big_i32(x); }
static VnBig vn_bdif(int32_t a, int32_t b) { return vn_big_i64(vn_d(a, b)); }
static VnBig vn_bsum(int32_t a, int32_t b) { return vn_big_i64((int64_t)a + (int64_t)b); }
static VnBig vn_bmul(VnBig a, VnBig b) { return vn_big_mul(a, b); }
static VnBig vn_badd(VnBig a, VnBig b) { return vn_big_add(a, b); }
static VnBig vn_bsub(VnBig a, VnBig b) { return vn_big_sub(a, b); }
static VnBig vn_bsqr_sum(VnBig a, VnBig b) { return vn_badd(vn_bmul(a, a), vn_bmul(b, b)); }
static VnBig vn_bflip(int c, VnBig b) { return c ? vn_big_neg(b) : b; }

static VnCircle vn_mp_ppp(VnSite s1, VnSite s2, VnSite s3, VnCircle c, int rcx, int rcy, int rlx) {
  int32_t x1 = s1.x0, y1 = s1.y0, x2 = s2.x0, y2 = s2.y0, x3 = s3.x0, y3 = s3.y0;
  VnBig dx0 = vn_bdif(x1, x2), dx1 = vn_bdif(x2, x3), dy0 = vn_bdif(y1, y2), dy1 = vn_bdif(y2, y3);
  double inv = 0.5 / vn_big_f64(vn_bsub(vn_bmul(dx0, dy1), vn_bmul(dx1, dy0)));
  VnBig n1 = vn_badd(vn_bmul(dx0, vn_bsum(x1, x2)), vn_bmul(dy0, vn_bsum(y1, y2)));
  VnBig n2 = vn_badd(vn_bmul(dx1, vn_bsum(x2, x3)), vn_bmul(dy1, vn_bsum(y2, y3)));
  if (rcx || rlx) {
    VnBig cx = vn_bsub(vn_bmul(n1, dy1), vn_bmul(n2, dy0));
    double x = vn_big_f64(cx) * inv;
    c.x = x;
    if (rlx) {
      VnBig sqr_r = vn_bmul(vn_bmul(vn_bsqr_sum(dx0, dy0), vn_bsqr_sum(dx1, dy1)), vn_bsqr_sum(vn_bdif(x1, x3), vn_bdif(y1, y3)));
      double r = sqrt(vn_big_f64(sqr_r));
      if (!(x < 0.0)) c.lx = inv < 0.0 ? x - r * inv : x + r * inv;
      else c.lx = vn_big_f64(vn_bsub(vn_bmul(cx, cx), sqr_r)) * inv / (vn_big_f64(cx) + r);
    }
  }
  if (rcy) c.y = vn_big_f64(vn_bsub(vn_bmul(n2, dx0), vn_bmul(n1, dx1))) * inv;
  return c;
}

static VnCircle vn_mp_pps(VnSite s1, VnSite s2, VnSite s3, int index, VnCircle c, int rcx, int rcy, int rlx) {
  VnPt st = vn_start(s3), en = vn_end(s3), p1 = vn_p1(s3);
  int32_t x1 = s1.x0, y1 = s1.y0, x2 = s2.x0, y2 = s2.y0;
  VnBig la = vn_bdif(en.y, st.y), lb = vn_bdif(st.x, en.x), vx = vn_bdif(y2, y1), vy = vn_bdif(x1, x2);
  VnBig a = vn_bsub(vn_bmul(la, vn_bdif(x1, p1.x)), vn_bmul(lb, vn_bdif(p1.y, y1)));
  VnBig b = vn_bsub(vn_bmul(la, vn_bdif(x2, p1.x)), vn_bmul(lb, vn_bdif(p1.y, y2)));
  VnBig seg = vn_bsqr_sum(la, lb), sx = vn_bsum(x1, x2), sy = vn_bsum(y1, y2);
  VnBig teta = vn_badd(vn_bmul(la, vx), vn_bmul(lb, vy)), denom = vn_bsub(vn_bmul(vx, lb), vn_bmul(vy, la));
  const double quarter = 0.25;
  if (!denom.count) {
    VnBig ab = vn_badd(a, b);
    VnBig numer = vn_bsub(vn_bmul(teta, teta), vn_bmul(ab, ab)), den = vn_bmul(teta, ab);
    VnBig a0 = vn_badd(vn_big_mul_i32(vn_bmul(den, sx), 2), vn_bmul(numer, vx));
    VnBig a1 = vn_badd(vn_big_mul_i32(vn_bmul(den, ab), 2), vn_bmul(numer, teta));
    VnBig a2 = vn_badd(vn_big_mul_i32(vn_bmul(den, sy), 2), vn_bmul(numer, vy));
    double inv = 1.0 / vn_big_f64(den);
    if (rcx) c.x = quarter * vn_big_f64(a0) * inv;
    if (rcy) c.y = quarter * vn_big_f64(a2) * inv;
    if (rlx) c.lx = quarter * vn_ef_f64(vn_eval2(a0, a1, seg, vn_bi(1))) * inv / sqrt(vn_big_f64(seg));
    return c;
  }
  int middle = index == 2;
  VnBig det = vn_big_mul_i32(vn_bmul(vn_bmul(vn_badd(vn_bmul(teta, teta), vn_bmul(denom, denom)), a), b), 4);
  double inv1 = 1.0 / vn_big_f64(denom), inv = inv1 * inv1;
  VnBig ab = vn_badd(a, b);
  VnBig a0 = vn_badd(vn_bmul(vn_bmul(sx, denom), denom), vn_bmul(vn_bmul(teta, ab), vx)), a1 = vn_bflip(middle, vx);
  VnBig a2 = vn_badd(vn_bmul(vn_bmul(sy, denom), denom), vn_bmul(vn_bmul(teta, ab), vy)), a3 = vn_bflip(middle, vy);
  if (rcx) c.x = 0.5 * vn_ef_f64(vn_eval2(a0, a1, vn_bi(1), det)) * inv;
  if (rcy) c.y = 0.5 * vn_ef_f64(vn_eval2(a2, a3, vn_bi(1), det)) * inv;
  if (rlx) {
    VnBig b2 = vn_bmul(vn_badd(a, b), vn_badd(vn_bmul(denom, denom), vn_bmul(teta, teta)));
    VnEf e = vn_eval4(a0, a1, b2, vn_bflip(middle, teta), vn_bmul(vn_bi(1), seg), vn_bmul(det, seg), vn_bi(1), det);
    c.lx = 0.5 * vn_ef_f64(e) * inv / sqrt(vn_big_f64(seg));
  }
  return c;
}

static VnEf vn_pss3(VnBig a0, VnBig a1, VnBig a2, VnBig a3, VnBig b0, VnBig b1, VnBig b2, VnBig b3) {
  VnEf lh = vn_eval2(a0, a1, b0, b1), rh = vn_eval2(a2, a3, b2, b3);
  if (vn_ef_same_sign(lh, rh)) return vn_ef_add(lh, rh);
  VnBig c0 = vn_bsub(vn_bsub(vn_badd(vn_bmul(vn_bmul(a0, a0), b0), vn_bmul(vn_bmul(a1, a1), b1)), vn_bmul(a2, a2)), vn_bmul(vn_bmul(vn_bmul(a3, a3), b0), b1));
  VnBig c1 = vn_big_mul_i32(vn_bsub(vn_bmul(a0, a1), vn_bmul(a2, a3)), 2);
  return vn_ef_div(vn_eval2(c0, c1, vn_bi(1), b3), vn_ef_sub(lh, rh));
}

static VnEf vn_pss4(VnBig a0, VnBig a1, VnBig a2, VnBig a3, VnBig b0, VnBig b1, VnBig b2, VnBig b3) {
  VnEf rh = vn_ef_mul(vn_eval1(a2, b3), vn_ef_sqrt(vn_eval2(vn_bi(1), b2, vn_bmul(b0, b1), vn_bi(1))));
  if (!a3.count) {
    VnEf lh = vn_eval2(a0, a1, b0, b1);
    if (vn_ef_same_sign(lh, rh)) return vn_ef_add(lh, rh);
    VnBig c0 = vn_bsub(vn_badd(vn_bmul(vn_bmul(a0, a0), b0), vn_bmul(vn_bmul(a1, a1), b1)), vn_bmul(vn_bmul(vn_bmul(a2, a2), b3), b2));
    VnBig c1 = vn_bsub(vn_big_mul_i32(vn_bmul(a0, a1), 2), vn_bmul(vn_bmul(a2, a2), b3));
    return vn_ef_div(vn_eval2(c0, c1, vn_bi(1), vn_bmul(b0, b1)), vn_ef_sub(lh, rh));
  }
  VnEf lh = vn_eval3(a0, a1, a3, b0, b1, vn_bi(1));
  if (vn_ef_same_sign(lh, rh)) return vn_ef_add(lh, rh);
  VnBig c0 = vn_big_mul_i32(vn_bmul(a3, a0), 2), c1 = vn_big_mul_i32(vn_bmul(a3, a1), 2);
  VnBig c2 = vn_bsub(vn_badd(vn_badd(vn_bmul(vn_bmul(a0, a0), b0), vn_bmul(vn_bmul(a1, a1), b1)), vn_bmul(a3, a3)), vn_bmul(vn_bmul(vn_bmul(a2, a2), b2), b3));
  VnBig c3 = vn_bsub(vn_big_mul_i32(vn_bmul(a0, a1), 2), vn_bmul(vn_bmul(a2, a2), b3));
  return vn_ef_div(vn_pss3(c0, c1, c2, c3, b0, b1, vn_bi(1), vn_bmul(b0, b1)), vn_ef_sub(lh, rh));
}

static VnBig vn_pss_numer(VnBig along, VnBig i, VnBig dx, VnBig dy, VnBig ea, VnBig eb) {
  return vn_bsub(vn_bmul(along, vn_bsqr_sum(dx, dy)), vn_bmul(i, vn_badd(vn_bmul(dx, ea), vn_bmul(dy, eb))));
}

static VnCircle vn_mp_pss(VnSite s1, VnSite s2, VnSite s3, int index, VnCircle c, int rcx, int rcy, int rlx) {
  VnPt st1 = vn_end(s2), en1 = vn_start(s2), st2 = vn_start(s3), en2 = vn_end(s3);
  VnBig a0 = vn_bdif(en1.x, st1.x), b0 = vn_bdif(en1.y, st1.y), a1 = vn_bdif(en2.x, st2.x), b1 = vn_bdif(en2.y, st2.y);
  VnBig orientation = vn_bsub(vn_bmul(a1, b0), vn_bmul(a0, b1));
  int second = index == 2;
  int32_t x = s1.x0, y = s1.y0;
  if (!orientation.count) {
    double denom = 2.0 * vn_big_f64(vn_bsqr_sum(a0, b0));
    VnBig c0 = vn_bsub(vn_bmul(b0, vn_bdif(st2.x, st1.x)), vn_bmul(a0, vn_bdif(st2.y, st1.y)));
    VnBig dx = vn_bsub(vn_bmul(a0, vn_bdif(y, st1.y)), vn_bmul(b0, vn_bdif(x, st1.x)));
    VnBig dy = vn_bsub(vn_bmul(b0, vn_bdif(x, st2.x)), vn_bmul(a0, vn_bdif(y, st2.y)));
    VnBig cb0 = vn_bmul(dx, dy);
    if (rcy) {
      VnBig ca0 = vn_big_mul_i32(b0, second ? 2 : -2);
      VnBig ya = vn_bmul(vn_bmul(a0, a0), vn_bsum(st1.y, st2.y));
      VnBig yb = vn_bmul(vn_bmul(a0, b0), vn_big_i64(((int64_t)st1.x + st2.x) - ((int64_t)x + x)));
      VnBig yc = vn_bmul(vn_bmul(b0, b0), vn_big_i64((int64_t)y + y));
      c.y = vn_ef_f64(vn_eval2(ca0, vn_badd(vn_bsub(ya, yb), yc), cb0, vn_bi(1))) / denom;
    }
    if (rcx || rlx) {
      VnBig ca0 = vn_big_mul_i32(a0, second ? 2 : -2);
      VnBig xa = vn_bmul(vn_bmul(b0, b0), vn_bsum(st1.x, st2.x));
      VnBig xb = vn_bmul(vn_bmul(a0, b0), vn_big_i64(((int64_t)st1.y + st2.y) - ((int64_t)y + y)));
      VnBig xc = vn_bmul(vn_bmul(a0, a0), vn_big_i64((int64_t)x + x));
      VnBig ca1 = vn_badd(vn_bsub(xa, xb), xc);
      if (rcx) c.x = vn_ef_f64(vn_eval2(ca0, ca1, cb0, vn_bi(1))) / denom;
      if (rlx) {
        VnBig ca2 = vn_bflip(c0.count < 0, c0);
        c.lx = vn_ef_f64(vn_eval3(ca0, ca1, ca2, cb0, vn_bi(1), vn_bsqr_sum(a0, b0))) / denom;
      }
    }
    return c;
  }
  VnBig c0 = vn_bsub(vn_big_mul_i32(b0, en1.x), vn_big_mul_i32(a0, en1.y));
  VnBig c1 = vn_bsub(vn_big_mul_i32(a1, en2.y), vn_big_mul_i32(b1, en2.x));
  VnBig ix = vn_badd(vn_bmul(a0, c1), vn_bmul(a1, c0)), iy = vn_badd(vn_bmul(b0, c1), vn_bmul(b1, c0));
  VnBig dx = vn_bsub(ix, vn_big_mul_i32(orientation, x)), dy = vn_bsub(iy, vn_big_mul_i32(orientation, y));
  if (!dx.count && !dy.count) {
    double denom = vn_big_f64(orientation), cx = vn_big_f64(ix) / denom;
    return (VnCircle){cx, vn_big_f64(iy) / denom, cx};
  }
  VnBig sign = vn_bi((int32_t)((u32)(second ? 1 : -1) * (u32)(orientation.count < 0 ? 1 : -1)));
  VnBig b3 = vn_big_mul_i32(vn_bmul(vn_bsub(vn_bmul(a0, dy), vn_bmul(b0, dx)), vn_bsub(vn_bmul(a1, dy), vn_bmul(b1, dx))), -2);
  VnBig bb0 = vn_bsqr_sum(a0, b0), bb1 = vn_bsqr_sum(a1, b1), bb2 = vn_badd(vn_bmul(a0, a1), vn_bmul(b0, b1));
  VnBig ca0 = vn_badd(vn_bmul(a1, vn_big_neg(dx)), vn_bmul(b1, vn_big_neg(dy)));
  VnBig ca1 = vn_badd(vn_bmul(a0, vn_big_neg(dx)), vn_bmul(b0, vn_big_neg(dy)));
  double temp = vn_ef_f64(vn_pss4(ca0, ca1, sign, vn_bi(0), bb0, bb1, bb2, b3));
  double denom = temp * vn_big_f64(orientation);
  if (rcy) {
    VnBig ya0 = vn_pss_numer(b1, iy, dx, dy, a1, b1), ya1 = vn_pss_numer(b0, iy, dx, dy, a0, b0);
    c.y = vn_ef_f64(vn_pss4(ya0, ya1, vn_bmul(iy, sign), vn_bi(0), bb0, bb1, bb2, b3)) / denom;
  }
  if (rcx || rlx) {
    VnBig xa0 = vn_pss_numer(a1, ix, dx, dy, a1, b1), xa1 = vn_pss_numer(a0, ix, dx, dy, a0, b0), xa2 = vn_bmul(ix, sign);
    if (rcx) c.x = vn_ef_f64(vn_pss4(xa0, xa1, xa2, vn_bi(0), bb0, bb1, bb2, b3)) / denom;
    if (rlx) {
      VnBig xa3 = vn_big_mul_i32(vn_bmul(orientation, vn_bsqr_sum(dx, dy)), temp < 0.0 ? -1 : 1);
      c.lx = vn_ef_f64(vn_pss4(xa0, xa1, xa2, xa3, bb0, bb1, bb2, b3)) / denom;
    }
  }
  return c;
}

typedef struct { VnBig a, b, c; } VnLine;

static VnLine vn_sss_line(VnSite s) {
  VnPt st = vn_start(s), en = vn_end(s);
  uint64_t c = (uint64_t)((int64_t)st.x) * (uint64_t)((int64_t)en.y) - (uint64_t)((int64_t)st.y) * (uint64_t)((int64_t)en.x);
  return (VnLine){vn_bdif(en.x, st.x), vn_bdif(en.y, st.y), vn_big_i64((int64_t)c)};
}

static VnBig vn_cross_ab(VnLine j, VnLine k) { return vn_bsub(vn_bmul(j.a, k.b), vn_bmul(k.a, j.b)); }
static VnBig vn_cross_bc(VnLine j, VnLine k) { return vn_bsub(vn_bmul(j.b, k.c), vn_bmul(k.b, j.c)); }
static VnBig vn_cross_ac(VnLine j, VnLine k) { return vn_bsub(vn_bmul(j.a, k.c), vn_bmul(k.a, j.c)); }
static VnBig vn_line_len(VnLine l) { return vn_bsqr_sum(l.a, l.b); }

static VnCircle vn_mp_sss(VnSite s1, VnSite s2, VnSite s3, VnCircle c, int rcx, int rcy, int rlx) {
  VnLine l0 = vn_sss_line(s1), l1 = vn_sss_line(s2), l2 = vn_sss_line(s3);
  double denom = vn_ef_f64(vn_eval3(vn_cross_ab(l1, l2), vn_cross_ab(l2, l0), vn_cross_ab(l0, l1), vn_line_len(l0), vn_line_len(l1), vn_line_len(l2)));
  if (rcy) {
    VnEf e = vn_eval3(vn_cross_bc(l1, l2), vn_cross_bc(l2, l0), vn_cross_bc(l0, l1), vn_line_len(l0), vn_line_len(l1), vn_line_len(l2));
    c.y = vn_ef_f64(e) / denom;
  }
  if (rcx || rlx) {
    VnBig a0 = vn_cross_ac(l1, l2), a1 = vn_cross_ac(l2, l0), a2 = vn_cross_ac(l0, l1);
    if (rcx) c.x = vn_ef_f64(vn_eval3(a0, a1, a2, vn_line_len(l0), vn_line_len(l1), vn_line_len(l2))) / denom;
    if (rlx) {
      VnBig a3 = vn_badd(vn_badd(vn_badd(vn_bi(0), vn_bmul(a0, l0.b)), vn_bmul(a1, l1.b)), vn_bmul(a2, l2.b));
      c.lx = vn_ef_f64(vn_eval4(a0, a1, a2, a3, vn_line_len(l0), vn_line_len(l1), vn_line_len(l2), vn_bi(1))) / denom;
    }
  }
  return c;
}

// lazy_circle_formation_functor and circle_formation_predicate
// ------------------------------------------------------------

static double vn_triple(double a, double b, double c) { return a * b * c; }
static double vn_sqr_sum(double a, double b) { return a * a + b * b; }

static VnCircle vn_lazy_finish(VnRd cx, VnRd cy, VnRd lx, int* rcx, int* rcy, int* rlx) {
  *rcx = vn_rd_exact(cx); *rcy = vn_rd_exact(cy); *rlx = vn_rd_exact(lx);
  return (VnCircle){vn_rd_value(cx), vn_rd_value(cy), vn_rd_value(lx)};
}

static VnCircle vn_lazy_ppp(VnSite s1, VnSite s2, VnSite s3) {
  int32_t x1 = s1.x0, y1 = s1.y0, x2 = s2.x0, y2 = s2.y0, x3 = s3.x0, y3 = s3.y0;
  double dx1 = (double)x1 - (double)x2, dx2 = (double)x2 - (double)x3, dy1 = (double)y1 - (double)y2, dy2 = (double)y2 - (double)y3;
  double inv = 0.5 / vn_cross(vn_d(x1, x2), vn_d(x2, x3), vn_d(y1, y2), vn_d(y2, y3));
  double sx1 = (double)x1 + (double)x2, sx2 = (double)x2 + (double)x3, sy1 = (double)y1 + (double)y2, sy2 = (double)y2 + (double)y3;
  double dx3 = (double)x1 - (double)x3, dy3 = (double)y1 - (double)y3;
  VnRd cx = vn_rd_add_rf(vn_rd_zero(), vn_rfe(vn_triple(dx1, sx1, dy2), 2.0));
  cx = vn_rd_add_rf(cx, vn_rfe(vn_triple(dy1, sy1, dy2), 2.0));
  cx = vn_rd_sub_rf(cx, vn_rfe(vn_triple(dx2, sx2, dy1), 2.0));
  cx = vn_rd_sub_rf(cx, vn_rfe(vn_triple(dy2, sy2, dy1), 2.0));
  VnRd cy = vn_rd_add_rf(vn_rd_zero(), vn_rfe(vn_triple(dx2, sx2, dx1), 2.0));
  cy = vn_rd_add_rf(cy, vn_rfe(vn_triple(dy2, sy2, dx1), 2.0));
  cy = vn_rd_sub_rf(cy, vn_rfe(vn_triple(dx1, sx1, dx2), 2.0));
  cy = vn_rd_sub_rf(cy, vn_rfe(vn_triple(dy1, sy1, dx2), 2.0));
  VnRd lx = vn_rd_sub_rf(cx, vn_rfe(sqrt(vn_triple(vn_sqr_sum(dx1, dy1), vn_sqr_sum(dx2, dy2), vn_sqr_sum(dx3, dy3))), 5.0));
  int rcx = vn_rd_exact(cx), rcy = vn_rd_exact(cy), rlx = vn_rd_exact(lx);
  VnCircle c = {vn_rd_value(cx) * inv, vn_rd_value(cy) * inv, vn_rd_value(lx) * inv};
  return rcx || rcy || rlx ? vn_mp_ppp(s1, s2, s3, c, rcx, rcy, rlx) : c;
}

static VnCircle vn_lazy_pps(VnSite s1, VnSite s2, VnSite s3, int index) {
  VnPt st = vn_start(s3), en = vn_end(s3), p1 = vn_p1(s3);
  int32_t x1 = s1.x0, y1 = s1.y0, x2 = s2.x0, y2 = s2.y0;
  double la = (double)en.y - (double)st.y, lb = (double)st.x - (double)en.x;
  double vx = (double)y2 - (double)y1, vy = (double)x1 - (double)x2;
  int64_t ila = vn_d(en.y, st.y), ilb = vn_d(st.x, en.x);
  VnRf teta = vn_rfe(vn_cross(ila, ilb, vn_d(x2, x1), vn_d(y2, y1)), 1.0);
  VnRf a = vn_rfe(vn_cross(ila, ilb, vn_d(p1.y, y1), vn_d(x1, p1.x)), 1.0);
  VnRf b = vn_rfe(vn_cross(ila, ilb, vn_d(p1.y, y2), vn_d(x2, p1.x)), 1.0);
  VnRf denom = vn_rfe(vn_cross(vn_d(y2, y1), vn_d(x1, x2), ila, ilb), 1.0);
  VnRf inv_len = vn_rfe(1.0 / sqrt(vn_sqr_sum(la, lb)), 3.0);
  VnRd t;
  if (denom.v == 0.0) {
    t = vn_rd_add_rf(vn_rd_zero(), vn_rf_div(teta, vn_rf_mul(vn_rf(8.0), a)));
    t = vn_rd_sub_rf(t, vn_rf_div(a, vn_rf_mul(vn_rf(2.0), teta)));
  } else {
    VnRf det = vn_rf_sqrt(vn_rf_mul(vn_rf_mul(vn_rf_add(vn_rf_mul(teta, teta), vn_rf_mul(denom, denom)), a), b));
    VnRf q = vn_rf_div(det, vn_rf_mul(denom, denom));
    t = index == 2 ? vn_rd_sub_rf(vn_rd_zero(), q) : vn_rd_add_rf(vn_rd_zero(), q);
    t = vn_rd_add_rf(t, vn_rf_div(vn_rf_mul(teta, vn_rf_add(a, b)), vn_rf_mul(vn_rf_mul(vn_rf(2.0), denom), denom)));
  }
  VnRd cx = vn_rd_add(vn_rd_add_rf(vn_rd_zero(), vn_rf(0.5 * ((double)x1 + (double)x2))), vn_rf_mul_rd(vn_rf(vx), t));
  VnRd cy = vn_rd_add(vn_rd_add_rf(vn_rd_zero(), vn_rf(0.5 * ((double)y1 + (double)y2))), vn_rf_mul_rd(vn_rf(vy), t));
  VnRd r = vn_rd_sub_rf(vn_rd_zero(), vn_rf_mul(vn_rf(la), vn_rf((double)s3.x0)));
  r = vn_rd_sub_rf(r, vn_rf_mul(vn_rf(lb), vn_rf((double)s3.y0)));
  r = vn_rd_add(r, vn_rf_mul_rd(vn_rf(la), cx));
  r = vn_rd_positive(vn_rd_add(r, vn_rf_mul_rd(vn_rf(lb), cy)));
  VnRd lx = vn_rd_add(cx, vn_rd_mul_rf(r, inv_len));
  int rcx, rcy, rlx;
  VnCircle c = vn_lazy_finish(cx, cy, lx, &rcx, &rcy, &rlx);
  return rcx || rcy || rlx ? vn_mp_pps(s1, s2, s3, index, c, rcx, rcy, rlx) : c;
}

static VnRd vn_pss_centre(VnRd i, VnRd t, double f1, double f2, VnRf q1, VnRf q2) {
  return vn_rd_add(vn_rd_add(i, vn_rd_mul_rf(t, vn_rf_mul(vn_rf(f1), q2))), vn_rd_mul_rf(t, vn_rf_mul(vn_rf(f2), q1)));
}

static VnCircle vn_lazy_pss(VnSite s1, VnSite s2, VnSite s3, int index) {
  VnPt st1 = vn_end(s2), en1 = vn_start(s2), st2 = vn_start(s3), en2 = vn_end(s3);
  VnRf orientation = vn_rfe(vn_cross(vn_d(en1.y, st1.y), vn_d(en1.x, st1.x), vn_d(en2.y, st2.y), vn_d(en2.x, st2.x)), 1.0);
  int32_t x = s1.x0, y = s1.y0;
  int64_t e1x = vn_d(en1.x, st1.x), e1y = vn_d(en1.y, st1.y);
  double a1 = (double)en1.x - (double)st1.x, b1 = (double)en1.y - (double)st1.y;
  VnRd cx, cy, lx;
  if (orientation.v == 0.0) {
    VnRf a = vn_rfe(vn_sqr_sum(a1, b1), 2.0);
    VnRf c = vn_rfe(vn_cross(e1y, e1x, vn_d(st2.y, st1.y), vn_d(st2.x, st1.x)), 1.0);
    VnRf det = vn_rfe(vn_cross(e1x, e1y, vn_d(x, st1.x), vn_d(y, st1.y)) * vn_cross(e1y, e1x, vn_d(y, st2.y), vn_d(x, st2.x)), 3.0);
    double mx = ((double)st1.x + (double)st2.x) * 0.5 - (double)x, my = ((double)st1.y + (double)st2.y) * 0.5 - (double)y;
    VnRd t = vn_rd_sub_rf(vn_rd_sub_rf(vn_rd_zero(), vn_rf_mul(vn_rf(a1), vn_rf(mx))), vn_rf_mul(vn_rf(b1), vn_rf(my)));
    t = index == 2 ? vn_rd_add_rf(t, vn_rf_sqrt(det)) : vn_rd_sub_rf(t, vn_rf_sqrt(det));
    t = vn_rd_div_assign(t, a);
    cx = vn_rd_add(vn_rd_add_rf(vn_rd_zero(), vn_rf(0.5 * ((double)st1.x + (double)st2.x))), vn_rf_mul_rd(vn_rf(a1), t));
    cy = vn_rd_add(vn_rd_add_rf(vn_rd_zero(), vn_rf(0.5 * ((double)st1.y + (double)st2.y))), vn_rf_mul_rd(vn_rf(b1), t));
    VnRf shift = vn_rf_div(vn_rf_mul(vn_rf(0.5), c), vn_rf_sqrt(a));
    lx = c.v < 0.0 ? vn_rd_sub_rf(cx, shift) : vn_rd_add_rf(cx, shift);
  } else {
    int64_t e2x = vn_d(en2.x, st2.x), e2y = vn_d(en2.y, st2.y);
    double a2 = (double)en2.x - (double)st2.x, b2 = (double)en2.y - (double)st2.y;
    VnRf q1 = vn_rfe(sqrt(vn_sqr_sum(a1, b1)), 2.0), q2 = vn_rfe(sqrt(vn_sqr_sum(a2, b2)), 2.0);
    VnRf a0 = vn_rfe(vn_cross(e1x, e1y, vn_d(st2.y, en2.y), e2x), 1.0);
    VnRf a = !(a0.v < 0.0) ? vn_rf_add(a0, vn_rf_mul(q1, q2)) : vn_rf_div(vn_rf_mul(orientation, orientation), vn_rf_sub(vn_rf_mul(q1, q2), a0));
    VnRf or1 = vn_rfe(vn_cross(e1y, e1x, vn_d(en1.y, y), vn_d(en1.x, x)), 1.0);
    VnRf or2 = vn_rfe(vn_cross(e2x, e2y, vn_d(en2.x, x), vn_d(en2.y, y)), 1.0);
    VnRf det = vn_rf_mul(vn_rf_mul(vn_rf_mul(vn_rf(2.0), a), or1), or2);
    VnRf c1 = vn_rfe(vn_cross(e1y, e1x, en1.y, en1.x), 1.0);
    VnRf c2 = vn_rfe(vn_cross(e2x, e2y, en2.x, en2.y), 1.0);
    VnRf inv = vn_rf_div(vn_rf(1.0), orientation);
    VnRd ix = vn_rd_add_rf(vn_rd_add_rf(vn_rd_zero(), vn_rf_mul(vn_rf_mul(vn_rf(a2), c1), inv)), vn_rf_mul(vn_rf_mul(vn_rf(a1), c2), inv));
    VnRd iy = vn_rd_add_rf(vn_rd_add_rf(vn_rd_zero(), vn_rf_mul(vn_rf_mul(vn_rf(b1), c2), inv)), vn_rf_mul(vn_rf_mul(vn_rf(b2), c1), inv));
    VnRf k1 = vn_rfe(vn_cross(e2x, e2y, (int64_t)(int32_t)(0u - (u32)y), x), 1.0);
    VnRf k2 = vn_rfe(vn_cross(e1x, e1y, (int64_t)(int32_t)(0u - (u32)y), x), 1.0);
    VnRd bs = vn_rd_add(vn_rd_zero(), vn_rd_mul_rf(ix, vn_rf_mul(vn_rf(a1), q2)));
    bs = vn_rd_add(bs, vn_rd_mul_rf(ix, vn_rf_mul(vn_rf(a2), q1)));
    bs = vn_rd_add(bs, vn_rd_mul_rf(iy, vn_rf_mul(vn_rf(b1), q2)));
    bs = vn_rd_add(bs, vn_rd_mul_rf(iy, vn_rf_mul(vn_rf(b2), q1)));
    bs = vn_rd_sub_rf(vn_rd_sub_rf(bs, vn_rf_mul(q1, k1)), vn_rf_mul(q2, k2));
    VnRd t = vn_rd_sub(vn_rd_zero(), bs);
    t = index == 2 ? vn_rd_add_rf(t, vn_rf_sqrt(det)) : vn_rd_sub_rf(t, vn_rf_sqrt(det));
    t = vn_rd_div_assign(t, vn_rf_mul(a, a));
    cx = vn_pss_centre(ix, t, a1, a2, q1, q2);
    cy = vn_pss_centre(iy, t, b1, b2, q1, q2);
    VnRd tp = vn_rd_positive(t);
    lx = orientation.v < 0.0 ? vn_rd_sub(cx, vn_rd_mul_rf(tp, orientation)) : vn_rd_add(cx, vn_rd_mul_rf(tp, orientation));
  }
  int rcx, rcy, rlx;
  VnCircle c = vn_lazy_finish(cx, cy, lx, &rcx, &rcy, &rlx);
  return rcx || rcy || rlx ? vn_mp_pss(s1, s2, s3, index, c, rcx, rcy, rlx) : c;
}

typedef struct { VnRf a, b, c, len; int64_t dx, dy; } VnSeg;

static VnSeg vn_sss_seg(VnSite s) {
  VnPt st = vn_start(s), en = vn_end(s);
  VnRf a = vn_rf((double)en.x - (double)st.x), b = vn_rf((double)en.y - (double)st.y);
  VnRf c = vn_rfe(vn_cross(st.x, st.y, en.x, en.y), 1.0);
  return (VnSeg){a, b, c, vn_rf_sqrt(vn_rf_add(vn_rf_mul(a, a), vn_rf_mul(b, b))), vn_d(en.x, st.x), vn_d(en.y, st.y)};
}

static VnRf vn_seg_cross(VnSeg p, VnSeg q) { return vn_rfe(vn_cross(p.dx, p.dy, q.dx, q.dy), 1.0); }
static VnRf vn_term(VnRf x, VnRf y, VnRf z) { return vn_rf_mul(vn_rf_mul(x, y), z); }

static VnRd vn_sss_centre(VnRf f1, VnRf f2, VnRf f3, VnSeg p1, VnSeg p2, VnSeg p3) {
  VnRd s = vn_rd_add_rf(vn_rd_zero(), vn_term(f1, p2.c, p3.len));
  s = vn_rd_sub_rf(s, vn_term(f2, p1.c, p3.len));
  s = vn_rd_add_rf(s, vn_term(f2, p3.c, p1.len));
  s = vn_rd_sub_rf(s, vn_term(f3, p2.c, p1.len));
  s = vn_rd_add_rf(s, vn_term(f3, p1.c, p2.len));
  return vn_rd_sub_rf(s, vn_term(f1, p3.c, p2.len));
}

static VnCircle vn_lazy_sss(VnSite s1, VnSite s2, VnSite s3) {
  VnSeg p1 = vn_sss_seg(s1), p2 = vn_sss_seg(s2), p3 = vn_sss_seg(s3);
  VnRf x12 = vn_seg_cross(p1, p2), x23 = vn_seg_cross(p2, p3), x31 = vn_seg_cross(p3, p1);
  VnRd denom = vn_rd_add_rf(vn_rd_add_rf(vn_rd_add_rf(vn_rd_zero(), vn_rf_mul(x12, p3.len)), vn_rf_mul(x23, p1.len)), vn_rf_mul(x31, p2.len));
  VnRd r = vn_rd_sub_rf(vn_rd_sub_rf(vn_rd_sub_rf(vn_rd_zero(), vn_rf_mul(x12, p3.c)), vn_rf_mul(x23, p1.c)), vn_rf_mul(x31, p2.c));
  VnRd cx = vn_sss_centre(p1.a, p2.a, p3.a, p1, p2, p3), cy = vn_sss_centre(p1.b, p2.b, p3.b, p1, p2, p3);
  VnRf dd = vn_rd_dif(denom);
  VnRf cxd = vn_rf_div(vn_rd_dif(cx), dd), cyd = vn_rf_div(vn_rd_dif(cy), dd), lxd = vn_rf_div(vn_rd_dif(vn_rd_add(cx, r)), dd);
  int rcx = vn_rf_exact(cxd), rcy = vn_rf_exact(cyd), rlx = vn_rf_exact(lxd);
  VnCircle c = {cxd.v, cyd.v, lxd.v};
  return rcx || rcy || rlx ? vn_mp_sss(s1, s2, s3, c, rcx, rcy, rlx) : c;
}

static int vn_circle_formation(VnSite s1, VnSite s2, VnSite s3, VnCircle* c) {
  int p1 = vn_is_point(s1), p2 = vn_is_point(s2), p3 = vn_is_point(s3);
  if (p1 && p2 && p3) { if (!vn_exists_ppp(s1, s2, s3)) return 0; *c = vn_lazy_ppp(s1, s2, s3); return 1; }
  if (p1 && p2) { if (!vn_exists_pps(s1, s2, s3, 3)) return 0; *c = vn_lazy_pps(s1, s2, s3, 3); return 1; }
  if (p1 && p3) { if (!vn_exists_pps(s1, s3, s2, 2)) return 0; *c = vn_lazy_pps(s1, s3, s2, 2); return 1; }
  if (p1) { if (!vn_exists_pss(s1, s2, s3, 1)) return 0; *c = vn_lazy_pss(s1, s2, s3, 1); return 1; }
  if (p2 && p3) { if (!vn_exists_pps(s2, s3, s1, 1)) return 0; *c = vn_lazy_pps(s2, s3, s1, 1); return 1; }
  if (p2) { if (!vn_exists_pss(s2, s1, s3, 2)) return 0; *c = vn_lazy_pss(s2, s1, s3, 2); return 1; }
  if (p3) { if (!vn_exists_pss(s3, s1, s2, 3)) return 0; *c = vn_lazy_pss(s3, s1, s2, 3); return 1; }
  if (!vn_exists_sss(s1, s2, s3)) return 0;
  *c = vn_lazy_sss(s1, s2, s3);
  return 1;
}

// std::sort (libstdc++ and VC9) and the heap algorithms over handles, with the Bend port's scan budgets
// -----------------------------------------------------------------------------------------------------

typedef struct { VnCircle c; int active; u32 node; } VnEvent;

typedef struct VnOrder VnOrder;
struct VnOrder {
  u32* items;
  u32 mask;
  int (*lt)(VnOrder* o, u32 a, u32 b);
  const VnSite* sites;
  const VnEvent* events;
  u32 dmask;
};

#define VN_AT(o, i) ((o)->items[(i) & (o)->mask])

static int vn_lt_at(VnOrder* o, u32 i, u32 j) { return o->lt(o, VN_AT(o, i), VN_AT(o, j)); }
static void vn_swap(VnOrder* o, u32 i, u32 j) { u32 vi = VN_AT(o, i), vj = VN_AT(o, j); VN_AT(o, i) = vj; VN_AT(o, j) = vi; }

static void vn_push_hole(VnOrder* o, u32 first, u32 hole, u32 top, u32 value) {
  for (int n = 34; n > 0 && hole > top; n--) {
    u32 parent = (hole - 1) >> 1, above = VN_AT(o, first + parent);
    if (!o->lt(o, above, value)) break;
    VN_AT(o, first + hole) = above;
    hole = parent;
  }
  VN_AT(o, first + hole) = value;
}

static void vn_adjust(VnOrder* o, u32 first, u32 hole, u32 len, u32 value) {
  u32 top = hole, limit = (len - 1) >> 1;
  for (int n = 34; n > 0 && hole < limit; n--) {
    u32 child = (hole + 1) << 1, right = VN_AT(o, first + child), left = VN_AT(o, first + child - 1);
    int take_left = o->lt(o, right, left);
    VN_AT(o, first + hole) = take_left ? left : right;
    hole = take_left ? child - 1 : child;
  }
  if ((len & 1) == 0 && hole == (len - 2) >> 1) {
    VN_AT(o, first + hole) = VN_AT(o, first + (hole << 1) + 1);
    hole = (hole << 1) + 1;
  }
  vn_push_hole(o, first, hole, top, value);
}

static void vn_push_heap(VnOrder* o, u32 first, u32 last) { vn_push_hole(o, first, last - first - 1, 0, VN_AT(o, last - 1)); }

static void vn_pop_heap(VnOrder* o, u32 first, u32 last) {
  if (last - first <= 1) return;
  u32 value = VN_AT(o, last - 1);
  VN_AT(o, last - 1) = VN_AT(o, first);
  vn_adjust(o, first, 0, last - 1 - first, value);
}

static void vn_heap_sort(VnOrder* o, u32 first, u32 last) {
  u32 len = last - first, parents = len >= 2 ? ((len - 2) >> 1) + 1 : 0;
  for (u32 parent = parents - 1, k = 0; k < parents; k++, parent--) vn_adjust(o, first, parent, len, VN_AT(o, first + parent));
  for (u32 k = len >= 2 ? len - 1 : 0; k > 0; k--, last--) vn_pop_heap(o, first, last);
}

static void vn_linear_insert(VnOrder* o, u32 hole, u32 value, u32 fuel) {
  for (; fuel > 0; fuel--) {
    u32 below = VN_AT(o, hole - 1);
    if (!o->lt(o, value, below)) break;
    VN_AT(o, hole) = below;
    hole--;
  }
  VN_AT(o, hole) = value;
}

static void vn_insertion_sort(VnOrder* o, u32 first, u32 last) {
  u32 count = last - first;
  for (u32 i = first + 1, k = count >= 2 ? count - 1 : 0; k > 0; k--, i++) {
    u32 value = VN_AT(o, i);
    if (o->lt(o, value, VN_AT(o, first))) {
      for (u32 j = i; j > first; j--) VN_AT(o, j) = VN_AT(o, j - 1);
      VN_AT(o, first) = value;
    } else vn_linear_insert(o, i, value, count + 2);
  }
}

static u32 vn_floor_log2(u32 x) { u32 e = 0; for (int k = 0; k < 32; k++, x >>= 1) e += x >= 2; return e; }

static u32 vn_scan(VnOrder* o, u32 index, u32 pivot, int up, u32 fuel) {
  int hit = up ? o->lt(o, VN_AT(o, index), pivot) : o->lt(o, pivot, VN_AT(o, index));
  for (; fuel > 0 && hit; fuel--) {
    index = up ? index + 1 : index - 1;
    hit = up ? o->lt(o, VN_AT(o, index), pivot) : o->lt(o, pivot, VN_AT(o, index));
  }
  return index;
}

static void vn_move_median(VnOrder* o, u32 first, u32 a, u32 b, u32 c) {
  if (vn_lt_at(o, a, b)) {
    if (vn_lt_at(o, b, c)) vn_swap(o, first, b);
    else vn_swap(o, first, vn_lt_at(o, a, c) ? c : a);
  } else if (vn_lt_at(o, a, c)) vn_swap(o, first, a);
  else vn_swap(o, first, vn_lt_at(o, b, c) ? c : b);
}

static u32 vn_partition_pivot(VnOrder* o, u32 first, u32 last) {
  vn_move_median(o, first, first + 1, first + ((last - first) >> 1), last - 1);
  u32 pivot = VN_AT(o, first), fuel = last - first + 2, lo = first + 1, hi = last;
  for (u32 n = fuel; n > 0; n--) {
    lo = vn_scan(o, lo, pivot, 1, fuel);
    u32 low_value = VN_AT(o, lo);
    hi = vn_scan(o, hi - 1, pivot, 0, fuel);
    if (!(lo < hi)) break;
    VN_AT(o, lo) = VN_AT(o, hi);
    VN_AT(o, hi) = low_value;
    lo++;
  }
  return lo;
}

typedef struct { int done; u32 rf, rl, rd, nf, nl, nd; } VnPlan;

static VnPlan vn_intro_step(VnOrder* o, u32 first, u32 last, u32 depth) {
  VnPlan p = {1, 0, 0, 0, 0, 0, 0};
  if (last - first <= 16) return p;
  if (!depth) { vn_heap_sort(o, first, last); return p; }
  u32 cut = vn_partition_pivot(o, first, last);
  return (VnPlan){0, cut, last, depth - 1, first, cut, depth - 1};
}

static void vn_intro(VnOrder* o, u32 n, VnPlan p) {
  if (!n || p.done) return;
  vn_intro(o, n - 1, vn_intro_step(o, p.rf, p.rl, p.rd));
  vn_intro(o, n - 1, vn_intro_step(o, p.nf, p.nl, p.nd));
}

static void vn_gnu_sort(VnOrder* o, u32 first, u32 last) {
  u32 depth = vn_floor_log2(last - first) << 1;
  vn_intro(o, depth + 4, vn_intro_step(o, first, last, depth));
  if (last - first > 16) {
    vn_insertion_sort(o, first, first + 16);
    for (u32 i = first + 16, fuel = last - first + 2; i < last; i++) vn_linear_insert(o, i, VN_AT(o, i), fuel);
  } else vn_insertion_sort(o, first, last);
}

static void vn_order_pair(VnOrder* o, u32 i, u32 j) {
  u32 xj = VN_AT(o, j), yi = VN_AT(o, i);
  int less = o->lt(o, xj, yi);
  VN_AT(o, i) = less ? xj : yi;
  VN_AT(o, j) = less ? yi : xj;
}

static void vn_med3(VnOrder* o, u32 a, u32 b, u32 c) { vn_order_pair(o, a, b); vn_order_pair(o, b, c); vn_order_pair(o, a, b); }

static void vn_fat_partition(VnOrder* o, u32 first, u32 last, u32* pfirst, u32* plast) {
  u32 mid = first + ((last - first) >> 1), end = last - 1, fuel = last - first + 2;
  if (end - first > 40) {
    u32 step = (end - first + 1) >> 3, two = step << 1;
    vn_med3(o, first, first + step, first + two);
    vn_med3(o, mid - step, mid, mid + step);
    vn_med3(o, end - two, end - step, end);
    vn_med3(o, first + step, mid, end - step);
  } else vn_med3(o, first, mid, end);
  u32 pf = mid, pl = mid + 1;
  for (u32 n = fuel; n > 0 && first < pf && !vn_lt_at(o, pf - 1, pf) && !vn_lt_at(o, pf, pf - 1); n--) pf--;
  for (u32 n = fuel; n > 0 && pl < last && !vn_lt_at(o, pl, pf) && !vn_lt_at(o, pf, pl); n--) pl++;
  u32 gf = pl, gl = pf;
  for (u32 round = fuel; round > 0; round--) {
    for (u32 n = fuel; n > 0 && gf < last; n--) {
      if (vn_lt_at(o, pf, gf)) { gf++; continue; }
      if (vn_lt_at(o, gf, pf)) break;
      vn_swap(o, pl, gf); pl++; gf++;
    }
    for (u32 n = fuel; n > 0 && first < gl; n--) {
      if (vn_lt_at(o, gl - 1, pf)) { gl--; continue; }
      if (vn_lt_at(o, pf, gl - 1)) break;
      vn_swap(o, pf - 1, gl - 1); pf--; gl--;
    }
    int bottom = gl == first, top = gf == last;
    if (bottom && top) break;
    if (bottom) {
      if (pl != gf) vn_swap(o, pf, pl);
      vn_swap(o, pf, gf);
      pf++; pl++; gf++;
    } else if (top) {
      vn_swap(o, gl - 1, pf - 1);
      vn_swap(o, pf - 1, pl - 1);
      pf--; pl--; gl--;
    } else {
      vn_swap(o, gf, gl - 1);
      gf++; gl--;
    }
  }
  *pfirst = pf; *plast = pl;
}

static VnPlan vn_msvc_step(VnOrder* o, u32 first, u32 last, u32 ideal) {
  VnPlan p = {1, 0, 0, 0, 0, 0, 0};
  if (last - first <= 32) { vn_insertion_sort(o, first, last); return p; }
  if (!ideal) { vn_heap_sort(o, first, last); return p; }
  u32 pf, pl;
  vn_fat_partition(o, first, last, &pf, &pl);
  u32 next = (ideal >> 1) + (ideal >> 2);
  int low = pf - first < last - pl;
  return (VnPlan){0, low ? first : pl, low ? pf : last, next, low ? pl : first, low ? last : pf, next};
}

static void vn_msvc_drive(VnOrder* o, u32 n, VnPlan p) {
  if (!n || p.done) return;
  vn_msvc_drive(o, n - 1, vn_msvc_step(o, p.rf, p.rl, p.rd));
  vn_msvc_drive(o, n - 1, vn_msvc_step(o, p.nf, p.nl, p.nd));
}

static void vn_platform_sort(VnOrder* o, int windows, u32 first, u32 last) {
  if (windows) {
    u32 count = last - first;
    vn_msvc_drive(o, (vn_floor_log2(count) + 2) * 3 + 8, vn_msvc_step(o, first, last, count));
  } else vn_gnu_sort(o, first, last);
}

// voronoi_diagram<double> and its _build
// --------------------------------------

typedef struct { u32 cell, v0, next, prev, flags; } VnEdge;
typedef struct { double x, y; u32 incident; } VnVertex;
typedef struct { u32 src, cat, incident; } VnCell;

typedef struct {
  VnEdge* edges; u32 emask, ne;
  VnVertex* vertices; u32 vmask, nv;
  VnCell* cells; u32 cmask, nc;
} VnDiagram;

static u32 vn_pow2_above(u32 words) { u32 d = vn_floor_log2(words) + 1; return 1u << d; }

#define VN_E(d, i) ((d)->edges[(i) & (d)->emask])
#define VN_V(d, i) ((d)->vertices[(i) & (d)->vmask])
#define VN_C(d, i) ((d)->cells[(i) & (d)->cmask])

static u32 vn_twin(u32 e) { return e ^ 1; }

static int vn_is_primary(VnSite s1, VnSite s2) {
  int f1 = vn_is_segment(s1), f2 = vn_is_segment(s2);
  if (f1 && !f2) return !vn_pt_eq(vn_p0(s1), vn_p0(s2)) && !vn_pt_eq(vn_p1(s1), vn_p0(s2));
  if (!f1 && f2) return !vn_pt_eq(vn_p0(s2), vn_p0(s1)) && !vn_pt_eq(vn_p1(s2), vn_p0(s1));
  return 1;
}

static u32 vn_edge_flags(VnSite s1, VnSite s2) {
  int primary = vn_is_primary(s1, s2);
  int linear = !primary || !(vn_is_segment(s1) ^ vn_is_segment(s2));
  return (u32)linear + 2u * (u32)primary;
}

static void vn_push_cell(VnDiagram* d, VnSite s) { VN_C(d, d->nc) = (VnCell){s.initial, s.flags & 31, VN_NIL}; d->nc++; }

static u32 vn_insert_edge(VnDiagram* d, VnSite s1, VnSite s2) {
  u32 f = vn_edge_flags(s1, s2), e = d->ne;
  if (!d->nc) vn_push_cell(d, s1);
  VN_E(d, e) = (VnEdge){s1.sorted, VN_NIL, VN_NIL, VN_NIL, f};
  VN_E(d, e + 1) = (VnEdge){s2.sorted, VN_NIL, VN_NIL, VN_NIL, f};
  vn_push_cell(d, s2);
  d->ne += 2;
  return e;
}

static u32 vn_insert_vertex(VnDiagram* d, VnSite s1, VnSite s3, VnCircle c, u32 e12, u32 e23) {
  u32 f = vn_edge_flags(s1, s3), ne = d->ne, nv = d->nv;
  VN_V(d, nv) = (VnVertex){c.x, c.y, VN_NIL};
  VN_E(d, e12).v0 = nv; VN_E(d, e12).prev = ne;
  VN_E(d, e23).v0 = nv; VN_E(d, e23).prev = vn_twin(e12);
  VN_E(d, vn_twin(e12)).next = e23;
  VN_E(d, vn_twin(e23)).next = ne + 1;
  VN_E(d, ne) = (VnEdge){s1.sorted, VN_NIL, e12, VN_NIL, f};
  VN_E(d, ne + 1) = (VnEdge){s3.sorted, nv, VN_NIL, vn_twin(e23), f};
  d->ne += 2; d->nv++;
  return ne;
}

static u32 vn_rot_next(VnDiagram* d, u32 e) { return vn_twin(VN_E(d, e).prev); }

static void vn_remove_edge(VnDiagram* d, u32 i, u32 fuel) {
  u32 v = VN_E(d, i).v0, stop = vn_twin(i), e = vn_rot_next(d, stop);
  for (u32 n = fuel; n > 0 && e != stop; n--) { VN_E(d, e).v0 = v; e = vn_rot_next(d, e); }
  u32 r1p = VN_E(d, vn_twin(i)).next, r1n = vn_twin(VN_E(d, i).prev);
  u32 r2p = VN_E(d, i).next, r2n = vn_twin(VN_E(d, vn_twin(i)).prev);
  VN_E(d, vn_twin(r1n)).next = r2p;
  VN_E(d, r2p).prev = vn_twin(r1n);
  VN_E(d, r1p).prev = vn_twin(r2n);
  VN_E(d, vn_twin(r2n)).next = r1p;
}

static void vn_build_diagram(VnDiagram* d) {
  u32 ne = d->ne, last = 0;
  for (u32 i = 0; i < ne; i += 2) {
    u32 v1 = VN_E(d, i).v0, v2 = VN_E(d, i + 1).v0;
    if (v1 != VN_NIL && v2 != VN_NIL && vn_ulp_cmp(VN_V(d, v1).x, VN_V(d, v2).x, 128) == 0 && vn_ulp_cmp(VN_V(d, v1).y, VN_V(d, v2).y, 128) == 0) {
      vn_remove_edge(d, i, ne);
      continue;
    }
    if (i != last) {
      VN_E(d, last) = VN_E(d, i);
      VN_E(d, last + 1) = VN_E(d, i + 1);
      u32 e1 = last, n1 = VN_E(d, e1).next, p1 = VN_E(d, e1).prev;
      if (p1 != VN_NIL) VN_E(d, p1).next = e1;
      u32 n2 = VN_E(d, vn_twin(e1)).next, p2 = VN_E(d, vn_twin(e1)).prev;
      if (p1 != VN_NIL) VN_E(d, n2).prev = vn_twin(e1);
      if (p2 != VN_NIL) { VN_E(d, n1).prev = e1; VN_E(d, p2).next = vn_twin(e1); }
    }
    last += 2;
  }
  d->ne = ne = last;
  for (u32 i = 0; i < ne; i++) {
    u32 c = VN_E(d, i).cell, v = VN_E(d, i).v0;
    if (v != VN_NIL) VN_V(d, v).incident = i;
    VN_C(d, c).incident = i;
  }
  u32 nv = d->nv, kept = 0;
  for (u32 i = 0; i < nv; i++) {
    VnVertex v = VN_V(d, i);
    if (v.incident == VN_NIL) continue;
    if (i != kept) {
      u32 e = v.incident;
      for (u32 n = ne; n > 0; n--) { VN_E(d, e).v0 = kept; e = vn_rot_next(d, e); if (e == v.incident) break; }
      VN_V(d, kept) = v;
    }
    kept++;
  }
  d->nv = kept;
  for (u32 c = 0; c < d->nc; c++) {
    u32 inc = VN_C(d, c).incident;
    if (inc == VN_NIL) continue;
    u32 left = inc;
    for (u32 n = ne; n > 0; n--) {
      u32 p = VN_E(d, left).prev;
      if (p == VN_NIL) break;
      if (p == inc) { left = p; break; }
      left = p;
    }
    if (VN_E(d, left).prev != VN_NIL) continue;
    u32 right = inc;
    for (u32 n = ne; n > 0; n--) {
      u32 x = VN_E(d, right).next;
      if (x == VN_NIL) break;
      right = x;
    }
    VN_E(d, left).prev = right;
    VN_E(d, right).next = left;
  }
}

// voronoi_builder<int32>::construct
// ---------------------------------

typedef struct { VnSite l, r; u32 edge, circle, id; } VnNode;
typedef struct { VnPt p; u32 node; } VnEnd;

typedef struct {
  VnNode* nodes; u32 *prev, *next, *live, nmask, first, last, ids;
  VnEvent* events; u32* heap; u32 hmask, size, count;
  VnEnd* ends; u32 nends;
  VnDiagram d;
} VnSweep;

#define VN_N(s, i) ((s)->nodes[(i) & (s)->nmask])
#define VN_PREV(s, i) ((s)->prev[(i) & (s)->nmask])
#define VN_NEXT(s, i) ((s)->next[(i) & (s)->nmask])
#define VN_LIVE(s, i) ((s)->live[(i) & (s)->nmask])
#define VN_EV(s, i) ((s)->events[(i) & (s)->hmask])

static VnNode vn_node(VnSweep* s, u32 id) {
  if (id == VN_NIL) return (VnNode){{0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0, 0}, VN_NIL, VN_NIL, VN_NIL};
  return VN_N(s, id);
}

static void vn_beach_insert(VnSweep* s, u32 pos, VnNode n) {
  u32 id = n.id;
  VN_N(s, id) = n;
  VN_LIVE(s, id) = 1;
  if (pos == VN_NIL) {
    VN_PREV(s, id) = s->last;
    VN_NEXT(s, id) = VN_NIL;
    if (s->last == VN_NIL) s->first = id;
    else VN_NEXT(s, s->last) = id;
    s->last = id;
    return;
  }
  u32 p = VN_PREV(s, pos);
  VN_PREV(s, id) = p;
  VN_PREV(s, pos) = id;
  VN_NEXT(s, id) = pos;
  if (p == VN_NIL) s->first = id;
  else VN_NEXT(s, p) = id;
}

static void vn_beach_erase(VnSweep* s, u32 id) {
  if (!VN_LIVE(s, id)) return;
  VN_LIVE(s, id) = 0;
  u32 p = VN_PREV(s, id), q = VN_NEXT(s, id);
  if (p == VN_NIL) s->first = q;
  else VN_NEXT(s, p) = q;
  if (q == VN_NIL) s->last = p;
  else VN_PREV(s, q) = p;
}

static int vn_probe_less(VnSweep* s, u32 id, VnSite kl, VnSite kr) {
  if (id == VN_NIL) return 0;
  VnNode n = VN_N(s, id);
  return vn_node_less(n.l, n.r, kl, kr);
}

static u32 vn_beach_lower(VnSweep* s, VnSite kl, VnSite kr) {
  u32 id = s->first;
  int less = vn_probe_less(s, id, kl, kr);
  for (u32 fuel = 1048576; fuel > 0 && less; fuel--) {
    id = VN_NEXT(s, id);
    less = vn_probe_less(s, id, kl, kr);
  }
  return id;
}

static int vn_event_lt(VnOrder* o, u32 i, u32 j) { return vn_circle_less(o->events[j & o->dmask].c, o->events[i & o->dmask].c); }

static VnOrder vn_queue_order(VnSweep* s) { return (VnOrder){s->heap, s->hmask, vn_event_lt, NULL, s->events, s->hmask}; }

static u32 vn_push_event(VnSweep* s, VnCircle c, u32 node) {
  u32 id = s->count;
  VN_EV(s, id) = (VnEvent){c, 1, node};
  s->heap[s->size & s->hmask] = id;
  VnOrder o = vn_queue_order(s);
  vn_push_heap(&o, 0, s->size + 1);
  s->size++; s->count++;
  return id;
}

static void vn_pop_event(VnSweep* s) {
  VnOrder o = vn_queue_order(s);
  vn_pop_heap(&o, 0, s->size);
  s->size--;
}

static void vn_deactivate(VnSweep* s, u32 id) {
  u32 c = vn_node(s, id).circle;
  VN_N(s, id).circle = VN_NIL;
  if (c != VN_NIL) VN_EV(s, c).active = 0;
}

static void vn_activate(VnSweep* s, VnSite s1, VnSite s2, VnSite s3, u32 node) {
  VnCircle c;
  if (vn_circle_formation(s1, s2, s3, &c)) VN_N(s, node).circle = vn_push_event(s, c, node);
}

static u32 vn_insert_arc(VnSweep* s, VnSite arc1, VnSite arc2, VnSite site, u32 pos) {
  u32 e = vn_insert_edge(&s->d, arc2, site);
  int seg = vn_is_segment(site);
  u32 right = s->ids++;
  vn_beach_insert(s, pos, (VnNode){vn_inverse_if(seg, site), arc2, e + 1, VN_NIL, right});
  pos = right;
  if (seg) {
    u32 mid = s->ids++;
    vn_beach_insert(s, pos, (VnNode){site, vn_inverse(site), VN_NIL, VN_NIL, mid});
    s->ends[s->nends++] = (VnEnd){vn_p1(site), mid};
    pos = mid;
  }
  u32 left = s->ids++;
  vn_beach_insert(s, pos, (VnNode){arc1, site, e, VN_NIL, left});
  return left;
}

static u32 vn_place_one(VnSweep* s, VnSite site, u32 right) {
  if (right == VN_NIL) {
    VnNode left = vn_node(s, s->last);
    u32 fresh = vn_insert_arc(s, left.r, left.r, site, VN_NIL);
    vn_activate(s, left.l, left.r, site, fresh);
    return fresh;
  }
  VnSite flipped = vn_inverse_if(vn_is_segment(site), site);
  if (right == s->first) {
    VnNode n = vn_node(s, right);
    u32 fresh = vn_insert_arc(s, n.l, n.l, site, right);
    vn_activate(s, flipped, n.l, n.r, right);
    return fresh;
  }
  VnNode rn = vn_node(s, right), ln = vn_node(s, VN_PREV(s, right));
  vn_deactivate(s, right);
  u32 fresh = vn_insert_arc(s, ln.r, rn.l, site, right);
  vn_activate(s, ln.l, ln.r, site, fresh);
  vn_activate(s, flipped, rn.l, rn.r, right);
  return fresh;
}

static u32 vn_process_site(VnSweep* s, const VnSite* sites, u32 at, u32 n) {
  VnSite first = sites[at];
  u32 end = at + 1;
  if (vn_is_point(first)) {
    VnPt p = vn_p0(first);
    u32 kept = 0;
    for (u32 k = 0; k < s->nends; k++) {
      VnEnd e = s->ends[k];
      if (vn_pt_eq(p, e.p)) vn_beach_erase(s, e.node);
      else s->ends[kept++] = e;
    }
    s->nends = kept;
  } else {
    while (end < n && vn_is_segment(sites[end]) && vn_pt_eq(vn_p0(sites[end]), vn_p0(first))) end++;
  }
  u32 right = vn_beach_lower(s, first, first);
  for (u32 k = at; k < end; k++) right = vn_place_one(s, sites[k], right);
  return end;
}

static void vn_process_circle(VnSweep* s) {
  VnEvent ev = VN_EV(s, s->heap[0]);
  u32 last = ev.node;
  VnNode ln = vn_node(s, last), first = vn_node(s, VN_PREV(s, last));
  VnSite s1 = first.l, s3 = ln.r;
  if (vn_is_point(s1) && vn_is_segment(s3) && vn_pt_eq(vn_end(s3), vn_p0(s1))) s3 = vn_inverse(s3);
  u32 e = vn_insert_vertex(&s->d, s1, s3, ev.c, first.edge, ln.edge);
  VN_N(s, first.id).r = s3;
  VN_N(s, first.id).edge = e;
  vn_beach_erase(s, last);
  vn_pop_event(s);
  u32 head = s->first, next = VN_NEXT(s, first.id);
  if (head != first.id) {
    vn_deactivate(s, first.id);
    vn_activate(s, vn_node(s, VN_PREV(s, first.id)).l, s1, s3, first.id);
  }
  if (next != VN_NIL) {
    vn_deactivate(s, next);
    vn_activate(s, s1, s3, vn_node(s, next).r, next);
  }
}

static int vn_site_lt(VnOrder* o, u32 i, u32 j) { return vn_site_less(o->sites[i & o->dmask], o->sites[j & o->dmask]); }

static void* vn_alloc(size_t n, size_t size) { return io_mem(calloc(n ? n : 1, size)); }

// The diagram of the input points and the frame segments, from its site events (sorted and made unique).
static void vn_construct(VnDiagram* out, int windows, const VnPt* points, u32 np, const int32_t* segs, u32 ns) {
  u32 total = np + 3 * ns, cap = vn_pow2_above(total + 1);
  VnSite* input = vn_alloc(cap, sizeof(VnSite));
  u32* handles = vn_alloc(cap, sizeof(u32));
  for (u32 i = 0; i < np; i++) input[i] = (VnSite){points[i].x, points[i].y, points[i].x, points[i].y, 0, i, 0};
  for (u32 k = 0; k < ns; k++) {
    const int32_t* g = segs + 4 * k;
    VnPt p1 = {g[0], g[1]}, p2 = {g[2], g[3]};
    u32 at = np + 3 * k, index = np + k;
    input[at] = (VnSite){p1.x, p1.y, p1.x, p1.y, 0, index, 1};
    input[at + 1] = (VnSite){p2.x, p2.y, p2.x, p2.y, 0, index, 2};
    input[at + 2] = vn_point_less(p1, p2) ? (VnSite){p1.x, p1.y, p2.x, p2.y, 0, index, 8} : (VnSite){p2.x, p2.y, p1.x, p1.y, 0, index, 9};
  }
  for (u32 i = 0; i < total; i++) handles[i] = i;
  VnOrder order = {handles, cap - 1, vn_site_lt, input, NULL, cap - 1};
  vn_platform_sort(&order, windows, 0, total);
  VnSite* sites = vn_alloc(total + 1, sizeof(VnSite));
  u32 n = 0;
  for (u32 i = 0; i < total; i++) {
    VnSite s = input[handles[i] & (cap - 1)];
    if (n && vn_same_site(sites[n - 1], s)) continue;
    s.sorted = n;
    sites[n++] = s;
  }
  free(input); free(handles);

  VnSweep sw = {0};
  sw.nmask = vn_pow2_above(n * 4 + 16) - 1;
  sw.nodes = vn_alloc(sw.nmask + 1, sizeof(VnNode));
  sw.prev = vn_alloc(3 * ((size_t)sw.nmask + 1), sizeof(u32));
  sw.next = sw.prev + sw.nmask + 1;
  sw.live = sw.next + sw.nmask + 1;
  for (u32 i = 0; i <= sw.nmask; i++) { sw.prev[i] = VN_NIL; sw.next[i] = VN_NIL; sw.nodes[i].edge = sw.nodes[i].circle = sw.nodes[i].id = VN_NIL; }
  sw.first = sw.last = VN_NIL;
  sw.hmask = vn_pow2_above(n * 16 + 16) - 1;
  sw.events = vn_alloc(sw.hmask + 1, sizeof(VnEvent));
  sw.heap = vn_alloc(sw.hmask + 1, sizeof(u32));
  for (u32 i = 0; i <= sw.hmask; i++) sw.events[i].node = VN_NIL;
  sw.ends = vn_alloc(n + 1, sizeof(VnEnd));
  VnDiagram* d = &sw.d;
  d->emask = vn_pow2_above(n * 8 + 16) - 1;
  d->vmask = d->cmask = vn_pow2_above(n * 2 + 8) - 1;
  d->edges = vn_alloc(d->emask + 1, sizeof(VnEdge));
  d->vertices = vn_alloc(d->vmask + 1, sizeof(VnVertex));
  d->cells = vn_alloc(d->cmask + 1, sizeof(VnCell));
  for (u32 i = 0; i <= d->emask; i++) d->edges[i] = (VnEdge){0, VN_NIL, VN_NIL, VN_NIL, 0};
  for (u32 i = 0; i <= d->vmask; i++) { d->vertices[i] = (VnVertex){0.0, 0.0, VN_NIL}; d->cells[i] = (VnCell){0, 0, VN_NIL}; }

  u32 at = 0;
  if (n == 1) {
    vn_push_cell(d, sites[0]);
    at = 1;
  } else if (n > 1) {
    u32 skip = 0;
    while (skip < n && sites[skip].x0 == sites[0].x0 && vn_is_vertical(sites[skip])) skip++;
    if (skip == 1) {
      vn_insert_arc(&sw, sites[0], sites[0], sites[1], VN_NIL);
      at = 2;
    } else {
      for (u32 k = 0; k < skip - 1 && k < n; k++) {
        VnSite a = sites[k], b = k + 1 < n ? sites[k + 1] : (VnSite){0, 0, 0, 0, 0, 0, 0};
        u32 e = vn_insert_edge(d, a, b);
        vn_beach_insert(&sw, VN_NIL, (VnNode){a, b, e, VN_NIL, sw.ids++});
      }
      at = skip;
    }
  }
  if (n) {
    for (u32 fuel = n * 64 + 64; fuel > 0; fuel--) {
      if (at < n && (!sw.size || vn_site_before_circle(sites[at], VN_EV(&sw, sw.heap[0]).c))) at = vn_process_site(&sw, sites, at, n);
      else if (sw.size) vn_process_circle(&sw);
      else break;
      for (u32 k = n * 64 + 64; k > 0 && sw.size && !VN_EV(&sw, sw.heap[0]).active; k--) vn_pop_event(&sw);
    }
  }
  free(sites); free(sw.nodes); free(sw.prev); free(sw.events); free(sw.heap); free(sw.ends);
  vn_build_diagram(d);
  *out = *d;
}

// BuildVoronoi's polygons and states, and the tile cells
// ------------------------------------------------------

typedef struct { u32 x, y, kind, cx, cy; } VnSiteIn;
typedef struct { double x, y; } VnD2;
typedef struct { u32* w; size_t n, cap; } VnWords;
typedef struct { u32 twin_cell, has0, has1, flags; double x0, y0, x1, y1; } VnHalf;
typedef struct { u32 pts, npts, nbs, nnbs, cx, cy, state; } VnPoly;

typedef struct {
  const VnSiteIn* sites; u32 n, smask;
  double w, h;
  VnDiagram d;
  VnWords pts, nbs, line;
  VnPoly* polys;
} VnBuild;

static void vn_put(VnWords* o, u32 x) {
  if (o->n == o->cap) { o->cap = o->cap ? 2 * o->cap : 256; o->w = io_mem(realloc(o->w, o->cap * 4)); }
  o->w[o->n++] = x;
}

static void vn_put_f64(VnWords* o, double x) { uint64_t b = vn_bits(x); vn_put(o, (u32)(b >> 32)); vn_put(o, (u32)b); }

static VnD2 vn_seg_start(VnBuild* b, u32 k) {
  if (k == 0) return (VnD2){0.0, 0.0};
  if (k == 1) return (VnD2){b->w, 0.0};
  if (k == 2) return (VnD2){b->w, b->h};
  return (VnD2){0.0, b->h};
}

static VnD2 vn_seg_end(VnBuild* b, u32 k) { return vn_seg_start(b, (k + 1) & 3); }

static VnD2 vn_retrieve(VnBuild* b, VnCell c) {
  if (c.cat == 0) { VnSiteIn s = b->sites[c.src & b->smask]; return (VnD2){vn_f64_of(s.x), vn_f64_of(s.y)}; }
  return c.cat == 1 ? vn_seg_start(b, c.src - b->n) : vn_seg_end(b, c.src - b->n);
}

static void vn_point(VnWords* o, VnD2 p) { vn_put(o, vn_bits(p.x) >> 32); vn_put(o, (u32)vn_bits(p.x)); vn_put(o, vn_bits(p.y) >> 32); vn_put(o, (u32)vn_bits(p.y)); }

static VnD2 vn_word_point(const VnWords* o, size_t at) {
  return (VnD2){vn_dbl((uint64_t)o->w[at] << 32 | o->w[at + 1]), vn_dbl((uint64_t)o->w[at + 2] << 32 | o->w[at + 3])};
}

static void vn_clip(VnBuild* b, VnCell c1, VnCell c2, VnHalf h) {
  VnD2 o, dir;
  if (c1.cat < 8 && c2.cat < 8) {
    VnD2 p1 = vn_retrieve(b, c1), p2 = vn_retrieve(b, c2);
    o = (VnD2){(p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5};
    dir = (VnD2){p1.y - p2.y, p2.x - p1.x};
  } else {
    int seg_first = !(c1.cat < 8);
    o = vn_retrieve(b, seg_first ? c2 : c1);
    u32 k = seg_first ? c1.src - b->n : c2.src - b->n;
    VnD2 s0 = vn_seg_start(b, k), s1 = vn_seg_end(b, k);
    double dx = s1.x - s0.x, dy = s1.y - s0.y;
    int low = s0.x == o.x && s0.y == o.y;
    dir = (low ^ (c1.cat < 8)) ? (VnD2){dy, -dx} : (VnD2){-dy, dx};
  }
  double koef = b->w / vn_max(fabs(dir.x), fabs(dir.y));
  vn_point(&b->line, h.has0 ? (VnD2){h.x0, h.y0} : (VnD2){o.x - dir.x * koef, o.y - dir.y * koef});
  vn_point(&b->line, h.has1 ? (VnD2){h.x1, h.y1} : (VnD2){o.x + dir.x * koef, o.y + dir.y * koef});
}

static double vn_parabola_y(double x, double a, double b) { double t = x - a; return (t * t + b * b) / (b + b); }

static double vn_projection(VnD2 p, VnD2 s0, VnD2 s1) {
  double svx = s1.x - s0.x, svy = s1.y - s0.y, pvx = p.x - s0.x, pvy = p.y - s0.y;
  return (svx * pvx + svy * pvy) / (svx * svx + svy * svy);
}

static void vn_discretize(VnBuild* b, VnD2 point, VnD2 s0, VnD2 s1, double max_dist, VnD2 v0, VnD2 v1) {
  double svx = s1.x - s0.x, svy = s1.y - s0.y, sqr = svx * svx + svy * svy;
  double start = sqr * vn_projection(v0, s0, s1), stop = sqr * vn_projection(v1, s0, s1);
  double pvx = point.x - s0.x, pvy = point.y - s0.y;
  double rx = svx * pvx + svy * pvy, ry = svx * pvy - svy * pvx, limit = max_dist * max_dist * sqr;
  VnWords stack = {0};
  vn_put_f64(&stack, stop);
  double cx = start, cy = vn_parabola_y(start, rx, ry);
  size_t first = b->line.n;
  vn_point(&b->line, v0);
  for (u32 fuel = 65536; fuel > 0 && stack.n; fuel--) {
    double nx = vn_dbl((uint64_t)stack.w[stack.n - 2] << 32 | stack.w[stack.n - 1]);
    double ny = vn_parabola_y(nx, rx, ry);
    double mx = (ny - cy) / (nx - cx) * ry + rx, my = vn_parabola_y(mx, rx, ry);
    if (!vn_finite(mx) || !vn_finite(my)) { stack.n -= 2; continue; }
    double dy = ny - cy, dx = nx - cx, raw = dy * (mx - cx) - dx * (my - cy);
    double dist = raw * raw / (dy * dy + dx * dx);
    if (dist <= limit) {
      stack.n -= 2;
      vn_point(&b->line, (VnD2){(svx * nx - svy * ny) / sqr + s0.x, (svx * ny + svy * nx) / sqr + s0.y});
      cx = nx; cy = ny;
    } else vn_put_f64(&stack, mx);
  }
  free(stack.w);
  b->line.n -= 4;
  if (b->line.n < first) b->line.n = first;
  vn_point(&b->line, v1);
}

static void vn_curved_or_line(VnBuild* b, VnCell c1, VnCell c2, VnHalf h) {
  VnD2 v0 = {h.x0, h.y0}, v1 = {h.x1, h.y1};
  if (h.flags & 1) { vn_point(&b->line, v0); vn_point(&b->line, v1); return; }
  int point_first = c1.cat < 8;
  VnCell seg = point_first ? c2 : c1;
  u32 k = seg.src - b->n;
  vn_discretize(b, vn_retrieve(b, point_first ? c1 : c2), vn_seg_start(b, k), vn_seg_end(b, k), b->w * 0.001, v0, v1);
}

static int vn_within(double x) { return vn_finite(x) && fabs(x) <= 10000.0; }

static VnHalf vn_half(VnDiagram* d, u32 e) {
  VnEdge x = VN_E(d, e), t = VN_E(d, vn_twin(e));
  VnVertex a = x.v0 != VN_NIL ? VN_V(d, x.v0) : (VnVertex){0.0, 0.0, VN_NIL};
  VnVertex z = t.v0 != VN_NIL ? VN_V(d, t.v0) : (VnVertex){0.0, 0.0, VN_NIL};
  return (VnHalf){t.cell, x.v0 != VN_NIL, t.v0 != VN_NIL, x.flags, a.x, a.y, z.x, z.y};
}

static u32 vn_half_points(VnBuild* b, VnCell c1, VnHalf h, int polygon) {
  VnCell c2 = VN_C(&b->d, h.twin_cell);
  b->line.n = 0;
  if (!(h.has0 && h.has1)) vn_clip(b, c1, c2, h);
  else if (!polygon || (vn_within(h.x0) && vn_within(h.y0) && vn_within(h.x1) && vn_within(h.y1))) vn_curved_or_line(b, c1, c2, h);
  return c2.src;
}

static void vn_centroid(const u32* pts, u32 count, u32* cx, u32* cy) {
  float a = 0.0f, x = 0.0f, y = 0.0f, fx = vn_flt(pts[0]), fy = vn_flt(pts[1]), px = fx, py = fy;
  for (u32 i = 1; i < count; i++) {
    float qx = vn_flt(pts[2 * i]), qy = vn_flt(pts[2 * i + 1]), c = px * qy - qx * py;
    a = a + c; x = x + (px + qx) * c; y = y + (py + qy) * c;
    px = qx; py = qy;
  }
  float c = px * fy - fx * py;
  a = a + c; x = x + (fx + px) * c; y = y + (fy + py) * c;
  float a6 = a * 0.5f * 6.0f;
  *cx = vn_fbits(x / a6); *cy = vn_fbits(y / a6);
}

static void vn_cell_poly(VnBuild* b, VnCell cell, u32 k) {
  VnDiagram* d = &b->d;
  VnPoly* p = &b->polys[cell.src];
  int border = 0;
  p->pts = (u32)b->pts.n; p->nbs = (u32)b->nbs.n;
  u32 inc = VN_C(d, k).incident, e = inc;
  if (inc != VN_NIL)
    for (u32 fuel = d->ne; fuel > 0; fuel--) {
      VnHalf h = vn_half(d, e);
      u32 src = vn_half_points(b, cell, h, 1);
      for (size_t i = 0; i < b->line.n; i += 4) {
        VnD2 q = vn_word_point(&b->line, i);
        vn_put(&b->pts, vn_f32_of(q.x)); vn_put(&b->pts, vn_f32_of(q.y));
      }
      vn_put(&b->nbs, src < b->n ? src : VN_NIL);
      border = border || !(src < b->n);
      e = VN_E(d, e).next;
      if (e == inc) break;
    }
  p->npts = (u32)(b->pts.n - p->pts) / 2;
  p->nnbs = (u32)b->nbs.n - p->nbs;
  VnSiteIn s = b->sites[cell.src];
  if (p->npts) vn_centroid(b->pts.w + p->pts, p->npts, &p->cx, &p->cy);
  else { p->cx = s.x; p->cy = s.y; }
  p->state = (s.kind & ~2u) == 1 ? 1 : (border ? 4 : 5);
}

static void vn_state_pass(VnBuild* b) {
  for (u32 i = 0; i < b->n; i++) {
    VnPoly* p = &b->polys[i];
    int all_above = 1, any_blank = 0;
    for (u32 k = 0; k < p->nnbs; k++) {
      u32 j = b->nbs.w[p->nbs + k], st = j == VN_NIL ? 0 : b->polys[j].state;
      all_above = all_above && 2 < st;
      any_blank = any_blank || st == 1;
    }
    if (p->state < 4) p->state = p->state == 1 && all_above ? 2 : p->state;
    else p->state = any_blank ? 3 : p->state;
  }
}

static void vn_frame_segments(int32_t* segs, u32 w, u32 h) {
  int32_t sw = (int32_t)w, sh = (int32_t)h;
  int32_t f[16] = {0, 0, sw, 0, sw, 0, sw, sh, sw, sh, 0, sh, 0, sh, 0, 0};
  memcpy(segs, f, sizeof f);
}

// BoostMap::BuildVoronoi of the sites in a w x h frame: one polygon per site, in site order.
static void vn_build(VnBuild* b, int windows, u32 w, u32 h, const VnSiteIn* sites, u32 n) {
  memset(b, 0, sizeof *b);
  b->sites = sites; b->n = n; b->smask = VN_NIL;
  b->w = (double)w; b->h = (double)h;
  VnPt* points = vn_alloc(n, sizeof(VnPt));
  for (u32 i = 0; i < n; i++) points[i] = (VnPt){vn_to_i32(vn_f64_of(sites[i].x)), vn_to_i32(vn_f64_of(sites[i].y))};
  int32_t segs[16];
  vn_frame_segments(segs, w, h);
  vn_construct(&b->d, windows, points, n, segs, 4);
  free(points);
  b->polys = vn_alloc(n, sizeof(VnPoly));
  for (u32 i = 0; i < n; i++) b->polys[i] = (VnPoly){0, 0, 0, 0, sites[i].cx, sites[i].cy, 5};
  for (u32 k = 0; k < b->d.nc; k++) {
    VnCell cell = VN_C(&b->d, k);
    if (cell.src < n) vn_cell_poly(b, cell, k);
  }
  vn_state_pass(b);
}

static void vn_build_free(VnBuild* b) {
  free(b->d.edges); free(b->d.vertices); free(b->d.cells);
  free(b->pts.w); free(b->nbs.w); free(b->line.w); free(b->polys);
}

static void vn_put_polys(VnWords* o, VnBuild* b) {
  for (u32 i = 0; i < b->n; i++) {
    VnPoly p = b->polys[i];
    vn_put(o, p.npts);
    for (u32 k = 0; k < 2 * p.npts; k++) vn_put(o, b->pts.w[p.pts + k]);
    vn_put(o, p.cx); vn_put(o, p.cy);
    vn_put(o, p.nnbs);
    for (u32 k = 0; k < p.nnbs; k++) vn_put(o, b->nbs.w[p.nbs + k]);
    vn_put(o, p.state);
  }
}

// GenWorld.cells: every point cell's half-edges with their vertices and drawn points.
static void vn_put_cells(VnWords* o, VnBuild* b) {
  VnDiagram* d = &b->d;
  size_t count_at = o->n;
  u32 cells = 0;
  vn_put(o, 0);
  for (u32 k = 0; k < d->nc; k++) {
    VnCell cell = VN_C(d, k);
    if (!(cell.src < b->n)) continue;
    cells++;
    vn_put(o, cell.src);
    size_t edges_at = o->n;
    u32 edges = 0;
    vn_put(o, 0);
    u32 inc = cell.incident, e = inc;
    if (inc != VN_NIL)
      for (u32 fuel = d->ne; fuel > 0; fuel--) {
        VnHalf h = vn_half(d, e);
        u32 twin = vn_half_points(b, cell, h, 0);
        vn_put(o, twin);
        vn_put(o, h.has0 | h.has1 << 1);
        vn_point(o, (VnD2){h.x0, h.y0});
        vn_point(o, (VnD2){h.x1, h.y1});
        vn_put(o, (u32)(b->line.n / 4));
        for (size_t i = 0; i < b->line.n; i++) vn_put(o, b->line.w[i]);
        edges++;
        e = VN_E(d, e).next;
        if (e == inc) break;
      }
    o->w[edges_at] = edges;
  }
  o->w[count_at] = cells;
}

// worldsim/commit.bend: Commit's size and ScaleAndCenter, in float
// -----------------------------------------------------------------

typedef struct { float lox, hix, loy, hiy; } VnBox;

static VnBox vn_box(const VnSiteIn* s, u32 n) {
  VnBox b = {vn_flt(0x7f7fffffu), vn_flt(0x00800000u), vn_flt(0x7f7fffffu), vn_flt(0x00800000u)};
  for (u32 i = 0; i < n; i++) {
    float x = vn_flt(s[i].x), y = vn_flt(s[i].y);
    b.lox = b.lox <= x ? b.lox : x; b.hix = x <= b.hix ? b.hix : x;
    b.loy = b.loy <= y ? b.loy : y; b.hiy = y <= b.hiy ? b.hiy : y;
  }
  return b;
}

static u32 vn_extent(float lo, float hi, u32 margin, int empty) { return empty ? 0x80000000u + margin * 2 : (u32)vn_ftoi(hi - lo) + margin * 2; }

static u32 vn_commit_size(const VnSiteIn* s, u32 n, u32 w, u32 h) {
  u32 margin = w == 1 && h == 1 ? 0 : 20;
  VnBox b = vn_box(s, n);
  u32 sx = vn_extent(b.lox, b.hix, margin, !n), sy = vn_extent(b.loy, b.hiy, margin, !n);
  return sy <= sx ? sx : sy;
}

static float vn_centre(float lo, float hi, int empty) { return empty ? vn_flt(0x7effffffu) : (hi - lo) * 0.5f + lo; }
static float vn_frame_centre(u32 size) { float hi = vn_float_of((double)size), lo = 0.0f; return (hi - lo) * 0.5f + lo; }

static void vn_scale_and_center(VnSiteIn* s, u32 n, float fx, float fy, u32 w, u32 h) {
  for (u32 i = 0; i < n; i++) { s[i].x = vn_fbits(vn_flt(s[i].x) * fx); s[i].y = vn_fbits(vn_flt(s[i].y) * fy); }
  VnBox b = vn_box(s, n);
  float ox = vn_frame_centre(w) - vn_centre(b.lox, b.hix, !n), oy = vn_frame_centre(h) - vn_centre(b.loy, b.hiy, !n);
  for (u32 i = 0; i < n; i++) { s[i].x = vn_fbits(vn_flt(s[i].x) + ox); s[i].y = vn_fbits(vn_flt(s[i].y) + oy); }
}

static float vn_int_float(u32 x) { return vn_float_of((double)(int32_t)x); }

static u32 vn_tile_map_size(u32 min_size, u32 w, u32 h) {
  float s0 = vn_int_float(min_size), s1 = s0 <= vn_int_float(w) ? vn_int_float(w) : s0, s2 = s1 <= vn_int_float(h) ? vn_int_float(h) : s1;
  return (u32)vn_ftoi(s2);
}

static void vn_with_centroids(VnSiteIn* s, VnBuild* b) {
  for (u32 i = 0; i < b->n; i++) { s[i].cx = b->polys[i].cx; s[i].cy = b->polys[i].cy; }
}

// The pass's words: its BuildVoronoi, and after the last pass also Commit's and ConvertToTileMap's.
static void vn_answer(VnWords* o, const u32* kk, u32 kk_len, const u32* plan, u32 plan_len) {
  u32 n = kk_len ? kk[0] : 0, windows = plan[0], world = plan[1], last = plan[2];
  if (n > (kk_len - 1) / 4) n = (kk_len - 1) / 4;
  if (n > (plan_len - 3) / 3) n = (plan_len - 3) / 3;
  vn_put(o, 0);
  for (u32 i = 0; i < 1 + 4 * n; i++) vn_put(o, kk[i]);
  vn_put(o, last ? 1 : 0);
  VnSiteIn* sites = vn_alloc(n, sizeof(VnSiteIn));
  for (u32 i = 0; i < n; i++) {
    const u32* p = kk + 1 + 4 * i;
    double x = vn_dbl((uint64_t)p[0] << 32 | p[1]), y = vn_dbl((uint64_t)p[2] << 32 | p[3]);
    sites[i] = (VnSiteIn){vn_f32_of(x), vn_f32_of(y), plan[3 + 3 * i], plan[4 + 3 * i], plan[5 + 3 * i]};
  }
  VnBuild b;
  vn_build(&b, windows, world, world, sites, n);
  vn_put_polys(o, &b);
  if (last) {
    vn_with_centroids(sites, &b);
    vn_build_free(&b);
    u32 size = vn_commit_size(sites, n, world, world);
    vn_scale_and_center(sites, n, 1.0f, 1.0f, size, size);
    vn_build(&b, windows, size, size, sites, n);
    vn_put_polys(o, &b);
    vn_with_centroids(sites, &b);
    vn_build_free(&b);
    u32 tile = vn_tile_map_size(world, size, size);
    float fs = vn_float_of((double)tile);
    vn_scale_and_center(sites, n, fs / vn_int_float(size), fs / vn_int_float(size), tile, tile);
    vn_build(&b, windows, tile, tile, sites, n);
    vn_put_polys(o, &b);
    vn_put_cells(o, &b);
  }
  vn_build_free(&b);
  free(sites);
  o->w[0] = (u32)o->n;
}

// The effect
// ----------
// The pass's KK runs first, on the same helper thread: kk.c's solver, which FID(native_kk) has the compiler splice in.

static u32* native_kk_solve(const u32* in, u64 len);

typedef struct { u32 *kk, *plan; u32 kk_len, plan_len; VnWords out; } VnJob;

static u32* vn_words_of(Env e, Term a, u32* len) {
  const u32a* in = blk_ptr(e.mem, blk_loc(e.mem, a), 0);
  *len = 1u << blk_cls(a);
  u32* w = io_mem(malloc((size_t)*len * 4));
  for (u32 i = 0; i < *len; i++) w[i] = in[i];
  blk_free(e, a);
  return w;
}

static void native_layout_call(IoWork* w) {
  VnJob* j = (VnJob*)w->data;
  u32* laid = native_kk_solve(j->kk, j->kk_len);
  vn_answer(&j->out, laid, 1 + 4 * laid[0], j->plan, j->plan_len);
  free(laid);
}

static Term native_layout_pack(Env e, IoWork* w) {
  VnJob* j = (VnJob*)w->data;
  u32 cls = 1;
  while ((1ull << cls) < j->out.n) cls++;
  u64 l = heap_alloc(e, blk_wcls(false, cls));
  if (!err_seen(e.mem)) {
    u32a* out = blk_ptr(e.mem, l, 0);
    memset((void*)out, 0, 4ull << cls);
    for (size_t i = 0; i < j->out.n; i++) out[i] = j->out.w[i];
  }
  free(j->kk); free(j->plan); free(j->out.w); free(j);
  return term_blk(false, err_seen(e.mem) ? 0 : cls, l);
}

Term native_layout_run(Env e, Term* f, IoWork* w) {
  (void)FID(native_kk);
  VnJob* j = io_mem(calloc(1, sizeof(VnJob)));
  j->kk = vn_words_of(e, f[0], &j->kk_len);
  j->plan = vn_words_of(e, f[1], &j->plan_len);
  w->data = (char*)j;
  return io_work(w, native_layout_call, native_layout_pack);
}

static void __attribute__((constructor)) native_layout_use(void) {
  io_eff(CID(native_layout), native_layout_run);
}
