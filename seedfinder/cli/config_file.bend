import Base
import ../filters/config.bend as Config
import ../filters/cave_config.bend as CaveConfig
import ./files.bend as Files

# A search config compiled for its shard: the --shard flag decides, else the config's own `shard`, else the forest.
type Loaded is Data:
  Forest{config: Config.Config}
  Caves{config: CaveConfig.Config}

def shard_of(+flag: U32, +text: String) -> U32:
  Bool.pick(U32, U32.is_zero(flag), Bool.pick(U32, U32.is_eq(Config.shard_named(text), 2), 2, 1), flag)

def forest_loaded(compiled: Result<&1, &1, U32 & String, Config.Config>) -> Result<&1, &1, U32 & String, Loaded>:
  match compiled:
    case Fail{failure}:
      Fail{failure}
    case Done{config}:
      Done{Forest{config}}

def caves_loaded(compiled: Result<&1, &1, U32 & String, CaveConfig.Config>) -> Result<&1, &1, U32 & String, Loaded>:
  match compiled:
    case Fail{failure}:
      Fail{failure}
    case Done{config}:
      Done{Caves{config}}

def compiled_for(caves: Bool, +json: String) -> Result<&1, &1, U32 & String, Loaded>:
  match caves:
    case True{}:
      caves_loaded(CaveConfig.config_of(json))
    case False{}:
      forest_loaded(Config.config_of(json))

def compiled(+flag: U32, text: Result<&1, &1, U32 & String, String>) -> Result<&1, &1, U32 & String, Loaded>:
  match text:
    case Fail{failure}:
      Fail{failure}
    case Done{+json}:
      compiled_for(U32.is_eq(shard_of(flag, json), 2), json)

# Reads and compiles the config file (none: the config that matches every seed) for the shard `flag` names (0: the config's).
def load_config(path: Maybe<&2, String>, +flag: U32) -> IO(Result<&1, &1, U32 & String, Loaded>):
  match path:
    case None{}:
      IO.pure(Result<&1, &1, U32 & String, Loaded>, compiled(flag, Done{"{}"}))
    case Some{+file}:
      do IO<Result<&1, &1, U32 & String, Loaded>>:
        text : Result<&1, &1, U32 & String, String> <- Files.read_text("config: ", file)
        IO.pure(Result<&1, &1, U32 & String, Loaded>, compiled(flag, text))
