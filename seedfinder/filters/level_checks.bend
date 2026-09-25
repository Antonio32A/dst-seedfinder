import Base
import ./json.bend as J
import ./parse.bend as PS
import ../level/summary.bend as W
import ../level/prefix.bend as P
import ../data/world_catalog.bend as K

# Part A of a criteria entry in config order (for the witnesses of criteria.py check_tasks, check_swaps and
# check_setpieces), read back from a config that filters/config.bend already accepted.
type Swap is Data:
  Swap{category: String, variant: String}

type Bounded is Data:
  Bounded{name: String, low: U32, high: Maybe<&2, U32>}

type Pieces is Data:
  Pieces{tasks: List<&2, String>, bounds: List<&2, Bounded>}

type Shown is Data:
  Shown{required: List<&2, String>, excluded: List<&2, String>, swaps: List<&2, Swap>, setpieces: List<&2, Pieces>}

def texts(items: List<&2, J.Json>) -> List<&2, String>:
  match items:
    case Nil{}:
      Nil{}
    case Con{J.JStr{+s}, rest}:
      s <> texts(rest)
    case Con{_, rest}:
      texts(rest)

def distinct_texts(names: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}:
      List.reverse(&2, String, seen)
    case Con{+name, rest}:
      distinct_texts(rest, Bool.pick(List<&2, String>, PS.is_member(seen, name), seen, name <> seen))

def listed(m: Maybe<&2, J.Json>) -> List<&2, String>:
  match m:
    case Some{J.JArr{items}}:
      distinct_texts(texts(items), Nil{})
    case _:
      Nil{}

def fields_of(m: Maybe<&2, J.Json>) -> List<&2, J.Json>:
  match m:
    case Some{J.JObj{fields}}:
      fields
    case _:
      Nil{}

def swaps_of(fields: List<&2, J.Json>) -> List<&2, Swap>:
  match fields:
    case Con{J.JField{+category, J.JStr{+variant}}, rest}:
      Swap{category, variant} <> swaps_of(rest)
    case Con{_, rest}:
      swaps_of(rest)
    case Nil{}:
      Nil{}

def bounds_of(fields: List<&2, J.Json>) -> List<&2, Bounded>:
  match fields:
    case Con{J.JField{+name, J.JNum{+low}}, rest}:
      Bounded{name, low, None{}} <> bounds_of(rest)
    case Con{J.JField{+name, J.JArr{Con{J.JNum{+low}, Con{J.JNum{+high}, _}}}}, rest}:
      Bounded{name, low, Some{high}} <> bounds_of(rest)
    case Con{_, rest}:
      bounds_of(rest)
    case Nil{}:
      Nil{}

def pieces_of(items: List<&2, J.Json>) -> List<&2, Pieces>:
  match items:
    case Con{J.JObj{+fields}, rest}:
      Pieces{listed(PS.field(fields, "tasks")), bounds_of(fields_of(PS.field(fields, "required")))} <> pieces_of(rest)
    case Con{_, rest}:
      pieces_of(rest)
    case Nil{}:
      Nil{}

def items_of(m: Maybe<&2, J.Json>) -> List<&2, J.Json>:
  match m:
    case Some{J.JArr{items}}:
      items
    case _:
      Nil{}

def shown_entry(fields: List<&2, J.Json>) -> Shown:
  +all = fields
  +tasks = fields_of(PS.field(all, "tasks"))
  Shown{listed(PS.field(tasks, "required")), listed(PS.field(tasks, "excluded")), swaps_of(fields_of(PS.field(all, "prefab_swaps"))),
    pieces_of(items_of(PS.field(all, "setpieces")))}

def shown_entries(items: List<&2, J.Json>) -> List<&2, Shown>:
  match items:
    case Con{J.JObj{+fields}, rest}:
      shown_entry(fields) <> shown_entries(rest)
    case Con{_, rest}:
      shown_entries(rest)
    case Nil{}:
      Nil{}

def shown_of_json(json: J.Json) -> List<&2, Shown>:
  match json:
    case J.JObj{+fields}:
      shown_entries(items_of(PS.field(fields, "criteria")))
    case _:
      Nil{}

def shown_or_none(r: Result<&1, &1, U32 & String, J.Json>) -> List<&2, Shown>:
  match r:
    case Done{json}:
      shown_of_json(json)
    case Fail{_}:
      Nil{}

# Part A of every entry of a valid config text, in config order.
def shown_of(+text: String) -> List<&2, Shown>:
  shown_or_none(J.parse(text))

# One chosen task of a level table: its name and every set piece placed in it (set_pieces then random_set_pieces).
type Placed is Data:
  Placed{task: String, pieces: List<&2, String>}

def piece_names(entries: List<&2, U32>, +task: U32) -> List<&2, String>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, rest}:
      +tail = piece_names(rest, task)
      Bool.pick(List<&2, String>, U32.is_eq((((entry >> 6n) >> U32.to_nat(task)) .&. 1 : U32), 1), K.key_name((entry .&. 63 : U32)) <> tail, tail)

def special_names(n: Nat, +codes: U32, +tasks: U32, +task: U32, +k: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +tail = special_names(p, codes, tasks, task, (k + 1 : U32))
      Bool.pick(List<&2, String>, U32.is_eq(P.field5(tasks, k), task), K.special_name(P.field5(codes, k)) <> tail, tail)

def placed_tasks(n: Nat, +s: W.Summary, +c: U32) -> List<&2, Placed>:
  match n s:
    case 0n _:
      Nil{}
    case 1n+p W.Summary{_, +lo, +entries, +codes, +tasks, +count, _}:
      +task = P.chosen_task(lo, c)
      Placed{K.task_name(task), List.append(&2, String, piece_names(entries, task), special_names(U32.to_nat(count), codes, tasks, task, 0))}
        <> placed_tasks(p, s, (c + 1 : U32))

# The chosen tasks of a level table in chosen order, with their placed set pieces.
def placed(+s: W.Summary) -> List<&2, Placed>:
  placed_tasks(W.chosen_count(), s, 0)

def task_names(placed: List<&2, Placed>) -> List<&2, String>:
  match placed:
    case Nil{}:
      Nil{}
    case Con{Placed{+task, _}, rest}:
      task <> task_names(rest)

def quoted_names(names: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}:
      Nil{}
    case Con{+name, rest}:
      J.quote(True{}, name) <> quoted_names(rest)

def quoted_list(+names: List<&2, String>) -> String:
  "[" ++ String.join(quoted_names(names), ",") ++ "]"

def only(names: List<&2, String>, +chosen: List<&2, String>, +wanted: Bool) -> List<&2, String>:
  match names:
    case Nil{}:
      Nil{}
    case Con{+name, rest}:
      +tail = only(rest, chosen, wanted)
      Bool.pick(List<&2, String>, Bool.xor(PS.is_member(chosen, name), Bool.not(wanted)), name <> tail, tail)

# check_tasks: (ok, fields after "ok").
def tasks_check(+shown: Shown, +placed: List<&2, Placed>) -> Bool & String:
  match shown:
    case Shown{+required, +excluded, _, _}:
      +chosen = task_names(placed)
      +missing = only(required, chosen, False{})
      +present = only(excluded, chosen, True{})
      (List.is_empty(&2, String, missing) && List.is_empty(&2, String, present), ",\"missing\":" ++ quoted_list(missing) ++ ",\"excluded_present\":" ++ quoted_list(present))

def actual_of(+swaps: U32, +category: String) -> String:
  Bool.pick(String, String.eq(category, "grass"), Bool.pick(String, U32.is_zero((swaps .&. 1 : U32)), "regular grass", "grass gekko"),
    Bool.pick(String, String.eq(category, "twigs"), Bool.pick(String, U32.is_zero((swaps .&. 2 : U32)), "regular twigs", "twiggy trees"),
      Bool.pick(String, U32.is_zero((swaps .&. 4 : U32)), "regular berries", "juicy berries")))

def swap_items(swaps: List<&2, Swap>, +actual: U32) -> List<&2, String>:
  match swaps:
    case Nil{}:
      Nil{}
    case Con{Swap{+category, _}, rest}:
      (J.quote(True{}, category) ++ ":" ++ J.quote(True{}, actual_of(actual, category))) <> swap_items(rest, actual)

def swaps_hold(swaps: List<&2, Swap>, +actual: U32) -> Bool:
  match swaps:
    case Nil{}:
      True{}
    case Con{Swap{+category, +variant}, rest}:
      String.eq(actual_of(actual, category), variant) && swaps_hold(rest, actual)

def summary_swaps(+s: W.Summary) -> U32:
  match s:
    case W.Summary{+swaps, _, _, _, _, _, _}:
      swaps

# check_swaps: (ok, fields after "ok").
def swaps_check(+shown: Shown, +s: W.Summary) -> Bool & String:
  match shown:
    case Shown{_, _, +swaps, _}:
      (swaps_hold(swaps, summary_swaps(s)), ",\"actual\":{" ++ String.join(swap_items(swaps, summary_swaps(s)), ",") ++ "}")

def scoped(placed: List<&2, Placed>, +scope: List<&2, String>) -> List<&2, String>:
  match placed:
    case Nil{}:
      Nil{}
    case Con{Placed{+task, +pieces}, rest}:
      +tail = scoped(rest, scope)
      Bool.pick(List<&2, String>, List.is_empty(&2, String, scope) || PS.is_member(scope, task), List.append(&2, String, pieces, tail), tail)

def occurrences(names: List<&2, String>, +name: String) -> U32:
  match names:
    case Nil{}:
      0
    case Con{+n, rest}:
      (Bool.to_u32(String.eq(n, name)) + occurrences(rest, name) : U32)

def bound_holds(+count: U32, +low: U32, high: Maybe<&2, U32>) -> Bool:
  match high:
    case None{}:
      (count >= low : U32)
    case Some{+h}:
      (count >= low : U32) && (count <= h : U32)

def piece_items(bounds: List<&2, Bounded>, +names: List<&2, String>) -> List<&2, String>:
  match bounds:
    case Nil{}:
      Nil{}
    case Con{Bounded{+name, _, _}, rest}:
      (J.quote(True{}, name) ++ ":" ++ U32.show(occurrences(names, name))) <> piece_items(rest, names)

def pieces_hold(bounds: List<&2, Bounded>, +names: List<&2, String>) -> Bool:
  match bounds:
    case Nil{}:
      True{}
    case Con{Bounded{+name, +low, +high}, rest}:
      bound_holds(occurrences(names, name), low, high) && pieces_hold(rest, names)

# check_setpieces for one rule: (ok, fields after "ok").
def setpiece_check(+rule: Pieces, +placed: List<&2, Placed>) -> Bool & String:
  match rule:
    case Pieces{+tasks, +bounds}:
      +names = scoped(placed, tasks)
      (pieces_hold(bounds, names), ",\"counts\":{" ++ String.join(piece_items(bounds, names), ",") ++ "}")
