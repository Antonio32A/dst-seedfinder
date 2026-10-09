import Base
import ../f32/powf.bend as Powf

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
