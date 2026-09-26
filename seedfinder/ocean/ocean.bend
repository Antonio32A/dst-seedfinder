import Base
import ../rng/pcg.bend as Pcg
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/groups.bend as TileGroups
import ../data/ocean.bend as OceanData
import ./ents.bend as OceanEnts
import ./state.bend as OceanState
import ./place.bend as OceanPlace
import ./populate.bend as OceanPopulate
import ./monkey.bend as Monkey
import ./post.bend as OceanPost
import ./bunches.bend as Bunches
import ./convert.bend as OceanConvert
import ./convert_blend.bend as ConvertBlend

# forest_map.Generate from land_done to the required prefab check (has_ocean): Ocean_PlaceSetPieces (prefill),
# Ocean_ConvertImpassibleToWater, PopulateOcean, MonkeyIsland_GenerateDocks, Graph:GlobalPostPopulate, the
# impassable filter, BunchSpawnerRun, and the check that decides whether the attempt is the world (its map then
# goes through GetEncodedMap's ReplaceSingleNonLandTiles).

# The prefill: level.ocean_prefill_setpieces on IMPASSABLE with ocean_prefill_setpieces_min_land_dist.
def prefill(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  OceanState.digest(c, OceanPlace.place_set_pieces(OceanPopulate.prefill_specs(), c, TileGroups.impassable(), OceanData.config_ocean_prefill_setpieces_min_land_dist(), s), 0)

def encoded(ok: Bool, +c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match ok:
    case False{}:
      s
    case True{}:
      match s:
        case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
          OceanState.digest(c, OceanState.Sea{Points.replace_single_non_land(g), ids, rng, ents, topo, events}, 10)

def checked(got: OceanState.Sea & Bool, +c: OceanState.Ctx) -> OceanState.Sea & Bool:
  (s, +ok) = got
  (encoded(ok, c, s), ok)

def with_counts(got: OceanState.Sea & List<&2, OceanEnts.Ent>, +c: OceanState.Ctx) -> OceanState.Sea:
  (s, +ents) = got
  OceanState.noted(c, s, OceanState.ECounts{0, ents})

def populated(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  with_counts(OceanState.ents_of(OceanState.digest(c, OceanPopulate.populate(c, s), 6)), c)

# Everything after the conversion, with the required prefab table: the final state and whether it passed.
def after_convert(+c: OceanState.Ctx, +reqs: List<&2, OceanPost.Req>, s: OceanState.Sea) -> OceanState.Sea & Bool:
  docked = OceanState.digest(c, Monkey.docks(c, populated(c, s)), 7)
  checked(OceanPost.required(reqs, c, Bunches.bunches(c, OceanPost.impassable_filter(c, OceanPost.post_populate(c, docked)))), c)

def fills_step(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      OceanState.digest(c, OceanState.Sea{OceanConvert.fills(g), ids, rng, ents, topo, events}, 1)

def noised(got: Grid.Grid & Pcg.Rng, ids: Grid.Grid, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>) -> OceanState.Sea:
  (g, +rng) = got
  OceanState.Sea{g, ids, rng, ents, topo, events}

def noise_step(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      OceanState.digest(c, noised(OceanConvert.noise(g, rng), ids, ents, topo, events), 2)

def hashed(got: Array<U32> & Grid.Hash, +k: U32, +events: List<&2, OceanState.Ev>) -> Array<U32> & List<&2, OceanState.Ev>:
  (o, +h) = got
  (o, OceanState.EBlend{k, h} <> events)

def el_hashed(got: Array<U32> & List<&2, OceanState.Ev>, +n: U32) -> Array<U32> & List<&2, OceanState.Ev>:
  (o, +events) = got
  hashed(ConvertBlend.map_hash(o, ConvertBlend.el_base(n), n), 2, events)

def g_hashed(got: Array<U32> & List<&2, OceanState.Ev>, +n: U32) -> Array<U32> & List<&2, OceanState.Ev>:
  (o, +events) = got
  el_hashed(hashed(ConvertBlend.map_hash(o, ConvertBlend.g_base(n), n), 1, events), n)

def blend_applied(got: Array<U32> & List<&2, OceanState.Ev>, g: Grid.Grid, ids: Grid.Grid, +rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +topo: U32) -> OceanState.Sea:
  (o, +events) = got
  OceanState.Sea{ConvertBlend.apply(g, o), ids, rng, ents, topo, events}

def blend_maps(got: Grid.Grid & Array<U32>, ids: Grid.Grid, +rng: Pcg.Rng, +ents: List<&2, OceanEnts.Ent>, +topo: U32, +events: List<&2, OceanState.Ev>, +n: U32) -> OceanState.Sea:
  (g, o) = got
  blend_applied(g_hashed(hashed(ConvertBlend.map_hash(o, ConvertBlend.cm_base(n), n), 0, events), n), g, ids, rng, ents, topo)

def blend_if(tracing: Bool, +c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match tracing:
    case False{}:
      match s:
        case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
          OceanState.Sea{OceanConvert.blend(g), ids, rng, ents, topo, events}
    case True{}:
      match s:
        case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
          blend_maps(ConvertBlend.maps(g), ids, rng, ents, topo, events, (OceanState.width_of(c) * OceanState.height_of(c) : U32))

# do_blend, with the three blended maps' hashes when tracing.
def blend_step(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  OceanState.digest(c, blend_if(OceanState.tracing_of(c), c, s), 3)

def shore_step(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      OceanState.digest(c, OceanState.Sea{OceanConvert.shoreline(g), ids, rng, ents, topo, events}, 4)

def void_step(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  match s:
    case OceanState.Sea{g, ids, +rng, +ents, +topo, +events}:
      OceanState.digest(c, noised(OceanConvert.void_outline(g, rng), ids, ents, topo, events), 5)

# Ocean_ConvertImpassibleToWater (ocean/convert.bend), step by step for the digests.
def convert(+c: OceanState.Ctx, s: OceanState.Sea) -> OceanState.Sea:
  void_step(c, shore_step(c, blend_step(c, noise_step(c, fills_step(c, s)))))

# The ocean phase of one attempt from land_done: the final state and whether the required prefabs are all there.
def run(+c: OceanState.Ctx, +reqs: List<&2, OceanPost.Req>, s: OceanState.Sea) -> OceanState.Sea & Bool:
  after_convert(c, reqs, convert(c, prefill(c, s)))
