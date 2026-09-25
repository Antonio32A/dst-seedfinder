import Base
import ./kk.bend as KK

# Balanced rounds over many layout jobs: a binary tree of jobs (one workspace per leaf) advanced by the same fuel
# in parallel, so a search can bound each round and refill finished leaves between rounds.

type Jobs is Type:
  One{job: KK.Job}
  Two{a: Jobs, b: Jobs}

type Round is Type:
  Round{jobs: Jobs, live: U32}

def live_at(phase: KK.Phase, clock: KK.Clock) -> U32:
  match phase:
    case KK.Ended{}:
      match clock:
        case KK.Clock{inner, outer, last, outers, newtons, left}:
          Bool.to_u32(Bool.not(U32.is_zero(left)))
    case _:
      1

def counted(job: KK.Job) -> Round:
  match job:
    case KK.Job{ws, +n, +phase, +p, +delta, +clock, +ok}:
      Round{One{KK.Job{ws, n, phase, p, delta, clock, ok}}, live_at(phase, clock)}

def joined(x: Round, y: Round) -> Round:
  match x:
    case Round{a, +la}:
      match y:
        case Round{b, +lb}:
          Round{Two{a, b}, (la + lb : U32)}

# Every job advanced by `fuel` phase steps (KK.advance), both halves of each node in parallel; `live` counts the
# jobs that have not ended their last run.
def advance_all(+fuel: Nat, jobs: Jobs) -> Round:
  match jobs:
    case One{job}:
      counted(KK.advance(fuel, job))
    case Two{a, b}:
      x y = advance_all(fuel, a) advance_all(fuel, b)
      joined(x, y)
