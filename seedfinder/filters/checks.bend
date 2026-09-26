import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ./world.bend as FilterWorld
import ./anchor.bend as Anchor
import ./metric.bend as Metric
import ./relax.bend as Relax
import ./rules.bend as Rules
import ./routes.bend as Routes
import ./tiles.bend as FilterTiles
import ./witness.bend as Witness

# The checks of parts B-E (criteria.py check_count, check_distance, check_tiles, check_route): whether a rule holds
# and its witness fields, as evaluate.py --json prints them after "ok".
type Check is Data:
  Check{ok: Bool, fields: String}

def cost_text(+c: Metric.Cost) -> String:
  match c:
    case Metric.Straight{+d}:
      Witness.double_text(d)
    case Metric.Walk{+l}:
      Witness.length_text(l)
    case Metric.Unreached{}:
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

def point_inst(+p: Anchor.Point) -> FilterWorld.Inst:
  match p:
    case Anchor.Point{+inst, _}:
      inst

def point_at(+points: List<&2, Anchor.Point>, +i: U32) -> Anchor.Point:
  Maybe.default(&2, Anchor.Point, List.get(&2, Anchor.Point, points, U32.to_nat(i)), Anchor.Point{Metric.none_inst(), None{}})

def json_list(+items: List<&2, String>) -> String:
  "[" ++ String.join(items, ",") ++ "]"

def hop_items(hops: List<&2, Metric.Hop>) -> List<&2, String>:
  match hops:
    case Nil{}:
      Nil{}
    case Con{Metric.Hop{+entry, +exit}, rest}:
      ("{\"entry\":" ++ Witness.instance(entry) ++ ",\"exit\":" ++ Witness.instance(exit) ++ "}") <> hop_items(rest)

def hops_json(hops: List<&2, Metric.Hop>) -> String:
  json_list(hop_items(hops))

def counted_items(targets: List<&2, Anchor.Point>, relaxed: List<&2, Metric.Relaxed>, +anchors: List<&2, Anchor.Point>, +within: F64Repr.F64, +acc: List<&2, String>) -> List<&2, String>:
  match targets relaxed:
    case Con{+t, ts} Con{Metric.Relaxed{+cost, +seed}, rs}:
      +item = "{" ++ Witness.instance_fields(point_inst(t)) ++ ",\"near\":" ++ Witness.instance(point_inst(point_at(anchors, seed))) ++ ",\"distance\":" ++ cost_text(cost) ++ "}"
      counted_items(ts, rs, anchors, within, Bool.pick(List<&2, String>, Metric.is_reached(cost) && Metric.within_max(cost, Some{within}), item <> acc, acc))
    case _ _:
      List.reverse(&2, String, acc)

def length_u32(+items: List<&2, String>) -> U32:
  U32.from_nat(List.length(&2, String, items))

def count_near(+world: FilterWorld.World, +insts: List<&2, FilterWorld.Inst>, near: Rules.Near, +min: Maybe<&2, U32>, +max: Maybe<&2, U32>) -> Check:
  match near:
    case Rules.Near{+prefabs, +within, +metric}:
      +s = Relax.space(world, metric)
      +anchors = Relax.points(s, FilterWorld.instances(world, prefabs))
      +targets = Relax.points(s, insts)
      +items = counted_items(targets, Relax.relax(s, Relax.zero_sources(s, anchors), targets, True{}), anchors, within, Nil{})
      +n = length_u32(items)
      Check{at_least(n, min) && at_most(n, max), ",\"count\":" ++ U32.show(n) ++ ",\"total\":" ++ U32.show(U32.from_nat(List.length(&2, FilterWorld.Inst, insts)))
        ++ ",\"instances\":" ++ json_list(items)}

def count_with(near: Maybe<&2, Rules.Near>, +world: FilterWorld.World, +insts: List<&2, FilterWorld.Inst>, +min: Maybe<&2, U32>, +max: Maybe<&2, U32>) -> Check:
  match near:
    case None{}:
      +n = U32.from_nat(List.length(&2, FilterWorld.Inst, insts))
      Check{at_least(n, min) && at_most(n, max), ",\"count\":" ++ U32.show(n)}
    case Some{rule}:
      count_near(world, insts, rule, min, max)

# criteria.py check_count.
def count(+world: FilterWorld.World, rule: Rules.Count) -> Check:
  match rule:
    case Rules.Count{+prefabs, +min, +max, near}:
      count_with(near, world, FilterWorld.instances(world, prefabs), min, max)

def distance_leg(leg: Metric.Leg, +cost: Metric.Cost, +source: Anchor.Point, +goal: Anchor.Point, +min: Maybe<&2, F64Repr.F64>, +max: Maybe<&2, F64Repr.F64>) -> Check:
  match leg:
    case Metric.Leg{_, hops}:
      Check{Metric.within(cost, min, max), ",\"distance\":" ++ cost_text(cost) ++ ",\"from\":" ++ Witness.instance(point_inst(source)) ++ ",\"to\":"
        ++ Witness.instance(point_inst(goal)) ++ ",\"wormholes\":" ++ hops_json(hops)}

def distance_found(reached: Bool, +s: Relax.Space, +best: Routes.Best, +sources: List<&2, Anchor.Point>, +targets: List<&2, Anchor.Point>, +min: Maybe<&2, F64Repr.F64>, +max: Maybe<&2, F64Repr.F64>) -> Check:
  match reached best:
    case True{} Routes.Best{+cost, +seed, +target}:
      distance_leg(Relax.leg(s, point_at(sources, seed), point_at(targets, target)), cost, point_at(sources, seed), point_at(targets, target), min, max)
    case False{} _:
      Check{Metric.within(Metric.Unreached{}, min, max), ",\"distance\":null"}

def best_cost(+b: Routes.Best) -> Metric.Cost:
  match b:
    case Routes.Best{+cost, _, _}:
      cost

def distance_best(+s: Relax.Space, +best: Routes.Best, +sources: List<&2, Anchor.Point>, +targets: List<&2, Anchor.Point>, +min: Maybe<&2, F64Repr.F64>, +max: Maybe<&2, F64Repr.F64>) -> Check:
  distance_found(Metric.is_reached(best_cost(best)), s, best, sources, targets, min, max)

# criteria.py check_distance.
def distance(+world: FilterWorld.World, rule: Rules.Distance) -> Check:
  match rule:
    case Rules.Distance{+from, +to, +min, +max, +metric}:
      +s = Relax.space(world, metric)
      +sources = Relax.points(s, FilterWorld.instances(world, from))
      +targets = Relax.points(s, FilterWorld.instances(world, to))
      distance_best(s, Routes.argmin(Relax.relax(s, Relax.zero_sources(s, sources), targets, True{})), sources, targets, min, max)

def world_size(+world: FilterWorld.World) -> U32:
  match world:
    case FilterWorld.World{_, +w, _, _, _, _, _}:
      w

def world_height(+world: FilterWorld.World) -> U32:
  match world:
    case FilterWorld.World{_, _, +h, _, _, _, _}:
      h

def tiles_found(found: Maybe<&2, FilterTiles.Found>, +world: FilterWorld.World, +max: U32) -> Check:
  match found:
    case None{}:
      Check{False{}, ",\"distance\":null"}
    case Some{FilterTiles.Found{+steps, +origin, +goal}}:
      Check{(steps <= max : U32), ",\"distance\":" ++ U32.show(steps) ++ ",\"from_tile\":" ++ Witness.tile(origin, world_size(world), world_height(world))
        ++ ",\"to_tile\":" ++ Witness.tile(goal, world_size(world), world_height(world))}

# criteria.py check_tiles.
def tiles(+world: FilterWorld.World, rule: Rules.Tiles) -> Check:
  match rule:
    case Rules.Tiles{+from, +to, +max}:
      tiles_found(FilterTiles.nearest(world, from, to), world, max)

def stop_points(+s: Relax.Space, +world: FilterWorld.World, visit: List<&2, List<&2, U32>>) -> List<&2, List<&2, Anchor.Point>>:
  match visit:
    case Nil{}:
      Nil{}
    case Con{+ids, rest}:
      Relax.points(s, FilterWorld.instances(world, ids)) <> stop_points(s, world, rest)

def end_points(+s: Relax.Space, +world: FilterWorld.World, to: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, Anchor.Point>>:
  match to:
    case None{}:
      None{}
    case Some{+ids}:
      Some{Relax.points(s, FilterWorld.instances(world, ids))}

def leg_item(leg: Metric.Leg, +a: Anchor.Point, +b: Anchor.Point) -> String:
  match leg:
    case Metric.Leg{+cost, hops}:
      "{\"from\":" ++ Witness.instance(point_inst(a)) ++ ",\"to\":" ++ Witness.instance(point_inst(b)) ++ ",\"distance\":" ++ cost_text(cost)
        ++ ",\"wormholes\":" ++ hops_json(hops) ++ "}"

def leg_items(+s: Relax.Space, path: List<&2, Anchor.Point>) -> List<&2, String>:
  match path:
    case Con{+a, Con{+b, rest}}:
      leg_item(Relax.leg(s, a, b), a, b) <> leg_items(s, Con{b, rest})
    case _:
      Nil{}

def stop_items(path: List<&2, Anchor.Point>) -> List<&2, String>:
  match path:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      Witness.instance(point_inst(p)) <> stop_items(rest)

def route_found(last: Maybe<&2, Routes.Path>, +s: Relax.Space, +max: F64Repr.F64) -> Check:
  match last:
    case None{}:
      Check{False{}, ",\"length\":null"}
    case Some{+p}:
      +path = Routes.unwind(p)
      Check{Metric.within_max(Routes.path_cost(p), Some{max}), ",\"length\":" ++ cost_text(Routes.path_cost(p)) ++ ",\"stops\":" ++ json_list(stop_items(path))
        ++ ",\"legs\":" ++ json_list(leg_items(s, path))}

# criteria.py check_route.
def route(+world: FilterWorld.World, rule: Rules.Route) -> Check:
  match rule:
    case Rules.Route{+from, +visit, +to, +max, +fixed, +metric}:
      +s = Relax.space(world, metric)
      route_found(Routes.shortest(s, Relax.points(s, FilterWorld.instances(world, from)), stop_points(s, world, visit), end_points(s, world, to), fixed), s, max)
