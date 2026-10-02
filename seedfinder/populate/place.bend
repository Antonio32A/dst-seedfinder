import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../f32/ops.bend as F32Ops
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../data/blob.bend as Blob
import ../data/layouts.bend as Layouts
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/groups.bend as TileGroups
import ./entities.bend as Entities
import ./layout.bend as PopulateLayout
import ./state.bend as PopulateState
import ./setpiece.bend as PopulateSetpiece

# object_layout.lua's ReserveAndPlaceLayout for ConvertGround's layouts (position nil, WorldSim): the reserved size
# from the entity list's bounding box (or the ground's side), the random transform (3 GetRandomItem draws unless
# disable_transform), the ground tiles in ReserveSpace's order, ReserveSpace, then each entity at
# rcx + size - 0.5 + x * scale through Node:AddEntity without the random offset.

type Box is Data:
  Box{xmin: F64Repr.F64, xmax: F64Repr.F64, ymin: F64Repr.F64, ymax: F64Repr.F64}

def million() -> F64Repr.F64:
  F64Repr.from_u32(1000000)

def grown(+b: Box, +i: PopulateLayout.Item) -> Box:
  match b:
    case Box{+xmin, +xmax, +ymin, +ymax}:
      match i:
        case PopulateLayout.Item{_, +x, +y, _}:
          Box{F64Repr.pick(F64Cmp.lt(x, xmin), x, xmin), F64Repr.pick(F64Cmp.gt(x, xmax), x, xmax), F64Repr.pick(F64Cmp.lt(y, ymin), y, ymin), F64Repr.pick(F64Cmp.gt(y, ymax), y, ymax)}

def bounds(items: List<&2, PopulateLayout.Item>, +b: Box) -> Box:
  match items:
    case Nil{}:
      b
    case Con{+i, rest}:
      bounds(rest, grown(b, i))

def scale_of(bits: U32 & U32) -> F64Repr.F64:
  (+hi, +lo) = bits
  F64Repr.F64{hi, lo}

def half_extent(+b: Box) -> F64Repr.F64:
  match b:
    case Box{+xmin, +xmax, +ymin, +ymax}:
      +w = F64Arith.mul(F64Arith.sub(xmax, xmin), F64Repr.half())
      +h = F64Arith.mul(F64Arith.sub(ymax, ymin), F64Repr.half())
      F64Repr.pick(F64Cmp.lt(w, h), h, w)

# The transform: switch_xy and the two flips (1 or -1 as True/False: True = 1).
type Turn is Data:
  Turn{switch: Bool, fx: Bool, fy: Bool}

def turned_y(got: U32 & Pcg.Rng, +switch: Bool, +fx: Bool) -> Turn & Pcg.Rng:
  (+v, rng) = got
  (Turn{switch, fx, U32.is_eq(v, 1)}, rng)

def turned_x(got: U32 & Pcg.Rng, +switch: Bool) -> Turn & Pcg.Rng:
  (+v, rng) = got
  turned_y(MathRandom.random_upto(rng, 2), switch, U32.is_eq(v, 1))

def turned(got: U32 & Pcg.Rng) -> Turn & Pcg.Rng:
  (+v, rng) = got
  turned_x(MathRandom.random_upto(rng, 2), U32.is_eq(v, 1))

def turn(fixed: Bool, rng: Pcg.Rng) -> Turn & Pcg.Rng:
  match fixed:
    case True{}:
      (Turn{False{}, False{}, True{}}, rng)
    case False{}:
      turned(MathRandom.random_upto(rng, 2))

# layout.force_rotation's translation (switch_xy, flip_x, flip_y) for LAYOUT_ROTATION 0..3.
def forced(+rotation: U32) -> Turn:
  match rotation:
    case 0:
      Turn{False{}, False{}, True{}}
    case 1:
      Turn{True{}, True{}, True{}}
    case 2:
      Turn{False{}, True{}, False{}}
    case _:
      Turn{True{}, False{}, False{}}

def rotated(got: Turn & Pcg.Rng, +rotation: U32) -> Turn & Pcg.Rng:
  (+random, rng) = got
  (Bool.pick(Turn, Blob.is_none(rotation), random, forced(rotation)), rng)

# The transform of layout variant v: the random turn (drawn unless disable_transform) unless the layout forces a rotation.
def turn_of(+v: U32, rng: Pcg.Rng) -> Turn & Pcg.Rng:
  rotated(turn(Layouts.has(v, Layouts.flag_disable_transform()), rng), Layouts.force_rotation(v))

def flipped(+keep: Bool, +n: U32, +k: U32) -> U32:
  Bool.pick(U32, keep, k, (n - 1 - k : U32))

def ground_index(+t: Turn, +n: U32, +column: U32, +row: U32) -> U32:
  match t:
    case Turn{+switch, +fx, +fy}:
      +rw = flipped(fy, n, Bool.pick(U32, switch, column, row))
      +clmn = flipped(fx, n, Bool.pick(U32, switch, row, column))
      (rw * n + clmn : U32)

def ground_at(+v: U32, +t: Turn, +n: U32, +column: U32, +row: U32) -> U32:
  Layouts.ground_tile(v, ground_index(t, n, column, row))

def unpack_ground(units: List<&2, U32>, tiles: Array<U32>, +k: U32) -> Array<U32>:
  match units:
    case Nil{}:
      tiles
    case Con{+u, rest}:
      tiles[k] <- (u .&. 1023 : U32)
      tiles[(k + 1 : U32)] <- (u >> 10n : U32)
      unpack_ground(rest, tiles, (k + 2 : U32))

def pushed(got: Array<U32> & U32, +acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  (tiles, +v) = got
  (tiles, v <> acc)

def ground_loop(k: Nat, got: Array<U32> & List<&2, U32>, +t: Turn, +n: U32, +q: U32) -> List<&2, U32>:
  match k:
    case 0n:
      (_, +acc) = got
      acc
    case 1n+p:
      (tiles, +acc) = got
      ground_loop(p, pushed(tiles[ground_index(t, n, (q / n : U32), (q % n : U32))], acc), t, n, (q - 1 : U32))

def ground_decoded(empty: Bool, +v: U32, +t: Turn, +n: U32) -> List<&2, U32>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      +cells = (n * n : U32)
      ground_loop(U32.to_nat(cells), (unpack_ground(Layouts.ground(v), [0 : U32^10n], 0), Nil{}), t, n, (cells - 1 : U32))

# The ground tiles as ReserveAndPlaceLayout lists them: column outer, row inner, transformed (0 = keep the tile).
# The variant's ground row is decoded once (sizes up to 30 x 30).
def ground(+v: U32, +t: Turn) -> List<&2, U32>:
  +n = Layouts.ground_size(v)
  ground_decoded(U32.is_zero(n), v, t, n)

def item_x(+t: Turn, +i: PopulateLayout.Item) -> F64Repr.F64:
  match t:
    case Turn{+switch, +fx, +fy}:
      match i:
        case PopulateLayout.Item{_, +x, +y, _}:
          Bool.pick(F64Repr.F64, switch, F64Repr.pick(fy, y, F64Repr.neg(y)), F64Repr.pick(fx, x, F64Repr.neg(x)))

def item_y(+t: Turn, +i: PopulateLayout.Item) -> F64Repr.F64:
  match t:
    case Turn{+switch, +fx, +fy}:
      match i:
        case PopulateLayout.Item{_, +x, +y, _}:
          Bool.pick(F64Repr.F64, switch, F64Repr.pick(fx, x, F64Repr.neg(x)), F64Repr.pick(fy, y, F64Repr.neg(y)))

def item_prefab(+i: PopulateLayout.Item) -> U32:
  match i:
    case PopulateLayout.Item{+prefab, _, _, _}:
      prefab

def fixed_placed(got: Grid.Grid & Bool, +c: PopulateState.Ctx, +e: Entities.Ent, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>) -> PopulateState.Land:
  (g, _) = got
  PopulateState.added_in(c, PopulateState.Land{g, rng, ents, events}, e)

def fixed_on(land: Bool, g: Grid.Grid, +c: PopulateState.Ctx, +prefab: U32, +px: F64Repr.F64, +py: F64Repr.F64, +ix: U32, +iy: U32, rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>) -> PopulateState.Land:
  match land:
    case False{}:
      PopulateState.Land{g, rng, ents, events}
    case True{}:
      +e = Entities.entity(prefab, px, py, PopulateState.width_of(c), PopulateState.height_of(c), False{}, rng)
      fixed_placed(Points.reserve_tile(g, ix, iy), c, e, Entities.rng_of(e), ents, events)

def fixed_tile(got: Grid.Grid & U32, +c: PopulateState.Ctx, +prefab: U32, +px: F64Repr.F64, +py: F64Repr.F64, +ix: U32, +iy: U32, rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>) -> PopulateState.Land:
  (g, +tile) = got
  fixed_on(TileGroups.is_land(tile), g, c, prefab, px, py, ix, iy, rng, ents, events)

# Node:AddEntity(prefab, {px}, {py}, 1, ..., rand_offset = false).
def add_fixed(+c: PopulateState.Ctx, +prefab: U32, +px: F64Repr.F64, +py: F64Repr.F64, l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      +ix = Points.lua_int(px)
      +iy = Points.lua_int(py)
      fixed_tile(Points.get_tile(g, ix, iy), c, prefab, px, py, ix, iy, rng, ents, events)

# Where the layout's centre is: rcx, rcy after `+ size - 0.5`, the transform and the scale.
type Frame is Data:
  Frame{cx: F64Repr.F64, cy: F64Repr.F64, turn: Turn, scale: F64Repr.F64}

def place_items(items: List<&2, PopulateLayout.Item>, +f: Frame, +c: PopulateState.Ctx, l: PopulateState.Land) -> PopulateState.Land:
  match items:
    case Nil{}:
      l
    case Con{+i, rest}:
      match f:
        case Frame{+cx, +cy, +t, +scale}:
          +px = F64Arith.add(cx, F64Arith.mul(item_x(t, i), scale))
          +py = F64Arith.add(cy, F64Arith.mul(item_y(t, i), scale))
          place_items(rest, Frame{cx, cy, t, scale}, c, add_fixed(c, item_prefab(i), px, py, l))

# The transform as SETP's bits: 1 switch_xy, 2 flip_x = -1, 4 flip_y = -1.
def turn_bits(+t: Turn) -> U32:
  match t:
    case Turn{+switch, +fx, +fy}:
      (Bool.to_u32(switch) .|. (Bool.to_u32(Bool.not(fx)) << 1n) .|. (Bool.to_u32(Bool.not(fy)) << 2n) : U32)

def piece_after(got: PopulateState.Land & U32, +p: PopulateSetpiece.Piece, +from: U32) -> PopulateState.Land:
  (l, +to) = got
  PopulateState.noted(l, PopulateState.EPiece{PopulateSetpiece.with_members(p, from, to)})

def piece_before(got: PopulateState.Land & U32, +c: PopulateState.Ctx, +items: List<&2, PopulateLayout.Item>, +f: Frame, +p: PopulateSetpiece.Piece) -> PopulateState.Land:
  (l, +from) = got
  piece_after(PopulateState.counted(place_items(items, f, c, l)), p, from)

def placed_recorded(on: Bool, l: PopulateState.Land, +c: PopulateState.Ctx, +items: List<&2, PopulateLayout.Item>, +f: Frame, +p: PopulateSetpiece.Piece) -> PopulateState.Land:
  match on:
    case False{}:
      place_items(items, f, c, l)
    case True{}:
      piece_before(PopulateState.counted(l), c, items, f, p)

def corner(+v: U32, +size: F64Repr.F64) -> F64Repr.F64:
  F64Arith.sub(F64Arith.add(F64Repr.from_u32(v), size), F64Repr.half())

def place_if(ok: Bool, l: PopulateState.Land, +c: PopulateState.Ctx, +items: List<&2, PopulateLayout.Item>, +f: Frame, +cx: F64Repr.F64, +cy: F64Repr.F64, +p: PopulateSetpiece.Piece) -> PopulateState.Land:
  match ok:
    case False{}:
      l
    case True{}:
      match f p:
        case Frame{_, _, +t, +scale} PopulateSetpiece.Piece{+name, +source, _, _, _, +half, _, _}:
          placed_recorded(PopulateState.pieces_of(c), l, c, items, Frame{cx, cy, t, scale}, PopulateSetpiece.Piece{name, source, turn_bits(t), cx, cy, half, 0, 0})

def reserved(r: Points.Reserved, +c: PopulateState.Ctx, +node: U32, +ask: Points.Ask, +pos: U32, +items: List<&2, PopulateLayout.Item>, +f: Frame, +size: F64Repr.F64, +before: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>, +p: PopulateSetpiece.Piece) -> PopulateState.Land:
  match r:
    case Points.Reserved{g, +rng, +ok, +x, +y, +n}:
      match ask:
        case Points.Ask{+fsize, +start, +fill}:
          place_if(ok, PopulateState.Land{g, rng, ents, PopulateState.EReserve{node, F32Ops.bits(fsize), start, fill, pos, n, before, rng, ok, x, y} <> events}, c,
            items, f, corner(x, size), corner(y, size), p)

def ground_size(+v: U32, +size: F64Repr.F64) -> F64Repr.F64:
  +n = Layouts.ground_size(v)
  F64Repr.pick(U32.is_zero(n), size, F64Arith.mul(F64Repr.from_u32(n), F64Repr.half()))

def or_zero(+v: U32) -> U32:
  Bool.pick(U32, Blob.is_none(v), 0, v)

def position_of(+v: U32) -> U32:
  or_zero(Layouts.layout_position(v))

def placed_turn(got: Turn & Pcg.Rng, +c: PopulateState.Ctx, +node: U32, +v: U32, +items: List<&2, PopulateLayout.Item>, +size: F64Repr.F64, g: Grid.Grid, +ents: List<&2, Entities.Ent>, +events: List<&2, PopulateState.Ev>, +name: U32, +source: U32) -> PopulateState.Land:
  (+t, +rng) = got
  +sized = ground_size(v, size)
  +ask = {Points.Ask{F32Ops.from_f64(sized), or_zero(Layouts.start_mask(v)), or_zero(Layouts.fill_mask(v))} : Points.Ask}
  +site = PopulateState.site_of(c, node)
  +f = {Frame{F64Repr.zero(), F64Repr.zero(), t, scale_of(Layouts.scale(v))} : Frame}
  reserved(Points.reserve_space(PopulateState.windows_of(c), PopulateState.sites_of(c), site, ask, position_of(v), ground(v, t), g, rng), c, node, ask, position_of(v),
    items, f, sized, rng, ents, events, PopulateSetpiece.Piece{name, source, 0, F64Repr.zero(), F64Repr.zero(), sized, 0, 0})

# ReserveAndPlaceLayout(node, layout, prefabs, add_fn) for the layout variant v, named `name` (string id) and from
# `source` (populate/setpiece.bend) when the context records the placed layouts.
def place(+c: PopulateState.Ctx, +node: U32, +name: U32, +source: U32, +v: U32, +items: List<&2, PopulateLayout.Item>, l: PopulateState.Land) -> PopulateState.Land:
  match l:
    case PopulateState.Land{g, +rng, +ents, +events}:
      +start = {Box{million(), F64Repr.neg(million()), million(), F64Repr.neg(million())} : Box}
      +size = F64Arith.mul(scale_of(Layouts.scale(v)), half_extent(bounds(items, start)))
      placed_turn(turn_of(v, rng), c, node, v, items, size, g, ents, events, name, source)
