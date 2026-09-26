import Base
import ../rng/pcg.bend as Pcg
import ../rng/lua_random.bend as LuaRandom
import ../data/world_catalog.bend as WorldCatalog

# The forest level table, i.e. everything worldgen_main.lua GenerateNew decides before
# forest_map.Generate: prefab swaps, ChooseTasks, AddSetPeices and Level:ChooseSetPieces.
# Tasks are data/world_catalog.bend task ids; task sets are 25-bit masks over them.

# After SelectPrefabSwaps and ChooseTasks: swapped prefab sets (bit 0 grass gekko, 1 twiggy trees,
# 2 juicy berries) and the shuffled optional tasks as 4-bit optional indices, slots 0-7 in lo and
# 8-10 in hi. Slot 10 only fills when math.random(1, i) returns i + 1; 15 is nil.
type Prefix is Data:
  Prefix{swaps: U32, lo: U32, hi: U32, rng: Pcg.Rng}

def swap_threshold() -> U32:
  3221225472

def unshuffled_lo() -> U32:
  1985229328

def unshuffled_hi() -> U32:
  3992

def with_swap(+k: U32, +swaps: U32, +lo: U32, +hi: U32, drawn: U32 & Pcg.Rng) -> Prefix:
  (+x, s) = drawn
  Prefix{(swaps .|. (Bool.to_u32((x >= swap_threshold() : U32)) << U32.to_nat(k)) : U32), lo, hi, s}

def swap_step(p: Prefix, +k: U32) -> Prefix:
  match p:
    case Prefix{+swaps, +lo, +hi, rng}:
      with_swap(k, swaps, lo, hi, Pcg.draw(rng))

def slot(+lo: U32, +hi: U32, +k: U32) -> U32:
  ((Bool.pick(U32, (k < 8 : U32), lo, hi) >> U32.to_nat(((k .&. 7) * 4 : U32))) .&. 15 : U32)

def with_nibble(+word: U32, +k: U32, +v: U32) -> U32:
  +shift = U32.to_nat(((k .&. 7) * 4 : U32))
  ((word .&. U32.not((15 << shift : U32))) .|. (v << shift) : U32)

def put_lo(+lo: U32, +k: U32, +v: U32) -> U32:
  Bool.pick(U32, (k < 8 : U32), with_nibble(lo, k, v), lo)

def put_hi(+hi: U32, +k: U32, +v: U32) -> U32:
  Bool.pick(U32, (k < 8 : U32), hi, with_nibble(hi, k, v))

def with_shuffle(+i: U32, +swaps: U32, +lo: U32, +hi: U32, rolled: U32 & Pcg.Rng) -> Prefix:
  (+j, s) = rolled
  +a = (i - 1 : U32)
  +va = slot(lo, hi, a)
  +vb = slot(lo, hi, j)
  +lo_a = put_lo(lo, a, vb)
  +hi_a = put_hi(hi, a, vb)
  Prefix{swaps, put_lo(lo_a, j, va), put_hi(hi_a, j, va), s}

def shuffle_step(p: Prefix, +i: U32) -> Prefix:
  match p:
    case Prefix{+swaps, +lo, +hi, rng}:
      with_shuffle(i, swaps, lo, hi, LuaRandom.roll(rng, i))

def swap_loop(n: Nat, p: Prefix, +k: U32) -> Prefix:
  match n:
    case 0n:
      p
    case 1n+q:
      swap_loop(q, swap_step(p, k), (k + 1 : U32))

def shuffle_loop(n: Nat, p: Prefix, +i: U32) -> Prefix:
  match n:
    case 0n:
      p
    case 1n+q:
      shuffle_loop(q, shuffle_step(p, i), (i - 1 : U32))

# SetWorldGenSeed (seed + one discarded draw), SelectPrefabSwaps (3 draws) and ChooseTasks'
# shuffleArray of the 10 optional tasks (9 draws).
def prefix(+seed: U32) -> Prefix:
  shuffle_loop(9n, swap_loop(3n, Prefix{0, unshuffled_lo(), unshuffled_hi(), Pair.snd(U32, Pcg.Rng, Pcg.draw(Pcg.srandom(seed)))}, 0), 10)

def field5(+word: U32, +k: U32) -> U32:
  ((word >> U32.to_nat((k * 5 : U32))) .&. 31 : U32)

def optional_task(+index: U32) -> U32:
  Bool.pick(U32, (index < 6 : U32), field5(WorldCatalog.optional_tasks_0(), index), field5(WorldCatalog.optional_tasks_1(), (index - 6 : U32)))

def task_bit(+task: U32) -> U32:
  (1 << U32.to_nat(task) : U32)

def chosen_optional(+lo: U32, +s: U32) -> U32:
  task_bit(optional_task(((lo >> U32.to_nat((s * 4 : U32))) .&. 15 : U32)))

# The 20 chosen tasks: required and moon tasks plus optional slots 0-4.
def chosen_tasks(+lo: U32) -> U32:
  (WorldCatalog.always_chosen() .|. chosen_optional(lo, 0) .|. chosen_optional(lo, 1) .|. chosen_optional(lo, 2)
    .|. chosen_optional(lo, 3) .|. chosen_optional(lo, 4) : U32)

# A nil among the first five optional slots makes ChooseTasks fail an assert.
def has_nil_task(+lo: U32) -> Bool:
  +x = (lo .&. 1048575 : U32)
  Bool.not(U32.is_zero((x .&. (x >> 1n) .&. (x >> 2n) .&. (x >> 3n) .&. 69905 : U32)))

# Task of placeable index p (GetTasksForLevelSetPieces order: required tasks, then optional slots).
def placeable_task(+lo: U32, +p: U32) -> U32:
  +required = Bool.pick(U32, (p < 6 : U32), field5(WorldCatalog.required_tasks_0(), p), field5(WorldCatalog.required_tasks_1(), (p - 6 : U32)))
  +optional = optional_task(((lo >> U32.to_nat((((p - 10) .&. 7) * 4 : U32))) .&. 15 : U32))
  Bool.pick(U32, (p < 10 : U32), required, optional)

# Task at position c of chosen_tasks (required, moon, then optional slots).
def chosen_task(+lo: U32, +c: U32) -> U32:
  Bool.pick(U32, (c < 10 : U32), placeable_task(lo, c),
    Bool.pick(U32, (c < 15 : U32), field5(WorldCatalog.moon_tasks(), (c - 10 : U32)), placeable_task(lo, (c - 5 : U32))))

def optional_background(+index: U32) -> U32:
  ((WorldCatalog.optional_backgrounds() >> U32.to_nat((index * 3 : U32))) .&. 7 : U32)

def slot_in_area(+lo: U32, +s: U32, +area: U32) -> U32:
  +index = ((lo >> U32.to_nat((s * 4 : U32))) .&. 15 : U32)
  (Bool.to_u32(U32.is_eq(optional_background(index), area)) << U32.to_nat((s + 10 : U32)) : U32)

# GetAreasForChoice as a mask over placeable indices (area 0 = Any/Rare: every placeable task).
def area_choices(+area: U32, +lo: U32) -> U32:
  +tiles = (WorldCatalog.area_required(area) .|. slot_in_area(lo, 0, area) .|. slot_in_area(lo, 1, area)
    .|. slot_in_area(lo, 2, area) .|. slot_in_area(lo, 3, area) .|. slot_in_area(lo, 4, area) : U32)
  Bool.pick(U32, U32.is_zero(area), 32767, tiles)

