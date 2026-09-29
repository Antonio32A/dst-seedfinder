import Base

# A world_tile_map entry.
type TileName is Data:
  TileName{id: U32, name: String}

# An instance position in hundredths of world units (int32 bits).
type Position is Data:
  Position{xk: U32, zk: U32}

# A prefab's instances in savedata order.
type Prefab is Data:
  Prefab{name: String, positions: List<&2, Position>}

# A directed wormhole link between two `wormhole` instance indices.
type Link is Data:
  Link{entry: U32, exit: U32}

# A directed tentacle pillar link (the PILL section): the entry and exit instance, each as the position of its
# prefab in ENTS (from 0) and its index in that prefab.
type Pillar is Data:
  Pillar{entry_prefab: U32, entry: U32, exit_prefab: U32, exit: U32}

# A set piece member: instance `index` of the `prefab`-th ENTS prefab (both from 0).
type Member is Data:
  Member{prefab: U32, index: U32}

# A static layout the world generation placed (the SETP section): its name, source and transform, its centre and
# bounds (xmin, zmin, xmax, zmax) in hundredths of world units (int32 bits), and its members.
type Piece is Data:
  Piece{name: String, source: U32, turn: U32, xk: U32, zk: U32, x0k: U32, z0k: U32, x1k: U32, z1k: U32, members: List<&2, Member>}

# A road the game saved (the ROAD section): its weight and its points in hundredths of world units (int32 bits).
type Road is Data:
  Road{weight: U32, points: List<&2, Position>}

# A world dump (docs/world-dump.md) as the file lays it out: a generated world (tiles packed two u16 per word, the
# first in the low half; its shard, 0 forest or 1 caves; its set pieces when it has a SETP section and its roads when it
# has a ROAD section), or the seed, platform and shard of one whose generation gave up.
type Dump is Data:
  Generated{seed: U32, platform: U32, shard: U32, build: U32, width: U32, height: U32, tile_names: List<&2, TileName>, tiles: List<&2, U32>, prefabs: List<&2, Prefab>, links: List<&2, Link>, pillars: List<&2, Pillar>, pieces: Maybe<&2, List<&2, Piece>>, roads: Maybe<&2, List<&2, Road>>}
  GaveUp{seed: U32, platform: U32, shard: U32}

def magic() -> U32:
  1465144132

def words_of(bytes: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      words_of(rest, ((a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n)) : U32) <> acc)
    case _:
      List.reverse(&2, U32, acc)

def bytes_of(words: List<&2, U32>) -> List<&2, U32>:
  match words:
    case Nil{}:
      Nil{}
    case Con{+w, rest}:
      (w .&. 255 : U32) <> ((w >> 8n) .&. 255 : U32) <> ((w >> 16n) .&. 255 : U32) <> (w >> 24n : U32) <> bytes_of(rest)

def text_of(n: Nat, bytes: List<&2, U32>) -> String:
  match n bytes:
    case 1n+p Con{+b, rest}:
      SCon{Chr{b}, text_of(p, rest)}
    case _ _:
      SNil{}

def string_of(words: List<&2, U32>) -> String & List<&2, U32>:
  match words:
    case Con{+n, +rest}:
      +padded = U32.to_nat(((n + 3 : U32) >> 2n : U32))
      (text_of(U32.to_nat(n), bytes_of(List.take(&2, U32, rest, padded))), List.drop(&2, U32, rest, padded))
    case Nil{}:
      (SNil{}, Nil{})

def tile_name_with(+id: U32, got: String & List<&2, U32>) -> TileName & List<&2, U32>:
  (name, rest) = got
  (TileName{id, name}, rest)

def tile_name_of(words: List<&2, U32>) -> TileName & List<&2, U32>:
  match words:
    case Con{+id, rest}:
      tile_name_with(id, string_of(rest))
    case Nil{}:
      (TileName{0, SNil{}}, Nil{})

def positions_of(n: Nat, words: List<&2, U32>) -> List<&2, Position>:
  match n words:
    case 1n+p Con{+xk, Con{+zk, rest}}:
      Position{xk, zk} <> positions_of(p, rest)
    case _ _:
      Nil{}

def prefab_with(got: String & List<&2, U32>) -> Prefab & List<&2, U32>:
  (name, rest) = got
  match rest:
    case Con{+count, +more}:
      (Prefab{name, positions_of(U32.to_nat(count), more)}, List.drop(&2, U32, more, Nat.add(U32.to_nat(count), U32.to_nat(count))))
    case Nil{}:
      (Prefab{name, Nil{}}, Nil{})

def prefab_of(words: List<&2, U32>) -> Prefab & List<&2, U32>:
  prefab_with(string_of(words))

def link_of(words: List<&2, U32>) -> Link & List<&2, U32>:
  match words:
    case Con{+entry, Con{+exit, rest}}:
      (Link{entry, exit}, rest)
    case _:
      (Link{0, 0}, Nil{})

def pillar_of(words: List<&2, U32>) -> Pillar & List<&2, U32>:
  match words:
    case Con{+entry_prefab, Con{+entry, Con{+exit_prefab, Con{+exit, rest}}}}:
      (Pillar{entry_prefab, entry, exit_prefab, exit}, rest)
    case _:
      (Pillar{0, 0, 0, 0}, Nil{})

def members_of(n: Nat, words: List<&2, U32>) -> List<&2, Member>:
  match n words:
    case 1n+p Con{+prefab, Con{+index, rest}}:
      Member{prefab, index} <> members_of(p, rest)
    case _ _:
      Nil{}

def piece_with(got: String & List<&2, U32>) -> Piece & List<&2, U32>:
  (name, rest) = got
  match rest:
    case Con{+source, Con{+turn, Con{+xk, Con{+zk, Con{+x0k, Con{+z0k, Con{+x1k, Con{+z1k, Con{+count, +more}}}}}}}}}:
      +n = U32.to_nat(count)
      (Piece{name, source, turn, xk, zk, x0k, z0k, x1k, z1k, members_of(n, more)}, List.drop(&2, U32, more, Nat.add(n, n)))
    case _:
      (Piece{name, 0, 0, 0, 0, 0, 0, 0, 0, Nil{}}, Nil{})

def piece_of(words: List<&2, U32>) -> Piece & List<&2, U32>:
  piece_with(string_of(words))

def road_of(words: List<&2, U32>) -> Road & List<&2, U32>:
  match words:
    case Con{+weight, Con{+count, +more}}:
      +n = U32.to_nat(count)
      (Road{weight, positions_of(n, more)}, List.drop(&2, U32, more, Nat.add(n, n)))
    case _:
      (Road{0, Nil{}}, Nil{})

def entries(~A: Data, ~entry: List<&2, U32> -> A & List<&2, U32>, n: Nat, got: A & List<&2, U32>) -> List<&2, A>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      (item, rest) = got
      item <> entries(~A, ~entry, p, entry(rest))

def counted(~A: Data, ~entry: List<&2, U32> -> A & List<&2, U32>, words: List<&2, U32>) -> List<&2, A>:
  match words:
    case Con{+count, rest}:
      entries(~A, ~entry, U32.to_nat(count), entry(rest))
    case Nil{}:
      Nil{}

def with_section(tag: U32, payload: List<&2, U32>, d: Dump) -> Dump:
  match tag d:
    case 1296125524 Generated{+seed, +platform, +shard, +build, +width, +height, _, +tiles, +prefabs, +links, +pillars, +pieces, +roads}:
      Generated{seed, platform, shard, build, width, height, counted(~TileName, ~tile_name_of, payload), tiles, prefabs, links, pillars, pieces, roads}
    case 1162627412 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, _, +prefabs, +links, +pillars, +pieces, +roads}:
      Generated{seed, platform, shard, build, width, height, tile_names, payload, prefabs, links, pillars, pieces, roads}
    case 1398033989 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, _, +links, +pillars, +pieces, +roads}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, counted(~Prefab, ~prefab_of, payload), links, pillars, pieces, roads}
    case 1297239895 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, _, +pillars, +pieces, +roads}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, counted(~Link, ~link_of, payload), pillars, pieces, roads}
    case 1280067920 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, +links, _, +pieces, +roads}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, links, counted(~Pillar, ~pillar_of, payload), pieces, roads}
    case 1347700051 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, +links, +pillars, _, +roads}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, links, pillars, Some{counted(~Piece, ~piece_of, payload)}, roads}
    case 1145130834 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, +links, +pillars, +pieces, _}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, links, pillars, pieces, Some{counted(~Road, ~road_of, payload)}}
    case _ other:
      other

def sections(fuel: Nat, words: List<&2, U32>, d: Dump) -> Dump:
  match fuel words:
    case 1n+p Con{+tag, Con{+length, +rest}}:
      +n = U32.to_nat((length >> 2n : U32))
      sections(p, List.drop(&2, U32, rest, n), with_section(tag, List.take(&2, U32, rest, n), d))
    case _ _:
      d

def versioned(words: List<&2, U32>) -> Result<&1, &1, U32 & String, Dump>:
  match words:
    case Con{_, Con{3, Con{+seed, Con{1, Con{+platform, Con{+shard, Con{+build, Con{+width, Con{+height, +rest}}}}}}}}}:
      Done{sections(List.length(&2, U32, rest), rest, Generated{seed, platform, shard, build, width, height, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, None{}, None{}})}
    case Con{_, Con{3, Con{+seed, Con{0, Con{+platform, Con{+shard, _}}}}}}:
      Done{GaveUp{seed, platform, shard}}
    case Con{_, Con{+version, _}}:
      Fail{(2, "world dump format " ++ U32.show(version) ++ ", regenerate it (this finder reads format 3)")}
    case _:
      Fail{(2, "not a world dump")}

def is_dump(words: List<&2, U32>) -> Bool:
  match words:
    case Con{+tag, _}:
      U32.is_eq(tag, magic())
    case Nil{}:
      False{}

# Reads a world dump from its bytes.
def of_bytes(bytes: List<&2, U32>) -> Result<&1, &1, U32 & String, Dump>:
  +words = words_of(bytes, Nil{})
  Bool.pick(Result<&1, &1, U32 & String, Dump>, is_dump(words), versioned(words), Fail{(2, "not a world dump")})

def string_bytes(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{+b}, rest}:
      b <> string_bytes(rest)

def string_field(s: String) -> List<&2, U32>:
  +raw = string_bytes(s)
  +n = U32.from_nat(List.length(&2, U32, raw))
  List.append(&2, U32, bytes_of([n]), List.append(&2, U32, raw, List.replicate(U32, U32.to_nat(((4 - (n .&. 3)) .&. 3 : U32)), 0)))

def entries_bytes(~A: Data, ~entry: A -> List<&2, U32>, items: List<&2, A>) -> List<&2, U32>:
  match items:
    case Nil{}:
      Nil{}
    case Con{+item, rest}:
      List.append(&2, U32, entry(item), entries_bytes(~A, ~entry, rest))

def counted_bytes(~A: Data, ~entry: A -> List<&2, U32>, +items: List<&2, A>) -> List<&2, U32>:
  List.append(&2, U32, bytes_of([U32.from_nat(List.length(&2, A, items))]), entries_bytes(~A, ~entry, items))

def section(+tag: U32, +payload: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, bytes_of([tag, U32.from_nat(List.length(&2, U32, payload))]), payload)

def tile_name_bytes(n: TileName) -> List<&2, U32>:
  match n:
    case TileName{+id, +name}:
      List.append(&2, U32, bytes_of([id]), string_field(name))

# The TNAM section of these tile names, in the given order.
def tile_names_section(+names: List<&2, TileName>) -> List<&2, U32>:
  section(1296125524, counted_bytes(~TileName, ~tile_name_bytes, names))

# The TILE section of tiles packed two u16 per word (the first in the low half, a zero high half after an odd count).
def tiles_section(+tiles: List<&2, U32>) -> List<&2, U32>:
  section(1162627412, bytes_of(tiles))

def position_words(positions: List<&2, Position>) -> List<&2, U32>:
  match positions:
    case Nil{}:
      Nil{}
    case Con{Position{+xk, +zk}, rest}:
      xk <> zk <> position_words(rest)

def prefab_bytes(p: Prefab) -> List<&2, U32>:
  match p:
    case Prefab{+name, +positions}:
      List.append(&2, U32, string_field(name), bytes_of(U32.from_nat(List.length(&2, Position, positions)) <> position_words(positions)))

# The ENTS section of these prefabs, in the given order.
def entities_section(+prefabs: List<&2, Prefab>) -> List<&2, U32>:
  section(1398033989, counted_bytes(~Prefab, ~prefab_bytes, prefabs))

def link_words(links: List<&2, Link>) -> List<&2, U32>:
  match links:
    case Nil{}:
      Nil{}
    case Con{Link{+entry, +exit}, rest}:
      entry <> exit <> link_words(rest)

# The WORM section of these links, in the given order.
def links_section(+links: List<&2, Link>) -> List<&2, U32>:
  section(1297239895, bytes_of(U32.from_nat(List.length(&2, Link, links)) <> link_words(links)))

def pillar_words(pillars: List<&2, Pillar>) -> List<&2, U32>:
  match pillars:
    case Nil{}:
      Nil{}
    case Con{Pillar{+entry_prefab, +entry, +exit_prefab, +exit}, rest}:
      entry_prefab <> entry <> exit_prefab <> exit <> pillar_words(rest)

# The PILL section of these tentacle pillar links, in the given order.
def pillars_section(+pillars: List<&2, Pillar>) -> List<&2, U32>:
  section(1280067920, bytes_of(U32.from_nat(List.length(&2, Pillar, pillars)) <> pillar_words(pillars)))

def optional_pillars(+shard: U32, +pillars: List<&2, Pillar>) -> List<&2, U32>:
  match shard:
    case 1:
      pillars_section(pillars)
    case _:
      Nil{}

def member_words(members: List<&2, Member>) -> List<&2, U32>:
  match members:
    case Nil{}:
      Nil{}
    case Con{Member{+prefab, +index}, rest}:
      prefab <> index <> member_words(rest)

def piece_bytes(p: Piece) -> List<&2, U32>:
  match p:
    case Piece{+name, +source, +turn, +xk, +zk, +x0k, +z0k, +x1k, +z1k, +members}:
      +count = U32.from_nat(List.length(&2, Member, members))
      List.append(&2, U32, string_field(name), bytes_of(source <> turn <> xk <> zk <> x0k <> z0k <> x1k <> z1k <> count <> member_words(members)))

# The SETP section of these set pieces, in the given order.
def set_pieces_section(+pieces: List<&2, Piece>) -> List<&2, U32>:
  section(1347700051, counted_bytes(~Piece, ~piece_bytes, pieces))

def road_bytes(r: Road) -> List<&2, U32>:
  match r:
    case Road{+weight, +points}:
      bytes_of(weight <> U32.from_nat(List.length(&2, Position, points)) <> position_words(points))

# The ROAD section of these roads, in the given order.
def roads_section(+roads: List<&2, Road>) -> List<&2, U32>:
  section(1145130834, counted_bytes(~Road, ~road_bytes, roads))

def optional_roads(+roads: Maybe<&2, List<&2, Road>>) -> List<&2, U32>:
  match roads:
    case None{}:
      Nil{}
    case Some{+found}:
      roads_section(found)

def optional_set_pieces(+pieces: Maybe<&2, List<&2, Piece>>) -> List<&2, U32>:
  match pieces:
    case None{}:
      Nil{}
    case Some{+found}:
      set_pieces_section(found)

# A world dump's file bytes: the header, then a generated world's TNAM, TILE, ENTS and WORM sections and, in the caves
# shard, its PILL section, and, when it has set pieces, its SETP section and, when it has roads, its ROAD section.
def bytes(d: Dump) -> List<&2, U32>:
  match d:
    case GaveUp{+seed, +platform, +shard}:
      bytes_of([magic(), 3, seed, 0, platform, shard])
    case Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, +links, +pillars, +pieces, +roads}:
      List.concat(&2, U32, [bytes_of([magic(), 3, seed, 1, platform, shard, build, width, height]), tile_names_section(tile_names), tiles_section(tiles),
        entities_section(prefabs), links_section(links), optional_pillars(shard, pillars), optional_set_pieces(pieces), optional_roads(roads)])

# The prefabs of a dump (none when its world generation gave up).
def prefabs(+d: Dump) -> List<&2, Prefab>:
  match d:
    case Generated{_, _, _, _, _, _, _, _, +found, _, _, _, _}:
      found
    case GaveUp{_, _, _}:
      Nil{}

# The set pieces of a dump (none when it has no SETP section).
def set_pieces(+d: Dump) -> Maybe<&2, List<&2, Piece>>:
  match d:
    case Generated{_, _, _, _, _, _, _, _, _, _, _, +found, _}:
      found
    case GaveUp{_, _, _}:
      None{}

# The roads of a dump (none when it has no ROAD section).
def roads(+d: Dump) -> Maybe<&2, List<&2, Road>>:
  match d:
    case Generated{_, _, _, _, _, _, _, _, _, _, _, _, +found}:
      found
    case GaveUp{_, _, _}:
      None{}
