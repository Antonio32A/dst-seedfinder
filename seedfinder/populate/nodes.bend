import Base
import ../lua/table.bend as LuaTable
import ../data/blob.bend as Blob
import ../data/strings.bend as Strings
import ../data/rooms.bend as Rooms
import ../data/populate.bend as PopulateData
import ../storygen/graph.bend as StoryGraph
import ../storygen/order.bend as StoryOrder

# The story nodes as the land population reads them: terrain_contents (room and deepcopy depth; the START node's
# AddStartingSetPiece changes), terrain_contents_extra (map tag items and static layouts), the set pieces inserted
# into countstaticlayouts, and the traversal orders of Graph:ConvertGround and Graph:PopulateVoronoi.

def none() -> U32:
  4294967295

def room(+s: StoryGraph.St, +n: U32) -> U32:
  StoryGraph.nf(s, n, StoryGraph.f_room())

def has_contents(+s: StoryGraph.St, +n: U32) -> Bool:
  Bool.not(U32.is_eq(room(s, n), none()))

def row(+s: StoryGraph.St, +n: U32) -> U32:
  Rooms.row_of(room(s, n), StoryGraph.nf(s, n, StoryGraph.f_depth()))

def is_start(+s: StoryGraph.St, +n: U32) -> Bool:
  U32.is_eq(StoryGraph.nf(s, n, StoryGraph.f_kind()), StoryGraph.id_start())

def tile(+s: StoryGraph.St, +n: U32) -> U32:
  StoryGraph.nf(s, n, StoryGraph.f_value())

def extra_kind(mine: Bool, +s: StoryGraph.St, +slot: U32, +tail: List<&2, U32>) -> List<&2, U32>:
  match mine:
    case True{}:
      StoryGraph.get(s, (slot + 2 : U32)) <> tail
    case False{}:
      tail

def extra_owned(owned: Bool, +s: StoryGraph.St, +slot: U32, +kind: U32, +tail: List<&2, U32>) -> List<&2, U32>:
  match owned:
    case True{}:
      extra_kind(U32.is_eq(StoryGraph.get(s, (slot + 1 : U32)), kind), s, slot, tail)
    case False{}:
      tail

def extras_loop(n: Nat, +s: StoryGraph.St, +node: U32, +kind: U32, +k: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +slot = (StoryGraph.extra_base() + (k * 3 : U32) : U32)
      extra_owned(U32.is_eq(StoryGraph.get(s, slot), node), s, slot, kind, extras_loop(p, s, node, kind, (k + 1 : U32)))

def extras(+s: StoryGraph.St, +node: U32, +kind: U32) -> List<&2, U32>:
  extras_loop(U32.to_nat(StoryGraph.get(s, StoryGraph.s_extras())), s, node, kind, 0)

# terrain_contents_extra.prefabs (ipairs order): prefab string ids.
def extra_prefabs(+s: StoryGraph.St, +node: U32) -> List<&2, U32>:
  extras(s, node, 3)

# terrain_contents_extra.static_layouts (insertion order): layout indices.
def extra_layouts(+s: StoryGraph.St, +node: U32) -> List<&2, U32>:
  extras(s, node, 4)

# One countstaticlayouts entry: key string id, value kind (0 integer, 1 closure) and value, layout index.
type Static is Data:
  Static{key: U32, kind: U32, value: U32, layout: U32}

def statics_of(n: Nat, +row: List<&2, U32>) -> List<&2, Static>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Static{Blob.at(row, 0), Blob.at(row, 1), Blob.at(row, 2), Blob.at(row, 3)} <> statics_of(p, Blob.drop(row, 4))

def base_statics(+row: U32) -> List<&2, Static>:
  +r = Rooms.room_countstaticlayouts(row)
  statics_of(Nat.div(List.length(&2, U32, r), 4n), r)

def piece_owned(owned: Bool, +s: StoryGraph.St, +slot: U32, +tail: List<&2, Static>) -> List<&2, Static>:
  match owned:
    case True{}:
      Static{StoryGraph.get(s, (slot + 1 : U32)), 0, 1, StoryGraph.get(s, (slot + 2 : U32))} <> tail
    case False{}:
      tail

def pieces_loop(n: Nat, +s: StoryGraph.St, +node: U32, +k: U32) -> List<&2, Static>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +slot = (StoryGraph.piece_base() + (k * 3 : U32) : U32)
      piece_owned(U32.is_eq(StoryGraph.get(s, slot), node), s, slot, pieces_loop(p, s, node, (k + 1 : U32)))

# The set pieces InsertAdditionalSetPieces put into the node's countstaticlayouts, in insertion order.
def pieces(+s: StoryGraph.St, +node: U32) -> List<&2, Static>:
  pieces_loop(U32.to_nat(StoryGraph.get(s, StoryGraph.s_pieces())), s, node, 0)

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

def layout_node(empty: Bool, nodes: Array<U32>, +row: List<&2, U32>, +entries: List<&2, Static>, +i: U32) -> Array<U32>:
  match empty:
    case True{}:
      nodes
    case False{}:
      +key = Blob.at(row, 0)
      LuaTable.write_node(nodes, i, LuaTable.Node{2, Strings.hash(key), key, next_field(Blob.at(row, 1)), Blob.at(row, 2), key_index(entries, False{}, key, 0)})

def layout_nodes(n: Nat, nodes: Array<U32>, +row: List<&2, U32>, +entries: List<&2, Static>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      nodes
    case 1n+p:
      layout_nodes(p, layout_node(Blob.is_none(Blob.at(row, 0)), nodes, row, entries, i), Blob.drop(row, 3), entries, (i + 1 : U32))

def from_layout(+row: List<&2, U32>, +entries: List<&2, Static>) -> LuaTable.Table:
  +lsize = Blob.at(row, 0)
  +asize = Blob.at(row, 2)
  nodes = layout_nodes(U32.to_nat(LuaTable.shl(1, lsize)), LuaTable.empty_nodes(lsize), Blob.drop(row, 4), entries, 0)
  LuaTable.Table{nodes, LuaTable.new_cells(LuaTable.cell_capacity(asize)), lsize, U32.is_eq(Blob.at(row, 3), 1), asize, LuaTable.cell_capacity(asize), Blob.at(row, 1)}

def base_table(empty: Bool, +row: U32, +entries: List<&2, Static>) -> LuaTable.Table:
  match empty:
    case True{}:
      LuaTable.new(0, 0)
    case False{}:
      from_layout(Rooms.room_countstaticlayouts_layout(row), entries)

def inserted(ps: List<&2, Static>, t: LuaTable.Table, +i: U32) -> LuaTable.Table:
  match ps:
    case Nil{}:
      t
    case Con{Static{+key, _, _, _}, rest}:
      inserted(rest, LuaTable.set(t, LuaTable.string_key(Strings.hash(key), key), i), (i + 1 : U32))

def entry_of(+all: List<&2, Static>, +i: U32) -> Static:
  Maybe.default(&2, Static, List.get(&2, Static, all, U32.to_nat(i)), Static{0, 0, 0, 0})

def entries_of(vs: List<&2, U32>, +all: List<&2, Static>) -> List<&2, Static>:
  match vs:
    case Nil{}:
      Nil{}
    case Con{+v, rest}:
      entry_of(all, v) <> entries_of(rest, all)

def with_pieces(+base: List<&2, Static>, +ps: List<&2, Static>, +row: U32) -> List<&2, Static>:
  +m = U32.from_nat(List.length(&2, Static, base))
  t = inserted(ps, base_table(List.is_empty(&2, Static, base), row, base), m)
  entries_of(StoryOrder.values_only(StoryOrder.values(t)), List.append(&2, Static, base, ps))

def plain_or_pieces(plain: Bool, +base: List<&2, Static>, +ps: List<&2, Static>, +row: U32) -> List<&2, Static>:
  match plain:
    case True{}:
      base
    case False{}:
      with_pieces(base, ps, row)

def start_statics() -> List<&2, Static>:
  [Static{PopulateData.start_key(), 0, 1, PopulateData.start_layout()}]

def start_with(+ps: List<&2, Static>) -> List<&2, Static>:
  t = inserted(ps, inserted(start_statics(), LuaTable.new(0, 0), 0), 1)
  entries_of(StoryOrder.values_only(StoryOrder.values(t)), List.append(&2, Static, start_statics(), ps))

def statics_of_node(start: Bool, +s: StoryGraph.St, +node: U32, +ps: List<&2, Static>) -> List<&2, Static>:
  match start:
    case True{}:
      start_with(ps)
    case False{}:
      plain_or_pieces(List.is_empty(&2, Static, ps), base_statics(row(s, node)), ps, row(s, node))

# pairs(terrain_contents.countstaticlayouts) of a node with contents (AddStartingSetPiece's fresh table on START).
def statics(+s: StoryGraph.St, +node: U32) -> List<&2, Static>:
  statics_of_node(is_start(s, node), s, node, pieces(s, node))

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

def counts_for(start: Bool, +all: List<&2, Count>) -> List<&2, Count>:
  match start:
    case True{}:
      keyed(Rooms.start_countprefabs(0), all)
    case False{}:
      all

# pairs(terrain_contents.countprefabs) (the START node without spawnpoint).
def countprefabs(+s: StoryGraph.St, +node: U32) -> List<&2, Count>:
  counts_for(is_start(s, node), triples(Rooms.room_countprefabs(row(s, node))))

def order_for(start: Bool, +s: StoryGraph.St, +node: U32) -> List<&2, U32>:
  match start:
    case True{}:
      Rooms.start_countprefabs(1)
    case False{}:
      Rooms.room_generate_order(row(s, node))

# pairs(generate_these): the countprefabs keys in PopulateVoronoi's placement order.
def generate_order(+s: StoryGraph.St, +node: U32) -> List<&2, U32>:
  order_for(is_start(s, node), s, node)

def has_countprefabs(+s: StoryGraph.St, +node: U32) -> Bool:
  Rooms.has(room(s, node), Rooms.flag_countprefabs())

def has_distribute(+s: StoryGraph.St, +node: U32) -> Bool:
  Rooms.has(room(s, node), Rooms.flag_distributeprefabs())

def has_distribute_percent(+s: StoryGraph.St, +node: U32) -> Bool:
  Rooms.has(room(s, node), Rooms.flag_distribute_percent())

# terrain_contents.prefabdata entries.
def prefabdata(+s: StoryGraph.St, +node: U32) -> List<&2, Count>:
  triples(Rooms.room_prefabdata(row(s, node)))

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
