import Base
import ../rng/pcg.bend as Pcg
import ../level/summary.bend as LevelSummary
import ../storygen/graph.bend as StoryGraph
import ../storygen/plan.bend as StoryPlan
import ../populate/state.bend as PopulateState
import ../populate/planned.bend as PopulatePlanned
import ../filters/dump.bend as FilterDump
import ../filters/world.bend as FilterWorld
import ../filters/checks.bend as Checks
import ../filters/rules.bend as Rules
import ../filters/level_checks.bend as LevelChecks

# Ensure placed laws: the level plan's placement (populate/planned.bend) and the setpieces rules' `placed` names.
# A synthetic attempt: the level plans one MooseNest (piece key 3, string id 140, layout 60) in task 0 "Make a pick"
# (the first chosen task when no optional task is drawn); in a fresh story memory every node is in graph 0, whose task
# is 0.

def plan() -> StoryPlan.Plan:
  StoryPlan.ForestPlan{LevelSummary.Summary{0, 0, [67], 0, 0, 0, False{}}}

def story() -> StoryGraph.St:
  StoryGraph.place_piece(StoryGraph.fresh(Pcg.Rng{0, 0}), 0, 140, 60)

def reserved(+ok: Bool) -> List<&2, PopulateState.Ev>:
  [PopulateState.EReserve{0, 0, 0, 0, 0, 0, Pcg.Rng{0, 0}, Pcg.Rng{0, 0}, ok, 0, 0}, PopulateState.ELayout{0, 140, Pcg.Rng{0, 0}}]

# The story put the piece in node 0, whose ReserveSpace found no spot: planned once, not placed.
law failed_reservation_not_placed:
  {PopulatePlanned.planned(plan(), story(), reserved(False{})) == [PopulatePlanned.Planned{0, 140, False{}}] : List<&2, PopulatePlanned.Planned>}

def failed_reservation_not_placed():
  {==}

law found_reservation_placed:
  {PopulatePlanned.planned(plan(), story(), reserved(True{})) == [PopulatePlanned.Planned{0, 140, True{}}] : List<&2, PopulatePlanned.Planned>}

def found_reservation_placed():
  {==}

# The story found no node for the piece: a layout of that name the land placed elsewhere does not count.
law dropped_piece_not_placed:
  {PopulatePlanned.planned(plan(), StoryGraph.fresh(Pcg.Rng{0, 0}), reserved(True{})) == [PopulatePlanned.Planned{0, 140, False{}}] : List<&2, PopulatePlanned.Planned>}

def dropped_piece_not_placed():
  {==}

def world(+placed: Bool) -> FilterWorld.World:
  FilterWorld.World{1, 2, 2, Nil{}, Nil{}, Nil{}, Nil{}, None{}, Some{[FilterDump.Planned{"Make a pick", "MooseNest", placed}]}}

def moose_rule(+tasks: List<&2, String>) -> Rules.Placed:
  Rules.Placed{0, tasks, [LevelChecks.Bounded{"MooseNest", 1, None{}}]}

# `MooseNest >= 1` with `placed`: the witness counts the planned and the placed copies.
law placed_rule_fails_on_dropped_copy:
  {Checks.placed(world(False{}), moose_rule([])) == Checks.Check{False{}, ",\"pieces\":[{\"name\":\"MooseNest\",\"planned\":1,\"placed\":0}]"} : Checks.Check}

def placed_rule_fails_on_dropped_copy():
  {==}

law placed_rule_holds_on_placed_copy:
  {Checks.placed(world(True{}), moose_rule(["Make a pick"])) == Checks.Check{True{}, ",\"pieces\":[{\"name\":\"MooseNest\",\"planned\":1,\"placed\":1}]"} : Checks.Check}

def placed_rule_holds_on_placed_copy():
  {==}

# A copy outside the rule's tasks counts neither as planned nor as placed.
law placed_rule_scoped_to_tasks:
  {Checks.placed(world(True{}), moose_rule(["Magic meadow"])) == Checks.Check{False{}, ",\"pieces\":[{\"name\":\"MooseNest\",\"planned\":0,\"placed\":0}]"} : Checks.Check}

def placed_rule_scoped_to_tasks():
  {==}

def placed_member() -> Rules.Member:
  Rules.Member{LevelChecks.Pieces{[], []}, [LevelChecks.Bounded{"MooseNest", 1, None{}}]}

def level_member() -> Rules.Member:
  Rules.Member{LevelChecks.Pieces{[], [LevelChecks.Bounded{"MooseNest", 0, None{}}]}, []}

# A group holds when one of its rules holds on the level table (of the world's seed) and on the placed copies.
law group_fails_on_dropped_copy:
  {Checks.placed(world(False{}), Rules.AnyPlaced{0, [placed_member()], None{}}) == Checks.Check{False{}, ",\"any\":[{\"ok\":false,\"counts\":{},\"pieces\":[{\"name\":\"MooseNest\",\"planned\":1,\"placed\":0}]}]"} : Checks.Check}

def group_fails_on_dropped_copy():
  {==}

law group_holds_on_placed_copy:
  {Checks.placed(world(True{}), Rules.AnyPlaced{0, [placed_member()], None{}}) == Checks.Check{True{}, ",\"any\":[{\"ok\":true,\"counts\":{},\"pieces\":[{\"name\":\"MooseNest\",\"planned\":1,\"placed\":1}]}]"} : Checks.Check}

def group_holds_on_placed_copy():
  {==}

def holds(+c: Checks.Check) -> Bool:
  match c:
    case Checks.Check{+ok, _}:
      ok

law group_holds_on_other_rule:
  {holds(Checks.placed(world(False{}), Rules.AnyPlaced{0, [placed_member(), level_member()], None{}})) == True{} : Bool}

def group_holds_on_other_rule():
  {==}

def total_rule() -> Rules.Placed:
  +moose : LevelChecks.Bounded = LevelChecks.Bounded{"MooseNest", 0, None{}}
  Rules.AnyPlaced{0, [Rules.Member{LevelChecks.Pieces{[], [moose]}, [moose]}, Rules.Member{LevelChecks.Pieces{[], [LevelChecks.Bounded{"CookingBoon", 0, None{}}]}, []}], Some{LevelChecks.Total{2, None{}}}}

# A group's total counts the placed copies of its `placed` names and the planned ones of the others: seed 1 plans
# CookingBoon once, and MooseNest 7 times, of which the world's plan holds the one copy.
law group_total_counts_placed_copies:
  {(Checks.placed(world(True{}), total_rule()), holds(Checks.placed(world(False{}), total_rule()))) == (Checks.Check{True{}, ",\"any\":[{\"ok\":true,\"counts\":{\"MooseNest\":7},\"pieces\":[{\"name\":\"MooseNest\",\"planned\":1,\"placed\":1}]},{\"ok\":true,\"counts\":{\"CookingBoon\":1},\"pieces\":[]}],\"total\":2"}, False{}) : Checks.Check & Bool}

def group_total_counts_placed_copies():
  {==}
