import Base
import ../worldsim/points.bend as Points
import ./ground.bend as Ground
import ./state.bend as PopulateState
import ./voronoi.bend as PopulateVoronoi

# forest_map.Generate's land population: Graph:ConvertGround, ReplaceSingleNonLandTiles, Graph:PopulateVoronoi
# (default forest: keep_disconnected_tiles, so no DetectDisconnect; ClearSafeFromDisconnect is a no-op here).

def replaced(l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      PopulateState.Land{Points.replace_single_non_land(g), rng, ents, events}

# The land entities and grid from the grid after CreateNodeIdTileMap and the RNG at ConvertGround.
def land(+c: PopulateState.Ctx, l: PopulateState.Land) -> PopulateState.Land:
  PopulateVoronoi.populate(c, PopulateState.digest(replaced(Ground.convert_ground(c, l)), c, 1))
