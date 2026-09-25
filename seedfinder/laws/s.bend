import Base
import ../rng/pcg.bend as R
import ../lua/strhash.bend as LS
import ../lua/table.bend as LT
import ../lua/sort.bend as LO
import ../lua/math_random.bend as LM
import ../lua/util.bend as LU
import ../stl/heap.bend as SH
import ../stl/sort.bend as SS
import ../storygen/order.bend as GO
import ../storygen/mem.bend as SM

# Lane S (story, Lua and data) laws. Each law is followed by its proof def of the same name, in this file.
# Rules: .scratch/port/CONVENTIONS.md "Laws" (tiny U32 golden values, each probed alone first).
# Golden values: .scratch/port/test/law_goldens.py (stock Lua 5.1.5, lua-dst, g++, the Windows game exe, C doubles).

law lua_strhash_short:
  {LS.hash_string("forest") == 2463871799 : U32}

def lua_strhash_short():
  {==}

law lua_strhash_long:
  {LS.hash_string("Speak to the king:BG_65:BGDeciduous") == 2317924953 : U32}

def lua_strhash_long():
  {==}

law lua_table_string_reinsert:
  {Pair.snd(LT.Table, U32, LT.fingerprint(LT.set(LT.remove(LT.set(LT.set(LT.set(LT.set(LT.set(LT.new(0, 0), LT.string_key(1650982772, 0), 1), LT.string_key(2464825061, 1), 2), LT.string_key(7345781, 2), 3), LT.string_key(311191059, 3), 4), LT.string_key(2463871799, 4), 5), LT.string_key(2464825061, 1)), LT.string_key(2464825061, 1), 7))) == 1984421159 : U32}

def lua_table_string_reinsert():
  {==}

law lua_table_string_gc_reinsert:
  {Pair.snd(LT.Table, U32, LT.fingerprint(LT.set(LT.collect(LT.remove(LT.set(LT.set(LT.set(LT.set(LT.set(LT.new(0, 0), LT.string_key(1650982772, 0), 1), LT.string_key(2464825061, 1), 2), LT.string_key(7345781, 2), 3), LT.string_key(311191059, 3), 4), LT.string_key(2463871799, 4), 5), LT.string_key(2464825061, 1))), LT.string_key(2464825061, 1), 7))) == 2302288171 : U32}

def lua_table_string_gc_reinsert():
  {==}

law lua_table_numbers:
  {Pair.snd(LT.Table, U32, LT.fingerprint(LT.set(LT.set(LT.remove(LT.set(LT.set(LT.set(LT.set(LT.set(LT.set(LT.new(0, 0), LT.int_key(1), 10), LT.int_key(2), 20), LT.int_key(3), 30), LT.int_key(4), 40), LT.int_key(5), 50), LT.number_key(1071644672, 0), 7), LT.int_key(3)), LT.number_key(3220176896, 0), 8), LT.int_key(100), 9))) == 102005494 : U32}

def lua_table_numbers():
  {==}

law lua_table_length:
  {Pair.snd(LT.Table, U32, LT.length(LT.set(LT.set(LT.set(LT.set(LT.set(LT.new(0, 0), LT.int_key(1), 1), LT.int_key(2), 2), LT.int_key(4), 4), LT.int_key(5), 5), LT.int_key(6), 6))) == 6 : U32}

def lua_table_length():
  {==}

law lua_sort_ties:
  {LO.fingerprint(LO.sort(~Unit, ~SH.key_less, Unit{}, SH.from_list(4n, [0, 196608, 65537, 196610, 131075, 65540, 196613, 131078, 65543, 196616, 9]), 10, 0), 10) == 3876019456 : U32}

def lua_sort_ties():
  {==}

law stl_sort_libstdcxx:
  {SH.work_fingerprint(SS.sort(~Unit, ~SH.key_less, Unit{}, SH.from_list(5n, [131072, 1, 65538, 131075, 131076, 5, 65542, 65543, 8, 131081, 65546, 11, 131084, 131085, 65550, 15, 16, 65553, 131090, 65555, 20, 131093, 65558, 23]), 0, 24), 0, 24) == 3943174043 : U32}

def stl_sort_libstdcxx():
  {==}

law stl_sort_msvc:
  {SH.work_fingerprint(SS.msvc_sort(~Unit, ~SH.key_less, Unit{}, SH.from_list(6n, [0, 1, 131074, 65539, 65540, 196613, 196614, 65543, 8, 9, 131082, 131083, 12, 196621, 196622, 65551, 65552, 196625, 131090, 131091, 20, 21, 131094, 65559, 65560, 196633, 196634, 65563, 28, 29, 131102, 131103, 32, 196641, 196642, 65571, 65572, 196645, 131110, 131111, 40, 41, 131114, 65579, 65580]), 0, 45), 0, 45) == 712265201 : U32}

def stl_sort_msvc():
  {==}

law stl_heap_push_pop:
  {SH.work_fingerprint(SH.pop_work(~Unit, ~SH.key_less, SH.pop_work(~Unit, ~SH.key_less, SH.pop_work(~Unit, ~SH.key_less, SH.pop_work(~Unit, ~SH.key_less, SH.push_work(~Unit, ~SH.key_less, SH.push_work(~Unit, ~SH.key_less, SH.push_work(~Unit, ~SH.key_less, SH.push_work(~Unit, ~SH.key_less, SH.push_work(~Unit, ~SH.key_less, SH.push_work(~Unit, ~SH.key_less, SH.push_work(~Unit, ~SH.key_less, SH.push_work(~Unit, ~SH.key_less, SH.Work{Unit{}, SH.from_list(3n, [327680, 65537, 327682, 196611, 65540, 262149, 327686, 131079])}, 0, 1), 0, 2), 0, 3), 0, 4), 0, 5), 0, 6), 0, 7), 0, 8), 0, 8), 0, 7), 0, 6), 0, 5), 0, 8) == 437835803 : U32}

def stl_heap_push_pop():
  {==}

law lua_math_random_scale:
  {LM.floor_of(LM.scale(2610666395, 51)) == 30 : U32}

def lua_math_random_scale():
  {==}

law lua_math_random_range:
  {Pair.fst(U32, R.Rng, LM.random_range(R.srandom(1), 1, 51)) == 48 : U32}

def lua_math_random_range():
  {==}

law lua_util_shuffle:
  {SH.fingerprint(LU.items_of(LU.shuffle_array(SH.from_list(4n, [1, 2, 3, 4, 5, 6, 7, 8]), 8, R.srandom(7))), 0, 8) == 2172912623 : U32}

def lua_util_shuffle():
  {==}

law storygen_table_order:
  {GO.order([GO.Slot{LS.hash_string("Make a pick:0:Clearing"), 1}, GO.Slot{LS.hash_string("Make a pick:1:Plain"), 2},
    GO.Slot{LS.hash_string("START"), 3}, GO.Slot{LS.hash_string("Make a pick:2:Forest"), 4},
    GO.Slot{LS.hash_string("Make a pick:BG_0:BGGrass"), 5}]) == [1, 2, 3, 5, 4] : List<&2, U32>}

def storygen_table_order():
  {==}

law storygen_unit_weight_exact:
  {GO.unit_weight_pick(1431655765, 3) == 0 : U32}

def storygen_unit_weight_exact():
  {==}

law storygen_unit_weight_half:
  {GO.unit_weight_pick(2147483648, 4) == 2 : U32}

def storygen_unit_weight_half():
  {==}

# M12: storygen's persistent array after word writes and a 32-word block write (the block replaces every word of its
# aligned range, here 1056..1087: 1057 comes from the block, 1070 is cleared, 2000 is outside and kept).
law storygen_mem_block:
  {(SM.get(SM.set_block(SM.set(SM.set(SM.empty(), 2000, 7), 1070, 9), 1056, 5n, SM.block(5n, [4, 5, 6])), 1057)
    + (SM.get(SM.set_block(SM.set(SM.set(SM.empty(), 2000, 7), 1070, 9), 1056, 5n, SM.block(5n, [4, 5, 6])), 1070) * 10)
    + (SM.get(SM.set_block(SM.set(SM.set(SM.empty(), 2000, 7), 1070, 9), 1056, 5n, SM.block(5n, [4, 5, 6])), 2000) * 100) : U32) == 705 : U32}

def storygen_mem_block():
  {==}
