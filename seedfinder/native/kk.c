// Native KK
// =========
// worldsim/layout/kk.bend in IEEE doubles, same operation order (exact caches, cycle skipping, norm bound).
// Words in: n, left, arc count, arcs (from, to), then n positions (x hi, x lo, y hi, y lo). Words out: n positions.

#pragma STDC FP_CONTRACT OFF
#pragma clang fp contract(off)

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  double x, y, d;
  u32 h;
} KnPair;

typedef struct {
  u32 n, left, arcs, *arc;
  KnPair* pd;
  double *x, *y, *gx, *gy, *qx, *qy, *cl, *ck, *ckl;
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
  u32 h = k->pd[KN_AT(k, m, i)].h;
  double r = k->cl[h] / d;
  *ox = k->ck[h] * (dx - r * dx);
  *oy = k->ck[h] * (dy - r * dy);
  *od = d;
}
static int kn_nonzero(double x) { return x != 0.0 && x == x; }
static void kn_refresh(Kn* k, u32 m, u32 i) {
  double x, y, d;
  KnPair *a = &k->pd[KN_AT(k, m, i)], *b = &k->pd[KN_AT(k, i, m)];
  kn_partial(k, m, i, &x, &y, &d);
  a->x = x; a->y = y; a->d = d;
  if (kn_nonzero(x) && kn_nonzero(y)) { b->x = -x; b->y = -y; b->d = d; return; }
  kn_partial(k, i, m, &x, &y, &d);
  b->x = x; b->y = y; b->d = d;
}

static double kn_row(Kn* k, u32 p) {
  double sx = 0.0, sy = 0.0;
  for (u32 i = 0; i < k->n; i++) {
    if (i == p) { sx = sx + 0.0; sy = sy + 0.0; continue; }
    kn_refresh(k, p, i);
    sx = sx + k->pd[KN_AT(k, p, i)].x; sy = sy + k->pd[KN_AT(k, p, i)].y;
  }
  k->gx[p] = sx; k->gy[p] = sy;
  return kn_norm(sx, sy);
}

static double kn_newton(Kn* k, u32 p) {
  double h00 = 0.0, h01 = 0.0, h10 = 0.0, h11 = 0.0;
  for (u32 i = 0; i < k->n; i++) {
    if (i == p) continue;
    double dx = k->x[p] - k->x[i], dy = k->y[p] - k->y[i];
    double d = k->pd[KN_AT(k, p, i)].d;
    u32 h = k->pd[KN_AT(k, p, i)].h;
    double d2 = d * d, inv = 1.0 / (d2 * d);
    h00 = h00 + k->ck[h] * (1.0 + (k->cl[h] * (dx * dx - d2)) * inv);
    h01 = h01 + ((k->ckl[h] * dx) * dy) * inv;
    h10 = h10 + ((k->ckl[h] * dy) * dx) * inv;
    h11 = h11 + k->ck[h] * (1.0 + (k->cl[h] * (dy * dy - d2)) * inv);
  }
  double gx = k->gx[p], gy = k->gy[p];
  double den = h00 * h11 - h10 * h01;
  k->x[p] = k->x[p] + -((gx * h11 - gy * h01) / den);
  k->y[p] = k->y[p] + -((h00 * gy - h10 * gx) / den);
  return kn_row(k, p);
}

static void kn_pick(Kn* k, u32 u, double x, double y, u32* p, double* delta) {
  k->gx[u] = x; k->gy[u] = y;
  double b = (fabs(x) + fabs(y)) * 0x1.0000000000008p+0;
  u32 e = (u32)(kn_bits(b) >> 52) & 2047;
  if (e >= 23 && e <= 2023 && b < *delta) return;
  double d = kn_norm(x, y);
  if (d > *delta) { *p = u; *delta = d; }
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
    if (m > 100 || delta < 0.001) return delta;
    u32 j = (u32)kn_cycle(hx, hy, m);
    if (j) {
      u32 t = j + (101 - j) % (m - j);
      k->x[p] = hx[t]; k->y[p] = hy[t];
      return kn_row(k, p);
    }
  }
}

static void kn_run(Kn* k) {
  u32 n = k->n, p = 0;
  double delta = 0.0, last = 0.0;
  for (u32 u = 0; u < n; u++) {
    double sx = 0.0, sy = 0.0;
    for (u32 i = 0; i < n; i++) { sx = sx + k->pd[KN_AT(k, u, i)].x; sy = sy + k->pd[KN_AT(k, u, i)].y; }
    kn_pick(k, u, sx, sy, &p, &delta);
  }
  for (u32 outer = 1; outer <= 100; outer++) {
    double diff = last - delta;
    if (diff < 0.0) diff = -diff;
    last = delta;
    if (diff < 0.001) return;
    for (u32 i = 0; i < n; i++) { k->qx[i] = k->pd[KN_AT(k, i, p)].x; k->qy[i] = k->pd[KN_AT(k, i, p)].y; }
    delta = kn_inner(k, p);
    u32 old = p;
    for (u32 u = 0; u < n; u++)
      kn_pick(k, u, k->gx[u] + (k->pd[KN_AT(k, u, old)].x - k->qx[u]), k->gy[u] + (k->pd[KN_AT(k, u, old)].y - k->qy[u]), &p, &delta);
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
    for (u32 v = 0; v < n; v++) { k->pd[KN_AT(k, s, v)].h = row[v]; ok = ok && (s || row[v] != 0xffffffffu); }
  }
  free(start); free(adj); free(q); free(at); free(row);
  return ok && n;
}

static void kn_layout(Kn* k) {
  u32 n = k->n;
  if (!kn_hops(k)) return;
  for (u32 d = 0; d < n; d++) { double h = (double)d; k->cl[d] = 10.0 * h; k->ck[d] = 1.0 / (h * h); k->ckl[d] = k->ck[d] * k->cl[d]; }
  for (u32 m = 0; m < n; m++) for (u32 i = m + 1; i < n; i++) kn_refresh(k, m, i);
  for (u32 r = 0; r <= k->left; r++) kn_run(k);
}

static void native_kk_call(IoWork* w) {
  Kn* k = (Kn*)w->data;
  u32 n = k->n;
  size_t nn = (size_t)n * n + 1;
  k->pd = io_mem(calloc(nn, sizeof(KnPair)));
  k->gx = io_mem(calloc(9 * (size_t)n + 1, 8));
  k->gy = k->gx + n; k->qx = k->gy + n; k->qy = k->qx + n; k->cl = k->qy + n; k->ck = k->cl + n; k->ckl = k->ck + n;
  kn_layout(k);
  free(k->pd); free(k->gx);
}

static Term native_kk_pack(Env e, IoWork* w) {
  Kn* k = (Kn*)w->data;
  Term xs = term_pak(CID_NIL, 0);
  for (u32 v = k->n; v > 0; v--) {
    uint64_t bx = kn_bits(k->x[v - 1]), by = kn_bits(k->y[v - 1]);
    xs = io_node(e, CID_CON, (u32)by, xs);
    xs = io_node(e, CID_CON, (u32)(by >> 32), xs);
    xs = io_node(e, CID_CON, (u32)bx, xs);
    xs = io_node(e, CID_CON, (u32)(bx >> 32), xs);
  }
  free(k->x); free(k->arc); free(k);
  return xs;
}

static u32 kn_take(Env e, Term* xs) {
  if (term_aux(*xs) != CID_CON) return 0;
  Term fb[2];
  spare_free(e, cls_fit(2), ctr_take(e, *xs, 2, fb));
  *xs = fb[1];
  return (u32)fb[0];
}

Term native_kk_run(Env e, Term* f, IoWork* w) {
  Term xs = f[0];
  Kn* k = io_mem(calloc(1, sizeof(Kn)));
  k->n = kn_take(e, &xs); k->left = kn_take(e, &xs); k->arcs = kn_take(e, &xs);
  k->arc = io_mem(malloc(((size_t)k->arcs * 2 + 1) * 4));
  for (u32 a = 0; a < 2 * k->arcs; a++) k->arc[a] = kn_take(e, &xs);
  k->x = io_mem(malloc(((size_t)k->n * 2 + 1) * 8));
  k->y = k->x + k->n;
  for (u32 v = 0; v < k->n; v++) {
    uint64_t xh = kn_take(e, &xs), xl = kn_take(e, &xs), yh = kn_take(e, &xs), yl = kn_take(e, &xs);
    k->x[v] = kn_dbl(xh << 32 | xl); k->y[v] = kn_dbl(yh << 32 | yl);
  }
  while (term_aux(xs) == CID_CON) kn_take(e, &xs);
  w->data = (char*)k;
  return io_work(w, native_kk_call, native_kk_pack);
}

static void __attribute__((constructor)) native_kk_use(void) {
  io_eff(CID(native_kk), native_kk_run, 0);
}
