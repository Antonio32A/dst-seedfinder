import Base
import ../rng/pcg.bend as Pcg
import ../lua/strhash.bend as StrHash
import ../lua/table.bend as LuaTable
import ../lua/sort.bend as LuaSort
import ../lua/math_random.bend as MathRandom
import ../lua/util.bend as LuaUtil
import ../stl/heap.bend as Heap
import ../stl/sort.bend as StlSort
import ../storygen/order.bend as StoryOrder
import ../storygen/mem.bend as StoryMem

# Lane S (story, Lua and data) laws. Each law is followed by its proof def of the same name, in this file.
# Rules: tiny U32 golden values, each probed alone first.
# Golden values: stock Lua 5.1.5, lua-dst, g++, the Windows game exe, C doubles.

law lua_strhash_short:
  {StrHash.hash_string("forest") == 2463871799 : U32}

def lua_strhash_short():
  {==}

law lua_strhash_long:
  {StrHash.hash_string("Speak to the king:BG_65:BGDeciduous") == 2317924953 : U32}

def lua_strhash_long():
  {==}

law lua_table_string_reinsert:
  {Pair.snd(LuaTable.Table, U32, LuaTable.fingerprint(LuaTable.set(LuaTable.remove(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.new(0, 0), LuaTable.string_key(1650982772, 0), 1), LuaTable.string_key(2464825061, 1), 2), LuaTable.string_key(7345781, 2), 3), LuaTable.string_key(311191059, 3), 4), LuaTable.string_key(2463871799, 4), 5), LuaTable.string_key(2464825061, 1)), LuaTable.string_key(2464825061, 1), 7))) == 1984421159 : U32}

def lua_table_string_reinsert():
  {==}

law lua_table_string_gc_reinsert:
  {Pair.snd(LuaTable.Table, U32, LuaTable.fingerprint(LuaTable.set(LuaTable.collect(LuaTable.remove(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.new(0, 0), LuaTable.string_key(1650982772, 0), 1), LuaTable.string_key(2464825061, 1), 2), LuaTable.string_key(7345781, 2), 3), LuaTable.string_key(311191059, 3), 4), LuaTable.string_key(2463871799, 4), 5), LuaTable.string_key(2464825061, 1))), LuaTable.string_key(2464825061, 1), 7))) == 2302288171 : U32}

def lua_table_string_gc_reinsert():
  {==}

law lua_table_numbers:
  {Pair.snd(LuaTable.Table, U32, LuaTable.fingerprint(LuaTable.set(LuaTable.set(LuaTable.remove(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.new(0, 0), LuaTable.int_key(1), 10), LuaTable.int_key(2), 20), LuaTable.int_key(3), 30), LuaTable.int_key(4), 40), LuaTable.int_key(5), 50), LuaTable.number_key(1071644672, 0), 7), LuaTable.int_key(3)), LuaTable.number_key(3220176896, 0), 8), LuaTable.int_key(100), 9))) == 102005494 : U32}

def lua_table_numbers():
  {==}

law lua_table_length:
  {Pair.snd(LuaTable.Table, U32, LuaTable.length(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.set(LuaTable.new(0, 0), LuaTable.int_key(1), 1), LuaTable.int_key(2), 2), LuaTable.int_key(4), 4), LuaTable.int_key(5), 5), LuaTable.int_key(6), 6))) == 6 : U32}

def lua_table_length():
  {==}

law lua_sort_ties:
  {LuaSort.fingerprint(LuaSort.sort(~Unit, ~Heap.key_less, Unit{}, Heap.from_list(4n, [0, 196608, 65537, 196610, 131075, 65540, 196613, 131078, 65543, 196616, 9]), 10, 0), 10) == 3876019456 : U32}

def lua_sort_ties():
  {==}

law stl_sort_libstdcxx:
  {Heap.work_fingerprint(StlSort.sort(~Unit, ~Heap.key_less, Unit{}, Heap.from_list(5n, [131072, 1, 65538, 131075, 131076, 5, 65542, 65543, 8, 131081, 65546, 11, 131084, 131085, 65550, 15, 16, 65553, 131090, 65555, 20, 131093, 65558, 23]), 0, 24), 0, 24) == 3943174043 : U32}

def stl_sort_libstdcxx():
  {==}

law stl_sort_msvc:
  {Heap.work_fingerprint(StlSort.msvc_sort(~Unit, ~Heap.key_less, Unit{}, Heap.from_list(6n, [0, 1, 131074, 65539, 65540, 196613, 196614, 65543, 8, 9, 131082, 131083, 12, 196621, 196622, 65551, 65552, 196625, 131090, 131091, 20, 21, 131094, 65559, 65560, 196633, 196634, 65563, 28, 29, 131102, 131103, 32, 196641, 196642, 65571, 65572, 196645, 131110, 131111, 40, 41, 131114, 65579, 65580]), 0, 45), 0, 45) == 712265201 : U32}

def stl_sort_msvc():
  {==}

law stl_heap_push_pop:
  {Heap.work_fingerprint(Heap.pop_work(~Unit, ~Heap.key_less, Heap.pop_work(~Unit, ~Heap.key_less, Heap.pop_work(~Unit, ~Heap.key_less, Heap.pop_work(~Unit, ~Heap.key_less, Heap.push_work(~Unit, ~Heap.key_less, Heap.push_work(~Unit, ~Heap.key_less, Heap.push_work(~Unit, ~Heap.key_less, Heap.push_work(~Unit, ~Heap.key_less, Heap.push_work(~Unit, ~Heap.key_less, Heap.push_work(~Unit, ~Heap.key_less, Heap.push_work(~Unit, ~Heap.key_less, Heap.push_work(~Unit, ~Heap.key_less, Heap.Work{Unit{}, Heap.from_list(3n, [327680, 65537, 327682, 196611, 65540, 262149, 327686, 131079])}, 0, 1), 0, 2), 0, 3), 0, 4), 0, 5), 0, 6), 0, 7), 0, 8), 0, 8), 0, 7), 0, 6), 0, 5), 0, 8) == 437835803 : U32}

def stl_heap_push_pop():
  {==}

law lua_math_random_scale:
  {MathRandom.floor_of(MathRandom.scale(2610666395, 51)) == 30 : U32}

def lua_math_random_scale():
  {==}

law lua_math_random_range:
  {Pair.fst(U32, Pcg.Rng, MathRandom.random_range(Pcg.srandom(1), 1, 51)) == 48 : U32}

def lua_math_random_range():
  {==}

law lua_util_shuffle:
  {Heap.fingerprint(LuaUtil.items_of(LuaUtil.shuffle_array(Heap.from_list(4n, [1, 2, 3, 4, 5, 6, 7, 8]), 8, Pcg.srandom(7))), 0, 8) == 2172912623 : U32}

def lua_util_shuffle():
  {==}

law storygen_table_order:
  {StoryOrder.order([StoryOrder.Slot{StrHash.hash_string("Make a pick:0:Clearing"), 1}, StoryOrder.Slot{StrHash.hash_string("Make a pick:1:Plain"), 2},
    StoryOrder.Slot{StrHash.hash_string("START"), 3}, StoryOrder.Slot{StrHash.hash_string("Make a pick:2:Forest"), 4},
    StoryOrder.Slot{StrHash.hash_string("Make a pick:BG_0:BGGrass"), 5}]) == [1, 2, 3, 5, 4] : List<&2, U32>}

def storygen_table_order():
  {==}

law storygen_unit_weight_exact:
  {StoryOrder.unit_weight_pick(1431655765, 3) == 0 : U32}

def storygen_unit_weight_exact():
  {==}

law storygen_unit_weight_half:
  {StoryOrder.unit_weight_pick(2147483648, 4) == 2 : U32}

def storygen_unit_weight_half():
  {==}

# M12: storygen's persistent array after word writes and a 32-word block write (the block replaces every word of its
# aligned range, here 1056..1087: 1057 comes from the block, 1070 is cleared, 2000 is outside and kept).
law storygen_mem_block:
  {(StoryMem.get(StoryMem.set_block(StoryMem.set(StoryMem.set(StoryMem.empty(), 2000, 7), 1070, 9), 1056, 5n, StoryMem.block(5n, [4, 5, 6])), 1057)
    + (StoryMem.get(StoryMem.set_block(StoryMem.set(StoryMem.set(StoryMem.empty(), 2000, 7), 1070, 9), 1056, 5n, StoryMem.block(5n, [4, 5, 6])), 1070) * 10)
    + (StoryMem.get(StoryMem.set_block(StoryMem.set(StoryMem.set(StoryMem.empty(), 2000, 7), 1070, 9), 1056, 5n, StoryMem.block(5n, [4, 5, 6])), 2000) * 100) : U32) == 705 : U32}

def storygen_mem_block():
  {==}
