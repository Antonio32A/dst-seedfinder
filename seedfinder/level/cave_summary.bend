import Base
import ../data/cave_catalog.bend as CaveCatalog
import ./cave_prefix.bend as CavePrefix
import ./cave_choose.bend as CaveChoose

def quoted(+s: String) -> String:
  "\"" ++ s ++ "\""

def swap_item(+swaps: U32, +k: U32) -> String:
  quoted(CaveCatalog.swap_category(k)) ++ ":" ++ quoted(Bool.pick(String, U32.is_zero(((swaps >> U32.to_nat(k)) .&. 1 : U32)),
    CaveCatalog.swap_regular(k), CaveCatalog.swap_swapped(k)))

def swap_items(n: Nat, +swaps: U32, +k: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      swap_item(swaps, k) <> swap_items(p, swaps, (k + 1 : U32))

def piece_names(placed: List<&2, CaveChoose.Placed>, +task: U32) -> List<&2, String>:
  match placed:
    case Nil{}:
      Nil{}
    case Con{CaveChoose.Placed{+key, +lo, +hi}, rest}:
      +tail = piece_names(rest, task)
      Bool.pick(List<&2, String>, CavePrefix.is_chosen(lo, hi, task), quoted(CaveCatalog.key_name(key)) <> tail, tail)

def task_json(+placed: List<&2, CaveChoose.Placed>, +task: U32) -> String:
  "{\"task\":" ++ quoted(CaveCatalog.task_name(task)) ++ ",\"set_pieces\":[" ++ String.join(piece_names(placed, task), ",")
    ++ "],\"random_set_pieces\":[]}"

def tasks_json(tasks: List<&2, U32>, +placed: List<&2, CaveChoose.Placed>) -> List<&2, String>:
  match tasks:
    case Nil{}:
      Nil{}
    case Con{+task, rest}:
      task_json(placed, task) <> tasks_json(rest, placed)

def world_json(+w: CaveChoose.World) -> String:
  match w:
    case CaveChoose.World{+swaps, +picks, +placed, +crashed}:
      Bool.pick(String, crashed, "{\"error\":\"worldgen raises a Lua error for this seed\"}",
        "{\"prefab_swaps\":{" ++ String.join(swap_items(U32.to_nat(CaveCatalog.swap_count()), swaps, 0), ",")
          ++ "},\"tasks\":[" ++ String.join(tasks_json(CavePrefix.chosen_ids(picks), placed), ",") ++ "]}")

# The caves level table of a seed as JSON, in the reference harness' world format.
def summary_json(+seed: U32) -> String:
  world_json(CaveChoose.world(seed))
