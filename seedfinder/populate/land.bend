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

def populated(+build: Builds.Build, ok: Bool, l: PopulateState.Land, +c: PopulateState.Ctx) -> PopulateState.Land & Bool:
  match ok:
    case True{}:
      (PopulateVoronoi.populate(build, c, l), True{})
    case False{}:
      (l, False{})

def disconnected(+build: Builds.Build, got: Grid.Grid & U32, +c: PopulateState.Ctx, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>) -> PopulateState.Land & Bool:
  (g, +count) = got
  populated(build, Bool.not(TileDisconnect.exceeds(count, PopulateState.width_of(c), PopulateState.height_of(c))), PopulateState.Land{g, rng, ents, events}, c)

def detected(+build: Builds.Build, l: PopulateState.Land, +c: PopulateState.Ctx, +start_x: U32, +start_y: U32) -> PopulateState.Land & Bool:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      disconnected(build, TileDisconnect.detect(g, start_x, start_y), c, rng, ents, events)

# The caves' land population: Graph:ConvertGround, ReplaceSingleNonLandTiles, DetectDisconnect from the START node's site tile
# (start_x, start_y) and, unless more than 5% of the tiles are disconnected, Graph:PopulateVoronoi. The verdict is false when
# the attempt fails at DetectDisconnect (the land then holds the RNG after ConvertGround, which the next attempt continues).
def land_caves(+build: Builds.Build, +c: PopulateState.Ctx, +start_x: U32, +start_y: U32, l: PopulateState.Land) -> PopulateState.Land & Bool:
  detected(build, PopulateState.digest(replaced(Ground.convert_ground(build, c, l)), c, 1), c, start_x, start_y)
