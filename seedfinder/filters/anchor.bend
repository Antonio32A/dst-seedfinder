import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ./walk.bend as Walk
import ./world.bend as FilterWorld

# Walk anchors (docs/config.md section 5): an instance on a land tile enters there with offset 0; any other instance
# enters at the land tile whose centre is nearest (Euclidean, as world.py computes it in doubles; ties to the lowest
# ty*W + tx) with that distance as offset. The search scans Chebyshev rings of tiles around the instance with exact
# integer squared distances (coordinates are hundredths), then breaks exact ties with world.py's doubles.

type Anchor is Data:
  Anchor{tile: U32, offset: F64Repr.F64, length: Walk.Length}

# An instance with its walk anchor (None when the world has no land tile).
type Point is Data:
  Point{inst: FilterWorld.Inst, anchor: Maybe<&2, Anchor>}

def depth_for(n: Nat, +size: U32, +d: Nat) -> Nat:
  match n:
    case 0n:
      d
    case 1n+p:
      Bool.pick(Nat, (U32.from_nat(Nat.pow(2n, d)) >= size : U32), d, depth_for(p, size, Nat.add(d, 1n)))

# The depth of the smallest power-of-two array holding `size` cells.
def depth_of(+size: U32) -> Nat:
  depth_for(24n, size, 0n)

def land_bit(+tile: U32) -> U32:
  Bool.to_u32(FilterWorld.is_land_tile(tile))

def written_pair(a: Array<U32>, +i: U32, +word: U32) -> Array<U32>:
  a[i] <- land_bit((word .&. 65535 : U32))
  a[(i + 1 : U32)] <- land_bit((word >> 16n : U32))

def land_cells(words: List<&2, U32>, +i: U32, a: Array<U32>) -> Array<U32>:
  match words:
    case Nil{}:
      a
    case Con{+word, rest}:
      land_cells(rest, (i + 2 : U32), written_pair(a, i, word))

# A cell array with 1 on land tiles and 0 elsewhere (index ty*W + tx), of 2^depth cells.
def land_array(+world: FilterWorld.World, +depth: Nat) -> Array<U32>:
  match world:
    case FilterWorld.World{_, _, _, _, _, _, +tiles}:
      land_cells(tiles, 0, [0 : U32^depth])

def is_negative(+v: U32) -> Bool:
  (v >= 2147483648 : U32)

def magnitude(+v: U32) -> U32:
  Bool.pick(U32, is_negative(v), (0 - v : U32), v)

# Map:GetTileCoordsAtPoint for one axis from hundredths: trunc((v/100 + 2 + 2*size) / 4) toward zero (exact for
# coordinates with two decimals); 4294967295 when the point is left of the map.
def tile_coordinate(+k: U32, +size: U32) -> U32:
  +v = (k + 200 + size * 200 : U32)
  Bool.pick(U32, is_negative(v), Bool.pick(U32, (magnitude(v) < 400 : U32), 0, 4294967295), (v / 400 : U32))

def clamped_coordinate(+k: U32, +size: U32) -> U32:
  +v = (k + 200 + size * 200 : U32)
  +t = Bool.pick(U32, is_negative(v), 0, (v / 400 : U32))
  Bool.pick(U32, (t >= size : U32), (size - 1 : U32), t)

# The centre of tile t in hundredths: (t - size/2) * 400.
def centre(+t: U32, +size: U32) -> U32:
  (t * 400 - size * 200 : U32)

def squared(+v: U32) -> Nat:
  +m = U32.to_nat(magnitude(v))
  Nat.mul(m, m)

type Ring is Data:
  Ring{best: Nat, found: Bool, ties: List<&2, U32>}

def ring_update(+ring: Ring, +s: Nat, +index: U32) -> Ring:
  match ring:
    case Ring{+best, +found, +ties}:
      Bool.pick(Ring, Bool.not(found) || Nat.is_lt(s, best), Ring{s, True{}, [index]},
        Bool.pick(Ring, Nat.is_eq(s, best), Ring{best, True{}, index <> ties}, ring))

type Probe is Data:
  Probe{xk: U32, zk: U32, width: U32, height: U32}

def tile_distance(+p: Probe, +tx: U32, +ty: U32) -> Nat:
  match p:
    case Probe{+xk, +zk, +w, +h}:
      Nat.add(squared((centre(tx, w) - xk : U32)), squared((centre(ty, h) - zk : U32)))

def probe_width(+p: Probe) -> U32:
  match p:
    case Probe{_, _, +w, _}:
      w

def probed(got: Array<U32> & U32, +p: Probe, +tx: U32, +ty: U32, +ring: Ring) -> Array<U32> & Ring:
  (land, +cell) = got
  (land, Bool.pick(Ring, U32.is_eq(cell, 1), ring_update(ring, tile_distance(p, tx, ty), (ty * probe_width(p) + tx : U32)), ring))

def inside(+p: Probe, +tx: U32, +ty: U32) -> Bool:
  match p:
    case Probe{_, _, +w, +h}:
      (tx < w : U32) && (ty < h : U32)

def probe_at(on_map: Bool, land: Array<U32>, +p: Probe, +tx: U32, +ty: U32, +ring: Ring) -> Array<U32> & Ring:
  match on_map:
    case True{}:
      probed(land[(ty * probe_width(p) + tx : U32)], p, tx, ty, ring)
    case False{}:
      (land, ring)

def probe_tile(land: Array<U32>, +p: Probe, +tx: U32, +ty: U32, +ring: Ring) -> Array<U32> & Ring:
  probe_at(inside(p, tx, ty), land, p, tx, ty, ring)

def scan_row(n: Nat, got: Array<U32> & Ring, +p: Probe, +tx: U32, +ty: U32) -> Array<U32> & Ring:
  match n:
    case 0n:
      got
    case 1n+k:
      (land, +ring) = got
      scan_row(k, probe_tile(land, p, tx, ty, ring), p, (tx + 1 : U32), ty)

def scan_column(n: Nat, got: Array<U32> & Ring, +p: Probe, +tx: U32, +ty: U32) -> Array<U32> & Ring:
  match n:
    case 0n:
      got
    case 1n+k:
      (land, +ring) = got
      scan_column(k, probe_tile(land, p, tx, ty, ring), p, tx, (ty + 1 : U32))

def ring_columns(got: Array<U32> & Ring, +p: Probe, +cx: U32, +cy: U32, +r: U32) -> Array<U32> & Ring:
  +span = U32.to_nat((r * 2 - 1 : U32))
  scan_column(span, scan_column(span, got, p, (cx - r : U32), (cy - r + 1 : U32)), p, (cx + r : U32), (cy - r + 1 : U32))

def ring_tiles(first: Bool, land: Array<U32>, +p: Probe, +cx: U32, +cy: U32, +r: U32, +ring: Ring) -> Array<U32> & Ring:
  match first:
    case True{}:
      probe_tile(land, p, cx, cy, ring)
    case False{}:
      +span = U32.to_nat((r * 2 + 1 : U32))
      ring_columns(scan_row(span, scan_row(span, (land, ring), p, (cx - r : U32), (cy - r : U32)), p, (cx - r : U32), (cy + r : U32)), p, cx, cy, r)

def far_enough(+ring: Ring, +next_ring: U32, +slack: U32) -> Bool:
  match ring:
    case Ring{+best, +found, _}:
      +reach = (next_ring * 400 : U32)
      +gap = U32.to_nat((reach - slack : U32))
      found && (reach > slack : U32) && Nat.is_gt(Nat.mul(gap, gap), best)

# The land array, the nearest tiles so far, and whether the rings scanned so far suffice.
type Scan is Type:
  Scan{land: Array<U32>, ring: Ring, stop: Bool}

def scanned(got: Array<U32> & Ring, +next_ring: U32, +slack: U32) -> Scan:
  (land, +ring) = got
  Scan{land, ring, far_enough(ring, next_ring, slack)}

def ring_search(n: Nat, s: Scan, +p: Probe, +cx: U32, +cy: U32, +r: U32, +slack: U32) -> Scan:
  match n s:
    case 1n+k Scan{land, +ring, False{}}:
      ring_search(k, scanned(ring_tiles(U32.is_zero(r), land, p, cx, cy, r, ring), (r + 1 : U32), slack), p, cx, cy, (r + 1 : U32), slack)
    case _ other:
      other

def signed_double(+v: U32) -> F64Repr.F64:
  F64Repr.from_i32(v)

def centre_double(+t: U32, +size: U32) -> F64Repr.F64:
  signed_double((t * 4 - size * 2 : U32))

def centre_squared(+inst: FilterWorld.Inst, +w: U32, +h: U32, +index: U32) -> F64Repr.F64:
  match inst:
    case FilterWorld.Inst{_, _, +x, +z, _, _, _}:
      +dx = F64Arith.sub(centre_double((index % w : U32), w), x)
      +dz = F64Arith.sub(centre_double((index / w : U32), h), z)
      F64Arith.add(F64Arith.mul(dx, dx), F64Arith.mul(dz, dz))

type Nearest is Data:
  Nearest{squared: F64Repr.F64, index: U32}

def nearest_tie(ties: List<&2, U32>, +inst: FilterWorld.Inst, +w: U32, +h: U32, +best: Nearest) -> Nearest:
  match ties best:
    case Nil{} _:
      best
    case Con{+index, rest} Nearest{+bs, +bi}:
      +s = centre_squared(inst, w, h, index)
      +better = F64Cmp.lt(s, bs) || (F64Cmp.eq(s, bs) && (index < bi : U32))
      nearest_tie(rest, inst, w, h, Bool.pick(Nearest, better, Nearest{s, index}, Nearest{bs, bi}))

def anchor_of_nearest(n: Nearest) -> Maybe<&2, Anchor>:
  match n:
    case Nearest{+s, +index}:
      +offset = F64Arith.sqrt(s)
      Some{Anchor{index, offset, Walk.of_double(offset)}}

def anchor_of_ring(+inst: FilterWorld.Inst, +w: U32, +h: U32, ring: Ring) -> Maybe<&2, Anchor>:
  match ring:
    case Ring{_, True{}, Con{+first, +rest}}:
      anchor_of_nearest(nearest_tie(rest, inst, w, h, Nearest{centre_squared(inst, w, h, first), first}))
    case _:
      None{}

def with_anchor(s: Scan, +inst: FilterWorld.Inst, +w: U32, +h: U32) -> Array<U32> & Maybe<&2, Anchor>:
  match s:
    case Scan{land, ring, _}:
      (land, anchor_of_ring(inst, w, h, ring))

def slack_of(+inst: FilterWorld.Inst, +w: U32, +h: U32, +cx: U32, +cy: U32) -> U32:
  match inst:
    case FilterWorld.Inst{_, _, _, _, +xk, +zk, _}:
      U32.max(magnitude((centre(cx, w) - xk : U32)), magnitude((centre(cy, h) - zk : U32)))

def nearest_land(land: Array<U32>, +inst: FilterWorld.Inst, +w: U32, +h: U32) -> Array<U32> & Maybe<&2, Anchor>:
  match inst:
    case FilterWorld.Inst{_, _, _, _, +xk, +zk, _}:
      +cx = clamped_coordinate(xk, w)
      +cy = clamped_coordinate(zk, h)
      +rings = U32.to_nat((U32.max(w, h) + 2 : U32))
      with_anchor(ring_search(rings, Scan{land, Ring{0n, False{}, Nil{}}, False{}}, Probe{xk, zk, w, h}, cx, cy, 0, slack_of(inst, w, h, cx, cy)), inst, w, h)

def own_or_nearest(on_land: Bool, land: Array<U32>, +inst: FilterWorld.Inst, +index: U32, +w: U32, +h: U32) -> Array<U32> & Maybe<&2, Anchor>:
  match on_land:
    case True{}:
      (land, Some{Anchor{index, F64Repr.zero(), Walk.zero()}})
    case False{}:
      nearest_land(land, inst, w, h)

def own_tile(got: Array<U32> & U32, +inst: FilterWorld.Inst, +index: U32, +w: U32, +h: U32) -> Array<U32> & Maybe<&2, Anchor>:
  (land, +cell) = got
  own_or_nearest(U32.is_eq(cell, 1), land, inst, index, w, h)

def anchor_on(on_map: Bool, land: Array<U32>, +inst: FilterWorld.Inst, +index: U32, +w: U32, +h: U32) -> Array<U32> & Maybe<&2, Anchor>:
  match on_map:
    case True{}:
      own_tile(land[index], inst, index, w, h)
    case False{}:
      nearest_land(land, inst, w, h)

# The anchor of an instance (world.py walk_anchor), given the land array of its world.
def anchor(land: Array<U32>, +inst: FilterWorld.Inst, +w: U32, +h: U32) -> Array<U32> & Maybe<&2, Anchor>:
  match inst:
    case FilterWorld.Inst{_, _, _, _, +xk, +zk, _}:
      +tx = tile_coordinate(xk, w)
      +ty = tile_coordinate(zk, h)
      anchor_on((tx < w : U32) && (ty < h : U32), land, inst, (ty * w + tx : U32), w, h)

def pointed(got: Array<U32> & Maybe<&2, Anchor>, +inst: FilterWorld.Inst) -> Array<U32> & Maybe<&2, Point>:
  (land, found) = got
  (land, Some{Point{inst, found}})

def pushed(pending: Maybe<&2, Point>, acc: List<&2, Point>) -> List<&2, Point>:
  match pending:
    case None{}:
      acc
    case Some{point}:
      point <> acc

def point_list(insts: List<&2, FilterWorld.Inst>, got: Array<U32> & Maybe<&2, Point>, +w: U32, +h: U32, acc: List<&2, Point>) -> Array<U32> & List<&2, Point>:
  match insts:
    case Nil{}:
      (land, pending) = got
      (land, List.reverse(&2, Point, pushed(pending, acc)))
    case Con{+inst, rest}:
      (land, pending) = got
      point_list(rest, pointed(anchor(land, inst, w, h), inst), w, h, pushed(pending, acc))

# The instances with their anchors, given the land array of their world.
def points(insts: List<&2, FilterWorld.Inst>, land: Array<U32>, +w: U32, +h: U32) -> Array<U32> & List<&2, Point>:
  point_list(insts, (land, None{}), w, h, Nil{})
