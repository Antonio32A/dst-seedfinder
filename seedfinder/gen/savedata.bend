import Base
import ../f64/repr.bend as F64Repr
import ./centi.bend as Centi
import ../worldsim/grid.bend as Grid
import ../f64/arith.bend as F64Arith
import ../f32/ops.bend as F32Ops
import ../worldsim/tiles/world.bend as TileWorld
import ../ocean/ents.bend as OceanEnts
import ../populate/entities.bend as Entities
import ../populate/setpiece.bend as PopulateSetpiece
import ../filters/world.bend as FilterWorld
import ../filters/dump.bend as FilterDump
import ../data/gen_tags.bend as GenTagsData
import ../data/search_vocab.bend as SearchVocab
import ../data/strings.bend as Strings
import ../data/constants.bend as Constants
import ./job.bend as GenJob

# The filters' world (filters/world.bend) of a generated world, equal to what FilterWorld.of_bytes reads from the dump of the
# same world's savedata: the dump mod writes every position with printf("%.2f") (trailing zeros cut), and
# AddWorldEntities adds the pocket dimension containers at (0, 0) when the world has none.

def insts_of(ents: List<&2, OceanEnts.Ent>, +v: U32, +index: U32, +windows: Bool) -> List<&2, FilterWorld.Inst>:
  match ents:
    case Nil{}:
      Nil{}
    case Con{OceanEnts.Ent{_, +x, +z, _, _, _}, rest}:
      FilterWorld.inst_of(v, index, Centi.centi(x, windows), Centi.centi(z, windows)) <> insts_of(rest, v, (index + 1 : U32), windows)

def is_pocket(+v: U32) -> Bool:
  U32.is_eq(v, GenTagsData.vocab_shadow_container()) || U32.is_eq(v, GenTagsData.vocab_rabbitkinghorn_container())

def pocket_default(pocket: Bool, +v: U32) -> List<&2, FilterWorld.Inst>:
  match pocket:
    case True{}:
      [FilterWorld.Inst{v, 0, F64Repr.zero(), F64Repr.zero(), 0, 0, 3}]
    case False{}:
      Nil{}

def group_of(ents: List<&2, OceanEnts.Ent>, +v: U32, +windows: Bool) -> List<&2, FilterWorld.Inst>:
  match ents:
    case Nil{}:
      pocket_default(is_pocket(v), v)
    case Con{+e, +rest}:
      insts_of(e <> rest, v, 0, windows)

def slot_set(fits: Bool, a: Array<U32>, +sid: U32, +v: U32) -> Array<U32>:
  match fits:
    case True{}:
      a[sid] <- v
      a
    case False{}:
      a

def sid_slots() -> U32:
  U32.pow(2, GenTagsData.sid_depth())

def lookup_fill(sids: List<&2, U32>, +v: U32, a: Array<U32>) -> Array<U32>:
  match sids:
    case Nil{}:
      a
    case Con{+sid, rest}:
      lookup_fill(rest, (v + 1 : U32), slot_set((sid < sid_slots() : U32), a, sid, v))

def no_vocab() -> U32:
  65535

# The catalog index of every string id (no_vocab() for the rest).
def lookup() -> Array<U32>:
  lookup_fill(GenTagsData.vocab_prefab_sids(), 0, Array.new(U32, GenTagsData.sid_depth(), no_vocab()))

def bucket_depth() -> Nat:
  9n

def bucket_put(known: Bool, got: Array<List<&2, OceanEnts.Ent>> & List<&2, OceanEnts.Ent>, +v: U32, +e: OceanEnts.Ent) -> Array<List<&2, OceanEnts.Ent>>:
  match known:
    case True{}:
      (a, old) = got
      Array.set(List<&2, OceanEnts.Ent>, a, v, e <> old)
    case False{}:
      (a, old) = got
      Array.set(List<&2, OceanEnts.Ent>, a, v, old)

def bucket_add(got: Array<U32> & U32, a: Array<List<&2, OceanEnts.Ent>>, +e: OceanEnts.Ent) -> Array<U32> & Array<List<&2, OceanEnts.Ent>>:
  (ids, +v) = got
  (ids, bucket_put(U32.is_ne(v, no_vocab()), Array.swap(List<&2, OceanEnts.Ent>, a, v, Nil{}), v, e))

def bucket_step(got: Array<U32> & Array<List<&2, OceanEnts.Ent>>, +e: OceanEnts.Ent) -> Array<U32> & Array<List<&2, OceanEnts.Ent>>:
  (ids, a) = got
  bucket_add(ids[OceanEnts.prefab_of(e)], a, e)

# savedata.ents per catalog prefab, oldest first, from the newest-first entity list.
def buckets(ents: List<&2, OceanEnts.Ent>, got: Array<U32> & Array<List<&2, OceanEnts.Ent>>) -> Array<U32> & Array<List<&2, OceanEnts.Ent>>:
  match ents:
    case Nil{}:
      got
    case Con{+e, rest}:
      buckets(rest, bucket_step(got, e))

type Grouped is Type:
  Grouped{groups: List<&2, List<&2, FilterWorld.Inst>>, wormholes: List<&2, OceanEnts.Ent>}

def groups_loop(n: Nat, got: Array<List<&2, OceanEnts.Ent>> & List<&2, OceanEnts.Ent>, +v: U32, +windows: Bool, +acc: List<&2, List<&2, FilterWorld.Inst>>, +wormholes: List<&2, OceanEnts.Ent>) -> Grouped:
  match n:
    case 0n:
      Grouped{List.reverse(&2, List<&2, FilterWorld.Inst>, acc), wormholes}
    case 1n+p:
      (a, +ents) = got
      groups_loop(p, Array.swap(List<&2, OceanEnts.Ent>, a, (v + 1 : U32), Nil{}), (v + 1 : U32), windows, group_of(ents, v, windows) <> acc,
        Bool.pick(List<&2, OceanEnts.Ent>, U32.is_eq(v, GenTagsData.vocab_wormhole()), ents, wormholes))

def ent_id(+e: OceanEnts.Ent) -> U32:
  match e:
    case OceanEnts.Ent{_, _, _, +id, _, _}:
      id

def ent_target(+e: OceanEnts.Ent) -> U32:
  match e:
    case OceanEnts.Ent{_, _, _, _, +target, _}:
      target

def last_with_id(ents: List<&2, OceanEnts.Ent>, +id: U32, +i: U32, +found: U32) -> U32:
  match ents:
    case Nil{}:
      found
    case Con{+e, rest}:
      last_with_id(rest, id, (i + 1 : U32), Bool.pick(U32, U32.is_eq(ent_id(e), id) && U32.is_ne(ent_target(e), 0), i, found))

def link_if(+exit: U32, +entry: U32, +rest: List<&2, FilterDump.Link>) -> List<&2, FilterDump.Link>:
  Bool.pick(List<&2, FilterDump.Link>, U32.is_eq(exit, no_vocab()), rest, FilterDump.Link{entry, exit} <> rest)

def links_loop(ents: List<&2, OceanEnts.Ent>, +all: List<&2, OceanEnts.Ent>, +i: U32) -> List<&2, FilterDump.Link>:
  match ents:
    case Nil{}:
      Nil{}
    case Con{+e, rest}:
      +more = links_loop(rest, all, (i + 1 : U32))
      Bool.pick(List<&2, FilterDump.Link>, U32.is_zero(ent_target(e)), more, link_if(last_with_id(all, ent_target(e), 0, no_vocab()), i, more))

# The directed wormhole links in savedata order, as wormhole indices: every wormhole with a teleporter target to the
# wormhole of that id.
def links(+wormholes: List<&2, OceanEnts.Ent>) -> List<&2, FilterDump.Link>:
  links_loop(wormholes, wormholes, 0)

def pair_word(+hold: U32, +tile: U32) -> U32:
  ((hold << 16n) .|. tile : U32)

# The tiles from cell c down to cell 0, two u16 per word (the even cell in the low half), prepended to acc.
def packed_loop(n: Nat, got: Grid.Grid & U32, +c: U32, +hold: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      (g, +cell) = got
      +even = U32.is_zero((c .&. 1 : U32))
      packed_loop(p, Grid.get(g, (c - 1 : U32)), (c - 1 : U32), Bool.pick(U32, even, 0, Grid.tile_of(cell)),
        Bool.pick(List<&2, U32>, even, pair_word(hold, Grid.tile_of(cell)) <> acc, acc))

def packed(g: Grid.Grid, +n: U32) -> List<&2, U32>:
  packed_loop(U32.to_nat(n), Grid.get(g, (n - 1 : U32)), (n - 1 : U32), 0, Nil{})

def world_of_groups(gr: Grouped, +seed: U32, +w: U32, +tiles: List<&2, U32>) -> FilterWorld.World:
  match gr:
    case Grouped{+groups, +wormholes}:
      FilterWorld.World{seed, w, w, GenTagsData.vocab_tile_ids(), groups, FilterWorld.links_of(links(wormholes), groups, GenTagsData.vocab_wormhole()), tiles}

def grouped(got: Array<U32> & Array<List<&2, OceanEnts.Ent>>, +windows: Bool) -> Grouped:
  (_, a) = got
  groups_loop(List.length(&2, U32, GenTagsData.vocab_prefab_sids()), Array.swap(List<&2, OceanEnts.Ent>, a, 0, Nil{}), 0, windows, Nil{}, Nil{})

# The filters' world of a generated world (the seed's world attempt on the platform).
def world(+seed: U32, +windows: Bool, final: GenJob.Final) -> FilterWorld.World:
  match final:
    case GenJob.Final{g, _, +ents, +w, _, _, _}:
      +tiles = packed(g, (w * w : U32))
      world_of_groups(grouped(buckets(ents, (lookup(), Array.new(List<&2, OceanEnts.Ent>, bucket_depth(), Nil{}))), windows), seed, w, tiles)

def sid_bucket_add(got: Array<List<&2, OceanEnts.Ent>> & List<&2, OceanEnts.Ent>, +sid: U32, +e: OceanEnts.Ent) -> Array<List<&2, OceanEnts.Ent>>:
  (a, +old) = got
  Array.set(List<&2, OceanEnts.Ent>, a, sid, e <> old)

# savedata.ents per string id, oldest first, from the newest-first entity list.
def sid_buckets(ents: List<&2, OceanEnts.Ent>, a: Array<List<&2, OceanEnts.Ent>>) -> Array<List<&2, OceanEnts.Ent>>:
  match ents:
    case Nil{}:
      a
    case Con{+e, rest}:
      +sid = OceanEnts.prefab_of(e)
      sid_buckets(rest, sid_bucket_add(Array.swap(List<&2, OceanEnts.Ent>, a, sid, Nil{}), sid, e))

def positions_of(ents: List<&2, OceanEnts.Ent>, +windows: Bool) -> List<&2, FilterDump.Position>:
  match ents:
    case Nil{}:
      Nil{}
    case Con{OceanEnts.Ent{_, +x, +z, _, _, _}, rest}:
      FilterDump.Position{Centi.centi(x, windows), Centi.centi(z, windows)} <> positions_of(rest, windows)

# A prefab's savedata.ents entries, oldest first.
type Named is Data:
  Named{name: String, ents: List<&2, OceanEnts.Ent>}

def named_if(ents: List<&2, OceanEnts.Ent>, +sid: U32, +acc: List<&2, Named>) -> List<&2, Named>:
  match ents:
    case Nil{}:
      acc
    case Con{+e, +rest}:
      Named{Strings.name(sid), e <> rest} <> acc

def named_loop(n: Nat, got: Array<List<&2, OceanEnts.Ent>> & List<&2, OceanEnts.Ent>, +sid: U32, +acc: List<&2, Named>) -> List<&2, Named>:
  match n:
    case 0n:
      acc
    case 1n+p:
      (a, +ents) = got
      named_loop(p, Array.swap(List<&2, OceanEnts.Ent>, a, (sid + 1 : U32), Nil{}), (sid + 1 : U32), named_if(ents, sid, acc))

def has_prefab(prefabs: List<&2, Named>, +name: String) -> Bool:
  match prefabs:
    case Nil{}:
      False{}
    case Con{Named{+found, _}, rest}:
      String.eq(found, name) || has_prefab(rest, name)

def with_pocket(+prefabs: List<&2, Named>, +v: U32) -> List<&2, Named>:
  +name = Maybe.default(&2, String, List.get(&2, String, SearchVocab.prefabs(), U32.to_nat(v)), "")
  +origin = {OceanEnts.Ent{0, F64Repr.zero(), F64Repr.zero(), 0, 0, 0} : OceanEnts.Ent}
  Bool.pick(List<&2, Named>, has_prefab(prefabs, name), prefabs, Named{name, [origin]} <> prefabs)

def named_le(a: Named, b: Named) -> Bool:
  match a b:
    case Named{x, _} Named{y, _}:
      String.is_le(x, y)

def prefabs_of(named: List<&2, Named>, +windows: Bool) -> List<&2, FilterDump.Prefab>:
  match named:
    case Nil{}:
      Nil{}
    case Con{Named{+name, +ents}, rest}:
      FilterDump.Prefab{name, positions_of(ents, windows)} <> prefabs_of(rest, windows)

# A set piece member with the set piece it belongs to.
type Tagged is Data:
  Tagged{piece: U32, member: FilterDump.Member}

def tagged_ents(ents: List<&2, OceanEnts.Ent>, +prefab: U32, +index: U32, +tail: List<&2, Tagged>) -> List<&2, Tagged>:
  match ents:
    case Nil{}:
      tail
    case Con{OceanEnts.Ent{_, _, _, _, _, +piece}, rest}:
      +more = tagged_ents(rest, prefab, (index + 1 : U32), tail)
      Bool.pick(List<&2, Tagged>, U32.is_zero(piece), more, Tagged{piece, FilterDump.Member{prefab, index}} <> more)

def tagged_of(named: List<&2, Named>, +prefab: U32) -> List<&2, Tagged>:
  match named:
    case Nil{}:
      Nil{}
    case Con{Named{_, +ents}, rest}:
      tagged_ents(ents, prefab, 0, tagged_of(rest, (prefab + 1 : U32)))

# A set piece's members, in ENTS order.
type Group is Data:
  Group{piece: U32, members: List<&2, FilterDump.Member>}

def tagged_ge(a: Tagged, b: Tagged) -> Bool:
  match a b:
    case Tagged{+k, FilterDump.Member{+p, +i}} Tagged{+l, FilterDump.Member{+q, +j}}:
      (k > l : U32) || (U32.is_eq(k, l) && ((p > q : U32) || (U32.is_eq(p, q) && (i >= j : U32))))

# The grouping so far: the set piece of the group in progress, its members and the finished groups.
type Run is Data:
  Run{current: U32, members: List<&2, FilterDump.Member>, groups: List<&2, Group>}

def group_step(same: Bool, +k: U32, +m: FilterDump.Member, +r: Run) -> Run:
  match same r:
    case True{} Run{+current, +members, +groups}:
      Run{current, m <> members, groups}
    case False{} Run{+current, +members, +groups}:
      Run{k, [m], Group{current, members} <> groups}

def group_loop(tagged: List<&2, Tagged>, +r: Run) -> List<&2, Group>:
  match tagged r:
    case Nil{} Run{+current, +members, +groups}:
      Group{current, members} <> groups
    case Con{Tagged{+k, +m}, rest} Run{+current, +members, +groups}:
      group_loop(rest, group_step(U32.is_eq(k, current), k, m, Run{current, members, groups}))

# The members of each set piece, by set piece number (a set piece without members has no group).
def groups_of(+tagged: List<&2, Tagged>) -> List<&2, Group>:
  group_loop(List.sort(~Tagged, ~tagged_ge, tagged), Run{0, Nil{}, Nil{}})

def group_members(groups: List<&2, Group>, +k: U32) -> List<&2, FilterDump.Member>:
  match groups:
    case Con{Group{+piece, +members}, _}:
      Bool.pick(List<&2, FilterDump.Member>, U32.is_eq(piece, k), members, Nil{})
    case Nil{}:
      Nil{}

def groups_after(groups: List<&2, Group>, +k: U32) -> List<&2, Group>:
  match groups:
    case Con{Group{+piece, +members}, +rest}:
      Bool.pick(List<&2, Group>, U32.is_eq(piece, k), rest, Group{piece, members} <> rest)
    case Nil{}:
      Nil{}

def world_centi(+t: F64Repr.F64, +w: U32, +windows: Bool) -> U32:
  Centi.centi(Entities.centred(t, w), windows)

def piece_of(+p: PopulateSetpiece.Piece, +members: List<&2, FilterDump.Member>, +w: U32, +windows: Bool) -> FilterDump.Piece:
  match p:
    case PopulateSetpiece.Piece{+name, +source, +turn, +cx, +cy, +half, _, _}:
      +x0 = world_centi(F64Arith.sub(cx, half), w, windows)
      +z0 = world_centi(F64Arith.sub(cy, half), w, windows)
      +x1 = world_centi(F64Arith.add(cx, half), w, windows)
      +z1 = world_centi(F64Arith.add(cy, half), w, windows)
      FilterDump.Piece{Strings.name(name), source, turn, world_centi(cx, w, windows), world_centi(cy, w, windows), x0, z0, x1, z1, members}

# The set pieces numbered from k, with the members of their groups.
def pieces_of(pieces: List<&2, PopulateSetpiece.Piece>, +groups: List<&2, Group>, +k: U32, +w: U32, +windows: Bool) -> List<&2, FilterDump.Piece>:
  match pieces:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      piece_of(p, group_members(groups, k), w, windows) <> pieces_of(rest, groups_after(groups, k), (k + 1 : U32), w, windows)

def tile_name_le(a: FilterDump.TileName, b: FilterDump.TileName) -> Bool:
  match a b:
    case FilterDump.TileName{_, x} FilterDump.TileName{_, y}:
      String.is_le(x, y)

def tile_names_of(tiles: List<&2, SearchVocab.Tile>, ids: List<&2, U32>) -> List<&2, FilterDump.TileName>:
  match tiles ids:
    case Con{SearchVocab.Tile{+name, _}, rest} Con{+id, more}:
      FilterDump.TileName{id, name} <> tile_names_of(rest, more)
    case _ _:
      Nil{}

# A road coordinate in the ENTS unit: 10 * floor((p - w / 2) * 4 * 10) with the game's double arithmetic (so the savedata value
# times 100).
def road_units(+t: F64Repr.F64, +half: F64Repr.F64) -> U32:
  (F64Repr.to_i32(F64Repr.floor(F64Arith.mul(F64Arith.mul(F64Arith.sub(t, half), F64Repr.from_u32(4)), F64Repr.from_u32(10)))) * 10 : U32)

def road_of(+w: U32, +p: TileWorld.Point) -> FilterDump.Position:
  match p:
    case TileWorld.Point{+x, +y}:
      +half = F64Arith.mul(F64Repr.from_u32(w), F64Repr.half())
      +xk = road_units(F32Ops.to_f64(x), half)
      +zk = road_units(F32Ops.to_f64(y), half)
      FilterDump.Position{xk, zk}

def road_positions(points: List<&2, TileWorld.Point>, +w: U32) -> List<&2, FilterDump.Position>:
  match points:
    case Nil{}:
      Nil{}
    case Con{+p, rest}:
      road_of(w, p) <> road_positions(rest, w)

def roads_kept(roads: List<&2, List<&2, TileWorld.Point>>, +min_road: U32, +w: U32, +weight: U32) -> List<&2, FilterDump.Road>:
  match roads:
    case Nil{}:
      Nil{}
    case Con{+points, rest}:
      +tail = roads_kept(rest, min_road, w, 1)
      Bool.pick(List<&2, FilterDump.Road>, (min_road <= U32.from_nat(List.length(&2, TileWorld.Point, points)) : U32), FilterDump.Road{weight, road_positions(points, w)} <> tail, tail)

# The roads forest_map saves: the polylines with at least min_road points, in order; a kept first road weighs 3 whatever
# GetRoad says, the others 1.
def roads_of(roads: List<&2, List<&2, TileWorld.Point>>, +min_road: U32, +w: U32) -> List<&2, FilterDump.Road>:
  roads_kept(roads, min_road, w, 3)

def dump_of(got: Array<List<&2, OceanEnts.Ent>> & List<&2, OceanEnts.Ent>, +seed: U32, +windows: Bool, +w: U32, +tiles: List<&2, U32>, +pieces: List<&2, PopulateSetpiece.Piece>, +roads: List<&2, FilterDump.Road>) -> FilterDump.Dump:
  (a, +wormholes) = got
  +found = named_loop(U32.to_nat(sid_slots()), Array.swap(List<&2, OceanEnts.Ent>, a, 0, Nil{}), 0, Nil{})
  +named = List.sort(~Named, ~named_le, with_pocket(with_pocket(found, GenTagsData.vocab_shadow_container()), GenTagsData.vocab_rabbitkinghorn_container()))
  FilterDump.Generated{seed, Bool.pick(U32, windows, 1, 2), 0, Constants.game_build(), w, w,
    List.sort(~FilterDump.TileName, ~tile_name_le, tile_names_of(SearchVocab.tiles(), GenTagsData.vocab_tile_ids())), tiles,
    prefabs_of(named, windows), links(wormholes), [], Some{pieces_of(pieces, groups_of(tagged_of(named, 0)), 1, w, windows)}, Some{roads}}

def wormhole_sid() -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, GenTagsData.vocab_prefab_sids(), U32.to_nat(GenTagsData.vocab_wormhole())), 0)

# The world dump (docs/world-dump.md) of a generated world (the seed's world attempt on the platform): every
# savedata.ents entry whatever its prefab, and the pocket dimension containers, per prefab in name order, and the
# placed layouts with their members.
def dump(+seed: U32, +windows: Bool, final: GenJob.Final) -> FilterDump.Dump:
  match final:
    case GenJob.Final{g, _, +ents, +w, +pieces, +roads, +min_road}:
      +tiles = packed(g, (w * w : U32))
      dump_of(Array.get(List<&2, OceanEnts.Ent>, sid_buckets(ents, Array.new(List<&2, OceanEnts.Ent>, GenTagsData.sid_depth(), Nil{})), wormhole_sid()),
        seed, windows, w, tiles, pieces, roads_of(roads, min_road, w))
