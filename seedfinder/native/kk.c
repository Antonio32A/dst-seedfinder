// Native KK
// =========
// worldsim/layout/kk.bend in IEEE doubles, same operation order (exact caches, cycle skipping, norm bound).
// Words in (an array, consumed): n, left, arc count, arcs (from, to), then n positions (x hi, x lo, y hi, y lo). Words
// out (a new array): n, then the n positions.
// Vector lanes (AVX2 when the CPU has it, WebAssembly SIMD128) do the scalar pair's IEEE operations and every sum adds
// the pairs in index order. The matrices are symmetric: the partial of (i, m) is the negated (m, i) one, so row m's
// mirrors (i, m) are built from row m once its Newton steps end, wait in c*, then go to column m. The hop graph must be
// undirected (every arc in both directions, as the Bend side builds it).

#pragma STDC FP_CONTRACT OFF
#pragma clang fp contract(off)

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  u32 n, left, arcs, *arc, *ph;
  double *x, *y, *px, *py, *pd, *cx, *cy, *pck, *gx, *gy, *qx, *qy, *cl, *ck, *ckl;
} Kn;

static uint64_t kn_bits(double x) { uint64_t u; memcpy(&u, &x, 8); return u; }
static double kn_dbl(uint64_t u) { double x; memcpy(&x, &u, 8); return x; }

static double kn_quiet(double x) { return x != x ? kn_dbl(kn_bits(x) | 0x0008000000000000ull) : x; }

static double kn_hypot(double x, double y) {
  x = fabs(x); y = fabs(y);
  if (isinf(x) || isinf(y)) return INFINITY;
  if (x < y) { double t = x; x = y; y = t; }
  if (x * 2.220446049250313e-16 >= y) return x;
  double rat = y / x;
  return x * sqrt(1.0 + rat * rat);
}
static double kn_norm(double dx, double dy) { return kn_hypot(kn_quiet(fabs(dx)), dy); }

#define KN_AT(k, m, i) ((size_t)(m) * (k)->n + (i))

static void kn_partial(Kn* k, u32 m, u32 i, double* ox, double* oy, double* od) {
  double dx = k->x[m] - k->x[i], dy = k->y[m] - k->y[i];
  double d = kn_norm(dx, dy);
  u32 h = k->ph[KN_AT(k, m, i)];
  double r = k->cl[h] / d;
  *ox = k->ck[h] * (dx - r * dx);
  *oy = k->ck[h] * (dy - r * dy);
  *od = d;
}
static int kn_nonzero(double x) { return x != 0.0 && x == x; }
static void kn_flush(Kn* k, u32 m, u32 i, u32 end) {
  for (; i < end; i++) { size_t at = KN_AT(k, i, m); k->px[at] = k->cx[i]; k->py[at] = k->cy[i]; k->pd[at] = k->pd[KN_AT(k, m, i)]; }
}

static int kn_gradient_contends(Kn* k, u32 u, double x, double y, double delta) {
  k->gx[u] = x; k->gy[u] = y;
  double b = (fabs(x) + fabs(y)) * 0x1.0000000000008p+0;
  u32 e = (u32)(kn_bits(b) >> 52) & 2047;
  return !(e >= 23 && e <= 2023 && b < delta);
}
static void kn_pick(Kn* k, u32 u, double x, double y, u32* p, double* delta) {
  if (!kn_gradient_contends(k, u, x, y, *delta)) return;
  double d = kn_norm(x, y);
  if (d > *delta) { *p = u; *delta = d; }
}

#if defined(__x86_64__)
#define KN_W 4
#define KN_WIDE __attribute__((target("avx2")))
#define KN_WIDE_OK() __builtin_cpu_supports("avx2")
#elif defined(__wasm__)
#define KN_W 2
#define KN_WIDE __attribute__((target("simd128")))
#define KN_WIDE_OK() 1
#else
#define KN_WIDE_OK() 0
#endif

#ifdef KN_W
typedef double KnV __attribute__((vector_size(8 * KN_W)));
typedef int64_t KnM __attribute__((vector_size(8 * KN_W)));
typedef u32 KnH __attribute__((vector_size(4 * KN_W)));
typedef int32_t KnS __attribute__((vector_size(4 * KN_W)));
typedef double Kn2 __attribute__((vector_size(16)));
typedef double Kn4 __attribute__((vector_size(32)));

KN_WIDE static inline KnV kn_v_load(const double* p) { KnV v; memcpy(&v, p, sizeof v); return v; }
KN_WIDE static inline void kn_v_save(double* p, KnV v) { memcpy(p, &v, sizeof v); }
KN_WIDE static inline KnV kn_v_pick(KnM m, KnV a, KnV b) { return (KnV)((m & (KnM)a) | (~m & (KnM)b)); }

KN_WIDE static inline void kn_v_transpose(KnV* b) {
#if KN_W == 4
  KnV a0 = __builtin_shufflevector(b[0], b[1], 0, 4, 2, 6), a1 = __builtin_shufflevector(b[0], b[1], 1, 5, 3, 7);
  KnV a2 = __builtin_shufflevector(b[2], b[3], 0, 4, 2, 6), a3 = __builtin_shufflevector(b[2], b[3], 1, 5, 3, 7);
  b[0] = __builtin_shufflevector(a0, a2, 0, 1, 4, 5); b[1] = __builtin_shufflevector(a1, a3, 0, 1, 4, 5);
  b[2] = __builtin_shufflevector(a0, a2, 2, 3, 6, 7); b[3] = __builtin_shufflevector(a1, a3, 2, 3, 6, 7);
#else
  KnV a0 = __builtin_shufflevector(b[0], b[1], 0, 2), a1 = __builtin_shufflevector(b[0], b[1], 1, 3);
  b[0] = a0; b[1] = a1;
#endif
}

KN_WIDE static inline void kn_v_hop_coefs(Kn* k, size_t at, KnV* l, KnV* c, KnV* cl) {
  KnH h;
  memcpy(&h, k->ph + at, sizeof h);
  *c = kn_v_load(k->pck + at);
  *l = 10.0 * __builtin_convertvector((KnS)h, KnV);
  *cl = *c * *l;
}

KN_WIDE static inline KnV kn_v_norm(KnV dx, KnV dy) {
  KnV x = (KnV)((KnM)dx & INT64_MAX), y = (KnV)((KnM)dy & INT64_MAX);
  x = (KnV)((KnM)x | ((KnM)(x != x) & (int64_t)0x0008000000000000));
  KnM swap = (KnM)(x < y);
  KnV hi = kn_v_pick(swap, y, x), lo = kn_v_pick(swap, x, y), rat = lo / hi;
  KnV far = kn_v_pick((KnM)(hi * 2.220446049250313e-16 >= lo), hi, hi * __builtin_elementwise_sqrt(1.0 + rat * rat));
  return kn_v_pick((KnM)(x == INFINITY) | (KnM)(y == INFINITY), (KnV){} + INFINITY, far);
}

KN_WIDE static inline int kn_v_none_contend(Kn* k, u32 u, KnV x, KnV y, double delta) {
  kn_v_save(k->gx + u, x); kn_v_save(k->gy + u, y);
  KnV b = ((KnV)((KnM)x & INT64_MAX) + (KnV)((KnM)y & INT64_MAX)) * 0x1.0000000000008p+0;
  KnM e = ((KnM)b >> 52) & 2047, loose = (e >= 23) & (e <= 2023) & (KnM)(b < delta);
  KnV sq = x * x + y * y;
  KnM tight = (KnM)(sq >= 0x1p-900) & (KnM)(sq * 1.0000000000036380 < delta * delta);
  return __builtin_reduce_and(delta < 0x1p450 ? loose | tight : loose) != 0;
}

KN_WIDE static u32 kn_v_refresh(Kn* k, u32 m, u32 i, u32 end, double* sums) {
  size_t row = KN_AT(k, m, 0);
  Kn2 s = {sums[0], sums[1]};
  for (; i + KN_W <= end; i += KN_W) {
    KnV dx = k->x[m] - kn_v_load(k->x + i), dy = k->y[m] - kn_v_load(k->y + i), d = kn_v_norm(dx, dy), l, c, cl;
    kn_v_hop_coefs(k, row + i, &l, &c, &cl);
    KnV r = l / d, x = c * (dx - r * dx), y = c * (dy - r * dy);
    kn_v_save(k->px + row + i, x); kn_v_save(k->py + row + i, y); kn_v_save(k->pd + row + i, d);
#if KN_W == 4
    KnV lo = __builtin_shufflevector(x, y, 0, 4, 2, 6), hi = __builtin_shufflevector(x, y, 1, 5, 3, 7);
    s = s + __builtin_shufflevector(lo, lo, 0, 1); s = s + __builtin_shufflevector(hi, hi, 0, 1);
    s = s + __builtin_shufflevector(lo, lo, 2, 3); s = s + __builtin_shufflevector(hi, hi, 2, 3);
#else
    s = s + __builtin_shufflevector(x, y, 0, 2); s = s + __builtin_shufflevector(x, y, 1, 3);
#endif
  }
  sums[0] = s[0]; sums[1] = s[1];
  return i;
}

KN_WIDE static u32 kn_v_hessian(Kn* k, u32 p, u32 i, u32 end, double* hs) {
  size_t row = KN_AT(k, p, 0);
  Kn4 h = {hs[0], hs[1], hs[2], hs[3]};
  for (; i + KN_W <= end; i += KN_W) {
    KnV dx = k->x[p] - kn_v_load(k->x + i), dy = k->y[p] - kn_v_load(k->y + i), d = kn_v_load(k->pd + row + i), l, c, cl;
    kn_v_hop_coefs(k, row + i, &l, &c, &cl);
    KnV d2 = d * d, inv = 1.0 / (d2 * d);
    KnV t[4] = {c * (1.0 + (l * (dx * dx - d2)) * inv), ((cl * dx) * dy) * inv, ((cl * dy) * dx) * inv,
      c * (1.0 + (l * (dy * dy - d2)) * inv)};
#if KN_W == 4
    kn_v_transpose(t);
    for (int j = 0; j < 4; j++) h = h + t[j];
#else
    h = h + __builtin_shufflevector(__builtin_shufflevector(t[0], t[1], 0, 2), __builtin_shufflevector(t[2], t[3], 0, 2), 0, 1, 2, 3);
    h = h + __builtin_shufflevector(__builtin_shufflevector(t[0], t[1], 1, 3), __builtin_shufflevector(t[2], t[3], 1, 3), 0, 1, 2, 3);
#endif
  }
  hs[0] = h[0]; hs[1] = h[1]; hs[2] = h[2]; hs[3] = h[3];
  return i;
}

KN_WIDE static u32 kn_v_outgoing(Kn* k, u32 m, u32 i, u32 end, double* ox, double* oy) {
  size_t row = KN_AT(k, m, 0);
  for (; i + KN_W <= end; i += KN_W) {
    KnV x = kn_v_load(k->px + row + i), y = kn_v_load(k->py + row + i);
    kn_v_save(ox + i, -x); kn_v_save(oy + i, -y);
    KnM exact = (KnM)(x != 0.0) & (KnM)(x == x) & (KnM)(y != 0.0) & (KnM)(y == y);
    if (__builtin_reduce_and(exact) == 0)
      for (int j = 0; j < KN_W; j++)
        if (!exact[j]) { double d; kn_partial(k, i + j, m, &ox[i + j], &oy[i + j], &d); }
  }
  return i;
}

KN_WIDE static u32 kn_v_pick_row_sums(Kn* k, u32* p, double* delta) {
  u32 n = k->n, u = 0;
  for (; u + KN_W <= n; u += KN_W) {
    KnV sx = {0.0}, sy = {0.0};
    u32 i = 0;
    for (; i + KN_W <= n; i += KN_W) {
      KnV bx[KN_W], by[KN_W];
      for (int r = 0; r < KN_W; r++) { bx[r] = kn_v_load(k->px + KN_AT(k, u + r, i)); by[r] = kn_v_load(k->py + KN_AT(k, u + r, i)); }
      kn_v_transpose(bx); kn_v_transpose(by);
      for (int j = 0; j < KN_W; j++) { sx = sx + bx[j]; sy = sy + by[j]; }
    }
    for (; i < n; i++) {
      KnV cx, cy;
      for (int r = 0; r < KN_W; r++) { cx[r] = k->px[KN_AT(k, u + r, i)]; cy[r] = k->py[KN_AT(k, u + r, i)]; }
      sx = sx + cx; sy = sy + cy;
    }
    if (kn_v_none_contend(k, u, sx, sy, *delta)) continue;
    KnV d = kn_v_norm(sx, sy);
    for (int r = 0; r < KN_W; r++)
      if (kn_gradient_contends(k, u + r, sx[r], sy[r], *delta) && d[r] > *delta) { *p = u + r; *delta = d[r]; }
  }
  return u;
}

KN_WIDE static u32 kn_v_pick_moved(Kn* k, u32* p, double* delta) {
  u32 u = 0;
  for (; u + KN_W <= k->n; u += KN_W) {
    KnV x = kn_v_load(k->gx + u) + (kn_v_load(k->cx + u) - kn_v_load(k->qx + u));
    KnV y = kn_v_load(k->gy + u) + (kn_v_load(k->cy + u) - kn_v_load(k->qy + u));
    if (kn_v_none_contend(k, u, x, y, *delta)) continue;
    KnV d = kn_v_norm(x, y);
    for (int j = 0; j < KN_W; j++)
      if (kn_gradient_contends(k, u + j, x[j], y[j], *delta) && d[j] > *delta) { *p = u + j; *delta = d[j]; }
  }
  return u;
}
#else
static u32 kn_v_refresh(Kn* k, u32 m, u32 i, u32 end, double* sums) { return i; }
static u32 kn_v_hessian(Kn* k, u32 p, u32 i, u32 end, double* hs) { return i; }
static u32 kn_v_outgoing(Kn* k, u32 m, u32 i, u32 end, double* ox, double* oy) { return i; }
static u32 kn_v_pick_row_sums(Kn* k, u32* p, double* delta) { return 0; }
static u32 kn_v_pick_moved(Kn* k, u32* p, double* delta) { return 0; }
#endif

static void kn_refresh(Kn* k, u32 m, u32 i, u32 end, double* sums) {
  if (KN_WIDE_OK()) i = kn_v_refresh(k, m, i, end, sums);
  double sx = sums[0], sy = sums[1];
  for (; i < end; i++) {
    double x, y, d;
    size_t at = KN_AT(k, m, i);
    kn_partial(k, m, i, &x, &y, &d);
    k->px[at] = x; k->py[at] = y; k->pd[at] = d;
    sx = sx + x; sy = sy + y;
  }
  sums[0] = sx; sums[1] = sy;
}

static void kn_hessian(Kn* k, u32 p, u32 i, u32 end, double* hs) {
  if (KN_WIDE_OK()) i = kn_v_hessian(k, p, i, end, hs);
  for (; i < end; i++) {
    double dx = k->x[p] - k->x[i], dy = k->y[p] - k->y[i];
    double d = k->pd[KN_AT(k, p, i)];
    u32 h = k->ph[KN_AT(k, p, i)];
    double d2 = d * d, inv = 1.0 / (d2 * d);
    hs[0] = hs[0] + k->ck[h] * (1.0 + (k->cl[h] * (dx * dx - d2)) * inv);
    hs[1] = hs[1] + ((k->ckl[h] * dx) * dy) * inv;
    hs[2] = hs[2] + ((k->ckl[h] * dy) * dx) * inv;
    hs[3] = hs[3] + k->ck[h] * (1.0 + (k->cl[h] * (dy * dy - d2)) * inv);
  }
}

static void kn_outgoing(Kn* k, u32 m, u32 i, u32 end, double* ox, double* oy) {
  if (KN_WIDE_OK()) i = kn_v_outgoing(k, m, i, end, ox, oy);
  for (; i < end; i++) {
    double x = k->px[KN_AT(k, m, i)], y = k->py[KN_AT(k, m, i)], d;
    ox[i] = -x; oy[i] = -y;
    if (!(kn_nonzero(x) && kn_nonzero(y))) kn_partial(k, i, m, &ox[i], &oy[i], &d);
  }
}

static double kn_row(Kn* k, u32 p) {
  double s[2] = {0.0, 0.0};
  kn_refresh(k, p, 0, p, s);
  s[0] = s[0] + 0.0; s[1] = s[1] + 0.0;
  kn_refresh(k, p, p + 1, k->n, s);
  k->gx[p] = s[0]; k->gy[p] = s[1];
  return kn_norm(s[0], s[1]);
}

static double kn_newton(Kn* k, u32 p) {
  double hs[4] = {0.0, 0.0, 0.0, 0.0};
  kn_hessian(k, p, 0, p, hs);
  kn_hessian(k, p, p + 1, k->n, hs);
  double h00 = hs[0], h01 = hs[1], h10 = hs[2], h11 = hs[3];
  double gx = k->gx[p], gy = k->gy[p];
  double den = h00 * h11 - h10 * h01;
  k->x[p] = k->x[p] + -((gx * h11 - gy * h01) / den);
  k->y[p] = k->y[p] + -((h00 * gy - h10 * gx) / den);
  return kn_row(k, p);
}

static int kn_cycle(double* hx, double* hy, u32 m) {
  for (u32 j = 1; j < m; j++)
    if (kn_bits(hx[j]) == kn_bits(hx[m]) && kn_bits(hy[j]) == kn_bits(hy[m])) return (int)j;
  return 0;
}

static double kn_inner(Kn* k, u32 p) {
  double hx[102], hy[102], delta = 0.0;
  for (u32 m = 1;; m++) {
    delta = kn_newton(k, p);
    hx[m] = k->x[p]; hy[m] = k->y[p];
    if (m > 100 || delta < 0.001) break;
    u32 j = (u32)kn_cycle(hx, hy, m);
    if (j) {
      u32 t = j + (101 - j) % (m - j);
      k->x[p] = hx[t]; k->y[p] = hy[t];
      delta = kn_row(k, p);
      break;
    }
  }
  kn_outgoing(k, p, 0, k->n, k->cx, k->cy);
  k->cx[p] = 0.0; k->cy[p] = 0.0;
  kn_flush(k, p, 0, k->n);
  return delta;
}

static void kn_run(Kn* k) {
  u32 n = k->n, p = 0;
  double delta = 0.0, last = 0.0;
  for (u32 u = KN_WIDE_OK() ? kn_v_pick_row_sums(k, &p, &delta) : 0; u < n; u++) {
    double sx = 0.0, sy = 0.0;
    for (u32 i = 0; i < n; i++) { sx = sx + k->px[KN_AT(k, u, i)]; sy = sy + k->py[KN_AT(k, u, i)]; }
    kn_pick(k, u, sx, sy, &p, &delta);
  }
  for (u32 outer = 1; outer <= 100; outer++) {
    double diff = last - delta;
    if (diff < 0.0) diff = -diff;
    last = delta;
    if (diff < 0.001) return;
    kn_outgoing(k, p, 0, n, k->qx, k->qy);
    k->qx[p] = 0.0; k->qy[p] = 0.0;
    delta = kn_inner(k, p);
    for (u32 u = KN_WIDE_OK() ? kn_v_pick_moved(k, &p, &delta) : 0; u < n; u++) kn_pick(k, u, k->gx[u] + (k->cx[u] - k->qx[u]), k->gy[u] + (k->cy[u] - k->qy[u]), &p, &delta);
  }
}

static int kn_hops(Kn* k) {
  u32 n = k->n, *start = io_mem(calloc(n + 1, 4)), *adj = io_mem(malloc((k->arcs + 1) * 4)), *q = io_mem(malloc(n * 4 + 4)), *row = io_mem(malloc(n * 4 + 4));
  int ok = 1;
  for (u32 a = 0; a < k->arcs; a++) ok = ok && k->arc[2 * a] < n && k->arc[2 * a + 1] < n;
  if (!ok) k->arcs = 0;
  for (u32 a = 0; a < k->arcs; a++) start[k->arc[2 * a] + 1]++;
  for (u32 v = 0; v < n; v++) start[v + 1] += start[v];
  u32* at = memcpy(io_mem(malloc((n + 1) * 4)), start, (n + 1) * 4);
  for (u32 a = 0; a < k->arcs; a++) adj[at[k->arc[2 * a]]++] = k->arc[2 * a + 1];
  for (u32 s = 0; s < n; s++) {
    u32 head = 0, tail = 1;
    memset(row, 0xff, n * 4);
    row[s] = 0; q[0] = s;
    while (head < tail) {
      u32 u = q[head++];
      for (u32 j = start[u]; j < start[u + 1]; j++)
        if (row[adj[j]] == 0xffffffffu) { row[adj[j]] = row[u] + 1; q[tail++] = adj[j]; }
    }
    for (u32 v = 0; v < n; v++) { k->ph[KN_AT(k, s, v)] = row[v]; ok = ok && (s || row[v] != 0xffffffffu); }
  }
  for (u32 a = 0; a < n; a++)
    for (u32 b = 0; b < a; b++) ok = ok && k->ph[KN_AT(k, a, b)] == k->ph[KN_AT(k, b, a)];
  free(start); free(adj); free(q); free(at); free(row);
  return ok && n;
}

static void kn_layout(Kn* k) {
  u32 n = k->n;
  if (!kn_hops(k)) return;
  for (u32 d = 0; d < n; d++) { double h = (double)d; k->cl[d] = 10.0 * h; k->ck[d] = 1.0 / (h * h); k->ckl[d] = k->ck[d] * k->cl[d]; }
  for (size_t at = 0; at < (size_t)n * n; at++) k->pck[at] = k->ck[k->ph[at]];
  double unused[2] = {0.0, 0.0};
  for (u32 m = 0; m < n; m++) { kn_refresh(k, m, m + 1, n, unused); kn_outgoing(k, m, m + 1, n, k->cx, k->cy); kn_flush(k, m, m + 1, n); }
  for (u32 r = 0; r <= k->left; r++) kn_run(k);
}

static void native_kk_call(IoWork* w) {
  Kn* k = (Kn*)w->data;
  u32 n = k->n;
  size_t nn = (size_t)n * n + 1;
  k->px = io_mem(calloc(3 * nn, 8));
  k->py = k->px + nn; k->pd = k->py + nn;
  k->ph = io_mem(calloc(nn, 4));
  k->pck = io_mem(calloc(nn, 8));
  k->gx = io_mem(calloc(9 * (size_t)n + 1, 8));
  k->gy = k->gx + n; k->qx = k->gy + n; k->qy = k->qx + n; k->cl = k->qy + n; k->ck = k->cl + n; k->ckl = k->ck + n;
  k->cx = k->ckl + n; k->cy = k->cx + n;
  kn_layout(k);
  free(k->px); free(k->ph); free(k->pck); free(k->gx);
}

static Term native_kk_pack(Env e, IoWork* w) {
  Kn* k = (Kn*)w->data;
  u32 cls = 1;
  while ((1ull << cls) < 1 + 4ull * k->n) cls++;
  u64 l = heap_alloc(e, buf_wcls(cls));
  if (err_seen(e.mem)) {
    free(k->x); free(k->arc); free(k);
    return term_buf(0, l);
  }
  u32a* out = blk_ptr(e.mem, l, 0);
  memset((void*)out, 0, 4ull << cls);
  out[0] = k->n;
  for (u32 v = 0; v < k->n; v++) {
    uint64_t bx = kn_bits(k->x[v]), by = kn_bits(k->y[v]);
    out[1 + 4 * v] = (u32)(bx >> 32); out[2 + 4 * v] = (u32)bx;
    out[3 + 4 * v] = (u32)(by >> 32); out[4 + 4 * v] = (u32)by;
  }
  free(k->x); free(k->arc); free(k);
  return term_blk(false, cls, l);
}

static u32 kn_next(const u32a* in, u64 len, u64* at) {
  return *at < len ? in[(*at)++] : 0;
}

Term native_kk_run(Env e, Term* f, IoWork* w) {
  Term a = f[0];
  const u32a* in = blk_ptr(e.mem, blk_loc(e.mem, a), 0);
  u64 len = 1ull << blk_cls(a), at = 0;
  Kn* k = io_mem(calloc(1, sizeof(Kn)));
  k->n = kn_next(in, len, &at); k->left = kn_next(in, len, &at); k->arcs = kn_next(in, len, &at);
  k->arc = io_mem(malloc(((size_t)k->arcs * 2 + 1) * 4));
  for (u32 i = 0; i < 2 * k->arcs; i++) k->arc[i] = kn_next(in, len, &at);
  k->x = io_mem(malloc(((size_t)k->n * 2 + 1) * 8));
  k->y = k->x + k->n;
  for (u32 v = 0; v < k->n; v++) {
    uint64_t xh = kn_next(in, len, &at), xl = kn_next(in, len, &at), yh = kn_next(in, len, &at), yl = kn_next(in, len, &at);
    k->x[v] = kn_dbl(xh << 32 | xl); k->y[v] = kn_dbl(yh << 32 | yl);
  }
  blk_free(e, a);
  w->data = (char*)k;
  return io_work(w, native_kk_call, native_kk_pack);
}

static void __attribute__((constructor)) native_kk_use(void) {
  io_eff(CID(native_kk), native_kk_run, 0);
}
