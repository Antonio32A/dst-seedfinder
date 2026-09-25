import Base
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ../f32/ops.bend as FO
import ../data/blob.bend as B
import ../data/constants.bend as KC
import ../data/enums.bend as EN
import ../data/ocean.bend as OC
import ../data/ocean_convert.bend as OD
import ../worldsim/grid.bend as GR
import ../worldsim/tiles/groups.bend as TG
import ./convert_plane.bend as OP
import ./convert_fills.bend as OF

# Ocean_ConvertImpassibleToWater's do_blend: three WorldSim:GenerateBlendedMap calls (encode.cpp: each tile's level
# as a float, a horizontal then a vertical pass of the float kernel, zero padding, sums in tap order) and the tile
# choice per ocean or impassable tile. All sums are of non-negative terms from +0, so a zero term or a tap past the
# map adds exactly nothing, and the passes can run tap by tap over whole rows. The levels compare as doubles:
# (double)float is exact, the edge falloff is a multiple of 1/4, so every product is exact.
#
# The blend array holds, N = w * h cells each: the cm, g and el results, one map's source and pass buffer, then
# the block planes, the kernel and a tile -> level table.

type Level is Data:
  Level{tile: U32, bits: U32}

def f32_bits_of(bits: U32 & U32) -> U32:
  (+hi, +lo) = bits
  FR.to_f32_bits(FR.F64{hi, lo})

def level_row(+row: List<&2, U32>) -> Level:
  Level{B.at(row, 0), f32_bits_of(B.f64(row, 1))}

def el_rows(n: Nat, +i: U32) -> List<&2, Level>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      level_row(OC.config_ellevels(i)) <> el_rows(p, (i + 1 : U32))

# A map's (tile, level) rows in table order (a later duplicate overrides an earlier one, as GenerateBlendedMap's
# unordered_map does) and its default level, as F32 bits.
type Levels is Data:
  Levels{rows: List<&2, Level>, fallback: U32}

def el_levels() -> Levels:
  Levels{el_rows(U32.to_nat(OC.config_ellevels_count()), 0), f32_bits_of(OD.el_default())}

def cm_levels() -> Levels:
  Levels{[Level{OD.cm_level_tile(), f32_bits_of(OD.cm_level_value())}], f32_bits_of(OD.cm_default())}

def g_levels() -> Levels:
  Levels{[Level{OD.g_level_tile(), f32_bits_of(OD.g_level_value())}], f32_bits_of(OD.g_default())}

def cm_base(+n: U32) -> U32:
  0

def g_base(+n: U32) -> U32:
  n

def el_base(+n: U32) -> U32:
  (2 * n : U32)

def src_base(+n: U32) -> U32:
  (3 * n : U32)

def tmp_base(+n: U32) -> U32:
  (4 * n : U32)

def zero_go(n: Nat, a: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      a[i] <- 0
      zero_go(p, a, (i + 1 : U32))

def fill_go(n: Nat, a: Array<U32>, +i: U32, +v: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      a[i] <- v
      fill_go(p, a, (i + 1 : U32), v)

def lut_rows(rows: List<&2, Level>, o: Array<U32>, +lut: U32) -> Array<U32>:
  match rows:
    case Nil{}:
      o
    case Con{Level{+t, +bits}, rest}:
      o[(lut + (t .&. 65535) : U32)] <- bits
      lut_rows(rest, o, lut)

# The tile -> level table (65536 entries from `lut` on) of a map.
def lut_fill(o: Array<U32>, +lut: U32, +l: Levels) -> Array<U32>:
  match l:
    case Levels{+rows, +fallback}:
      lut_rows(rows, fill_go(65536n, o, lut, fallback), lut)

def source_level(got: Array<U32> & U32, cells: Array<U32>, +at: U32) -> Array<U32> & Array<U32>:
  (o, +v) = got
  o[at] <- v
  (cells, o)

def source_cell(got: Array<U32> & U32, o: Array<U32>, +at: U32, +lut: U32) -> Array<U32> & Array<U32>:
  (cells, +v) = got
  source_level(o[(lut + GR.tile_of(v) : U32)], cells, at)

def source_go(n: Nat, got: Array<U32> & Array<U32>, +i: U32, +base: U32, +lut: U32) -> Array<U32> & Array<U32>:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, o) = got
      source_go(p, source_cell(cells[i], o, (base + i : U32), lut), (i + 1 : U32), base, lut)

def acc_got(got: Array<U32> & U32, +v: F32, +w: F32, +dst: U32) -> Array<U32>:
  (a, +t) = got
  a[dst] <- FO.bits(FO.add(FO.from_bits(t), FO.mul(w, v)))

def tap_step(got: Array<U32> & U32, +dst: U32, +w: F32) -> Array<U32>:
  (a, +v) = got
  acc_got(a[dst], FO.from_bits(v), w, dst)

# a[dst + j] += w * a[src + j] for j < n, in F32.
def tap_run(n: Nat, a: Array<U32>, +src: U32, +dst: U32, +w: F32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      tap_run(p, tap_step(a[src], dst, w), (src + 1 : U32), (dst + 1 : U32), w)

def half() -> U32:
  (OD.kernel_size() >> 1n : U32)

def first_valid(+c: U32) -> U32:
  Bool.pick(U32, (c < half() : U32), (half() - c : U32), 0)

def end_valid(+c: U32, +size: U32) -> U32:
  Bool.pick(U32, (c > half() : U32), (size + half() - c : U32), size)

# One blur: map size, words per mask row, and the source, pass-buffer, result and kernel bases in the blend array.
type Blur is Data:
  Blur{w: U32, h: U32, ww: U32, src: U32, tmp: U32, out: U32, kernel: U32}

def max_u32(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a < b : U32), b, a)

def min_u32(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (b < a : U32), b, a)

def htap_weighted(got: Array<U32> & U32, +b: Blur, +y: U32, +x0: U32, +x1: U32, +c: U32) -> Array<U32>:
  (o, +wb) = got
  match b:
    case Blur{+w, _, _, +src, +tmp, _, _}:
      +lo = max_u32(x0, first_valid(c))
      +hi = max_u32(lo, min_u32(x1, end_valid(c, w)))
      +row = (y * w : U32)
      tap_run(U32.to_nat((hi - lo : U32)), o, (src + row + lo + c - half() : U32), (tmp + row + lo : U32), FO.from_bits(wb))

def htap_block(n: Nat, o: Array<U32>, +b: Blur, +y: U32, +x0: U32, +x1: U32, +c: U32) -> Array<U32>:
  match n:
    case 0n:
      o
    case 1n+p:
      match b:
        case Blur{_, _, _, _, _, _, +kb}:
          htap_block(p, htap_weighted(o[(kb + c : U32)], b, y, x0, x1, c), b, y, x0, x1, (c + 1 : U32))

def vtap_weighted(got: Array<U32> & U32, +live: Bool, +b: Blur, +yy: U32, +y: U32, +x0: U32, +k: U32) -> Array<U32>:
  (o, +wb) = got
  match b:
    case Blur{+w, _, _, _, +tmp, +out, _}:
      +n = Bool.pick(U32, live, k, 0)
      tap_run(U32.to_nat(n), o, (tmp + yy * w + x0 : U32), (out + y * w + x0 : U32), FO.from_bits(wb))

def vtap_block(n: Nat, o: Array<U32>, +b: Blur, +y: U32, +x0: U32, +k: U32, +r: U32) -> Array<U32>:
  match n:
    case 0n:
      o
    case 1n+p:
      match b:
        case Blur{_, +h, _, _, _, _, +kb}:
          +yy = (y + r - half() : U32)
          vtap_block(p, vtap_weighted(o[(kb + r : U32)], (yy < h : U32), b, yy, y, x0, k), b, y, x0, k, (r + 1 : U32))

def block_cells(+b: Blur, +j: U32) -> U32:
  match b:
    case Blur{+w, _, _, _, _, _, _}:
      min_u32((w - j * 32 : U32), 32)

def hblock(o: Array<U32>, +b: Blur, +y: U32, +j: U32) -> Array<U32>:
  htap_block(U32.to_nat(OD.kernel_size()), o, b, y, (j * 32 : U32), (j * 32 + block_cells(b, j) : U32), 0)

def vblock(o: Array<U32>, +b: Blur, +y: U32, +j: U32) -> Array<U32>:
  vtap_block(U32.to_nat(OD.kernel_size()), o, b, y, (j * 32 : U32), block_cells(b, j), 0)

def cblock(o: Array<U32>, +b: Blur, +y: U32, +j: U32) -> Array<U32>:
  match b:
    case Blur{+w, _, _, _, +tmp, _, _}:
      zero_go(U32.to_nat(block_cells(b, j)), o, (tmp + y * w + j * 32 : U32))

# kind 0: the horizontal pass of the block's cells, 1: the vertical pass, 2: clear the block's pass buffer.
def block(+kind: U32, o: Array<U32>, +b: Blur, +y: U32, +j: U32) -> Array<U32>:
  match kind:
    case 0:
      hblock(o, b, y, j)
    case 1:
      vblock(o, b, y, j)
    case _:
      cblock(o, b, y, j)

def block_if(hit: Bool, o: Array<U32>, +kind: U32, +b: Blur, +y: U32, +j: U32) -> Array<U32>:
  match hit:
    case True{}:
      block(kind, o, b, y, j)
    case False{}:
      o

def block_read(got: Array<U32> & U32, +kind: U32, +b: Blur, +y: U32, +j: U32) -> Array<U32>:
  (o, +m) = got
  block_if(U32.is_ne(m, 0), o, kind, b, y, j)

def blocks_go(n: Nat, o: Array<U32>, +kind: U32, +b: Blur, +mask: U32, +y: U32, +j: U32) -> Array<U32>:
  match n:
    case 0n:
      o
    case 1n+p:
      match b:
        case Blur{_, _, +ww, _, _, _, _}:
          +wrap = U32.is_eq((j + 1 : U32), ww)
          done = block_read(o[(mask + y * ww + j : U32)], kind, b, y, j)
          blocks_go(p, done, kind, b, mask, Bool.pick(U32, wrap, (y + 1 : U32), y), Bool.pick(U32, wrap, 0, (j + 1 : U32)))

def fork_depth() -> Nat:
  5n

def blocks_leaf(got: Array<U32> & Array<U32>, +kind: U32, +b: Blur, +mask: U32, +y: U32, +rows: U32) -> Array<U32>:
  (o, other) = got
  match b:
    case Blur{_, _, +ww, _, _, _, _}:
      Array.join(U32, blocks_go(U32.to_nat((rows * ww : U32)), o, kind, b, mask, y, 0), other)

# The block op for every 32-cell block whose word in the mask plane at `mask` is nonzero, rows split over a balanced
# fork tree sharing the blend array (each leaf writes only its own rows).
def blocks_par(+d: Nat, got: Array<U32> & Array<U32>, +kind: U32, +b: Blur, +mask: U32, +y: U32, +rows: U32) -> Array<U32>:
  match d:
    case 0n:
      blocks_leaf(got, kind, b, mask, y, rows)
    case 1n+p:
      (l, r) = got
      +half = (rows >> 1n : U32)
      top bottom = blocks_par(p, Array.fork(U32, l), kind, b, mask, y, half) blocks_par(p, Array.fork(U32, r), kind, b, mask, (y + half : U32), (rows - half : U32))
      Array.join(U32, top, bottom)

def blocks(o: Array<U32>, +kind: U32, +b: Blur, +mask: U32) -> Array<U32>:
  match b:
    case Blur{_, +h, _, _, _, _, _}:
      blocks_par(fork_depth(), Array.fork(U32, o), kind, b, mask, 0, h)

def plane_at(+n: U32, +g: OP.Geo, +k: U32) -> U32:
  (5 * n + OP.base(g, k) : U32)

def kernel_base(+n: U32, +g: OP.Geo) -> U32:
  plane_at(n, g, 4)

def put_kernel(n: Nat, o: Array<U32>, +at: U32, +c: U32) -> Array<U32>:
  match n:
    case 0n:
      o
    case 1n+p:
      o[(at + c : U32)] <- KC.blur_weight(c)
      put_kernel(p, o, at, (c + 1 : U32))

def lut_base(+n: U32, +g: OP.Geo) -> U32:
  (kernel_base(n, g) + OD.kernel_size() : U32)

def blurred(got: Array<U32> & Array<U32>, +w: U32, +h: U32, +out: U32) -> Array<U32> & Array<U32>:
  (cells, o) = got
  +n = (w * h : U32)
  +g = OP.geo(w, h)
  +b = {Blur{w, h, OP.words_of(w), src_base(n), tmp_base(n), out, kernel_base(n, g)} : Blur}
  +z = plane_at(n, g, 0)
  +mh = plane_at(n, g, 1)
  +mv = plane_at(n, g, 2)
  across = OP.word_spread(OP.nonzero(o, g, z, src_base(n)), g, mh, z)
  down = OP.vspread(across, g, mv, mh, plane_at(n, g, 3), half())
  (cells, blocks(blocks(blocks(down, 0, b, mh), 1, b, mv), 2, b, mh))

# GenerateBlendedMap(kernelSize, sigma, levels, default) into the blend array from `out` on. Only the blocks within
# half the kernel (< 32) of a nonzero source are summed (the others are exactly zero).
def blend_map(got: Array<U32> & Array<U32>, +w: U32, +h: U32, +l: Levels, +out: U32) -> Array<U32> & Array<U32>:
  (cells, o) = got
  +n = (w * h : U32)
  +g = OP.geo(w, h)
  +lut = lut_base(n, g)
  blurred(source_go(U32.to_nat(n), (cells, lut_fill(o, lut, l)), 0, src_base(n), lut), w, h, out)

def blank(+size: U32) -> Array<U32>:
  GR.alloc(GR.depth_for(24n, size, 0n, 1), 0)

def maps_done(got: Array<U32> & Array<U32>, +w: U32, +h: U32) -> GR.Grid & Array<U32>:
  (cells, o) = got
  (GR.Grid{cells, w, h}, o)

# The three blended maps of do_blend in call order (cm: OCEAN_BRINEPOOL, g: OCEAN_HAZARDOUS, el: ellevels), as F32
# bits in one array: cm from 0, g from N, el from 2N (then one map's source and pass buffer, planes, the kernel and
# a tile -> level table).
def maps(g: GR.Grid) -> GR.Grid & Array<U32>:
  match g:
    case GR.Grid{cells, +w, +h}:
      +n = (w * h : U32)
      +geo = OP.geo(w, h)
      o = put_kernel(U32.to_nat(OD.kernel_size()), blank((lut_base(n, geo) + 65536 : U32)), kernel_base(n, geo), 0)
      cm = blend_map((cells, o), w, h, cm_levels(), cm_base(n))
      gm = blend_map(cm, w, h, g_levels(), g_base(n))
      maps_done(blend_map(gm, w, h, el_levels(), el_base(n)), w, h)

def is_sea(+tile: U32) -> Bool:
  TG.is_ocean(tile) || U32.is_eq(tile, EN.tile_impassable())

def hash_go(n: Nat, got: Array<U32> & U32, +i: U32, +acc: GR.Hash) -> Array<U32> & GR.Hash:
  match n:
    case 0n:
      (o, _) = got
      (o, acc)
    case 1n+p:
      (o, +v) = got
      hash_go(p, o[(i + 1 : U32)], (i + 1 : U32), GR.fnv_u32(acc, v))

# FNV-1a 64 over the F32 bits of the n cells from `base` on (the oracle's `oblend` hash).
def map_hash(o: Array<U32>, +base: U32, +n: U32) -> Array<U32> & GR.Hash:
  hash_go(U32.to_nat(n), o[base], base, GR.fnv_offset())

def smallest_above(+t: FR.F64) -> F32:
  +r = FR.to_f32_bits(t)
  FO.from_bits(Bool.pick(U32, FC.gt(FR.from_f32_bits(r), t), r, (r + 1 : U32)))

def f64_of(bits: U32 & U32) -> FR.F64:
  (+hi, +lo) = bits
  FR.F64{hi, lo}

# The first F32 above final_level_shallow and final_level_medium (a non-negative float is above the double level
# exactly when it is at least that float).
type Rule is Data:
  Rule{shallow: F32, medium: F32, coral_hi: U32, coral_lo: U32, grave_hi: U32, grave_lo: U32, zero_grave: Bool}

def rule_of(+coral: FR.F64, +grave: FR.F64) -> Rule:
  match coral grave:
    case FR.F64{+ch, +cl} FR.F64{+gh, +gl}:
      Rule{smallest_above(f64_of(OD.final_level_shallow())), smallest_above(f64_of(OD.final_level_medium())),
        ch, cl, gh, gl, FC.gt(FR.zero(), grave)}

def rule() -> Rule:
  rule_of(f64_of(OD.final_level_coral()), f64_of(OD.final_level_grave()))

def between(inside: Bool, +edge: U32, +near: U32, +far: U32) -> FR.F64:
  match inside:
    case True{}:
      FA.div(FR.from_i32((edge - near : U32)), FR.from_i32((far - near : U32)))
    case False{}:
      Bool.pick(FR.F64, (edge >= far : U32), FR.one(), FR.zero())

# getEdgeFalloff(x, y, w, h, WARN_RANGE + near, WARN_RANGE + far, low, high): math.clamp(dist, 0.0, 1.0) answers
# 1.0 from the far edge distance on (an integer quotient of at least 1) and 0.0 up to the near one.
def falloff(+x: U32, +y: U32, +w: U32, +h: U32) -> FR.F64:
  +edge = min_u32(min_u32(x, (w - x : U32)), min_u32(y, (h - y : U32)))
  +near = (OD.warn_range() + OD.falloff_near() : U32)
  +far = (OD.warn_range() + OD.falloff_far() : U32)
  +low = f64_of(OD.falloff_low())
  +high = f64_of(OD.falloff_high())
  FA.add(FA.mul(FA.sub(high, low), between((edge > near : U32) && (edge < far : U32), edge, near, far)), low)

def scaled_above(+level: F32, +x: U32, +y: U32, +w: U32, +h: U32, +t: FR.F64) -> Bool:
  FC.gt(FA.mul(FO.to_f64(level), falloff(x, y, w, h)), t)

def deep_route(zero: Bool, +gl: F32, +r: Rule, +x: U32, +y: U32, +w: U32, +h: U32) -> Bool:
  match zero:
    case True{}:
      match r:
        case Rule{_, _, _, _, _, _, +zero_grave}:
          zero_grave
    case False{}:
      match r:
        case Rule{_, _, _, _, +gh, +glo, _}:
          scaled_above(gl, x, y, w, h, FR.F64{gh, glo})

def brine_route(brine: Bool, +cl: F32, +r: Rule, +x: U32, +y: U32, +w: U32, +h: U32) -> Bool:
  match brine:
    case True{}:
      match r:
        case Rule{_, _, +ch, +clo, _, _, _}:
          scaled_above(cl, x, y, w, h, FR.F64{ch, clo})
    case False{}:
      False{}

def shallow_route(waterlog: Bool, +tile: U32, +cl: F32, +r: Rule, +x: U32, +y: U32, +w: U32, +h: U32) -> U32:
  match waterlog:
    case True{}:
      tile
    case False{}:
      +brine = brine_route(U32.is_eq(tile, EN.tile_ocean_brinepool()), cl, r, x, y, w, h)
      Bool.pick(U32, brine, tile, EN.tile_ocean_coastal())

def medium_route(medium: Bool, +gl: F32, +r: Rule, +x: U32, +y: U32, +w: U32, +h: U32) -> U32:
  match medium:
    case True{}:
      EN.tile_ocean_swell()
    case False{}:
      +hit = deep_route(U32.is_eq(FO.bits(gl), 0), gl, r, x, y, w, h)
      Bool.pick(U32, hit, EN.tile_ocean_hazardous(), EN.tile_ocean_rough())

def level_route(shallow: Bool, +tile: U32, +el: F32, +cl: F32, +gl: F32, +r: Rule, +x: U32, +y: U32, +w: U32, +h: U32) -> U32:
  match shallow:
    case True{}:
      shallow_route(U32.is_eq(tile, EN.tile_ocean_waterlog()), tile, cl, r, x, y, w, h)
    case False{}:
      match r:
        case Rule{_, +medium, _, _, _, _, _}:
          medium_route(FO.le(medium, el), gl, r, x, y, w, h)

# The do_blend loop's tile for an ocean or impassable tile with blended levels el, cm and g at (x, y).
def blended_tile(+tile: U32, +el: F32, +cl: F32, +gl: F32, +r: Rule, +x: U32, +y: U32, +w: U32, +h: U32) -> U32:
  match r:
    case Rule{+shallow, _, _, _, _, _, _}:
      level_route(FO.le(shallow, el), tile, el, cl, gl, r, x, y, w, h)

type Spot is Data:
  Spot{i: U32, x: U32, y: U32, w: U32, h: U32, n: U32}

def spot_next(+s: Spot) -> Spot:
  match s:
    case Spot{+i, +x, +y, +w, +h, +n}:
      +last = U32.is_eq((x + 1 : U32), w)
      Spot{(i + 1 : U32), Bool.pick(U32, last, 0, (x + 1 : U32)), Bool.pick(U32, last, (y + 1 : U32), y), w, h, n}

def with_g(got: Array<U32> & U32, cells: Array<U32>, +v: U32, +el: F32, +cl: F32, +s: Spot, +r: Rule) -> Array<U32> & Array<U32>:
  (o, +gl) = got
  match s:
    case Spot{+i, +x, +y, +w, +h, _}:
      cells[i] <- OF.set_tile(blended_tile(GR.tile_of(v), el, cl, FO.from_bits(gl), r, x, y, w, h), v)
      (cells, o)

def with_cm(got: Array<U32> & U32, cells: Array<U32>, +v: U32, +el: F32, +s: Spot, +r: Rule) -> Array<U32> & Array<U32>:
  (o, +cl) = got
  match s:
    case Spot{+i, _, _, _, _, +n}:
      with_g(o[(g_base(n) + i : U32)], cells, v, el, FO.from_bits(cl), s, r)

def with_el(got: Array<U32> & U32, cells: Array<U32>, +v: U32, +s: Spot, +r: Rule) -> Array<U32> & Array<U32>:
  (o, +el) = got
  match s:
    case Spot{+i, _, _, _, _, +n}:
      with_cm(o[(cm_base(n) + i : U32)], cells, v, FO.from_bits(el), s, r)

def cell_route(sea: Bool, cells: Array<U32>, o: Array<U32>, +v: U32, +s: Spot, +r: Rule) -> Array<U32> & Array<U32>:
  match sea:
    case True{}:
      match s:
        case Spot{+i, _, _, _, _, +n}:
          with_el(o[(el_base(n) + i : U32)], cells, v, s, r)
    case False{}:
      (cells, o)

def cell_read(got: Array<U32> & U32, o: Array<U32>, +s: Spot, +r: Rule) -> Array<U32> & Array<U32>:
  (cells, +v) = got
  cell_route(is_sea(GR.tile_of(v)), cells, o, v, s, r)

def apply_go(n: Nat, got: Array<U32> & Array<U32>, +s: Spot, +r: Rule) -> Array<U32> & Array<U32>:
  match n:
    case 0n:
      got
    case 1n+p:
      (cells, o) = got
      match s:
        case Spot{+i, _, _, _, _, _}:
          apply_go(p, cell_read(cells[i], o, s, r), spot_next(s), r)

def applied(got: Array<U32> & Array<U32>, +w: U32, +h: U32) -> GR.Grid:
  (cells, _) = got
  GR.Grid{cells, w, h}

# The do_blend loop over the map with the three blended maps of `maps`.
def apply(g: GR.Grid, o: Array<U32>) -> GR.Grid:
  match g:
    case GR.Grid{cells, +w, +h}:
      +n = (w * h : U32)
      applied(apply_go(U32.to_nat(n), (cells, o), Spot{0, 0, 0, w, h, n}, rule()), w, h)

def mapped(got: GR.Grid & Array<U32>) -> GR.Grid:
  (g, o) = got
  apply(g, o)

# do_blend: the three blended maps, then each ocean or IMPASSABLE tile's new tile.
def blend(g: GR.Grid) -> GR.Grid:
  mapped(maps(g))
