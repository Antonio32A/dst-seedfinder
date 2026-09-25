import Base
import ../rng/pcg.bend as R
import ../lua/math_random.bend as LM
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ../f64/random.bend as FRN
import ../data/distribute.bend as DS
import ../data/picks.bend as PK
import ../data/rooms.bend as RM

# The room closures of ConvertGround / PopulateVoronoi (data/closures.bend category 1, bodies in
# .scratch/port/gen/out/closures.json) and forest_map.lua's pickspawnprefab.

def draw_pair(got: U32 & R.Rng, +offset: U32) -> U32 & R.Rng:
  (+v, rng) = got
  ((v + offset : U32), rng)

def upto(rng: R.Rng, +n: U32, +offset: U32) -> U32 & R.Rng:
  draw_pair(LM.random_upto(rng, n), offset)

def range(rng: R.Rng, +m: U32, +n: U32, +offset: U32) -> U32 & R.Rng:
  draw_pair(LM.random_range(rng, m, n), offset)

def above_drawn(got: U32 & R.Rng, +limit: U32, +yes: U32) -> U32 & R.Rng:
  (+v, rng) = got
  (Bool.pick(U32, (v > limit : U32), yes, 0), rng)

def uniform_drawn(got: FR.F64 & R.Rng, +limit: FR.F64, +yes: U32) -> U32 & R.Rng:
  (+r, rng) = got
  (Bool.pick(U32, FC.gt(r, limit), yes, 0), rng)

def uniform_above(rng: R.Rng, +limit: FR.F64, +yes: U32) -> U32 & R.Rng:
  uniform_drawn(FRN.random(rng), limit, yes)

def ninety_seven_hundredths() -> FR.F64:
  FR.F64{1072630333, 1889785610}

def livingtree_chance() -> FR.F64:
  FR.F64{1071749529, 2576980378}

def rare_pick(hit: Bool, rng: R.Rng) -> U32 & R.Rng:
  match hit:
    case False{}:
      (0, rng)
    case True{}:
      range(rng, 1, 2, 0)

def rare_pair(got: U32 & R.Rng) -> U32 & R.Rng:
  (+hit, rng) = got
  rare_pick(U32.is_ne(hit, 0), rng)

def moon_count(+area: U32, +per: U32, +extra: U32) -> U32:
  (U32.max(1, (area / per : U32)) + extra : U32)

def small_world(+width: U32) -> U32:
  Bool.to_u32((width < 425 : U32))

# A count closure's value (area = the site area in ConvertGround, the kept point count in PopulateVoronoi).
def count_of(+closure: U32, +area: U32, +width: U32, rng: R.Rng) -> U32 & R.Rng:
  match closure:
    case 68:
      above_drawn(LM.random_range(rng, 0, 1000), 985, 1)
    case 69:
      upto(rng, 4, 2)
    case 70:
      upto(rng, 2, 0)
    case 71:
      upto(rng, 5, 0)
    case 72:
      upto(rng, 4, 4)
    case 73:
      above_drawn(LM.random_upto(rng, 1000), 995, 1)
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
    case _:
      (0, rng)

# A countprefabs / countstaticlayouts value: kind 0 an integer, kind 1 a closure.
def value_of(+kind: U32, +v: U32, +area: U32, +width: U32, rng: R.Rng) -> U32 & R.Rng:
  match kind:
    case 1:
      count_of(v, area, width, rng)
    case _:
      (v, rng)

def prefab_data_drawn(got: U32 & R.Rng) -> R.Rng:
  (_, rng) = got
  rng

# Calling a prefabdata closure (kind 1): SpiderVillage's spiderden growth stage draws math.random() once.
def prefab_data_call(+kind: U32, rng: R.Rng) -> R.Rng:
  match kind:
    case 1:
      prefab_data_drawn(R.draw(rng))
    case _:
      rng

def f64_of(bits: U32 & U32) -> FR.F64:
  (+hi, +lo) = bits
  FR.F64{hi, lo}

def weight_of(+unit: U32) -> FR.F64:
  f64_of(RM.weight(DS.entry_weight(unit)))

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
  Weighted{prefab: U32, weight: FR.F64}

def weighted(units: List<&2, U32>) -> List<&2, Weighted>:
  match units:
    case Nil{}:
      Nil{}
    case Con{+u, rest}:
      Weighted{DS.entry_prefab(u), weight_of(u)} <> weighted(rest)

def weighted_total(items: List<&2, Weighted>, +acc: FR.F64) -> FR.F64:
  match items:
    case Nil{}:
      acc
    case Con{Weighted{_, +w}, rest}:
      weighted_total(rest, FA.add(acc, w))

# pickspawnprefab's items for one (distribute variant, tile), decoded once: (prefab, weight) in the order of its
# total and subtraction loops, and the total.
type Prepared is Data:
  Prepared{items: List<&2, Weighted>, total: FR.F64}

def prepared(+items: List<&2, Weighted>) -> Prepared:
  Prepared{items, weighted_total(items, FR.zero())}

def subtract_loop(items: List<&2, Weighted>, +rnd: FR.F64, done: Bool, +found: U32) -> U32:
  match items:
    case Nil{}:
      found
    case Con{Weighted{+prefab, +w}, rest}:
      match done:
        case True{}:
          found
        case False{}:
          +left = FA.sub(rnd, w)
          +hit = FC.le(left, FR.zero())
          subtract_loop(rest, left, hit, Bool.pick(U32, hit, prefab, 4294967295))

def pick_drawn(got: FR.F64 & R.Rng, +items: List<&2, Weighted>, +total: FR.F64) -> U32 & R.Rng:
  (+r, rng) = got
  (subtract_loop(items, FA.mul(r, total), False{}, 4294967295), rng)

def pick_total(positive: Bool, +items: List<&2, Weighted>, +total: FR.F64, rng: R.Rng) -> U32 & R.Rng:
  match positive:
    case False{}:
      (4294967295, rng)
    case True{}:
      pick_drawn(FRN.random(rng), items, total)

# The weighted pick of pickspawnprefab on prepared items.
def pick_prepared(+p: Prepared, rng: R.Rng) -> U32 & R.Rng:
  match p:
    case Prepared{+items, +total}:
      pick_total(FC.gt(total, FR.zero()), items, total, rng)

def pick_units(+units: List<&2, U32>, rng: R.Rng) -> U32 & R.Rng:
  pick_prepared(prepared(weighted(units)), rng)

def class_units(unfiltered: Bool, +variant: U32, +class: U32) -> List<&2, U32>:
  match unfiltered:
    case True{}:
      DS.variants(variant)
    case False{}:
      picked_units(PK.pick(variant, class), DS.variants(variant))

# pickspawnprefab's items for a distribute variant on a tile (a tile outside the land classes filters nothing).
def prepare(+variant: U32, +tile: U32) -> Prepared:
  +class = DS.tile_class(tile)
  prepared(weighted(class_units(U32.is_eq(class, 1048575), variant, class)))

# pickspawnprefab(distributeprefabs, ground): the prefab string id (4294967295 = nil) for a distribute variant on a
# tile; one math.random() when the filtered weights sum above 0.
def pickspawnprefab(+variant: U32, +tile: U32, rng: R.Rng) -> U32 & R.Rng:
  pick_prepared(prepare(variant, tile), rng)
