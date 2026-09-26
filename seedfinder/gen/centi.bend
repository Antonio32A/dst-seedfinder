import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp

# Savedata positions as the dump mod prints them: printf("%.2f"), i.e. 100 x rounded to the nearest integer exactly.

def hundred() -> F64Repr.F64:
  F64Repr.F64{1079574528, 0}

def odd(+f: F64Repr.F64) -> Bool:
  U32.is_eq((F64Repr.to_i32(f) .&. 1 : U32), 1)

def tie_up(zero_error: Bool, +windows: Bool, +f: F64Repr.F64, +e: F64Repr.F64) -> Bool:
  match zero_error:
    case True{}:
      Bool.pick(Bool, windows, F64Cmp.ge(f, F64Repr.zero()), odd(f))
    case False{}:
      F64Cmp.gt(e, F64Repr.zero())

def rounded_up(below: Bool, above: Bool, +windows: Bool, +f: F64Repr.F64, +e: F64Repr.F64) -> Bool:
  match below:
    case True{}:
      False{}
    case False{}:
      match above:
        case True{}:
          True{}
        case False{}:
          tie_up(F64Repr.is_zero(e), windows, f, e)

def centi_of(+p: F64Repr.F64, +e: F64Repr.F64, +f: F64Repr.F64, +windows: Bool) -> U32:
  +d = F64Arith.sub(p, f)
  (F64Repr.to_i32(f) + Bool.to_u32(rounded_up(F64Cmp.lt(d, F64Repr.half()), F64Cmp.gt(d, F64Repr.half()), windows, f, e)) : U32)

# The integer nearest to 100 x, exactly, as printf("%.2f") rounds x: ties to even (glibc), or away from zero on
# Windows (MSVCR90).
def centi(+x: F64Repr.F64, +windows: Bool) -> U32:
  +p = F64Arith.mul(x, hundred())
  centi_of(p, F64Arith.fma(x, hundred(), F64Repr.neg(p)), F64Repr.floor(p), windows)
