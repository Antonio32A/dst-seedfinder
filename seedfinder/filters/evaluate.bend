import Base
import ./world.bend as FilterWorld
import ./par.bend as Par
import ./rules.bend as Rules
import ./checks.bend as Checks
import ./bridges.bend as Bridges
import ./level_checks.bend as LevelChecks
import ../level/summary.bend as LevelSummary

# One config evaluated on one world (evaluate.py): per criteria entry the results of its sections in the order
# tasks, prefab_swaps, setpieces, counts, tiles, distances, bridges, routes; parts B-E run in parallel.

type Job is Data:
  JCount{index: U32, rule: Rules.Count}
  JTiles{index: U32, rule: Rules.Tiles}
  JDistance{index: U32, rule: Rules.Distance}
  JBridge{index: U32, rule: Rules.Bridge}
  JRoute{index: U32, rule: Rules.Route}

# One result: whether it holds, whether it belongs to parts B-E, and its JSON object.
type Outcome is Data:
  Outcome{ok: Bool, later: Bool, json: String}

def result_json(+section: String, +index: U32, +ok: Bool, +fields: String) -> String:
  "{\"section\":\"" ++ section ++ "\",\"index\":" ++ U32.show(index) ++ ",\"ok\":" ++ Bool.pick(String, ok, "true", "false") ++ fields ++ "}"

def checked(+section: String, +index: U32, c: Checks.Check) -> Outcome:
  match c:
    case Checks.Check{+ok, +fields}:
      Outcome{ok, True{}, result_json(section, index, ok, fields)}

def run_job(+world: FilterWorld.World, job: Job) -> Outcome:
  match job:
    case JCount{+i, rule}:
      checked("counts", i, Checks.count(world, rule))
    case JTiles{+i, rule}:
      checked("tiles", i, Checks.tiles(world, rule))
    case JDistance{+i, rule}:
      checked("distances", i, Checks.distance(world, rule))
    case JBridge{+i, rule}:
      checked("bridges", i, Bridges.check(world, rule))
    case JRoute{+i, rule}:
      checked("routes", i, Checks.route(world, rule))

def job_outcome(world: FilterWorld.World, job: Job) -> Outcome:
  run_job(world, job)

def is_route(+job: Job) -> Bool:
  match job:
    case JRoute{_, _}:
      True{}
    case _:
      False{}

def only(jobs: List<&2, Job>, +routes: Bool, +acc: List<&2, Job>) -> List<&2, Job>:
  match jobs:
    case Nil{}:
      List.reverse(&2, Job, acc)
    case Con{+job, rest}:
      only(rest, routes, Bool.pick(List<&2, Job>, Bool.xor(is_route(job), Bool.not(routes)), job <> acc, acc))

def run_each(jobs: List<&2, Job>, +world: FilterWorld.World) -> List<&2, Outcome>:
  match jobs:
    case Nil{}:
      Nil{}
    case Con{job, rest}:
      run_job(world, job) <> run_each(rest, world)

# The outcomes of the jobs in order (the routes come last): the other rules spread over one balanced fork tree, the
# routes one after the other, since each forks its own Held-Karp stages and a fork inside a forked task would stay
# on that task's thread.
def parallel_jobs(+world: FilterWorld.World, +jobs: List<&2, Job>) -> List<&2, Outcome>:
  List.append(&2, Outcome, Par.map(~Job, ~Outcome, ~FilterWorld.World, ~job_outcome, world, only(jobs, False{}, Nil{})), run_each(only(jobs, True{}, Nil{}), world))

def check_ok(+c: Checks.Check) -> Bool:
  match c:
    case Checks.Check{+ok, _}:
      ok

def job_holds(+world: FilterWorld.World, job: Job) -> Bool:
  match job:
    case JCount{_, rule}:
      Checks.count_holds(world, rule)
    case JTiles{_, rule}:
      check_ok(Checks.tiles(world, rule))
    case JDistance{_, rule}:
      Checks.distance_holds(world, rule)
    case JBridge{_, rule}:
      Bridges.holds(world, rule)
    case JRoute{_, rule}:
      Checks.route_holds(world, rule)

def job_verdict(world: FilterWorld.World, job: Job) -> Bool:
  job_holds(world, job)

def all_true(verdicts: List<&2, Bool>) -> Bool:
  match verdicts:
    case Nil{}:
      True{}
    case Con{+ok, rest}:
      ok && all_true(rest)

def routes_hold(jobs: List<&2, Job>, go: Bool, +world: FilterWorld.World) -> Bool:
  match jobs go:
    case Con{job, rest} True{}:
      routes_hold(rest, job_holds(world, job), world)
    case _ _:
      go

# holds(parallel_jobs(world, jobs)), from the verdicts alone.
def parallel_holds(+world: FilterWorld.World, +jobs: List<&2, Job>) -> Bool:
  routes_hold(only(jobs, True{}, Nil{}), all_true(Par.map(~Job, ~Bool, ~FilterWorld.World, ~job_verdict, world, only(jobs, False{}, Nil{}))), world)

def count_jobs(rules: List<&2, Rules.Count>, +i: U32) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JCount{i, rule} <> count_jobs(rest, (i + 1 : U32))

def tile_jobs(rules: List<&2, Rules.Tiles>, +i: U32) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JTiles{i, rule} <> tile_jobs(rest, (i + 1 : U32))

def distance_jobs(rules: List<&2, Rules.Distance>, +i: U32) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JDistance{i, rule} <> distance_jobs(rest, (i + 1 : U32))

def bridge_jobs(rules: List<&2, Rules.Bridge>, +i: U32) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JBridge{i, rule} <> bridge_jobs(rest, (i + 1 : U32))

def route_jobs(rules: List<&2, Rules.Route>, +i: U32) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JRoute{i, rule} <> route_jobs(rest, (i + 1 : U32))

# The jobs of parts B-E in result order: counts, tiles, distances, bridges, routes.
def jobs_of(later: Rules.Later) -> List<&2, Job>:
  match later:
    case Rules.Later{counts, distances, tiles, bridges, routes}:
      List.concat(&2, Job, [count_jobs(counts, 0), tile_jobs(tiles, 0), distance_jobs(distances, 0), bridge_jobs(bridges, 0), route_jobs(routes, 0)])

def pair_outcome(+section: String, +index: U32, got: Bool & String) -> Outcome:
  (+ok, +fields) = got
  Outcome{ok, False{}, result_json(section, index, ok, fields)}

def setpiece_outcomes(rules: List<&2, LevelChecks.Pieces>, +placed: List<&2, LevelChecks.Placed>, +i: U32) -> List<&2, Outcome>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{+rule, rest}:
      pair_outcome("setpieces", i, LevelChecks.setpiece_check(rule, placed)) <> setpiece_outcomes(rest, placed, (i + 1 : U32))

def has_tasks(+shown: LevelChecks.Shown) -> Bool:
  match shown:
    case LevelChecks.Shown{+required, +excluded, _, _}:
      Bool.not(List.is_empty(&2, String, required) && List.is_empty(&2, String, excluded))

def has_swaps(+shown: LevelChecks.Shown) -> Bool:
  match shown:
    case LevelChecks.Shown{_, _, +swaps, _}:
      Bool.not(List.is_empty(&2, LevelChecks.Swap, swaps))

def shown_pieces(+shown: LevelChecks.Shown) -> List<&2, LevelChecks.Pieces>:
  match shown:
    case LevelChecks.Shown{_, _, _, +pieces}:
      pieces

# The part A outcomes of an entry on a level table.
def level_outcomes(+shown: LevelChecks.Shown, +s: LevelSummary.Summary) -> List<&2, Outcome>:
  +placed = LevelChecks.placed(s)
  +tasks = Bool.pick(List<&2, Outcome>, has_tasks(shown), [pair_outcome("tasks", 0, LevelChecks.tasks_check(shown, placed))], Nil{})
  +swaps = Bool.pick(List<&2, Outcome>, has_swaps(shown), [pair_outcome("prefab_swaps", 0, LevelChecks.swaps_check(shown, s))], Nil{})
  List.concat(&2, Outcome, [tasks, swaps, setpiece_outcomes(shown_pieces(shown), placed, 0)])

def until_failure(outcomes: List<&2, Outcome>) -> List<&2, Outcome>:
  match outcomes:
    case Nil{}:
      Nil{}
    case Con{Outcome{+ok, +later, +json}, rest}:
      Outcome{ok, later, json} <> Bool.pick(List<&2, Outcome>, ok, until_failure(rest), Nil{})

def all_ok(outcomes: List<&2, Outcome>) -> Bool:
  match outcomes:
    case Nil{}:
      True{}
    case Con{Outcome{+ok, _, _}, rest}:
      ok && all_ok(rest)

def later_outcomes(skip: Bool, +world: FilterWorld.World, +later: Rules.Later) -> List<&2, Outcome>:
  match skip:
    case True{}:
      Nil{}
    case False{}:
      parallel_jobs(world, jobs_of(later))

# The outcomes of an entry whose part A outcomes are `level`.
def entry_outcomes_from(+level: List<&2, Outcome>, +later: Rules.Later, +world: FilterWorld.World, +fast: Bool) -> List<&2, Outcome>:
  +all = List.append(&2, Outcome, level, later_outcomes(fast && Bool.not(all_ok(level)), world, later))
  Bool.pick(List<&2, Outcome>, fast, until_failure(all), all)

def entry_outcomes(+shown: LevelChecks.Shown, +later: Rules.Later, +world: FilterWorld.World, +s: LevelSummary.Summary, +fast: Bool) -> List<&2, Outcome>:
  entry_outcomes_from(level_outcomes(shown, s), later, world, fast)

def outcome_texts(outcomes: List<&2, Outcome>, +later_only: Bool) -> List<&2, String>:
  match outcomes:
    case Nil{}:
      Nil{}
    case Con{Outcome{_, +later, +json}, rest}:
      +tail = outcome_texts(rest, later_only)
      Bool.pick(List<&2, String>, later || Bool.not(later_only), json <> tail, tail)

# The results array of an entry (only parts B-E when later_only, for search hits).
def results_json(+outcomes: List<&2, Outcome>, +later_only: Bool) -> String:
  "[" ++ String.join(outcome_texts(outcomes, later_only), ",") ++ "]"

# Whether every outcome holds.
def holds(+outcomes: List<&2, Outcome>) -> Bool:
  all_ok(outcomes)
