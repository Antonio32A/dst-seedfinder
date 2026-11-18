import Base

# The soft F64's FPU fast paths (f64.c: the C each F64 spin tries first on the native and WebAssembly targets).

# Runs n operand sets through every fast path and its Bend body: how many of the fast paths' results differ (0 on the
# JS target, which has no fast paths).
def native_f64_check(n: U32) -> IO(U32):
  import "./f64.c"
  import "./f64.js"
