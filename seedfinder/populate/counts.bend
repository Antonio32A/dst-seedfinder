import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../f64/random.bend as F64Random
import ../data/distribute.bend as Distribute
import ../data/picks.bend as Picks
import ../data/rooms.bend as Rooms

# The room closures of ConvertGround / PopulateVoronoi (data/closures.bend category 1, bodies in
# scripts/gen/out/closures.json) and forest_map.lua's pickspawnprefab.

def draw_pair(got: U32 & Pcg.Rng, +offset: U32) -> U32 & Pcg.Rng:
  (+v, rng) = got
  ((v + offset : U32), rng)

def upto(rng: Pcg.Rng, +n: U32, +offset: U32) -> U32 & Pcg.Rng:
  draw_pair(MathRandom.random_upto(rng, n), offset)

def range(rng: Pcg.Rng, +m: U32, +n: U32, +offset: U32) -> U32 & Pcg.Rng:
  draw_pair(MathRandom.random_range(rng, m, n), offset)

def above_drawn(got: U32 & Pcg.Rng, +limit: U32, +yes: U32) -> U32 & Pcg.Rng:
  (+v, rng) = got
  (Bool.pick(U32, (v > limit : U32), yes, 0), rng)

def uniform_drawn(got: F64Repr.F64 & Pcg.Rng, +limit: F64Repr.F64, +yes: U32) -> U32 & Pcg.Rng:
  (+r, rng) = got
  (Bool.pick(U32, F64Cmp.gt(r, limit), yes, 0), rng)

def uniform_above(rng: Pcg.Rng, +limit: F64Repr.F64, +yes: U32) -> U32 & Pcg.Rng:
  uniform_drawn(F64Random.random(rng), limit, yes)

def below_drawn(got: F64Repr.F64 & Pcg.Rng, +limit: F64Repr.F64, +yes: U32) -> U32 & Pcg.Rng:
  (+r, rng) = got
  (Bool.pick(U32, F64Cmp.lt(r, limit), yes, 0), rng)

def ninety_seven_hundredths() -> F64Repr.F64:
  F64Repr.F64{1072630333, 1889785610}

def livingtree_chance() -> F64Repr.F64:
  F64Repr.F64{1071749529, 2576980378}

def quarter() -> F64Repr.F64:
  F64Repr.F64{1070596096, 0}

def boulder_gen_chance() -> F64Repr.F64:
  F64Repr.F64{1070945621, 1431655765}

def rare_pick(hit: Bool, rng: Pcg.Rng) -> U32 & Pcg.Rng:
  match hit:
    case False{}:
      (0, rng)
    case True{}:
      range(rng, 1, 2, 0)

def rare_pair(got: U32 & Pcg.Rng) -> U32 & Pcg.Rng:
  (+hit, rng) = got
  rare_pick(U32.is_ne(hit, 0), rng)

def moon_count(+area: U32, +per: U32, +extra: U32) -> U32:
  (U32.max(1, (area / per : U32)) + extra : U32)

def small_world(+width: U32) -> U32:
  Bool.to_u32((width < 425 : U32))

# A count closure's value (area = the site area in ConvertGround, the kept point count in PopulateVoronoi).
def count_of(+closure: U32, +area: U32, +width: U32, rng: Pcg.Rng) -> U32 & Pcg.Rng:
  match closure:
    case 68:
      above_drawn(MathRandom.random_range(rng, 0, 1000), 985, 1)
    case 69:
      upto(rng, 4, 2)
    case 70:
      upto(rng, 2, 0)
    case 71:
      upto(rng, 5, 0)
    case 72:
      upto(rng, 4, 4)
    case 73:
      above_drawn(MathRandom.random_upto(rng, 1000), 995, 1)
    case 74:
      range(rng, 2, 5, 0)
    case 75:
      uniform_above(rng, ninety_seven_hundredths(), 1)
    case 76:
      upto(rng, 4, 3)
    case 77:
      upto(rng, 3, 0)
    case 79:
      range(rng, 0, 1, 0)
    case 80:
      rare_pair(uniform_above(rng, ninety_seven_hundredths(), 1))
    case 81:
      upto(rng, 4, 5)
    case 83:
      upto(rng, 3, 5)
    case 84:
      upto(rng, 3, 3)
    case 86:
      uniform_above(rng, livingtree_chance(), 1)
    case 87:
      (moon_count(area, 75, 2), rng)
    case 88:
      (moon_count(area, 100, 0), rng)
    case 89:
      (moon_count(area, 50, 0), rng)
    case 90:
      (moon_count(area, 25, 0), rng)
    case 91:
      range(rng, 0, 1, 0)
    case 92:
      range(rng, 0, 2, 0)
    case 93:
      ((1 - small_world(width) : U32), rng)
    case 94:
      (small_world(width), rng)
    case 95:
      range(rng, 1, 2, 0)
    case 96:
      range(rng, 1, 2, 4294967295)
    case 97:
      range(rng, 3, 5, 0)
    case 100:
      upto(rng, 3, 0)
    case 141:
      upto(rng, 2, 4294967295)
    case 142:
      below_drawn(F64Random.random(rng), quarter(), 1)
    case 143:
      range(rng, 2, 3, 0)
    case _:
      (0, rng)

# A countprefabs / countstaticlayouts value: kind 0 an integer, kind 1 a closure.
def value_of(+kind: U32, +v: U32, +area: U32, +width: U32, rng: Pcg.Rng) -> U32 & Pcg.Rng:
  match kind:
    case 1:
      count_of(v, area, width, rng)
    case _:
      (v, rng)

def prefab_data_drawn(got: U32 & Pcg.Rng) -> Pcg.Rng:
  (_, rng) = got
  rng

def rock_tree_rolled(hit: Bool, rng: Pcg.Rng) -> Pcg.Rng:
  match hit:
    case True{}:
      prefab_data_drawn(Pcg.draw(rng))
    case False{}:
      rng

def rock_tree_drawn(got: F64Repr.F64 & Pcg.Rng) -> Pcg.Rng:
  (+r, rng) = got
  rock_tree_rolled(F64Cmp.lt(r, boulder_gen_chance()), rng)

# Calling a prefabdata closure (data/closures.bend id; 0 when the prefab has no prefabdata): the spiderden growth stage
# (85) and the vent rock state (145) draw math.random() once, RandomRockTreeState (144) draws a second one when the
# first is below BOULDER_GEN_CHANCE.
def prefab_data_call(+closure: U32, rng: Pcg.Rng) -> Pcg.Rng:
  match closure:
    case 85:
      prefab_data_drawn(Pcg.draw(rng))
    case 144:
      rock_tree_drawn(F64Random.random(rng))
    case 145:
      prefab_data_drawn(Pcg.draw(rng))
    case _:
      rng

def f64_of(bits: U32 & U32) -> F64Repr.F64:
  (+hi, +lo) = bits
  F64Repr.F64{hi, lo}

def weight_of(+unit: U32) -> F64Repr.F64:
  f64_of(Rooms.weight(Distribute.entry_weight(unit)))

def entry_at(+entries: List<&2, U32>, +i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, entries, U32.to_nat(i)), 0)

def picked_units(order: List<&2, U32>, +entries: List<&2, U32>) -> List<&2, U32>:
  match order:
    case Nil{}:
      Nil{}
    case Con{+i, rest}:
      entry_at(entries, i) <> picked_units(rest, entries)

# A pickspawnprefab item: prefab string id and weight.
type Weighted is Data:
  Weighted{prefab: U32, weight: F64Repr.F64}

def weighted(units: List<&2, U32>) -> List<&2, Weighted>:
  match units:
    case Nil{}:
      Nil{}
    case Con{+u, rest}:
      Weighted{Distribute.entry_prefab(u), weight_of(u)} <> weighted(rest)

def weighted_total(items: List<&2, Weighted>, +acc: F64Repr.F64) -> F64Repr.F64:
  match items:
    case Nil{}:
      acc
    case Con{Weighted{_, +w}, rest}:
      weighted_total(rest, F64Arith.add(acc, w))

# pickspawnprefab's items for one (distribute variant, tile), decoded once: (prefab, weight) in the order of its
# total and subtraction loops, and the total.
type Prepared is Data:
  Prepared{items: List<&2, Weighted>, total: F64Repr.F64}

def prepared(+items: List<&2, Weighted>) -> Prepared:
  Prepared{items, weighted_total(items, F64Repr.zero())}

def subtract_loop(items: List<&2, Weighted>, +rnd: F64Repr.F64, done: Bool, +found: U32) -> U32:
  match items:
    case Nil{}:
      found
    case Con{Weighted{+prefab, +w}, rest}:
      match done:
        case True{}:
          found
        case False{}:
          +left = F64Arith.sub(rnd, w)
          +hit = F64Cmp.le(left, F64Repr.zero())
          subtract_loop(rest, left, hit, Bool.pick(U32, hit, prefab, 4294967295))

def pick_drawn(got: F64Repr.F64 & Pcg.Rng, +items: List<&2, Weighted>, +total: F64Repr.F64) -> U32 & Pcg.Rng:
  (+r, rng) = got
  (subtract_loop(items, F64Arith.mul(r, total), False{}, 4294967295), rng)

def pick_total(positive: Bool, +items: List<&2, Weighted>, +total: F64Repr.F64, rng: Pcg.Rng) -> U32 & Pcg.Rng:
  match positive:
    case False{}:
      (4294967295, rng)
    case True{}:
      pick_drawn(F64Random.random(rng), items, total)

# The weighted pick of pickspawnprefab on prepared items.
def pick_prepared(+p: Prepared, rng: Pcg.Rng) -> U32 & Pcg.Rng:
  match p:
    case Prepared{+items, +total}:
      pick_total(F64Cmp.gt(total, F64Repr.zero()), items, total, rng)

def pick_units(+units: List<&2, U32>, rng: Pcg.Rng) -> U32 & Pcg.Rng:
  pick_prepared(prepared(weighted(units)), rng)

def class_units(unfiltered: Bool, +variant: U32, +class: U32) -> List<&2, U32>:
  match unfiltered:
    case True{}:
      Distribute.variants(variant)
    case False{}:
      picked_units(Picks.pick(variant, class), Distribute.variants(variant))

# pickspawnprefab's items for a distribute variant on a tile (a tile outside the land classes filters nothing).
def prepare(+variant: U32, +tile: U32) -> Prepared:
  +class = Distribute.tile_class(tile)
  prepared(weighted(class_units(U32.is_eq(class, 1048575), variant, class)))

# pickspawnprefab(distributeprefabs, ground): the prefab string id (4294967295 = nil) for a distribute variant on a
# tile; one math.random() when the filtered weights sum above 0.
def pickspawnprefab(+variant: U32, +tile: U32, rng: Pcg.Rng) -> U32 & Pcg.Rng:
  pick_prepared(prepare(variant, tile), rng)
