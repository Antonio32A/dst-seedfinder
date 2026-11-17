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

# A task set piece of the level plan (the PLAN section): its task, its name and whether the world generation placed it.
type Planned is Data:
  Planned{task: String, piece: String, placed: Bool}

# A road the game saved (the ROAD section): its weight and its points in hundredths of world units (int32 bits).
type Road is Data:
  Road{weight: U32, points: List<&2, Position>}

# A savedata topology node (the GRPH section): its id, its NODE_TYPE and its position in hundredths of world units
# (int32 bits, multiples of 100).
type Node is Data:
  Node{id: String, kind: U32, xk: U32, zk: U32}

# A topology edge between two nodes, as their positions in the node list, AddLink's first argument first.
type Edge is Data:
  Edge{n1: U32, n2: U32}

# The savedata topology without the edges ApplyPoisonTag cleared: nodes in ascending id order, edges in ascending (n1, n2)
# order.
type Graph is Data:
  Graph{nodes: List<&2, Node>, edges: List<&2, Edge>}

# A world dump (docs/world-dump.md) as the file lays it out: a generated world (tiles packed two u16 per word, the
# first in the low half; its shard, 0 forest or 1 caves; its set pieces when it has a SETP section, its level plan when
# it has a PLAN section, its roads when it has a ROAD section and its topology when it has a GRPH section), or the seed,
# platform and shard of one whose generation gave up.
type Dump is Data:
  Generated{seed: U32, platform: U32, shard: U32, build: U32, width: U32, height: U32, tile_names: List<&2, TileName>, tiles: List<&2, U32>, prefabs: List<&2, Prefab>, links: List<&2, Link>, pillars: List<&2, Pillar>, pieces: Maybe<&2, List<&2, Piece>>, plan: Maybe<&2, List<&2, Planned>>, roads: Maybe<&2, List<&2, Road>>, graph: Maybe<&2, Graph>}
  GaveUp{seed: U32, platform: U32, shard: U32}

# Encoded entries before the rest of a dump: the bytes, their size, how many entries they are and how many items the
# entries' own lists hold (the instances of ENTS prefabs).
type Onto is Data:
  Onto{bytes: List<&2, U32>, size: U32, entries: U32, items: U32}

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

def planned_with(+task: String, got: String & List<&2, U32>) -> Planned & List<&2, U32>:
  (piece, rest) = got
  match rest:
    case Con{+placed, +more}:
      (Planned{task, piece, U32.is_eq(placed, 1)}, more)
    case Nil{}:
      (Planned{task, piece, False{}}, Nil{})

def task_planned(got: String & List<&2, U32>) -> Planned & List<&2, U32>:
  (task, rest) = got
  planned_with(task, string_of(rest))

def planned_of(words: List<&2, U32>) -> Planned & List<&2, U32>:
  task_planned(string_of(words))

def road_of(words: List<&2, U32>) -> Road & List<&2, U32>:
  match words:
    case Con{+weight, Con{+count, +more}}:
      +n = U32.to_nat(count)
      (Road{weight, positions_of(n, more)}, List.drop(&2, U32, more, Nat.add(n, n)))
    case _:
      (Road{0, Nil{}}, Nil{})

def node_with(got: String & List<&2, U32>) -> Node & List<&2, U32>:
  (id, rest) = got
  match rest:
    case Con{+kind, Con{+xk, Con{+zk, +more}}}:
      (Node{id, kind, xk, zk}, more)
    case _:
      (Node{id, 0, 0, 0}, Nil{})

def node_of(words: List<&2, U32>) -> Node & List<&2, U32>:
  node_with(string_of(words))

def edges_of(n: Nat, words: List<&2, U32>) -> List<&2, Edge>:
  match n words:
    case 1n+p Con{+n1, Con{+n2, rest}}:
      Edge{n1, n2} <> edges_of(p, rest)
    case _ _:
      Nil{}

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

def graph_nodes(n: Nat, words: List<&2, U32>, got: Node & List<&2, U32>, acc: List<&2, Node>) -> List<&2, Node> & List<&2, U32>:
  match n:
    case 0n:
      (List.reverse(&2, Node, acc), words)
    case 1n+p:
      (node, +rest) = got
      graph_nodes(p, rest, node_of(rest), node <> acc)

def graph_after(got: List<&2, Node> & List<&2, U32>) -> Graph:
  (nodes, words) = got
  match words:
    case Con{+count, +rest}:
      Graph{nodes, edges_of(U32.to_nat(count), rest)}
    case Nil{}:
      Graph{nodes, Nil{}}

def graph_of(words: List<&2, U32>) -> Graph:
  match words:
    case Con{+count, +rest}:
      graph_after(graph_nodes(U32.to_nat(count), rest, node_of(rest), Nil{}))
    case Nil{}:
      Graph{Nil{}, Nil{}}

def with_section(tag: U32, payload: List<&2, U32>, d: Dump) -> Dump:
  match tag d:
    case 1296125524 Generated{+seed, +platform, +shard, +build, +width, +height, _, +tiles, +prefabs, +links, +pillars, +pieces, +plan, +roads, +graph}:
      Generated{seed, platform, shard, build, width, height, counted(~TileName, ~tile_name_of, payload), tiles, prefabs, links, pillars, pieces, plan, roads, graph}
    case 1162627412 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, _, +prefabs, +links, +pillars, +pieces, +plan, +roads, +graph}:
      Generated{seed, platform, shard, build, width, height, tile_names, payload, prefabs, links, pillars, pieces, plan, roads, graph}
    case 1398033989 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, _, +links, +pillars, +pieces, +plan, +roads, +graph}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, counted(~Prefab, ~prefab_of, payload), links, pillars, pieces, plan, roads, graph}
    case 1297239895 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, _, +pillars, +pieces, +plan, +roads, +graph}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, counted(~Link, ~link_of, payload), pillars, pieces, plan, roads, graph}
    case 1280067920 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, +links, _, +pieces, +plan, +roads, +graph}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, links, counted(~Pillar, ~pillar_of, payload), pieces, plan, roads, graph}
    case 1347700051 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, +links, +pillars, _, +plan, +roads, +graph}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, links, pillars, Some{counted(~Piece, ~piece_of, payload)}, plan, roads, graph}
    case 1312902224 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, +links, +pillars, +pieces, _, +roads, +graph}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, links, pillars, pieces, Some{counted(~Planned, ~planned_of, payload)}, roads, graph}
    case 1145130834 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, +links, +pillars, +pieces, +plan, _, +graph}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, links, pillars, pieces, plan, Some{counted(~Road, ~road_of, payload)}, graph}
    case 1213223495 Generated{+seed, +platform, +shard, +build, +width, +height, +tile_names, +tiles, +prefabs, +links, +pillars, +pieces, +plan, +roads, _}:
      Generated{seed, platform, shard, build, width, height, tile_names, tiles, prefabs, links, pillars, pieces, plan, roads, Some{graph_of(payload)}}
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
      Done{sections(List.length(&2, U32, rest), rest, Generated{seed, platform, shard, build, width, height, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, None{}, None{}, None{}, None{}})}
    case Con{_, Con{3, Con{+seed, Con{0, Con{+platform, Con{+shard, _}}}}}}:
      Done{GaveUp{seed, platform, shard}}
    case Con{_, Con{+version, _}}:
      Fail{(2, "world dump format " ++ U32.show(version) ++ ", regenerate it (this finder reads format 3)")}
    case _:
      Fail{(2, "not a world dump")}

def build_in(words: List<&2, U32>) -> U32:
  match words:
    case Con{+tag, Con{3, Con{_, Con{1, Con{_, Con{_, Con{+build, _}}}}}}}:
      Bool.pick(U32, U32.is_eq(tag, magic()), build, 0)
    case _:
      0

# The game build a world dump's header names: 0 when unknown, when the world generation gave up, or when the bytes are
# no format 3 dump.
def build_of_bytes(bytes: List<&2, U32>) -> U32:
  build_in(words_of(List.take(&2, U32, bytes, 28n), Nil{}))

# Whether a dump of build `dumped` (build_of_bytes) belongs to another build than `build`.
def is_other_build(+dumped: U32, +build: U32) -> Bool:
  Bool.not(U32.is_zero(dumped) || U32.is_eq(dumped, build))

def other_build_message(+dumped: U32, +build: U32) -> String:
  "world dump is build " ++ U32.show(dumped) ++ ", the config is build " ++ U32.show(build)

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

def word_onto(+w: U32, rest: List<&2, U32>) -> List<&2, U32>:
  (w .&. 255 : U32) <> ((w >> 8n) .&. 255 : U32) <> ((w >> 16n) .&. 255 : U32) <> (w >> 24n : U32) <> rest

def words_onto(words: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  match words:
    case Nil{}:
      rest
    case Con{w, more}:
      word_onto(w, words_onto(more, rest))

def counted_word(+w: U32, got: List<&2, U32> & U32) -> List<&2, U32> & U32:
  (bytes, +n) = got
  (word_onto(w, bytes), (n + 1 : U32))

def counted_pair(+a: U32, +b: U32, got: List<&2, U32> & U32) -> List<&2, U32> & U32:
  (bytes, +n) = got
  (word_onto(a, word_onto(b, bytes)), (n + 1 : U32))

def start(rest: List<&2, U32>) -> Onto:
  Onto{rest, 0, 0, 0}

def put_word(+w: U32, o: Onto) -> Onto:
  match o:
    case Onto{bytes, +size, +entries, +items}:
      Onto{word_onto(w, bytes), (size + 4 : U32), entries, items}

def zeros_onto(n: Nat, rest: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      rest
    case 1n+p:
      zeros_onto(p, 0 <> rest)

def chars_onto(s: String, rest: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}:
      rest
    case SCon{Chr{b}, more}:
      b <> chars_onto(more, rest)

def put_string(+s: String, o: Onto) -> Onto:
  match o:
    case Onto{bytes, +size, +entries, +items}:
      +n = U32.from_nat(String.length(s))
      +padding = ((4 - (n .&. 3)) .&. 3 : U32)
      Onto{word_onto(n, chars_onto(s, zeros_onto(U32.to_nat(padding), bytes))), (size + 4 + n + padding : U32), entries, items}

def put_counted(got: List<&2, U32> & U32, +item_size: U32, +size: U32, +entries: U32, +items: U32) -> Onto:
  (bytes, +n) = got
  Onto{word_onto(n, bytes), (size + 4 + (n * item_size : U32) : U32), entries, (items + n : U32)}

def positions_onto(positions: List<&2, Position>, rest: List<&2, U32>) -> List<&2, U32> & U32:
  match positions:
    case Nil{}:
      (rest, 0)
    case Con{Position{xk, zk}, more}:
      counted_pair(xk, zk, positions_onto(more, rest))

def put_positions(positions: List<&2, Position>, o: Onto) -> Onto:
  match o:
    case Onto{bytes, +size, +entries, +items}:
      put_counted(positions_onto(positions, bytes), 8, size, entries, items)

def entry_added(o: Onto) -> Onto:
  match o:
    case Onto{bytes, +size, +entries, +items}:
      Onto{bytes, size, (entries + 1 : U32), items}

def entries_onto(~A: Data, ~entry: @item:A -> @after:Onto -> Onto, entries: List<&2, A>, after: Onto) -> Onto:
  match entries:
    case Nil{}:
      after
    case Con{item, more}:
      entry_added(entry(item, entries_onto(~A, ~entry, more, after)))

# A section with its tag, its size and its entry count before its entries.
def counted_section(+tag: U32, o: Onto) -> Onto:
  match o:
    case Onto{bytes, +size, +entries, +items}:
      Onto{word_onto(tag, word_onto((size + 4 : U32), word_onto(entries, bytes))), (size + 12 : U32), entries, items}

def onto_bytes(o: Onto) -> List<&2, U32>:
  match o:
    case Onto{bytes, _, _, _}:
      bytes

def tile_name_onto(n: TileName, after: Onto) -> Onto:
  match n:
    case TileName{id, name}:
      put_word(id, put_string(name, after))

# The TNAM section of these tile names, in the given order, before `rest`.
def tile_names_section(names: List<&2, TileName>, rest: List<&2, U32>) -> List<&2, U32>:
  onto_bytes(counted_section(1296125524, entries_onto(~TileName, ~tile_name_onto, names, start(rest))))

def tiles_onto(tiles: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32> & U32:
  match tiles:
    case Nil{}:
      (rest, 0)
    case Con{w, more}:
      counted_word(w, tiles_onto(more, rest))

def tiles_headed(got: List<&2, U32> & U32) -> List<&2, U32>:
  (bytes, +n) = got
  word_onto(1162627412, word_onto((n * 4 : U32), bytes))

# The TILE section of tiles packed two u16 per word (the first in the low half, a zero high half after an odd count),
# before `rest`.
def tiles_section(tiles: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  tiles_headed(tiles_onto(tiles, rest))

def prefab_onto(p: Prefab, after: Onto) -> Onto:
  match p:
    case Prefab{name, positions}:
      put_string(name, put_positions(positions, after))

def entities_onto(prefabs: List<&2, Prefab>, rest: List<&2, U32>) -> Onto:
  counted_section(1398033989, entries_onto(~Prefab, ~prefab_onto, prefabs, start(rest)))

# The ENTS section of these prefabs, in the given order, before `rest`.
def entities_section(prefabs: List<&2, Prefab>, rest: List<&2, U32>) -> List<&2, U32>:
  onto_bytes(entities_onto(prefabs, rest))

def link_onto(l: Link, after: Onto) -> Onto:
  match l:
    case Link{entry, exit}:
      put_word(entry, put_word(exit, after))

# The WORM section of these links, in the given order, before `rest`.
def links_section(links: List<&2, Link>, rest: List<&2, U32>) -> List<&2, U32>:
  onto_bytes(counted_section(1297239895, entries_onto(~Link, ~link_onto, links, start(rest))))

def pillar_onto(p: Pillar, after: Onto) -> Onto:
  match p:
    case Pillar{entry_prefab, entry, exit_prefab, exit}:
      put_word(entry_prefab, put_word(entry, put_word(exit_prefab, put_word(exit, after))))

# The PILL section of these tentacle pillar links, in the given order, before `rest`.
def pillars_section(pillars: List<&2, Pillar>, rest: List<&2, U32>) -> List<&2, U32>:
  onto_bytes(counted_section(1280067920, entries_onto(~Pillar, ~pillar_onto, pillars, start(rest))))

def optional_pillars(+shard: U32, pillars: List<&2, Pillar>, rest: List<&2, U32>) -> List<&2, U32>:
  match shard:
    case 1:
      pillars_section(pillars, rest)
    case _:
      rest

def members_onto(members: List<&2, Member>, rest: List<&2, U32>) -> List<&2, U32> & U32:
  match members:
    case Nil{}:
      (rest, 0)
    case Con{Member{prefab, index}, more}:
      counted_pair(prefab, index, members_onto(more, rest))

def put_members(members: List<&2, Member>, o: Onto) -> Onto:
  match o:
    case Onto{bytes, +size, +entries, +items}:
      put_counted(members_onto(members, bytes), 8, size, entries, items)

def piece_onto(p: Piece, after: Onto) -> Onto:
  match p:
    case Piece{name, source, turn, xk, zk, x0k, z0k, x1k, z1k, members}:
      put_string(name, put_word(source, put_word(turn, put_word(xk, put_word(zk, put_word(x0k, put_word(z0k, put_word(x1k, put_word(z1k,
        put_members(members, after))))))))))

# The SETP section of these set pieces, in the given order, before `rest`.
def set_pieces_section(pieces: List<&2, Piece>, rest: List<&2, U32>) -> List<&2, U32>:
  onto_bytes(counted_section(1347700051, entries_onto(~Piece, ~piece_onto, pieces, start(rest))))

def optional_set_pieces(pieces: Maybe<&2, List<&2, Piece>>, rest: List<&2, U32>) -> List<&2, U32>:
  match pieces:
    case None{}:
      rest
    case Some{found}:
      set_pieces_section(found, rest)

def planned_onto(p: Planned, after: Onto) -> Onto:
  match p:
    case Planned{task, piece, placed}:
      put_string(task, put_string(piece, put_word(Bool.to_u32(placed), after)))

# The PLAN section of this level plan, in plan order, before `rest`.
def plan_section(plan: List<&2, Planned>, rest: List<&2, U32>) -> List<&2, U32>:
  onto_bytes(counted_section(1312902224, entries_onto(~Planned, ~planned_onto, plan, start(rest))))

def optional_plan(plan: Maybe<&2, List<&2, Planned>>, rest: List<&2, U32>) -> List<&2, U32>:
  match plan:
    case None{}:
      rest
    case Some{found}:
      plan_section(found, rest)

def road_onto(r: Road, after: Onto) -> Onto:
  match r:
    case Road{weight, points}:
      put_word(weight, put_positions(points, after))

# The ROAD section of these roads, in the given order, before `rest`.
def roads_section(roads: List<&2, Road>, rest: List<&2, U32>) -> List<&2, U32>:
  onto_bytes(counted_section(1145130834, entries_onto(~Road, ~road_onto, roads, start(rest))))

def optional_roads(roads: Maybe<&2, List<&2, Road>>, rest: List<&2, U32>) -> List<&2, U32>:
  match roads:
    case None{}:
      rest
    case Some{found}:
      roads_section(found, rest)

def node_onto(n: Node, after: Onto) -> Onto:
  match n:
    case Node{id, kind, xk, zk}:
      put_string(id, put_word(kind, put_word(xk, put_word(zk, after))))

def edges_onto(edges: List<&2, Edge>, rest: List<&2, U32>) -> List<&2, U32> & U32:
  match edges:
    case Nil{}:
      (rest, 0)
    case Con{Edge{n1, n2}, more}:
      counted_pair(n1, n2, edges_onto(more, rest))

# The GRPH section of this topology, in its order, before `rest`.
def graph_section(g: Graph, rest: List<&2, U32>) -> List<&2, U32>:
  match g:
    case Graph{nodes, edges}:
      onto_bytes(counted_section(1213223495, entries_onto(~Node, ~node_onto, nodes, put_counted(edges_onto(edges, rest), 8, 0, 0, 0))))

def optional_graph(graph: Maybe<&2, Graph>, rest: List<&2, U32>) -> List<&2, U32>:
  match graph:
    case None{}:
      rest
    case Some{found}:
      graph_section(found, rest)

def headed(+seed: U32, +platform: U32, +shard: U32, +build: U32, +width: U32, +height: U32, tile_names: List<&2, TileName>, tiles: List<&2, U32>, ents: Onto) -> List<&2, U32> & U32:
  match ents:
    case Onto{bytes, _, _, +instances}:
      (words_onto([magic(), 3, seed, 1, platform, shard, build, width, height], tile_names_section(tile_names, tiles_section(tiles, bytes))), instances)

# A world dump's file bytes and its instance count (none when its world generation gave up): the header, then a
# generated world's TNAM, TILE, ENTS and WORM sections and, in the caves shard, its PILL section, and, when it has set
# pieces, its SETP section, when it has a level plan, its PLAN section, when it has roads, its ROAD section and, when it
# has a topology, its GRPH section.
def encoded(d: Dump) -> List<&2, U32> & U32:
  match d:
    case GaveUp{seed, platform, shard}:
      (words_onto([magic(), 3, seed, 0, platform, shard], Nil{}), 0)
    case Generated{seed, platform, +shard, build, width, height, tile_names, tiles, prefabs, links, pillars, pieces, plan, roads, graph}:
      headed(seed, platform, shard, build, width, height, tile_names, tiles, entities_onto(prefabs, links_section(links, optional_pillars(shard, pillars,
        optional_set_pieces(pieces, optional_plan(plan, optional_roads(roads, optional_graph(graph, Nil{}))))))))

def encoded_bytes(got: List<&2, U32> & U32) -> List<&2, U32>:
  (bytes, _) = got
  bytes

# A world dump's file bytes (encoded).
def bytes(d: Dump) -> List<&2, U32>:
  encoded_bytes(encoded(d))

# The prefabs of a dump (none when its world generation gave up).
def prefabs(+d: Dump) -> List<&2, Prefab>:
  match d:
    case Generated{_, _, _, _, _, _, _, _, +found, _, _, _, _, _, _}:
      found
    case GaveUp{_, _, _}:
      Nil{}

# The set pieces of a dump (none when it has no SETP section).
def set_pieces(+d: Dump) -> Maybe<&2, List<&2, Piece>>:
  match d:
    case Generated{_, _, _, _, _, _, _, _, _, _, _, +found, _, _, _}:
      found
    case GaveUp{_, _, _}:
      None{}

# The level plan of a dump (none when it has no PLAN section).
def plan(+d: Dump) -> Maybe<&2, List<&2, Planned>>:
  match d:
    case Generated{_, _, _, _, _, _, _, _, _, _, _, _, +found, _, _}:
      found
    case GaveUp{_, _, _}:
      None{}

# The roads of a dump (none when it has no ROAD section).
def roads(+d: Dump) -> Maybe<&2, List<&2, Road>>:
  match d:
    case Generated{_, _, _, _, _, _, _, _, _, _, _, _, _, +found, _}:
      found
    case GaveUp{_, _, _}:
      None{}

# The topology of a dump (none when it has no GRPH section).
def graph(+d: Dump) -> Maybe<&2, Graph>:
  match d:
    case Generated{_, _, _, _, _, _, _, _, _, _, _, _, _, _, +found}:
      found
    case GaveUp{_, _, _}:
      None{}
