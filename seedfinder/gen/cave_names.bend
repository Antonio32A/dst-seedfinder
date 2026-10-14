import Base
import ../populate/names.bend as PopulateNames
import ../data/builds.bend as Builds

# The prefab names the caves' post-populate steps use, as string ids.

def wormhole(+build: Builds.Build) -> U32:
  PopulateNames.string_id(build, "tentacle_pillar")

def dispenser(+build: Builds.Build) -> U32:
  PopulateNames.string_id(build, "archive_lockbox_dispencer")

def temporary(+build: Builds.Build) -> U32:
  PopulateNames.string_id(build, "archive_lockbox_dispencer_temp")

def atrium(+build: Builds.Build) -> U32:
  PopulateNames.string_id(build, "tentacle_pillar_atrium")
