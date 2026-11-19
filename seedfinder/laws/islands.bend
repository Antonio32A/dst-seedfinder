import Base
import ../filters/world.bend as FilterWorld
import ../filters/landmass.bend as Landmass
import ../filters/islands.bend as Islands
import ../filters/rules.bend as Rules
import ../filters/checks.bend as Checks
import ../filters/config.bend as Config
import ../filters/cave_config.bend as CaveConfig
import ../data/builds.bend as Builds

# The islands rules (docs/config.md section 4 G): landmasses are 4-neighbour, an instance's reach is its anchor's
# landmass (and with the links every landmass they exit to from the reach), and A is the smallest reach. Goldens: the
# real worlds' tiles cropped around one landmass by .dstw (Windows forest, build 762172) with its 4-neighbour flood
# (Python); the toy worlds by hand.

def build() -> Builds.Build:
  Builds.Build{762172}

def nils(n: Nat) -> List<&2, List<&2, FilterWorld.Inst>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Nil{} <> nils(p)

# The instances of vocabulary prefab `id` (the groups before it empty).
def groups_with(+id: U32, +insts: List<&2, FilterWorld.Inst>) -> List<&2, List<&2, FilterWorld.Inst>>:
  List.append(&2, List<&2, FilterWorld.Inst>, nils(U32.to_nat(id)), [insts])

def world_of(+w: U32, +h: U32, +tiles: List<&2, U32>, +groups: List<&2, List<&2, FilterWorld.Inst>>, +links: List<&2, FilterWorld.Link>) -> FilterWorld.World:
  FilterWorld.World{1, w, h, Nil{}, groups, links, tiles, None{}, None{}, FilterWorld.land_bits(tiles, 0n, 0), None{}}

def reach_area(found: Maybe<&2, Islands.Reach>) -> Maybe<&2, U32>:
  match found:
    case None{}:
      None{}
    case Some{Islands.Reach{_, _, +area}}:
      Some{area}

def area_at(+world: FilterWorld.World, +at: List<&2, U32>, +links: Bool) -> Maybe<&2, U32>:
  reach_area(Islands.smallest_reach(world, at, links))

# A 6 x 4 world, land (6) and water (1):
#   y0  L L . L L .
#   y1  L . . L . L
#   y2  L L L L . .
#   y3  . . . . . L
# The two arms of the U are runs of different roots until row 2 joins them; (5, 1) touches the U only at the corner of
# (4, 0), and (5, 3) only at nothing: three landmasses of 10, 1 and 1 tiles, numbered in scan order.
def toy_tiles() -> List<&2, U32>:
  [393222, 393217, 65542, 65542, 393217, 393217, 393222, 393222, 65537, 65537, 65537, 393217]

def toy_masses() -> Landmass.Masses:
  Landmass.of_land(FilterWorld.land_bits(toy_tiles(), 0n, 0), 6, 4)

def labels(n: Nat, +masses: Landmass.Masses, +tile: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Landmass.mass_at(masses, tile) <> labels(p, masses, (tile + 1 : U32))

law landmasses_join_only_through_sides:
  {labels(24n, toy_masses(), 0) == [0, 0, Landmass.none(), 0, 0, Landmass.none(), 0, Landmass.none(), Landmass.none(), 0, Landmass.none(), 1,
    0, 0, 0, 0, Landmass.none(), Landmass.none(), Landmass.none(), Landmass.none(), Landmass.none(), Landmass.none(), Landmass.none(), 2] : List<&2, U32>}

def landmasses_join_only_through_sides():
  {==}

law landmass_areas_and_bounds:
  {[Landmass.mass(toy_masses(), 0), Landmass.mass(toy_masses(), 1), Landmass.mass(toy_masses(), 2)]
    == [Landmass.Mass{10, 0, 0, 4, 2}, Landmass.Mass{1, 5, 1, 5, 1}, Landmass.Mass{1, 5, 3, 5, 3}] : List<&2, Landmass.Mass>}

def landmass_areas_and_bounds():
  {==}

# The portal (190) on the U at (0, 0) and on (5, 3); the wormholes (338) link (5, 3) to (0, 0) and (5, 1) to (5, 3). A
# portal in the water of (4, 1), 1.5 east of its centre, anchors at the nearest land centre, (5, 1) 2.5 away.
def u_portal() -> FilterWorld.Inst:
  FilterWorld.inst_of(190, 0, 4294966096, 4294966496)

def east_portal() -> FilterWorld.Inst:
  FilterWorld.inst_of(190, 1, 800, 400)

def wet_portal() -> FilterWorld.Inst:
  FilterWorld.inst_of(190, 0, 550, 4294966896)

def toy_links() -> List<&2, FilterWorld.Link>:
  [FilterWorld.Link{FilterWorld.inst_of(338, 0, 800, 400), FilterWorld.inst_of(338, 1, 4294966096, 4294966496)},
    FilterWorld.Link{FilterWorld.inst_of(338, 2, 800, 4294966896), FilterWorld.inst_of(338, 3, 800, 400)}]

def toy(+portals: List<&2, FilterWorld.Inst>) -> FilterWorld.World:
  world_of(6, 4, toy_tiles(), groups_with(190, portals), toy_links())

def island(+min: Maybe<&2, U32>, +max: Maybe<&2, U32>, +links: Bool) -> Rules.Island:
  Rules.Island{[190], min, max, links, False{}}

# A is the smallest reach (the portal on (5, 3)), and its bounds are inclusive.
law islands_take_the_smallest_reach:
  {Islands.check(build(), toy([u_portal(), east_portal()]), island(Some{1}, Some{1}, False{}))
    == Checks.Check{True{}, ",\"area\":1,\"at\":{\"prefab\":\"multiplayer_portal\",\"index\":1,\"x\":8,\"z\":4},\"tile\":{\"tx\":5,\"ty\":3,\"x\":8.0,\"z\":4.0},\"landmasses\":[{\"tx\":5,\"ty\":3,\"area\":1}],\"bounds\":{\"tx0\":5,\"ty0\":3,\"tx1\":5,\"ty1\":3}"} : Checks.Check}

def islands_take_the_smallest_reach():
  {==}

law islands_bounds_are_inclusive:
  {(Islands.holds(toy([u_portal(), east_portal()]), island(Some{2}, None{}, False{})), Islands.holds(toy([u_portal()]), island(None{}, Some{9}, False{})),
    Islands.holds(toy([u_portal()]), island(Some{10}, Some{10}, False{})))
    == (False{}, False{}, True{}) : Bool & Bool & Bool}

def islands_bounds_are_inclusive():
  {==}

# Off land, the portal anchors at (5, 1) (section 5); the links chain from it to (5, 3) and on to the U, in the order
# they reach them (the second link first), and the reach's tiles and bounds add up.
law islands_follow_the_links:
  {(area_at(toy([wet_portal()]), [190], False{}), Islands.check(build(), toy([wet_portal()]), island(None{}, Some{12}, True{})))
    == (Some{1}, Checks.Check{True{}, ",\"area\":12,\"at\":{\"prefab\":\"multiplayer_portal\",\"index\":0,\"x\":5.5,\"z\":-4},\"tile\":{\"tx\":5,\"ty\":1,\"x\":8.0,\"z\":-4.0},\"landmasses\":[{\"tx\":5,\"ty\":1,\"area\":1},{\"tx\":5,\"ty\":3,\"area\":1},{\"tx\":0,\"ty\":0,\"area\":10}],\"bounds\":{\"tx0\":0,\"ty0\":0,\"tx1\":5,\"ty1\":3}"}) : Maybe<&2, U32> & Checks.Check}

def islands_follow_the_links():
  {==}

# Without an anchored instance A is null: a max fails, a min holds, and a rule without bounds holds; a world without
# land anchors nothing.
law islands_null_area:
  {(Islands.check(build(), toy(Nil{}), island(None{}, Some{30000}, False{})), Islands.holds(toy(Nil{}), island(Some{1}, None{}, True{})),
    Islands.holds(toy(Nil{}), island(None{}, None{}, False{})), area_at(world_of(2, 1, [65537], groups_with(190, [FilterWorld.inst_of(190, 0, 0, 0)]), Nil{}), [190], False{}))
    == (Checks.Check{False{}, ",\"area\":null"}, True{}, True{}, None{}) : Checks.Check & Bool & Bool & Maybe<&2, U32>}

def islands_null_area():
  {==}

# Seed 1's hermit island: hermithouse_construction1 (124) at (-603.75, 160.12), its 108 tiles cropped with one tile of
# their water around.
def hermit_island() -> FilterWorld.World:
  world_of(15, 17,
    [13369548, 13172940, 13172937, 13238473, 13238474, 13238474, 13172938, 13369545, 13369548, 13172937, 13238473,
     2883786, 2883628, 13238316, 13172938, 13369548, 13172937, 13238473, 2883786, 2883628, 2883628, 13238316,
     13369546, 13172937, 13172937, 2883786, 2818092, 2883627, 2883628, 13238316, 13172940, 13172937, 13238473,
     2818091, 2818091, 2818091, 2883628, 13172938, 13172937, 13172937, 2818250, 2818091, 2818091, 2883627, 13238474,
     13172937, 13172937, 13238473, 2818091, 2818091, 2818091, 13238315, 13238473, 13238474, 13172937, 13238474,
     2818091, 2818091, 2818091, 13238474, 2883786, 13238474, 13172937, 13238474, 2818092, 2818091, 2818091, 13238474,
     2883628, 13172938, 13172937, 2883786, 2883628, 2818091, 13238315, 2883786, 13238316, 13172938, 13238474, 2883628,
     2883628, 2818091, 13238474, 2883628, 13238316, 13238474, 2883628, 2883628, 2818092, 13238315, 2883786, 2883628,
     2883628, 2883628, 2883628, 2883628, 2818091, 13238474, 2883786, 2883628, 2883628, 2883628, 2883628, 13238316,
     13238474, 13238473, 13238474, 2883628, 2883628, 2883628, 13238474, 13172938, 13172937, 13172937, 13238474,
     13238474, 13238474, 13238474, 13172937, 13172937, 13172937, 13172937, 13172937, 13172937, 13172937, 13172937,
     13172937, 201],
    groups_with(124, [FilterWorld.inst_of(124, 0, 825, 4294966108)]), Nil{})

law hermit_island_of_seed_1:
  {area_at(hermit_island(), [124], False{}) == Some{108} : Maybe<&2, U32>}

def hermit_island_of_seed_1():
  {==}

# Seed 1's moon_fissure (173) 26 at (321.74, -569.32): one of the moon's islets, 139 tiles.
def moon_islet() -> FilterWorld.World:
  world_of(21, 17,
    [13172937, 13172937, 13238474, 13238474, 13172937, 13172937, 13172937, 13172937, 13172937, 13172937, 13172937,
     13172937, 13238474, 2752555, 13238474, 13172937, 13172937, 13172937, 13172937, 13172937, 13172937, 13172937,
     13238474, 2818091, 2752554, 13238474, 13172937, 13172937, 13172937, 13172937, 13172937, 13172937, 13238474,
     2752555, 2752554, 2752554, 13238474, 13172937, 13172937, 13172937, 13172937, 13172937, 13238474, 2752554,
     2752554, 2752554, 2752554, 13238474, 13172937, 13172937, 13172937, 13172937, 13238473, 2752554, 2752554, 2752554,
     2752554, 2752554, 13238474, 13172937, 13172937, 13172937, 13172937, 2752714, 2752554, 2752554, 2752554, 2752554,
     2752554, 13238474, 13172937, 13172937, 13172937, 13238473, 2752554, 2752554, 2752554, 2752554, 2752554, 2752554,
     13238474, 13172937, 13172937, 13172937, 2752714, 2752554, 2752554, 2752554, 2752554, 2818090, 2818091, 13238474,
     13172937, 13172937, 13238473, 2752554, 2752554, 2752554, 2752554, 2752554, 2818091, 2818091, 13238474, 13172938,
     13172937, 13238474, 2752554, 2752554, 2752554, 2752554, 2818091, 2818091, 2818091, 13238315, 13172938, 13172937,
     13238474, 2752714, 2752554, 2752554, 2818090, 2818091, 2818090, 2818091, 13238314, 13172938, 13172937, 13238473,
     2752714, 2752554, 2752554, 2818091, 2818091, 2818091, 2752555, 13238314, 13172937, 13172937, 13238473, 2752714,
     2752554, 2752554, 2818091, 2818091, 2818091, 13238314, 13172938, 13172937, 13172937, 13238473, 13238474,
     13238314, 13238474, 13238474, 2818091, 13238315, 13172938, 13172937, 13172937, 13172937, 13238473, 13238474,
     13172938, 13172937, 13238474, 13238474, 13172938, 13172937, 13172937, 13172937, 13238474, 2752714, 13238314,
     13238474, 13238474, 13172937, 13172937, 13172937, 201],
    groups_with(173, [FilterWorld.inst_of(173, 26, 1374, 268)]), Nil{})

law moon_islet_of_seed_1:
  {area_at(moon_islet(), [173], False{}) == Some{139} : Maybe<&2, U32>}

def moon_islet_of_seed_1():
  {==}

def later_of(compiled: Result<&1, &1, U32 & String, Config.Config>) -> Result<&1, &1, U32 & String, List<&2, Rules.Later>>:
  match compiled:
    case Done{Config.Config{_, _, _, +later, _, _}}:
      Done{later}
    case Fail{failure}:
      Fail{failure}

def cave_later_of(compiled: Result<&1, &1, U32 & String, CaveConfig.Config>) -> Result<&1, &1, U32 & String, List<&2, Rules.Later>>:
  match compiled:
    case Done{CaveConfig.Config{_, _, _, +later, _}}:
      Done{later}
    case Fail{failure}:
      Fail{failure}

law config_reads_islands:
  {(later_of(Config.config_of("{\"version\": 3, \"build\": 762172, \"filters\": [{\"islands\": [{\"at\": \"multiplayer_portal\", \"max\": 30000}, {\"at\": [\"moon_fissure\", \"wormhole\"], \"min\": 1, \"wormholes\": true}]}]}", None{})),
    cave_later_of(CaveConfig.config_of("{\"version\": 3, \"build\": 762172, \"shard\": \"caves\", \"filters\": [{\"islands\": [{\"at\": \"cave_exit\", \"pillars\": true}]}]}", None{})))
    == (Done{[Rules.Later{[], [], [], [], [], [], [Rules.Island{[190], None{}, Some{30000}, False{}, False{}}, Rules.Island{[173, 338], Some{1}, None{}, True{}, False{}}]}]},
      Done{[Rules.Later{[], [], [], [], [], [], [Rules.Island{[372], None{}, None{}, True{}, True{}}]}]})
    : Result<&1, &1, U32 & String, List<&2, Rules.Later>> & Result<&1, &1, U32 & String, List<&2, Rules.Later>>}

def config_reads_islands():
  {==}

def error_of(compiled: Result<&1, &1, U32 & String, Config.Config>) -> String:
  match compiled:
    case Fail{(_, message)}:
      message
    case Done{_}:
      ""

def cave_error_of(compiled: Result<&1, &1, U32 & String, CaveConfig.Config>) -> String:
  match compiled:
    case Fail{(_, message)}:
      message
    case Done{_}:
      ""

def forest_islands(+rules: String) -> String:
  "{\"version\": 3, \"build\": 762172, \"filters\": [{\"islands\": " ++ rules ++ "}]}"

law islands_config_errors:
  {(error_of(Config.config_of(forest_islands("[{\"max\": 3}]"), None{})), error_of(Config.config_of(forest_islands("[{\"at\": \"pigking\", \"radius\": 3}]"), None{})),
    error_of(Config.config_of(forest_islands("[{\"at\": \"pigking\", \"pillars\": true}]"), None{})),
    cave_error_of(CaveConfig.config_of("{\"version\": 3, \"build\": 762172, \"shard\": \"caves\", \"filters\": [{\"islands\": [{\"at\": \"cave_exit\", \"wormholes\": true}]}]}", None{})),
    error_of(Config.config_of(forest_islands("[{\"at\": \"pigking\", \"max\": -1}]"), None{})))
    == ("config: filters[0].islands[0].at is required", "config: unknown key \"radius\" in filters[0].islands[0]",
      "config: unknown key \"pillars\" in filters[0].islands[0]", "config: unknown key \"wormholes\" in filters[0].islands[0]",
      "config: filters[0].islands[0].max must be an integer in 0..4294967295")
    : String & String & String & String & String}

def islands_config_errors():
  {==}

# An islands rule reads its `at` prefabs, the land and its landmasses, and with the links the wormholes.
law islands_needs:
  {Rules.needs(build(), [Rules.Later{[], [], [], [], [], [], [Rules.Island{[190], None{}, Some{30000}, True{}, False{}}]}])
    == Rules.Needs{[190, 338], True{}, False{}, True{}, False{}, False{}, True{}} : Rules.Needs}

def islands_needs():
  {==}
