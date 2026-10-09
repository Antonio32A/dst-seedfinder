import Base
import ./crand.bend as TraceCrand
import ./map.bend as TraceMap
import ../worldsim/layout/trace.bend as LayoutTrace
import ../worldsim/voronoi/trace.bend as VoronoiTrace
import ../storygen/trace.bend as StoryTrace
import ../gen/trace.bend as GenTrace
import ../gen/cave_trace.bend as CaveTrace

# `seedfinder trace` stage dispatch: the first module whose `handles` accepts the stage runs it.

def unknown(+stage: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  Fail{(2, "trace: unknown stage \"" ++ stage ++ "\"")}

def via_map(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{TraceMap.run(stage, seed, windows, input)}
    case False{}:
      unknown(stage)

def via_story(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{StoryTrace.run(seed, input)}
    case False{}:
      via_map(TraceMap.handles(stage), stage, seed, windows, input)

def via_voronoi(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{VoronoiTrace.run(stage, seed, windows, input)}
    case False{}:
      via_story(String.eq(stage, "storygen"), stage, seed, windows, input)

def via_layout(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{LayoutTrace.run(stage, seed, windows, input)}
    case False{}:
      via_voronoi(VoronoiTrace.handles(stage), stage, seed, windows, input)

def via_crand(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{TraceCrand.run(stage, seed, windows, input)}
    case False{}:
      via_layout(LayoutTrace.handles(stage), stage, seed, windows, input)

def via_gen(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{GenTrace.run(stage, seed, windows, input)}
    case False{}:
      via_crand(TraceCrand.handles(stage), stage, seed, windows, input)

def via_cave(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{CaveTrace.run(stage, seed, windows, input)}
    case False{}:
      via_gen(GenTrace.handles(stage), stage, seed, windows, input)

# The canonical records of `stage` for `seed` on the given platform, from the text of the --input file.
def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  via_cave(CaveTrace.handles(stage), stage, seed, windows, input)
