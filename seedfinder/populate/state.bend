import Base
import ../rng/pcg.bend as R
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/table.bend as TB
import ../storygen/graph.bend as GG
import ./entities.bend as PE
import ../f64/repr.bend as FR

# The land population state of one attempt (ConvertGround to the end of PopulateVoronoi) and what it runs on.

# The attempt's inputs: platform, prefab swap state, site point lists, the story graph, each story node's site (NONE
# when it has none) and the map size; `tracing` records the grid digests for the trace stage.
type Ctx is Data:
  Ctx{windows: Bool, swaps: U32, sites: PT.Sites, story: GG.St, site_of: TB.Tree<U32>, width: U32, height: U32, tracing: Bool, tiles_rng: R.Rng}

# A layout object as the trace reports it: prefab string id, x, y.
type Obj is Data:
  Obj{prefab: U32, x: FR.F64, y: FR.F64}

# What happened, in execution order (story nodes by index, layouts by string id).
type Ev is Data:
  EPoints{node: U32, n: U32, before: R.Rng, after: R.Rng, shuffled: List<&2, U32>, kept: List<&2, PT.Pt>}
  EReserve{node: U32, size: U32, start: U32, fill: U32, position: U32, n: U32, before: R.Rng, after: R.Rng, ok: Bool, x: U32, y: U32}
  EConvertNode{node: U32, before: R.Rng, after: R.Rng}
  ELayout{node: U32, name: U32, before: R.Rng}
  EItems{name: U32, items: List<&2, Obj>, before: R.Rng, after: R.Rng}
  EPlaced{after: R.Rng}
  EEntity{ent: PE.Ent}
  EPopulateNode{node: U32, before: R.Rng, after: R.Rng}
  ELand{populate: Bool, before: R.Rng, after: R.Rng}
  EDigest{at: U32, rng: R.Rng, tiles: GR.Hash, flags: GR.Hash}

# The grid, the RNG, the entities (newest first) and the events (newest first).
type Land is Type:
  Land{grid: GR.Grid, rng: R.Rng, ents: List<&2, PE.Ent>, events: List<&2, Ev>}

def site_of(+c: Ctx, +node: U32) -> U32:
  match c:
    case Ctx{_, _, _, _, +site_of, _, _, _, _}:
      TB.at(~U32, site_of, node)

def story_of(+c: Ctx) -> GG.St:
  match c:
    case Ctx{_, _, _, +story, _, _, _, _, _}:
      story

def sites_of(+c: Ctx) -> PT.Sites:
  match c:
    case Ctx{_, _, +sites, _, _, _, _, _, _}:
      sites

def windows_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{+windows, _, _, _, _, _, _, _, _}:
      windows

def swaps_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, +swaps, _, _, _, _, _, _, _}:
      swaps

def width_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, _, _, _, _, +width, _, _, _}:
      width

def height_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, _, _, _, _, _, +height, _, _}:
      height

def rng_of(l: Land) -> Land & R.Rng:
  match l:
    case Land{g, +rng, +ents, +events}:
      (Land{g, rng, ents, events}, rng)

def noted(l: Land, +ev: Ev) -> Land:
  match l:
    case Land{g, +rng, +ents, +events}:
      Land{g, rng, ents, ev <> events}

def added(l: Land, +e: PE.Ent) -> Land:
  match l:
    case Land{g, _, +ents, +events}:
      Land{g, PE.rng_of(e), e <> ents, EEntity{e} <> events}

def tracing_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{_, _, _, _, _, _, _, +tracing, _}:
      tracing

def entity_events(tracing: Bool, +e: PE.Ent, +events: List<&2, Ev>) -> List<&2, Ev>:
  match tracing:
    case True{}:
      EEntity{e} <> events
    case False{}:
      events

# `added`, with the EEntity event only when tracing (production skips the event list's copy of every entity).
def added_in(+c: Ctx, l: Land, +e: PE.Ent) -> Land:
  match l:
    case Land{g, _, +ents, +events}:
      Land{g, PE.rng_of(e), e <> ents, entity_events(tracing_of(c), e, events)}

def with_rng(l: Land, +rng: R.Rng) -> Land:
  match l:
    case Land{g, _, +ents, +events}:
      Land{g, rng, ents, events}

def digest_of(got: GR.Grid & GR.Hash, +tiles: GR.Hash, +at: U32, +rng: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, Ev>) -> Land:
  (g, +flags) = got
  Land{g, rng, ents, EDigest{at, rng, tiles, flags} <> events}

def digest_tiles(got: GR.Grid & GR.Hash, +c: Ctx, +at: U32, +rng: R.Rng, +ents: List<&2, PE.Ent>, +events: List<&2, Ev>) -> Land:
  (g, +tiles) = got
  match c:
    case Ctx{_, _, _, _, _, _, _, _, +tiles_rng}:
      digest_of(GR.flags_digest(g, tiles_rng), tiles, at, rng, ents, events)

def digest_if(on: Bool, l: Land, +c: Ctx, +at: U32) -> Land:
  match on:
    case False{}:
      l
    case True{}:
      match l:
        case Land{g, +rng, +ents, +events}:
          digest_tiles(GR.tiles_digest(g), c, at, rng, ents, events)

# The tile and flag digests of the grid now (0 ConvertGround, 1 ReplaceSingleNonLandTiles, 2 PopulateVoronoi), only
# when tracing.
def digest(l: Land, +c: Ctx, +at: U32) -> Land:
  match c:
    case Ctx{_, _, _, _, _, _, _, +tracing, _}:
      digest_if(tracing, l, c, at)

# The same context without the grid digests (production).
def untraced(+c: Ctx) -> Ctx:
  match c:
    case Ctx{+windows, +swaps, +sites, +story, +site_of, +width, +height, _, +tiles_rng}:
      Ctx{windows, swaps, sites, story, site_of, width, height, False{}, tiles_rng}
