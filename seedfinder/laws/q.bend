import Base
import ../rng/pcg.bend as Pcg
import ../f64/repr.bend as F64Repr
import ../populate/layout.bend as PopulateLayout
import ../populate/counts.bend as PopulateCounts

# Lane Q (caves population closures) laws. Goldens: the real game Lua under DST's PCG32 (count and prefabdata closures called
# with math.random counted, object_layout.ConvertLayoutToEntitylist of the caves' layouts): each law is followed by its
# proof def of the same name.

def word_fold(+h: U32, +w: U32) -> U32:
  (h * 31 + w : U32)

def item_fold(+h: U32, +i: PopulateLayout.Item) -> U32:
  match i:
    case PopulateLayout.Item{+prefab, F64Repr.F64{+xh, +xl}, F64Repr.F64{+yh, +yl}, _}:
      word_fold(word_fold(word_fold(word_fold(word_fold(h, prefab), xh), xl), yh), yl)

def items_fold(items: List<&2, PopulateLayout.Item>, +h: U32) -> U32:
  match items:
    case Nil{}:
      h
    case Con{+i, rest}:
      items_fold(rest, item_fold(h, i))

# The items of a layout conversion folded with their positions' bits, then the draw counter of the RNG after it.
def items_code(got: List<&2, PopulateLayout.Item> & Pcg.Rng, +seed: U32) -> U32:
  (+items, s) = got
  (items_fold(items, 0) * 31 + Pcg.counter(seed, s) : U32)

law count_closure_100_at_0:
  {PopulateCounts.count_of(100, 0, 425, Pcg.at_counter(1, 0)) == (3, Pcg.at_counter(1, 1)) : U32 & Pcg.Rng}

def count_closure_100_at_0():
  {==}

law count_closure_100_at_3:
  {PopulateCounts.count_of(100, 0, 425, Pcg.at_counter(1, 3)) == (2, Pcg.at_counter(1, 4)) : U32 & Pcg.Rng}

def count_closure_100_at_3():
  {==}

law count_closure_100_at_6:
  {PopulateCounts.count_of(100, 0, 425, Pcg.at_counter(1, 6)) == (1, Pcg.at_counter(1, 7)) : U32 & Pcg.Rng}

def count_closure_100_at_6():
  {==}

law count_closure_141_at_0:
  {PopulateCounts.count_of(141, 0, 425, Pcg.at_counter(1, 0)) == (1, Pcg.at_counter(1, 1)) : U32 & Pcg.Rng}

def count_closure_141_at_0():
  {==}

law count_closure_141_at_6:
  {PopulateCounts.count_of(141, 0, 425, Pcg.at_counter(1, 6)) == (0, Pcg.at_counter(1, 7)) : U32 & Pcg.Rng}

def count_closure_141_at_6():
  {==}

law count_closure_142_at_0:
  {PopulateCounts.count_of(142, 0, 425, Pcg.at_counter(1, 0)) == (0, Pcg.at_counter(1, 1)) : U32 & Pcg.Rng}

def count_closure_142_at_0():
  {==}

law count_closure_142_at_6:
  {PopulateCounts.count_of(142, 0, 425, Pcg.at_counter(1, 6)) == (1, Pcg.at_counter(1, 7)) : U32 & Pcg.Rng}

def count_closure_142_at_6():
  {==}

law count_closure_143_at_0:
  {PopulateCounts.count_of(143, 0, 425, Pcg.at_counter(1, 0)) == (3, Pcg.at_counter(1, 1)) : U32 & Pcg.Rng}

def count_closure_143_at_0():
  {==}

law count_closure_143_at_6:
  {PopulateCounts.count_of(143, 0, 425, Pcg.at_counter(1, 6)) == (2, Pcg.at_counter(1, 7)) : U32 & Pcg.Rng}

def count_closure_143_at_6():
  {==}

law prefabdata_closure_85_at_0:
  {PopulateCounts.prefab_data_call(85, Pcg.at_counter(1, 0)) == Pcg.at_counter(1, 1) : Pcg.Rng}

def prefabdata_closure_85_at_0():
  {==}

law prefabdata_closure_85_at_6:
  {PopulateCounts.prefab_data_call(85, Pcg.at_counter(1, 6)) == Pcg.at_counter(1, 7) : Pcg.Rng}

def prefabdata_closure_85_at_6():
  {==}

law prefabdata_closure_144_at_0:
  {PopulateCounts.prefab_data_call(144, Pcg.at_counter(1, 0)) == Pcg.at_counter(1, 1) : Pcg.Rng}

def prefabdata_closure_144_at_0():
  {==}

law prefabdata_closure_144_at_6:
  {PopulateCounts.prefab_data_call(144, Pcg.at_counter(1, 6)) == Pcg.at_counter(1, 8) : Pcg.Rng}

def prefabdata_closure_144_at_6():
  {==}

law prefabdata_closure_144_at_18:
  {PopulateCounts.prefab_data_call(144, Pcg.at_counter(1, 18)) == Pcg.at_counter(1, 20) : Pcg.Rng}

def prefabdata_closure_144_at_18():
  {==}

law prefabdata_closure_145_at_0:
  {PopulateCounts.prefab_data_call(145, Pcg.at_counter(1, 0)) == Pcg.at_counter(1, 1) : Pcg.Rng}

def prefabdata_closure_145_at_0():
  {==}

law prefabdata_closure_145_at_3:
  {PopulateCounts.prefab_data_call(145, Pcg.at_counter(1, 3)) == Pcg.at_counter(1, 4) : Pcg.Rng}

def prefabdata_closure_145_at_3():
  {==}

law prefabdata_closure_145_at_6:
  {PopulateCounts.prefab_data_call(145, Pcg.at_counter(1, 6)) == Pcg.at_counter(1, 7) : Pcg.Rng}

def prefabdata_closure_145_at_6():
  {==}
