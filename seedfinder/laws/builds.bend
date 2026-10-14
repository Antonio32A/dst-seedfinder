import Base
import ../data/builds.bend as Builds
import ../cli/args.bend as Args
import ../filters/cave_config.bend as CaveConfig

# The game builds (builds.json, data/builds.bend): the registry the config's `build` and the --build flag name.

def number_of(m: Maybe<&2, Builds.Build>) -> U32:
  match m:
    case None{}:
      0
    case Some{build}:
      Builds.number(build)

def round_trips(numbers: List<&2, U32>) -> Bool:
  match numbers:
    case Nil{}:
      True{}
    case Con{+n, rest}:
      U32.is_eq(number_of(Builds.of_number(n)), n) && round_trips(rest)

# Every registered number names its build and back; 0 (a world dump's unknown build) is never one.
law build_numbers_round_trip:
  {(round_trips(Builds.numbers()), Builds.of_number(0)) == (True{}, None{}) : Bool & Maybe<&2, Builds.Build>}

def build_numbers_round_trip():
  {==}

# The default build is registered and has both shards.
law latest_build_is_registered:
  {(Builds.of_number(Builds.number(Builds.latest())), Builds.has_caves(Builds.latest())) == (Some{Builds.latest()}, True{}) : Maybe<&2, Builds.Build> & Bool}

def latest_build_is_registered():
  {==}

law build_flag_names_a_registered_build:
  {(Args.build_flag(Some{"757748"}), Args.build_flag(Some{"123"}), Args.build_flag(None{}))
    == (Done{Some{Builds.Build{757748}}}, Fail{(2, "--build must be a game build (" ++ Builds.numbers_text() ++ "), got \"123\"")}, Done{None{}})
    : Result<&1, &1, U32 & String, Maybe<&2, Builds.Build>> & Result<&1, &1, U32 & String, Maybe<&2, Builds.Build>> & Result<&1, &1, U32 & String, Maybe<&2, Builds.Build>>}

def build_flag_names_a_registered_build():
  {==}

# Without a config, a command runs the --build flag's build, else the latest; the caves shard needs a build that has it.
law build_without_config:
  {(Args.build_for(None{}, True{}), Args.build_for(Some{Builds.Build{757748}}, False{}), Args.build_for(Some{Builds.Build{757748}}, True{}))
    == (Done{Builds.latest()}, Done{Builds.Build{757748}}, Fail{(2, "build 757748 does not support the caves shard yet")})
    : Result<&1, &1, U32 & String, Builds.Build> & Result<&1, &1, U32 & String, Builds.Build> & Result<&1, &1, U32 & String, Builds.Build>}

def build_without_config():
  {==}

law caves_config_needs_a_build_with_caves:
  {CaveConfig.config_of("{\"version\": 3, \"build\": 757748, \"shard\": \"caves\"}", None{}) == Fail{(2, "config: build 757748 does not support the caves shard yet")} : Result<&1, &1, U32 & String, CaveConfig.Config>}

def caves_config_needs_a_build_with_caves():
  {==}
