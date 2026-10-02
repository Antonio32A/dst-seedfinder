import Base
import ./json.bend as Json
import ./evaluate.bend as Evaluate
import ./level_checks.bend as LevelChecks
import ./parse.bend as Parse
import ../data/cave_catalog.bend as CaveCatalog
import ../level/cave_prefix.bend as CavePrefix
import ../level/cave_choose.bend as CaveChoose

# Part A of an entry on the caves level table of a seed, as the witnesses of docs/config.md section 8.

def piece_names(placed: List<&2, CaveChoose.Placed>, +task: U32) -> List<&2, String>:
  match placed:
    case Nil{}:
      Nil{}
    case Con{CaveChoose.Placed{+key, +lo, +hi}, rest}:
      +tail = piece_names(rest, task)
      Bool.pick(List<&2, String>, CavePrefix.is_chosen(lo, hi, task), CaveCatalog.key_name(key) <> tail, tail)

def placed_tasks(tasks: List<&2, U32>, +placed: List<&2, CaveChoose.Placed>) -> List<&2, LevelChecks.Placed>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+task, rest}:
      LevelChecks.Placed{CaveCatalog.task_name(task), piece_names(placed, task)} <> placed_tasks(rest, placed)

def swap_actual(n: Nat, +swaps: U32, +category: String, +k: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      Bool.pick(String, String.eq(CaveCatalog.swap_category(k), category),
        Bool.pick(String, U32.is_zero(((swaps >> U32.to_nat(k)) .&. 1 : U32)), CaveCatalog.swap_regular(k), CaveCatalog.swap_swapped(k)),
        swap_actual(p, swaps, category, (k + 1 : U32)))

def actual_of(+swaps: U32, +category: String) -> String:
  swap_actual(U32.to_nat(CaveCatalog.swap_count()), swaps, category, 0)

def swap_items(swaps: List<&2, LevelChecks.Swap>, +actual: U32) -> List<&2, String>:
  match swaps:
    case Nil{}:
      Nil{}
    case Con{LevelChecks.Swap{+category, _}, rest}:
      (Json.quote(True{}, category) ++ ":" ++ Json.quote(True{}, actual_of(actual, category))) <> swap_items(rest, actual)

def swaps_hold(swaps: List<&2, LevelChecks.Swap>, +actual: U32) -> Bool:
  match swaps:
    case Nil{}:
      True{}
    case Con{LevelChecks.Swap{+category, +variant}, rest}:
      String.eq(actual_of(actual, category), variant) && swaps_hold(rest, actual)

def swaps_check(+shown: LevelChecks.Shown, +actual: U32) -> Bool & String:
  match shown:
    case LevelChecks.Shown{_, _, +swaps, _}:
      (swaps_hold(swaps, actual), ",\"actual\":{" ++ String.join(swap_items(swaps, actual), ",") ++ "}")

def world_outcomes(+shown: LevelChecks.Shown, w: CaveChoose.World) -> List<&2, Evaluate.Outcome>:
  match w:
    case CaveChoose.World{+swaps, +picks, +placed, _}:
      +chosen = placed_tasks(CavePrefix.chosen_ids(picks), placed)
      +tasks = Bool.pick(List<&2, Evaluate.Outcome>, Evaluate.has_tasks(shown), [Evaluate.pair_outcome("tasks", 0, LevelChecks.tasks_check(shown, chosen))], Nil{})
      +checked = Bool.pick(List<&2, Evaluate.Outcome>, Evaluate.has_swaps(shown), [Evaluate.pair_outcome("prefab_swaps", 0, swaps_check(shown, swaps))], Nil{})
      List.concat(&2, Evaluate.Outcome, [tasks, checked, Evaluate.setpiece_outcomes(Evaluate.shown_pieces(shown), chosen, 0)])

# The part A outcomes of an entry on the caves level table of a seed.
def level_outcomes(+shown: LevelChecks.Shown, +seed: U32) -> List<&2, Evaluate.Outcome>:
  world_outcomes(shown, CaveChoose.world(seed))
