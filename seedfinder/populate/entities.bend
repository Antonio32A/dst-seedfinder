import Base
import ../rng/pcg.bend as R
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/random.bend as FRN

# savedata.ents entries as PopulateWorld_AddEntity writes them: x = floor(((tile_x - width / 2) * 4 [+ r * 2 - 1])
# * 100) / 100 in doubles (the same for z from tile_y), in insertion order across all prefabs.

# One entity: prefab string id, the tile coordinates it was given, its x/z and x/z * 100 (the integers the rounding
# kept, two's complement), and the RNG after its draws (the prefabdata call included).
type Ent is Data:
  Ent{prefab: U32, tx: FR.F64, ty: FR.F64, x: FR.F64, z: FR.F64, xk: U32, zk: U32, rng: R.Rng}

def hundred() -> FR.F64:
  FR.from_u32(100)

def tile_scale() -> FR.F64:
  FR.from_u32(4)

def centred(+t: FR.F64, +size: U32) -> FR.F64:
  FA.mul(FA.sub(t, FA.mul(FR.from_u32(size), FR.half())), tile_scale())

# r * 2 for a math.random() value r (0 or a normal number in (0, 1)): the exponent plus one.
def twice(+r: FR.F64) -> FR.F64:
  match r:
    case FR.F64{+hi, +lo}:
      FR.pick(FR.is_zero(r), r, FR.F64{(hi + 1048576 : U32), lo})

def jittered(+v: FR.F64, +r: FR.F64) -> FR.F64:
  FA.sub(FA.add(v, twice(r)), FR.one())

def floored_hundredths(+v: FR.F64) -> FR.F64:
  FR.floor(FA.mul(v, hundred()))

type Placed is Data:
  Placed{x: FR.F64, z: FR.F64, rng: R.Rng}

def offset_z(+x: FR.F64, +z: FR.F64, got: FR.F64 & R.Rng) -> Placed:
  (+r, rng) = got
  Placed{x, jittered(z, r), rng}

def offset_x(+z: FR.F64, +x: FR.F64, got: FR.F64 & R.Rng) -> Placed:
  (+r, rng) = got
  offset_z(jittered(x, r), z, FRN.random(rng))

def offsets(jitter: Bool, +x: FR.F64, +z: FR.F64, rng: R.Rng) -> Placed:
  match jitter:
    case False{}:
      Placed{x, z, rng}
    case True{}:
      offset_x(z, x, FRN.random(rng))

def rounded(+prefab: U32, +tx: FR.F64, +ty: FR.F64, +p: Placed) -> Ent:
  match p:
    case Placed{+x, +z, +rng}:
      +xh = floored_hundredths(x)
      +zh = floored_hundredths(z)
      Ent{prefab, tx, ty, FA.div(xh, hundred()), FA.div(zh, hundred()), FR.to_i32(xh), FR.to_i32(zh), rng}

# PopulateWorld_AddEntity's position for a map of width x height: with `jitter` (rand_offset nil or true) x and then
# z get math.random() * 2 - 1 added (2 draws).
def entity(+prefab: U32, +tx: FR.F64, +ty: FR.F64, +width: U32, +height: U32, jitter: Bool, rng: R.Rng) -> Ent:
  rounded(prefab, tx, ty, offsets(jitter, centred(tx, width), centred(ty, height), rng))

# (t - size / 2) * 4 for an integer tile coordinate: every double step is exact, so it is the integer 4t - 2 size.
def centred_tile(+t: U32, +size: U32) -> FR.F64:
  FR.from_i32(((t * 4 : U32) - (size * 2 : U32) : U32))

# `entity` for integer tile coordinates x, y (below 2^29).
def tile_entity(+prefab: U32, +x: U32, +y: U32, +width: U32, +height: U32, jitter: Bool, rng: R.Rng) -> Ent:
  rounded(prefab, FR.from_u32(x), FR.from_u32(y), offsets(jitter, centred_tile(x, width), centred_tile(y, height), rng))

def with_rng(+e: Ent, +rng: R.Rng) -> Ent:
  match e:
    case Ent{+prefab, +tx, +ty, +x, +z, +xk, +zk, _}:
      Ent{prefab, tx, ty, x, z, xk, zk, rng}

def rng_of(+e: Ent) -> R.Rng:
  match e:
    case Ent{_, _, _, _, _, _, _, +rng}:
      rng
