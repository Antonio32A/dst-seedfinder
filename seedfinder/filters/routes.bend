import Base
import ./anchor.bend as AN
import ./metric.bend as MT
import ./relax.bend as RX
import ./par.bend as PX

# The exact shortest instance-consistent route (criteria.py shortest_route): Held-Karp over the set of visited stops,
# where every transition is one multi-source relaxation from all route ends of a set to the instances of the next
# stops. No candidate is pruned.

# A route prefix: its last instance, its length, and the prefix before it.
type Path is Data:
  PStart{}
  PStop{point: AN.Point, cost: MT.Cost, parent: Path}

def path_point(+p: Path) -> AN.Point:
  match p:
    case PStop{+point, _, _}:
      point
    case PStart{}:
      AN.Point{MT.none_inst(), None{}}

def path_cost(+p: Path) -> MT.Cost:
  match p:
    case PStop{_, +cost, _}:
      cost
    case PStart{}:
      MT.Unreached{}

def bit_count(+mask: U32) -> U32:
  +a = ((mask .&. 21845) + ((mask >> 1n) .&. 21845) : U32)
  +b = ((a .&. 13107) + ((a >> 2n) .&. 13107) : U32)
  +c = ((b .&. 3855) + ((b >> 4n) .&. 3855) : U32)
  ((c .&. 255) + (c >> 8n) : U32)

def masks_of_size(n: Nat, +size: U32, +mask: U32, +limit: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      +rest = masks_of_size(k, size, (mask + 1 : U32), limit)
      Bool.pick(List<&2, U32>, (mask < limit : U32) && U32.is_eq(bit_count(mask), size), mask <> rest, rest)

def unvisited(n: Nat, +mask: U32, +k: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +rest = unvisited(p, mask, (k + 1 : U32))
      Bool.pick(List<&2, U32>, U32.is_zero(((mask >> U32.to_nat(k)) .&. 1 : U32)), k <> rest, rest)

def next_stops(+mask: U32, +count: U32, +fixed: Bool) -> List<&2, U32>:
  +all = unvisited(U32.to_nat(count), mask, 0)
  Bool.pick(List<&2, U32>, fixed, List.take(&2, U32, all, 1n), all)

type Target is Data:
  Target{stop: U32, point: AN.Point}

def stop_targets(+k: U32, points: List<&2, AN.Point>) -> List<&2, Target>:
  match points:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      Target{k, p} <> stop_targets(k, rest)

def targets_of(ks: List<&2, U32>, +stops: List<&2, List<&2, AN.Point>>) -> List<&2, Target>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{+k, rest}:
      List.append(&2, Target, stop_targets(k, Maybe.default(&2, List<&2, AN.Point>, List.get(&2, List<&2, AN.Point>, stops, U32.to_nat(k)), Nil{})), targets_of(rest, stops))

def target_points(targets: List<&2, Target>) -> List<&2, AN.Point>:
  match targets:
    case Nil{}:
      Nil{}
    case Con{Target{_, +p}, rest}:
      p <> target_points(rest)

def sources_of(paths: List<&2, Path>) -> List<&2, RX.Src>:
  match paths:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      RX.Src{path_point(p), path_cost(p)} <> sources_of(rest)

def frontier_at(+frontier: List<&2, List<&2, Path>>, +mask: U32) -> List<&2, Path>:
  Maybe.default(&2, List<&2, Path>, List.get(&2, List<&2, Path>, frontier, U32.to_nat(mask)), Nil{})

def reached_paths(points: List<&2, AN.Point>, relaxed: List<&2, MT.Relaxed>, +seeds: List<&2, Path>, +acc: List<&2, Path>) -> List<&2, Path>:
  match points relaxed:
    case Con{+p, ps} Con{MT.Relaxed{+cost, +seed}, rs}:
      +parent = Maybe.default(&2, Path, List.get(&2, Path, seeds, U32.to_nat(seed)), PStart{})
      reached_paths(ps, rs, seeds, Bool.pick(List<&2, Path>, MT.is_reached(cost), PStop{p, cost, parent} <> acc, acc))
    case _ _:
      List.reverse(&2, Path, acc)

def appended_all(+frontier: List<&2, List<&2, Path>>, +mask: U32, +paths: List<&2, Path>) -> List<&2, List<&2, Path>>:
  List.set(&2, List<&2, Path>, frontier, U32.to_nat(mask), List.append(&2, Path, frontier_at(frontier, mask), paths))

def stop_points(+stops: List<&2, List<&2, AN.Point>>, +k: U32) -> List<&2, AN.Point>:
  Maybe.default(&2, List<&2, AN.Point>, List.get(&2, List<&2, AN.Point>, stops, U32.to_nat(k)), Nil{})

# Appends, stop by stop, the reached instances of each next stop to the frontier of the set grown by that stop.
# The paths a relaxation from one set adds to the frontier of one bigger set.
type Growth is Data:
  Growth{mask: U32, paths: List<&2, Path>}

def growths(ks: List<&2, U32>, +relaxed: List<&2, MT.Relaxed>, +stops: List<&2, List<&2, AN.Point>>, +seeds: List<&2, Path>, +mask: U32) -> List<&2, Growth>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{+k, rest}:
      +points = stop_points(stops, k)
      +n = List.length(&2, AN.Point, points)
      Growth{(mask .|. (1 << U32.to_nat(k)) : U32), reached_paths(points, List.take(&2, MT.Relaxed, relaxed, n), seeds, Nil{})}
        <> growths(rest, List.drop(&2, MT.Relaxed, relaxed, n), stops, seeds, mask)

type Plan is Data:
  Plan{count: U32, fixed: Bool, stops: List<&2, List<&2, AN.Point>>}

# What one set of visited stops is relaxed against: the metric, the plan, and the frontier before its size.
type Stage is Data:
  Stage{space: RX.Space, plan: Plan, frontier: List<&2, List<&2, Path>>}

def grow_from(seeds: List<&2, Path>, +s: RX.Space, +plan: Plan, +mask: U32) -> List<&2, Growth>:
  match seeds plan:
    case Nil{} _:
      Nil{}
    case Con{+first, +rest} Plan{+count, +fixed, +stops}:
      +ks = next_stops(mask, count, fixed)
      growths(ks, RX.relax(s, sources_of(first <> rest), target_points(targets_of(ks, stops)), False{}), stops, first <> rest, mask)

# One Held-Karp transition: the relaxation from the frontier of `mask` to the instances of its next stops.
def grow_at(+stage: Stage, +mask: U32) -> List<&2, Growth>:
  match stage:
    case Stage{+s, +plan, +frontier}:
      grow_from(frontier_at(frontier, mask), s, plan, mask)

def grow_mask(stage: Stage, mask: U32) -> List<&2, Growth>:
  grow_at(stage, mask)

def merged(gs: List<&2, Growth>, +frontier: List<&2, List<&2, Path>>) -> List<&2, List<&2, Path>>:
  match gs:
    case Nil{}:
      frontier
    case Con{Growth{+mask, +paths}, rest}:
      merged(rest, appended_all(frontier, mask, paths))

def merged_all(all: List<&2, List<&2, Growth>>, +frontier: List<&2, List<&2, Path>>) -> List<&2, List<&2, Path>>:
  match all:
    case Nil{}:
      frontier
    case Con{+gs, rest}:
      merged_all(rest, merged(gs, frontier))

def cleared(masks: List<&2, U32>, +frontier: List<&2, List<&2, Path>>) -> List<&2, List<&2, Path>>:
  match masks:
    case Nil{}:
      frontier
    case Con{+mask, rest}:
      cleared(rest, List.set(&2, List<&2, Path>, frontier, U32.to_nat(mask), Nil{}))

# The masks of one size relax in parallel (each reads only frontiers of its own size, final by then); their paths
# are appended in mask order, as the sequential loop appends them.
def run_group(+masks: List<&2, U32>, +s: RX.Space, +plan: Plan, +frontier: List<&2, List<&2, Path>>) -> List<&2, List<&2, Path>>:
  merged_all(PX.map(~U32, ~List<&2, Growth>, ~Stage, ~grow_mask, Stage{s, plan, frontier}, masks), cleared(masks, frontier))

def run_groups(groups: List<&2, List<&2, U32>>, +s: RX.Space, +plan: Plan, +frontier: List<&2, List<&2, Path>>) -> List<&2, List<&2, Path>>:
  match groups:
    case Nil{}:
      frontier
    case Con{+masks, rest}:
      run_groups(rest, s, plan, run_group(masks, s, plan, frontier))

def size_groups(n: Nat, +size: U32, +count: U32, +fixed: Bool) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      Bool.pick(List<&2, U32>, fixed, [((1 << U32.to_nat(size)) - 1 : U32)], masks_of_size(64n, size, 0, ((1 << U32.to_nat(count)) - 1 : U32)))
        <> size_groups(k, (size + 1 : U32), count, fixed)

def cheapest(paths: List<&2, Path>, +best: Path) -> Path:
  match paths:
    case Nil{}:
      best
    case Con{+p, rest}:
      cheapest(rest, Bool.pick(Path, MT.cost_lt(path_cost(p), path_cost(best)), p, best))

def first_path(+paths: List<&2, Path>) -> Maybe<&2, Path>:
  match paths:
    case Nil{}:
      None{}
    case Con{+p, rest}:
      Some{cheapest(rest, p)}

type Best is Data:
  Best{cost: MT.Cost, seed: U32, target: U32}

def best_target(relaxed: List<&2, MT.Relaxed>, +i: U32, +best: Best) -> Best:
  match relaxed best:
    case Con{MT.Relaxed{+cost, +seed}, rest} Best{+bc, +bs, +bt}:
      best_target(rest, (i + 1 : U32), Bool.pick(Best, MT.cost_lt(cost, bc), Best{cost, seed, i}, Best{bc, bs, bt}))
    case _ other:
      other

# The target reached most cheaply (the first on ties), or none when every target is unreached.
def argmin(relaxed: List<&2, MT.Relaxed>) -> Best:
  best_target(relaxed, 0, Best{MT.Unreached{}, 0, 0})

def closed_at(+b: Best, +finals: List<&2, Path>, +ends: List<&2, AN.Point>) -> Maybe<&2, Path>:
  match b:
    case Best{+cost, +seed, +target}:
      Bool.pick(Maybe<&2, Path>, MT.is_reached(cost),
        Some{PStop{Maybe.default(&2, AN.Point, List.get(&2, AN.Point, ends, U32.to_nat(target)), AN.Point{MT.none_inst(), None{}}), cost,
          Maybe.default(&2, Path, List.get(&2, Path, finals, U32.to_nat(seed)), PStart{})}}, None{})

def close_with(to: Maybe<&2, List<&2, AN.Point>>, +s: RX.Space, finals: List<&2, Path>) -> Maybe<&2, Path>:
  match to finals:
    case None{} paths:
      first_path(paths)
    case Some{_} Nil{}:
      None{}
    case Some{+ends} Con{+first, +rest}:
      closed_at(argmin(RX.relax(s, sources_of(first <> rest), ends, False{})), first <> rest, ends)

def start_paths(points: List<&2, AN.Point>, +zero: MT.Cost) -> List<&2, Path>:
  match points:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      PStop{p, zero, PStart{}} <> start_paths(rest, zero)

def empty_frontier(n: Nat) -> List<&2, List<&2, Path>>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      Nil{} <> empty_frontier(k)

# The last stop of the shortest route from `from` through every stop (to `to` when given), or None.
def shortest(+s: RX.Space, +from: List<&2, AN.Point>, +stops: List<&2, List<&2, AN.Point>>, to: Maybe<&2, List<&2, AN.Point>>, +fixed: Bool) -> Maybe<&2, Path>:
  +count = U32.from_nat(List.length(&2, List<&2, AN.Point>, stops))
  +frontier = List.set(&2, List<&2, Path>, empty_frontier(128n), 0n, start_paths(from, RX.zero(s)))
  +done = run_groups(size_groups(U32.to_nat(count), 0, count, fixed), s, Plan{count, fixed, stops}, frontier)
  close_with(to, s, frontier_at(done, ((1 << U32.to_nat(count)) - 1 : U32)))

def unwound(p: Path, +acc: List<&2, AN.Point>) -> List<&2, AN.Point>:
  match p:
    case PStart{}:
      acc
    case PStop{+point, _, parent}:
      unwound(parent, point <> acc)

# The instances of a route, first stop first.
def unwind(+p: Path) -> List<&2, AN.Point>:
  unwound(p, Nil{})
