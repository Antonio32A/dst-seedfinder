import Base
import ../populate/names.bend as PopulateNames

# The prefab names the caves' post-populate steps use, as string ids.

def wormhole() -> U32:
  PopulateNames.string_id("tentacle_pillar")

def dispenser() -> U32:
  PopulateNames.string_id("archive_lockbox_dispencer")

def temporary() -> U32:
  PopulateNames.string_id("archive_lockbox_dispencer_temp")

def atrium() -> U32:
  PopulateNames.string_id("tentacle_pillar_atrium")
