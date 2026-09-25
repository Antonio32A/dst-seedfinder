import Base
import ./pcg.bend as R

# Lua math.random on the PCG32 stream: r = output / (2^32 - 1), so r can be exactly 1.0.
def largest_output() -> U32:
  4294967295

def rare_reroll_cutoff() -> U32:
  4209067950

# floor(x / (2^32 - 1) * n) for n < 2^16, bit-exact with the game's double math for n <= 50.
def scale(+x: U32, +n: U32) -> U32:
  +low_part = ((x .&. 65535 : U32) * n : U32)
  +hi = ((((x >> 16n) * n : U32) + (low_part >> 16n)) >> 16n : U32)
  (hi + Bool.to_u32(((x * n : U32) >= (largest_output() - hi) : U32)) : U32)

# math.random(n) - 1, as a 0-based index.
def roll(s: R.Rng, +n: U32) -> U32 & R.Rng:
  match s:
    case R.Rng{+hi, +lo}:
      (scale(R.output(hi, lo), n), R.affine(hi, lo, R.multiplier_hi(), R.multiplier_lo(), R.increment_hi(), R.increment_lo()))

# math.random() < 0.98
def is_below_rare_cutoff(+x: U32) -> Bool:
  (x < rare_reroll_cutoff() : U32)
