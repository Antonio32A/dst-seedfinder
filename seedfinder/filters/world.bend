import Base
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../data/search_vocab.bend as SearchVocab

# A generated world as the filters see it (.scratch/port/tools/world_dump.py writes the dump; M11 will build it from
# the generator instead). Instances are savedata.ents entries: `index` is the position in its prefab's list, x/z the
# doubles the worldgen rounded to 0.01, xk/zk those values times 100, and flags bit 0/1 say that x/z were integers in
# the JSON (for printing them like Python does).
type Inst is Data:
  Inst{prefab: U32, index: U32, x: F64Repr.F64, z: F64Repr.F64, xk: U32, zk: U32, flags: U32}

# A directed wormhole link between two `wormhole` instances.
type Link is Data:
  Link{entry: Inst, exit: Inst}

# width x height tiles (packed two u16 per word, row-major), the world_tile_map id of every vocabulary tile (65535
# when absent), the instances of every vocabulary prefab, and the wormhole links in teleporter order.
type World is Data:
  World{seed: U32, width: U32, height: U32, tile_ids: List<&2, U32>, entities: List<&2, List<&2, Inst>>, links: List<&2, Link>, tiles: List<&2, U32>}

# A dump: a generated world with its platform (0 unknown, 1 windows, 2 linux), or the seed of a world whose
# generation gave up.
type Loaded is Data:
  Generated{world: World, platform: U32}
  GaveUp{seed: U32}

def magic() -> U32:
  1465144132

def words_of(bytes: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      words_of(rest, ((a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n)) : U32) <> acc)
    case _:
      List.reverse(&2, U32, acc)

type Taken is Data:
  Taken{items: List<&2, U32>, rest: List<&2, U32>}

def taken(+n: U32, +words: List<&2, U32>) -> Taken:
  Taken{List.take(&2, U32, words, U32.to_nat(n)), List.drop(&2, U32, words, U32.to_nat(n))}

type Insts is Data:
  Insts{items: List<&2, Inst>, rest: List<&2, U32>}

def inst_list(n: Nat, +prefab: U32, +index: U32, words: List<&2, U32>, acc: List<&2, Inst>) -> Insts:
  match n words:
    case 1n+p Con{+xh, Con{+xl, Con{+zh, Con{+zl, Con{+xk, Con{+zk, Con{+flags, rest}}}}}}}:
      inst_list(p, prefab, (index + 1 : U32), rest, Inst{prefab, index, F64Repr.F64{xh, xl}, F64Repr.F64{zh, zl}, xk, zk, flags} <> acc)
    case _ rest:
      Insts{List.reverse(&2, Inst, acc), rest}

type Grouped is Data:
  Grouped{groups: List<&2, List<&2, Inst>>, rest: List<&2, U32>}

def grouped(counts: List<&2, U32>, +prefab: U32, got: Insts, acc: List<&2, List<&2, Inst>>) -> Grouped:
  match counts got:
    case Nil{} Insts{items, rest}:
      Grouped{List.drop(&2, List<&2, Inst>, List.reverse(&2, List<&2, Inst>, items <> acc), 1n), rest}
    case Con{+n, more} Insts{items, rest}:
      grouped(more, (prefab + 1 : U32), inst_list(U32.to_nat(n), prefab, 0, rest, Nil{}), items <> acc)

def instance_at(+groups: List<&2, List<&2, Inst>>, +prefab: U32, +index: U32) -> Inst:
  +group = Maybe.default(&2, List<&2, Inst>, List.get(&2, List<&2, Inst>, groups, U32.to_nat(prefab)), Nil{})
  Maybe.default(&2, Inst, List.get(&2, Inst, group, U32.to_nat(index)), Inst{prefab, index, F64Repr.zero(), F64Repr.zero(), 0, 0, 0})

def link_list(n: Nat, +groups: List<&2, List<&2, Inst>>, +wormhole: U32, words: List<&2, U32>, acc: List<&2, Link>) -> Taken & List<&2, Link>:
  match n words:
    case 1n+p Con{+entry, Con{+exit, rest}}:
      link_list(p, groups, wormhole, rest, Link{instance_at(groups, wormhole, entry), instance_at(groups, wormhole, exit)} <> acc)
    case _ rest:
      (Taken{Nil{}, rest}, List.reverse(&2, Link, acc))

def index_of(names: List<&2, String>, +name: String, +i: U32) -> U32:
  match names:
    case Nil{}:
      i
    case Con{+entry, rest}:
      Bool.pick(U32, String.eq(entry, name), i, index_of(rest, name, (i + 1 : U32)))

# The vocabulary id of a prefab name (the vocabulary size when unknown).
def prefab_id(+name: String) -> U32:
  index_of(SearchVocab.prefabs(), name, 0)

def world_from_links(+seed: U32, +width: U32, +height: U32, +tile_ids: List<&2, U32>, +groups: List<&2, List<&2, Inst>>, got: Taken & List<&2, Link>) -> Loaded:
  (rest, links) = got
  match rest:
    case Taken{_, tiles}:
      Generated{World{seed, width, height, tile_ids, groups, links, tiles}, 0}

def world_from_groups(+seed: U32, +width: U32, +height: U32, +tile_ids: List<&2, U32>, g: Grouped) -> Loaded:
  match g:
    case Grouped{+groups, Con{+count, rest}}:
      world_from_links(seed, width, height, tile_ids, groups, link_list(U32.to_nat(count), groups, prefab_id("wormhole"), rest, Nil{}))
    case Grouped{_, _}:
      GaveUp{seed}

def world_from_counts(+seed: U32, +width: U32, +height: U32, +tile_ids: List<&2, U32>, counts: Taken) -> Loaded:
  match counts:
    case Taken{items, rest}:
      world_from_groups(seed, width, height, tile_ids, grouped(items, 0, Insts{Nil{}, rest}, Nil{}))

def world_from_tiles(+seed: U32, +width: U32, +height: U32, ids: Taken) -> Loaded:
  match ids:
    case Taken{+tile_ids, Con{+prefabs, rest}}:
      world_from_counts(seed, width, height, tile_ids, taken(prefabs, rest))
    case Taken{_, _}:
      GaveUp{seed}

def generated(words: List<&2, U32>, +seed: U32) -> Loaded:
  match words:
    case Con{+width, Con{+height, Con{+tile_count, rest}}}:
      world_from_tiles(seed, width, height, taken(tile_count, rest))
    case _:
      GaveUp{seed}

def with_platform(l: Loaded, +platform: U32) -> Loaded:
  match l:
    case Generated{world, _}:
      Generated{world, platform}
    case other:
      other

def loaded_of(words: List<&2, U32>) -> Result<&1, &1, U32 & String, Loaded>:
  match words:
    case Con{+tag, Con{1, Con{+seed, Con{1, Con{+platform, rest}}}}}:
      Bool.pick(Result<&1, &1, U32 & String, Loaded>, U32.is_eq(tag, magic()), Done{with_platform(generated(rest, seed), platform)}, Fail{(2, "not a world dump")})
    case Con{+tag, Con{1, Con{+seed, Con{0, _}}}}:
      Bool.pick(Result<&1, &1, U32 & String, Loaded>, U32.is_eq(tag, magic()), Done{GaveUp{seed}}, Fail{(2, "not a world dump")})
    case _:
      Fail{(2, "not a world dump (format 1)")}

# Reads a dump of .scratch/port/tools/world_dump.py from its bytes.
def of_bytes(bytes: List<&2, U32>) -> Result<&1, &1, U32 & String, Loaded>:
  loaded_of(words_of(bytes, Nil{}))

def instance_groups(+groups: List<&2, List<&2, Inst>>, ids: List<&2, U32>) -> List<&2, List<&2, Inst>>:
  match ids:
    case Nil{}:
      Nil{}
    case Con{+id, rest}:
      Maybe.default(&2, List<&2, Inst>, List.get(&2, List<&2, Inst>, groups, U32.to_nat(id)), Nil{}) <> instance_groups(groups, rest)

# The instances of a prefab set, prefab by prefab (search-v1.md: the union over the ids, in order).
def instances(+world: World, ids: List<&2, U32>) -> List<&2, Inst>:
  match world:
    case World{_, _, _, _, +groups, _, _}:
      List.concat(&2, Inst, instance_groups(groups, ids))

def is_land_tile(+tile: U32) -> Bool:
  ((2 <= tile : U32) && (tile <= 127 : U32)) || ((256 <= tile : U32) && (tile <= 10497 : U32))
