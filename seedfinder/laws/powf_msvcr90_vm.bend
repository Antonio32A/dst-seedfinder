import Base
import ../lawkit/powf_cases.bend as PowfCases

# MSVCR90 powf results read back from the MSVCR90.dll that the Windows VM's dedicated server loads (see powf_msvcr90.bend).

# u, val: (1, 7), (2147483648, -3), (1125, 2), (11138364, -1), (5293560, 4): MSVCR90 results read back from the Windows VM.
law msvcr90_vm:
  {PowfCases.weights(True{}, [PowfCases.Case{1, 7}, PowfCases.Case{2147483648, 4294967293}, PowfCases.Case{1125, 2}, PowfCases.Case{11138364, 4294967295}, PowfCases.Case{5293560, 4}]) == [1065017286, 896615254, 1040429148, 868776850, 1063416065] : List<&2, U32>}

def msvcr90_vm():
  {==}
