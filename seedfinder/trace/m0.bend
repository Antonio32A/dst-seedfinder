import Base
import ../rng/pcg.bend as Pcg
import ../rng/crand.bend as CRand
import ./canon.bend as Canon

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
      Canon.record("gpfs_perm", [Canon.field("a", a), Canon.field("i", i), Canon.number("k", k), Canon.number("src", src)])
        <> perm_lines(rest, a, i, (k + 1 : U32))

def call_lines(+seed: U32, +fields: List<&2, String>, +n: U32, +before: U32, order: CRand.Order) -> List<&2, String>:
  match order:
    case CRand.Order{+indices, rng}:
      +a = Canon.text_or(Canon.value_of("a", fields), "0")
      +i = Canon.text_or(Canon.value_of("i", fields), "0")
      Canon.record("gpfs", [Canon.field("a", a), Canon.field("i", i), Canon.field("node", Canon.text_or(Canon.value_of("node", fields), "\"\"")),
        Canon.number("n", n), Canon.number("before", before), Canon.number("after", Pcg.counter(seed, rng))]) <> perm_lines(indices, a, i, 0)

def gpfs_lines(+seed: U32, +windows: Bool, +fields: List<&2, String>) -> List<&2, String>:
  +n = Canon.number_or(Canon.value_of("n", fields), 0)
  +before = Canon.number_or(Canon.value_of("before", fields), 0)
  call_lines(seed, fields, n, before, CRand.shuffled_order(windows, n, Pcg.at_counter(seed, before)))

def all_calls(+seed: U32, +windows: Bool, calls: List<&2, List<&2, String>>) -> List<&2, String>:
  match calls:
    case Nil{}:
      Nil{}
    case Con{+fields, rest}:
      List.append(&2, String, gpfs_lines(seed, windows, fields), all_calls(seed, windows, rest))

def run(+stage: String, +seed: U32, +windows: Bool, +input: String) -> List<&2, String>:
  all_calls(seed, windows, Canon.records("gpfs", String.split(input, '\n')))
