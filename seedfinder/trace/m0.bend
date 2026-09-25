import Base
import ../rng/pcg.bend as R
import ../rng/crand.bend as CR
import ./canon.bend as CN

# Trace stages of the M0 skeleton. `crand`: for every `gpfs` record of the input (an oracle points.txt, or the
# records a diff script picked from it), GetPointsForSite's random_shuffle replayed from the record's `before`
# counter and `n`: the `gpfs` record with the counter after the shuffle, and one `gpfs_perm` record per position.

def handles(+stage: String) -> Bool:
  String.eq(stage, "crand")

def perm_lines(order: List<&2, U32>, +a: String, +i: String, +k: U32) -> List<&2, String>:
  match order:
    case Nil{}:
      Nil{}
    case Con{+src, rest}:
      CN.record("gpfs_perm", [CN.field("a", a), CN.field("i", i), CN.number("k", k), CN.number("src", src)])
        <> perm_lines(rest, a, i, (k + 1 : U32))

def call_lines(+seed: U32, +fields: List<&2, String>, +n: U32, +before: U32, order: CR.Order) -> List<&2, String>:
  match order:
    case CR.Order{+indices, rng}:
      +a = CN.text_or(CN.value_of("a", fields), "0")
      +i = CN.text_or(CN.value_of("i", fields), "0")
      CN.record("gpfs", [CN.field("a", a), CN.field("i", i), CN.field("node", CN.text_or(CN.value_of("node", fields), "\"\"")),
        CN.number("n", n), CN.number("before", before), CN.number("after", R.counter(seed, rng))]) <> perm_lines(indices, a, i, 0)

def gpfs_lines(+seed: U32, +windows: Bool, +fields: List<&2, String>) -> List<&2, String>:
  +n = CN.number_or(CN.value_of("n", fields), 0)
  +before = CN.number_or(CN.value_of("before", fields), 0)
  call_lines(seed, fields, n, before, CR.shuffled_order(windows, n, R.at_counter(seed, before)))

def all_calls(+seed: U32, +windows: Bool, calls: List<&2, List<&2, String>>) -> List<&2, String>:
  match calls:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      List.append(&2, String, gpfs_lines(seed, windows, fields), all_calls(seed, windows, rest))

def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  all_calls(seed, windows, CN.records("gpfs", String.split(input, '\n')))
