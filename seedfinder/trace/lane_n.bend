import Base
import ../worldsim/layout/trace.bend as LayoutTrace
import ../worldsim/voronoi/trace.bend as VoronoiTrace

# Lane N (numeric) trace stages: `handles` names the stages this file owns, `run` returns their canonical
# records (.scratch/port/CONVENTIONS.md "Trace mode"). Only lane N edits this file. Layout (M5): `hops`, `kk`. Voronoi (M6): `voronoi`,
# `polygons`.
# A new lane N stage module adds its `handles` to `handles` and a `via_*` step in place of `unowned`.

def handles(+stage: String) -> Bool:
  LayoutTrace.handles(stage) || VoronoiTrace.handles(stage)

def unowned(+stage: String) -> List<&2, String>:
  Nil{}

def via_voronoi(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  match owned:
    case True{}:
      VoronoiTrace.run(stage, seed, windows, input)
    case False{}:
      unowned(stage)

def via_layout(owned: Bool, +stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  match owned:
    case True{}:
      LayoutTrace.run(stage, seed, windows, input)
    case False{}:
      via_voronoi(VoronoiTrace.handles(stage), stage, seed, windows, input)

def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  via_layout(LayoutTrace.handles(stage), stage, seed, windows, input)
