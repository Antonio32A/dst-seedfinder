import Base
import ../rng/pcg.bend as Pcg
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/table.bend as TileTable
import ../storygen/graph.bend as StoryGraph
import ./entities.bend as Entities
import ./setpiece.bend as PopulateSetpiece
import ../f64/repr.bend as F64Repr

# The land population state of one attempt (ConvertGround to the end of PopulateVoronoi) and what it runs on.

# The attempt's inputs: platform, prefab swap state, site point lists, the story graph, each story node's site (NONE
# when it has none) and the map size; `tracing` records the grid digests for the trace stage, `pieces` the layouts
# placed (EPiece).
type Ctx is Data:
  Ctx{windows: Bool, swaps: U32, sites: Points.Sites, story: StoryGraph.St, site_of: TileTable.Tree<U32>, width: U32, height: U32, tracing: Bool, tiles_rng: Pcg.Rng, pieces: Bool}

# A layout object as the trace reports it: prefab string id, x, y.
type Obj is Data:
  Obj{prefab: U32, x: F64Repr.F64, y: F64Repr.F64}

# What happened, in execution order (story nodes by index, layouts by string id).
type Ev is Data:
  EPoints{node: U32, n: U32, before: Pcg.Rng, after: Pcg.Rng, shuffled: List<&2, U32>, kept: List<&2, Points.Pt>}
  EReserve{node: U32, size: U32, start: U32, fill: U32, position: U32, n: U32, before: Pcg.Rng, after: Pcg.Rng, ok: Bool, x: U32, y: U32}
  EConvertNode{node: U32, before: Pcg.Rng, after: Pcg.Rng}
  ELayout{node: U32, name: U32, before: Pcg.Rng}
  EItems{name: U32, items: List<&2, Obj>, before: Pcg.Rng, after: Pcg.Rng}
  EPlaced{after: Pcg.Rng}
  EEntity{ent: Entities.Ent}
  EPopulateNode{node: U32, before: Pcg.Rng, after: Pcg.Rng}
  ELand{populate: Bool, before: Pcg.Rng, after: Pcg.Rng}
  EDigest{at: U32, rng: Pcg.Rng, tiles: Grid.Hash, flags: Grid.Hash}
  EPiece{piece: PopulateSetpiece.Piece}

# The grid, the RNG, the entities (newest first) and the events (newest first).
type Land is Type:
  Land{grid: Grid.Grid, rng: Pcg.Rng, ents: List<&2, Entities.Ent>, events: List<&2, Ev>}

def site_of(+c: Ctx, +node: U32) -> U32:
  match c:
    case Ctx{_, _, _, _, +site_of, _, _, _, _, _}:
      TileTable.at(~U32, site_of, node)

def story_of(+c: Ctx) -> StoryGraph.St:
  match c:
    case Ctx{_, _, _, +story, _, _, _, _, _, _}:
      story

def sites_of(+c: Ctx) -> Points.Sites:
  match c:
    case Ctx{_, _, +sites, _, _, _, _, _, _, _}:
      sites

def windows_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{+windows, _, _, _, _, _, _, _, _, _}:
      windows

def swaps_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, +swaps, _, _, _, _, _, _, _, _}:
      swaps

def width_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, _, _, _, _, +width, _, _, _, _}:
      width

def height_of(+c: Ctx) -> U32:
  match c:
    case Ctx{_, _, _, _, _, _, +height, _, _, _}:
      height

def rng_of(l: Land) -> Land & Pcg.Rng:
  match l:
    case Land{g, +rng, +ents, +events}:
      (Land{g, rng, ents, events}, rng)

def noted(l: Land, +ev: Ev) -> Land:
  match l:
    case Land{g, +rng, +ents, +events}:
      Land{g, rng, ents, ev <> events}

def added(l: Land, +e: Entities.Ent) -> Land:
  match l:
    case Land{g, _, +ents, +events}:
      Land{g, Entities.rng_of(e), e <> ents, EEntity{e} <> events}

def pieces_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{_, _, _, _, _, _, _, _, _, +pieces}:
      pieces

def tracing_of(+c: Ctx) -> Bool:
  match c:
    case Ctx{_, _, _, _, _, _, _, +tracing, _, _}:
      tracing

def entity_events(tracing: Bool, +e: Entities.Ent, +events: List<&2, Ev>) -> List<&2, Ev>:
  match tracing:
    case True{}:
      EEntity{e} <> events
    case False{}:
      events

# `added`, with the EEntity event only when tracing (production skips the event list's copy of every entity).
def added_in(+c: Ctx, l: Land, +e: Entities.Ent) -> Land:
  match l:
    case Land{g, _, +ents, +events}:
      Land{g, Entities.rng_of(e), e <> ents, entity_events(tracing_of(c), e, events)}

# The land and its entity count.
def counted(l: Land) -> Land & U32:
  match l:
    case Land{g, +rng, +ents, +events}:
      (Land{g, rng, ents, events}, U32.from_nat(List.length(&2, Entities.Ent, ents)))

def with_rng(l: Land, +rng: Pcg.Rng) -> Land:
  match l:
    case Land{g, _, +ents, +events}:
      Land{g, rng, ents, events}

def digest_of(got: Grid.Grid & Grid.Hash, +tiles: Grid.Hash, +at: U32, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, Ev>) -> Land:
  (g, +flags) = got
  Land{g, rng, ents, EDigest{at, rng, tiles, flags} <> events}

def digest_tiles(got: Grid.Grid & Grid.Hash, +c: Ctx, +at: U32, +rng: Pcg.Rng, +ents: List<&2, Entities.Ent>, +events: List<&2, Ev>) -> Land:
  (g, +tiles) = got
  match c:
    case Ctx{_, _, _, _, _, _, _, _, +tiles_rng, _}:
      digest_of(Grid.flags_digest(g, tiles_rng), tiles, at, rng, ents, events)

def digest_if(on: Bool, l: Land, +c: Ctx, +at: U32) -> Land:
  match on:
    case False{}:
      l
    case True{}:
      match l:
        case Land{g, +rng, +ents, +events}:
          digest_tiles(Grid.tiles_digest(g), c, at, rng, ents, events)

# The tile and flag digests of the grid now (0 ConvertGround, 1 ReplaceSingleNonLandTiles, 2 PopulateVoronoi), only
# when tracing.
def digest(l: Land, +c: Ctx, +at: U32) -> Land:
  match c:
    case Ctx{_, _, _, _, _, _, _, +tracing, _, _}:
      digest_if(tracing, l, c, at)

# The same context without the grid digests (production).
def untraced(+c: Ctx) -> Ctx:
  match c:
    case Ctx{+windows, +swaps, +sites, +story, +site_of, +width, +height, _, +tiles_rng, +pieces}:
      Ctx{windows, swaps, sites, story, site_of, width, height, False{}, tiles_rng, pieces}

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
