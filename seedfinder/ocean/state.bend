import Base
import ../rng/pcg.bend as R
import ../f64/repr.bend as FR
import ../worldsim/grid.bend as GR
import ./ents.bend as OE

# The state of one attempt's ocean phase (land_done to the required prefab check) and what it records for the trace.

# Platform, prefab swap state, map size, and `tracing` to record the map digests and entity snapshots.
type Ctx is Data:
  Ctx{windows: Bool, swaps: U32, width: U32, height: U32, tracing: Bool}

# What happened, in execution order. Digest points `at`: 0 prefill, 1 fills, 2 noise, 3 blend, 4 shoreline, 5 void,
# 6 populate, 7 docks, 8 post, 9 bunches, 10 encoded. Snapshot points: 0 populate, 1 filter. EDocks and EBunches
# hold every entity after the step and how many of the newest it added.
type Ev is Data:
  EDigest{at: U32, rng: R.Rng, tiles: GR.Hash, mflags: GR.Hash, ids: GR.Hash}
  EBlend{k: U32, hash: GR.Hash}
  EPieces{tile: U32, total: U32, before: R.Rng, after: R.Rng}
  EAdd{prefab: U32, tx: FR.F64, ty: FR.F64, x: FR.F64, z: FR.F64, after: R.Rng}
  ECounts{at: U32, ents: List<&2, OE.Ent>}
  EDocks{before: R.Rng, after: R.Rng, ents: List<&2, OE.Ent>, added: U32}
  EWormholes{ents: List<&2, OE.Ent>}
  EBunches{before: R.Rng, after: R.Rng, ents: List<&2, OE.Ent>, added: U32}
  EFinal{ents: List<&2, OE.Ent>}
  EReq{prefab: U32, count: U32, have: U32}
  EStatus{ok: Bool, missing: List<&2, U32>, rng: R.Rng}

# The tile map (tiles and flags), the node-id map (0 x 0 when not tracked), the RNG, the entities (newest first), the
# topology node count and the events (newest first).
type Sea is Type:
  Sea{grid: GR.Grid, ids: GR.Grid, rng: R.Rng, ents: List<&2, OE.Ent>, topo: U32, events: List<&2, Ev>}

def width_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, _, +width, _, _}:
      width

def height_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, _, _, +height, _}:
      height

def swaps_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, +swaps, _, _, _}:
      swaps

def windows_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{+windows, _, _, _, _}:
      windows

def tracing_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{_, _, _, _, +tracing}:
      tracing

def flags_loop(n: Nat, got: Array<U32> & U32, +i: U32, h: GR.Hash) -> Array<U32> & GR.Hash:
  match n:
    case 0n:
      (cells, _) = got
      (cells, h)
    case 1n+p:
      (cells, +v) = got
      flags_loop(p, cells[(i + 1 : U32)], (i + 1 : U32), GR.fnv_u16(h, (v >> 16n : U32)))

def flags_done(r: Array<U32> & GR.Hash, +w: U32, +h: U32) -> GR.Grid & GR.Hash:
  (cells, hash) = r
  (GR.Grid{cells, w, h}, hash)

# FNV-1a 64 of width, height and every cell's stored flags (the oracle's `mflags`: the variant nibble is not stored).
def flags_digest(g: GR.Grid) -> GR.Grid & GR.Hash:
  match g:
    case GR.Grid{cells, +w, +h}:
      flags_done(flags_loop(U32.to_nat((w * h : U32)), cells[0], 0, GR.header(w, h)), w, h)

def noted_if(on: Bool, s: Sea, +ev: Ev) -> Sea:
  match on:
    case False{}:
      s
    case True{}:
      match s:
        case Sea{g, ids, +rng, +ents, +topo, +events}:
          Sea{g, ids, rng, ents, topo, ev <> events}

# Records an event when tracing.
def noted(+c: Ctx, s: Sea, +ev: Ev) -> Sea:
  noted_if(tracing_of(c), s, ev)

def hash_ids(got: GR.Grid & GR.Hash, g: GR.Grid, +at: U32, +rng: R.Rng, +tiles: GR.Hash, +mflags: GR.Hash, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, Ev>) -> Sea:
  (ids, +h) = got
  Sea{g, ids, rng, ents, topo, EDigest{at, rng, tiles, mflags, h} <> events}

def hash_flags(got: GR.Grid & GR.Hash, ids: GR.Grid, +at: U32, +rng: R.Rng, +tiles: GR.Hash, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, Ev>) -> Sea:
  (g, +mflags) = got
  hash_ids(GR.tiles_digest(ids), g, at, rng, tiles, mflags, ents, topo, events)

def hash_tiles(got: GR.Grid & GR.Hash, ids: GR.Grid, +at: U32, +rng: R.Rng, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, Ev>) -> Sea:
  (g, +tiles) = got
  hash_flags(flags_digest(g), ids, at, rng, tiles, ents, topo, events)

def digest_if(on: Bool, s: Sea, +at: U32) -> Sea:
  match on:
    case False{}:
      s
    case True{}:
      match s:
        case Sea{g, ids, +rng, +ents, +topo, +events}:
          hash_tiles(GR.tiles_digest(g), ids, at, rng, ents, topo, events)

# Records the map digests at a digest point when tracing.
def digest(+c: Ctx, s: Sea, +at: U32) -> Sea:
  digest_if(tracing_of(c), s, at)

def rng_of(s: Sea) -> Sea & R.Rng:
  match s:
    case Sea{g, ids, +rng, +ents, +topo, +events}:
      (Sea{g, ids, rng, ents, topo, events}, rng)

def ents_of(s: Sea) -> Sea & List<&2, OE.Ent>:
  match s:
    case Sea{g, ids, +rng, +ents, +topo, +events}:
      (Sea{g, ids, rng, ents, topo, events}, ents)

def with_rng(s: Sea, +rng: R.Rng) -> Sea:
  match s:
    case Sea{g, ids, _, +ents, +topo, +events}:
      Sea{g, ids, rng, ents, topo, events}

def with_ents(s: Sea, +ents: List<&2, OE.Ent>) -> Sea:
  match s:
    case Sea{g, ids, +rng, _, +topo, +events}:
      Sea{g, ids, rng, ents, topo, events}
