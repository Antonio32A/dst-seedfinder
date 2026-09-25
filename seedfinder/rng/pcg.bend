import Base

# DST worldgen RNG: Klei's math.random is PCG32 (pcg32_srandom / pcg32_random) and returns
# output / (2^32 - 1). The 64-bit state is kept as two U32 words.
type Rng is Data:
  Rng{hi: U32, lo: U32}

def multiplier_hi() -> U32:
  1481765933

def multiplier_lo() -> U32:
  1284865837

def increment_hi() -> U32:
  3028054935

def increment_lo() -> U32:
  695383991

# SetWorldGenSeed(seed), its discarded draw and the 12 draws of SelectPrefabSwaps and ChooseTasks
# collapse into one affine map of the seed: state = seed * K + L (mod 2^64).
def skip_multiplier_hi() -> U32:
  943789509

def skip_multiplier_lo() -> U32:
  2385944217

def skip_increment_hi() -> U32:
  2439525479

def skip_increment_lo() -> U32:
  2923026973

# pcg32_srandom(seed): state = seed * MULT + (INC * MULT + INC) (mod 2^64), before any draw.
def srandom_increment_hi() -> U32:
  4230588467

def srandom_increment_lo() -> U32:
  2638466018

def carry(+sum: U32, +operand: U32) -> U32:
  Bool.to_u32((sum < operand : U32))

def mul_hi(+a: U32, +b: U32) -> U32:
  +al = (a .&. 65535 : U32)
  +ah = (a >> 16n : U32)
  +bl = (b .&. 65535 : U32)
  +bh = (b >> 16n : U32)
  +ll = (al * bl : U32)
  +lh = (al * bh : U32)
  +hl = (ah * bl : U32)
  +mid = ((ll >> 16n) + (lh .&. 65535) + (hl .&. 65535) : U32)
  (ah * bh + (lh >> 16n) + (hl >> 16n) + (mid >> 16n) : U32)

def affine(+hi: U32, +lo: U32, +mul_hi_word: U32, +mul_lo_word: U32, add_hi: U32, +add_lo: U32) -> Rng:
  +product_lo = (lo * mul_lo_word : U32)
  +sum_lo = (product_lo + add_lo : U32)
  +product_hi = (mul_hi(lo, mul_lo_word) + lo * mul_hi_word + hi * mul_lo_word : U32)
  Rng{(product_hi + add_hi + carry(sum_lo, product_lo) : U32), sum_lo}

# The state right before the first draw that set piece selection inspects.
def seeded(+seed: U32) -> Rng:
  affine(0, seed, skip_multiplier_hi(), skip_multiplier_lo(), skip_increment_hi(), skip_increment_lo())

# The state right after math.randomseed(seed), before SetWorldGenSeed's discarded draw.
def srandom(+seed: U32) -> Rng:
  affine(0, seed, multiplier_hi(), multiplier_lo(), srandom_increment_hi(), srandom_increment_lo())

def output(+hi: U32, +lo: U32) -> U32:
  +shifted = (((hi .^. (hi >> 18n)) << 5n) .|. ((lo .^. ((hi << 14n) .|. (lo >> 18n))) >> 27n) : U32)
  +rotation = (hi >> 27n : U32)
  ((shifted >> U32.to_nat(rotation)) .|. (shifted << U32.to_nat(((32 - rotation) .&. 31 : U32))) : U32)

def draw(s: Rng) -> U32 & Rng:
  match s:
    case Rng{+hi, +lo}:
      (output(hi, lo), affine(hi, lo, multiplier_hi(), multiplier_lo(), increment_hi(), increment_lo()))

def step(+hi: U32, +lo: U32) -> Rng:
  affine(hi, lo, multiplier_hi(), multiplier_lo(), increment_hi(), increment_lo())

def one() -> Rng:
  Rng{0, 1}

def multiplier() -> Rng:
  Rng{multiplier_hi(), multiplier_lo()}

def increment() -> Rng:
  Rng{increment_hi(), increment_lo()}

def low_word(s: Rng) -> U32:
  match s:
    case Rng{_, +lo}:
      lo

# 64-bit product a * b (mod 2^64).
def mul64(a: Rng, b: Rng) -> Rng:
  match a:
    case Rng{+ah, +al}:
      match b:
        case Rng{+bh, +bl}:
          Rng{(mul_hi(al, bl) + al * bh + ah * bl : U32), (al * bl : U32)}

# 64-bit sum a + b (mod 2^64).
def add64(a: Rng, b: Rng) -> Rng:
  match a:
    case Rng{+ah, +al}:
      match b:
        case Rng{+bh, +bl}:
          +lo = (al + bl : U32)
          Rng{(ah + bh + carry(lo, al) : U32), lo}

type Jump is Data:
  Jump{mult: Rng, plus: Rng, step_mult: Rng, step_plus: Rng}

def jump_step(j: Jump, +taken: Bool) -> Jump:
  match j:
    case Jump{+mult, +plus, +step_mult, +step_plus}:
      Jump{Bool.pick(Rng, taken, mul64(mult, step_mult), mult),
        Bool.pick(Rng, taken, add64(mul64(plus, step_mult), step_plus), plus),
        mul64(step_mult, step_mult), mul64(add64(step_mult, one()), step_plus)}

def jump_loop(n: Nat, j: Jump, +k: U32) -> Jump:
  match n:
    case 0n:
      j
    case 1n+p:
      jump_loop(p, jump_step(j, U32.is_eq((k .&. 1 : U32), 1)), (k >> 1n : U32))

def apply_jump(j: Jump, s: Rng) -> Rng:
  match j:
    case Jump{+mult, +plus, _, _}:
      add64(mul64(mult, s), plus)

# The state k draws after s (PCG jump-ahead by squaring, 32 rounds).
def advance(s: Rng, +k: U32) -> Rng:
  apply_jump(jump_loop(32n, Jump{one(), Rng{0, 0}, multiplier(), increment()}, k), s)

type Distance is Data:
  Distance{state: Rng, step_mult: Rng, step_plus: Rng, count: U32}

def distance_step(d: Distance, +target_lo: U32, +bit: U32) -> Distance:
  match d:
    case Distance{+state, +step_mult, +step_plus, +count}:
      +differs = U32.is_eq((((low_word(state) .^. target_lo) >> U32.to_nat(bit)) .&. 1 : U32), 1)
      Distance{Bool.pick(Rng, differs, add64(mul64(state, step_mult), step_plus), state),
        mul64(step_mult, step_mult), mul64(add64(step_mult, one()), step_plus),
        (count .|. (Bool.to_u32(differs) << U32.to_nat(bit)) : U32)}

def distance_loop(n: Nat, d: Distance, +target_lo: U32, +bit: U32) -> Distance:
  match n:
    case 0n:
      d
    case 1n+p:
      distance_loop(p, distance_step(d, target_lo, bit), target_lo, (bit + 1 : U32))

def count_of(d: Distance) -> U32:
  match d:
    case Distance{_, _, _, +count}:
      count

# The number of draws from `from` to `to`, mod 2^32 (PCG's distance: one bit of the count per round).
def distance(from: Rng, to: Rng) -> U32:
  count_of(distance_loop(32n, Distance{from, multiplier(), increment(), 0}, low_word(to), 0))

# The state `count` draws after math.randomseed(seed): the canonical draw counter of the oracle dumps.
def at_counter(+seed: U32, +count: U32) -> Rng:
  advance(srandom(seed), count)

# The canonical draw counter of a state: draws since math.randomseed(seed).
def counter(+seed: U32, s: Rng) -> U32:
  distance(srandom(seed), s)
