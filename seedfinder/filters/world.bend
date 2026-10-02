import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../gen/centi.bend as Centi
import ../data/search_vocab.bend as SearchVocab
import ../data/gen_tags.bend as GenTagsData
import ./dump.bend as FilterDump
import ./parse.bend as Parse

# A generated world as the filters see it (gen/savedata.bend builds it, of_bytes reads it from a world dump).
# Instances are savedata.ents entries: `index` is the position in its prefab's list, x/z the doubles the worldgen
# rounded to 0.01, xk/zk those values times 100, and flags bit 0/1 say that x/z are whole (for printing them like
# Python does).
type Inst is Data:
  Inst{prefab: U32, index: U32, x: F64Repr.F64, z: F64Repr.F64, xk: U32, zk: U32, flags: U32}

# A directed wormhole link between two `wormhole` instances.
type Link is Data:
  Link{entry: Inst, exit: Inst}

# width x height tiles (packed two u16 per word, row-major), the world_tile_map id of every vocabulary tile (65535
# when absent), the instances of every vocabulary prefab, and the wormhole links in savedata order.
type World is Data:
  World{seed: U32, width: U32, height: U32, tile_ids: List<&2, U32>, entities: List<&2, List<&2, Inst>>, links: List<&2, Link>, tiles: List<&2, U32>}

# A dump: a generated world with its platform (0 unknown, 1 windows, 2 linux), or the seed of a world whose
# generation gave up. A dump of the other shard than the one asked for is refused.
type Loaded is Data:
  Generated{world: World, platform: U32}
  GaveUp{seed: U32}

def magnitude(+k: U32) -> U32:
  Bool.pick(U32, (k >= 2147483648 : U32), (0 - k : U32), k)

def whole_flag(+k: U32) -> U32:
  Bool.to_u32(U32.is_zero(U32.mod(magnitude(k), 100)))

# The instance at hundredths (xk, zk) of a position.
def inst_of(+prefab: U32, +index: U32, +xk: U32, +zk: U32) -> Inst:
  Inst{prefab, index, F64Arith.div(F64Repr.from_i32(xk), Centi.hundred()), F64Arith.div(F64Repr.from_i32(zk), Centi.hundred()), xk, zk,
    (whole_flag(xk) .|. (whole_flag(zk) << 1n) : U32)}

def insts_of(positions: List<&2, FilterDump.Position>, +prefab: U32, +index: U32) -> List<&2, Inst>:
  match positions:
    case Nil{}:
      Nil{}
    case Con{FilterDump.Position{+xk, +zk}, rest}:
      inst_of(prefab, index, xk, zk) <> insts_of(rest, prefab, (index + 1 : U32))

def picked(same: Bool, positions: List<&2, FilterDump.Position>, +prefab: U32, later: List<&2, Inst>) -> List<&2, Inst>:
  match same:
    case True{}:
      insts_of(positions, prefab, 0)
    case False{}:
      later

# The instances of the dump's prefab `name`, as vocabulary prefab `prefab`.
def group_of(prefabs: List<&2, FilterDump.Prefab>, +name: String, +prefab: U32) -> List<&2, Inst>:
  match prefabs:
    case Nil{}:
      Nil{}
    case Con{FilterDump.Prefab{+found, +positions}, rest}:
      picked(String.eq(found, name), positions, prefab, group_of(rest, name, prefab))

def groups_of(names: List<&2, String>, +prefabs: List<&2, FilterDump.Prefab>, +prefab: U32) -> List<&2, List<&2, Inst>>:
  match names:
    case Nil{}:
      Nil{}
    case Con{+name, rest}:
      group_of(prefabs, name, prefab) <> groups_of(rest, prefabs, (prefab + 1 : U32))

def tile_id_of(tile_names: List<&2, FilterDump.TileName>, +name: String) -> U32:
  match tile_names:
    case Nil{}:
      65535
    case Con{FilterDump.TileName{+id, +found}, rest}:
      Bool.pick(U32, String.eq(found, name), id, tile_id_of(rest, name))

def tile_ids_of(tiles: List<&2, SearchVocab.Tile>, +tile_names: List<&2, FilterDump.TileName>) -> List<&2, U32>:
  match tiles:
    case Nil{}:
      Nil{}
    case Con{SearchVocab.Tile{+name, _}, rest}:
      tile_id_of(tile_names, name) <> tile_ids_of(rest, tile_names)

def instance_at(+groups: List<&2, List<&2, Inst>>, +prefab: U32, +index: U32) -> Inst:
  +group = Maybe.default(&2, List<&2, Inst>, List.get(&2, List<&2, Inst>, groups, U32.to_nat(prefab)), Nil{})
  Maybe.default(&2, Inst, List.get(&2, Inst, group, U32.to_nat(index)), Inst{prefab, index, F64Repr.zero(), F64Repr.zero(), 0, 0, 0})

def links_of(links: List<&2, FilterDump.Link>, +groups: List<&2, List<&2, Inst>>, +wormhole: U32) -> List<&2, Link>:
  match links:
    case Nil{}:
      Nil{}
    case Con{FilterDump.Link{+entry, +exit}, rest}:
      Link{instance_at(groups, wormhole, entry), instance_at(groups, wormhole, exit)} <> links_of(rest, groups, wormhole)

def prefab_name_at(prefabs: List<&2, FilterDump.Prefab>, +position: U32) -> String:
  match prefabs:
    case Nil{}:
      ""
    case Con{FilterDump.Prefab{+name, _}, rest}:
      Bool.pick(String, U32.is_zero(position), name, prefab_name_at(rest, (position - 1 : U32)))

def vocab_id(+name: String) -> U32:
  Maybe.default(&2, U32, Parse.index_of(SearchVocab.all_prefabs(), name, 0), 65535)

def pillar_inst(+groups: List<&2, List<&2, Inst>>, +prefabs: List<&2, FilterDump.Prefab>, +prefab: U32, +index: U32) -> Inst:
  instance_at(groups, vocab_id(prefab_name_at(prefabs, prefab)), index)

def pillar_links_of(pillars: List<&2, FilterDump.Pillar>, +prefabs: List<&2, FilterDump.Prefab>, +groups: List<&2, List<&2, Inst>>) -> List<&2, Link>:
  match pillars:
    case Nil{}:
      Nil{}
    case Con{FilterDump.Pillar{+entry_prefab, +entry, +exit_prefab, +exit}, rest}:
      Link{pillar_inst(groups, prefabs, entry_prefab, entry), pillar_inst(groups, prefabs, exit_prefab, exit)} <> pillar_links_of(rest, prefabs, groups)

def wrong_shard(+caves: Bool) -> Result<&1, &1, U32 & String, Loaded>:
  Fail{(2, Bool.pick(String, caves, "world dump of the forest shard, this finder searches the caves shard",
    "world dump of the caves shard, this finder searches the forest shard"))}

def forest_loaded(+seed: U32, +platform: U32, +width: U32, +height: U32, +tile_names: List<&2, FilterDump.TileName>, +tiles: List<&2, U32>, +prefabs: List<&2, FilterDump.Prefab>, +links: List<&2, FilterDump.Link>) -> Loaded:
  +groups = groups_of(SearchVocab.prefabs(), prefabs, 0)
  Generated{World{seed, width, height, tile_ids_of(SearchVocab.tiles(), tile_names), groups, links_of(links, groups, GenTagsData.vocab_wormhole()), tiles}, platform}

def cave_loaded(+seed: U32, +platform: U32, +width: U32, +height: U32, +tile_names: List<&2, FilterDump.TileName>, +tiles: List<&2, U32>, +prefabs: List<&2, FilterDump.Prefab>, +pillars: List<&2, FilterDump.Pillar>) -> Loaded:
  +groups = groups_of(SearchVocab.all_prefabs(), prefabs, 0)
  Generated{World{seed, width, height, tile_ids_of(SearchVocab.tiles(), tile_names), groups, pillar_links_of(pillars, prefabs, groups), tiles}, platform}

# The world of a parsed dump of the shard `caves` names; a dump of the other shard is refused.
def loaded_of(dump: Result<&1, &1, U32 & String, FilterDump.Dump>, +caves: Bool) -> Result<&1, &1, U32 & String, Loaded>:
  match dump:
    case Done{FilterDump.Generated{+seed, +platform, +shard, _, +width, +height, +tile_names, +tiles, +prefabs, +links, +pillars, _, _}}:
      Bool.pick(Result<&1, &1, U32 & String, Loaded>, U32.is_eq(shard, Bool.to_u32(caves)),
        Done{Bool.pick(Loaded, caves, cave_loaded(seed, platform, width, height, tile_names, tiles, prefabs, pillars),
          forest_loaded(seed, platform, width, height, tile_names, tiles, prefabs, links))},
        wrong_shard(caves))
    case Done{FilterDump.GaveUp{+seed, _, +shard}}:
      Bool.pick(Result<&1, &1, U32 & String, Loaded>, U32.is_eq(shard, Bool.to_u32(caves)), Done{GaveUp{seed}}, wrong_shard(caves))
    case Fail{error}:
      Fail{error}

# Reads a world dump (docs/world-dump.md) of the forest shard from its bytes, with the prefabs and tiles of the vocabulary.
def of_bytes(bytes: List<&2, U32>) -> Result<&1, &1, U32 & String, Loaded>:
  loaded_of(FilterDump.of_bytes(bytes), False{})

# Reads a world dump of the shard `caves` names (True: the caves) from its bytes.
def of_bytes_in(bytes: List<&2, U32>, +caves: Bool) -> Result<&1, &1, U32 & String, Loaded>:
  loaded_of(FilterDump.of_bytes(bytes), caves)

def instance_groups(+groups: List<&2, List<&2, Inst>>, ids: List<&2, U32>) -> List<&2, List<&2, Inst>>:
  match ids:
    case Nil{}:
      Nil{}
    case Con{+id, rest}:
      Maybe.default(&2, List<&2, Inst>, List.get(&2, List<&2, Inst>, groups, U32.to_nat(id)), Nil{}) <> instance_groups(groups, rest)

# The instances of a prefab set, prefab by prefab (docs/config.md: the union over the ids, in order).
def instances(+world: World, ids: List<&2, U32>) -> List<&2, Inst>:
  match world:
    case World{_, _, _, _, +groups, _, _}:
      List.concat(&2, Inst, instance_groups(groups, ids))

def is_land_tile(+tile: U32) -> Bool:
  ((2 <= tile : U32) && (tile <= 127 : U32)) || ((256 <= tile : U32) && (tile <= 10497 : U32))
