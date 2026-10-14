import Base
import ./json.bend as Json
import ./evaluate.bend as Evaluate
import ./level_checks.bend as LevelChecks
import ./parse.bend as Parse
import ../data/cave_catalog.bend as CaveCatalog
import ../level/cave_prefix.bend as CavePrefix
import ../level/cave_choose.bend as CaveChoose
import ../data/builds.bend as Builds

# Part A of an entry on the caves level table of a seed, as the witnesses of docs/config.md section 8.

def piece_names(+build: Builds.Build, placed: List<&2, CaveChoose.Placed>, +task: U32) -> List<&2, String>:
  match placed:
    case Nil{}:
      Nil{}
    case Con{CaveChoose.Placed{+key, +lo, +hi}, rest}:
      +tail = piece_names(build, rest, task)
      Bool.pick(List<&2, String>, CavePrefix.is_chosen(lo, hi, task), CaveCatalog.key_name(build, key) <> tail, tail)

def placed_tasks(+build: Builds.Build, tasks: List<&2, U32>, +placed: List<&2, CaveChoose.Placed>) -> List<&2, LevelChecks.Placed>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+task, rest}:
      LevelChecks.Placed{CaveCatalog.task_name(build, task), piece_names(build, placed, task)} <> placed_tasks(build, rest, placed)

def swap_actual(+build: Builds.Build, n: Nat, +swaps: U32, +category: String, +k: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      Bool.pick(String, String.eq(CaveCatalog.swap_category(build, k), category),
        Bool.pick(String, U32.is_zero(((swaps >> U32.to_nat(k)) .&. 1 : U32)), CaveCatalog.swap_regular(build, k), CaveCatalog.swap_swapped(build, k)),
        swap_actual(build, p, swaps, category, (k + 1 : U32)))

def actual_of(+build: Builds.Build, +swaps: U32, +category: String) -> String:
  swap_actual(build, U32.to_nat(CaveCatalog.swap_count(build)), swaps, category, 0)

def swap_items(+build: Builds.Build, swaps: List<&2, LevelChecks.Swap>, +actual: U32) -> List<&2, String>:
  match swaps:
    case Nil{}:
      Nil{}
    case Con{LevelChecks.Swap{+category, _}, rest}:
      (Json.quote(True{}, category) ++ ":" ++ Json.quote(True{}, actual_of(build, actual, category))) <> swap_items(build, rest, actual)

def swaps_hold(+build: Builds.Build, swaps: List<&2, LevelChecks.Swap>, +actual: U32) -> Bool:
  match swaps:
    case Nil{}:
      True{}
    case Con{LevelChecks.Swap{+category, +variant}, rest}:
      String.eq(actual_of(build, actual, category), variant) && swaps_hold(build, rest, actual)

def swaps_check(+build: Builds.Build, +shown: LevelChecks.Shown, +actual: U32) -> Bool & String:
  match shown:
    case LevelChecks.Shown{_, _, +swaps, _}:
      (swaps_hold(build, swaps, actual), ",\"actual\":{" ++ String.join(swap_items(build, swaps, actual), ",") ++ "}")

def world_outcomes(+build: Builds.Build, +shown: LevelChecks.Shown, w: CaveChoose.World) -> List<&2, Evaluate.Outcome>:
  match w:
    case CaveChoose.World{+swaps, +picks, +placed, _}:
      +chosen = placed_tasks(build, CavePrefix.chosen_ids(build, picks), placed)
      +tasks = Bool.pick(List<&2, Evaluate.Outcome>, Evaluate.has_tasks(shown), [Evaluate.pair_outcome("tasks", 0, LevelChecks.tasks_check(shown, chosen))], Nil{})
      +checked = Bool.pick(List<&2, Evaluate.Outcome>, Evaluate.has_swaps(shown), [Evaluate.pair_outcome("prefab_swaps", 0, swaps_check(build, shown, swaps))], Nil{})
      List.concat(&2, Evaluate.Outcome, [tasks, checked, Evaluate.setpiece_outcomes(Evaluate.shown_pieces(shown), chosen, 0)])

# The part A outcomes of an entry on the caves level table of a seed.
def level_outcomes(+build: Builds.Build, +shown: LevelChecks.Shown, +seed: U32) -> List<&2, Evaluate.Outcome>:
  world_outcomes(build, shown, CaveChoose.world(build, seed))
