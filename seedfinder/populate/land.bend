import Base
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/disconnect.bend as TileDisconnect
import ../rng/pcg.bend as Pcg
import ./entities.bend as Entities
import ./ground.bend as Ground
import ./state.bend as PopulateState
import ./voronoi.bend as PopulateVoronoi
import ../data/builds.bend as Builds

# forest_map.Generate's land population: Graph:ConvertGround, ReplaceSingleNonLandTiles, Graph:PopulateVoronoi
# (default forest: keep_disconnected_tiles, so no DetectDisconnect; ClearSafeFromDisconnect is a no-op here).

def replaced(l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      PopulateState.Land{Points.replace_single_non_land(g), rng, ents, events}

# The land entities and grid from the grid after CreateNodeIdTileMap and the RNG at ConvertGround.
def land(+build: Builds.Build, +c: PopulateState.Ctx, l: PopulateState.Land) -> PopulateState.Land:
  PopulateVoronoi.populate(build, c, PopulateState.digest(replaced(Ground.convert_ground(build, c, l)), c, 1))

def ground_checked(got: Grid.Grid & U32, +c: PopulateState.Ctx, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>) -> PopulateState.Land & Bool:
  (g, +count) = got
  (PopulateState.Land{g, rng, ents, events}, Bool.not(TileDisconnect.exceeds(count, PopulateState.width_of(c), PopulateState.height_of(c))))

def detected(l: PopulateState.Land, +c: PopulateState.Ctx, +start_x: U32, +start_y: U32) -> PopulateState.Land & Bool:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      ground_checked(TileDisconnect.detect(g, start_x, start_y), c, rng, ents, events)

# The caves' land population up to its verdict: Graph:ConvertGround, ReplaceSingleNonLandTiles and DetectDisconnect
# from the START node's site tile (start_x, start_y). The verdict is false when more than 5% of the tiles are
# disconnected and the attempt fails (the land then holds the RNG after ConvertGround, which the next attempt
# continues); else Graph:PopulateVoronoi (voronoi_caves) follows.
def ground_caves(+build: Builds.Build, +c: PopulateState.Ctx, +start_x: U32, +start_y: U32, l: PopulateState.Land) -> PopulateState.Land & Bool:
  detected(PopulateState.digest(replaced(Ground.convert_ground(build, c, l)), c, 1), c, start_x, start_y)

# The caves' Graph:PopulateVoronoi.
def voronoi_caves(+build: Builds.Build, +c: PopulateState.Ctx, l: PopulateState.Land) -> PopulateState.Land:
  PopulateVoronoi.populate(build, c, l)
