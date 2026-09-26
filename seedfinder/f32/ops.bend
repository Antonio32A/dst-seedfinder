import Base
import ../f64/repr.bend as F64Repr

# The only module that touches Bend's native F32 (IEEE binary32 on the CPU), so a soft backend can replace it.

def from_bits(x: U32) -> F32:
  match x:
    case U32{w}:
      F32{w}

def bits(x: F32) -> U32:
  F32.bits(x)

def add(a: F32, b: F32) -> F32:
  F32.add(a, b)

def sub(a: F32, b: F32) -> F32:
  F32.sub(a, b)

def mul(a: F32, b: F32) -> F32:
  F32.mul(a, b)

def div(a: F32, b: F32) -> F32:
  F32.div(a, b)

def sqrt(a: F32) -> F32:
  F32.sqrt(a)

def floor(a: F32) -> F32:
  F32.floor(a)

# (float)x for a U32, rounded to nearest even.
def from_u32(x: U32) -> F32:
  U32.to_f32(x)

# (double)x, exact.
def to_f64(x: F32) -> F64Repr.F64:
  F64Repr.from_f32_bits(F32.bits(x))

# (float)x, rounded to nearest even.
def from_f64(x: F64Repr.F64) -> F32:
  from_bits(F64Repr.to_f32_bits(x))

# a <= b (false with a NaN).
def le(a: F32, b: F32) -> Bool:
  F32.is_le(a, b)

# a == b (false with a NaN, +0 == -0).
def eq(a: F32, b: F32) -> Bool:
  F32.is_eq(a, b)

# (int)x: truncation toward zero (cvttss2si; 0x80000000 for NaN and out of range).
def to_i32(x: F32) -> U32:
  F64Repr.to_i32(to_f64(x))
