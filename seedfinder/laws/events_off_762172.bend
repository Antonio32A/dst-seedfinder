import Base
import ../rng/pcg.bend as Pcg
import ../populate/counts.bend as PopulateCounts
import ../populate/layout.bend as PopulateLayout
import ../data/strings.bend as Strings
import ../data/layouts.bend as Layouts
import ../data/blob.bend as Blob
import ../data/builds.bend as Builds

# Build 762172 defaults to Hallowed Nights (constants.lua WORLD_SPECIAL_EVENT), but its worlds are generated with events
# disabled, so the Halloween branches of the room counts, boons and start layout never run. Goldens: the game Lua of
# map/rooms/forest/pigs.lua, map/boons.lua and map/layouts.lua with specialevent "none" under DST's PCG32.

def string_names(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+id, rest}:
      Strings.name(Builds.Build{762172}, id) <> string_names(rest)

def key_and_choices(+defs: List<&2, U32>) -> List<&2, String>:
  List.append(&2, String, string_names(Blob.first(defs, 1)), string_names(Blob.drop(defs, 2)))

# DefaultStart's (layout 25) defs: map/layouts.lua loads after forest_map.Generate applies the event, so its welcomitem
# is a flower (a pumpkin_lantern under Hallowed Nights).
law default_start_welcome_item:
  {key_and_choices(Layouts.defs(Builds.Build{762172}, Layouts.variant(Builds.Build{762172}, 25, 0))) == ["welcomitem", "flower"] : List<&2, String>}

def default_start_welcome_item():
  {==}

def names_of(+build: Builds.Build, xs: List<&2, PopulateLayout.Res>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{PopulateLayout.RName{+id}, rest}:
      Strings.name(build, id) <> names_of(build, rest)
    case Con{PopulateLayout.RPlaced{+id, _, _}, rest}:
      Strings.name(build, id) <> names_of(build, rest)

def named(got: List<&2, PopulateLayout.Res> & Pcg.Rng) -> List<&2, String> & Pcg.Rng:
  (+xs, rng) = got
  (names_of(Builds.Build{762172}, xs), rng)

def boon(+c: U32) -> List<&2, String> & Pcg.Rng:
  named(PopulateLayout.boon_a(Builds.Build{762172}, c, Pcg.at_counter(1, 0)))

# The Halloween count closures count 0 without a draw: DLCrooms.lua's pumpkins (66) and HalloweenPumpkinCarving (67),
# pigs.lua's HalloweenPumpkins (67) and pumpkin_lanterns (78 and 82).
law halloween_count_66_is_zero:
  {PopulateCounts.value_of(1, 66, 0, 425, Pcg.at_counter(1, 0)) == (0, Pcg.at_counter(1, 0)) : U32 & Pcg.Rng}

def halloween_count_66_is_zero():
  {==}

law halloween_count_67_is_zero:
  {PopulateCounts.value_of(1, 67, 0, 425, Pcg.at_counter(1, 0)) == (0, Pcg.at_counter(1, 0)) : U32 & Pcg.Rng}

def halloween_count_67_is_zero():
  {==}

law halloween_count_78_is_zero:
  {PopulateCounts.value_of(1, 78, 0, 425, Pcg.at_counter(1, 0)) == (0, Pcg.at_counter(1, 0)) : U32 & Pcg.Rng}

def halloween_count_78_is_zero():
  {==}

law halloween_count_82_is_zero:
  {PopulateCounts.value_of(1, 82, 0, 425, Pcg.at_counter(1, 0)) == (0, Pcg.at_counter(1, 0)) : U32 & Pcg.Rng}

def halloween_count_82_is_zero():
  {==}

# WoodBoon's item_area (closure 0, whose Halloween branch gained a pumpkin_bomb): PickSome(1, {"shovel", "axe"}).
law wood_boon_item:
  {boon(0) == (["axe"], Pcg.at_counter(1, 1)) : List<&2, String> & Pcg.Rng}

def wood_boon_item():
  {==}

# GrassBoon's item_area (closure 4): PickSome(1, {"torch", "trap"}).
law grass_boon_item:
  {boon(4) == (["trap"], Pcg.at_counter(1, 1)) : List<&2, String> & Pcg.Rng}

def grass_boon_item():
  {==}

# TwigsBoon's item_area (closure 6) is nil.
law twigs_boon_item:
  {boon(6) == ([], Pcg.at_counter(1, 0)) : List<&2, String> & Pcg.Rng}

def twigs_boon_item():
  {==}

# TwigsBoon's resource_area (closure 7): PickSomeWithDups(math.random(3, 5), {"twigs"}), five twigs in six draws.
law twigs_boon_resources:
  {boon(7) == (["twigs", "twigs", "twigs", "twigs", "twigs"], Pcg.at_counter(1, 6)) : List<&2, String> & Pcg.Rng}

def twigs_boon_resources():
  {==}
