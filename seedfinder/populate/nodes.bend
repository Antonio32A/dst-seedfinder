import Base
import ../lua/table.bend as LuaTable
import ../data/blob.bend as Blob
import ../data/strings.bend as Strings
import ../data/rooms.bend as Rooms
import ../data/populate.bend as PopulateData
import ../data/layouts.bend as Layouts
import ../data/cave_story.bend as CaveStory
import ./names.bend as PopulateNames
import ../data/cave_catalog.bend as CaveCatalog
import ../storygen/graph.bend as StoryGraph
import ../storygen/order.bend as StoryOrder
import ../storygen/catalog.bend as StoryCatalog
import ../storygen/setpieces.bend as StorySetpieces
import ../data/builds.bend as Builds

# The story nodes as the land population reads them: terrain_contents (room and deepcopy depth; the START node's
# AddStartingSetPiece changes), terrain_contents_extra (map tag items and static layouts), the set pieces inserted
# into countstaticlayouts, and the traversal orders of Graph:ConvertGround and Graph:PopulateVoronoi.

def none() -> U32:
  4294967295

def is_cave_room(+stored: U32) -> Bool:
  U32.is_ne(stored, none()) && StoryCatalog.is_cave_room(stored)

def global_room(+build: Builds.Build, caves: Bool, +stored: U32) -> U32:
  match caves:
    case True{}:
      Rooms.from_cave_room(build, StoryCatalog.cave_room(stored))
    case False{}:
      stored

# The room row of data/rooms.bend of a node (a caves story stores cave-local room ids).
def room(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> U32:
  +stored = StoryGraph.nf(s, n, StoryGraph.f_room())
  global_room(build, is_cave_room(stored), stored)

def is_caves(+s: StoryGraph.St, +n: U32) -> Bool:
  is_cave_room(StoryGraph.nf(s, n, StoryGraph.f_room()))

def has_contents(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> Bool:
  Bool.not(U32.is_eq(room(build, s, n), none()))

def row(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> U32:
  Rooms.row_of(build, room(build, s, n), StoryGraph.nf(s, n, StoryGraph.f_depth()))

def is_start(+s: StoryGraph.St, +n: U32) -> Bool:
  U32.is_eq(StoryGraph.nf(s, n, StoryGraph.f_kind()), StoryGraph.id_start())

def is_forest_start(+s: StoryGraph.St, +n: U32) -> Bool:
  is_start(s, n) && Bool.not(is_caves(s, n))

def tile(+s: StoryGraph.St, +n: U32) -> U32:
  StoryGraph.nf(s, n, StoryGraph.f_value())

# A set piece slot (owner node, name, layout) or an extra slot (owner node, kind, value) of the story.
type Slot is Data:
  Slot{owner: U32, a: U32, b: U32}

# The story's set piece and extra slots, read once for the land population.
type Slots is Data:
  Slots{pieces: List<&2, Slot>, extras: List<&2, Slot>}

def slot_list(n: Nat, +s: StoryGraph.St, +base: U32, +k: U32) -> List<&2, Slot>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +slot = (base + (k * 3 : U32) : U32)
      Slot{StoryGraph.get(s, slot), StoryGraph.get(s, (slot + 1 : U32)), StoryGraph.get(s, (slot + 2 : U32))} <> slot_list(p, s, base, (k + 1 : U32))

def slots(+s: StoryGraph.St) -> Slots:
  Slots{slot_list(U32.to_nat(StoryGraph.get(s, StoryGraph.s_pieces())), s, StoryGraph.piece_base(), 0),
    slot_list(U32.to_nat(StoryGraph.get(s, StoryGraph.s_extras())), s, StoryGraph.extra_base(), 0)}

def extra_slot(mine: Bool, +value: U32, +tail: List<&2, U32>) -> List<&2, U32>:
  match mine:
    case True{}:
      value <> tail
    case False{}:
      tail

def extras_in(xs: List<&2, Slot>, +node: U32, +kind: U32) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Slot{+owner, +k, +value}, rest}:
      extra_slot(U32.is_eq(owner, node) && U32.is_eq(k, kind), value, extras_in(rest, node, kind))

def extras(+sl: Slots, +node: U32, +kind: U32) -> List<&2, U32>:
  match sl:
    case Slots{_, +xs}:
      extras_in(xs, node, kind)

def cave_tag_prefabs(+build: Builds.Build, tags: List<&2, U32>) -> List<&2, U32>:
  match tags:
    case Nil{}:
      Nil{}
    case Con{+tag, rest}:
      PopulateNames.string_id(build, CaveStory.tag_value(build, tag)) <> cave_tag_prefabs(build, rest)

def tag_items(+build: Builds.Build, caves: Bool, items: List<&2, U32>) -> List<&2, U32>:
  match caves:
    case True{}:
      cave_tag_prefabs(build, items)
    case False{}:
      items

# terrain_contents_extra.prefabs (ipairs order): prefab string ids (a caves story records the map tag, whose item is the
# tag's value).
def extra_prefabs(+build: Builds.Build, +s: StoryGraph.St, +sl: Slots, +node: U32) -> List<&2, U32>:
  tag_items(build, is_caves(s, node), extras(sl, node, 3))

# terrain_contents_extra.static_layouts (insertion order): layout indices.
def extra_layouts(+sl: Slots, +node: U32) -> List<&2, U32>:
  extras(sl, node, 4)

# One countstaticlayouts entry: key string id, value kind (0 integer, 1 closure) and value, layout index.
type Static is Data:
  Static{key: U32, kind: U32, value: U32, layout: U32}

def statics_of(n: Nat, +row: List<&2, U32>) -> List<&2, Static>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Static{Blob.at(row, 0), Blob.at(row, 1), Blob.at(row, 2), Blob.at(row, 3)} <> statics_of(p, Blob.drop(row, 4))

def base_statics(+build: Builds.Build, +row: U32) -> List<&2, Static>:
  +r = Rooms.room_countstaticlayouts(build, row)
  statics_of(Nat.div(List.length(&2, U32, r), 4n), r)

def cave_layout_scan(+build: Builds.Build, n: Nat, +l: U32, +hash: U32) -> U32:
  match n:
    case 0n:
      none()
    case 1n+p:
      Bool.pick(U32, U32.is_eq(Strings.hash(build, Layouts.name(build, Layouts.variant(build, l, 0))), hash), l, cave_layout_scan(build, p, (l + 1 : U32), hash))

def named_layout(+build: Builds.Build, +layout: U32) -> Static:
  Static{Layouts.name(build, Layouts.variant(build, layout, 0)), 0, 1, layout}

def piece_static(+build: Builds.Build, resolved: Bool, +name: U32, +layout: U32) -> Static:
  match resolved:
    case True{}:
      Static{name, 0, 1, layout}
    case False{}:
      named_layout(build, cave_layout_scan(build, U32.to_nat(Layouts.layout_count(build)), 0, CaveCatalog.key_hash(build, name)))

def piece_slot(+build: Builds.Build, owned: Bool, +name: U32, +layout: U32, +tail: List<&2, Static>) -> List<&2, Static>:
  match owned:
    case True{}:
      piece_static(build, U32.is_ne(layout, StorySetpieces.cave_layout_unresolved()), name, layout) <> tail
    case False{}:
      tail

def pieces_in(+build: Builds.Build, xs: List<&2, Slot>, +node: U32) -> List<&2, Static>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Slot{+owner, +name, +layout}, rest}:
      piece_slot(build, U32.is_eq(owner, node), name, layout, pieces_in(build, rest, node))

# The set pieces InsertAdditionalSetPieces put into the node's countstaticlayouts, in insertion order.
def pieces(+build: Builds.Build, +sl: Slots, +node: U32) -> List<&2, Static>:
  match sl:
    case Slots{+xs, _}:
      pieces_in(build, xs, node)

def key_index(xs: List<&2, Static>, found: Bool, +key: U32, +i: U32) -> U32:
  match xs:
    case Nil{}:
      Bool.pick(U32, found, (i - 1 : U32), none())
    case Con{Static{+k, _, _, _}, rest}:
      match found:
        case True{}:
          (i - 1 : U32)
        case False{}:
          key_index(rest, U32.is_eq(k, key), key, (i + 1 : U32))

def next_field(+v: U32) -> U32:
  Bool.pick(U32, Blob.is_none(v), 0, (v + 1 : U32))

def layout_node(+build: Builds.Build, empty: Bool, nodes: Array<U32>, +row: List<&2, U32>, +entries: List<&2, Static>, +i: U32) -> Array<U32>:
  match empty:
    case True{}:
      nodes
    case False{}:
      +key = Blob.at(row, 0)
      LuaTable.write_node(nodes, i, LuaTable.Node{2, Strings.hash(build, key), key, next_field(Blob.at(row, 1)), Blob.at(row, 2), key_index(entries, False{}, key, 0)})

def layout_nodes(+build: Builds.Build, n: Nat, nodes: Array<U32>, +row: List<&2, U32>, +entries: List<&2, Static>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      nodes
    case 1n+p:
      layout_nodes(build, p, layout_node(build, Blob.is_none(Blob.at(row, 0)), nodes, row, entries, i), Blob.drop(row, 3), entries, (i + 1 : U32))

def from_layout(+build: Builds.Build, +row: List<&2, U32>, +entries: List<&2, Static>) -> LuaTable.Table:
  +lsize = Blob.at(row, 0)
  +asize = Blob.at(row, 2)
  nodes = layout_nodes(build, U32.to_nat(LuaTable.shl(1, lsize)), LuaTable.empty_nodes(lsize), Blob.drop(row, 4), entries, 0)
  LuaTable.Table{nodes, LuaTable.new_cells(LuaTable.cell_capacity(asize)), lsize, U32.is_eq(Blob.at(row, 3), 1), asize, LuaTable.cell_capacity(asize), Blob.at(row, 1)}

def base_table(+build: Builds.Build, empty: Bool, +row: U32, +entries: List<&2, Static>) -> LuaTable.Table:
  match empty:
    case True{}:
      LuaTable.new(0, 0)
    case False{}:
      from_layout(build, Rooms.room_countstaticlayouts_layout(build, row), entries)

def inserted(+build: Builds.Build, ps: List<&2, Static>, t: LuaTable.Table, +i: U32) -> LuaTable.Table:
  match ps:
    case Nil{}:
      t
    case Con{Static{+key, _, _, _}, rest}:
      inserted(build, rest, LuaTable.set(t, LuaTable.string_key(Strings.hash(build, key), key), i), (i + 1 : U32))

def entry_of(+all: List<&2, Static>, +i: U32) -> Static:
  Maybe.default(&2, Static, List.get(&2, Static, all, U32.to_nat(i)), Static{0, 0, 0, 0})

def entries_of(vs: List<&2, U32>, +all: List<&2, Static>) -> List<&2, Static>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+v, rest}:
      entry_of(all, v) <> entries_of(rest, all)

def with_pieces(+build: Builds.Build, +base: List<&2, Static>, +ps: List<&2, Static>, +row: U32) -> List<&2, Static>:
  +m = U32.from_nat(List.length(&2, Static, base))
  t = inserted(build, ps, base_table(build, List.is_empty(&2, Static, base), row, base), m)
  entries_of(StoryOrder.values_only(StoryOrder.values(t)), List.append(&2, Static, base, ps))

def plain_or_pieces(+build: Builds.Build, plain: Bool, +base: List<&2, Static>, +ps: List<&2, Static>, +row: U32) -> List<&2, Static>:
  match plain:
    case True{}:
      base
    case False{}:
      with_pieces(build, base, ps, row)

def start_key_of(+build: Builds.Build, caves: Bool) -> U32:
  Bool.pick(U32, caves, PopulateData.cave_start_key(build), PopulateData.start_key(build))

def start_layout_of(+build: Builds.Build, caves: Bool) -> U32:
  Bool.pick(U32, caves, PopulateData.cave_start_layout(build), PopulateData.start_layout(build))

# The string id of the START node's starting set piece.
def start_key(+build: Builds.Build, +s: StoryGraph.St, +n: U32) -> U32:
  start_key_of(build, is_caves(s, n))

def start_statics(+build: Builds.Build, +caves: Bool) -> List<&2, Static>:
  [Static{start_key_of(build, caves), 0, 1, start_layout_of(build, caves)}]

def start_with(+build: Builds.Build, +caves: Bool, +ps: List<&2, Static>) -> List<&2, Static>:
  t = inserted(build, ps, inserted(build, start_statics(build, caves), LuaTable.new(0, 0), 0), 1)
  entries_of(StoryOrder.values_only(StoryOrder.values(t)), List.append(&2, Static, start_statics(build, caves), ps))

def statics_of_node(+build: Builds.Build, start: Bool, +s: StoryGraph.St, +node: U32, +ps: List<&2, Static>) -> List<&2, Static>:
  match start:
    case True{}:
      start_with(build, is_caves(s, node), ps)
    case False{}:
      plain_or_pieces(build, List.is_empty(&2, Static, ps), base_statics(build, row(build, s, node)), ps, row(build, s, node))

# pairs(terrain_contents.countstaticlayouts) of a node with contents (AddStartingSetPiece's fresh table on START).
def statics(+build: Builds.Build, +s: StoryGraph.St, +sl: Slots, +node: U32) -> List<&2, Static>:
  statics_of_node(build, is_start(s, node), s, node, pieces(build, sl, node))

# One countprefabs / prefabdata entry: key string id, value kind and value.
type Count is Data:
  Count{key: U32, kind: U32, value: U32}

def counts_of(n: Nat, +r: List<&2, U32>) -> List<&2, Count>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Count{Blob.at(r, 0), Blob.at(r, 1), Blob.at(r, 2)} <> counts_of(p, Blob.drop(r, 3))

def triples(+r: List<&2, U32>) -> List<&2, Count>:
  counts_of(Nat.div(List.length(&2, U32, r), 3n), r)

def count_for(xs: List<&2, Count>, found: Bool, +key: U32, +c: Count) -> Count:
  match xs:
    case Nil{}:
      Bool.pick(Count, found, c, Count{key, 0, 0})
    case Con{Count{+k, +kind, +v}, rest}:
      match found:
        case True{}:
          c
        case False{}:
          count_for(rest, U32.is_eq(k, key), key, Count{k, kind, v})

def keyed(keys: List<&2, U32>, +all: List<&2, Count>) -> List<&2, Count>:
  match keys:
    case Nil{}:
      Nil{}
    case Con{+k, rest}:
      count_for(all, False{}, k, Count{k, 0, 0}) <> keyed(rest, all)

def counts_for(+build: Builds.Build, start: Bool, +all: List<&2, Count>) -> List<&2, Count>:
  match start:
    case True{}:
      keyed(Rooms.start_countprefabs(build, 0), all)
    case False{}:
      all

# pairs(terrain_contents.countprefabs) (the START node without spawnpoint).
def countprefabs(+build: Builds.Build, +s: StoryGraph.St, +node: U32) -> List<&2, Count>:
  counts_for(build, is_forest_start(s, node), triples(Rooms.room_countprefabs(build, row(build, s, node))))

def order_for(+build: Builds.Build, start: Bool, +s: StoryGraph.St, +node: U32) -> List<&2, U32>:
  match start:
    case True{}:
      Rooms.start_countprefabs(build, 1)
    case False{}:
      Rooms.room_generate_order(build, row(build, s, node))

# pairs(generate_these): the countprefabs keys in PopulateVoronoi's placement order.
def generate_order(+build: Builds.Build, +s: StoryGraph.St, +node: U32) -> List<&2, U32>:
  order_for(build, is_forest_start(s, node), s, node)

# Whether the room's custom tile function ran (Node.populated): PopulateVoronoi skips the node.
def has_custom_tiles(+build: Builds.Build, +s: StoryGraph.St, +node: U32) -> Bool:
  Rooms.has(build, room(build, s, node), Rooms.flag_custom_tiles(build))

def has_countprefabs(+build: Builds.Build, +s: StoryGraph.St, +node: U32) -> Bool:
  Rooms.has(build, room(build, s, node), Rooms.flag_countprefabs(build))

def has_distribute(+build: Builds.Build, +s: StoryGraph.St, +node: U32) -> Bool:
  Rooms.has(build, room(build, s, node), Rooms.flag_distributeprefabs(build))

def has_distribute_percent(+build: Builds.Build, +s: StoryGraph.St, +node: U32) -> Bool:
  Rooms.has(build, room(build, s, node), Rooms.flag_distribute_percent(build))

# terrain_contents.prefabdata entries.
def prefabdata(+build: Builds.Build, +s: StoryGraph.St, +node: U32) -> List<&2, Count>:
  triples(Rooms.room_prefabdata(build, row(build, s, node)))

def graph_nodes(gs: List<&2, U32>, +s: StoryGraph.St) -> List<&2, U32>:
  match gs:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      List.append(&2, U32, StoryGraph.copy_order(s, g), graph_nodes(rest, s))

# Graph:PopulateVoronoi's node order: pairs(root.children), then pairs(child:GetNodes(false)) of each.
def populate_order(+s: StoryGraph.St) -> List<&2, U32>:
  graph_nodes(StoryGraph.children_order(s), s)

# Graph:ConvertGround's node order: pairs(root:GetNodes(true)), the table merged from every child's copy.
def convert_order(+s: StoryGraph.St) -> List<&2, U32>:
  StoryGraph.node_table_order(s, populate_order(s))
