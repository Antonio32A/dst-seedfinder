import Base
import ../f32/powf.bend as Powf

# MSVCR90 powf results read back from the MSVCR90.dll that the Windows VM's dedicated server loads (see w.bend).

type Case is Data:
  Case{u: U32, val: U32}

def weights(+windows: Bool, cases: List<&2, Case>) -> List<&2, U32>:
  match cases:
    case Nil{}:
      Nil{}
    case Con{Case{+u, +val}, rest}:
      Powf.maze_weight(windows, u, Powf.maze_exponent(val)) <> weights(windows, rest)

# u, val: (1, 7), (2147483648, -3), (1125, 2), (11138364, -1), (5293560, 4): MSVCR90 results read back from the Windows VM.
law msvcr90_vm:
  {weights(True{}, [Case{1, 7}, Case{2147483648, 4294967293}, Case{1125, 2}, Case{11138364, 4294967295}, Case{5293560, 4}]) == [1065017286, 896615254, 1040429148, 868776850, 1063416065] : List<&2, U32>}

def msvcr90_vm():
  {==}
