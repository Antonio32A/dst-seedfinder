import Base
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ../f32/ops.bend as FO
import ./world.bend as WD
import ./metric.bend as MT

# The straight metric of .scratch/search/metric.py (StraightMetric) in IEEE doubles, operation for operation: the
# Euclidean distance sqrt(dx*dx + dz*dz), and with wormholes the Floyd-Warshall closure over the link ends (free
# links, Euclidean flights between ends), any number of jumps.

# The wormhole ends (the links' entries and exits in first-appearance order), their closure and next-hop matrices,
# and the links as pairs of end positions.
type At is Data:
  At{from: U32, to: U32}

type Ends is Data:
  Ends{insts: List<&2, WD.Inst>, closure: List<&2, List<&2, FR.F64>>, next: List<&2, List<&2, U32>>, links: List<&2, At>}

def x_of(+i: WD.Inst) -> FR.F64:
  match i:
    case WD.Inst{_, _, +x, _, _, _, _}:
      x

def z_of(+i: WD.Inst) -> FR.F64:
  match i:
    case WD.Inst{_, _, _, +z, _, _, _}:
      z

def square(+d: FR.F64) -> FR.F64:
  FA.mul(d, d)

# The distance between two instances, as numpy's sqrt(((a - b) ** 2).sum()).
def distance(+a: WD.Inst, +b: WD.Inst) -> FR.F64:
  FA.sqrt(FA.add(square(FA.sub(x_of(a), x_of(b))), square(FA.sub(z_of(a), z_of(b)))))

def position_from(ends: List<&2, WD.Inst>, +inst: WD.Inst, +i: U32) -> U32:
  match ends:
    case Nil{}:
      i
    case Con{+head, rest}:
      Bool.pick(U32, MT.same_inst(head, inst), i, position_from(rest, inst, (i + 1 : U32)))

def position(+ends: List<&2, WD.Inst>, +inst: WD.Inst) -> U32:
  position_from(ends, inst, 0)

def is_known(+ends: List<&2, WD.Inst>, +inst: WD.Inst) -> Bool:
  (position(ends, inst) < U32.from_nat(List.length(&2, WD.Inst, ends)) : U32)

def with_end(+ends: List<&2, WD.Inst>, +inst: WD.Inst) -> List<&2, WD.Inst>:
  Bool.pick(List<&2, WD.Inst>, is_known(ends, inst), ends, List.append(&2, WD.Inst, ends, [inst]))

def end_list(links: List<&2, WD.Link>, +ends: List<&2, WD.Inst>) -> List<&2, WD.Inst>:
  match links:
    case Nil{}:
      ends
    case Con{WD.Link{+entry, +exit}, rest}:
      end_list(rest, with_end(with_end(ends, entry), exit))

def link_positions(links: List<&2, WD.Link>, +ends: List<&2, WD.Inst>) -> List<&2, At>:
  match links:
    case Nil{}:
      Nil{}
    case Con{WD.Link{+entry, +exit}, rest}:
      At{position(ends, entry), position(ends, exit)} <> link_positions(rest, ends)

def is_link(pairs: List<&2, At>, +a: U32, +b: U32) -> Bool:
  match pairs:
    case Nil{}:
      False{}
    case Con{At{+x, +y}, rest}:
      (U32.is_eq(x, a) && U32.is_eq(y, b)) || is_link(rest, a, b)

def first_row(+links: List<&2, At>, +from: WD.Inst, +i: U32, ends: List<&2, WD.Inst>, +j: U32) -> List<&2, FR.F64>:
  match ends:
    case Nil{}:
      Nil{}
    case Con{+to, rest}:
      Bool.pick(FR.F64, is_link(links, i, j), FR.zero(), distance(from, to)) <> first_row(links, from, i, rest, (j + 1 : U32))

def first_rows(+links: List<&2, At>, rows: List<&2, WD.Inst>, +all: List<&2, WD.Inst>, +i: U32) -> List<&2, List<&2, FR.F64>>:
  match rows:
    case Nil{}:
      Nil{}
    case Con{+from, rest}:
      first_row(links, from, i, all, 0) <> first_rows(links, rest, all, (i + 1 : U32))

def counting(n: Nat, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      i <> counting(p, (i + 1 : U32))

def identity_after(n: Nat, +count: Nat) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      counting(count, 0) <> identity_after(p, count)

def cost_at(+row: List<&2, FR.F64>, +j: U32) -> FR.F64:
  Maybe.default(&2, FR.F64, List.get(&2, FR.F64, row, U32.to_nat(j)), FR.zero())

def next_in(+row: List<&2, U32>, +j: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, row, U32.to_nat(j)), j)

def relaxed_costs(costs: List<&2, FR.F64>, through_m: List<&2, FR.F64>, +cim: FR.F64) -> List<&2, FR.F64>:
  match costs through_m:
    case Con{+c, cs} Con{+cm, ms}:
      +through = FA.add(cim, cm)
      Bool.pick(FR.F64, FC.lt(through, c), through, c) <> relaxed_costs(cs, ms, cim)
    case _ _:
      Nil{}

def relaxed_after(costs: List<&2, FR.F64>, after: List<&2, U32>, through_m: List<&2, FR.F64>, +cim: FR.F64, +aim: U32) -> List<&2, U32>:
  match costs after through_m:
    case Con{+c, cs} Con{+a, rest} Con{+cm, ms}:
      Bool.pick(U32, FC.lt(FA.add(cim, cm), c), aim, a) <> relaxed_after(cs, rest, ms, cim, aim)
    case _ _ _:
      Nil{}

def passed_costs(costs: List<&2, List<&2, FR.F64>>, +row_m: List<&2, FR.F64>, +m: U32) -> List<&2, List<&2, FR.F64>>:
  match costs:
    case Nil{}:
      Nil{}
    case Con{+row, rest}:
      relaxed_costs(row, row_m, cost_at(row, m)) <> passed_costs(rest, row_m, m)

def passed_after(costs: List<&2, List<&2, FR.F64>>, after: List<&2, List<&2, U32>>, +row_m: List<&2, FR.F64>, +m: U32) -> List<&2, List<&2, U32>>:
  match costs after:
    case Con{+row, rest} Con{+next_row, more}:
      relaxed_after(row, next_row, row_m, cost_at(row, m), next_in(next_row, m)) <> passed_after(rest, more, row_m, m)
    case _ _:
      Nil{}

type Rows is Data:
  Rows{costs: List<&2, List<&2, FR.F64>>, after: List<&2, List<&2, U32>>}

def floyd_pass(rows: Rows, +m: U32) -> Rows:
  match rows:
    case Rows{+costs, +after}:
      +row_m = Maybe.default(&2, List<&2, FR.F64>, List.get(&2, List<&2, FR.F64>, costs, U32.to_nat(m)), Nil{})
      Rows{passed_costs(costs, row_m, m), passed_after(costs, after, row_m, m)}

def floyd(n: Nat, +m: U32, rows: Rows) -> Rows:
  match n:
    case 0n:
      rows
    case 1n+p:
      floyd(p, (m + 1 : U32), floyd_pass(rows, m))

def ends_of_rows(+insts: List<&2, WD.Inst>, +links: List<&2, At>, rows: Rows) -> Ends:
  match rows:
    case Rows{costs, after}:
      Ends{insts, costs, after, links}

# The ends and closure of a world's wormhole links (numpy's hop_closure).
def ends_of(links: List<&2, WD.Link>) -> Ends:
  +links_list = links
  +insts = end_list(links_list, Nil{})
  +pairs = link_positions(links_list, insts)
  +count = List.length(&2, WD.Inst, insts)
  ends_of_rows(insts, pairs, floyd(count, 0, Rows{first_rows(pairs, insts, insts, 0), identity_after(count, count)}))

def has_ends(+e: Ends) -> Bool:
  match e:
    case Ends{+insts, _, _, _}:
      Bool.not(List.is_empty(&2, WD.Inst, insts))

def seed_cost(c: MT.Cost) -> FR.F64:
  match c:
    case MT.Straight{+v}:
      v
    case _:
      FR.zero()

# A seed's position (hundredths) and cost (hundredths) in F32, for bounding its cost to a target within 4e-6
# relative: seeds whose lower bound is above the least upper bound cannot be the least (or a tie).
type Pre is Data:
  Pre{x: F32, z: F32, c: F32}

def centi_f32(+k: U32) -> F32:
  Bool.pick(F32, (k >= 2147483648 : U32), FO.sub(0.0, FO.from_u32((0 - k : U32))), FO.from_u32(k))

def pre_of(+inst: WD.Inst, +cost: MT.Cost) -> Pre:
  match inst:
    case WD.Inst{_, _, _, _, +xk, +zk, _}:
      Pre{centi_f32(xk), centi_f32(zk), FO.mul(FO.from_f64(seed_cost(cost)), 100.0)}

def pres_of(seeds: List<&2, MT.Seed>) -> List<&2, Pre>:
  match seeds:
    case Nil{}:
      Nil{}
    case Con{MT.Seed{+inst, +cost}, rest}:
      pre_of(inst, cost) <> pres_of(rest)

def approx_cost(+p: Pre, +tx: F32, +tz: F32) -> F32:
  match p:
    case Pre{+x, +z, +c}:
      +dx = FO.sub(x, tx)
      +dz = FO.sub(z, tz)
      FO.add(c, FO.sqrt(FO.add(FO.mul(dx, dx), FO.mul(dz, dz))))

def upper(+a: F32) -> F32:
  FO.add(FO.mul(a, 1.000004), 0.01)

def lower(+a: F32) -> F32:
  FO.sub(FO.mul(a, 0.999996), 0.01)

def least_upper(pres: List<&2, Pre>, +tx: F32, +tz: F32, +own: U32, +i: U32, +found: Bool, +best: F32) -> Maybe<&2, F32>:
  match pres:
    case Nil{}:
      Bool.pick(Maybe<&2, F32>, found, Some{best}, None{})
    case Con{+p, rest}:
      +u = upper(approx_cost(p, tx, tz))
      +take = Bool.not(U32.is_eq(i, own)) && (Bool.not(found) || F32.is_lt(u, best))
      least_upper(rest, tx, tz, own, (i + 1 : U32), found || take, Bool.pick(F32, take, u, best))

def exact_step(near: Bool, +inst: WD.Inst, +cost: MT.Cost, +target: WD.Inst, +i: U32, +best: MT.Relaxed) -> MT.Relaxed:
  match near best:
    case True{} MT.Relaxed{+best_cost, +best_seed}:
      +value = {MT.Straight{FA.add(seed_cost(cost), distance(inst, target))} : MT.Cost}
      Bool.pick(MT.Relaxed, MT.cost_lt(value, best_cost), MT.Relaxed{value, i}, MT.Relaxed{best_cost, best_seed})
    case False{} other:
      other

def direct_near(seeds: List<&2, MT.Seed>, pres: List<&2, Pre>, +target: WD.Inst, +tx: F32, +tz: F32, +bound: F32, +own: U32, +i: U32, +best: MT.Relaxed) -> MT.Relaxed:
  match seeds pres:
    case Con{MT.Seed{+inst, +cost}, rest} Con{+p, ps}:
      +near = Bool.not(U32.is_eq(i, own)) && F32.is_le(lower(approx_cost(p, tx, tz)), bound)
      direct_near(rest, ps, target, tx, tz, bound, own, (i + 1 : U32), exact_step(near, inst, cost, target, i, best))
    case _ _:
      best

def direct_bounded(bound: Maybe<&2, F32>, +seeds: List<&2, MT.Seed>, +pres: List<&2, Pre>, +target: WD.Inst, +tx: F32, +tz: F32, +own: U32) -> MT.Relaxed:
  match bound:
    case None{}:
      MT.unreached()
    case Some{+b}:
      direct_near(seeds, pres, target, tx, tz, b, own, 0, MT.unreached())

# The least seed cost plus distance to the target (first seed on ties), computing exact doubles only for the seeds
# whose F32 lower bound is under the least F32 upper bound.
def direct_best(+seeds: List<&2, MT.Seed>, +pres: List<&2, Pre>, +target: WD.Inst, +own: U32) -> MT.Relaxed:
  match target:
    case WD.Inst{_, _, _, _, +xk, +zk, _}:
      +tx = centi_f32(xk)
      +tz = centi_f32(zk)
      direct_bounded(least_upper(pres, tx, tz, own, 0, False{}, 0.0), seeds, pres, target, tx, tz, own)

def to_ends(+from: WD.Inst, +cost: FR.F64, ends: List<&2, WD.Inst>) -> List<&2, FR.F64>:
  match ends:
    case Nil{}:
      Nil{}
    case Con{+e, rest}:
      FA.add(cost, distance(from, e)) <> to_ends(from, cost, rest)

def row_plus(+base: FR.F64, row: List<&2, FR.F64>) -> List<&2, FR.F64>:
  match row:
    case Nil{}:
      Nil{}
    case Con{+h, rest}:
      FA.add(base, h) <> row_plus(base, rest)

def least(a: List<&2, FR.F64>, b: List<&2, FR.F64>) -> List<&2, FR.F64>:
  match a b:
    case Con{+x, xs} Con{+y, ys}:
      Bool.pick(FR.F64, FC.lt(y, x), y, x) <> least(xs, ys)
    case Nil{} rest:
      rest
    case rest Nil{}:
      rest

def reach_rows(to: List<&2, FR.F64>, closure: List<&2, List<&2, FR.F64>>, acc: List<&2, FR.F64>) -> List<&2, FR.F64>:
  match to closure:
    case Con{+t, ts} Con{+row, rows}:
      reach_rows(ts, rows, least(acc, row_plus(t, row)))
    case _ _:
      acc

type Top is Data:
  Top{v1: MT.Cost, i1: U32, v2: MT.Cost, i2: U32}

def empty_tops(ends: List<&2, WD.Inst>) -> List<&2, Top>:
  match ends:
    case Nil{}:
      Nil{}
    case Con{_, rest}:
      Top{MT.Unreached{}, 0, MT.Unreached{}, 0} <> empty_tops(rest)

def top_step(+top: Top, +v: FR.F64, +i: U32) -> Top:
  match top:
    case Top{+v1, +i1, +v2, +i2}:
      +value = {MT.Straight{v} : MT.Cost}
      Bool.pick(Top, MT.cost_lt(value, v1), Top{value, i, v1, i1}, Bool.pick(Top, MT.cost_lt(value, v2), Top{v1, i1, value, i}, top))

def tops_step(tops: List<&2, Top>, reach: List<&2, FR.F64>, +i: U32) -> List<&2, Top>:
  match tops reach:
    case Con{+top, more} Con{+v, vs}:
      top_step(top, v, i) <> tops_step(more, vs, i)
    case _ _:
      Nil{}

def seed_tops(seeds: List<&2, MT.Seed>, +e: Ends, +i: U32, tops: List<&2, Top>) -> List<&2, Top>:
  match seeds e:
    case Nil{} _:
      tops
    case Con{MT.Seed{+inst, +cost}, rest} Ends{+insts, +closure, _, _}:
      +to = to_ends(inst, seed_cost(cost), insts)
      seed_tops(rest, e, (i + 1 : U32), tops_step(tops, reach_rows(to, closure, Nil{}), i))

def via_value(+top: Top, +own: U32) -> MT.Relaxed:
  match top:
    case Top{+v1, +i1, +v2, +i2}:
      Bool.pick(MT.Relaxed, U32.is_eq(i1, own), MT.Relaxed{v2, i2}, MT.Relaxed{v1, i1})

def plus_flight(+r: MT.Relaxed, +from: WD.Inst, +target: WD.Inst) -> MT.Relaxed:
  match r:
    case MT.Relaxed{MT.Straight{+v}, +seed}:
      MT.Relaxed{MT.Straight{FA.add(v, distance(from, target))}, seed}
    case _:
      MT.unreached()

def relaxed_cost(+r: MT.Relaxed) -> MT.Cost:
  match r:
    case MT.Relaxed{+cost, _}:
      cost

def via_best(tops: List<&2, Top>, ends: List<&2, WD.Inst>, +target: WD.Inst, +own: U32, +best: MT.Relaxed) -> MT.Relaxed:
  match tops ends:
    case Con{+top, more} Con{+e, es}:
      +candidate = plus_flight(via_value(top, own), e, target)
      via_best(more, es, target, own, Bool.pick(MT.Relaxed, MT.cost_lt(relaxed_cost(candidate), relaxed_cost(best)), candidate, best))
    case _ _:
      best

def ends_insts(+e: Ends) -> List<&2, WD.Inst>:
  match e:
    case Ends{+insts, _, _, _}:
      insts

def target_best(+use_ends: Bool, +e: Ends, +tops: List<&2, Top>, +seeds: List<&2, MT.Seed>, +pres: List<&2, Pre>, +exclude_self: Bool, +target: WD.Inst) -> MT.Relaxed:
  +own = MT.own_seed(exclude_self, seeds, target)
  +direct = direct_best(seeds, pres, target, own)
  +via = Bool.pick(MT.Relaxed, use_ends, via_best(tops, ends_insts(e), target, own, MT.unreached()), MT.unreached())
  Bool.pick(MT.Relaxed, MT.cost_lt(relaxed_cost(via), relaxed_cost(direct)), via, direct)

def targets_best(targets: List<&2, WD.Inst>, +use_ends: Bool, +e: Ends, +tops: List<&2, Top>, +seeds: List<&2, MT.Seed>, +pres: List<&2, Pre>, +exclude_self: Bool) -> List<&2, MT.Relaxed>:
  match targets:
    case Nil{}:
      Nil{}
    case Con{+target, rest}:
      target_best(use_ends, e, tops, seeds, pres, exclude_self, target) <> targets_best(rest, use_ends, e, tops, seeds, pres, exclude_self)

# For every target, the least seed cost plus distance over the seeds (metric.py StraightMetric.relax).
def relax(+e: Ends, +seeds: List<&2, MT.Seed>, targets: List<&2, WD.Inst>, +exclude_self: Bool) -> List<&2, MT.Relaxed>:
  +use_ends = has_ends(e) && Bool.not(List.is_empty(&2, MT.Seed, seeds))
  +tops = Bool.pick(List<&2, Top>, use_ends, seed_tops(seeds, e, 0, empty_tops(ends_insts(e))), Nil{})
  targets_best(targets, use_ends, e, tops, seeds, pres_of(seeds), exclude_self)

def hop_at(+e: Ends, +u: U32, +v: U32) -> MT.Hop:
  match e:
    case Ends{+insts, _, _, _}:
      +none = {WD.Inst{0, 0, FR.zero(), FR.zero(), 0, 0, 0} : WD.Inst}
      MT.Hop{Maybe.default(&2, WD.Inst, List.get(&2, WD.Inst, insts, U32.to_nat(u)), none), Maybe.default(&2, WD.Inst, List.get(&2, WD.Inst, insts, U32.to_nat(v)), none)}

def hop_path(n: Nat, +e: Ends, +current: U32, +leave: U32) -> List<&2, MT.Hop>:
  match n e:
    case 0n _:
      Nil{}
    case 1n+p Ends{_, _, +next, +links}:
      +step = next_in(Maybe.default(&2, List<&2, U32>, List.get(&2, List<&2, U32>, next, U32.to_nat(current)), Nil{}), leave)
      +rest = Bool.pick(List<&2, MT.Hop>, U32.is_eq(current, leave), Nil{}, hop_path(p, e, step, leave))
      Bool.pick(List<&2, MT.Hop>, Bool.not(U32.is_eq(current, leave)) && is_link(links, current, step), hop_at(e, current, step) <> rest, rest)

type Best is Data:
  Best{value: FR.F64, entry: U32, leave: U32, via: Bool}

def leave_best(ends: List<&2, WD.Inst>, row: List<&2, FR.F64>, +b: WD.Inst, +to_entry: FR.F64, +entry: U32, +leave: U32, best: Best) -> Best:
  match ends row best:
    case Con{+l, ls} Con{+h, hs} Best{+value, +be, +bl, +via}:
      +total = FA.add(FA.add(to_entry, h), distance(l, b))
      leave_best(ls, hs, b, to_entry, entry, (leave + 1 : U32), Bool.pick(Best, FC.lt(total, value), Best{total, entry, leave, True{}}, Best{value, be, bl, via}))
    case _ _ other:
      other

def entry_best(ends: List<&2, WD.Inst>, closure: List<&2, List<&2, FR.F64>>, +all: List<&2, WD.Inst>, +a: WD.Inst, +b: WD.Inst, +entry: U32, best: Best) -> Best:
  match ends closure:
    case Con{+e, es} Con{+row, rows}:
      entry_best(es, rows, all, a, b, (entry + 1 : U32), leave_best(all, row, b, distance(a, e), entry, 0, best))
    case _ _:
      best

def leg_of(+e: Ends, best: Best) -> MT.Leg:
  match best:
    case Best{+value, +entry, +leave, +via}:
      MT.Leg{MT.Straight{value}, Bool.pick(List<&2, MT.Hop>, via, hop_path(32n, e, entry, leave), Nil{})}

# d(a, b) and the jumps of one shortest path (metric.py StraightMetric.leg).
def leg(+e: Ends, +a: WD.Inst, +b: WD.Inst) -> MT.Leg:
  match e:
    case Ends{+insts, +closure, _, _}:
      leg_of(e, entry_best(insts, closure, insts, a, b, 0, Best{distance(a, b), 0, 0, False{}}))
