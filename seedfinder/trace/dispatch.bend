import Base
import ./crand.bend as TraceCrand
import ./map.bend as TraceMap
import ../worldsim/layout/trace.bend as LayoutTrace
import ../worldsim/voronoi/trace.bend as VoronoiTrace
import ../storygen/trace.bend as StoryTrace
import ../gen/trace.bend as GenTrace
import ../gen/cave_trace.bend as CaveTrace
import ../data/builds.bend as Builds

# `seedfinder trace` stage dispatch: the first module whose `handles` accepts the stage runs it.

def unknown(+stage: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  Fail{(2, "trace: unknown stage \"" ++ stage ++ "\"")}

def via_map(+build: Builds.Build, owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{TraceMap.run(build, stage, seed, windows, input)}
    case False{}:
      unknown(stage)

def via_story(+build: Builds.Build, owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{StoryTrace.run(build, seed, input)}
    case False{}:
      via_map(build, TraceMap.handles(stage), stage, seed, windows, input)

def via_voronoi(+build: Builds.Build, owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{VoronoiTrace.run(stage, seed, windows, input)}
    case False{}:
      via_story(build, String.eq(stage, "storygen"), stage, seed, windows, input)

def via_layout(+build: Builds.Build, owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{LayoutTrace.run(stage, seed, windows, input)}
    case False{}:
      via_voronoi(build, VoronoiTrace.handles(stage), stage, seed, windows, input)

def via_crand(+build: Builds.Build, owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{TraceCrand.run(stage, seed, windows, input)}
    case False{}:
      via_layout(build, LayoutTrace.handles(stage), stage, seed, windows, input)

def via_gen(+build: Builds.Build, owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{GenTrace.run(build, stage, seed, windows, input)}
    case False{}:
      via_crand(build, TraceCrand.handles(stage), stage, seed, windows, input)

def via_cave(+build: Builds.Build, owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  match owned:
    case True{}:
      Done{CaveTrace.run(build, stage, seed, windows, input)}
    case False{}:
      via_gen(build, GenTrace.handles(stage), stage, seed, windows, input)

# The canonical records of `stage` for `seed` on the given platform, from the text of the --input file.
def run(+build: Builds.Build, +stage: String, +seed: U32, +windows: Bool, +input: String) -> Result<&1, &1, U32 & String, List<&2, String>>:
  via_cave(build, CaveTrace.handles(stage), stage, seed, windows, input)
