import Base
import ../rng/pcg.bend as Pcg
import ../level/setpieces.bend as LevelSetpieces
import ../data/world_catalog.bend as WorldCatalog
import ../level/prefix.bend as LevelPrefix
import ../level/choose.bend as LevelChoose
import ./json.bend as Json
import ./parse.bend as Parse
import ./rules.bend as Rules

# A world filter (README.md "world find"): criteria are alternatives, a seed matches when one holds.
# Task sets are masks over data/world_catalog.bend task ids; a rule bounds how many times a set piece
# (world_catalog piece id) is placed in the rule's tasks.
type Rule is Data:
  Rule{piece: U32, tasks: U32, low: U32, high: U32}

type Criteria is Data:
  Criteria{required: U32, excluded: U32, swap_care: U32, swap_want: U32, rules: List<&2, Rule>}

# A compiled config: the platform the worlds are generated on (windows unless "linux"), the part A criteria of the
# entries, their parts B-E (in the same order), the first "not supported by this binary yet" message when an entry
# has a counts, distances, tiles or routes key, and the part A criteria that make a seed a candidate (those of the
# entries that are not passive; anything when there are no entries).
type Config is Data:
  Config{windows: Bool, criteria: List<&2, Criteria>, later: List<&2, Rules.Later>, unsupported: Maybe<&2, String>, scanned: List<&2, Criteria>}

def every_task() -> U32:
  33554431

def unbounded() -> U32:
  4294967295

def anything() -> Criteria:
  Criteria{0, 0, 0, 0, Nil{}}

# The search criteria of a config: an empty criteria list matches every seed.
def or_anything(criteria: List<&2, Criteria>) -> List<&2, Criteria>:
  match criteria:
    case Nil{}:
      [anything()]
    case _:
      criteria

def is_member(names: List<&2, String>, +name: String) -> Bool:
  Parse.is_member(names, name)

# The parts B-E of an entry without counts, distances, tiles or routes rules.
def no_later() -> Rules.Later:
  Rules.nothing_later()

def lookup(names: List<&2, WorldCatalog.Name>, +name: String) -> Maybe<&2, U32>:
  match names:
    case Nil{}:
      None{}
    case Con{WorldCatalog.Name{+entry, +id}, rest}:
      Bool.pick(Maybe<&2, U32>, String.eq(entry, name), Some{id}, lookup(rest, name))

def known(found: Maybe<&2, U32>, +kind: String, +name: String, +path: String) -> Result<&1, &1, U32 & String, U32>:
  match found:
    case None{}:
      Fail{Parse.failure("unknown " ++ kind ++ " " ++ Parse.quoted(name) ++ " in " ++ path)}
    case Some{id}:
      Done{id}

def task_of(json: Json.Json, +index: U32, +path: String) -> Result<&1, &1, U32 & String, U32>:
  do Result<&1, &1, U32 & String, U32>:
    +name : String <- Parse.string_of(json, Parse.indexed(path, index))
    known(lookup(WorldCatalog.tasks(), name), "task", name, path)

def task_mask(items: List<&2, Json.Json>, +index: U32, +path: String, +acc: U32) -> Result<&1, &1, U32 & String, U32>:
  match items:
    case Nil{}:
      Done{acc}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, U32>:
        +task : U32 <- task_of(item, index, path)
        task_mask(rest, (index + 1 : U32), path, (acc .|. LevelPrefix.task_bit(task) : U32))

def task_list(m: Maybe<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, U32>:
  do Result<&1, &1, U32 & String, U32>:
    items : List<&2, Json.Json> <- Parse.optional_items(m, path)
    listed : List<&2, Json.Json> <- Parse.capped(items, 25, "tasks", path)
    task_mask(listed, 0, path, 0)

def task_rule(+tasks_key: String, section: Maybe<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, U32>:
  do Result<&1, &1, U32 & String, U32>:
    +fields : List<&2, Json.Json> <- Parse.optional_fields(section, path)
    ok : Unit <- Parse.check_keys(fields, ["required", "excluded"], path)
    task_list(Parse.field(fields, tasks_key), path ++ "." ++ tasks_key)

def swap_bit(+category: String) -> U32:
  Bool.pick(U32, String.eq(category, "grass"), 1, Bool.pick(U32, String.eq(category, "twigs"), 2, Bool.pick(U32, String.eq(category, "berries"), 4, 0)))

def swapped_name(+bit: U32) -> String:
  Bool.pick(String, U32.is_eq(bit, 1), "grass gekko", Bool.pick(String, U32.is_eq(bit, 2), "twiggy trees", "juicy berries"))

def regular_name(+bit: U32) -> String:
  Bool.pick(String, U32.is_eq(bit, 1), "regular grass", Bool.pick(String, U32.is_eq(bit, 2), "regular twigs", "regular berries"))

def text_of(json: Json.Json) -> String:
  match json:
    case Json.JStr{s}:
      s
    case _:
      ""

def is_string(json: Json.Json) -> Bool:
  match json:
    case Json.JStr{_}:
      True{}
    case _:
      False{}

# Packs a prefab swap choice as care bit | want bit << 8.
def swap_choice(+category: String, +value: Json.Json, +path: String) -> Result<&1, &1, U32 & String, U32>:
  +bit = swap_bit(category)
  +choice = text_of(value)
  +valid = is_string(value) && Bool.not(U32.is_zero(bit)) && (String.eq(choice, swapped_name(bit)) || String.eq(choice, regular_name(bit)))
  +want = Bool.pick(U32, String.eq(choice, swapped_name(bit)), bit, 0)
  Bool.pick(Result<&1, &1, U32 & String, U32>, valid, Done{(bit .|. (want << 8n) : U32)},
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

def bound_message(+path: String) -> U32 & String:
  Parse.failure(path ++ " must be an integer in 0..4294967295 or [min, max]")

def bounded_rule(+piece: U32, +tasks: U32, bound: Json.Json, +path: String) -> Result<&1, &1, U32 & String, Rule>:
  match bound:
    case Json.JNum{+low}:
      Done{Rule{piece, tasks, low, unbounded()}}
    case Json.JArr{Con{Json.JNum{+low}, Con{Json.JNum{+high}, Nil{}}}}:
      Done{Rule{piece, tasks, low, high}}
    case _:
      Fail{bound_message(path)}

def piece_ids(entries: List<&2, Json.Json>, +path: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match entries:
    case Nil{}:
      Done{Nil{}}
    case Con{Json.JField{+name, _}, rest}:
      do Result<&1, &1, U32 & String, List<&2, U32>>:
        piece : U32 <- known(lookup(WorldCatalog.pieces(), name), "set piece", name, path)
        others : List<&2, U32> <- piece_ids(rest, path)
        return piece <> others
    case Con{_, rest}:
      piece_ids(rest, path)

def rules_in(+tasks: U32, entries: List<&2, Json.Json>, pieces: List<&2, U32>, +path: String, acc: List<&2, Rule>) -> Result<&1, &1, U32 & String, List<&2, Rule>>:
  match entries pieces:
    case Con{Json.JField{+name, bound}, rest} Con{+piece, others}:
      do Result<&1, &1, U32 & String, List<&2, Rule>>:
        rule : Rule <- bounded_rule(piece, tasks, bound, path ++ "[" ++ Parse.quoted(name) ++ "]")
        rules_in(tasks, rest, others, path, rule <> acc)
    case _ _:
      Done{acc}

def setpiece_rules(item: Json.Json, +path: String, acc: List<&2, Rule>) -> Result<&1, &1, U32 & String, List<&2, Rule>>:
  do Result<&1, &1, U32 & String, List<&2, Rule>>:
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(item, ["tasks", "required"], path)
    +required : List<&2, Json.Json> <- Parse.optional_fields(Parse.field(fields, "required"), path ++ ".required")
    listed : List<&2, Json.Json> <- Parse.capped(required, 16, "set pieces", path ++ ".required")
    pieces : List<&2, U32> <- piece_ids(required, path ++ ".required")
    +tasks : U32 <- task_list(Parse.field(fields, "tasks"), path ++ ".tasks")
    rules_in(Bool.pick(U32, U32.is_zero(tasks), every_task(), tasks), required, pieces, path ++ ".required", acc)

def rules_of(items: List<&2, Json.Json>, +index: U32, +path: String, acc: List<&2, Rule>) -> Result<&1, &1, U32 & String, List<&2, Rule>>:
  match items:
    case Nil{}:
      Done{acc}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, Rule>>:
        more : List<&2, Rule> <- setpiece_rules(item, Parse.indexed(path, index), acc)
        rules_of(rest, (index + 1 : U32), path, more)

def later_parts() -> List<&2, String>:
  ["counts", "distances", "tiles", "routes"]

def first_later(+fields: List<&2, Json.Json>, sections: List<&2, String>, +path: String) -> Maybe<&2, String>:
  match sections:
    case Nil{}:
      None{}
    case Con{+section, rest}:
      Bool.pick(Maybe<&2, String>, Maybe.is_some(&2, Json.Json, Parse.field(fields, section)),
        Some{"config: " ++ path ++ "." ++ section ++ " is not supported by this binary yet (only tasks, prefab_swaps and setpieces are)"},
        first_later(fields, rest, path))

# One parsed criteria entry: its part A, its parts B-E, the message for a finder without worlds when it has a
# counts, distances, tiles or routes key, and whether it is passive (only decided on candidates of other entries).
type Entry is Data:
  Entry{level: Criteria, later: Rules.Later, unsupported: Maybe<&2, String>, passive: Bool}

def entry_of(json: Json.Json, +path: String) -> Result<&1, &1, U32 & String, Entry>:
  do Result<&1, &1, U32 & String, Entry>:
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(json, ["passive", "tasks", "prefab_swaps", "setpieces", "counts", "distances", "tiles", "routes"], path)
    +passive : Bool <- Parse.optional_flag(Parse.field(fields, "passive"), path ++ ".passive")
    items : List<&2, Json.Json> <- Parse.optional_items(Parse.field(fields, "setpieces"), path ++ ".setpieces")
    listed : List<&2, Json.Json> <- Parse.capped(items, 16, "rules", path ++ ".setpieces")
    rules : List<&2, Rule> <- rules_of(listed, 0, path ++ ".setpieces", Nil{})
    later : Rules.Later <- Rules.later_of(fields, path, False{})
    +required : U32 <- task_rule("required", Parse.field(fields, "tasks"), path ++ ".tasks")
    +excluded : U32 <- task_rule("excluded", Parse.field(fields, "tasks"), path ++ ".tasks")
    +swaps : U32 <- swaps_of(Parse.field(fields, "prefab_swaps"), path ++ ".prefab_swaps")
    return Entry{Criteria{required, excluded, (swaps .&. 255 : U32), (swaps >> 8n : U32), rules}, later, first_later(fields, later_parts(), path), passive}

def entry_list(items: List<&2, Json.Json>, +index: U32) -> Result<&1, &1, U32 & String, List<&2, Entry>>:
  match items:
    case Nil{}:
      Done{Nil{}}
    case Con{item, rest}:
      do Result<&1, &1, U32 & String, List<&2, Entry>>:
        head : Entry <- entry_of(item, Parse.indexed("criteria", index))
        tail : List<&2, Entry> <- entry_list(rest, (index + 1 : U32))
        return head <> tail

def is_default(json: Json.Json) -> Bool:
  match json:
    case Json.JStr{level}:
      String.eq(level, "default")
    case _:
      False{}

def default_setting(entry: Json.Json) -> Result<&1, &1, U32 & String, Unit>:
  match entry:
    case Json.JField{key, value}:
      Bool.pick(Result<&1, &1, U32 & String, Unit>, is_default(value), Done{Unit{}},
        Fail{Parse.failure("only default settings are supported (" ++ key ++ ")")})
    case _:
      Fail{Parse.failure("settings must be an object")}

def default_settings(entries: List<&2, Json.Json>) -> Result<&1, &1, U32 & String, Unit>:
  match entries:
    case Nil{}:
      Done{Unit{}}
    case Con{entry, rest}:
      do Result<&1, &1, U32 & String, Unit>:
        ok : Unit <- default_setting(entry)
        default_settings(rest)

def is_one(json: Json.Json) -> Bool:
  match json:
    case Json.JNum{n}:
      U32.is_eq(n, 1)
    case _:
      False{}

def supported_version(m: Maybe<&2, Json.Json>) -> Result<&1, &1, U32 & String, Unit>:
  match m:
    case None{}:
      Done{Unit{}}
    case Some{+json}:
      Bool.pick(Result<&1, &1, U32 & String, Unit>, is_one(json), Done{Unit{}}, Fail{Parse.failure("unsupported version " ++ Json.dump(json))})

def platform_of(m: Maybe<&2, Json.Json>) -> Result<&1, &1, U32 & String, Bool>:
  match m:
    case None{}:
      Done{True{}}
    case Some{+json}:
      Bool.pick(Result<&1, &1, U32 & String, Bool>, Parse.is_text(json, "windows") || Parse.is_text(json, "linux"),
        Done{Parse.is_text(json, "windows")}, Fail{Parse.failure("unknown platform " ++ Json.dump_text(json) ++ " (windows or linux)")})

# The config's shard key: 0 when absent, 1 forest, 2 caves.
def shard_of(m: Maybe<&2, Json.Json>) -> Result<&1, &1, U32 & String, U32>:
  match m:
    case None{}:
      Done{0}
    case Some{+json}:
      Bool.pick(Result<&1, &1, U32 & String, U32>, Parse.is_text(json, "forest"), Done{1},
        Bool.pick(Result<&1, &1, U32 & String, U32>, Parse.is_text(json, "caves"), Done{2},
          Fail{Parse.failure("unknown shard " ++ Json.dump_text(json) ++ " (forest or caves)")}))

def shard_code(m: Maybe<&2, Json.Json>) -> U32:
  match m:
    case Some{Json.JStr{+name}}:
      Bool.pick(U32, String.eq(name, "caves"), 2, Bool.pick(U32, String.eq(name, "forest"), 1, 0))
    case _:
      0

def object_shard(json: Json.Json) -> U32:
  match json:
    case Json.JObj{+fields}:
      shard_code(Parse.field(fields, "shard"))
    case _:
      0

def parsed_shard(r: Result<&1, &1, U32 & String, Json.Json>) -> U32:
  match r:
    case Done{json}:
      object_shard(json)
    case Fail{_}:
      0

# The shard a config text names (1 forest, 2 caves), 0 when it names none or is not a valid config.
def shard_named(+text: String) -> U32:
  parsed_shard(Json.parse(text))

def levels_of(entries: List<&2, Entry>) -> List<&2, Criteria>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Entry{level, _, _, _}, rest}:
      level <> levels_of(rest)

def laters_of(entries: List<&2, Entry>) -> List<&2, Rules.Later>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Entry{_, later, _, _}, rest}:
      later <> laters_of(rest)

def unsupported_of(entries: List<&2, Entry>) -> Maybe<&2, String>:
  match entries:
    case Nil{}:
      None{}
    case Con{Entry{_, _, Some{message}, _}, _}:
      Some{message}
    case Con{_, rest}:
      unsupported_of(rest)

def active_levels(entries: List<&2, Entry>) -> List<&2, Criteria>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Entry{level, _, _, False{}}, rest}:
      level <> active_levels(rest)
    case Con{_, rest}:
      active_levels(rest)

def some_active(+entries: List<&2, Entry>) -> Result<&1, &1, U32 & String, Unit>:
  Bool.pick(Result<&1, &1, U32 & String, Unit>, List.is_empty(&2, Entry, entries) || Bool.not(List.is_empty(&2, Criteria, active_levels(entries))), Done{Unit{}},
    Fail{Parse.failure("every criteria entry is passive (at least one must not be)")})

def config_from(+windows: Bool, +entries: List<&2, Entry>) -> Config:
  Config{windows, levels_of(entries), laters_of(entries), unsupported_of(entries), or_anything(active_levels(entries))}

# Compiles the JSON text of a search config (docs/config.md) into its platform, the part A criteria and
# parts B-E of every entry.
def config_of(+text: String) -> Result<&1, &1, U32 & String, Config>:
  do Result<&1, &1, U32 & String, Config>:
    json : Json.Json <- Json.parse(text)
    +fields : List<&2, Json.Json> <- Parse.keyed_fields(json, ["version", "platform", "settings", "criteria", "shard"], "the config")
    +windows : Bool <- platform_of(Parse.field(fields, "platform"))
    supported : Unit <- supported_version(Parse.field(fields, "version"))
    shard : U32 <- shard_of(Parse.field(fields, "shard"))
    settings : List<&2, Json.Json> <- Parse.optional_fields(Parse.field(fields, "settings"), "settings")
    defaults : Unit <- default_settings(settings)
    items : List<&2, Json.Json> <- Parse.optional_items(Parse.field(fields, "criteria"), "criteria")
    listed : List<&2, Json.Json> <- Parse.capped(items, 8, "entries", "criteria")
    +entries : List<&2, Entry> <- entry_list(listed, 0)
    active : Unit <- some_active(entries)
    return config_from(windows, entries)

# A config for a finder that only knows part A: the message when some entry has a counts/distances/tiles/routes key.
def level_table_only(+config: Config) -> Result<&1, &1, U32 & String, Config>:
  match config:
    case Config{_, _, _, None{}, _}:
      Done{config}
    case Config{_, _, _, Some{+message}, _}:
      Fail{(2, message)}

def tasks_hold(+c: Criteria, +chosen: U32, +swaps: U32) -> Bool:
  match c:
    case Criteria{+required, +excluded, +care, +want, _}:
      U32.is_zero(((required .&. U32.not(chosen)) .|. (excluded .&. chosen) .|. ((swaps .^. want) .&. care) : U32))

def any_tasks_hold(criteria: List<&2, Criteria>, +chosen: U32, +swaps: U32) -> Bool:
  match criteria:
    case Nil{}:
      False{}
    case Con{+c, rest}:
      tasks_hold(c, chosen, swaps) || any_tasks_hold(rest, chosen, swaps)

def selected(+id: U32, +index: U32) -> U32:
  Bool.to_u32(U32.is_eq(id, index))

# How many times a set piece can at most be placed, knowing only AddSetPeices' outcome.
def most_placed(+pieces: LevelSetpieces.Pieces, +piece: U32) -> U32:
  match pieces:
    case LevelSetpieces.Pieces{+trap, +poi, +protected, _, _, _, _}:
      +fixed = ((WorldCatalog.key_info(piece) >> 8n) .&. 15 : U32)
      Bool.pick(U32, (piece < WorldCatalog.first_boon_key() : U32), fixed,
      Bool.pick(U32, (piece <= WorldCatalog.first_trap_key() : U32), LevelSetpieces.boon_count(pieces, (piece - WorldCatalog.first_boon_key() : U32)),
      Bool.pick(U32, (piece <= WorldCatalog.first_poi_key() : U32), selected(trap, (piece - WorldCatalog.first_trap_key() : U32)),
      Bool.pick(U32, (piece <= WorldCatalog.first_protected_key() : U32), selected(poi, (piece - WorldCatalog.first_poi_key() : U32)),
      Bool.pick(U32, (piece < WorldCatalog.special_piece() : U32), selected(protected, (piece - WorldCatalog.first_protected_key() : U32)), 6)))))

def rules_possible(rules: List<&2, Rule>, +pieces: LevelSetpieces.Pieces) -> Bool:
  match rules:
    case Nil{}:
      True{}
    case Con{Rule{+piece, _, +low, _}, rest}:
      (low <= most_placed(pieces, piece) : U32) && rules_possible(rest, pieces)

def criteria_rules(+c: Criteria) -> List<&2, Rule>:
  match c:
    case Criteria{_, _, _, _, rules}:
      rules

def any_possible(criteria: List<&2, Criteria>, +chosen: U32, +swaps: U32, +pieces: LevelSetpieces.Pieces) -> Bool:
  match criteria:
    case Nil{}:
      False{}
    case Con{+c, rest}:
      (tasks_hold(c, chosen, swaps) && rules_possible(criteria_rules(c), pieces)) || any_possible(rest, chosen, swaps, pieces)

type Specials is Data:
  Specials{codes: U32, tasks: U32, count: U32}

def special_hits(n: Nat, +sp: Specials, +code: U32, +tasks: U32, +k: U32) -> U32:
  match n:
    case 0n:
      0
    case 1n+p:
      match sp:
        case Specials{+codes, +special_tasks, _}:
          +hit = U32.is_eq(LevelPrefix.field5(codes, k), code) && Bool.not(U32.is_zero((tasks .&. LevelPrefix.task_bit(LevelPrefix.field5(special_tasks, k)) : U32)))
          (Bool.to_u32(hit) + special_hits(p, sp, code, tasks, (k + 1 : U32)) : U32)

def special_placed(+sp: Specials, +code: U32, +tasks: U32) -> U32:
  match sp:
    case Specials{_, _, +count}:
      special_hits(U32.to_nat(count), sp, code, tasks, 0)

type Judging is Type:
  Judging{table: Array<U32>, holds: Bool}

def judge_count(got: Array<U32> & U32, holds: Bool, +rule: Rule, +sp: Specials) -> Judging:
  (table, +mask) = got
  match rule:
    case Rule{+piece, +tasks, +low, +high}:
      +special = (piece >= WorldCatalog.special_piece() : U32)
      +placed = Bool.pick(U32, special, special_placed(sp, (piece - WorldCatalog.special_piece() : U32), tasks), LevelChoose.popcount((mask .&. tasks : U32)))
      Judging{table, holds && (low <= placed : U32) && (placed <= high : U32)}

def rule_piece(+rule: Rule) -> U32:
  match rule:
    case Rule{+piece, _, _, _}:
      piece

def judge(+rule: Rule, st: Judging, +sp: Specials) -> Judging:
  match st:
    case Judging{table, holds}:
      judge_count(table[((LevelChoose.mask_slot() + rule_piece(rule)) .&. 127 : U32)], holds, rule, sp)

def rules_hold(rules: List<&2, Rule>, st: Judging, +sp: Specials) -> Judging:
  match rules:
    case Nil{}:
      st
    case Con{+rule, rest}:
      rules_hold(rest, judge(rule, st, sp), sp)

def either(any: Bool, judged: Judging) -> Judging:
  match judged:
    case Judging{table, holds}:
      Judging{table, any || holds}

def criterion_step(+c: Criteria, st: Judging, +chosen: U32, +swaps: U32, +sp: Specials) -> Judging:
  match st:
    case Judging{table, any}:
      either(any, rules_hold(criteria_rules(c), Judging{table, tasks_hold(c, chosen, swaps)}, sp))

def criteria_hold(criteria: List<&2, Criteria>, st: Judging, +chosen: U32, +swaps: U32, +sp: Specials) -> Judging:
  match criteria:
    case Nil{}:
      st
    case Con{+c, rest}:
      criteria_hold(rest, criterion_step(c, st, chosen, swaps, sp), chosen, swaps, sp)

def verdict(judged: Judging) -> Bool:
  match judged:
    case Judging{_, holds}:
      holds

def final_stage(+criteria: List<&2, Criteria>, w: LevelChoose.World) -> Bool:
  match w:
    case LevelChoose.World{+swaps, _, +chosen, _, table, _, +codes, +tasks, +count, crashed}:
      Bool.not(crashed) && verdict(criteria_hold(criteria, Judging{table, False{}}, chosen, swaps, Specials{codes, tasks, count}))

def choose_gate(pass: Bool, +criteria: List<&2, Criteria>, +swaps: U32, +lo: U32, +chosen: U32, +a: LevelChoose.Added) -> Bool:
  match pass:
    case False{}:
      False{}
    case True{}:
      final_stage(criteria, LevelChoose.choose(swaps, lo, chosen, a))

def added_stage(+criteria: List<&2, Criteria>, +swaps: U32, +lo: U32, +chosen: U32, +a: LevelChoose.Added) -> Bool:
  match a:
    case LevelChoose.Added{+pieces, _, _, _, _}:
      choose_gate(any_possible(criteria, chosen, swaps, pieces), criteria, swaps, lo, chosen, a)

def added_gate(pass: Bool, +criteria: List<&2, Criteria>, +swaps: U32, +lo: U32, +chosen: U32, rng: Pcg.Rng) -> Bool:
  match pass:
    case False{}:
      False{}
    case True{}:
      added_stage(criteria, swaps, lo, chosen, LevelChoose.added(rng))

def prefix_stage(+criteria: List<&2, Criteria>, p: LevelPrefix.Prefix) -> Bool:
  match p:
    case LevelPrefix.Prefix{+swaps, +lo, _, rng}:
      +chosen = LevelPrefix.chosen_tasks(lo)
      added_gate(any_tasks_hold(criteria, chosen, swaps), criteria, swaps, lo, chosen, rng)

# Stages bail out early: tasks and prefab swaps, then AddSetPeices counts, then ChooseSetPieces.
def matches(+criteria: List<&2, Criteria>, +seed: U32) -> Bool:
  prefix_stage(criteria, LevelPrefix.prefix(seed))

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
    case Con{Rule{+piece, +tasks, +low, +high}, rest}:
      Rule{piece, tasks, low, high} <> local_rules(rest)

# A private copy, so parallel workers do not share reference counts.
def local_criteria(criteria: List<&2, Criteria>) -> List<&2, Criteria>:
  match criteria:
    case Nil{}:
      Nil{}
    case Con{Criteria{+required, +excluded, +care, +want, rules}, rest}:
      Criteria{required, excluded, care, want, local_rules(rules)} <> local_criteria(rest)

