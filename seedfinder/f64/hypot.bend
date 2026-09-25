import Base
import ./word.bend as FW
import ./repr.bend as FR
import ./arith.bend as FA
import ./cmp.bend as FC

# boost::math::hypot (Boost 1.52 hypot_imp) for doubles, in its operation order. Boost raises an overflow error
# for an infinite argument; this returns +inf there.

def scaled(~mulhi: @+a:U32 -> @+b:U32 -> U32, +x: FR.F64, +y: FR.F64) -> FR.F64:
  +rat = FA.div_by(~mulhi, y, x)
  FA.mul_by(~mulhi, x, FA.sqrt_by(~mulhi, FA.add(FR.one(), FA.mul_by(~mulhi, rat, rat))))

def hypot_small(~mulhi: @+a:U32 -> @+b:U32 -> U32, small: Bool, +x: FR.F64, +y: FR.F64) -> FR.F64:
  match small:
    case True{}:
      x
    case False{}:
      scaled(~mulhi, x, y)

def eps_scaled(~mulhi: @+a:U32 -> @+b:U32 -> U32, exact: Bool, +x: FR.F64) -> FR.F64:
  match exact:
    case True{}:
      match x:
        case FR.F64{+h, +l}:
          FR.F64{(h - 54525952 : U32), l}
    case False{}:
      FA.mul_by(~mulhi, x, FR.epsilon())

def times_eps(~mulhi: @+a:U32 -> @+b:U32 -> U32, +x: FR.F64) -> FR.F64:
  match x:
    case FR.F64{+h, +l}:
      +e = FR.exp_field(h)
      eps_scaled(~mulhi, (e > 52 : U32) && (e < 2047 : U32), x)

def hypot_sorted(~mulhi: @+a:U32 -> @+b:U32 -> U32, swap: Bool, +x: FR.F64, +y: FR.F64) -> FR.F64:
  match swap:
    case True{}:
      hypot_small(~mulhi, FC.ge(times_eps(~mulhi, y), x), y, x)
    case False{}:
      hypot_small(~mulhi, FC.ge(times_eps(~mulhi, x), y), x, y)

def hypot_abs(~mulhi: @+a:U32 -> @+b:U32 -> U32, infinite: Bool, +x: FR.F64, +y: FR.F64) -> FR.F64:
  match infinite:
    case True{}:
      FR.inf()
    case False{}:
      hypot_sorted(~mulhi, FC.lt(x, y), x, y)

# hypot with the 32x32 high product mulhi (FW.mul_hi, or FW.mul_hi_nat in compiled hot loops: same values).
def hypot_by(~mulhi: @+a:U32 -> @+b:U32 -> U32, x: FR.F64, y: FR.F64) -> FR.F64:
  +ax = FR.abs(x)
  +ay = FR.abs(y)
  hypot_abs(~mulhi, FR.is_inf(ax) || FR.is_inf(ay), ax, ay)

def hypot(x: FR.F64, y: FR.F64) -> FR.F64:
  hypot_by(~FW.mul_hi, x, y)
