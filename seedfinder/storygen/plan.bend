import Base
import ../data/cave_catalog.bend as CaveCatalog
import ../data/tasks.bend as Tasks
import ../level/summary.bend as LevelSummary
import ../level/cave_choose.bend as CaveChoose
import ../level/cave_prefix.bend as CavePrefix
import ./catalog.bend as StoryCatalog

# What storygen takes from the level table of a seed. The forest's is its level summary (regions included). The caves
# have no regions and no random set pieces: their plan is the chosen tasks in ChooseTasks order (story task ids), the
# set pieces the level placed (key and task masks, in pairs() order) and the index (1-based, 0 while unresolved) of the
# entrance room GetRandomItem took for the task whose entrance_room is a list. The game overwrites that task field the
# first time it draws, so the pick lasts for the remaining attempts of the seed.
type Plan is Data:
  ForestPlan{level: LevelSummary.Summary}
  CavePlan{tasks: List<&2, U32>, placed: List<&2, CaveChoose.Placed>, entrance: U32}

def story_ids(tasks: List<&2, U32>) -> List<&2, U32>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+task, rest}:
      StoryCatalog.caves_task_id(task) <> story_ids(rest)

def caves(+world: CaveChoose.World, +entrance: U32) -> Plan:
  match world:
    case CaveChoose.World{_, +picks, +placed, _}:
      CavePlan{story_ids(CavePrefix.chosen_ids(picks)), placed, entrance}

def is_caves(+plan: Plan) -> Bool:
  match plan:
    case ForestPlan{_}:
      False{}
    case CavePlan{_, _, _}:
      True{}

def entrance_of(+plan: Plan) -> U32:
  match plan:
    case ForestPlan{_}:
      0
    case CavePlan{_, _, +entrance}:
      entrance

def with_entrance(+plan: Plan, +entrance: U32) -> Plan:
  match plan:
    case ForestPlan{+level}:
      ForestPlan{level}
    case CavePlan{+tasks, +placed, _}:
      CavePlan{tasks, placed, entrance}

def bg_min(+plan: Plan) -> U32:
  match plan:
    case ForestPlan{_}:
      0
    case CavePlan{_, _, _}:
      CaveCatalog.background_node_min()

def bg_max(+plan: Plan) -> U32:
  match plan:
    case ForestPlan{_}:
      2
    case CavePlan{_, _, _}:
      CaveCatalog.background_node_max()

# Story:GenerateNodesForRegion's layout mode for the mainland: the location's layout_mode.
def restricted(+plan: Plan) -> Bool:
  is_caves(plan)

def cave_piece_names(placed: List<&2, CaveChoose.Placed>, +task: U32) -> List<&2, U32>:
  match placed:
    case Nil{}:
      Nil{}
    case Con{CaveChoose.Placed{+key, +lo, +hi}, rest}:
      +tail = cave_piece_names(rest, task)
      Bool.pick(List<&2, U32>, CavePrefix.is_chosen(lo, hi, StoryCatalog.cave_task(task)), key <> tail, tail)

def caves_valid_starts(n: Nat, +k: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      StoryCatalog.caves_task_id(CaveCatalog.valid_start_task(k)) <> caves_valid_starts(p, (k + 1 : U32))

# level.valid_start_tasks as story task ids.
def valid_start_tasks(+plan: Plan) -> List<&2, U32>:
  match plan:
    case ForestPlan{_}:
      Tasks.lists(2)
    case CavePlan{_, _, _}:
      caves_valid_starts(U32.to_nat(CaveCatalog.valid_start_task_count()), 0)
