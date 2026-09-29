import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../data/blob.bend as Blob
import ../data/powf.bend as PowfData

# powf(x, y) bit-exact with the dedicated servers' C runtimes, for 0 <= x <= 1 and finite y > 0 (the growing-tree
# maze pop: x = (float)u * 2^-32, y = the maze exponent). Linux: glibc 2.41's __powf_fma (log2 and exp2 in double
# with fused multiply-adds). Windows: MSVCR90's powf (SSE2 doubles, no fused operations).

def f64_at(+xs: List<&2, U32>, +j: U32) -> F64Repr.F64:
  F64Repr.F64{Blob.word(xs, j), Blob.word(xs, (j + 2 : U32))}

def lo_of(x: F64Repr.F64) -> U32:
  match x:
    case F64Repr.F64{h, +l}:
      l

def hi_of(x: F64Repr.F64) -> U32:
  match x:
    case F64Repr.F64{+h, l}:
      h

def neg_one() -> F64Repr.F64:
  F64Repr.F64{3220176896, 0}

def sar23(+x: U32) -> U32:
  ((x >> 23n) .|. Bool.pick(U32, U32.is_zero((x >> 31n : U32)), 0, 4294966784) : U32)

def glibc_log2_tail(+r: F64Repr.F64, +y0: F64Repr.F64) -> F64Repr.F64:
  +r2 = F64Arith.mul(r, r)
  +r4 = F64Arith.mul(r2, r2)
  +y = F64Arith.fma(r, PowfData.glibc_log2_a0(), PowfData.glibc_log2_a1())
  +p = F64Arith.fma(r, PowfData.glibc_log2_a2(), PowfData.glibc_log2_a3())
  +q = F64Arith.fma(r2, p, F64Arith.fma(r, PowfData.glibc_log2_a4(), y0))
  F64Arith.fma(y, r4, q)

def glibc_log2_reduced(+row: List<&2, U32>, +z: F64Repr.F64, +k: U32) -> F64Repr.F64:
  glibc_log2_tail(F64Arith.fma(z, f64_at(row, 0), neg_one()), F64Arith.add(f64_at(row, 4), F64Repr.from_i32(k)))

# log2(x) for the float bits ix of a normal x.
def glibc_log2(+ix: U32) -> F64Repr.F64:
  +tmp = (ix - 1060306944 : U32)
  +top = (tmp .&. 4286578688 : U32)
  glibc_log2_reduced(PowfData.glibc_log2_tab(((tmp >> 19n) .&. 15 : U32)), F64Repr.from_f32_bits((ix - top : U32)), sar23(top))

def glibc_exp2_poly(+r: F64Repr.F64, +s: F64Repr.F64) -> F64Repr.F64:
  +r2 = F64Arith.mul(r, r)
  +z = F64Arith.fma(r, PowfData.glibc_exp2_c0(), PowfData.glibc_exp2_c1())
  +y = F64Arith.fma(r, PowfData.glibc_exp2_c2(), F64Repr.one())
  F64Arith.mul(F64Arith.fma(z, r2, y), s)

def glibc_exp2_scaled(+xd: F64Repr.F64, +kd: F64Repr.F64) -> F64Repr.F64:
  +row = PowfData.glibc_exp2_tab((lo_of(kd) .&. 31 : U32))
  glibc_exp2_poly(F64Arith.sub(xd, F64Arith.sub(kd, PowfData.glibc_exp2_shift())),
    F64Repr.F64{(Blob.word(row, 0) + (lo_of(kd) << 15n) : U32), Blob.word(row, 2)})

# The bits of 2^xd rounded to a float.
def glibc_exp2(+xd: F64Repr.F64) -> U32:
  F64Repr.to_f32_bits(glibc_exp2_scaled(xd, F64Arith.add(xd, PowfData.glibc_exp2_shift())))

def glibc_from_log(underflows: Bool, +ylogx: F64Repr.F64) -> U32:
  match underflows:
    case True{}:
      0
    case False{}:
      glibc_exp2(ylogx)

def glibc_nonzero(+ix: U32, +y: U32) -> U32:
  +ylogx = F64Arith.mul(F64Repr.from_f32_bits(y), glibc_log2(ix))
  glibc_from_log(F64Cmp.le(ylogx, F64Repr.from_i32(4294967146)), ylogx)

def glibc_checked(zero: Bool, +x: U32, +y: U32) -> U32:
  match zero:
    case True{}:
      0
    case False{}:
      glibc_nonzero(x, y)

# glibc powf on the float bits x and y.
def glibc(+x: U32, +y: U32) -> U32:
  glibc_checked(U32.is_zero(x), x, y)

def win_log_poly(+r: F64Repr.F64) -> F64Repr.F64:
  +r2 = F64Arith.mul(r, r)
  +r3 = F64Arith.mul(r2, r)
  +a4 = F64Arith.mul(F64Arith.add(F64Arith.mul(F64Repr.F64{1070596096, 0}, r), F64Repr.F64{1070945621, 1431655765}), r3)
  +a3 = F64Arith.mul(F64Arith.add(F64Arith.mul(F64Repr.half(), r), F64Repr.one()), r)
  F64Arith.add(a3, a4)

# y * ln(x) for the double bits (hi, lo) of a normal x.
def win_product(+hi: U32, +lo: U32, +y: F64Repr.F64) -> F64Repr.F64:
  +sum = ((hi .&. 1040384) + ((hi .&. 4096) << 1n) : U32)
  +idx = (sum >> 13n : U32)
  +m : F64Repr.F64 = F64Repr.F64{((hi .&. 1048575) .|. 1071644672 : U32), lo}
  +c : F64Repr.F64 = F64Repr.F64{(sum .|. 1071644672 : U32), 0}
  +r = F64Arith.mul(F64Arith.sub(c, m), f64_at(PowfData.win_recip_tab(idx), 0))
  +xe = F64Repr.from_i32(((hi >> 20n) - 1023 : U32))
  +s = F64Arith.sub(f64_at(PowfData.win_log_tab(idx), 0), win_log_poly(r))
  F64Arith.mul(F64Arith.add(s, F64Arith.mul(F64Repr.F64{1072049730, 4277811695}, xe)), y)

def sar5(+x: U32) -> U32:
  ((x >> 5n) .|. Bool.pick(U32, U32.is_zero((x >> 31n : U32)), 0, 4160749568) : U32)

def win_exp_poly(+rr: F64Repr.F64, +t2: F64Repr.F64, +k: U32) -> F64Repr.F64:
  +q3 = F64Arith.mul(F64Arith.mul(rr, rr), rr)
  +b4 = F64Arith.mul(F64Arith.add(F64Arith.mul(F64Repr.F64{1067799893, 1431655765}, rr), F64Repr.F64{1069897045, 1431655765}), q3)
  +b3 = F64Arith.mul(F64Arith.add(F64Arith.mul(F64Repr.half(), rr), F64Repr.one()), rr)
  +poly = F64Arith.add(b3, b4)
  F64Arith.mul(F64Arith.add(F64Arith.mul(poly, t2), t2), F64Repr.F64{((k + 1023) << 20n : U32), 0})

def win_exp_split(+tt: F64Repr.F64, +n: U32) -> F64Repr.F64:
  +j = (n .&. 31 : U32)
  win_exp_poly(F64Arith.sub(tt, F64Arith.mul(F64Repr.F64{1066806850, 4277811695}, F64Repr.from_i32(n))),
    f64_at(PowfData.win_exp2_tab(j), 0), sar5((n - j : U32)))

def win_exp_range(tiny: Bool, +tt: F64Repr.F64, +z: F64Repr.F64) -> U32:
  match tiny:
    case True{}:
      0
    case False{}:
      F64Repr.to_f32_bits(win_exp_split(tt, F64Repr.to_i32(F64Repr.rint(z))))

def win_exp_guard(huge: Bool, +tt: F64Repr.F64, +z: F64Repr.F64) -> U32:
  match huge:
    case True{}:
      2139095040
    case False{}:
      win_exp_range(F64Cmp.lt(z, F64Repr.from_i32(4294962528)), tt, z)

def win_from_product(+tt: F64Repr.F64) -> U32:
  +z = F64Arith.mul(F64Repr.F64{1078400327, 1697350398}, tt)
  win_exp_guard(F64Cmp.ge(z, F64Repr.from_i32(4096)), tt, z)

def win_nonzero(+xd: F64Repr.F64, +y: U32) -> U32:
  win_from_product(win_product(hi_of(xd), lo_of(xd), F64Repr.from_f32_bits(y)))

def win_general(identity: Bool, +x: U32, +y: U32) -> U32:
  match identity:
    case True{}:
      x
    case False{}:
      win_nonzero(F64Repr.from_f32_bits(x), y)

def win_checked(zero: Bool, +x: U32, +y: U32) -> U32:
  match zero:
    case True{}:
      0
    case False{}:
      win_general(U32.is_eq(y, 1065353216) || U32.is_eq(x, 1065353216), x, y)

# MSVCR90 powf on the float bits x and y.
def msvcr90(+x: U32, +y: U32) -> U32:
  win_checked(U32.is_zero(x), x, y)

# powf of the platform's runtime: MSVCR90's on Windows, glibc's on Linux.
def powf(+windows: Bool, +x: U32, +y: U32) -> U32:
  match windows:
    case True{}:
      msvcr90(x, y)
    case False{}:
      glibc(x, y)

# The bits of the growing-tree exponent (float)pow(e, -val) for val in -3..7 (both platforms round to the same float).
def maze_exponent(+val: U32) -> U32:
  Blob.word(PowfData.maze_exponent_tab((val + 3 : U32)), 0)

# The bits of (float)u * 2^-32 for a raw pcg32 output u.
def unit(+u: U32) -> U32:
  Bool.pick(U32, U32.is_zero(u), 0, (F64Repr.to_f32_bits(F64Repr.from_u32(u)) - 268435456 : U32))

# The growing-tree pop weight powf((float)u * 2^-32, e), as float bits.
def maze_weight(+windows: Bool, +u: U32, +e: U32) -> U32:
  powf(windows, unit(u), e)

# The index (int)((float)(count - 1) * weight) the growing tree picks from `count` active cells.
def maze_pick(+windows: Bool, +u: U32, +e: U32, +count: U32) -> U32:
  F64Repr.to_i32(F64Repr.from_f32_bits(F64Repr.to_f32_bits(F64Arith.mul(F64Repr.from_u32((count - 1 : U32)), F64Repr.from_f32_bits(maze_weight(windows, u, e))))))
