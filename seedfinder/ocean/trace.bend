import Base
import ./convert_trace.bend as ConvertTrace
import ./ocean_trace.bend as OceanPostTrace

# Lane G's ocean trace stages (.scratch/port/status/M10.md): `oconvert` (Ocean_ConvertImpassibleToWater from the
# oracle's grid after the prefill), `oceanpost` (land_done to the attempt status around the oracle's converted
# grid) and `ocean` (everything from land_done to the attempt status).

def handles(+stage: String) -> Bool:
  String.eq(stage, "oconvert") || String.eq(stage, "ocean") || String.eq(stage, "oceanpost")

def run_ocean(post: Bool, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match post:
    case True{}:
      OceanPostTrace.run_post(seed, windows, lines)
    case False{}:
      OceanPostTrace.run_full(seed, windows, lines)

def run_stage(convert: Bool, +stage: String, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  match convert:
    case True{}:
      ConvertTrace.run(seed, windows, lines)
    case False{}:
      run_ocean(String.eq(stage, "oceanpost"), seed, windows, lines)

# The stage's records for a seed, platform and the lines of its input.
def run(+stage: String, +seed: U32, +windows: Bool, +lines: List<&2, String>) -> List<&2, String>:
  run_stage(String.eq(stage, "oconvert"), stage, seed, windows, lines)
