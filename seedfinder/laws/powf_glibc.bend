import Base
import ../f32/powf.bend as Powf
import ../lawkit/powf_cases.bend as PowfCases

# Golden values of the growing-tree maze's powf((float)u * 2^-32, e^-val): glibc 2.41's powf called natively on x86-64 (FMA
# build).

# (float)pow(e, -val) for val = -3..7.
law maze_exponents:
  {[Powf.maze_exponent(4294967293), Powf.maze_exponent(4294967294), Powf.maze_exponent(4294967295), Powf.maze_exponent(0), Powf.maze_exponent(1), Powf.maze_exponent(2), Powf.maze_exponent(3), Powf.maze_exponent(4), Powf.maze_exponent(5), Powf.maze_exponent(6), Powf.maze_exponent(7)] == [1101049646, 1089237798, 1076754516, 1065353216, 1052531378, 1040880981, 1028386182, 1016466094, 1004325375, 992113296, 980355933] : List<&2, U32>}

def maze_exponents():
  {==}

# (float)u * 2^-32 rounds u to 24 bits to nearest even (16777217 -> 2^24, 16777219 -> 2^24 + 4, 4294967168 -> 1.0).
law unit_rounding:
  {[Powf.unit(0), Powf.unit(1), Powf.unit(16777217), Powf.unit(16777219), Powf.unit(2147483648), Powf.unit(4294967167), Powf.unit(4294967168), Powf.unit(4294967295)] == [0, 796917760, 998244352, 998244354, 1056964608, 1065353215, 1065353216, 1065353216] : List<&2, U32>}

def unit_rounding():
  {==}

# u, val: (0, -3), (1, 2), (24257705, -3), (24257706, -3), (25109445, -3), (25109446, -3), (26000000, -3), (29257708, -3).
law glibc_edges:
  {PowfCases.weights(False{}, [PowfCases.Case{0, 4294967293}, PowfCases.Case{1, 2}, PowfCases.Case{24257705, 4294967293}, PowfCases.Case{24257706, 4294967293}, PowfCases.Case{25109445, 4294967293}, PowfCases.Case{25109446, 4294967293}, PowfCases.Case{26000000, 4294967293}, PowfCases.Case{29257708, 4294967293}]) == [0, 1028361713, 0, 1, 1, 1, 2, 22] : List<&2, U32>}

def glibc_edges():
  {==}

# u, val: (123456789, -3), (3000000000, 7), (4294967295, 2), (873, 2), (2580, 2).
law glibc_common:
  {PowfCases.weights(False{}, [PowfCases.Case{123456789, 4294967293}, PowfCases.Case{3000000000, 7}, PowfCases.Case{4294967295, 2}, PowfCases.Case{873, 2}, PowfCases.Case{2580, 2}]) == [202249738, 1065347727, 1065353216, 1040088544, 1041455135] : List<&2, U32>}

def glibc_common():
  {==}

# u, val: (24260522, -3), (11138364, -1), (2931899, 1), (10172416, 2), (5293560, 4), (9939115, 6), (1789952, 7).
law glibc_differ:
  {PowfCases.weights(False{}, [PowfCases.Case{24260522, 4294967293}, PowfCases.Case{11138364, 4294967295}, PowfCases.Case{2931899, 1}, PowfCases.Case{10172416, 2}, PowfCases.Case{5293560, 4}, PowfCases.Case{9939115, 6}, PowfCases.Case{1789952, 7}]) == [1, 868776851, 1032597164, 1054992865, 1063416066, 1065102728, 1065234567] : List<&2, U32>}

def glibc_differ():
  {==}

# The active-list index (int)((float)(count - 1) * weight) for (u, val, count): (4294967295, 2, 1000), (2147483648, -1, 300), (3000000000, 7, 5), (1000, -3, 50).
law glibc_picks:
  {PowfCases.picks(False{}, [PowfCases.Pick{4294967295, 2, 1000}, PowfCases.Pick{2147483648, 4294967295, 300}, PowfCases.Pick{3000000000, 7, 5}, PowfCases.Pick{1000, 4294967293, 50}]) == [999, 45, 3, 0] : List<&2, U32>}

def glibc_picks():
  {==}
