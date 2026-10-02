import Base
import ../filters/world.bend as FilterWorld
import ../f64/repr.bend as F64Repr
import ../rng/pcg.bend as Pcg
import ../worldsim/grid.bend as Grid
import ../ocean/ents.bend as OceanEnts
import ../gen/job.bend as GenJob
import ../gen/savedata.bend as SaveData

# A caves world (newest entity first): a cave_exit (string id 917), two tentacle_pillar (1217) teleporting to each
# other, a tentacle_pillar_atrium (1218) whose target is gone, and an entity of no vocabulary prefab.
def cave_final() -> GenJob.Final:
  GenJob.Final{Grid.put(Grid.new(3, 3, Grid.cell(6, 0)), 4, Grid.cell(1, 0)), Pcg.Rng{0, 0},
    [OceanEnts.Ent{1218, F64Repr.F64{1081196544, 0}, F64Repr.F64{3227320320, 0}, 12, 99, 0}, OceanEnts.Ent{1217, F64Repr.F64{3229499392, 0}, F64Repr.F64{3227619328, 0}, 11, 10, 0},
      OceanEnts.Ent{5, F64Repr.F64{1069547520, 0}, F64Repr.F64{3217031168, 0}, 0, 0, 0}, OceanEnts.Ent{1217, F64Repr.F64{1082314752, 0}, F64Repr.F64{1079672832, 0}, 10, 11, 0},
      OceanEnts.Ent{917, F64Repr.F64{1069547520, 0}, F64Repr.F64{1079672832, 0}, 0, 0, 0}], 3, [], [], 3}

law cave_world_is_dump_world:
  {FilterWorld.loaded_of(Done{SaveData.dump_caves(7, True{}, cave_final())}, True{}) == Done{FilterWorld.Generated{SaveData.cave_world(7, True{}, cave_final()), 1}} : Result<&1, &1, U32 & String, FilterWorld.Loaded>}

def cave_world_is_dump_world():
  {==}
