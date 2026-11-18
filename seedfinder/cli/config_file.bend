import Base
import ../filters/config.bend as Config
import ../filters/cave_config.bend as CaveConfig
import ./files.bend as Files
import ./args.bend as Args
import ../data/builds.bend as Builds

# A search config compiled for its shard: the --shard flag decides, else the config's own `shard`, else the forest.
type Loaded is Data:
  Forest{config: Config.Config}
  Caves{config: CaveConfig.Config}

def shard_of(unflagged: Bool, +flag: U32, +text: String) -> U32:
  match unflagged:
    case True{}:
      Bool.pick(U32, U32.is_eq(Config.shard_named(text), 2), 2, 1)
    case False{}:
      flag

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

def build_of(+loaded: Loaded) -> Builds.Build:
  match loaded:
    case Forest{Config.Config{_, +build, _, _, _, _}}:
      build
    case Caves{CaveConfig.Config{_, +build, _, _, _}}:
      build

def compiled_for(caves: Bool, +json: String, +build: Maybe<&2, Builds.Build>) -> Result<&1, &1, U32 & String, Loaded>:
  match caves:
    case True{}:
      caves_loaded(CaveConfig.config_of(json, build))
    case False{}:
      forest_loaded(Config.config_of(json, build))

def compiled(+flag: U32, +build: Maybe<&2, Builds.Build>, text: Result<&1, &1, U32 & String, String>) -> Result<&1, &1, U32 & String, Loaded>:
  match text:
    case Fail{failure}:
      Fail{failure}
    case Done{+json}:
      compiled_for(U32.is_eq(shard_of(U32.is_zero(flag), flag, json), 2), json, build)

# The config that matches every seed of a build.
def matching_all(built: Result<&1, &1, U32 & String, Builds.Build>) -> Result<&1, &1, U32 & String, String>:
  match built:
    case Fail{failure}:
      Fail{failure}
    case Done{+build}:
      Done{"{\"version\": 3, \"build\": " ++ U32.show(Builds.number(build)) ++ "}"}

# Reads and compiles the config file (none: the config that matches every seed) for the shard `flag` names (0: the
# config's) and the build `build` names (None: the config's, else the latest).
def load_config(path: Maybe<&2, String>, +flag: U32, +build: Maybe<&2, Builds.Build>) -> IO(Result<&1, &1, U32 & String, Loaded>):
  match path:
    case None{}:
      IO.pure(Result<&1, &1, U32 & String, Loaded>, compiled(flag, None{}, matching_all(Args.build_for(build, U32.is_eq(flag, 2)))))
    case Some{+file}:
      do IO<Result<&1, &1, U32 & String, Loaded>>:
        text : Result<&1, &1, U32 & String, String> <- Files.read_text("config: ", file)
        IO.pure(Result<&1, &1, U32 & String, Loaded>, compiled(flag, build, text))
