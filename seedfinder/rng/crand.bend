import Base
import ./pcg.bend as Pcg

# Klei's C++ rand(), pcg32_boundedrand and std::random_shuffle. They share the PCG32 stream with math.random.
# `windows` selects the Windows server build (MSVC 2008: RAND_MAX 0x7fff, VC9 random_shuffle); otherwise the Linux
# build (glibc RAND_MAX 0x7fffffff, libstdc++ random_shuffle).

def rand_max(+windows: Bool) -> U32:
  Bool.pick(U32, windows, 32767, 2147483647)

def rejection_fuel() -> Nat:
  32n

def bounded_retry(n: Nat, rejected: Bool, +x: U32, s: Pcg.Rng, +bound: U32, +threshold: U32) -> U32 & Pcg.Rng:
  match n:
    case 0n:
      ((x % bound : U32), s)
    case 1n+p:
      match rejected:
        case False{}:
          ((x % bound : U32), s)
        case True{}:
          match s:
            case Pcg.Rng{+hi, +lo}:
              +next = Pcg.output(hi, lo)
              bounded_retry(p, (next < threshold : U32), next, Pcg.step(hi, lo), bound, threshold)

# pcg32_boundedrand(bound): draws until x >= (2^32 - bound) % bound, then returns x % bound. More than 32
# rejections in a row (probability below 2^-900 for the bounds used) would return a rejected draw.
def bounded(s: Pcg.Rng, +bound: U32) -> U32 & Pcg.Rng:
  match s:
    case Pcg.Rng{+hi, +lo}:
      +threshold = ((0 - bound : U32) % bound : U32)
      +x = Pcg.output(hi, lo)
      bounded_retry(rejection_fuel(), (x < threshold : U32), x, Pcg.step(hi, lo), bound, threshold)

# rand() = pcg32_boundedrand(RAND_MAX), in 0..RAND_MAX-1: rejects x < 2 on Linux and x < 4 on Windows.
def rand(+windows: Bool, s: Pcg.Rng) -> U32 & Pcg.Rng:
  bounded(s, rand_max(windows))

type Shuffled is Type:
  Shuffled{items: Array<U32>, rng: Pcg.Rng}

def swap_second(got: Array<U32> & U32, +i: U32, +j: U32, +first: U32) -> Array<U32>:
  (items, second) = got
  items[i] <- second
  items[j] <- first

def swap_first(got: Array<U32> & U32, +i: U32, +j: U32) -> Array<U32>:
  (items, +first) = got
  swap_second(items[j], i, j, first)

def with_swap(items: Array<U32>, +i: U32, drawn: U32 & Pcg.Rng) -> Shuffled:
  (r, s) = drawn
  Shuffled{swap_first(items[i], i, (r % (i + 1 : U32) : U32)), s}

def shuffle_loop(n: Nat, st: Shuffled, +windows: Bool, +i: U32) -> Shuffled:
  match n:
    case 0n:
      st
    case 1n+p:
      match st:
        case Shuffled{items, s}:
          shuffle_loop(p, with_swap(items, i, rand(windows, s)), windows, (i + 1 : U32))

# std::random_shuffle of items[0..n): for i = 1..n-1, swap items[i] with items[rand() % (i + 1)] (n - 1 rand()
# calls). libstdc++ on Linux; on Windows VC9's form, which is the same for n <= 32767 (its extra 15-bit rand()
# chunks start at n = 32768; forest site lists have at most ~1257 tiles).
def random_shuffle(+windows: Bool, items: Array<U32>, +n: U32, s: Pcg.Rng) -> Shuffled:
  shuffle_loop(Nat.sub(U32.to_nat(n), 1n), Shuffled{items, s}, windows, 1)

type Order is Data:
  Order{indices: List<&2, U32>, rng: Pcg.Rng}

def identity_loop(n: Nat, items: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      items
    case 1n+p:
      items[i] <- i
      identity_loop(p, items, (i + 1 : U32))

def collect(n: Nat, got: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      (items, +v) = got
      collect(p, items[(i - 1 : U32)], (i - 1 : U32), v <> acc)

def order_of(st: Shuffled, +n: U32) -> Order:
  match st:
    case Shuffled{items, s}:
      Order{collect(U32.to_nat(n), items[(n - 1 : U32)], (n - 1 : U32), Nil{}), s}

# random_shuffle of the indices 0..n-1 (n <= 2048): position k of the result holds the index that ends up there.
def shuffled_order(+windows: Bool, +n: U32, s: Pcg.Rng) -> Order:
  order_of(random_shuffle(windows, identity_loop(U32.to_nat(n), [0 : U32*2048n], 0), n, s), n)
