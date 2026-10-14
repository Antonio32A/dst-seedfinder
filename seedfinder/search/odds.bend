import Base
import ../data/world_catalog.bend as WorldCatalog
import ../data/cave_catalog.bend as CaveCatalog
import ../filters/config.bend as Config
import ../filters/cave_config.bend as CaveConfig
import ../filters/shard_search.bend as ShardSearch
import ../cli/config_file.bend as ConfigFile
import ../level/summary.bend as LevelSummary
import ../level/prefix.bend as LevelPrefix
import ../level/cave_choose.bend as CaveChoose
import ../level/cave_prefix.bend as CavePrefix
import ./common.bend as SearchCommon
import ../data/builds.bend as Builds

# `world odds`: how many seeds of a range choose each task and place each set piece (at least once), and how many are
# candidates of the config (its part A, docs/config.md section 1), from the level table alone. The counters of a range
# are one array: slot 0 counts the seeds whose level table exists, then tasks, set piece keys and random set pieces at
# the bases below, and the candidates in the last slot.

def slots() -> Nat:
  256n

def task_base() -> U32:
  1

def key_base() -> U32:
  64

def special_base() -> U32:
  128

def candidate_slot() -> U32:
  255

def chunk_size() -> Nat:
  131072n

def bump_read(got: Array<U32> & U32, +i: U32) -> Array<U32>:
  (counters, +n) = got
  counters[i] <- (n + 1 : U32)

def bump(counters: Array<U32>, +i: U32) -> Array<U32>:
  bump_read(counters[i], i)

def bump_when(placed: Bool, counters: Array<U32>, +i: U32) -> Array<U32>:
  match placed:
    case True{}:
      bump(counters, i)
    case False{}:
      counters

def count_tasks(+build: Builds.Build, n: Nat, counters: Array<U32>, +lo: U32, +c: U32) -> Array<U32>:
  match n:
    case 0n:
      counters
    case 1n+p:
      count_tasks(build, p, bump(counters, (task_base() + LevelPrefix.chosen_task(build, lo, c) : U32)), lo, (c + 1 : U32))

def count_entries(entries: List<&2, U32>, counters: Array<U32>) -> Array<U32>:
  match entries:
    case Nil{}:
      counters
    case Con{+entry, rest}:
      count_entries(rest, bump_when(Bool.not(U32.is_zero((entry >> 6n : U32))), counters, (key_base() + (entry .&. 63 : U32) : U32)))

def count_specials(n: Nat, counters: Array<U32>, +codes: U32, +k: U32, +seen: U32) -> Array<U32>:
  match n:
    case 0n:
      counters
    case 1n+p:
      +code = LevelPrefix.field5(codes, k)
      +bit = (1 << U32.to_nat(code) : U32)
      count_specials(p, bump_when(U32.is_zero((seen .&. bit : U32)), counters, (special_base() + code : U32)), codes, (k + 1 : U32), (seen .|. bit : U32))

def forest_level(+build: Builds.Build, crashed: Bool, +lo: U32, entries: List<&2, U32>, +codes: U32, +count: U32, counters: Array<U32>) -> Array<U32>:
  match crashed:
    case True{}:
      counters
    case False{}:
      count_specials(U32.to_nat(count), count_entries(entries, count_tasks(build, LevelSummary.chosen_count(), bump(counters, 0), lo, 0)), codes, 0, 0)

def forest_world(+build: Builds.Build, s: LevelSummary.Summary, counters: Array<U32>) -> Array<U32>:
  match s:
    case LevelSummary.Summary{_, +lo, entries, +codes, _, +count, crashed}:
      forest_level(build, crashed, lo, entries, codes, count, counters)

def count_chosen(tasks: List<&2, U32>, counters: Array<U32>) -> Array<U32>:
  match tasks:
    case Nil{}:
      counters
    case Con{+task, rest}:
      count_chosen(rest, bump(counters, (task_base() + task : U32)))

def count_added(entries: List<&2, CaveChoose.Entry>, counters: Array<U32>) -> Array<U32>:
  match entries:
    case Nil{}:
      counters
    case Con{CaveChoose.Entry{+key, +count, _}, rest}:
      count_added(rest, bump_when(Bool.not(U32.is_zero(count)), counters, (key_base() + key : U32)))

def cave_crashed(+c: CavePrefix.Chosen) -> Bool:
  match c:
    case CavePrefix.Chosen{_, _, CavePrefix.Masks{_, _, _, +crashed}, _}:
      crashed

def cave_picks(+c: CavePrefix.Chosen) -> List<&2, U32>:
  match c:
    case CavePrefix.Chosen{_, +picks, _, _}:
      picks

def cave_level(+build: Builds.Build, crashed: Bool, +c: CavePrefix.Chosen, counters: Array<U32>) -> Array<U32>:
  match crashed:
    case True{}:
      counters
    case False{}:
      count_added(CaveChoose.added_entries(build, c), count_chosen(CavePrefix.chosen_ids(build, cave_picks(c)), bump(counters, 0)))

def cave_world(+build: Builds.Build, +c: CavePrefix.Chosen, counters: Array<U32>) -> Array<U32>:
  cave_level(build, cave_crashed(c), c, counters)

def is_caves(+levels: ShardSearch.Levels) -> Bool:
  match levels:
    case ShardSearch.ForestLevels{_}:
      False{}
    case ShardSearch.CaveLevels{_}:
      True{}

def is_candidate(+build: Builds.Build, +levels: ShardSearch.Levels, +seed: U32) -> Bool:
  match levels:
    case ShardSearch.ForestLevels{criteria}:
      Config.matches(build, criteria, seed)
    case ShardSearch.CaveLevels{criteria}:
      CaveConfig.matches(build, criteria, seed)

def local_levels(levels: ShardSearch.Levels) -> ShardSearch.Levels:
  match levels:
    case ShardSearch.ForestLevels{criteria}:
      ShardSearch.ForestLevels{Config.local_criteria(criteria)}
    case ShardSearch.CaveLevels{criteria}:
      ShardSearch.CaveLevels{CaveConfig.local_criteria(criteria)}

def count_level(+build: Builds.Build, +caves: Bool, +seed: U32, counters: Array<U32>) -> Array<U32>:
  match caves:
    case True{}:
      cave_world(build, CavePrefix.chosen(build, seed), counters)
    case False{}:
      forest_world(build, LevelSummary.summary(build, seed), counters)

def count_seed(+build: Builds.Build, +levels: ShardSearch.Levels, +seed: U32, counters: Array<U32>) -> Array<U32>:
  count_level(build, is_caves(levels), seed, bump_when(is_candidate(build, levels, seed), counters, candidate_slot()))

def scan(+build: Builds.Build, n: Nat, +levels: ShardSearch.Levels, +seed: U32, counters: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      counters
    case 1n+p:
      scan(build, p, levels, (seed + 1 : U32), count_seed(build, levels, seed, counters))

type Merging is Type:
  Merging{into: Array<U32>, from: Array<U32>}

def merge_write(got: Array<U32> & U32, +i: U32, +x: U32, from: Array<U32>) -> Merging:
  (into, +y) = got
  into[i] <- (x + y : U32)
  Merging{into, from}

def merge_read(got: Array<U32> & U32, +i: U32, into: Array<U32>) -> Merging:
  (from, +x) = got
  merge_write(into[i], i, x, from)

def merge_step(st: Merging, +i: U32) -> Merging:
  match st:
    case Merging{into, from}:
      merge_read(from[i], i, into)

def merge_loop(n: Nat, st: Merging, +i: U32) -> Merging:
  match n:
    case 0n:
      st
    case 1n+p:
      merge_loop(p, merge_step(st, i), (i + 1 : U32))

def merged_into(st: Merging) -> Array<U32>:
  match st:
    case Merging{into, _}:
      into

def merged(a: Array<U32>, b: Array<U32>) -> Array<U32>:
  merged_into(merge_loop(slots(), Merging{a, b}, 0))

def search(+build: Builds.Build, +depth: Nat, +levels: ShardSearch.Levels, +lo: U32, +n: Nat) -> Array<U32>:
  match depth:
    case 0n:
      scan(build, n, local_levels(levels), lo, [0 : U32*256n])
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = search(build, d, levels, lo, half) search(build, d, levels, (lo + U32.from_nat(half) : U32), Nat.sub(n, half))
      merged(a, b)

type Counted is Type:
  Counted{counters: Array<U32>, counts: List<&2, U32>}

def count_read(got: Array<U32> & U32, counts: List<&2, U32>) -> Counted:
  (counters, +n) = got
  Counted{counters, n <> counts}

def count_step(st: Counted, +i: U32) -> Counted:
  match st:
    case Counted{counters, counts}:
      count_read(counters[i], counts)

def count_loop(n: Nat, st: Counted, +i: U32) -> Counted:
  match n:
    case 0n:
      st
    case 1n+p:
      count_loop(p, count_step(st, i), (i + 1 : U32))

def counted_list(st: Counted) -> List<&2, U32>:
  match st:
    case Counted{_, counts}:
      List.reverse(&2, U32, counts)

def counts_of(counters: Array<U32>) -> List<&2, U32>:
  counted_list(count_loop(slots(), Counted{counters, Nil{}}, 0))

def count_at(+counts: List<&2, U32>, +i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, counts, U32.to_nat(i)), 0)

def quoted(+s: String) -> String:
  "\"" ++ s ++ "\""

def item(+name: String, +count: U32, +tail: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_zero(count), tail, (quoted(name) ++ ":" ++ U32.show(count)) <> tail)

def task_name(+build: Builds.Build, +caves: Bool, +id: U32) -> String:
  Bool.pick(String, caves, CaveCatalog.task_name(build, id), WorldCatalog.task_name(build, id))

def key_name(+build: Builds.Build, +caves: Bool, +key: U32) -> String:
  Bool.pick(String, caves, CaveCatalog.key_name(build, key), WorldCatalog.key_name(build, key))

def task_items(+build: Builds.Build, n: Nat, +caves: Bool, +counts: List<&2, U32>, +id: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      item(task_name(build, caves, id), count_at(counts, (task_base() + id : U32)), task_items(build, p, caves, counts, (id + 1 : U32)))

def key_items(+build: Builds.Build, n: Nat, +caves: Bool, +counts: List<&2, U32>, +key: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      item(key_name(build, caves, key), count_at(counts, (key_base() + key : U32)), key_items(build, p, caves, counts, (key + 1 : U32)))

def special_items(+build: Builds.Build, n: Nat, +counts: List<&2, U32>, +code: U32) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      item(WorldCatalog.special_name(build, code), count_at(counts, (special_base() + code : U32)), special_items(build, p, counts, (code + 1 : U32)))

def odds_json(+build: Builds.Build, +caves: Bool, +counts: List<&2, U32>) -> String:
  "{\"seeds\":" ++ U32.show(count_at(counts, 0)) ++ ",\"candidates\":" ++ U32.show(count_at(counts, candidate_slot()))
    ++ ",\"tasks\":{" ++ String.join(task_items(build, 52n, caves, counts, 0), ",")
    ++ "},\"setpieces\":{" ++ String.join(List.append(&2, String, key_items(build, 63n, caves, counts, 1), special_items(build, 21n, counts, 0)), ",") ++ "}}"

type Chunked is Type:
  Chunked{counters: Array<U32>, valid: U32}

def chunk_read(got: Array<U32> & U32) -> Chunked:
  (counters, +valid) = got
  Chunked{counters, valid}

def chunked(counters: Array<U32>) -> Chunked:
  chunk_read(counters[0])

def finish(+build: Builds.Build, +caves: Bool, st: Chunked) -> IO(Unit):
  match st:
    case Chunked{counters, _}:
      IO.print("odds " ++ odds_json(build, caves, counts_of(counters)))

def next_chunk(+build: Builds.Build, st: Chunked, +levels: ShardSearch.Levels, +lo: U32, +len: Nat) -> Chunked:
  match st:
    case Chunked{counters, _}:
      chunked(merged(counters, search(build, SearchCommon.search_depth(), levels, lo, len)))

def run_chunks(+build: Builds.Build, k: Nat, st: Chunked, +levels: ShardSearch.Levels, +lo: U32, +left: Nat, +total: Nat, +started_ms: Nat) -> IO(Unit):
  match k st:
    case 0n _:
      finish(build, is_caves(levels), st)
    case 1n+p Chunked{counters, +valid}:
      +len = Nat.min(chunk_size(), left)
      do IO<Unit>:
        now : Nat <- IO.now()
        IO.print_err(SearchCommon.progress_line(Nat.sub(total, left), total, valid, Nat.sub(now, started_ms)))
        run_chunks(build, p, next_chunk(build, Chunked{counters, valid}, levels, lo, len), levels, (lo + U32.from_nat(len) : U32),
          Nat.sub(left, len), total, started_ms)

def chunk_count(+n: Nat) -> Nat:
  Nat.div(Nat.add(n, Nat.sub(chunk_size(), 1n)), chunk_size())

def levels_of(loaded: ConfigFile.Loaded) -> ShardSearch.Levels:
  match loaded:
    case ConfigFile.Forest{Config.Config{_, _, +level, _, _, _}}:
      ShardSearch.ForestLevels{[level]}
    case ConfigFile.Caves{CaveConfig.Config{_, _, +level, _, _}}:
      ShardSearch.CaveLevels{[level]}

def run(+build: Builds.Build, loaded: ConfigFile.Loaded, +from: U32, +to: U32) -> IO(Unit):
  +total = Nat.add(U32.to_nat((to - from : U32)), 1n)
  +levels = levels_of(loaded)
  do IO<Unit>:
    started : Nat <- IO.now()
    run_chunks(build, chunk_count(total), Chunked{[0 : U32*256n], 0}, levels, from, total, total, started)
