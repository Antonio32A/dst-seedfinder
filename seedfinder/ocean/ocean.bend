import Base
import ../rng/pcg.bend as R
import ../worldsim/grid.bend as GR
import ../worldsim/points.bend as PT
import ../worldsim/tiles/groups.bend as TG
import ../data/ocean.bend as OC
import ./ents.bend as OE
import ./state.bend as OS
import ./place.bend as OP
import ./populate.bend as OPP
import ./monkey.bend as OM
import ./post.bend as OT
import ./bunches.bend as OB
import ./convert.bend as OV
import ./convert_blend.bend as CB

# forest_map.Generate from land_done to the required prefab check (has_ocean): Ocean_PlaceSetPieces (prefill),
# Ocean_ConvertImpassibleToWater, PopulateOcean, MonkeyIsland_GenerateDocks, Graph:GlobalPostPopulate, the
# impassable filter, BunchSpawnerRun, and the check that decides whether the attempt is the world (its map then
# goes through GetEncodedMap's ReplaceSingleNonLandTiles).

# The prefill: level.ocean_prefill_setpieces on IMPASSABLE with ocean_prefill_setpieces_min_land_dist.
def prefill(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  OS.digest(c, OP.place_set_pieces(OPP.prefill_specs(), c, TG.impassable(), OC.config_ocean_prefill_setpieces_min_land_dist(), s), 0)

def encoded(ok: Bool, +c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match ok:
    case False{}:
      s
    case True{}:
      match s:
        case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
          OS.digest(c, OS.Sea{PT.replace_single_non_land(g), ids, rng, ents, topo, events}, 10)

def checked(got: OS.Sea & Bool, +c: OS.Ctx) -> OS.Sea & Bool:
  (s, +ok) = got
  (encoded(ok, c, s), ok)

def with_counts(got: OS.Sea & List<&2, OE.Ent>, +c: OS.Ctx) -> OS.Sea:
  (s, +ents) = got
  OS.noted(c, s, OS.ECounts{0, ents})

def populated(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  with_counts(OS.ents_of(OS.digest(c, OPP.populate(c, s), 6)), c)

# Everything after the conversion, with the required prefab table: the final state and whether it passed.
def after_convert(+c: OS.Ctx, +reqs: List<&2, OT.Req>, s: OS.Sea) -> OS.Sea & Bool:
  docked = OS.digest(c, OM.docks(c, populated(c, s)), 7)
  checked(OT.required(reqs, c, OB.bunches(c, OT.impassable_filter(c, OT.post_populate(c, docked)))), c)

def fills_step(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      OS.digest(c, OS.Sea{OV.fills(g), ids, rng, ents, topo, events}, 1)

def noised(got: GR.Grid & R.Rng, ids: GR.Grid, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>) -> OS.Sea:
  (g, +rng) = got
  OS.Sea{g, ids, rng, ents, topo, events}

def noise_step(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      OS.digest(c, noised(OV.noise(g, rng), ids, ents, topo, events), 2)

def hashed(got: Array<U32> & GR.Hash, +k: U32, +events: List<&2, OS.Ev>) -> Array<U32> & List<&2, OS.Ev>:
  (o, +h) = got
  (o, OS.EBlend{k, h} <> events)

def el_hashed(got: Array<U32> & List<&2, OS.Ev>, +n: U32) -> Array<U32> & List<&2, OS.Ev>:
  (o, +events) = got
  hashed(CB.map_hash(o, CB.el_base(n), n), 2, events)

def g_hashed(got: Array<U32> & List<&2, OS.Ev>, +n: U32) -> Array<U32> & List<&2, OS.Ev>:
  (o, +events) = got
  el_hashed(hashed(CB.map_hash(o, CB.g_base(n), n), 1, events), n)

def blend_applied(got: Array<U32> & List<&2, OS.Ev>, g: GR.Grid, ids: GR.Grid, +rng: R.Rng, +ents: List<&2, OE.Ent>, +topo: U32) -> OS.Sea:
  (o, +events) = got
  OS.Sea{CB.apply(g, o), ids, rng, ents, topo, events}

def blend_maps(got: GR.Grid & Array<U32>, ids: GR.Grid, +rng: R.Rng, +ents: List<&2, OE.Ent>, +topo: U32, +events: List<&2, OS.Ev>, +n: U32) -> OS.Sea:
  (g, o) = got
  blend_applied(g_hashed(hashed(CB.map_hash(o, CB.cm_base(n), n), 0, events), n), g, ids, rng, ents, topo)

def blend_if(tracing: Bool, +c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match tracing:
    case False{}:
      match s:
        case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
          OS.Sea{OV.blend(g), ids, rng, ents, topo, events}
    case True{}:
      match s:
        case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
          blend_maps(CB.maps(g), ids, rng, ents, topo, events, (OS.width_of(c) * OS.height_of(c) : U32))

# do_blend, with the three blended maps' hashes when tracing.
def blend_step(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  OS.digest(c, blend_if(OS.tracing_of(c), c, s), 3)

def shore_step(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      OS.digest(c, OS.Sea{OV.shoreline(g), ids, rng, ents, topo, events}, 4)

def void_step(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  match s:
    case OS.Sea{g, ids, +rng, +ents, +topo, +events}:
      OS.digest(c, noised(OV.void_outline(g, rng), ids, ents, topo, events), 5)

# Ocean_ConvertImpassibleToWater (ocean/convert.bend), step by step for the digests.
def convert(+c: OS.Ctx, s: OS.Sea) -> OS.Sea:
  void_step(c, shore_step(c, blend_step(c, noise_step(c, fills_step(c, s)))))

# The ocean phase of one attempt from land_done: the final state and whether the required prefabs are all there.
def run(+c: OS.Ctx, +reqs: List<&2, OT.Req>, s: OS.Sea) -> OS.Sea & Bool:
  after_convert(c, reqs, convert(c, prefill(c, s)))
