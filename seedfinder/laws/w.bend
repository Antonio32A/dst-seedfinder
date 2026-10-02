import Base
import ../f32/powf.bend as Powf

# Golden values of the growing-tree maze's powf((float)u * 2^-32, e^-val): the machine code of MSVCR90 9.00.30729.9635's
# powf, mapped from the DLL and called natively. Every golden value was reproduced by calling the MSVCR90.dll that a Windows
# dedicated server loads (WinSxS, SHA-256 9660860D3513934EAB21DE84462EDBAAC8E846E4273D07CDD371ED6E471EE2B8) inside the Windows VM,
# as were the exhaustive fingerprints over all 9.2e8 maze inputs.

type Case is Data:
  Case{u: U32, val: U32}

type Pick is Data:
  Pick{u: U32, val: U32, count: U32}

def picks(+windows: Bool, cases: List<&2, Pick>) -> List<&2, U32>:
  match cases:
    case Nil{}:
      Nil{}
    case Con{Pick{+u, +val, +count}, rest}:
      Powf.maze_pick(windows, u, Powf.maze_exponent(val), count) <> picks(windows, rest)

def weights(+windows: Bool, cases: List<&2, Case>) -> List<&2, U32>:
  match cases:
    case Nil{}:
      Nil{}
    case Con{Case{+u, +val}, rest}:
      Powf.maze_weight(windows, u, Powf.maze_exponent(val)) <> weights(windows, rest)

# u, val: (0, -3), (1, 2), (24257705, -3), (24257706, -3), (25109445, -3), (25109446, -3), (26000000, -3), (29257708, -3).
law msvcr90_edges:
  {weights(True{}, [Case{0, 4294967293}, Case{1, 2}, Case{24257705, 4294967293}, Case{24257706, 4294967293}, Case{25109445, 4294967293}, Case{25109446, 4294967293}, Case{26000000, 4294967293}, Case{29257708, 4294967293}]) == [0, 1028361713, 0, 0, 0, 1, 2, 22] : List<&2, U32>}

def msvcr90_edges():
  {==}

# u, val: (123456789, -3), (3000000000, 7), (4294967295, 2), (873, 2), (2580, 2).
law msvcr90_common:
  {weights(True{}, [Case{123456789, 4294967293}, Case{3000000000, 7}, Case{4294967295, 2}, Case{873, 2}, Case{2580, 2}]) == [202249738, 1065347727, 1065353216, 1040088543, 1041455136] : List<&2, U32>}

def msvcr90_common():
  {==}

# u, val: (24260522, -3), (11138364, -1), (2931899, 1), (10172416, 2), (5293560, 4), (9939115, 6), (1789952, 7).
law msvcr90_differ:
  {weights(True{}, [Case{24260522, 4294967293}, Case{11138364, 4294967295}, Case{2931899, 1}, Case{10172416, 2}, Case{5293560, 4}, Case{9939115, 6}, Case{1789952, 7}]) == [0, 868776850, 1032597163, 1054992864, 1063416065, 1065102727, 1065234566] : List<&2, U32>}

def msvcr90_differ():
  {==}

# The active-list index (int)((float)(count - 1) * weight) for (u, val, count): (4294967295, 2, 1000), (2147483648, -1, 300), (3000000000, 7, 5), (1000, -3, 50).
law msvcr90_picks:
  {picks(True{}, [Pick{4294967295, 2, 1000}, Pick{2147483648, 4294967295, 300}, Pick{3000000000, 7, 5}, Pick{1000, 4294967293, 50}]) == [999, 45, 3, 0] : List<&2, U32>}

def msvcr90_picks():
  {==}
