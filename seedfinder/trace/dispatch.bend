import Base
import ./m0.bend as M0
import ./lane_n.bend as TN
import ./lane_s.bend as TS
import ./lane_g.bend as TG
import ./lane_f.bend as TF
import ../gen/trace.bend as GT

# `seedfinder trace` stage dispatch: the first module whose `handles` accepts the stage runs it.

def unknown(+stage: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  Fail{(2, "trace: unknown stage \"" ++ stage ++ "\"")}

def via_f(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{TF.run(stage, seed, windows, input)}
    case False{}:
      unknown(stage)

def via_g(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{TG.run(stage, seed, windows, input)}
    case False{}:
      via_f(TF.handles(stage), stage, seed, windows, input)

def via_s(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{TS.run(stage, seed, windows, input)}
    case False{}:
      via_g(TG.handles(stage), stage, seed, windows, input)

def via_n(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{TN.run(stage, seed, windows, input)}
    case False{}:
      via_s(TS.handles(stage), stage, seed, windows, input)

def via_m0(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{M0.run(stage, seed, windows, input)}
    case False{}:
      via_n(TN.handles(stage), stage, seed, windows, input)

def via_gen(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{GT.run(stage, seed, windows, input)}
    case False{}:
      via_m0(M0.handles(stage), stage, seed, windows, input)

# The canonical records of `stage` for `seed` on the given platform, from the text of the --input file.
def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  via_gen(GT.handles(stage), stage, seed, windows, input)
