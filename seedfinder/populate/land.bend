import Base
import ../worldsim/points.bend as PT
import ./ground.bend as PG
import ./state.bend as PS
import ./voronoi.bend as PV

# forest_map.Generate's land population: Graph:ConvertGround, ReplaceSingleNonLandTiles, Graph:PopulateVoronoi
# (default forest: keep_disconnected_tiles, so no DetectDisconnect; ClearSafeFromDisconnect is a no-op here).

def replaced(l: PS.Land) -> PS.Land:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      PS.Land{PT.replace_single_non_land(g), rng, ents, events}

# The land entities and grid from the grid after CreateNodeIdTileMap and the RNG at ConvertGround.
def land(+c: PS.Ctx, l: PS.Land) -> PS.Land:
  PV.populate(c, PS.digest(replaced(PG.convert_ground(c, l)), c, 1))
