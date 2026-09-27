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

# A world dump (docs/world-dump.md) as the file lays it out: a generated world (tiles packed two u16 per word, the
# first in the low half), or the seed and platform of one whose generation gave up.
type Dump is Data:
  Generated{seed: U32, platform: U32, build: U32, width: U32, height: U32, tile_names: List<&2, TileName>, tiles: List<&2, U32>, prefabs: List<&2, Prefab>, links: List<&2, Link>}
  GaveUp{seed: U32, platform: U32}

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
    case 1296125524 Generated{+seed, +platform, +build, +width, +height, _, +tiles, +prefabs, +links}:
      Generated{seed, platform, build, width, height, counted(~TileName, ~tile_name_of, payload), tiles, prefabs, links}
    case 1162627412 Generated{+seed, +platform, +build, +width, +height, +tile_names, _, +prefabs, +links}:
      Generated{seed, platform, build, width, height, tile_names, payload, prefabs, links}
    case 1398033989 Generated{+seed, +platform, +build, +width, +height, +tile_names, +tiles, _, +links}:
      Generated{seed, platform, build, width, height, tile_names, tiles, counted(~Prefab, ~prefab_of, payload), links}
    case 1297239895 Generated{+seed, +platform, +build, +width, +height, +tile_names, +tiles, +prefabs, _}:
      Generated{seed, platform, build, width, height, tile_names, tiles, prefabs, counted(~Link, ~link_of, payload)}
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
    case Con{_, Con{2, Con{+seed, Con{1, Con{+platform, Con{+build, Con{+width, Con{+height, +rest}}}}}}}}:
      Done{sections(List.length(&2, U32, rest), rest, Generated{seed, platform, build, width, height, Nil{}, Nil{}, Nil{}, Nil{}})}
    case Con{_, Con{2, Con{+seed, Con{0, Con{+platform, _}}}}}:
      Done{GaveUp{seed, platform}}
    case Con{_, Con{+version, _}}:
      Fail{(2, "world dump format " ++ U32.show(version) ++ ", regenerate it (this finder reads format 2)")}
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
