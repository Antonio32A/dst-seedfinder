import Base
import ../rng/pcg.bend as Pcg
import ../f64/repr.bend as F64Repr
import ../worldsim/grid.bend as Grid
import ../populate/setpiece.bend as PopulateSetpiece
import ./ents.bend as OceanEnts

# The state of one attempt's ocean phase (land_done to the required prefab check) and what it records for the trace.

# Platform, prefab swap state, map size, `tracing` to record the map digests and entity snapshots, and `pieces` the
# layouts placed (EPiece).
type Ctx is Data:
  Ctx{windows: Bool, swaps: U32, width: U32, height: U32, tracing: Bool, pieces: Bool}

# What happened, in execution order. Digest points `at`: 0 prefill, 1 fills, 2 noise, 3 blend, 4 shoreline, 5 void,
# 6 populate, 7 docks, 8 post, 9 bunches, 10 encoded. Snapshot points: 0 populate, 1 filter. EDocks and EBunches
# hold every entity after the step and how many of the newest it added.
# EPiece: a placed layout (the land's first), recorded with `pieces` whether tracing or not.
type Ev is Data:
  EDigest{at: U32, rng: Pcg.Rng, tiles: Grid.Hash, mflags: Grid.Hash, ids: Grid.Hash}
  EBlend{k: U32, hash: Grid.Hash}
  EPieces{tile: U32, total: U32, before: Pcg.Rng, after: Pcg.Rng}
  EAdd{prefab: U32, tx: F64Repr.F64, ty: F64Repr.F64, x: F64Repr.F64, z: F64Repr.F64, after: Pcg.Rng}
  ECounts{at: U32, ents: List<&2, OceanEnts.Ent>}
  EDocks{before: Pcg.Rng, after: Pcg.Rng, ents: List<&2, OceanEnts.Ent>, added: U32}
  EWormholes{ents: List<&2, OceanEnts.Ent>}
  EBunches{before: Pcg.Rng, after: Pcg.Rng, ents: List<&2, OceanEnts.Ent>, added: U32}
  EFinal{ents: List<&2, OceanEnts.Ent>}
  EReq{prefab: U32, count: U32, have: U32}
  EStatus{ok: Bool, missing: List<&2, U32>, rng: Pcg.Rng}
  EPiece{piece: PopulateSetpiece.Piece}

# The tile map (tiles and flags), the node-id map (0 x 0 when not tracked), the RNG, the entities (newest first), the
# topology node count and the events (newest first).
type Sea is Type:
  Sea{grid: Grid.Grid, ids: Grid.Grid, rng: Pcg.Rng, ents: List<&2, OceanEnts.Ent>, topo: U32, events: List<&2, Ev>}

def width_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, _, +width, _, _, _}:
      width

def height_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, _, _, +height, _, _}:
      height

def swaps_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, +swaps, _, _, _, _}:
      swaps

def windows_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{+windows, _, _, _, _, _}:
      windows

def pieces_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{_, _, _, _, _, +pieces}:
      pieces

def tracing_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{_, _, _, _, +tracing, _}:
      tracing

def flags_loop(n: Nat, got: Array<U32> & U32, +i: U32, h: Grid.Hash) -> Array<U32> & Grid.Hash:
  match n:
    case 0n:
      (cells, _) = got
      (cells, h)
    case 1n+p:
      (cells, +v) = got
      flags_loop(p, cells[(i + 1 : U32)], (i + 1 : U32), Grid.fnv_u16(h, (v >> 16n : U32)))

def flags_done(r: Array<U32> & Grid.Hash, +w: U32, +h: U32) -> Grid.Grid & Grid.Hash:
  (cells, hash) = r
  (Grid.Grid{cells, w, h}, hash)

# FNV-1a 64 of width, height and every cell's stored flags (the oracle's `mflags`: the variant nibble is not stored).
def flags_digest(g: Grid.Grid) -> Grid.Grid & Grid.Hash:
  match g:
    case Grid.Grid{cells, +w, +h}:
      flags_done(flags_loop(U32.to_nat((w * h : U32)), cells[0], 0, Grid.header(w, h)), w, h)

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

def hash_ids(got: Grid.Grid & Grid.Hash, g: Grid.Grid, +at: U32, +rng: Pcg.Rng, +tiles: Grid.Hash, +mflags: Grid.Hash, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, Ev>) -> Sea:
  (ids, +h) = got
  Sea{g, ids, rng, ents, topo, EDigest{at, rng, tiles, mflags, h} <> events}

def hash_flags(got: Grid.Grid & Grid.Hash, ids: Grid.Grid, +at: U32, +rng: Pcg.Rng, +tiles: Grid.Hash, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, Ev>) -> Sea:
  (g, +mflags) = got
  hash_ids(Grid.tiles_digest(ids), g, at, rng, tiles, mflags, ents, topo, events)

def hash_tiles(got: Grid.Grid & Grid.Hash, ids: Grid.Grid, +at: U32, +rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, Ev>) -> Sea:
  (g, +tiles) = got
  hash_flags(flags_digest(g), ids, at, rng, tiles, ents, topo, events)

def digest_if(on: Bool, s: Sea, +at: U32) -> Sea:
  match on:
    case False{}:
      s
    case True{}:
      match s:
        case Sea{g, ids, +rng, +ents, +topo, +events}:
          hash_tiles(Grid.tiles_digest(g), ids, at, rng, ents, topo, events)

# Records the map digests at a digest point when tracing.
def digest(+c: Ctx, s: Sea, +at: U32) -> Sea:
  digest_if(tracing_of(c), s, at)

def rng_of(s: Sea) -> Sea & Pcg.Rng:
  match s:
    case Sea{g, ids, +rng, +ents, +topo, +events}:
      (Sea{g, ids, rng, ents, topo, events}, rng)

def ents_of(s: Sea) -> Sea & List<&2, OceanEnts.Ent>:
  match s:
    case Sea{g, ids, +rng, +ents, +topo, +events}:
      (Sea{g, ids, rng, ents, topo, events}, ents)

def with_rng(s: Sea, +rng: Pcg.Rng) -> Sea:
  match s:
    case Sea{g, ids, _, +ents, +topo, +events}:
      Sea{g, ids, rng, ents, topo, events}

def with_ents(s: Sea, +ents: List<&2, OceanEnts.Ent>) -> Sea:
  match s:
    case Sea{g, ids, +rng, _, +topo, +events}:
      Sea{g, ids, rng, ents, topo, events}

def pieces_loop(evs: List<&2, Ev>, +acc: List<&2, PopulateSetpiece.Piece>) -> List<&2, PopulateSetpiece.Piece>:
  match evs:
    case Nil{}:
      acc
    case Con{EPiece{+p}, rest}:
      pieces_loop(rest, p <> acc)
    case Con{_, rest}:
      pieces_loop(rest, acc)

# The EPiece records of the events (newest first), in placement order.
def pieces(+evs: List<&2, Ev>) -> List<&2, PopulateSetpiece.Piece>:
  pieces_loop(evs, Nil{})

def count_loop(evs: List<&2, Ev>, +n: U32) -> U32:
  match evs:
    case Nil{}:
      n
    case Con{EPiece{_}, rest}:
      count_loop(rest, (n + 1 : U32))
    case Con{_, rest}:
      count_loop(rest, n)

# How many EPiece records the events hold.
def piece_count(+evs: List<&2, Ev>) -> U32:
  count_loop(evs, 0)
