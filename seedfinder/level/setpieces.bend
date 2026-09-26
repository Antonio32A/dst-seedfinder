import Base
import ../rng/pcg.bend as Pcg
import ../rng/lua_random.bend as LuaRandom
import ../data/catalog.bend as Catalog

# The set pieces a seed rolls in AddSetPeices (worldgen_main.lua): one trap, point of interest and
# protected resource (catalog ids, 0 = none) and the boons, counted in 8-bit fields, 4 per word.
type Pieces is Data:
  Pieces{trap: U32, poi: U32, protected: U32, boons_a: U32, boons_b: U32, boons_c: U32, boons_d: U32}

def fields_below(+k: U32) -> U32:
  +half = U32.to_nat((k * 2 : U32))
  (((1 << half) << half) - 1 : U32)

def field_sum(+w: U32) -> U32:
  ((((w .&. 252645135) + ((w >> 4n) .&. 252645135)) * 16843009) >> 24n : U32)

def nibble(+lo: U32, +hi: U32, +k: U32) -> U32:
  ((Bool.pick(U32, (k < 8 : U32), lo, hi) >> U32.to_nat(((k .&. 7) * 4 : U32))) .&. 15 : U32)

def prefix_sum(low_half: Bool, +lo: U32, +hi: U32, +k: U32) -> U32:
  match low_half:
    case True{}:
      field_sum((lo .&. fields_below(k) : U32))
    case False{}:
      (field_sum(lo) + field_sum((hi .&. fields_below((k - 8 : U32)) : U32)) : U32)

def area_count(+box: Catalog.Sandbox) -> U32:
  match box:
    case Catalog.Sandbox{+areas, _, _, _, _, _}:
      areas

def area_size(+box: Catalog.Sandbox, +k: U32) -> U32:
  match box:
    case Catalog.Sandbox{_, _, +sizes_lo, +sizes_hi, _, _}:
      nibble(sizes_lo, sizes_hi, k)

def is_empty(+box: Catalog.Sandbox, +k: U32) -> Bool:
  U32.is_zero(area_size(box, k))

def is_rare(+box: Catalog.Sandbox, +k: U32) -> Bool:
  match box:
    case Catalog.Sandbox{_, +rare, _, _, _, _}:
      U32.is_eq(k, rare)

def item_id(+box: Catalog.Sandbox, +k: U32, +choice: U32) -> U32:
  match box:
    case Catalog.Sandbox{_, _, _, _, +ids_lo, +ids_hi}:
      +offset = prefix_sum((k < 8 : U32), ids_lo, ids_hi, k)
      Bool.pick(U32, U32.is_zero(nibble(ids_lo, ids_hi, k)), 0, (offset + choice + 1 : U32))

def pick_chosen(+box: Catalog.Sandbox, +k: U32, rolled: U32 & Pcg.Rng) -> U32 & Pcg.Rng:
  (+choice, s) = rolled
  (item_id(box, k, choice), s)

def pick_choice(empty: Bool, +box: Catalog.Sandbox, +k: U32, s: Pcg.Rng) -> U32 & Pcg.Rng:
  match empty:
    case True{}:
      (0, s)
    case False{}:
      pick_chosen(box, k, LuaRandom.roll(s, area_size(box, k)))

def pick_rerolled(+box: Catalog.Sandbox, +k: U32, rolled: U32 & Pcg.Rng) -> U32 & Pcg.Rng:
  (+j, s) = rolled
  +area = (j + Bool.to_u32((j >= k : U32)) : U32)
  pick_choice(is_empty(box, area), box, area, s)

def pick_reroll(reroll: Bool, +box: Catalog.Sandbox, +k: U32, s: Pcg.Rng) -> U32 & Pcg.Rng:
  match reroll:
    case True{}:
      pick_rerolled(box, k, LuaRandom.roll(s, (area_count(box) - 1 : U32)))
    case False{}:
      pick_choice(is_empty(box, k), box, k, s)

def pick_rare_drawn(+box: Catalog.Sandbox, +k: U32, drawn: U32 & Pcg.Rng) -> U32 & Pcg.Rng:
  (+x, s) = drawn
  pick_reroll(LuaRandom.is_below_rare_cutoff(x) || is_empty(box, k), box, k, s)

def pick_rare(rare: Bool, +box: Catalog.Sandbox, +k: U32, s: Pcg.Rng) -> U32 & Pcg.Rng:
  match rare:
    case True{}:
      pick_rare_drawn(box, k, Pcg.draw(s))
    case False{}:
      pick_reroll(is_empty(box, k), box, k, s)

def pick_area(+box: Catalog.Sandbox, rolled: U32 & Pcg.Rng) -> U32 & Pcg.Rng:
  (+k, s) = rolled
  pick_rare(is_rare(box, k), box, k, s)

# GetRandomFromLayouts + GetRandomKey from worldgen_main.lua; returns a catalog id (0 = none).
def pick(+box: Catalog.Sandbox, s: Pcg.Rng) -> U32 & Pcg.Rng:
  pick_area(box, LuaRandom.roll(s, area_count(box)))

def add_boon(+id: U32, +field_base: U32, +word: U32) -> U32:
  +index = (id - 1 : U32)
  +inside = (index >= field_base : U32) && (index < (field_base + 4 : U32) : U32)
  (word + (Bool.to_u32(inside) << U32.to_nat((((index - field_base : U32) % 4) * 8 : U32))) : U32)

def boon_loop(
  n: Nat, picked: U32 & Pcg.Rng, +trap: U32, +poi: U32, +protected: U32, +a: U32, +b: U32, +c: U32, +d: U32
) -> Pieces:
  match n:
    case 0n:
      (+id, s) = picked
      Pieces{trap, poi, protected, add_boon(id, 0, a), add_boon(id, 4, b), add_boon(id, 8, c), add_boon(id, 12, d)}
    case 1n+p:
      (+id, s) = picked
      boon_loop(p, pick(Catalog.boons(), s), trap, poi, protected,
        add_boon(id, 0, a), add_boon(id, 4, b), add_boon(id, 8, c), add_boon(id, 12, d))

def fewest_boons() -> U32:
  3

# AddSetPeices' boon count math.random(3, 8), minus fewest_boons().
def roll_boon_count(s: Pcg.Rng) -> U32 & Pcg.Rng:
  LuaRandom.roll(s, 6)

def with_boon_count(+trap: U32, +poi: U32, +protected: U32, rolled: U32 & Pcg.Rng) -> Pieces:
  (count, s) = rolled
  boon_loop(U32.to_nat((count + fewest_boons() : U32)), (0, s), trap, poi, protected, 0, 0, 0, 0)

def with_protected(+trap: U32, +poi: U32, picked: U32 & Pcg.Rng) -> Pieces:
  (protected, s) = picked
  with_boon_count(trap, poi, protected, roll_boon_count(s))

def with_poi(+trap: U32, picked: U32 & Pcg.Rng) -> Pieces:
  (poi, s) = picked
  with_protected(trap, poi, pick(Catalog.protected_resources(), s))

def with_trap(picked: U32 & Pcg.Rng) -> Pieces:
  (trap, s) = picked
  with_poi(trap, pick(Catalog.points_of_interest(), s))

def generate(+seed: U32) -> Pieces:
  with_trap(pick(Catalog.traps(), Pcg.seeded(seed)))

def boon_count(+p: Pieces, +index: U32) -> U32:
  match p:
    case Pieces{_, _, _, +a, +b, +c, +d}:
      +word = Bool.pick(U32, (index < 4 : U32), a, Bool.pick(U32, (index < 8 : U32), b, Bool.pick(U32, (index < 12 : U32), c, d)))
      ((word >> U32.to_nat(((index % 4) * 8 : U32))) .&. 255 : U32)

def chosen(+id: U32, +index: U32) -> U32:
  Bool.to_u32(U32.is_eq(id, index))

# How many times the catalog entry appears in the generated world.
def count_of(+p: Pieces, +kind: U32, +index: U32) -> U32:
  match p:
    case Pieces{+trap, +poi, +protected, _, _, _, _}:
      Bool.pick(U32, U32.is_eq(kind, Catalog.kind_fixed()), index,
      Bool.pick(U32, U32.is_eq(kind, Catalog.kind_boon()), boon_count(p, index),
      Bool.pick(U32, U32.is_eq(kind, Catalog.kind_trap()), chosen(trap, index),
      Bool.pick(U32, U32.is_eq(kind, Catalog.kind_point_of_interest()), chosen(poi, index), chosen(protected, index)))))
