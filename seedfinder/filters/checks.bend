import Base
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ./world.bend as WD
import ./anchor.bend as AN
import ./metric.bend as MT
import ./relax.bend as RX
import ./rules.bend as RU
import ./routes.bend as RO
import ./tiles.bend as TL
import ./witness.bend as WT

# The checks of parts B-E (criteria.py check_count, check_distance, check_tiles, check_route): whether a rule holds
# and its witness fields, as evaluate.py --json prints them after "ok".
type Check is Data:
  Check{ok: Bool, fields: String}

def cost_text(+c: MT.Cost) -> String:
  match c:
    case MT.Straight{+d}:
      WT.double_text(d)
    case MT.Walk{+l}:
      WT.length_text(l)
    case MT.Unreached{}:
      "null"

def at_least(+n: U32, m: Maybe<&2, U32>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{+low}:
      (n >= low : U32)

def at_most(+n: U32, m: Maybe<&2, U32>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{+high}:
      (n <= high : U32)

def point_inst(+p: AN.Point) -> WD.Inst:
  match p:
    case AN.Point{+inst, _}:
      inst

def point_at(+points: List<&2, AN.Point>, +i: U32) -> AN.Point:
  Maybe.default(&2, AN.Point, List.get(&2, AN.Point, points, U32.to_nat(i)), AN.Point{MT.none_inst(), None{}})

def json_list(+items: List<&2, String>) -> String:
  "[" ++ String.join(items, ",") ++ "]"

def hop_items(hops: List<&2, MT.Hop>) -> List<&2, String>:
  match hops:
    case Nil{}:
      Nil{}
    case Con{MT.Hop{+entry, +exit}, rest}:
      ("{\"entry\":" ++ WT.instance(entry) ++ ",\"exit\":" ++ WT.instance(exit) ++ "}") <> hop_items(rest)

def hops_json(hops: List<&2, MT.Hop>) -> String:
  json_list(hop_items(hops))

def counted_items(targets: List<&2, AN.Point>, relaxed: List<&2, MT.Relaxed>, +anchors: List<&2, AN.Point>, +within: FR.F64, +acc: List<&2, String>) -> List<&2, String>:
  match targets relaxed:
    case Con{+t, ts} Con{MT.Relaxed{+cost, +seed}, rs}:
      +item = "{" ++ WT.instance_fields(point_inst(t)) ++ ",\"near\":" ++ WT.instance(point_inst(point_at(anchors, seed))) ++ ",\"distance\":" ++ cost_text(cost) ++ "}"
      counted_items(ts, rs, anchors, within, Bool.pick(List<&2, String>, MT.is_reached(cost) && MT.within_max(cost, Some{within}), item <> acc, acc))
    case _ _:
      List.reverse(&2, String, acc)

def length_u32(+items: List<&2, String>) -> U32:
  U32.from_nat(List.length(&2, String, items))

def count_near(+world: WD.World, +insts: List<&2, WD.Inst>, near: RU.Near, +min: Maybe<&2, U32>, +max: Maybe<&2, U32>) -> Check:
  match near:
    case RU.Near{+prefabs, +within, +metric}:
      +s = RX.space(world, metric)
      +anchors = RX.points(s, WD.instances(world, prefabs))
      +targets = RX.points(s, insts)
      +items = counted_items(targets, RX.relax(s, RX.zero_sources(s, anchors), targets, True{}), anchors, within, Nil{})
      +n = length_u32(items)
      Check{at_least(n, min) && at_most(n, max), ",\"count\":" ++ U32.show(n) ++ ",\"total\":" ++ U32.show(U32.from_nat(List.length(&2, WD.Inst, insts)))
        ++ ",\"instances\":" ++ json_list(items)}

def count_with(near: Maybe<&2, RU.Near>, +world: WD.World, +insts: List<&2, WD.Inst>, +min: Maybe<&2, U32>, +max: Maybe<&2, U32>) -> Check:
  match near:
    case None{}:
      +n = U32.from_nat(List.length(&2, WD.Inst, insts))
      Check{at_least(n, min) && at_most(n, max), ",\"count\":" ++ U32.show(n)}
    case Some{rule}:
      count_near(world, insts, rule, min, max)

# criteria.py check_count.
def count(+world: WD.World, rule: RU.Count) -> Check:
  match rule:
    case RU.Count{+prefabs, +min, +max, near}:
      count_with(near, world, WD.instances(world, prefabs), min, max)

def distance_leg(leg: MT.Leg, +cost: MT.Cost, +source: AN.Point, +goal: AN.Point, +min: Maybe<&2, FR.F64>, +max: Maybe<&2, FR.F64>) -> Check:
  match leg:
    case MT.Leg{_, hops}:
      Check{MT.within(cost, min, max), ",\"distance\":" ++ cost_text(cost) ++ ",\"from\":" ++ WT.instance(point_inst(source)) ++ ",\"to\":"
        ++ WT.instance(point_inst(goal)) ++ ",\"wormholes\":" ++ hops_json(hops)}

def distance_found(reached: Bool, +s: RX.Space, +best: RO.Best, +sources: List<&2, AN.Point>, +targets: List<&2, AN.Point>, +min: Maybe<&2, FR.F64>, +max: Maybe<&2, FR.F64>) -> Check:
  match reached best:
    case True{} RO.Best{+cost, +seed, +target}:
      distance_leg(RX.leg(s, point_at(sources, seed), point_at(targets, target)), cost, point_at(sources, seed), point_at(targets, target), min, max)
    case False{} _:
      Check{MT.within(MT.Unreached{}, min, max), ",\"distance\":null"}

def best_cost(+b: RO.Best) -> MT.Cost:
  match b:
    case RO.Best{+cost, _, _}:
      cost

def distance_best(+s: RX.Space, +best: RO.Best, +sources: List<&2, AN.Point>, +targets: List<&2, AN.Point>, +min: Maybe<&2, FR.F64>, +max: Maybe<&2, FR.F64>) -> Check:
  distance_found(MT.is_reached(best_cost(best)), s, best, sources, targets, min, max)

# criteria.py check_distance.
def distance(+world: WD.World, rule: RU.Distance) -> Check:
  match rule:
    case RU.Distance{+from, +to, +min, +max, +metric}:
      +s = RX.space(world, metric)
      +sources = RX.points(s, WD.instances(world, from))
      +targets = RX.points(s, WD.instances(world, to))
      distance_best(s, RO.argmin(RX.relax(s, RX.zero_sources(s, sources), targets, True{})), sources, targets, min, max)

def world_size(+world: WD.World) -> U32:
  match world:
    case WD.World{_, +w, _, _, _, _, _}:
      w

def world_height(+world: WD.World) -> U32:
  match world:
    case WD.World{_, _, +h, _, _, _, _}:
      h

def tiles_found(found: Maybe<&2, TL.Found>, +world: WD.World, +max: U32) -> Check:
  match found:
    case None{}:
      Check{False{}, ",\"distance\":null"}
    case Some{TL.Found{+steps, +origin, +goal}}:
      Check{(steps <= max : U32), ",\"distance\":" ++ U32.show(steps) ++ ",\"from_tile\":" ++ WT.tile(origin, world_size(world), world_height(world))
        ++ ",\"to_tile\":" ++ WT.tile(goal, world_size(world), world_height(world))}

# criteria.py check_tiles.
def tiles(+world: WD.World, rule: RU.Tiles) -> Check:
  match rule:
    case RU.Tiles{+from, +to, +max}:
      tiles_found(TL.nearest(world, from, to), world, max)

def stop_points(+s: RX.Space, +world: WD.World, visit: List<&2, List<&2, U32>>) -> List<&2, List<&2, AN.Point>>:
  match visit:
    case Nil{}:
      Nil{}
    case Con{+ids, rest}:
      RX.points(s, WD.instances(world, ids)) <> stop_points(s, world, rest)

def end_points(+s: RX.Space, +world: WD.World, to: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, AN.Point>>:
  match to:
    case None{}:
      None{}
    case Some{+ids}:
      Some{RX.points(s, WD.instances(world, ids))}

def leg_item(leg: MT.Leg, +a: AN.Point, +b: AN.Point) -> String:
  match leg:
    case MT.Leg{+cost, hops}:
      "{\"from\":" ++ WT.instance(point_inst(a)) ++ ",\"to\":" ++ WT.instance(point_inst(b)) ++ ",\"distance\":" ++ cost_text(cost)
        ++ ",\"wormholes\":" ++ hops_json(hops) ++ "}"

def leg_items(+s: RX.Space, path: List<&2, AN.Point>) -> List<&2, String>:
  match path:
    case Con{+a, Con{+b, rest}}:
      leg_item(RX.leg(s, a, b), a, b) <> leg_items(s, Con{b, rest})
    case _:
      Nil{}

def stop_items(path: List<&2, AN.Point>) -> List<&2, String>:
  match path:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      WT.instance(point_inst(p)) <> stop_items(rest)

def route_found(last: Maybe<&2, RO.Path>, +s: RX.Space, +max: FR.F64) -> Check:
  match last:
    case None{}:
      Check{False{}, ",\"length\":null"}
    case Some{+p}:
      +path = RO.unwind(p)
      Check{MT.within_max(RO.path_cost(p), Some{max}), ",\"length\":" ++ cost_text(RO.path_cost(p)) ++ ",\"stops\":" ++ json_list(stop_items(path))
        ++ ",\"legs\":" ++ json_list(leg_items(s, path))}

# criteria.py check_route.
def route(+world: WD.World, rule: RU.Route) -> Check:
  match rule:
    case RU.Route{+from, +visit, +to, +max, +fixed, +metric}:
      +s = RX.space(world, metric)
      route_found(RO.shortest(s, RX.points(s, WD.instances(world, from)), stop_points(s, world, visit), end_points(s, world, to), fixed), s, max)
