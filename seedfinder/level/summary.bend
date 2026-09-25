import Base
import ../data/world_catalog.bend as K
import ./prefix.bend as P
import ./choose.bend as CH

# A World as plain data: level.set_pieces keys in pairs() order, each as key | task mask << 6.
type Summary is Data:
  Summary{
    swaps: U32, lo: U32, entries: List<&2, U32>, special_codes: U32, special_tasks: U32, special_count: U32,
    crashed: Bool
  }

type Listing is Type:
  Listing{table: Array<U32>, entries: List<&2, U32>}

def list_mask(got: Array<U32> & U32, +key: U32, entries: List<&2, U32>) -> Listing:
  (table, +mask) = got
  Listing{table, (key .|. (mask << 6n) : U32) <> entries}

def list_node(got: Array<U32> & U32, entries: List<&2, U32>) -> Listing:
  (table, +node) = got
  match node:
    case 0:
      Listing{table, entries}
    case _:
      list_mask(table[(CH.mask_slot() + (node .&. 63) : U32)], (node .&. 63 : U32), entries)

def list_step(st: Listing, +position: U32) -> Listing:
  match st:
    case Listing{table, entries}:
      list_node(table[position], entries)

def list_loop(n: Nat, st: Listing, +position: U32) -> Listing:
  match n:
    case 0n:
      st
    case 1n+p:
      list_loop(p, list_step(st, position), (position + 1 : U32))

def listed(st: Listing) -> List<&2, U32>:
  match st:
    case Listing{_, entries}:
      List.reverse(&2, U32, entries)

def summary_of(w: CH.World) -> Summary:
  match w:
    case CH.World{+swaps, +lo, _, _, table, +size, +codes, +tasks, +count, crashed}:
      Summary{swaps, lo, listed(list_loop(U32.to_nat(size), Listing{table, Nil{}}, 0)), codes, tasks, count, crashed}

def summary(+seed: U32) -> Summary:
  summary_of(CH.world(seed))

def quoted(+s: String) -> String:
  "\"" ++ s ++ "\""

def piece_names(entries: List<&2, U32>, +task: U32) -> List<&2, String>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, rest}:
      +tail = piece_names(rest, task)
      +placed = U32.is_eq((((entry >> 6n) >> U32.to_nat(task)) .&. 1 : U32), 1)
      Bool.pick(List<&2, String>, placed, quoted(K.key_name((entry .&. 63 : U32))) <> tail, tail)

def special_names(n: Nat, +codes: U32, +tasks: U32, +task: U32, +k: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +tail = special_names(p, codes, tasks, task, (k + 1 : U32))
      Bool.pick(List<&2, String>, U32.is_eq(P.field5(tasks, k), task), quoted(K.special_name(P.field5(codes, k))) <> tail, tail)

def task_json(+s: Summary, +c: U32) -> String:
  match s:
    case Summary{_, +lo, +entries, +codes, +tasks, +count, _}:
      +task = P.chosen_task(lo, c)
      "{\"task\":" ++ quoted(K.task_name(task)) ++ ",\"set_pieces\":[" ++ String.join(piece_names(entries, task), ",")
        ++ "],\"random_set_pieces\":[" ++ String.join(special_names(U32.to_nat(count), codes, tasks, task, 0), ",") ++ "]}"

def tasks_json(n: Nat, +s: Summary, +c: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      task_json(s, c) <> tasks_json(p, s, (c + 1 : U32))

def swap_name(+swaps: U32, +bit: U32, +regular: String, +swapped: String) -> String:
  quoted(Bool.pick(String, U32.is_zero((swaps .&. bit : U32)), regular, swapped))

def chosen_count() -> Nat:
  20n

# The level table as JSON, in the reference harness' world format.
def summary_json(+s: Summary) -> String:
  match s:
    case Summary{+swaps, _, _, _, _, _, crashed}:
      Bool.pick(String, crashed, "{\"error\":\"worldgen raises a Lua error for this seed\"}",
        "{\"prefab_swaps\":{\"grass\":" ++ swap_name(swaps, 1, "regular grass", "grass gekko")
          ++ ",\"twigs\":" ++ swap_name(swaps, 2, "regular twigs", "twiggy trees")
          ++ ",\"berries\":" ++ swap_name(swaps, 4, "regular berries", "juicy berries")
          ++ "},\"tasks\":[" ++ String.join(tasks_json(chosen_count(), s, 0), ",") ++ "]}")
