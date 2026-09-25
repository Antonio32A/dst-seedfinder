import Base
import ../lua/table.bend as LT
import ../data/blob.bend as B
import ../data/strings.bend as ST
import ../data/rooms.bend as RM
import ../data/populate.bend as PD
import ../storygen/graph.bend as GG
import ../storygen/order.bend as GO

# The story nodes as the land population reads them: terrain_contents (room and deepcopy depth; the START node's
# AddStartingSetPiece changes), terrain_contents_extra (map tag items and static layouts), the set pieces inserted
# into countstaticlayouts, and the traversal orders of Graph:ConvertGround and Graph:PopulateVoronoi.

def none() -> U32:
  4294967295

def room(+s: GG.St, +n: U32) -> U32:
  GG.nf(s, n, GG.f_room())

def has_contents(+s: GG.St, +n: U32) -> Bool:
  Bool.not(U32.is_eq(room(s, n), none()))

def row(+s: GG.St, +n: U32) -> U32:
  RM.row_of(room(s, n), GG.nf(s, n, GG.f_depth()))

def is_start(+s: GG.St, +n: U32) -> Bool:
  U32.is_eq(GG.nf(s, n, GG.f_kind()), GG.id_start())

def tile(+s: GG.St, +n: U32) -> U32:
  GG.nf(s, n, GG.f_value())

def extra_kind(mine: Bool, +s: GG.St, +slot: U32, +tail: List<&2, U32>) -> List<&2, U32>:
  match mine:
    case True{}:
      GG.get(s, (slot + 2 : U32)) <> tail
    case False{}:
      tail

def extra_owned(owned: Bool, +s: GG.St, +slot: U32, +kind: U32, +tail: List<&2, U32>) -> List<&2, U32>:
  match owned:
    case True{}:
      extra_kind(U32.is_eq(GG.get(s, (slot + 1 : U32)), kind), s, slot, tail)
    case False{}:
      tail

def extras_loop(n: Nat, +s: GG.St, +node: U32, +kind: U32, +k: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +slot = (GG.extra_base() + (k * 3 : U32) : U32)
      extra_owned(U32.is_eq(GG.get(s, slot), node), s, slot, kind, extras_loop(p, s, node, kind, (k + 1 : U32)))

def extras(+s: GG.St, +node: U32, +kind: U32) -> List<&2, U32>:
  extras_loop(U32.to_nat(GG.get(s, GG.s_extras())), s, node, kind, 0)

# terrain_contents_extra.prefabs (ipairs order): prefab string ids.
def extra_prefabs(+s: GG.St, +node: U32) -> List<&2, U32>:
  extras(s, node, 3)

# terrain_contents_extra.static_layouts (insertion order): layout indices.
def extra_layouts(+s: GG.St, +node: U32) -> List<&2, U32>:
  extras(s, node, 4)

# One countstaticlayouts entry: key string id, value kind (0 integer, 1 closure) and value, layout index.
type Static is Data:
  Static{key: U32, kind: U32, value: U32, layout: U32}

def statics_of(n: Nat, +row: List<&2, U32>) -> List<&2, Static>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Static{B.at(row, 0), B.at(row, 1), B.at(row, 2), B.at(row, 3)} <> statics_of(p, B.drop(row, 4))

def base_statics(+row: U32) -> List<&2, Static>:
  +r = RM.room_countstaticlayouts(row)
  statics_of(Nat.div(List.length(&2, U32, r), 4n), r)

def piece_owned(owned: Bool, +s: GG.St, +slot: U32, +tail: List<&2, Static>) -> List<&2, Static>:
  match owned:
    case True{}:
      Static{GG.get(s, (slot + 1 : U32)), 0, 1, GG.get(s, (slot + 2 : U32))} <> tail
    case False{}:
      tail

def pieces_loop(n: Nat, +s: GG.St, +node: U32, +k: U32) -> List<&2, Static>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +slot = (GG.piece_base() + (k * 3 : U32) : U32)
      piece_owned(U32.is_eq(GG.get(s, slot), node), s, slot, pieces_loop(p, s, node, (k + 1 : U32)))

# The set pieces InsertAdditionalSetPieces put into the node's countstaticlayouts, in insertion order.
def pieces(+s: GG.St, +node: U32) -> List<&2, Static>:
  pieces_loop(U32.to_nat(GG.get(s, GG.s_pieces())), s, node, 0)

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
  Bool.pick(U32, B.is_none(v), 0, (v + 1 : U32))

def layout_node(empty: Bool, nodes: Array<U32>, +row: List<&2, U32>, +entries: List<&2, Static>, +i: U32) -> Array<U32>:
  match empty:
    case True{}:
      nodes
    case False{}:
      +key = B.at(row, 0)
      LT.write_node(nodes, i, LT.Node{2, ST.hash(key), key, next_field(B.at(row, 1)), B.at(row, 2), key_index(entries, False{}, key, 0)})

def layout_nodes(n: Nat, nodes: Array<U32>, +row: List<&2, U32>, +entries: List<&2, Static>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      nodes
    case 1n+p:
      layout_nodes(p, layout_node(B.is_none(B.at(row, 0)), nodes, row, entries, i), B.drop(row, 3), entries, (i + 1 : U32))

def from_layout(+row: List<&2, U32>, +entries: List<&2, Static>) -> LT.Table:
  +lsize = B.at(row, 0)
  +asize = B.at(row, 2)
  nodes = layout_nodes(U32.to_nat(LT.shl(1, lsize)), LT.empty_nodes(lsize), B.drop(row, 4), entries, 0)
  LT.Table{nodes, LT.new_cells(LT.cell_capacity(asize)), lsize, U32.is_eq(B.at(row, 3), 1), asize, LT.cell_capacity(asize), B.at(row, 1)}

def base_table(empty: Bool, +row: U32, +entries: List<&2, Static>) -> LT.Table:
  match empty:
    case True{}:
      LT.new(0, 0)
    case False{}:
      from_layout(RM.room_countstaticlayouts_layout(row), entries)

def inserted(ps: List<&2, Static>, t: LT.Table, +i: U32) -> LT.Table:
  match ps:
    case Nil{}:
      t
    case Con{Static{+key, _, _, _}, rest}:
      inserted(rest, LT.set(t, LT.string_key(ST.hash(key), key), i), (i + 1 : U32))

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
  entries_of(GO.values_only(GO.values(t)), List.append(&2, Static, base, ps))

def plain_or_pieces(plain: Bool, +base: List<&2, Static>, +ps: List<&2, Static>, +row: U32) -> List<&2, Static>:
  match plain:
    case True{}:
      base
    case False{}:
      with_pieces(base, ps, row)

def start_statics() -> List<&2, Static>:
  [Static{PD.start_key(), 0, 1, PD.start_layout()}]

def start_with(+ps: List<&2, Static>) -> List<&2, Static>:
  t = inserted(ps, inserted(start_statics(), LT.new(0, 0), 0), 1)
  entries_of(GO.values_only(GO.values(t)), List.append(&2, Static, start_statics(), ps))

def statics_of_node(start: Bool, +s: GG.St, +node: U32, +ps: List<&2, Static>) -> List<&2, Static>:
  match start:
    case True{}:
      start_with(ps)
    case False{}:
      plain_or_pieces(List.is_empty(&2, Static, ps), base_statics(row(s, node)), ps, row(s, node))

# pairs(terrain_contents.countstaticlayouts) of a node with contents (AddStartingSetPiece's fresh table on START).
def statics(+s: GG.St, +node: U32) -> List<&2, Static>:
  statics_of_node(is_start(s, node), s, node, pieces(s, node))

# One countprefabs / prefabdata entry: key string id, value kind and value.
type Count is Data:
  Count{key: U32, kind: U32, value: U32}

def counts_of(n: Nat, +r: List<&2, U32>) -> List<&2, Count>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Count{B.at(r, 0), B.at(r, 1), B.at(r, 2)} <> counts_of(p, B.drop(r, 3))

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
      keyed(RM.start_countprefabs(0), all)
    case False{}:
      all

# pairs(terrain_contents.countprefabs) (the START node without spawnpoint).
def countprefabs(+s: GG.St, +node: U32) -> List<&2, Count>:
  counts_for(is_start(s, node), triples(RM.room_countprefabs(row(s, node))))

def order_for(start: Bool, +s: GG.St, +node: U32) -> List<&2, U32>:
  match start:
    case True{}:
      RM.start_countprefabs(1)
    case False{}:
      RM.room_generate_order(row(s, node))

# pairs(generate_these): the countprefabs keys in PopulateVoronoi's placement order.
def generate_order(+s: GG.St, +node: U32) -> List<&2, U32>:
  order_for(is_start(s, node), s, node)

def has_countprefabs(+s: GG.St, +node: U32) -> Bool:
  RM.has(room(s, node), RM.flag_countprefabs())

def has_distribute(+s: GG.St, +node: U32) -> Bool:
  RM.has(room(s, node), RM.flag_distributeprefabs())

def has_distribute_percent(+s: GG.St, +node: U32) -> Bool:
  RM.has(room(s, node), RM.flag_distribute_percent())

# terrain_contents.prefabdata entries.
def prefabdata(+s: GG.St, +node: U32) -> List<&2, Count>:
  triples(RM.room_prefabdata(row(s, node)))

def graph_nodes(gs: List<&2, U32>, +s: GG.St) -> List<&2, U32>:
  match gs:
    case Nil{}:
      Nil{}
    case Con{+g, rest}:
      List.append(&2, U32, GG.copy_order(s, g), graph_nodes(rest, s))

# Graph:PopulateVoronoi's node order: pairs(root.children), then pairs(child:GetNodes(false)) of each.
def populate_order(+s: GG.St) -> List<&2, U32>:
  graph_nodes(GG.children_order(s), s)

# Graph:ConvertGround's node order: pairs(root:GetNodes(true)), the table merged from every child's copy.
def convert_order(+s: GG.St) -> List<&2, U32>:
  GG.node_table_order(s, populate_order(s))
