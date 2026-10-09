import Base
import ../rng/pcg.bend as Pcg
import ../populate/counts.bend as PopulateCounts

# Goldens: the real game Lua under DST's PCG32 (the count and prefabdata closures called with math.random counted).

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
