import Base
import ./world.bend as FilterWorld
import ./par.bend as Par
import ./rules.bend as Rules
import ./checks.bend as Checks
import ./bridges.bend as Bridges
import ./level_checks.bend as LevelChecks
import ../level/summary.bend as LevelSummary
import ../data/builds.bend as Builds

# One config evaluated on one world (evaluate.py): per filter the results of `generation`'s sections in the order
# tasks, prefab_swaps, setpieces, then the filter's world rules: the setpieces rules' `placed` names, counts, tiles, distances,
# bridges, routes; the world rules run in parallel.

type Job is Data:
  JPlaced{rule: Rules.Placed}
  JCount{index: U32, rule: Rules.Count}
  JTiles{index: U32, rule: Rules.Tiles}
  JDistance{index: U32, rule: Rules.Distance}
  JBridge{index: U32, rule: Rules.Bridge}
  JRoute{index: U32, rule: Rules.Route}

# A world with the game build it was generated for: the context the parallel rule checks share.
type BuildWorld is Data:
  BuildWorld{build: Builds.Build, world: FilterWorld.World}

# One result: whether it holds, whether it belongs to parts B-E, and its JSON object.
type Outcome is Data:
  Outcome{ok: Bool, later: Bool, json: String}

def result_json(+section: String, +index: U32, +ok: Bool, +fields: String) -> String:
  "{\"section\":\"" ++ section ++ "\",\"index\":" ++ U32.show(index) ++ ",\"ok\":" ++ Bool.pick(String, ok, "true", "false") ++ fields ++ "}"

def checked(+section: String, +index: U32, c: Checks.Check) -> Outcome:
  match c:
    case Checks.Check{+ok, +fields}:
      Outcome{ok, True{}, result_json(section, index, ok, fields)}

def run_job(+build: Builds.Build, +world: FilterWorld.World, job: Job) -> Outcome:
  match job:
    case JPlaced{+rule}:
      checked("setpieces", Rules.placed_index(rule), Checks.placed(build, world, rule))
    case JCount{+i, rule}:
      checked("counts", i, Checks.count(build, world, rule))
    case JTiles{+i, rule}:
      checked("tiles", i, Checks.tiles(world, rule))
    case JDistance{+i, rule}:
      checked("distances", i, Checks.distance(build, world, rule))
    case JBridge{+i, rule}:
      checked("bridges", i, Bridges.check(world, rule))
    case JRoute{+i, rule}:
      checked("routes", i, Checks.route(build, world, rule))

def job_outcome(on: BuildWorld, job: Job) -> Outcome:
  match on:
    case BuildWorld{+build, +world}:
      run_job(build, world, job)

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

def run_each(+build: Builds.Build, jobs: List<&2, Job>, +world: FilterWorld.World) -> List<&2, Outcome>:
  match jobs:
    case Nil{}:
      Nil{}
    case Con{job, rest}:
      run_job(build, world, job) <> run_each(build, rest, world)

# The outcomes of the jobs in order (the routes come last): the other rules spread over one balanced fork tree, the
# routes one after the other, since each forks its own Held-Karp stages and a fork inside a forked task would stay
# on that task's thread.
def parallel_jobs(+build: Builds.Build, +world: FilterWorld.World, +jobs: List<&2, Job>) -> List<&2, Outcome>:
  List.append(&2, Outcome, Par.map(~Job, ~Outcome, ~BuildWorld, ~job_outcome, BuildWorld{build, world}, only(jobs, False{}, Nil{})), run_each(build, only(jobs, True{}, Nil{}), world))

def check_ok(+c: Checks.Check) -> Bool:
  match c:
    case Checks.Check{+ok, _}:
      ok

def job_holds(+build: Builds.Build, +world: FilterWorld.World, job: Job) -> Bool:
  match job:
    case JPlaced{rule}:
      check_ok(Checks.placed(build, world, rule))
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

def job_verdict(on: BuildWorld, job: Job) -> Bool:
  match on:
    case BuildWorld{+build, +world}:
      job_holds(build, world, job)

def all_true(verdicts: List<&2, Bool>) -> Bool:
  match verdicts:
    case Nil{}:
      True{}
    case Con{+ok, rest}:
      ok && all_true(rest)

def routes_hold(+build: Builds.Build, jobs: List<&2, Job>, go: Bool, +world: FilterWorld.World) -> Bool:
  match jobs go:
    case Con{job, rest} True{}:
      routes_hold(build, rest, job_holds(build, world, job), world)
    case _ _:
      go

# holds(parallel_jobs(world, jobs)), from the verdicts alone.
def parallel_holds(+build: Builds.Build, +world: FilterWorld.World, +jobs: List<&2, Job>) -> Bool:
  routes_hold(build, only(jobs, True{}, Nil{}), all_true(Par.map(~Job, ~Bool, ~BuildWorld, ~job_verdict, BuildWorld{build, world}, only(jobs, False{}, Nil{}))), world)

def placed_jobs(rules: List<&2, Rules.Placed>) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JPlaced{rule} <> placed_jobs(rest)

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

# The jobs of the world rules in result order: setpieces, counts, tiles, distances, bridges, routes.
def jobs_of(later: Rules.Later) -> List<&2, Job>:
  match later:
    case Rules.Later{setpieces, counts, distances, tiles, bridges, routes}:
      List.concat(&2, Job, [placed_jobs(setpieces), count_jobs(counts, 0), tile_jobs(tiles, 0), distance_jobs(distances, 0), bridge_jobs(bridges, 0), route_jobs(routes, 0)])

def pair_outcome(+section: String, +index: U32, got: Bool & String) -> Outcome:
  (+ok, +fields) = got
  Outcome{ok, False{}, result_json(section, index, ok, fields)}

def setpiece_outcomes(rules: List<&2, LevelChecks.Setpiece>, +placed: List<&2, LevelChecks.Placed>, +i: U32) -> List<&2, Outcome>:
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

def shown_pieces(+shown: LevelChecks.Shown) -> List<&2, LevelChecks.Setpiece>:
  match shown:
    case LevelChecks.Shown{_, _, _, +pieces}:
      pieces

# The part A outcomes of an entry on a level table.
def level_outcomes(+build: Builds.Build, +shown: LevelChecks.Shown, +s: LevelSummary.Summary) -> List<&2, Outcome>:
  +placed = LevelChecks.placed(build, s)
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

def later_outcomes(+build: Builds.Build, skip: Bool, +world: FilterWorld.World, +later: Rules.Later) -> List<&2, Outcome>:
  match skip:
    case True{}:
      Nil{}
    case False{}:
      parallel_jobs(build, world, jobs_of(later))

# The outcomes of an entry whose part A outcomes are `level`.
def entry_outcomes_from(+build: Builds.Build, +level: List<&2, Outcome>, +later: Rules.Later, +world: FilterWorld.World, +fast: Bool) -> List<&2, Outcome>:
  +all = List.append(&2, Outcome, level, later_outcomes(build, fast && Bool.not(all_ok(level)), world, later))
  Bool.pick(List<&2, Outcome>, fast, until_failure(all), all)

def entry_outcomes(+build: Builds.Build, +shown: LevelChecks.Shown, +later: Rules.Later, +world: FilterWorld.World, +s: LevelSummary.Summary, +fast: Bool) -> List<&2, Outcome>:
  entry_outcomes_from(build, level_outcomes(build, shown, s), later, world, fast)

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

# A job's rule as the one rule of a filter.
def job_later(+job: Job) -> Rules.Later:
  match job:
    case JPlaced{+rule}:
      Rules.Later{[rule], Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}
    case JCount{_, +rule}:
      Rules.Later{Nil{}, [rule], Nil{}, Nil{}, Nil{}, Nil{}}
    case JTiles{_, +rule}:
      Rules.Later{Nil{}, Nil{}, Nil{}, [rule], Nil{}, Nil{}}
    case JDistance{_, +rule}:
      Rules.Later{Nil{}, Nil{}, [rule], Nil{}, Nil{}, Nil{}}
    case JBridge{_, +rule}:
      Rules.Later{Nil{}, Nil{}, Nil{}, Nil{}, [rule], Nil{}}
    case JRoute{_, +rule}:
      Rules.Later{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, [rule]}

def job_laters(jobs: List<&2, Job>) -> List<&2, Rules.Later>:
  match jobs:
    case Nil{}:
      Nil{}
    case Con{+job, rest}:
      job_later(job) <> job_laters(rest)

def is_count_or_distance(+job: Job) -> Bool:
  match job:
    case JCount{_, _}:
      True{}
    case JDistance{_, _}:
      True{}
    case _:
      False{}

# The early tier of a job (Rules.early_tier of what it reads): counts and distances only, the routes are left to the
# whole world.
def early_tier(+build: Builds.Build, +job: Job) -> U32:
  Bool.pick(U32, is_count_or_distance(job), Rules.early_tier(build, Rules.needs(build, [job_later(job)])), 0)

def tiered(+build: Builds.Build, jobs: List<&2, Job>, +tier: U32) -> List<&2, Job>:
  match jobs:
    case Nil{}:
      Nil{}
    case Con{+job, rest}:
      +tail = tiered(build, rest, tier)
      Bool.pick(List<&2, Job>, U32.is_eq(early_tier(build, job), tier), job <> tail, tail)

# The jobs of a filter's world rules that a caves world checks right after ConvertGround: its counts and distances of
# early tier 1, or of tier 2 (walks) when it has none of tier 1.
def early_jobs(+build: Builds.Build, +later: Rules.Later) -> List<&2, Job>:
  +jobs = jobs_of(later)
  +straight = tiered(build, jobs, 1)
  Bool.pick(List<&2, Job>, List.is_empty(&2, Job, straight), tiered(build, jobs, 2), straight)

# Whether `ok` and every job holds, checked one after the other up to the first that fails.
def all_hold(+build: Builds.Build, +world: FilterWorld.World, jobs: List<&2, Job>, ok: Bool) -> Bool:
  match jobs ok:
    case _ False{}:
      False{}
    case Nil{} True{}:
      True{}
    case Con{+job, rest} True{}:
      all_hold(build, world, rest, job_holds(build, world, job))
