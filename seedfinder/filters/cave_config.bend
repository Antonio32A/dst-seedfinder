import Base
import ../data/cave_catalog.bend as CaveCatalog
import ../level/cave_prefix.bend as CavePrefix
import ../level/cave_choose.bend as CaveChoose
import ../level/choose.bend as LevelChoose
import ./json.bend as Json
import ./parse.bend as Parse
import ./config.bend as Config
import ./rules.bend as Rules

# The search config of the caves shard (docs/config.md): its part A, the level table. Task sets are two words over
# data/cave_catalog.bend task ids (ids 0-31 in `lo`, ids 32.. in `hi`); a rule bounds how many times a set piece (a
# cave_catalog key) is placed in the rule's tasks. Parts B-E (rules.bend) are decided on the caves world.
type TaskSet is Data:
  TaskSet{lo: U32, hi: U32}

type Rule is Data:
  Rule{key: U32, tasks: TaskSet, low: U32, high: U32}

type Criteria is Data:
  Criteria{required: TaskSet, excluded: TaskSet, swap_care: U32, swap_want: U32, rules: List<&2, Rule>}

# A compiled caves config: the platform for the report, the part A criteria of the entries, their parts B-E (in the same
# order) and the part A criteria that make a seed a candidate (those of the entries that are not passive; anything when
# there are no entries).
type Config is Data:
  Config{windows: Bool, criteria: List<&2, Criteria>, later: List<&2, Rules.Later>, scanned: List<&2, Criteria>}

def every_task() -> TaskSet:
  TaskSet{4294967295, 4294967295}

def anything() -> Criteria:
  Criteria{TaskSet{0, 0}, TaskSet{0, 0}, 0, 0, Nil{}}

def lookup(names: List<&2, CaveCatalog.Name>, +name: String) -> Maybe<&2, U32>:
  match names:
    case Nil{}:
      None{}
    case Con{CaveCatalog.Name{+entry, +id}, rest}:
      Bool.pick(Maybe<&2, U32>, String.eq(entry, name), Some{id}, lookup(rest, name))

def task_of(json: Json.Json, +index: U32, +path: String) -> Result<&1, &1, U32 & String, U32>:
  do Result<&1, &1, U32 & String, U32>:
    +name : String <- Parse.string_of(json, Parse.indexed(path, index))
    Config.known(lookup(CaveCatalog.tasks(), name), "task", name, path)

def task_masks(items: List<&2, Json.Json>, +index: U32, +path: String, +lo: U32, +hi: U32) -> Result<&1, &1, U32 & String, TaskSet>:
  match items:
    case Nil{}:
      Done{TaskSet{lo, hi}}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, TaskSet>:
        +task : U32 <- task_of(item, index, path)
        task_masks(rest, (index + 1 : U32), path, (lo .|. CavePrefix.task_bit_lo(task) : U32), (hi .|. CavePrefix.task_bit_hi(task) : U32))

def task_list(m: Maybe<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, TaskSet>:
  do Result<&1, &1, U32 & String, TaskSet>:
    items : List<&2, Json.Json> <- Parse.optional_items(m, path)
    listed : List<&2, Json.Json> <- Parse.capped(items, 25, "tasks", path)
    task_masks(listed, 0, path, 0, 0)

def task_rule(+tasks_key: String, section: Maybe<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, TaskSet>:
  do Result<&1, &1, U32 & String, TaskSet>:
    +fields : List<&2, Json.Json> <- Parse.optional_fields(section, path)
    ok : Unit <- Parse.check_keys(fields, ["required", "excluded"], path)
    task_list(Parse.field(fields, tasks_key), path ++ "." ++ tasks_key)

def swap_index(n: Nat, +category: String, +k: U32) -> U32:
  match n:
    case 0n:
      255
    case 1n+p:
      Bool.pick(U32, String.eq(CaveCatalog.swap_category(k), category), k, swap_index(p, category, (k + 1 : U32)))

def swappable(+k: U32) -> Bool:
  U32.is_eq(((CaveCatalog.swaps_possible() >> U32.to_nat((k .&. 31 : U32))) .&. 1 : U32), 1)

# Packs a prefab swap choice as care bit | want bit << 8; the swapped variant is only valid where the caves allow it.
def swap_choice(+category: String, +value: Json.Json, +path: String) -> Result<&1, &1, U32 & String, U32>:
  +k = swap_index(U32.to_nat(CaveCatalog.swap_count()), category, 0)
  +bit = (1 << U32.to_nat((k .&. 31 : U32)) : U32)
  +choice = Config.text_of(value)
  +swapped = String.eq(choice, CaveCatalog.swap_swapped(k)) && swappable(k)
  +valid = Config.is_string(value) && (k < 255 : U32) && (swapped || String.eq(choice, CaveCatalog.swap_regular(k)))
  Bool.pick(Result<&1, &1, U32 & String, U32>, valid, Done{(bit .|. (Bool.pick(U32, swapped, bit, 0) << 8n) : U32)},
    Fail{Parse.failure("unknown prefab swap " ++ Parse.quoted(category) ++ ": " ++ Json.dump(value) ++ " in " ++ path)})

def swap_choices(fields: List<&2, Json.Json>, +path: String, +acc: U32) -> Result<&1, &1, U32 & String, U32>:
  match fields:
    case Nil{}:
      Done{acc}
    case Con{Json.JField{+category, +value}, rest}:
      do Result<&1, &1, U32 & String, U32>:
        +packed : U32 <- swap_choice(category, value, path)
        swap_choices(rest, path, (acc .|. packed : U32))
    case Con{_, rest}:
      swap_choices(rest, path, acc)

def swaps_of(m: Maybe<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, U32>:
  do Result<&1, &1, U32 & String, U32>:
    fields : List<&2, Json.Json> <- Parse.optional_fields(m, path)
    swap_choices(fields, path, 0)

def bounded_rule(+key: U32, +tasks: TaskSet, bound: Json.Json, +path: String) -> Result<&1, &1, U32 & String, Rule>:
  match bound:
    case Json.JNum{+low}:
      Done{Rule{key, tasks, low, 4294967295}}
    case Json.JArr{Con{Json.JNum{+low}, Con{Json.JNum{+high}, Nil{}}}}:
      Done{Rule{key, tasks, low, high}}
    case _:
      Fail{Config.bound_message(path)}

def piece_keys(entries: List<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match entries:
    case Nil{}:
      Done{Nil{}}
    case Con{Json.JField{+name, _}, rest}:
      do Result<&1, &1, U32 & String, List<&2, U32>>:
        key : U32 <- Config.known(lookup(CaveCatalog.pieces(), name), "set piece", name, path)
        others : List<&2, U32> <- piece_keys(rest, path)
        return key <> others
    case Con{_, rest}:
      piece_keys(rest, path)

def rules_in(+tasks: TaskSet, entries: List<&2, Json.Json>, keys: List<&2, U32>, +path: String, acc: List<&2, Rule>) -> Result<&1, &1, U32 & String, List<&2, Rule>>:
  match entries keys:
    case Con{Json.JField{+name, bound}, rest} Con{+key, others}:
      do Result<&1, &1, U32 & String, List<&2, Rule>>:
        rule : Rule <- bounded_rule(key, tasks, bound, path ++ "[" ++ Parse.quoted(name) ++ "]")
        rules_in(tasks, rest, others, path, rule <> acc)
    case _ _:
      Done{acc}

def scope_of(+tasks: TaskSet) -> TaskSet:
  match tasks:
    case TaskSet{+lo, +hi}:
      Bool.pick(TaskSet, U32.is_zero((lo .|. hi : U32)), every_task(), tasks)

def setpiece_rules(item: Json.Json, +path: String, acc: List<&2, Rule>) -> Result<&1, &1, U32 & String, List<&2, Rule>>:
  do Result<&1, &1, U32 & String, List<&2, Rule>>:
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(item, ["tasks", "required"], path)
    +required : List<&2, Json.Json> <- Parse.optional_fields(Parse.field(fields, "required"), path ++ ".required")
    listed : List<&2, Json.Json> <- Parse.capped(required, 16, "set pieces", path ++ ".required")
    keys : List<&2, U32> <- piece_keys(required, path ++ ".required")
    +tasks : TaskSet <- task_list(Parse.field(fields, "tasks"), path ++ ".tasks")
    rules_in(scope_of(tasks), required, keys, path ++ ".required", acc)

def rules_of(items: List<&2, Json.Json>, +index: U32, +path: String, acc: List<&2, Rule>) -> Result<&1, &1, U32 & String, List<&2, Rule>>:
  match items:
    case Nil{}:
      Done{acc}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, Rule>>:
        more : List<&2, Rule> <- setpiece_rules(item, Parse.indexed(path, index), acc)
        rules_of(rest, (index + 1 : U32), path, more)

type Entry is Data:
  Entry{level: Criteria, later: Rules.Later, passive: Bool}

def entry_of(json: Json.Json, +path: String) -> Result<&1, &1, U32 & String, Entry>:
  do Result<&1, &1, U32 & String, Entry>:
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(json, ["passive", "tasks", "prefab_swaps", "setpieces", "counts", "distances", "tiles", "routes"], path)
    +passive : Bool <- Parse.optional_flag(Parse.field(fields, "passive"), path ++ ".passive")
    items : List<&2, Json.Json> <- Parse.optional_items(Parse.field(fields, "setpieces"), path ++ ".setpieces")
    listed : List<&2, Json.Json> <- Parse.capped(items, 16, "rules", path ++ ".setpieces")
    rules : List<&2, Rule> <- rules_of(listed, 0, path ++ ".setpieces", Nil{})
    later : Rules.Later <- Rules.later_of(fields, path, True{})
    required : TaskSet <- task_rule("required", Parse.field(fields, "tasks"), path ++ ".tasks")
    excluded : TaskSet <- task_rule("excluded", Parse.field(fields, "tasks"), path ++ ".tasks")
    +swaps : U32 <- swaps_of(Parse.field(fields, "prefab_swaps"), path ++ ".prefab_swaps")
    return Entry{Criteria{required, excluded, (swaps .&. 255 : U32), (swaps >> 8n : U32), rules}, later, passive}

def entry_list(items: List<&2, Json.Json>, +index: U32) -> Result<&1, &1, U32 & String, List<&2, Entry>>:
  match items:
    case Nil{}:
      Done{Nil{}}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, Entry>>:
        head : Entry <- entry_of(item, Parse.indexed("criteria", index))
        tail : List<&2, Entry> <- entry_list(rest, (index + 1 : U32))
        return head <> tail

def levels_of(entries: List<&2, Entry>) -> List<&2, Criteria>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Entry{level, _, _}, rest}:
      level <> levels_of(rest)

def laters_of(entries: List<&2, Entry>) -> List<&2, Rules.Later>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Entry{_, later, _}, rest}:
      later <> laters_of(rest)

def active_levels(entries: List<&2, Entry>) -> List<&2, Criteria>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Entry{level, _, False{}}, rest}:
      level <> active_levels(rest)
    case Con{_, rest}:
      active_levels(rest)

def some_active(+entries: List<&2, Entry>) -> Result<&1, &1, U32 & String, Unit>:
  Bool.pick(Result<&1, &1, U32 & String, Unit>, List.is_empty(&2, Entry, entries) || Bool.not(List.is_empty(&2, Criteria, active_levels(entries))), Done{Unit{}},
    Fail{Parse.failure("every criteria entry is passive (at least one must not be)")})

def or_anything(criteria: List<&2, Criteria>) -> List<&2, Criteria>:
  match criteria:
    case Nil{}:
      [anything()]
    case _:
      criteria

def config_from(+windows: Bool, +entries: List<&2, Entry>) -> Config:
  Config{windows, levels_of(entries), laters_of(entries), or_anything(active_levels(entries))}

# Compiles the JSON text of a search config (docs/config.md) for the caves shard.
def config_of(+text: String) -> Result<&1, &1, U32 & String, Config>:
  do Result<&1, &1, U32 & String, Config>:
    json : Json.Json <- Json.parse(text)
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(json, ["version", "platform", "settings", "criteria", "shard"], "the config")
    +windows : Bool <- Config.platform_of(Parse.field(fields, "platform"))
    supported : Unit <- Config.supported_version(Parse.field(fields, "version"))
    shard : U32 <- Config.shard_of(Parse.field(fields, "shard"))
    settings : List<&2, Json.Json> <- Parse.optional_fields(Parse.field(fields, "settings"), "settings")
    defaults : Unit <- Config.default_settings(settings)
    items : List<&2, Json.Json> <- Parse.optional_items(Parse.field(fields, "criteria"), "criteria")
    listed : List<&2, Json.Json> <- Parse.capped(items, 8, "entries", "criteria")
    +entries : List<&2, Entry> <- entry_list(listed, 0)
    active : Unit <- some_active(entries)
    return config_from(windows, entries)

def tasks_hold(+c: Criteria, +lo: U32, +hi: U32, +swaps: U32) -> Bool:
  match c:
    case Criteria{TaskSet{+required_lo, +required_hi}, TaskSet{+excluded_lo, +excluded_hi}, +care, +want, _}:
      U32.is_zero(((required_lo .&. U32.not(lo)) .|. (required_hi .&. U32.not(hi)) .|. (excluded_lo .&. lo) .|. (excluded_hi .&. hi)
        .|. ((swaps .^. want) .&. care) : U32))

def any_tasks_hold(criteria: List<&2, Criteria>, +lo: U32, +hi: U32, +swaps: U32) -> Bool:
  match criteria:
    case Nil{}:
      False{}
    case Con{+c, rest}:
      tasks_hold(c, lo, hi, swaps) || any_tasks_hold(rest, lo, hi, swaps)

# How many of the rule's tasks the set piece went to (a key AddSetPeices never added went to none).
def placed_in(placed: List<&2, CaveChoose.Placed>, +rule: Rule) -> U32:
  match placed:
    case Nil{}:
      0
    case Con{CaveChoose.Placed{+key, +lo, +hi}, rest}:
      match rule:
        case Rule{+wanted, TaskSet{+scope_lo, +scope_hi}, _, _}:
          Bool.pick(U32, U32.is_eq(key, wanted), (LevelChoose.popcount((lo .&. scope_lo : U32)) + LevelChoose.popcount((hi .&. scope_hi : U32)) : U32),
            placed_in(rest, rule))

def in_bounds(+count: U32, +low: U32, +high: U32) -> Bool:
  (low <= count : U32) && (count <= high : U32)

def rule_holds(placed: List<&2, CaveChoose.Placed>, +rule: Rule) -> Bool:
  match rule:
    case Rule{_, _, +low, +high}:
      in_bounds(placed_in(placed, rule), low, high)

def rules_hold(rules: List<&2, Rule>, +placed: List<&2, CaveChoose.Placed>) -> Bool:
  match rules:
    case Nil{}:
      True{}
    case Con{+rule, rest}:
      rule_holds(placed, rule) && rules_hold(rest, placed)

def criteria_rules(+c: Criteria) -> List<&2, Rule>:
  match c:
    case Criteria{_, _, _, _, rules}:
      rules

def any_hold(criteria: List<&2, Criteria>, +w: CaveChoose.World, +lo: U32, +hi: U32) -> Bool:
  match criteria:
    case Nil{}:
      False{}
    case Con{+c, rest}:
      match w:
        case CaveChoose.World{+swaps, _, +placed, _}:
          (tasks_hold(c, lo, hi, swaps) && rules_hold(criteria_rules(c), placed)) || any_hold(rest, w, lo, hi)

def world_holds(+criteria: List<&2, Criteria>, +w: CaveChoose.World, +lo: U32, +hi: U32) -> Bool:
  match w:
    case CaveChoose.World{_, _, _, +crashed}:
      Bool.not(crashed) && any_hold(criteria, w, lo, hi)

# The most a rule can still ask for once AddSetPeices is done: the copies of its key that were added.
def rules_possible(rules: List<&2, Rule>, +entries: List<&2, CaveChoose.Entry>) -> Bool:
  match rules:
    case Nil{}:
      True{}
    case Con{Rule{+key, _, +low, _}, rest}:
      (low <= CaveChoose.count_of(entries, key) : U32) && rules_possible(rest, entries)

def any_possible(criteria: List<&2, Criteria>, +lo: U32, +hi: U32, +swaps: U32, +entries: List<&2, CaveChoose.Entry>) -> Bool:
  match criteria:
    case Nil{}:
      False{}
    case Con{+c, rest}:
      (tasks_hold(c, lo, hi, swaps) && rules_possible(criteria_rules(c), entries)) || any_possible(rest, lo, hi, swaps, entries)

def choose_gate(pass: Bool, +criteria: List<&2, Criteria>, +c: CavePrefix.Chosen, a: CaveChoose.Added) -> Bool:
  match pass:
    case False{}:
      False{}
    case True{}:
      match c:
        case CavePrefix.Chosen{_, _, CavePrefix.Masks{+lo, +hi, _, _}, _}:
          world_holds(criteria, CaveChoose.choose_from(c, a), lo, hi)

def added_stage(+criteria: List<&2, Criteria>, +c: CavePrefix.Chosen, +a: CaveChoose.Added) -> Bool:
  match c a:
    case CavePrefix.Chosen{+swaps, _, CavePrefix.Masks{+lo, +hi, _, _}, _} CaveChoose.Added{+entries, _}:
      choose_gate(any_possible(criteria, lo, hi, swaps, entries), criteria, c, a)

def added_gate(pass: Bool, +criteria: List<&2, Criteria>, +c: CavePrefix.Chosen) -> Bool:
  match pass:
    case False{}:
      False{}
    case True{}:
      added_stage(criteria, c, CaveChoose.added_of(c))

def prefix_gate(+criteria: List<&2, Criteria>, +c: CavePrefix.Chosen) -> Bool:
  match c:
    case CavePrefix.Chosen{+swaps, _, CavePrefix.Masks{+lo, +hi, _, +crashed}, _}:
      added_gate(Bool.not(crashed) && any_tasks_hold(criteria, lo, hi, swaps), criteria, c)

# Stages bail out early: tasks and prefab swaps, then AddSetPeices' outcome, then ChooseSetPieces.
def matches(+criteria: List<&2, Criteria>, +seed: U32) -> Bool:
  prefix_gate(criteria, CavePrefix.chosen(seed))

# Index of the first criteria entry that holds for the seed (the number of entries when none does).
def first_match(criteria: List<&2, Criteria>, +seed: U32) -> U32:
  match criteria:
    case Nil{}:
      0
    case Con{+c, rest}:
      Bool.pick(U32, matches([c], seed), 0, (1 + first_match(rest, seed) : U32))

def local_rules(rules: List<&2, Rule>) -> List<&2, Rule>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{Rule{+key, TaskSet{+lo, +hi}, +low, +high}, rest}:
      Rule{key, TaskSet{lo, hi}, low, high} <> local_rules(rest)

# A private copy, so parallel workers do not share reference counts.
def local_criteria(criteria: List<&2, Criteria>) -> List<&2, Criteria>:
  match criteria:
    case Nil{}:
      Nil{}
    case Con{Criteria{TaskSet{+required_lo, +required_hi}, TaskSet{+excluded_lo, +excluded_hi}, +care, +want, rules}, rest}:
      Criteria{TaskSet{required_lo, required_hi}, TaskSet{excluded_lo, excluded_hi}, care, want, local_rules(rules)} <> local_criteria(rest)
