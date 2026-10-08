import Base
import ../rng/pcg.bend as Pcg
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../data/blob.bend as Blob
import ../data/cave_story.bend as CaveStory
import ../data/layouts.bend as Layouts
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../populate/entities.bend as Entities
import ../populate/layout.bend as PopulateLayout
import ../populate/place.bend as PopulatePlace

# obj_layout.Place(position, shape, add_fn, choices) for the maze layouts: LayoutForDefinition picks one of the maze
# choices, ConvertLayoutToEntitylist runs the layout's area closures, and ReserveAndPlaceLayout with a position paints
# the layout's ground into the tile map at (position + column, position + row) and puts every object down around
# position + size + 0.5 with add_fn (ReserveTile, then the entity at the tile position, floored to hundredths).

# The tile map, the RNG and the entities added so far (newest first).
type Laid is Type:
  Laid{grid: Grid.Grid, rng: Pcg.Rng, ents: List<&2, Entities.Ent>}

# The prefab swap state, the map width and the position of the layout (the lower corner tile).
type Spot is Data:
  Spot{swaps: U32, width: U32, x: U32, y: U32}

def swaps_of(+spot: Spot) -> U32:
  match spot:
    case Spot{+swaps, _, _, _}:
      swaps

def width_of(+spot: Spot) -> U32:
  match spot:
    case Spot{_, +width, _, _}:
      width

def x_of(+spot: Spot) -> U32:
  match spot:
    case Spot{_, _, +x, _}:
      x

def y_of(+spot: Spot) -> U32:
  match spot:
    case Spot{_, _, _, +y}:
      y

def flip_x(+t: PopulatePlace.Turn) -> PopulatePlace.Turn:
  match t:
    case PopulatePlace.Turn{+switch, +fx, +fy}:
      PopulatePlace.Turn{switch, Bool.not(fx), Bool.not(fy)}

# The transform of a positioned layout: the forced rotation when the layout has one, else the random transform, with
# both flips reversed ("all positioned layouts being authored in the wrong direction").
def transform(+random: PopulatePlace.Turn, +rotation: U32) -> PopulatePlace.Turn:
  flip_x(Bool.pick(PopulatePlace.Turn, Blob.is_none(rotation), random, PopulatePlace.forced(rotation)))

def tile_if(painted: Bool, g: Grid.Grid, +x: U32, +y: U32, +tile: U32) -> Grid.Grid:
  match painted:
    case True{}:
      Points.set_tile(g, x, y, tile, 1)
    case False{}:
      g

def paint_cells(cells: List<&2, U32>, g: Grid.Grid, +side: U32, +spot: Spot, +q: U32) -> Grid.Grid:
  match cells:
    case Nil{}:
      g
    case Con{+tile, rest}:
      +column = (q / side : U32)
      +row = (q % side : U32)
      paint_cells(rest, tile_if(Bool.not(U32.is_zero(tile)), g, (x_of(spot) + column + 1 : U32), (y_of(spot) + row + 1 : U32), tile), side, spot, (q + 1 : U32))

def reserved_ent(got: Grid.Grid & Bool, +prefab: U32, +px: F64Repr.F64, +py: F64Repr.F64, +width: U32, rng: Pcg.Rng, +ents: List<&2, Entities.Ent>) -> Laid:
  (g, _) = got
  +e = Entities.entity(prefab, px, py, width, width, False{}, rng)
  Laid{g, Entities.rng_of(e), e <> ents}

def add_object(+prefab: U32, +px: F64Repr.F64, +py: F64Repr.F64, +width: U32, l: Laid) -> Laid:
  match l:
    case Laid{g, +rng, +ents}:
      reserved_ent(Points.reserve_tile(g, Points.lua_int(px), Points.lua_int(py)), prefab, px, py, width, rng, ents)

def add_objects(items: List<&2, PopulateLayout.Item>, +f: PopulatePlace.Frame, +width: U32, l: Laid) -> Laid:
  match items:
    case Nil{}:
      l
    case Con{+i, rest}:
      match f:
        case PopulatePlace.Frame{+cx, +cy, +t, +scale}:
          add_objects(rest, f, width, add_object(PopulatePlace.item_prefab(i), F64Arith.add(cx, F64Arith.mul(PopulatePlace.item_x(t, i), scale)),
            F64Arith.add(cy, F64Arith.mul(PopulatePlace.item_y(t, i), scale)), width, l))

def painted_and_placed(+v: U32, +items: List<&2, PopulateLayout.Item>, +sized: F64Repr.F64, +t: PopulatePlace.Turn, +spot: Spot, l: Laid) -> Laid:
  match l:
    case Laid{g, +rng, +ents}:
      +side = Layouts.ground_size(v)
      +centre = F64Arith.add(F64Arith.add(F64Repr.from_u32(x_of(spot)), sized), F64Repr.half())
      add_objects(items, PopulatePlace.Frame{centre, F64Arith.add(F64Arith.add(F64Repr.from_u32(y_of(spot)), sized), F64Repr.half()), t, PopulatePlace.scale_of(Layouts.scale(v))},
        width_of(spot), Laid{paint_cells(PopulatePlace.ground(v, t), g, side, spot, 0), rng, ents})

def turned(got: PopulatePlace.Turn & Pcg.Rng, +v: U32, +items: List<&2, PopulateLayout.Item>, +size: F64Repr.F64, +spot: Spot, g: Grid.Grid, +ents: List<&2, Entities.Ent>) -> Laid:
  (+random, rng) = got
  painted_and_placed(v, items, PopulatePlace.ground_size(v, size), transform(random, Layouts.force_rotation(v)), spot, Laid{g, rng, ents})

def converted(got: List<&2, PopulateLayout.Item> & Pcg.Rng, +v: U32, +spot: Spot, g: Grid.Grid, +ents: List<&2, Entities.Ent>) -> Laid:
  (+items, rng) = got
  +start = {PopulatePlace.Box{PopulatePlace.million(), F64Repr.neg(PopulatePlace.million()), PopulatePlace.million(), F64Repr.neg(PopulatePlace.million())} : PopulatePlace.Box}
  turned(PopulatePlace.turn(Layouts.has(v, Layouts.flag_disable_transform()), rng), v, items, F64Arith.mul(PopulatePlace.scale_of(Layouts.scale(v)),
    PopulatePlace.half_extent(PopulatePlace.bounds(items, start))), spot, g, ents)

def picked(got: U32 & Pcg.Rng, +cell: U32, +spot: Spot, g: Grid.Grid, +ents: List<&2, Entities.Ent>) -> Laid:
  (+choice, rng) = got
  +layout = CaveStory.maze_layout(choice, cell)
  converted(PopulateLayout.convert(swaps_of(spot), layout, rng), Layouts.variant(layout, swaps_of(spot)), spot, g, ents)

# obj_layout.Place(position, MAZE_CELL_EXITS_INV[cell], add_fn, choices).
def place(+spot: Spot, +cell: U32, +choices: List<&2, U32>, l: Laid) -> Laid:
  match l:
    case Laid{g, rng, +ents}:
      picked(PopulateLayout.random_item(choices, rng), cell, spot, g, ents)
