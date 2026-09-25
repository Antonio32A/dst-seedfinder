import Base

# Lane F (filters and search) trace stages: `handles` names the stages this file owns, `run` returns their canonical
# records (.scratch/port/CONVENTIONS.md "Trace mode"). Only lane F edits this file.

def handles(+stage: String) -> Bool:
  False{}

def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  Nil{}
