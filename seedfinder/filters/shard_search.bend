import Base
import ./config.bend as Config
import ./cave_config.bend as CaveConfig
import ./rules.bend as Rules
import ./evaluate.bend as Evaluate
import ../level/summary.bend as LevelSummary
import ../level/cave_summary.bend as CaveSummary
import ../data/gen_tags.bend as GenTagsData
import ../data/builds.bend as Builds

# The part A criteria of either shard.
type Levels is Data:
  ForestLevels{criteria: List<&2, Config.Criteria>}
  CaveLevels{criteria: List<&2, CaveConfig.Criteria>}

# The early check of a caves search (search/generated.bend): per filter the jobs of its rules that a world checks right
# after ConvertGround (Evaluate.early_jobs), what they read, and the string ids of the prefabs they read.
type Early is Data:
  Early{jobs: List<&2, List<&2, Evaluate.Job>>, needs: Rules.Needs, sids: List<&2, U32>}

# A compiled search config of either shard as the world search sees it: the platform, the game build, the shard, the part A criteria
# of `generation` that pick the candidates, the parts B-E of every filter, what those read from a world, and the early
# check of a caves search whose every filter has early jobs (a world that fails one job of every filter is a miss).
type Search is Data:
  Search{windows: Bool, build: Builds.Build, caves: Bool, level: Levels, laters: List<&2, Rules.Later>, names: List<&2, String>, needs: Rules.Needs, early: Maybe<&2, Early>}

def of_forest(+config: Config.Config) -> Search:
  match config:
    case Config.Config{+windows, +build, +level, +laters, _, +names}:
      Search{windows, build, False{}, ForestLevels{[level]}, laters, names, Rules.needs(build, laters), None{}}

def early_jobs(+build: Builds.Build, laters: List<&2, Rules.Later>) -> List<&2, List<&2, Evaluate.Job>>:
  match laters:
    case Nil{}:
      Nil{}
    case Con{+later, rest}:
      Evaluate.early_jobs(build, later) <> early_jobs(build, rest)

def each_nonempty(jobs: List<&2, List<&2, Evaluate.Job>>) -> Bool:
  match jobs:
    case Nil{}:
      True{}
    case Con{+js, rest}:
      Bool.not(List.is_empty(&2, Evaluate.Job, js)) && each_nonempty(rest)

def sids_of(+all: List<&2, U32>, ids: List<&2, U32>) -> List<&2, U32>:
  match ids:
    case Nil{}:
      Nil{}
    case Con{+id, rest}:
      Maybe.default(&2, U32, List.get(&2, U32, all, U32.to_nat(id)), 0) <> sids_of(all, rest)

def early_of(+build: Builds.Build, +needs: Rules.Needs, +jobs: List<&2, List<&2, Evaluate.Job>>) -> Early:
  match needs:
    case Rules.Needs{+ids, _, _, _, _, _, _}:
      Early{jobs, needs, sids_of(List.append(&2, U32, GenTagsData.vocab_prefab_sids(build), GenTagsData.cave_vocab_prefab_sids(build)), ids)}

# The early check of a caves config: none when some filter has no early job or the config reads the level plan (which
# a caves world lacks, so no world is usable).
def early_check(+build: Builds.Build, +laters: List<&2, Rules.Later>) -> Maybe<&2, Early>:
  +jobs = early_jobs(build, laters)
  +on = each_nonempty(jobs) && Bool.not(Rules.needs_plan(laters))
  Bool.pick(Maybe<&2, Early>, on, Some{early_of(build, Rules.needs(build, Evaluate.job_laters(List.concat(&2, Evaluate.Job, jobs))), jobs)}, None{})

def of_caves(+config: CaveConfig.Config) -> Search:
  match config:
    case CaveConfig.Config{+windows, +build, +level, +laters, +names}:
      Search{windows, build, True{}, CaveLevels{[level]}, laters, names, Rules.needs(build, laters), early_check(build, laters)}

def windows(+search: Search) -> Bool:
  match search:
    case Search{+windows, _, _, _, _, _, _, _}:
      windows

def build(+search: Search) -> Builds.Build:
  match search:
    case Search{_, +build, _, _, _, _, _, _}:
      build

def caves(+search: Search) -> Bool:
  match search:
    case Search{_, _, +caves, _, _, _, _, _}:
      caves

def laters(+search: Search) -> List<&2, Rules.Later>:
  match search:
    case Search{_, _, _, _, +laters, _, _, _}:
      laters

def names(+search: Search) -> List<&2, String>:
  match search:
    case Search{_, _, _, _, _, +names, _, _}:
      names

def needs(+search: Search) -> Rules.Needs:
  match search:
    case Search{_, _, _, _, _, _, +needs, _}:
      needs

def early(+search: Search) -> Maybe<&2, Early>:
  match search:
    case Search{_, _, _, _, _, _, _, +early}:
      early

def level(+search: Search) -> Levels:
  match search:
    case Search{_, _, _, +level, _, _, _, _}:
      level

# The level table of `seed` as JSON, as `world show` prints it.
def summary_json(+build: Builds.Build, +caves: Bool, +seed: U32) -> String:
  Bool.pick(String, caves, CaveSummary.summary_json(build, seed), LevelSummary.summary_json(build, LevelSummary.summary(build, seed)))

def forest_leaf(+build: Builds.Build, n: Nat, +seed: U32, +criteria: List<&2, Config.Criteria>, +hits: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, hits)
    case 1n+p:
      forest_leaf(build, p, (seed + 1 : U32), criteria, Bool.pick(List<&2, U32>, Config.matches(build, criteria, seed), seed <> hits, hits))

def cave_leaf(+build: Builds.Build, n: Nat, +seed: U32, +criteria: List<&2, CaveConfig.Criteria>, +hits: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, hits)
    case 1n+p:
      cave_leaf(build, p, (seed + 1 : U32), criteria, Bool.pick(List<&2, U32>, CaveConfig.matches(build, criteria, seed), seed <> hits, hits))

# The seeds lo..lo+n-1 whose level table satisfies some of the criteria, in order, on one thread (a private copy of the criteria).
def candidates_leaf(+build: Builds.Build, levels: Levels, +lo: U32, n: Nat) -> List<&2, U32>:
  match levels:
    case ForestLevels{criteria}:
      forest_leaf(build, n, lo, Config.local_criteria(criteria), Nil{})
    case CaveLevels{criteria}:
      cave_leaf(build, n, lo, CaveConfig.local_criteria(criteria), Nil{})
