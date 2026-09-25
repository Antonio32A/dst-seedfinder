import Base
import ../rng/pcg.bend as R
import ../lua/math_random.bend as LM
import ../f32/ops.bend as FO
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ../data/blob.bend as B
import ../data/layouts.bend as LY
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/groups.bend as TG
import ./entities.bend as PE
import ./layout.bend as PL
import ./state.bend as PS

# object_layout.lua's ReserveAndPlaceLayout for ConvertGround's layouts (position nil, WorldSim): the reserved size
# from the entity list's bounding box (or the ground's side), the random transform (3 GetRandomItem draws unless
# disable_transform), the ground tiles in ReserveSpace's order, ReserveSpace, then each entity at
# rcx + size - 0.5 + x * scale through Node:AddEntity without the random offset.

type Box is Data:
  Box{xmin: FR.F64, xmax: FR.F64, ymin: FR.F64, ymax: FR.F64}

def million() -> FR.F64:
  FR.from_u32(1000000)

def grown(+b: Box, +i: PL.Item) -> Box:
  match b:
    case Box{+xmin, +xmax, +ymin, +ymax}:
      match i:
        case PL.Item{_, +x, +y, _}:
          Box{FR.pick(FC.lt(x, xmin), x, xmin), FR.pick(FC.gt(x, xmax), x, xmax), FR.pick(FC.lt(y, ymin), y, ymin), FR.pick(FC.gt(y, ymax), y, ymax)}

def bounds(items: List<&2, PL.Item>, +b: Box) -> Box:
  match items:
    case Nil{}:
      b
    case Con{+i, rest}:
      bounds(rest, grown(b, i))

def scale_of(bits: U32 & U32) -> FR.F64:
  (+hi, +lo) = bits
  FR.F64{hi, lo}

def half_extent(+b: Box) -> FR.F64:
  match b:
    case Box{+xmin, +xmax, +ymin, +ymax}:
      +w = FA.mul(FA.sub(xmax, xmin), FR.half())
      +h = FA.mul(FA.sub(ymax, ymin), FR.half())
      FR.pick(FC.lt(w, h), h, w)

# The transform: switch_xy and the two flips (1 or -1 as True/False: True = 1).
type Turn is Data:
  Turn{switch: Bool, fx: Bool, fy: Bool}

def turned_y(got: U32 & R.Rng, +switch: Bool, +fx: Bool) -> Turn & R.Rng:
  (+v, rng) = got
  (Turn{switch, fx, U32.is_eq(v, 1)}, rng)

def turned_x(got: U32 & R.Rng, +switch: Bool) -> Turn & R.Rng:
  (+v, rng) = got
  turned_y(LM.random_upto(rng, 2), switch, U32.is_eq(v, 1))

def turned(got: U32 & R.Rng) -> Turn & R.Rng:
  (+v, rng) = got
  turned_x(LM.random_upto(rng, 2), U32.is_eq(v, 1))

def turn(fixed: Bool, rng: R.Rng) -> Turn & R.Rng:
  match fixed:
    case True{}:
      (Turn{False{}, False{}, True{}}, rng)
    case False{}:
      turned(LM.random_upto(rng, 2))

def flipped(+keep: Bool, +n: U32, +k: U32) -> U32:
  Bool.pick(U32, keep, k, (n - 1 - k : U32))

def ground_index(+t: Turn, +n: U32, +column: U32, +row: U32) -> U32:
  match t:
    case Turn{+switch, +fx, +fy}:
      +rw = flipped(fy, n, Bool.pick(U32, switch, column, row))
      +clmn = flipped(fx, n, Bool.pick(U32, switch, row, column))
      (rw * n + clmn : U32)

def ground_at(+v: U32, +t: Turn, +n: U32, +column: U32, +row: U32) -> U32:
  LY.ground_tile(v, ground_index(t, n, column, row))

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
      ground_loop(U32.to_nat(cells), (unpack_ground(LY.ground(v), [0 : U32^10n], 0), Nil{}), t, n, (cells - 1 : U32))

# The ground tiles as ReserveAndPlaceLayout lists them: column outer, row inner, transformed (0 = keep the tile).
# The variant's ground row is decoded once (sizes up to 30 x 30).
def ground(+v: U32, +t: Turn) -> List<&2, U32>:
  +n = LY.ground_size(v)
  ground_decoded(U32.is_zero(n), v, t, n)

def item_x(+t: Turn, +i: PL.Item) -> FR.F64:
  match t:
    case Turn{+switch, +fx, +fy}:
      match i:
        case PL.Item{_, +x, +y, _}:
          Bool.pick(FR.F64, switch, FR.pick(fy, y, FR.neg(y)), FR.pick(fx, x, FR.neg(x)))

def item_y(+t: Turn, +i: PL.Item) -> FR.F64:
  match t:
    case Turn{+switch, +fx, +fy}:
      match i:
        case PL.Item{_, +x, +y, _}:
          Bool.pick(FR.F64, switch, FR.pick(fx, x, FR.neg(x)), FR.pick(fy, y, FR.neg(y)))

def item_prefab(+i: PL.Item) -> U32:
  match i:
    case PL.Item{+prefab, _, _, _}:
      prefab

def fixed_placed(got: GR.Grid & Bool, +c: PS.Ctx, +e: PE.Ent, +rng: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, PS.Ev>) -> PS.Land:
  (g, _) = got
  PS.added_in(c, PS.Land{g, rng, ents, events}, e)

def fixed_on(land: Bool, g: GR.Grid, +c: PS.Ctx, +prefab: U32, +px: FR.F64, +py: FR.F64, +ix: U32, +iy: U32, rng: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, PS.Ev>) -> PS.Land:
  match land:
    case False{}:
      PS.Land{g, rng, ents, events}
    case True{}:
      +e = PE.entity(prefab, px, py, PS.width_of(c), PS.height_of(c), False{}, rng)
      fixed_placed(PT.reserve_tile(g, ix, iy), c, e, PE.rng_of(e), ents, events)

def fixed_tile(got: GR.Grid & U32, +c: PS.Ctx, +prefab: U32, +px: FR.F64, +py: FR.F64, +ix: U32, +iy: U32, rng: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, PS.Ev>) -> PS.Land:
  (g, +tile) = got
  fixed_on(TG.is_land(tile), g, c, prefab, px, py, ix, iy, rng, ents, events)

# Node:AddEntity(prefab, {px}, {py}, 1, ..., rand_offset = false).
def add_fixed(+c: PS.Ctx, +prefab: U32, +px: FR.F64, +py: FR.F64, l: PS.Land) -> PS.Land:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      +ix = PT.lua_int(px)
      +iy = PT.lua_int(py)
      fixed_tile(PT.get_tile(g, ix, iy), c, prefab, px, py, ix, iy, rng, ents, events)

# Where the layout's centre is: rcx, rcy after `+ size - 0.5`, the transform and the scale.
type Frame is Data:
  Frame{cx: FR.F64, cy: FR.F64, turn: Turn, scale: FR.F64}

def place_items(items: List<&2, PL.Item>, +f: Frame, +c: PS.Ctx, l: PS.Land) -> PS.Land:
  match items:
    case Nil{}:
      l
    case Con{+i, rest}:
      match f:
        case Frame{+cx, +cy, +t, +scale}:
          +px = FA.add(cx, FA.mul(item_x(t, i), scale))
          +py = FA.add(cy, FA.mul(item_y(t, i), scale))
          place_items(rest, Frame{cx, cy, t, scale}, c, add_fixed(c, item_prefab(i), px, py, l))

def corner(+v: U32, +size: FR.F64) -> FR.F64:
  FA.sub(FA.add(FR.from_u32(v), size), FR.half())

def place_if(ok: Bool, l: PS.Land, +c: PS.Ctx, +items: List<&2, PL.Item>, +f: Frame, +cx: FR.F64, +cy: FR.F64) -> PS.Land:
  match ok:
    case False{}:
      l
    case True{}:
      match f:
        case Frame{_, _, +t, +scale}:
          place_items(items, Frame{cx, cy, t, scale}, c, l)

def reserved(r: PT.Reserved, +c: PS.Ctx, +node: U32, +ask: PT.Ask, +pos: U32, +items: List<&2, PL.Item>, +f: Frame, +size: FR.F64, +before: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, PS.Ev>) -> PS.Land:
  match r:
    case PT.Reserved{g, +rng, +ok, +x, +y, +n}:
      match ask:
        case PT.Ask{+fsize, +start, +fill}:
          place_if(ok, PS.Land{g, rng, ents, PS.EReserve{node, FO.bits(fsize), start, fill, pos, n, before, rng, ok, x, y} <> events}, c,
            items, f, corner(x, size), corner(y, size))

def ground_size(+v: U32, +size: FR.F64) -> FR.F64:
  +n = LY.ground_size(v)
  FR.pick(U32.is_zero(n), size, FA.mul(FR.from_u32(n), FR.half()))

def or_zero(+v: U32) -> U32:
  Bool.pick(U32, B.is_none(v), 0, v)

def position_of(+v: U32) -> U32:
  or_zero(LY.layout_position(v))

def placed_turn(got: Turn & R.Rng, +c: PS.Ctx, +node: U32, +v: U32, +items: List<&2, PL.Item>, +size: FR.F64, g: GR.Grid, +ents: List<&2, PE.Ent>, +events: List<&2, PS.Ev>) -> PS.Land:
  (+t, +rng) = got
  +sized = ground_size(v, size)
  +ask = {PT.Ask{FO.from_f64(sized), or_zero(LY.start_mask(v)), or_zero(LY.fill_mask(v))} : PT.Ask}
  +site = PS.site_of(c, node)
  +f = {Frame{FR.zero(), FR.zero(), t, scale_of(LY.scale(v))} : Frame}
  reserved(PT.reserve_space(PS.windows_of(c), PS.sites_of(c), site, ask, position_of(v), ground(v, t), g, rng), c, node, ask, position_of(v),
    items, f, sized, rng, ents, events)

# ReserveAndPlaceLayout(node, layout, prefabs, add_fn) for the layout variant v.
def place(+c: PS.Ctx, +node: U32, +v: U32, +items: List<&2, PL.Item>, l: PS.Land) -> PS.Land:
  match l:
    case PS.Land{g, +rng, +ents, +events}:
      +start = {Box{million(), FR.neg(million()), million(), FR.neg(million())} : Box}
      +size = FA.mul(scale_of(LY.scale(v)), half_extent(bounds(items, start)))
      placed_turn(turn(LY.has(v, LY.flag_disable_transform()), rng), c, node, v, items, size, g, ents, events)
