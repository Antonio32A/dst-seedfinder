import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ./walk.bend as Walk
import ./world.bend as FilterWorld

# Costs shared by both metrics: a straight distance (a double) or an exact walk length; Unreached is infinity.
type Cost is Data:
  Unreached{}
  Straight{value: F64Repr.F64}
  Walk{length: Walk.Length}

# A relaxation source: an instance and the cost already paid to stand on it.
type Seed is Data:
  Seed{inst: FilterWorld.Inst, cost: Cost}

# The best cost of a target and the position of the seed achieving it (in the seed list), as metric.py's Relaxed.
type Relaxed is Data:
  Relaxed{cost: Cost, seed: U32}

# A wormhole jump (entry, exit) on a shortest path.
type Hop is Data:
  Hop{entry: FilterWorld.Inst, exit: FilterWorld.Inst}

# The length of one leg and the wormhole jumps of one shortest path, in order.
type Leg is Data:
  Leg{cost: Cost, hops: List<&2, Hop>}

def unreached() -> Relaxed:
  Relaxed{Unreached{}, 0}

# A placeholder instance for lookups that cannot miss.
def none_inst() -> FilterWorld.Inst:
  FilterWorld.Inst{0, 0, F64Repr.zero(), F64Repr.zero(), 0, 0, 0}

# a < b, with Unreached above every cost.
def cost_lt(a: Cost, b: Cost) -> Bool:
  match a b:
    case Straight{+x} Straight{+y}:
      F64Cmp.lt(x, y)
    case Walk{+x} Walk{+y}:
      Walk.is_lt(x, y)
    case Unreached{} _:
      False{}
    case _ Unreached{}:
      True{}
    case _ _:
      False{}

def is_reached(c: Cost) -> Bool:
  match c:
    case Unreached{}:
      False{}
    case _:
      True{}

def within_max(+c: Cost, m: Maybe<&2, F64Repr.F64>) -> Bool:
  match c m:
    case _ None{}:
      True{}
    case Unreached{} Some{_}:
      False{}
    case Straight{+x} Some{+bound}:
      F64Cmp.le(x, bound)
    case Walk{+l} Some{+bound}:
      Walk.within_max(l, Walk.bound_of(bound))

def within_min(+c: Cost, m: Maybe<&2, F64Repr.F64>) -> Bool:
  match c m:
    case _ None{}:
      True{}
    case Unreached{} Some{_}:
      True{}
    case Straight{+x} Some{+bound}:
      F64Cmp.le(bound, x)
    case Walk{+l} Some{+bound}:
      Walk.within_min(l, Walk.bound_of(bound))

# metric.py's `within(value, low, high)` for a cost.
def within(+c: Cost, low: Maybe<&2, F64Repr.F64>, high: Maybe<&2, F64Repr.F64>) -> Bool:
  within_min(c, low) && within_max(c, high)

def same_inst(+a: FilterWorld.Inst, +b: FilterWorld.Inst) -> Bool:
  match a b:
    case FilterWorld.Inst{+ap, +ai, _, _, _, _, _} FilterWorld.Inst{+bp, +bi, _, _, _, _, _}:
      U32.is_eq(ap, bp) && U32.is_eq(ai, bi)

def own_seed_from(seeds: List<&2, Seed>, +target: FilterWorld.Inst, +i: U32) -> U32:
  match seeds:
    case Nil{}:
      4294967295
    case Con{Seed{+inst, _}, rest}:
      Bool.pick(U32, same_inst(inst, target), i, own_seed_from(rest, target, (i + 1 : U32)))

# The position of the seed that is the target itself (4294967295 when none or when self pairs are allowed).
def own_seed(+exclude_self: Bool, +seeds: List<&2, Seed>, +target: FilterWorld.Inst) -> U32:
  Bool.pick(U32, exclude_self, own_seed_from(seeds, target, 0), 4294967295)
