import Base
import ./config.bend as Config
import ./cave_config.bend as CaveConfig
import ./rules.bend as Rules
import ../level/summary.bend as LevelSummary
import ../level/cave_summary.bend as CaveSummary

# The part A criteria of either shard.
type Levels is Data:
  ForestLevels{criteria: List<&2, Config.Criteria>}
  CaveLevels{criteria: List<&2, CaveConfig.Criteria>}

# A compiled search config of either shard as the world search sees it: the platform, the shard, the part A criteria
# of `generation` that pick the candidates, and the parts B-E of every filter.
type Search is Data:
  Search{windows: Bool, caves: Bool, level: Levels, laters: List<&2, Rules.Later>}

def of_forest(+config: Config.Config) -> Search:
  match config:
    case Config.Config{+windows, +level, +laters, _}:
      Search{windows, False{}, ForestLevels{[level]}, laters}

def of_caves(+config: CaveConfig.Config) -> Search:
  match config:
    case CaveConfig.Config{+windows, +level, +laters}:
      Search{windows, True{}, CaveLevels{[level]}, laters}

def windows(+search: Search) -> Bool:
  match search:
    case Search{+windows, _, _, _}:
      windows

def caves(+search: Search) -> Bool:
  match search:
    case Search{_, +caves, _, _}:
      caves

def laters(+search: Search) -> List<&2, Rules.Later>:
  match search:
    case Search{_, _, _, +laters}:
      laters

def level(+search: Search) -> Levels:
  match search:
    case Search{_, _, +level, _}:
      level

# The level table of `seed` as JSON, as `world show` prints it.
def summary_json(+caves: Bool, +seed: U32) -> String:
  Bool.pick(String, caves, CaveSummary.summary_json(seed), LevelSummary.summary_json(LevelSummary.summary(seed)))

def forest_leaf(n: Nat, +seed: U32, +criteria: List<&2, Config.Criteria>, +hits: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, hits)
    case 1n+p:
      forest_leaf(p, (seed + 1 : U32), criteria, Bool.pick(List<&2, U32>, Config.matches(criteria, seed), seed <> hits, hits))

def cave_leaf(n: Nat, +seed: U32, +criteria: List<&2, CaveConfig.Criteria>, +hits: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, hits)
    case 1n+p:
      cave_leaf(p, (seed + 1 : U32), criteria, Bool.pick(List<&2, U32>, CaveConfig.matches(criteria, seed), seed <> hits, hits))

# The seeds lo..lo+n-1 whose level table satisfies some of the criteria, in order, on one thread (a private copy of the criteria).
def candidates_leaf(levels: Levels, +lo: U32, n: Nat) -> List<&2, U32>:
  match levels:
    case ForestLevels{criteria}:
      forest_leaf(n, lo, Config.local_criteria(criteria), Nil{})
    case CaveLevels{criteria}:
      cave_leaf(n, lo, CaveConfig.local_criteria(criteria), Nil{})
