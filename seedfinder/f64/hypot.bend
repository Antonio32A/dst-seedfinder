import Base
import ./word.bend as F64Word
import ./repr.bend as F64Repr
import ./arith.bend as F64Arith
import ./cmp.bend as F64Cmp

# boost::math::hypot (Boost 1.52 hypot_imp) for doubles, in its operation order. Boost raises an overflow error
# for an infinite argument; this returns +inf there.

def scaled(~mulhi: @+a:U32 -> @+b:U32 -> U32, +x: F64Repr.F64, +y: F64Repr.F64) -> F64Repr.F64:
  +rat = F64Arith.div_by(~mulhi, y, x)
  F64Arith.mul_by(~mulhi, x, F64Arith.sqrt_by(~mulhi, F64Arith.add(F64Repr.one(), F64Arith.mul_by(~mulhi, rat, rat))))

def hypot_small(~mulhi: @+a:U32 -> @+b:U32 -> U32, small: Bool, +x: F64Repr.F64, +y: F64Repr.F64) -> F64Repr.F64:
  match small:
    case True{}:
      x
    case False{}:
      scaled(~mulhi, x, y)

def eps_scaled(~mulhi: @+a:U32 -> @+b:U32 -> U32, exact: Bool, +x: F64Repr.F64) -> F64Repr.F64:
  match exact:
    case True{}:
      match x:
        case F64Repr.F64{+h, +l}:
          F64Repr.F64{(h - 54525952 : U32), l}
    case False{}:
      F64Arith.mul_by(~mulhi, x, F64Repr.epsilon())

def times_eps(~mulhi: @+a:U32 -> @+b:U32 -> U32, +x: F64Repr.F64) -> F64Repr.F64:
  match x:
    case F64Repr.F64{+h, +l}:
      +e = F64Repr.exp_field(h)
      eps_scaled(~mulhi, (e > 52 : U32) && (e < 2047 : U32), x)

def hypot_sorted(~mulhi: @+a:U32 -> @+b:U32 -> U32, swap: Bool, +x: F64Repr.F64, +y: F64Repr.F64) -> F64Repr.F64:
  match swap:
    case True{}:
      hypot_small(~mulhi, F64Cmp.ge(times_eps(~mulhi, y), x), y, x)
    case False{}:
      hypot_small(~mulhi, F64Cmp.ge(times_eps(~mulhi, x), y), x, y)

def hypot_abs(~mulhi: @+a:U32 -> @+b:U32 -> U32, infinite: Bool, +x: F64Repr.F64, +y: F64Repr.F64) -> F64Repr.F64:
  match infinite:
    case True{}:
      F64Repr.inf()
    case False{}:
      hypot_sorted(~mulhi, F64Cmp.lt(x, y), x, y)

# hypot with the 32x32 high product mulhi (F64Word.mul_hi, or F64Word.mul_hi_nat in compiled hot loops: same values).
def hypot_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, x: F64Repr.F64, y: F64Repr.F64) -> F64Repr.F64:
  +ax = F64Repr.abs(x)
  +ay = F64Repr.abs(y)
  hypot_abs(~mulhi, F64Repr.is_inf(ax) || F64Repr.is_inf(ay), ax, ay)

def hypot(x: F64Repr.F64, y: F64Repr.F64) -> F64Repr.F64:
  hypot_by(~F64Word.mul_hi, x, y)
