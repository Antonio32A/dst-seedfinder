import Base
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC

# Savedata positions as the dump mod prints them: printf("%.2f"), i.e. 100 x rounded to the nearest integer exactly.

def hundred() -> FR.F64:
  FR.F64{1079574528, 0}

def odd(+f: FR.F64) -> Bool:
  U32.is_eq((FR.to_i32(f) .&. 1 : U32), 1)

def tie_up(zero_error: Bool, +windows: Bool, +f: FR.F64, +e: FR.F64) -> Bool:
  match zero_error:
    case True{}:
      Bool.pick(Bool, windows, FC.ge(f, FR.zero()), odd(f))
    case False{}:
      FC.gt(e, FR.zero())

def rounded_up(below: Bool, above: Bool, +windows: Bool, +f: FR.F64, +e: FR.F64) -> Bool:
  match below:
    case True{}:
      False{}
    case False{}:
      match above:
        case True{}:
          True{}
        case False{}:
          tie_up(FR.is_zero(e), windows, f, e)

def centi_of(+p: FR.F64, +e: FR.F64, +f: FR.F64, +windows: Bool) -> U32:
  +d = FA.sub(p, f)
  (FR.to_i32(f) + Bool.to_u32(rounded_up(FC.lt(d, FR.half()), FC.gt(d, FR.half()), windows, f, e)) : U32)

# The integer nearest to 100 x, exactly, as printf("%.2f") rounds x: ties to even (glibc), or away from zero on
# Windows (MSVCR90).
def centi(+x: FR.F64, +windows: Bool) -> U32:
  +p = FA.mul(x, hundred())
  centi_of(p, FA.fma(x, hundred(), FR.neg(p)), FR.floor(p), windows)
