import Base
import ../rng/pcg.bend as Pcg
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/random.bend as F64Random

# savedata.ents entries as PopulateWorld_AddEntity writes them: x = floor(((tile_x - width / 2) * 4 [+ r * 2 - 1])
# * 100) / 100 in doubles (the same for z from tile_y), in insertion order across all prefabs.

# One entity: prefab string id, the tile coordinates it was given, its x/z and x/z * 100 (the integers the rounding
# kept, two's complement), and the RNG after its draws (the prefabdata call included).
type Ent is Data:
  Ent{prefab: U32, tx: F64Repr.F64, ty: F64Repr.F64, x: F64Repr.F64, z: F64Repr.F64, xk: U32, zk: U32, rng: Pcg.Rng}

def hundred() -> F64Repr.F64:
  F64Repr.from_u32(100)

def tile_scale() -> F64Repr.F64:
  F64Repr.from_u32(4)

def centred(+t: F64Repr.F64, +size: U32) -> F64Repr.F64:
  F64Arith.mul(F64Arith.sub(t, F64Arith.mul(F64Repr.from_u32(size), F64Repr.half())), tile_scale())

# r * 2 for a math.random() value r (0 or a normal number in (0, 1)): the exponent plus one.
def twice(+r: F64Repr.F64) -> F64Repr.F64:
  match r:
    case F64Repr.F64{+hi, +lo}:
      F64Repr.pick(F64Repr.is_zero(r), r, F64Repr.F64{(hi + 1048576 : U32), lo})

def jittered(+v: F64Repr.F64, +r: F64Repr.F64) -> F64Repr.F64:
  F64Arith.sub(F64Arith.add(v, twice(r)), F64Repr.one())

def floored_hundredths(+v: F64Repr.F64) -> F64Repr.F64:
  F64Repr.floor(F64Arith.mul(v, hundred()))

type Placed is Data:
  Placed{x: F64Repr.F64, z: F64Repr.F64, rng: Pcg.Rng}

def offset_z(+x: F64Repr.F64, +z: F64Repr.F64, got: F64Repr.F64 & Pcg.Rng) -> Placed:
  (+r, rng) = got
  Placed{x, jittered(z, r), rng}

def offset_x(+z: F64Repr.F64, +x: F64Repr.F64, got: F64Repr.F64 & Pcg.Rng) -> Placed:
  (+r, rng) = got
  offset_z(jittered(x, r), z, F64Random.random(rng))

def offsets(jitter: Bool, +x: F64Repr.F64, +z: F64Repr.F64, rng: Pcg.Rng) -> Placed:
  match jitter:
    case False{}:
      Placed{x, z, rng}
    case True{}:
      offset_x(z, x, F64Random.random(rng))

def rounded(+prefab: U32, +tx: F64Repr.F64, +ty: F64Repr.F64, +p: Placed) -> Ent:
  match p:
    case Placed{+x, +z, +rng}:
      +xh = floored_hundredths(x)
      +zh = floored_hundredths(z)
      Ent{prefab, tx, ty, F64Arith.div(xh, hundred()), F64Arith.div(zh, hundred()), F64Repr.to_i32(xh), F64Repr.to_i32(zh), rng}

# PopulateWorld_AddEntity's position for a map of width x height: with `jitter` (rand_offset nil or true) x and then
# z get math.random() * 2 - 1 added (2 draws).
def entity(+prefab: U32, +tx: F64Repr.F64, +ty: F64Repr.F64, +width: U32, +height: U32, jitter: Bool, rng: Pcg.Rng) -> Ent:
  rounded(prefab, tx, ty, offsets(jitter, centred(tx, width), centred(ty, height), rng))

# (t - size / 2) * 4 for an integer tile coordinate: every double step is exact, so it is the integer 4t - 2 size.
def centred_tile(+t: U32, +size: U32) -> F64Repr.F64:
  F64Repr.from_i32(((t * 4 : U32) - (size * 2 : U32) : U32))

# `entity` for integer tile coordinates x, y (below 2^29).
def tile_entity(+prefab: U32, +x: U32, +y: U32, +width: U32, +height: U32, jitter: Bool, rng: Pcg.Rng) -> Ent:
  rounded(prefab, F64Repr.from_u32(x), F64Repr.from_u32(y), offsets(jitter, centred_tile(x, width), centred_tile(y, height), rng))

def with_rng(+e: Ent, +rng: Pcg.Rng) -> Ent:
  match e:
    case Ent{+prefab, +tx, +ty, +x, +z, +xk, +zk, _}:
      Ent{prefab, tx, ty, x, z, xk, zk, rng}

def rng_of(+e: Ent) -> Pcg.Rng:
  match e:
    case Ent{_, _, _, _, _, _, _, +rng}:
      rng
