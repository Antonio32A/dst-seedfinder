import Base
import ./m0.bend as M0
import ./lane_n.bend as LaneN
import ./lane_s.bend as LaneS
import ./lane_g.bend as LaneG
import ./lane_f.bend as LaneF
import ../gen/trace.bend as GenTrace
import ../gen/cave_trace.bend as CaveTrace

# `seedfinder trace` stage dispatch: the first module whose `handles` accepts the stage runs it.

def unknown(+stage: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  Fail{(2, "trace: unknown stage \"" ++ stage ++ "\"")}

def via_f(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{LaneF.run(stage, seed, windows, input)}
    case False{}:
      unknown(stage)

def via_g(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{LaneG.run(stage, seed, windows, input)}
    case False{}:
      via_f(LaneF.handles(stage), stage, seed, windows, input)

def via_s(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{LaneS.run(stage, seed, windows, input)}
    case False{}:
      via_g(LaneG.handles(stage), stage, seed, windows, input)

def via_n(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{LaneN.run(stage, seed, windows, input)}
    case False{}:
      via_s(LaneS.handles(stage), stage, seed, windows, input)

def via_m0(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{M0.run(stage, seed, windows, input)}
    case False{}:
      via_n(LaneN.handles(stage), stage, seed, windows, input)

def via_gen(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{GenTrace.run(stage, seed, windows, input)}
    case False{}:
      via_m0(M0.handles(stage), stage, seed, windows, input)

def via_cave(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{CaveTrace.run(stage, seed, windows, input)}
    case False{}:
      via_gen(GenTrace.handles(stage), stage, seed, windows, input)

# The canonical records of `stage` for `seed` on the given platform, from the text of the --input file.
def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  via_cave(CaveTrace.handles(stage), stage, seed, windows, input)
