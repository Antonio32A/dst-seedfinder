import Base
import ../storygen/trace.bend as StoryTrace

# Lane S (story, Lua and data) trace stages: `handles` names the stages this file owns, `run` returns their canonical
# records (.scratch/port/CONVENTIONS.md "Trace mode"). Only lane S edits this file.

def handles(+stage: String) -> Bool:
  String.eq(stage, "storygen")

def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  StoryTrace.run(seed, input)
