import Base
import ../filters/world.bend as FilterWorld
import ../filters/dump.bend as FilterDump
import ../filters/rules.bend as Rules
import ../filters/landmass.bend as Landmass
import ../f64/repr.bend as F64Repr
import ../rng/pcg.bend as Pcg
import ../worldsim/grid.bend as Grid
import ../ocean/ents.bend as OceanEnts
import ../populate/planned.bend as PopulatePlanned
import ../gen/job.bend as GenJob
import ../gen/savedata.bend as SaveData
import ../data/builds.bend as Builds

# The search world (SaveData.world_for, cave_world_for) is the filters' world of the generated world with what the
# config's rules do not read emptied: the groups of the other prefabs (up to the last needed one), and the links, tile
# ids and pairs, land bits, topology and level plan unless some rule reads them (Rules.needs), with the landmasses of
# its land bits when some rule reads them.

def build() -> Builds.Build:
  Builds.Build{762172}

def kept_groups(groups: List<&2, List<&2, FilterWorld.Inst>>, ids: List<&2, U32>, +v: U32) -> List<&2, List<&2, FilterWorld.Inst>>:
  match groups ids:
    case Con{+g, rest} Con{+id, +more}:
      +hit = U32.is_eq(id, v)
      Bool.pick(List<&2, FilterWorld.Inst>, hit, g, Nil{}) <> kept_groups(rest, Bool.pick(List<&2, U32>, hit, more, id <> more), (v + 1 : U32))
    case _ _:
      Nil{}

def restricted(+world: FilterWorld.World, +needs: Rules.Needs) -> FilterWorld.World:
  match world needs:
    case FilterWorld.World{+seed, +w, +h, +tile_ids, +groups, +links, +tiles, +graph, +plan, +land, _} Rules.Needs{+ids, +follow, +reads_tiles, +walk, +topology, +planned, +masses}:
      FilterWorld.World{seed, w, h, Bool.pick(List<&2, U32>, reads_tiles, tile_ids, Nil{}), kept_groups(groups, ids, 0), Bool.pick(List<&2, FilterWorld.Link>, follow, links, Nil{}),
        Bool.pick(List<&2, U32>, reads_tiles, tiles, Nil{}), Bool.pick(Maybe<&2, FilterDump.Graph>, topology, graph, None{}),
        Bool.pick(Maybe<&2, List<&2, FilterDump.Planned>>, planned, plan, None{}), Bool.pick(List<&2, U32>, walk, land, Nil{}),
        Bool.pick(Maybe<&2, Landmass.Masses>, masses, Some{Landmass.of_land(land, w, h)}, None{})}

# 7 x 7 tiles of land (6) with four IMPASSABLE (1): two words of land bits.
def grid() -> Grid.Grid:
  Grid.put(Grid.put(Grid.put(Grid.put(Grid.new(7, 7, Grid.cell(6, 0)), 3, Grid.cell(1, 0)), 10, Grid.cell(1, 0)), 24, Grid.cell(1, 0)), 40, Grid.cell(1, 0))

def topology() -> FilterDump.Graph:
  FilterDump.Graph{[FilterDump.Node{"a", 1, 100, 200}], []}

def plan() -> List<&2, PopulatePlanned.Planned>:
  [PopulatePlanned.Planned{0, 140, True{}}]

def at(+sid: U32, +x: U32, +z: U32, +id: U32, +target: U32) -> OceanEnts.Ent:
  OceanEnts.Ent{sid, F64Repr.F64{x, 0}, F64Repr.F64{z, 0}, id, target, 0}

# A caves world (newest entity first): a tentacle_pillar_atrium (string id 1228) whose target is gone, two
# tentacle_pillar (1227) teleporting to each other around an atrium_gate (858) and an entity of no vocabulary prefab,
# and a cave_exit (927).
def cave_final() -> GenJob.Final:
  GenJob.Final{grid(), Pcg.Rng{0, 0}, [at(1228, 1081196544, 3227320320, 12, 99), at(1227, 3229499392, 3227619328, 11, 10), at(5, 1069547520, 3217031168, 0, 0),
    at(858, 1075838976, 1076887552, 0, 0), at(1227, 1082314752, 1079672832, 10, 11), at(927, 1069547520, 1079672832, 0, 0)], 7, [], [], 3, topology(), plan()}

# A forest world: two wormholes (615) teleporting to each other around a flower (278), an entity of no vocabulary
# prefab and an evergreen (262).
def forest_final() -> GenJob.Final:
  GenJob.Final{grid(), Pcg.Rng{0, 0}, [at(615, 3229499392, 3227619328, 11, 10), at(278, 1069547520, 3217031168, 0, 0), at(5, 1075838976, 1076887552, 0, 0),
    at(262, 1082314752, 1079672832, 0, 0), at(615, 1081196544, 3227320320, 10, 11)], 7, [], [], 3, topology(), plan()}

def walk_metric(+caves: Bool) -> Rules.Metric:
  Rules.Metric{True{}, True{}, caves}

def straight_metric(+caves: Bool) -> Rules.Metric:
  Rules.Metric{False{}, False{}, caves}

def later(+setpieces: List<&2, Rules.Placed>, +counts: List<&2, Rules.Count>, +distances: List<&2, Rules.Distance>, +tiles: List<&2, Rules.Tiles>, +bridges: List<&2, Rules.Bridge>) -> Rules.Later:
  Rules.Later{setpieces, counts, distances, tiles, bridges, Nil{}, Nil{}}

# cave_exit (vocabulary id 372) to atrium_gate (358), walking through the pillars (456, 457).
def cave_walk() -> Rules.Needs:
  Rules.needs(build(), [later(Nil{}, Nil{}, [Rules.Distance{[372], [358], None{}, None{}, walk_metric(True{})}], Nil{}, Nil{})])

# cave_exit counted, a tiles rule and a bridges rule; and the shadow_container (275), a pocket dimension container with
# no instance in the savedata, near the cave_exit along a route through the atrium_gate.
def cave_straight() -> Rules.Needs:
  Rules.needs(build(), [later(Nil{}, [Rules.Count{[372], Some{1}, None{}, None{}}], Nil{}, [Rules.Tiles{[0], [1], 3}], [Rules.Bridge{None{}, None{}}]),
    Rules.Later{Nil{}, [Rules.Count{[275], None{}, None{}, Some{Rules.Near{[372], F64Repr.zero(), straight_metric(True{})}}}], Nil{}, Nil{}, Nil{},
      [Rules.Route{[372], [[358]], None{}, F64Repr.zero(), False{}, straight_metric(True{})}], []}])

# flower (99) to evergreen (83), walking through the wormholes (338).
def forest_walk() -> Rules.Needs:
  Rules.needs(build(), [later(Nil{}, Nil{}, [Rules.Distance{[99], [83], None{}, None{}, walk_metric(False{})}], Nil{}, Nil{})])

# flower and shadow_container counted, a tiles rule and a setpieces rule with `placed` names.
def forest_straight() -> Rules.Needs:
  Rules.needs(build(), [later([Rules.Placed{0, Nil{}, Nil{}}], [Rules.Count{[275, 99], None{}, None{}, None{}}], Nil{}, [Rules.Tiles{[0], [1], 3}], Nil{})])

# flower (99) on its landmass and through the wormholes (338).
def forest_islands() -> Rules.Needs:
  Rules.needs(build(), [Rules.Later{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, [Rules.Island{[99], None{}, Some{3}, True{}, False{}}]}])

def placed_only() -> Rules.Needs:
  Rules.needs(build(), [later([Rules.Placed{0, Nil{}, Nil{}}], Nil{}, Nil{}, Nil{}, Nil{})])

law cave_walk_needs:
  {cave_walk() == Rules.Needs{[358, 372, 456, 457], True{}, False{}, True{}, False{}, False{}, False{}} : Rules.Needs}

def cave_walk_needs():
  {==}

law cave_straight_needs:
  {cave_straight() == Rules.Needs{[275, 358, 372], False{}, True{}, False{}, True{}, False{}, False{}} : Rules.Needs}

def cave_straight_needs():
  {==}

law forest_walk_needs:
  {forest_walk() == Rules.Needs{[83, 99, 338], True{}, False{}, True{}, False{}, False{}, False{}} : Rules.Needs}

def forest_walk_needs():
  {==}

law forest_straight_needs:
  {forest_straight() == Rules.Needs{[99, 275], False{}, True{}, False{}, False{}, True{}, False{}} : Rules.Needs}

def forest_straight_needs():
  {==}

law forest_islands_needs:
  {forest_islands() == Rules.Needs{[99, 338], True{}, False{}, True{}, False{}, False{}, True{}} : Rules.Needs}

def forest_islands_needs():
  {==}

law cave_search_world_with_pillars:
  {SaveData.cave_world_for(build(), 7, True{}, cave_walk(), cave_final()) == restricted(SaveData.cave_world(build(), 7, True{}, cave_final()), cave_walk()) : FilterWorld.World}

def cave_search_world_with_pillars():
  {==}

law cave_search_world_without_pillars:
  {SaveData.cave_world_for(build(), 7, False{}, cave_straight(), cave_final()) == restricted(SaveData.cave_world(build(), 7, False{}, cave_final()), cave_straight()) : FilterWorld.World}

def cave_search_world_without_pillars():
  {==}

law forest_search_world_with_wormholes:
  {SaveData.world_for(build(), 7, True{}, forest_walk(), forest_final()) == restricted(SaveData.world(build(), 7, True{}, forest_final()), forest_walk()) : FilterWorld.World}

def forest_search_world_with_wormholes():
  {==}

law forest_search_world_without_wormholes:
  {SaveData.world_for(build(), 7, False{}, forest_straight(), forest_final()) == restricted(SaveData.world(build(), 7, False{}, forest_final()), forest_straight()) : FilterWorld.World}

def forest_search_world_without_wormholes():
  {==}

law forest_search_world_with_landmasses:
  {SaveData.world_for(build(), 7, True{}, forest_islands(), forest_final()) == restricted(SaveData.world(build(), 7, True{}, forest_final()), forest_islands()) : FilterWorld.World}

def forest_search_world_with_landmasses():
  {==}

# Placed rules alone read only the level plan: the world holds the seed, the size and the plan.
law forest_search_world_plan_only:
  {SaveData.world_for(build(), 7, False{}, placed_only(), forest_final()) == FilterWorld.World{7, 7, 7, [], [], [], [], None{}, Some{SaveData.plan_of(build(), plan())}, [], None{}} : FilterWorld.World}

def forest_search_world_plan_only():
  {==}
