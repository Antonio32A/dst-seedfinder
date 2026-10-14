import Base
import ../rng/pcg.bend as Pcg
import ../rng/lua_random.bend as LuaRandom
import ../data/cave_catalog.bend as CaveCatalog
import ./prefix.bend as LevelPrefix
import ../data/builds.bend as Builds

# The caves level table, before AddSetPeices: everything worldgen_main.lua GenerateNew decides in SelectPrefabSwaps
# and ChooseTasks for DST_CAVE. Tasks are data/cave_catalog.bend task ids (the required tasks, then the optional
# ones); a set of tasks is two words, ids 0-31 in `lo` and ids 32.. in `hi` (bit id - 32).

# The swaps (bit k: swap category k took its swapped variant), the shuffled optional tasks (slot i: optional index,
# slot optional_count(): nil) and the PCG32 state after the shuffle.
type Shuffled is Type:
  Shuffled{swaps: U32, order: Array<U32>, rng: Pcg.Rng}

def nil_slot() -> U32:
  31

def swapped_bit(+build: Builds.Build, +k: U32, +x: U32) -> U32:
  +wanted = (Bool.to_u32((x >= LevelPrefix.swap_threshold() : U32)) << U32.to_nat(k) : U32)
  (wanted .&. CaveCatalog.swaps_possible(build) : U32)

def with_swap(+build: Builds.Build, +k: U32, +swaps: U32, order: Array<U32>, drawn: U32 & Pcg.Rng) -> Shuffled:
  (+x, s) = drawn
  Shuffled{(swaps .|. swapped_bit(build, k, x) : U32), order, s}

def swap_step(+build: Builds.Build, p: Shuffled, +k: U32) -> Shuffled:
  match p:
    case Shuffled{+swaps, order, rng}:
      with_swap(build, k, swaps, order, Pcg.draw(rng))

def swap_loop(+build: Builds.Build, n: Nat, p: Shuffled, +k: U32) -> Shuffled:
  match n:
    case 0n:
      p
    case 1n+q:
      swap_loop(build, q, swap_step(build, p, k), (k + 1 : U32))

def exchange_write(+a: U32, +j: U32, +vj: U32, got: Array<U32> & U32) -> Array<U32>:
  (order, +va) = got
  order[a] <- vj
  order[j] <- va
  order

def exchange_read(+a: U32, +j: U32, got: Array<U32> & U32) -> Array<U32>:
  (order, +vj) = got
  exchange_write(a, j, vj, order[a])

def exchanged(+swaps: U32, order: Array<U32>, +i: U32, rolled: U32 & Pcg.Rng) -> Shuffled:
  (+j, s) = rolled
  Shuffled{swaps, exchange_read((i - 1 : U32), j, order[j]), s}

def shuffle_step(p: Shuffled, +i: U32) -> Shuffled:
  match p:
    case Shuffled{+swaps, order, rng}:
      exchanged(swaps, order, i, LuaRandom.roll(rng, i))

def shuffle_loop(n: Nat, p: Shuffled, +i: U32) -> Shuffled:
  match n:
    case 0n:
      p
    case 1n+q:
      shuffle_loop(q, shuffle_step(p, i), (i - 1 : U32))

def identity(n: Nat, order: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      order
    case 1n+p:
      order[i] <- i
      identity(p, order, (i + 1 : U32))

def unshuffled(+build: Builds.Build) -> Array<U32>:
  order = identity(U32.to_nat(CaveCatalog.optional_count(build)), [0 : U32*32n], 0)
  order[CaveCatalog.optional_count(build)] <- nil_slot()
  order

def shuffle_start(+build: Builds.Build, +seed: U32) -> Shuffled:
  Shuffled{0, unshuffled(build), Pair.snd(U32, Pcg.Rng, Pcg.draw(Pcg.srandom(seed)))}

# SetWorldGenSeed (seed + one discarded draw), SelectPrefabSwaps (3 draws) and shuffleArray of the optional tasks
# (optional_count() - 1 draws).
def shuffled(+build: Builds.Build, +seed: U32) -> Shuffled:
  shuffle_loop(U32.to_nat((CaveCatalog.optional_count(build) - 1 : U32)), swap_loop(build, U32.to_nat(CaveCatalog.swap_count(build)), shuffle_start(build, seed), 0), CaveCatalog.optional_count(build))

def task_bit_lo(+task: U32) -> U32:
  Bool.pick(U32, (task < 32 : U32), (1 << U32.to_nat((task .&. 31 : U32)) : U32), 0)

def task_bit_hi(+task: U32) -> U32:
  Bool.pick(U32, (task < 32 : U32), 0, (1 << U32.to_nat((task .&. 31 : U32)) : U32))

def optional_task(+build: Builds.Build, +index: U32) -> U32:
  (CaveCatalog.required_count(build) + index : U32)

# The chosen tasks after ChooseTasks. `picks`: the optional indices in chosen order (nil_slot() when the shuffle put
# nil among them: EnqueueATask fails an assert then); `areas`: the room_bg codes of the chosen tasks as a mask.
type Chosen is Data:
  Chosen{swaps: U32, picks: List<&2, U32>, masks: Masks, rng: Pcg.Rng}

def picked_slots(n: Nat, got: Array<U32> & U32, +k: U32, picks: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, picks)
    case 1n+p:
      (order, +index) = got
      picked_slots(p, order[(k + 1 : U32)], (k + 1 : U32), index <> picks)

def required_lo(+build: Builds.Build) -> U32:
  (Bool.pick(U32, (CaveCatalog.required_count(build) < 32 : U32), (1 << U32.to_nat(CaveCatalog.required_count(build)) : U32), 0) - 1 : U32)

def required_hi(+build: Builds.Build) -> U32:
  Bool.pick(U32, (CaveCatalog.required_count(build) > 32 : U32), ((1 << U32.to_nat((CaveCatalog.required_count(build) - 32 : U32)) : U32) - 1 : U32), 0)

def area_bit(+build: Builds.Build, +task: U32) -> U32:
  (1 << U32.to_nat(CaveCatalog.task_area(build, task)) : U32)

type Masks is Data:
  Masks{lo: U32, hi: U32, areas: U32, crashed: Bool}

def masks_of(+build: Builds.Build, picks: List<&2, U32>, +lo: U32, +hi: U32, +areas: U32, +crashed: Bool) -> Masks:
  match picks:
    case Nil{}:
      Masks{lo, hi, areas, crashed}
    case Con{+index, rest}:
      +task = optional_task(build, index)
      masks_of(build, rest, (lo .|. task_bit_lo(task) : U32), (hi .|. task_bit_hi(task) : U32),
        (areas .|. area_bit(build, task) : U32), crashed || U32.is_eq(index, nil_slot()))

def chosen_of(+build: Builds.Build, +swaps: U32, +picks: List<&2, U32>, rng: Pcg.Rng) -> Chosen:
  Chosen{swaps, picks, masks_of(build, picks, required_lo(build), required_hi(build), CaveCatalog.required_areas(build), False{}), rng}

def chosen_from(+build: Builds.Build, p: Shuffled) -> Chosen:
  match p:
    case Shuffled{+swaps, order, rng}:
      chosen_of(build, swaps, picked_slots(U32.to_nat(CaveCatalog.picked_count(build)), order[0], 0, Nil{}), rng)

def chosen(+build: Builds.Build, +seed: U32) -> Chosen:
  chosen_from(build, shuffled(build, seed))

def is_chosen(+lo: U32, +hi: U32, +task: U32) -> Bool:
  Bool.not(U32.is_zero(((lo .&. task_bit_lo(task)) .|. (hi .&. task_bit_hi(task)) : U32)))

# The chosen tasks in the order of Level:GetTasksForLevelSetPieces: the required tasks, then the picked optional ones.
def required_ids(n: Nat, +task: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      tail
    case 1n+p:
      task <> required_ids(p, (task + 1 : U32), tail)

def picked_ids(+build: Builds.Build, picks: List<&2, U32>) -> List<&2, U32>:
  match picks:
    case Nil{}:
      Nil{}
    case Con{+index, rest}:
      optional_task(build, index) <> picked_ids(build, rest)

def chosen_ids(+build: Builds.Build, picks: List<&2, U32>) -> List<&2, U32>:
  required_ids(U32.to_nat(CaveCatalog.required_count(build)), 0, picked_ids(build, picks))
