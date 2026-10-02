import Base
import ../rng/pcg.bend as Pcg
import ../f32/ops.bend as F32Ops
import ../data/blob.bend as Blob
import ../data/cave_story.bend as CaveStory
import ../populate/names.bend as PopulateNames
import ../populate/entities.bend as Entities
import ../storygen/graph.bend as StoryGraph
import ../storygen/order.bend as StoryOrder
import ../storygen/catalog.bend as StoryCatalog
import ../worldsim/grid.bend as Grid
import ../worldsim/points.bend as Points
import ../worldsim/tiles/groups.bend as TileGroups
import ../worldsim/tiles/world.bend as TileWorld
import ../worldsim/cave/automaton.bend as CaveAutomaton
import ./graph.bend as GenGraph

# The caves' custom tile pass, forest_map.Generate's `for k, node in pairs(topology_save.root:GetNodes(true)) do
# node:SetTilesViaFunction(...)`: every node whose room has custom_tiles (RUNCA, map/room_functions.lua) runs the cellular
# automaton on its site, then rewrites the site's points through the room's translate layers and puts the layers' items
# down with Node:AddEntity.

# An item the pass asked AddEntity for: its data/cave_story.bend ca_items index, its tile, the float32 bits of the position
# AddEntity was given (the tile, or the site centroid) and the two math.random() outputs of its position offset (the entity
# is not built yet; the ReserveTile and the draws are).
type Placed is Data:
  Placed{item: U32, x: U32, y: U32, fx: U32, fy: U32, rx: U32, ry: U32}

# The pass in progress: the tile map, the PCG32 stream, each layer's item_count still left and the items placed
# (newest first).
type Ca is Type:
  Ca{grid: Grid.Grid, rng: Pcg.Rng, left: List<&2, U32>, placed: List<&2, Placed>}

def entity_finished(g: Grid.Grid, second: U32 & Pcg.Rng, +rx: U32, +item: U32, +x: U32, +y: U32, +fx: U32, +fy: U32, left: List<&2, U32>, placed: List<&2, Placed>) -> Ca:
  (+ry, rng) = second
  Ca{g, rng, left, Placed{item, x, y, fx, fy, rx, ry} <> placed}

def entity_offset(g: Grid.Grid, first: U32 & Pcg.Rng, +item: U32, +x: U32, +y: U32, +fx: U32, +fy: U32, left: List<&2, U32>, placed: List<&2, Placed>) -> Ca:
  (+rx, rng) = first
  entity_finished(g, Pcg.draw(rng), rx, item, x, y, fx, fy, left, placed)

def entity_reserved(reserved: Grid.Grid & Bool, rng: Pcg.Rng, +item: U32, +x: U32, +y: U32, +fx: U32, +fy: U32, left: List<&2, U32>, placed: List<&2, Placed>) -> Ca:
  (g, _) = reserved
  entity_offset(g, Pcg.draw(rng), item, x, y, fx, fy, left, placed)

def entity_on(land: Bool, g: Grid.Grid, rng: Pcg.Rng, +item: U32, +x: U32, +y: U32, +fx: U32, +fy: U32, left: List<&2, U32>, placed: List<&2, Placed>) -> Ca:
  match land:
    case True{}:
      entity_reserved(Points.reserve_tile(g, x, y), rng, item, x, y, fx, fy, left, placed)
    case False{}:
      Ca{g, rng, left, placed}

def entity_tile(got: Grid.Grid & U32, rng: Pcg.Rng, +item: U32, +x: U32, +y: U32, +fx: U32, +fy: U32, left: List<&2, U32>, placed: List<&2, Placed>) -> Ca:
  (g, +tile) = got
  entity_on(TileGroups.is_land(tile), g, rng, item, x, y, fx, fy, left, placed)

# Node:AddEntity(item, {fx}, {fy}, 1, ..., rand_offset = true) for the tile (x, y) = the floats truncated: nothing on a tile
# that is not land, else ReserveTile and the two math.random() draws of the offset.
def add_entity_at(st: Ca, +item: U32, +x: U32, +y: U32, +fx: U32, +fy: U32) -> Ca:
  match st:
    case Ca{g, rng, left, placed}:
      entity_tile(Points.get_tile(g, x, y), rng, item, x, y, fx, fy, left, placed)

def add_entity(st: Ca, +item: U32, +x: U32, +y: U32) -> Ca:
  add_entity_at(st, item, x, y, F32.bits(F32Ops.from_u32(x)), F32.bits(F32Ops.from_u32(y)))

def decremented(counts: List<&2, U32>, +k: U32) -> List<&2, U32>:
  match counts:
    case Nil{}:
      Nil{}
    case Con{+count, +rest}:
      Bool.pick(List<&2, U32>, U32.is_zero(k), (count - 1 : U32) <> rest, count <> decremented(rest, (k - 1 : U32)))

def with_tile(st: Ca, +x: U32, +y: U32, +tile: U32) -> Ca:
  match st:
    case Ca{g, rng, left, placed}:
      Ca{Points.set_tile(g, x, y, tile, 0), rng, left, placed}

def with_left_decremented(st: Ca, +layer: U32) -> Ca:
  match st:
    case Ca{g, rng, left, placed}:
      Ca{g, rng, decremented(left, layer), placed}

def item_placed(more: Bool, st: Ca, +item: U32, +x: U32, +y: U32, +layer: U32) -> Ca:
  match more:
    case True{}:
      with_left_decremented(add_entity(st, item, x, y), layer)
    case False{}:
      st

def left_read(st: Ca, +layer: U32) -> Ca & U32:
  match st:
    case Ca{g, rng, +left, placed}:
      (Ca{g, rng, left, placed}, StoryOrder.nth_or_last(left, layer, 0))

def layer_translated(got: Ca & U32, +item: U32, +x: U32, +y: U32, +layer: U32) -> Ca:
  (st, +remaining) = got
  item_placed(Bool.not(U32.is_zero(remaining)), st, item, x, y, layer)

# One point of the site in the translate loop: SetTile to the layer's tile, then the layer's item while it has some left.
def layer_step(st: Ca, +layers: List<&2, U32>, +layer: U32, +x: U32, +y: U32) -> Ca:
  layer_translated(left_read(with_tile(st, x, y, Blob.at(layers, (layer * 3 : U32))), layer), Blob.at(layers, (layer * 3 + 2 : U32)), x, y, layer)

# `type - 1 < #data.translate` with the type the engine reports: the CA values 2..count.
def point_step(inside: Bool, st: Ca, +layers: List<&2, U32>, +t: U32, +x: U32, +y: U32) -> Ca:
  match inside:
    case True{}:
      layer_step(st, layers, (t - 2 : U32), x, y)
    case False{}:
      st

def points_loop(points: List<&2, Points.Pt>, st: Ca, +layers: List<&2, U32>, +count: U32) -> Ca:
  match points:
    case Nil{}:
      st
    case Con{Points.Pt{+x, +y, +t}, rest}:
      points_loop(rest, point_step((t >= 2 : U32) && (t <= count : U32), st, layers, t, x, y), layers, count)

def centroid_step(has: Bool, st: Ca, +tile: U32, +item: U32, +x: U32, +y: U32, +fx: U32, +fy: U32) -> Ca:
  match has:
    case True{}:
      add_entity_at(with_tile(st, x, y, tile), item, x, y, fx, fy)
    case False{}:
      st

def centroid_at(st: Ca, +room: U32, +site: TileWorld.Site) -> Ca:
  match site:
    case TileWorld.Site{_, _, _, +cx, +cy, _}:
      centroid_step(Bool.not(Blob.is_none(CaveStory.room_ca_centroid_tile(room))), st, CaveStory.room_ca_centroid_tile(room),
        CaveStory.room_ca_centroid_item(room), F32Ops.to_i32(cx), F32Ops.to_i32(cy), F32.bits(cx), F32.bits(cy))

def site_translated(empty: Bool, st: Ca, kept: List<&2, Points.Pt>, +layers: List<&2, U32>, +count: U32, +room: U32, +site: TileWorld.Site) -> Ca:
  match empty:
    case True{}:
      st
    case False{}:
      centroid_at(points_loop(kept, st, layers, count), room, site)

def initial_left(n: Nat, +layers: List<&2, U32>, +k: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Blob.at(layers, (k * 3 + 1 : U32)) <> initial_left(p, layers, (k + 1 : U32))

def picked_translated(picked: Points.Picked, placed: List<&2, Placed>, +room: U32, +site: TileWorld.Site) -> Ca:
  match picked:
    case Points.Picked{g, rng, _, _, +kept}:
      site_translated(List.is_empty(&2, Points.Pt, kept), Ca{g, rng, initial_left(U32.to_nat(CaveStory.room_ca_layer_count(room)), CaveStory.room_ca_layers(room), 0), placed},
        kept, CaveStory.room_ca_layers(room), CaveStory.room_ca_layer_count(room), room, site)

def automaton_ran(ran: CaveAutomaton.Painted, +windows: Bool, +sites: Points.Sites, +vertex: U32, placed: List<&2, Placed>, +room: U32, +site: TileWorld.Site) -> Ca:
  match ran:
    case CaveAutomaton.Painted{g, rng}:
      picked_translated(Points.points_for_site(windows, sites, vertex, g, rng), placed, room, site)

# RUNCA.GeneratorFunction on one node: WorldSim:RunCA, GetPointsForSite (one more shuffle of the site's points) and the
# translate loop over what it returns, then the centroid layer.
def node_pass(st: Ca, +windows: Bool, +sites: Points.Sites, +world: TileWorld.World, +vertex: U32, +room: U32) -> Ca:
  match st:
    case Ca{g, rng, _, placed}:
      automaton_ran(CaveAutomaton.run(windows, TileWorld.site(world, vertex), CaveStory.room_ca_iterations(room), CaveStory.room_ca_seed_mode(room),
        CaveStory.room_ca_random_points(room), g, rng), windows, sites, vertex, placed, room, TileWorld.site(world, vertex))

def custom_room(+s: StoryGraph.St, +n: U32) -> Bool:
  +room = StoryGraph.nf(s, n, StoryGraph.f_room())
  +kind = StoryGraph.nf(s, n, StoryGraph.f_kind())
  (U32.is_eq(kind, StoryGraph.id_room()) || U32.is_eq(kind, StoryGraph.id_start())) && StoryCatalog.is_cave_room(room)
    && U32.is_ne((CaveStory.room_flags(StoryCatalog.cave_room(room)) .&. 1 : U32), 0)

def custom_nodes(nodes: List<&2, U32>, +s: StoryGraph.St) -> List<&2, U32>:
  match nodes:
    case Nil{}:
      Nil{}
    case Con{+n, rest}:
      +tail = custom_nodes(rest, s)
      Bool.pick(List<&2, U32>, custom_room(s, n), n <> tail, tail)

def child_slots(graphs: List<&2, U32>, +s: StoryGraph.St) -> List<&2, StoryOrder.Slot>:
  match graphs:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      List.append(&2, StoryOrder.Slot, StoryGraph.node_slots(s, StoryGraph.copy_order(s, g)), child_slots(rest, s))

# pairs(topology_save.root:GetNodes(true)): every child graph's nodes, copied in turn into one table.
def nodes_order(+s: StoryGraph.St) -> List<&2, U32>:
  StoryOrder.order(child_slots(StoryGraph.children_order(s), s))

def nodes_loop(nodes: List<&2, U32>, st: Ca, +windows: Bool, +sites: Points.Sites, +world: TileWorld.World, +s: StoryGraph.St, +k: GenGraph.Klei) -> Ca:
  match nodes:
    case Nil{}:
      st
    case Con{+n, rest}:
      nodes_loop(rest, node_pass(st, windows, sites, world, GenGraph.vertex_of(k, n), StoryCatalog.cave_room(StoryGraph.nf(s, n, StoryGraph.f_room()))), windows, sites, world, s, k)

def world_of(sites: Points.Sites) -> TileWorld.World:
  match sites:
    case Points.Sites{_, _, +world}:
      world

def any_crashes(nodes: List<&2, U32>, +world: TileWorld.World, +k: GenGraph.Klei) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case Con{+n, rest}:
      CaveAutomaton.crashes(TileWorld.site(world, GenGraph.vertex_of(k, n))) || any_crashes(rest, world, k)

# Whether the pass crashes the game: RunCA on a custom-tile node whose site has no polygon (CaveAutomaton.crashes).
def crashes(+s: StoryGraph.St, +k: GenGraph.Klei, +sites: Points.Sites) -> Bool:
  any_crashes(custom_nodes(nodes_order(s), s), world_of(sites), k)

# The tile map, the PCG32 stream and the items placed (in placement order) once every custom-tile node has run.
type Tiles is Type:
  Tiles{grid: Grid.Grid, rng: Pcg.Rng, placed: List<&2, Placed>}

def finished(st: Ca) -> Tiles:
  match st:
    case Ca{g, rng, _, placed}:
      Tiles{g, rng, List.reverse(&2, Placed, placed)}

# The custom tile pass over the tile map after ForceConnectivity, from the PCG32 stream after ConvertToTileMap.
def run(+s: StoryGraph.St, +k: GenGraph.Klei, +windows: Bool, +sites: Points.Sites, g: Grid.Grid, rng: Pcg.Rng) -> Tiles:
  finished(nodes_loop(custom_nodes(nodes_order(s), s), Ca{g, rng, Nil{}, Nil{}}, windows, sites, world_of(sites), s, k))

def item_prefabs(n: Nat, +item: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      PopulateNames.string_id(CaveStory.ca_item_name(item)) <> item_prefabs(p, (item + 1 : U32))

def entities_loop(placed: List<&2, Placed>, +prefabs: List<&2, U32>, +width: U32, +height: U32, +rng: Pcg.Rng, +acc: List<&2, Entities.Ent>) -> List<&2, Entities.Ent>:
  match placed:
    case Nil{}:
      acc
    case Con{Placed{+item, _, _, +fx, +fy, +rx, +ry}, rest}:
      entities_loop(rest, prefabs, width, height, rng, Entities.drawn_entity(StoryOrder.nth_or_last(prefabs, item, 0), F32Ops.to_f64(F32Ops.from_bits(fx)), F32Ops.to_f64(F32Ops.from_bits(fy)), width, height, rx, ry, rng) <> acc)

# The savedata entities of the items the custom tile pass placed (Node:AddEntity with rand_offset = true, offsets from
# the pass's own draws), newest first: the start of the land's entity list, before any Labyrinth, Maze or ConvertGround
# entity. `rng` is the stream after the pass.
def entities(placed: List<&2, Placed>, +width: U32, +height: U32, +rng: Pcg.Rng) -> List<&2, Entities.Ent>:
  entities_loop(placed, item_prefabs(U32.to_nat(CaveStory.ca_items_count()), 0), width, height, rng, Nil{})
