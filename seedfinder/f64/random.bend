import Base
import ./word.bend as FW
import ./repr.bend as FR
import ../rng/pcg.bend as R

# Lua math.random() as the game computes it: x / 4294967295.0 for a PCG32 output x, correctly rounded. The exact
# quotient is x repeated in every 32-bit block after the binary point, so its leading 64 bits are the rotated
# word twice, with a nonzero tail (sticky).
def from_output(+x: U32) -> FR.F64:
  +lz = FW.clz32(x)
  +w = (FW.shl(x, lz) .|. FW.shr(x, (32 - lz : U32)) : U32)
  FR.pick(U32.is_zero(x), FR.zero(), FR.round_pack(0, (1021 - lz : U32), (w >> 1n : U32), ((w << 31n) .|. (w >> 1n) .|. 1 : U32)))

def with_state(drawn: U32 & R.Rng) -> FR.F64 & R.Rng:
  (x, s) = drawn
  (from_output(x), s)

def random(s: R.Rng) -> FR.F64 & R.Rng:
  with_state(R.draw(s))
