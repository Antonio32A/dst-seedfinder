import Base
import ./world.bend as WD
import ./par.bend as PX
import ./rules.bend as RU
import ./checks.bend as CK
import ./level_checks.bend as LC
import ../level/summary.bend as W

# One config evaluated on one world (evaluate.py): per criteria entry the results of its sections in the order
# tasks, prefab_swaps, setpieces, counts, tiles, distances, routes; parts B-E run in parallel.

type Job is Data:
  JCount{index: U32, rule: RU.Count}
  JTiles{index: U32, rule: RU.Tiles}
  JDistance{index: U32, rule: RU.Distance}
  JRoute{index: U32, rule: RU.Route}

# One result: whether it holds, whether it belongs to parts B-E, and its JSON object.
type Outcome is Data:
  Outcome{ok: Bool, later: Bool, json: String}

def result_json(+section: String, +index: U32, +ok: Bool, +fields: String) -> String:
  "{\"section\":\"" ++ section ++ "\",\"index\":" ++ U32.show(index) ++ ",\"ok\":" ++ Bool.pick(String, ok, "true", "false") ++ fields ++ "}"

def checked(+section: String, +index: U32, c: CK.Check) -> Outcome:
  match c:
    case CK.Check{+ok, +fields}:
      Outcome{ok, True{}, result_json(section, index, ok, fields)}

def run_job(+world: WD.World, job: Job) -> Outcome:
  match job:
    case JCount{+i, rule}:
      checked("counts", i, CK.count(world, rule))
    case JTiles{+i, rule}:
      checked("tiles", i, CK.tiles(world, rule))
    case JDistance{+i, rule}:
      checked("distances", i, CK.distance(world, rule))
    case JRoute{+i, rule}:
      checked("routes", i, CK.route(world, rule))

def job_outcome(world: WD.World, job: Job) -> Outcome:
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

def run_each(jobs: List<&2, Job>, +world: WD.World) -> List<&2, Outcome>:
  match jobs:
    case Nil{}:
      Nil{}
    case Con{job, rest}:
      run_job(world, job) <> run_each(rest, world)

# The outcomes of the jobs in order (the routes come last): the other rules spread over one balanced fork tree, the
# routes one after the other, since each forks its own Held-Karp stages and a fork inside a forked task would stay
# on that task's thread.
def parallel_jobs(+world: WD.World, +jobs: List<&2, Job>) -> List<&2, Outcome>:
  List.append(&2, Outcome, PX.map(~Job, ~Outcome, ~WD.World, ~job_outcome, world, only(jobs, False{}, Nil{})), run_each(only(jobs, True{}, Nil{}), world))

def count_jobs(rules: List<&2, RU.Count>, +i: U32) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JCount{i, rule} <> count_jobs(rest, (i + 1 : U32))

def tile_jobs(rules: List<&2, RU.Tiles>, +i: U32) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JTiles{i, rule} <> tile_jobs(rest, (i + 1 : U32))

def distance_jobs(rules: List<&2, RU.Distance>, +i: U32) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JDistance{i, rule} <> distance_jobs(rest, (i + 1 : U32))

def route_jobs(rules: List<&2, RU.Route>, +i: U32) -> List<&2, Job>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{rule, rest}:
      JRoute{i, rule} <> route_jobs(rest, (i + 1 : U32))

# The jobs of parts B-E in result order: counts, tiles, distances, routes.
def jobs_of(later: RU.Later) -> List<&2, Job>:
  match later:
    case RU.Later{counts, distances, tiles, routes}:
      List.concat(&2, Job, [count_jobs(counts, 0), tile_jobs(tiles, 0), distance_jobs(distances, 0), route_jobs(routes, 0)])

def pair_outcome(+section: String, +index: U32, got: Bool & String) -> Outcome:
  (+ok, +fields) = got
  Outcome{ok, False{}, result_json(section, index, ok, fields)}

def setpiece_outcomes(rules: List<&2, LC.Pieces>, +placed: List<&2, LC.Placed>, +i: U32) -> List<&2, Outcome>:
  match rules:
    case Nil{}:
      Nil{}
    case Con{+rule, rest}:
      pair_outcome("setpieces", i, LC.setpiece_check(rule, placed)) <> setpiece_outcomes(rest, placed, (i + 1 : U32))

def has_tasks(+shown: LC.Shown) -> Bool:
  match shown:
    case LC.Shown{+required, +excluded, _, _}:
      Bool.not(List.is_empty(&2, String, required) && List.is_empty(&2, String, excluded))

def has_swaps(+shown: LC.Shown) -> Bool:
  match shown:
    case LC.Shown{_, _, +swaps, _}:
      Bool.not(List.is_empty(&2, LC.Swap, swaps))

def shown_pieces(+shown: LC.Shown) -> List<&2, LC.Pieces>:
  match shown:
    case LC.Shown{_, _, _, +pieces}:
      pieces

# The part A outcomes of an entry on a level table.
def level_outcomes(+shown: LC.Shown, +s: W.Summary) -> List<&2, Outcome>:
  +placed = LC.placed(s)
  +tasks = Bool.pick(List<&2, Outcome>, has_tasks(shown), [pair_outcome("tasks", 0, LC.tasks_check(shown, placed))], Nil{})
  +swaps = Bool.pick(List<&2, Outcome>, has_swaps(shown), [pair_outcome("prefab_swaps", 0, LC.swaps_check(shown, s))], Nil{})
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

def later_outcomes(skip: Bool, +world: WD.World, +later: RU.Later) -> List<&2, Outcome>:
  match skip:
    case True{}:
      Nil{}
    case False{}:
      parallel_jobs(world, jobs_of(later))

def entry_outcomes(+shown: LC.Shown, +later: RU.Later, +world: WD.World, +s: W.Summary, +fast: Bool) -> List<&2, Outcome>:
  +level = level_outcomes(shown, s)
  +all = List.append(&2, Outcome, level, later_outcomes(fast && Bool.not(all_ok(level)), world, later))
  Bool.pick(List<&2, Outcome>, fast, until_failure(all), all)

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
