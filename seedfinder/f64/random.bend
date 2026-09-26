import Base
import ./word.bend as F64Word
import ./repr.bend as F64Repr
import ../rng/pcg.bend as Pcg

# Lua math.random() as the game computes it: x / 4294967295.0 for a PCG32 output x, correctly rounded. The exact
# quotient is x repeated in every 32-bit block after the binary point, so its leading 64 bits are the rotated
# word twice, with a nonzero tail (sticky).
def from_output(+x: U32) -> F64Repr.F64:
  +lz = F64Word.clz32(x)
  +w = (F64Word.shl(x, lz) .|. F64Word.shr(x, (32 - lz : U32)) : U32)
  F64Repr.pick(U32.is_zero(x), F64Repr.zero(), F64Repr.round_pack(0, (1021 - lz : U32), (w >> 1n : U32), ((w << 31n) .|. (w >> 1n) .|. 1 : U32)))

def with_state(drawn: U32 & Pcg.Rng) -> F64Repr.F64 & Pcg.Rng:
  (x, s) = drawn
  (from_output(x), s)

def random(s: Pcg.Rng) -> F64Repr.F64 & Pcg.Rng:
  with_state(Pcg.draw(s))
