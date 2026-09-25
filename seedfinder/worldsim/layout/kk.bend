import Base
import ../../f64/word.bend as FW
import ../../f64/repr.bend as FR
import ../../f64/arith.bend as FA
import ../../f64/cmp.bend as FC
import ../../f64/hypot.bend as FH
import ../../data/constants.bend as KC
import ./space.bend as KS
import ./hops.bend as KH

# Boost 1.52 kamada_kawai_spring_layout (edge length 10, spring constant 1, unit weights) with Klei's KleiDone
# stop rule, in Boost's operation order, on the exact caches of the emulator's override
# (.scratch/worldsim/STATUS.md "KK speedup"): pair partials and distances kept current, mirrored as -pd when
# that is bit-exact. A Job advances by phase steps under a fuel bound, so a caller can cut a pass into rounds.

type Coef is Data:
  Coef{l: FR.F64, k: FR.F64, kl: FR.F64}

type Partial is Data:
  Partial{x: FR.F64, y: FR.F64, dist: FR.F64}

type Phase is Data:
  Start{}
  Check{}
  Newton{}
  Update{}
  Ended{}

# KleiDone's state (inner, outer, last) plus the run's outer iteration and Newton step counts and the number of
# runs still to start after this one.
type Clock is Data:
  Clock{inner: U32, outer: U32, last: FR.F64, outers: U32, newtons: U32, left: U32}

# A layout job: the workspace, the vertex count, the phase, the current vertex p and its delta, the clock, and
# whether the graph is connected (Boost returns false at once otherwise).
type Job is Type:
  Job{ws: Array<U32>, n: U32, phase: Phase, p: U32, delta: FR.F64, clock: Clock, ok: Bool}

type Stepped is Type:
  Stepped{go: Bool, job: Job}

type Hess is Type:
  Hess{ws: Array<U32>, h00: FR.F64, h01: FR.F64, h10: FR.F64, h11: FR.F64}

type Row is Type:
  Row{ws: Array<U32>, sx: FR.F64, sy: FR.F64}

type Pick is Type:
  Pick{ws: Array<U32>, p: U32, delta: FR.F64}

type Global is Data:
  Global{done: Bool, outer: U32, last: FR.F64}

def ten() -> FR.F64:
  FR.F64{1076101120, 0}

def tolerance() -> FR.F64:
  FR.F64{1062232653, 3539053052}

def max_iterations() -> U32:
  100

# hypot(0, x): |x|, quieted when x is a NaN.
def inner_hypot(x: FR.F64) -> FR.F64:
  match x:
    case FR.F64{+h, +l}:
      FR.pick(FR.is_nan_words(h, l), FR.quiet_words((h .&. FR.abs_mask() : U32), l), FR.F64{h, l})

# topology.norm: hypot(hypot(0, dx), dy), the inner hypot done exactly without its arithmetic.
def norm_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, +dx: FR.F64, +dy: FR.F64) -> FR.F64:
  FH.hypot_by(~mulhi, inner_hypot(dx), dy)

def norm(+dx: FR.F64, +dy: FR.F64) -> FR.F64:
  norm_by(~FW.mul_hi, dx, dy)

# l = 10 * d, k = 1 / (d * d) and the Hessian's k * l for a hop count d.
def coef_of(+d: U32) -> Coef:
  +h = FR.from_u32(d)
  +l = FA.mul(ten(), h)
  +k = FA.div(FR.one(), FA.mul(h, h))
  Coef{l, k, FA.mul(k, l)}

def partial_scaled_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, +dx: FR.F64, +dy: FR.F64, +dist: FR.F64, +r: FR.F64, +k: FR.F64) -> Partial:
  Partial{FA.mul_by(~mulhi, k, FA.sub(dx, FA.mul_by(~mulhi, r, dx))), FA.mul_by(~mulhi, k, FA.sub(dy, FA.mul_by(~mulhi, r, dy))), dist}

def partial_of_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, c: Coef, +dx: FR.F64, +dy: FR.F64, +dist: FR.F64) -> Partial:
  match c:
    case Coef{+l, +k, kl}:
      partial_scaled_by(~mulhi, dx, dy, dist, FA.div_by(~mulhi, l, dist), k)

# compute_partial_derivative(m, i) for positions a = pos[m], b = pos[i], with its distance.
def partial_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, a: KS.Vec, b: KS.Vec, c: Coef) -> Partial:
  match a:
    case KS.Vec{ax, ay}:
      match b:
        case KS.Vec{bx, by}:
          +dx = FA.sub(ax, bx)
          +dy = FA.sub(ay, by)
          partial_of_by(~mulhi, c, dx, dy, norm_by(~mulhi, dx, dy))

def partial(a: KS.Vec, b: KS.Vec, c: Coef) -> Partial:
  partial_by(~FW.mul_hi, a, b, c)

def nonzero_number(+x: FR.F64) -> Bool:
  Bool.not(FR.is_zero(x)) && Bool.not(FR.is_nan(x))

def exact_negation(p: Partial) -> Bool:
  match p:
    case Partial{+x, +y, dist}:
      nonzero_number(x) && nonzero_number(y)

def negated(p: Partial) -> Partial:
  match p:
    case Partial{x, y, dist}:
      Partial{FR.neg(x), FR.neg(y), dist}

def diag_term_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, +e: FR.F64, +dist2: FR.F64, +l: FR.F64, +k: FR.F64, +inv: FR.F64) -> FR.F64:
  FA.mul_by(~mulhi, k, FA.add(FR.one(), FA.mul_by(~mulhi, FA.mul_by(~mulhi, l, FA.sub(FA.mul_by(~mulhi, e, e), dist2)), inv)))

def cross_term_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, +kl: FR.F64, +a: FR.F64, +b: FR.F64, +inv: FR.F64) -> FR.F64:
  FA.mul_by(~mulhi, FA.mul_by(~mulhi, FA.mul_by(~mulhi, kl, a), b), inv)

# One vertex's contribution to the 2x2 Hessian of p: (h00, h01, h10, h11) plus the terms.
def hess_terms_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, c: Coef, ws: Array<U32>, +dx: FR.F64, +dy: FR.F64, +dist: FR.F64, +a: FR.F64, +b: FR.F64, +e: FR.F64, +d: FR.F64) -> Hess:
  match c:
    case Coef{+l, +k, +kl}:
      +dist2 = FA.mul_by(~mulhi, dist, dist)
      +inv = FA.div_by(~mulhi, FR.one(), FA.mul_by(~mulhi, dist2, dist))
      Hess{ws, FA.add(a, diag_term_by(~mulhi, dx, dist2, l, k, inv)), FA.add(b, cross_term_by(~mulhi, kl, dx, dy, inv)),
        FA.add(e, cross_term_by(~mulhi, kl, dy, dx, inv)), FA.add(d, diag_term_by(~mulhi, dy, dist2, l, k, inv))}

def hess_add_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, pp: KS.Vec, pi: KS.Vec, c: Coef, ws: Array<U32>, +dist: FR.F64, +a: FR.F64, +b: FR.F64, +e: FR.F64, +d: FR.F64) -> Hess:
  match pp:
    case KS.Vec{px, py}:
      match pi:
        case KS.Vec{ix, iy}:
          hess_terms_by(~mulhi, c, ws, FA.sub(px, ix), FA.sub(py, iy), dist, a, b, e, d)

def hess_add(pp: KS.Vec, pi: KS.Vec, c: Coef, ws: Array<U32>, +dist: FR.F64, +a: FR.F64, +b: FR.F64, +e: FR.F64, +d: FR.F64) -> Hess:
  hess_add_by(~FW.mul_hi, pp, pi, c, ws, dist, a, b, e, d)

# linear_solver<2> on the Hessian and gradient g, then topology.adjust(pos, -solution).
def solved_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, g: KS.Vec, pos: KS.Vec, +h00: FR.F64, +h01: FR.F64, +h10: FR.F64, +h11: FR.F64) -> KS.Vec:
  match g:
    case KS.Vec{+gx, +gy}:
      match pos:
        case KS.Vec{px, py}:
          +den = FA.sub(FA.mul_by(~mulhi, h00, h11), FA.mul_by(~mulhi, h10, h01))
          KS.Vec{FA.add(px, FR.neg(FA.div_by(~mulhi, FA.sub(FA.mul_by(~mulhi, gx, h11), FA.mul_by(~mulhi, gy, h01)), den))),
            FA.add(py, FR.neg(FA.div_by(~mulhi, FA.sub(FA.mul_by(~mulhi, h00, gy), FA.mul_by(~mulhi, h10, gx)), den)))}

def solved(g: KS.Vec, pos: KS.Vec, +h00: FR.F64, +h01: FR.F64, +h10: FR.F64, +h11: FR.F64) -> KS.Vec:
  solved_by(~FW.mul_hi, g, pos, h00, h01, h10, h11)

# The global KleiDone check: counts the outer iteration (done past 100) or compares |last - delta| < 0.001.
def global_capped(over: Bool, +next: U32, +delta: FR.F64, +last: FR.F64) -> Global:
  match over:
    case True{}:
      Global{True{}, 0, last}
    case False{}:
      +diff = FA.sub(last, delta)
      Global{FC.lt(FR.pick(FC.lt(diff, FR.zero()), FR.neg(diff), diff), tolerance()), next, delta}

def global_done(+delta: FR.F64, +outer: U32, +last: FR.F64) -> Global:
  +next = (outer + 1 : U32)
  global_capped((next > max_iterations() : U32), next, delta, last)

def coef_kl(got: Array<U32> & FR.F64, +l: FR.F64, +k: FR.F64) -> Array<U32> & Coef:
  (ws, kl) = got
  (ws, Coef{l, k, kl})

def coef_k(got: Array<U32> & FR.F64, +at: U32, +l: FR.F64) -> Array<U32> & Coef:
  (ws, k) = got
  coef_kl(KS.get(ws, (at + 4 : U32)), l, k)

def coef_l(got: Array<U32> & FR.F64, +at: U32) -> Array<U32> & Coef:
  (ws, l) = got
  coef_k(KS.get(ws, (at + 2 : U32)), at, l)

def coef_hop(got: Array<U32> & U32) -> Array<U32> & Coef:
  (ws, d) = got
  +at = KS.coef_at(d)
  coef_l(KS.get(ws, at), at)

def pair_coef(ws: Array<U32>, +m: U32, +i: U32) -> Array<U32> & Coef:
  coef_hop(ws[KS.hop_at(m, i)])

def store_partial(p: Partial, ws: Array<U32>, +m: U32, +i: U32) -> Array<U32>:
  match p:
    case Partial{x, y, dist}:
      KS.put(KS.put_vec(ws, KS.partial_at(m, i), KS.Vec{x, y}), KS.dist_at(m, i), dist)

def store_back(exact: Bool, ws: Array<U32>, +m: U32, +i: U32, +pm: KS.Vec, +pi: KS.Vec, +c: Coef, +p: Partial) -> Array<U32>:
  match exact:
    case True{}:
      store_partial(negated(p), ws, i, m)
    case False{}:
      store_partial(partial_by(~FW.mul_hi_nat, pi, pm, c), ws, i, m)

# refresh_pair(m, i): stores pd(m, i) and pd(i, m) with their distances; returns pd(m, i).
def refresh_pair(ws: Array<U32>, +m: U32, +i: U32, +pm: KS.Vec, +pi: KS.Vec, +c: Coef) -> Array<U32> & Partial:
  +p = partial_by(~FW.mul_hi_nat, pm, pi, c)
  (store_back(exact_negation(p), store_partial(p, ws, m, i), m, i, pm, pi, c, p), p)

def refresh_coef(got: Array<U32> & Coef, +i: U32, +m: U32, +pm: KS.Vec, +pi: KS.Vec) -> Array<U32>:
  (ws, c) = got
  Pair.fst(Array<U32>, Partial, refresh_pair(ws, m, i, pm, pi, c))

def refresh_pos(got: Array<U32> & KS.Vec, +i: U32, +m: U32, +pm: KS.Vec) -> Array<U32>:
  (ws, +pi) = got
  refresh_coef(pair_coef(ws, m, i), i, m, pm, pi)

def refresh_after(fuel: Nat, +i: U32, +m: U32, +pm: KS.Vec, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      refresh_after(f, (i + 1 : U32), m, pm, refresh_pos(KS.get_vec(ws, KS.pos_at(i)), i, m, pm))

def refresh_from(got: Array<U32> & KS.Vec, +m: U32, +n: U32) -> Array<U32>:
  (ws, +pm) = got
  refresh_after(U32.to_nat((n - m - 1 : U32)), (m + 1 : U32), m, pm, ws)

def refresh_rows(fuel: Nat, +m: U32, +n: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      refresh_rows(f, (m + 1 : U32), n, refresh_from(KS.get_vec(ws, KS.pos_at(m)), m, n))

# refresh_moved_vertices with every vertex moved: all pairs (m, i), m < i, in Boost's order.
def refresh_all(+n: U32, ws: Array<U32>) -> Array<U32>:
  refresh_rows(U32.to_nat(n), 0, n, ws)

def row_add(got: Array<U32> & Partial, +sx: FR.F64, +sy: FR.F64) -> Row:
  (ws, t) = got
  match t:
    case Partial{x, y, dist}:
      Row{ws, FA.add(sx, x), FA.add(sy, y)}

def row_coef(got: Array<U32> & Coef, +i: U32, +m: U32, +pm: KS.Vec, +pi: KS.Vec, +sx: FR.F64, +sy: FR.F64) -> Row:
  (ws, c) = got
  row_add(refresh_pair(ws, m, i, pm, pi, c), sx, sy)

def row_pos(got: Array<U32> & KS.Vec, +i: U32, +m: U32, +pm: KS.Vec, +sx: FR.F64, +sy: FR.F64) -> Row:
  (ws, +pi) = got
  row_coef(pair_coef(ws, m, i), i, m, pm, pi, sx, sy)

def row_step(same: Bool, st: Row, +i: U32, +m: U32, +pm: KS.Vec) -> Row:
  match same:
    case True{}:
      match st:
        case Row{ws, sx, sy}:
          Row{ws, FA.add(sx, FR.zero()), FA.add(sy, FR.zero())}
    case False{}:
      match st:
        case Row{ws, +sx, +sy}:
          row_pos(KS.get_vec(ws, KS.pos_at(i)), i, m, pm, sx, sy)

# update_partial_derivatives(m): refreshes row m against pos[m] = pm and sums it in ascending i.
def row_loop(fuel: Nat, +i: U32, +m: U32, +pm: KS.Vec, st: Row) -> Row:
  match fuel:
    case 0n:
      st
    case 1n+f:
      row_loop(f, (i + 1 : U32), m, pm, row_step(U32.is_eq(i, m), st, i, m, pm))

def hess_coef(got: Array<U32> & Coef, +pp: KS.Vec, +pi: KS.Vec, +dist: FR.F64, +a: FR.F64, +b: FR.F64, +e: FR.F64, +d: FR.F64) -> Hess:
  (ws, c) = got
  hess_add_by(~FW.mul_hi_nat, pp, pi, c, ws, dist, a, b, e, d)

def hess_dist(got: Array<U32> & FR.F64, +i: U32, +p: U32, +pp: KS.Vec, +pi: KS.Vec, +a: FR.F64, +b: FR.F64, +e: FR.F64, +d: FR.F64) -> Hess:
  (ws, +dist) = got
  hess_coef(pair_coef(ws, p, i), pp, pi, dist, a, b, e, d)

def hess_pos(got: Array<U32> & KS.Vec, +i: U32, +p: U32, +pp: KS.Vec, +a: FR.F64, +b: FR.F64, +e: FR.F64, +d: FR.F64) -> Hess:
  (ws, +pi) = got
  hess_dist(KS.get(ws, KS.dist_at(p, i)), i, p, pp, pi, a, b, e, d)

def hess_step(same: Bool, st: Hess, +i: U32, +p: U32, +pp: KS.Vec) -> Hess:
  match same:
    case True{}:
      st
    case False{}:
      match st:
        case Hess{ws, +a, +b, +e, +d}:
          hess_pos(KS.get_vec(ws, KS.pos_at(i)), i, p, pp, a, b, e, d)

def hess_loop(fuel: Nat, +i: U32, +p: U32, +pp: KS.Vec, st: Hess) -> Hess:
  match fuel:
    case 0n:
      st
    case 1n+f:
      hess_loop(f, (i + 1 : U32), p, pp, hess_step(U32.is_eq(i, p), st, i, p, pp))

def newton_finish(r: Row, +p: U32) -> Array<U32> & FR.F64:
  match r:
    case Row{ws, +sx, +sy}:
      (KS.put_vec(ws, KS.deriv_at(p), KS.Vec{sx, sy}), norm_by(~FW.mul_hi_nat, sx, sy))

def newton_store(got: Array<U32> & KS.Vec, +n: U32, +p: U32) -> Array<U32> & FR.F64:
  (ws, +np) = got
  placed = KS.put_vec(ws, KS.pos_at(p), np)
  newton_finish(row_loop(U32.to_nat(n), 0, p, np, Row{placed, FR.zero(), FR.zero()}), p)

def newton_solve(got: Array<U32> & KS.Vec, +pos: KS.Vec, +h00: FR.F64, +h01: FR.F64, +h10: FR.F64, +h11: FR.F64) -> Array<U32> & KS.Vec:
  (ws, g) = got
  (ws, solved_by(~FW.mul_hi_nat, g, pos, h00, h01, h10, h11))

def newton_grad(h: Hess, +pos: KS.Vec, +n: U32, +p: U32) -> Array<U32> & FR.F64:
  match h:
    case Hess{ws, +h00, +h01, +h10, +h11}:
      newton_store(newton_solve(KS.get_vec(ws, KS.deriv_at(p)), pos, h00, h01, h10, h11), n, p)

def newton_hess(got: Array<U32> & KS.Vec, +n: U32, +p: U32) -> Array<U32> & FR.F64:
  (ws, +pos) = got
  +z = FR.zero()
  newton_grad(hess_loop(U32.to_nat(n), 0, p, pos, Hess{ws, z, z, z, z}), pos, n, p)

# One Newton move of p: Hessian, solve, adjust, refresh row p; returns the new delta_p.
def newton(ws: Array<U32>, +n: U32, +p: U32) -> Array<U32> & FR.F64:
  newton_hess(KS.get_vec(ws, KS.pos_at(p)), n, p)

def choose(better: Bool, ws: Array<U32>, +u: U32, +p: U32, +d: FR.F64, +delta: FR.F64) -> Pick:
  match better:
    case True{}:
      Pick{ws, u, d}
    case False{}:
      Pick{ws, p, delta}

def bound_growth() -> FR.F64:
  FR.F64{1072693248, 8}

def in_bound_range(b: FR.F64) -> Bool:
  match b:
    case FR.F64{+h, l}:
      +e = FR.exp_field(h)
      (e >= 23 : U32) && (e <= 2023 : U32)

# fl(fl(|x| + |y|) * (1 + 2^-49)): at least norm(x, y) when it lies in [2^-1000, 2^1000] (hypot rounds up by at
# most 4 ulps of the exact norm, which is at most |x| + |y|; checked on random operands in test/f64).
def norm_bound(+x: FR.F64, +y: FR.F64) -> FR.F64:
  FA.mul_by(~FW.mul_hi_nat, FA.add(FR.abs(x), FR.abs(y)), bound_growth())

def surely_below(+b: FR.F64, +delta: FR.F64) -> Bool:
  in_bound_range(b) && FC.lt(b, delta)

def pick_norm(below: Bool, ws: Array<U32>, +x: FR.F64, +y: FR.F64, +u: U32, +p: U32, +delta: FR.F64) -> Pick:
  match below:
    case True{}:
      Pick{ws, p, delta}
    case False{}:
      +d = norm_by(~FW.mul_hi_nat, x, y)
      choose(FC.gt(d, delta), ws, u, p, d, delta)

# Stores the derivative of u and keeps the strict maximum of the norms; a norm surely below delta is not computed.
def pick_stored(v: KS.Vec, ws: Array<U32>, +u: U32, +p: U32, +delta: FR.F64) -> Pick:
  match v:
    case KS.Vec{+x, +y}:
      pick_norm(surely_below(norm_bound(x, y), delta), KS.put_vec(ws, KS.deriv_at(u), KS.Vec{x, y}), x, y, u, p, delta)

def sum_add(got: Array<U32> & KS.Vec, +sx: FR.F64, +sy: FR.F64) -> Row:
  (ws, t) = got
  match t:
    case KS.Vec{x, y}:
      Row{ws, FA.add(sx, x), FA.add(sy, y)}

def sum_loop(fuel: Nat, +i: U32, +u: U32, st: Row) -> Row:
  match fuel:
    case 0n:
      st
    case 1n+f:
      match st:
        case Row{ws, +sx, +sy}:
          sum_loop(f, (i + 1 : U32), u, sum_add(KS.get_vec(ws, KS.partial_at(u, i)), sx, sy))

def start_vertex(r: Row, +u: U32, +p: U32, +delta: FR.F64) -> Pick:
  match r:
    case Row{ws, sx, sy}:
      pick_stored(KS.Vec{sx, sy}, ws, u, p, delta)

def start_loop(fuel: Nat, +u: U32, +n: U32, st: Pick) -> Pick:
  match fuel:
    case 0n:
      st
    case 1n+f:
      match st:
        case Pick{ws, +p, +delta}:
          start_loop(f, (u + 1 : U32), n, start_vertex(sum_loop(U32.to_nat(n), 0, u, Row{ws, FR.zero(), FR.zero()}), u, p, delta))

# The run's first loop: every derivative summed from the cache, and the vertex of largest delta.
def start_sums(ws: Array<U32>, +n: U32) -> Pick:
  start_loop(U32.to_nat(n), 0, n, Pick{ws, 0, FR.zero()})

def pin_copy(got: Array<U32> & KS.Vec, +i: U32) -> Array<U32>:
  (ws, v) = got
  KS.put_vec(ws, KS.pinned_at(i), v)

def pin_loop(fuel: Nat, +i: U32, +p: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      pin_loop(f, (i + 1 : U32), p, pin_copy(KS.get_vec(ws, KS.partial_at(i, p)), i))

def shifted(d: KS.Vec, m: KS.Vec, q: KS.Vec) -> KS.Vec:
  match d:
    case KS.Vec{dx, dy}:
      match m:
        case KS.Vec{mx, my}:
          match q:
            case KS.Vec{qx, qy}:
              KS.Vec{FA.add(dx, FA.sub(mx, qx)), FA.add(dy, FA.sub(my, qy))}

def update_pinned(got: Array<U32> & KS.Vec, +d: KS.Vec, +m: KS.Vec, +i: U32, +p: U32, +delta: FR.F64) -> Pick:
  (ws, q) = got
  pick_stored(shifted(d, m, q), ws, i, p, delta)

def update_partial(got: Array<U32> & KS.Vec, +d: KS.Vec, +i: U32, +p: U32, +delta: FR.F64) -> Pick:
  (ws, +m) = got
  update_pinned(KS.get_vec(ws, KS.pinned_at(i)), d, m, i, p, delta)

def update_deriv(got: Array<U32> & KS.Vec, +i: U32, +old: U32, +p: U32, +delta: FR.F64) -> Pick:
  (ws, +d) = got
  update_partial(KS.get_vec(ws, KS.partial_at(i, old)), d, i, p, delta)

def update_loop(fuel: Nat, +i: U32, +old: U32, st: Pick) -> Pick:
  match fuel:
    case 0n:
      st
    case 1n+f:
      match st:
        case Pick{ws, +p, +delta}:
          update_loop(f, (i + 1 : U32), old, update_deriv(KS.get_vec(ws, KS.deriv_at(i)), i, old, p, delta))

def fresh_clock(+left: U32) -> Clock:
  Clock{0, 0, FR.zero(), 0, 0, left}

def clock_left(clock: Clock) -> U32:
  match clock:
    case Clock{inner, outer, last, outers, newtons, left}:
      left

def ended_at(finished: Bool, ws: Array<U32>, +n: U32, +p: U32, +delta: FR.F64, +clock: Clock, +ok: Bool) -> Stepped:
  match finished:
    case True{}:
      Stepped{False{}, Job{ws, n, Ended{}, p, delta, clock, ok}}
    case False{}:
      Stepped{True{}, Job{ws, n, Start{}, p, delta, fresh_clock((clock_left(clock) - 1 : U32)), ok}}

def started_pick(pick: Pick, +n: U32, +clock: Clock) -> Stepped:
  match pick:
    case Pick{ws, p, delta}:
      Stepped{True{}, Job{ws, n, Check{}, p, delta, clock, True{}}}

def started(ok: Bool, ws: Array<U32>, +n: U32, +clock: Clock) -> Stepped:
  match ok:
    case True{}:
      started_pick(start_sums(ws, n), n, clock)
    case False{}:
      Stepped{True{}, Job{ws, n, Ended{}, 0, FR.zero(), clock, False{}}}

def checked_done(done: Bool, clock: Clock, ws: Array<U32>, +n: U32, +p: U32, +delta: FR.F64, +outer: U32, +last: FR.F64) -> Stepped:
  match done:
    case True{}:
      match clock:
        case Clock{inner, old_outer, old_last, +outers, +newtons, +left}:
          Stepped{True{}, Job{ws, n, Ended{}, p, delta, Clock{0, outer, last, outers, newtons, left}, True{}}}
    case False{}:
      match clock:
        case Clock{inner, old_outer, old_last, +outers, +newtons, +left}:
          Stepped{True{}, Job{pin_loop(U32.to_nat(n), 0, p, ws), n, Newton{}, p, delta,
            Clock{0, outer, last, (outers + 1 : U32), newtons, left}, True{}}}

def checked_at(g: Global, clock: Clock, ws: Array<U32>, +n: U32, +p: U32, +delta: FR.F64) -> Stepped:
  match g:
    case Global{done, +outer, +last}:
      checked_done(done, clock, ws, n, p, delta, outer, last)

def checked(+clock: Clock, ws: Array<U32>, +n: U32, +p: U32, +delta: FR.F64) -> Stepped:
  match clock:
    case Clock{inner, +outer, +last, outers, newtons, left}:
      checked_at(global_done(delta, outer, last), clock, ws, n, p, delta)

def inner_cap() -> U32:
  101

def same_vec(a: KS.Vec, b: KS.Vec) -> Bool:
  match a:
    case KS.Vec{FR.F64{ah, al}, FR.F64{bh, bl}}:
      match b:
        case KS.Vec{FR.F64{ch, cl}, FR.F64{dh, dl}}:
          U32.is_eq(ah, ch) && U32.is_eq(al, cl) && U32.is_eq(bh, dh) && U32.is_eq(bl, dl)

def seen_at(got: Array<U32> & KS.Vec, +j: U32, +now: KS.Vec, +found: U32) -> Array<U32> & U32:
  (ws, +h) = got
  (ws, FW.pick(U32.is_zero(found) && same_vec(h, now), j, found))

def seen_loop(fuel: Nat, +j: U32, +now: KS.Vec, got: Array<U32> & U32) -> Array<U32> & U32:
  match fuel:
    case 0n:
      got
    case 1n+f:
      (ws, +found) = got
      seen_loop(f, (j + 1 : U32), now, seen_at(KS.get_vec(ws, KS.history_at(j)), j, now, found))

# The first move j < m whose position equals the position after move m (0 if none).
def seen_before(got: Array<U32> & KS.Vec, +m: U32) -> Array<U32> & U32:
  (ws, +now) = got
  seen_loop(U32.to_nat((m - 1 : U32)), 1, now, (ws, 0))

def recorded(got: Array<U32> & KS.Vec, +m: U32) -> Array<U32>:
  (ws, v) = got
  KS.put_vec(ws, KS.history_at(m), v)

def cycled(got: Array<U32> & FR.F64, +n: U32, +p: U32, +outer: U32, +last: FR.F64, +outers: U32, +newtons: U32, +left: U32) -> Stepped:
  (ws, +delta) = got
  Stepped{True{}, Job{ws, n, Update{}, p, delta, Clock{0, outer, last, outers, newtons, left}, True{}}}

def cycle_or_go(none: Bool, ws: Array<U32>, +j: U32, +n: U32, +p: U32, +delta: FR.F64, +m: U32, +outer: U32, +last: FR.F64, +outers: U32, +newtons: U32, +left: U32) -> Stepped:
  match none:
    case True{}:
      Stepped{True{}, Job{ws, n, Newton{}, p, delta, Clock{m, outer, last, outers, (newtons + 1 : U32), left}, True{}}}
    case False{}:
      +t = (j + U32.mod((inner_cap() - j : U32), (m - j : U32)) : U32)
      cycled(newton_store(KS.get_vec(ws, KS.history_at(t)), n, p), n, p, outer, last, outers,
        (newtons + 1 + inner_cap() - m : U32), left)

def cycle_check(got: Array<U32> & U32, +n: U32, +p: U32, +delta: FR.F64, +m: U32, +outer: U32, +last: FR.F64, +outers: U32, +newtons: U32, +left: U32) -> Stepped:
  (ws, +j) = got
  cycle_or_go(U32.is_zero(j), ws, j, n, p, delta, m, outer, last, outers, newtons, left)

# After move m of an inner loop the moving vertex's position is recorded. Moves 2.. are a fixed map of that position
# (the gradient is the fresh row sum), so a position seen at an earlier move j >= 1 repeats with period m - j and,
# no position of the cycle being below the tolerance, the loop runs to the cap: the last position is taken from the
# cycle, row p is refreshed there (the caches are a function of the positions), and the skipped moves are counted.
def moved_on(finished: Bool, ws: Array<U32>, +n: U32, +p: U32, +delta: FR.F64, +m: U32, +capped: Bool, +outer: U32, +last: FR.F64, +outers: U32, +newtons: U32, +left: U32) -> Stepped:
  match finished:
    case True{}:
      Stepped{True{}, Job{ws, n, Update{}, p, delta, Clock{FW.pick(capped, 0, m), outer, last, outers, (newtons + 1 : U32), left}, True{}}}
    case False{}:
      cycle_check(seen_before(KS.get_vec(ws, KS.history_at(m)), m), n, p, delta, m, outer, last, outers, newtons, left)

def moved_at(+capped: Bool, got: Array<U32> & FR.F64, +n: U32, +p: U32, +next: U32, +outer: U32, +last: FR.F64, +outers: U32, +newtons: U32, +left: U32) -> Stepped:
  (ws, +delta) = got
  +finished = capped || FC.lt(delta, tolerance())
  moved_on(finished, recorded(KS.get_vec(ws, KS.pos_at(p)), next), n, p, delta, next, capped, outer, last, outers,
    newtons, left)

def moved(+clock: Clock, got: Array<U32> & FR.F64, +n: U32, +p: U32) -> Stepped:
  match clock:
    case Clock{inner, +outer, +last, +outers, +newtons, +left}:
      +next = (inner + 1 : U32)
      moved_at((next > max_iterations() : U32), got, n, p, next, outer, last, outers, newtons, left)

def updated(pick: Pick, +n: U32, +clock: Clock) -> Stepped:
  match pick:
    case Pick{ws, p, delta}:
      Stepped{True{}, Job{ws, n, Check{}, p, delta, clock, True{}}}

def step_phase(phase: Phase, ws: Array<U32>, +n: U32, +p: U32, +delta: FR.F64, +clock: Clock, +ok: Bool) -> Stepped:
  match phase:
    case Start{}:
      started(ok, ws, n, clock)
    case Check{}:
      checked(clock, ws, n, p, delta)
    case Newton{}:
      moved(clock, newton(ws, n, p), n, p)
    case Update{}:
      updated(update_loop(U32.to_nat(n), 0, p, Pick{ws, p, delta}), n, clock)
    case Ended{}:
      ended_at(U32.is_zero(clock_left(clock)), ws, n, p, delta, clock, ok)

def step(job: Job) -> Stepped:
  match job:
    case Job{ws, +n, phase, +p, +delta, +clock, +ok}:
      step_phase(phase, ws, n, p, delta, clock, ok)

def advance_loop(fuel: Nat, st: Stepped) -> Job:
  match fuel:
    case 0n:
      match st:
        case Stepped{go, job}:
          job
    case 1n+f:
      match st:
        case Stepped{go, job}:
          match go:
            case True{}:
              advance_loop(f, step(job))
            case False{}:
              job

# Runs up to `fuel` phase steps (a run start, a global check, a Newton move or a derivative update each).
# Stops early once the job has ended its last run; a run that ends with runs left starts the next one.
def advance(fuel: Nat, job: Job) -> Job:
  advance_loop(fuel, Stepped{True{}, job})

# The most phase steps one run can take (100 outer iterations of a check, 101 Newton moves and an update).
def run_fuel() -> Nat:
  20480n

# Starts a new run (a fresh KleiDone) with `left` more runs to follow, keeping positions and caches.
def restart(job: Job, +left: U32) -> Job:
  match job:
    case Job{ws, n, phase, p, delta, clock, ok}:
      Job{ws, n, Start{}, p, delta, fresh_clock(left), ok}

def place_y(xy: U32 & U32, +v: U32, +x: FR.F64, ws: Array<U32>) -> Array<U32>:
  (hi, lo) = xy
  KS.put_vec(ws, KS.pos_at(v), KS.Vec{x, FR.F64{hi, lo}})

def place_x(xy: U32 & U32, +v: U32, ws: Array<U32>) -> Array<U32>:
  (hi, lo) = xy
  place_y(KC.kk_y(v), v, FR.F64{hi, lo}, ws)

def place_loop(fuel: Nat, +v: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      place_loop(f, (v + 1 : U32), place_x(KC.kk_x(v), v, ws))

# InitializeNodePoints / AddNewPositions: vertices first..n-1 take the minstd_rand positions (the baked table).
def place_new(+first: U32, +n: U32, ws: Array<U32>) -> Array<U32>:
  place_loop(U32.to_nat((n - first : U32)), first, ws)

def store_coef(c: Coef, +d: U32, ws: Array<U32>) -> Array<U32>:
  match c:
    case Coef{l, k, kl}:
      +at = KS.coef_at(d)
      KS.put(KS.put(KS.put(ws, at, l), (at + 2 : U32), k), (at + 4 : U32), kl)

def coef_loop(fuel: Nat, +d: U32, ws: Array<U32>) -> Array<U32>:
  match fuel:
    case 0n:
      ws
    case 1n+f:
      coef_loop(f, (d + 1 : U32), store_coef(coef_of(d), d, ws))

def refresh_if(ok: Bool, +n: U32, ws: Array<U32>) -> Array<U32>:
  match ok:
    case True{}:
      refresh_all(n, ws)
    case False{}:
      ws

def pass_ready(got: Array<U32> & Bool, +n: U32, +left: U32) -> Job:
  (ws, +ok) = got
  Job{refresh_if(ok, n, coef_loop(U32.to_nat(n), 0, ws)), n, Start{}, 0, FR.zero(), fresh_clock(left), ok}

# A VoronoiPass's layout job on the graph given by its arcs: vertices first..n-1 are new (first = 0 after
# InitializeNodePoints), the others keep their positions in ws. `left` runs follow the first.
def pass_job(ws: Array<U32>, +first: U32, +n: U32, +arcs: List<&2, KH.Arc>, +left: U32) -> Job:
  placed = place_new(first, n, KH.hop_matrix(n, KH.load_arcs(n, arcs, ws)))
  pass_ready(KH.connected(n, placed), n, left)

def listed(got: Array<U32> & KS.Vec, acc: List<&2, KS.Vec>) -> Array<U32> & List<&2, KS.Vec>:
  (ws, v) = got
  (ws, v <> acc)

def list_loop(fuel: Nat, +v: U32, got: Array<U32> & List<&2, KS.Vec>) -> Array<U32> & List<&2, KS.Vec>:
  match fuel:
    case 0n:
      got
    case 1n+f:
      (ws, acc) = got
      list_loop(f, (v - 1 : U32), listed(KS.get_vec(ws, KS.pos_at(v)), acc))

# The positions of vertices 0..n-1.
def positions(ws: Array<U32>, +n: U32) -> Array<U32> & List<&2, KS.Vec>:
  list_loop(U32.to_nat(n), (n - 1 : U32), (ws, Nil{}))
