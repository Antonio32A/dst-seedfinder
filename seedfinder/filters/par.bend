import Base

# Fork-join maps. The runtime spreads a fork tree well when the forked calls carry only small values (index ranges)
# and read shared inputs at the leaves; forking on split lists keeps the work on about two threads, and forks
# nested inside a forked task stay on its thread. A tree of depth bits(n) with
# at most one item per leaf balances best.

def bits_of(n: Nat, +k: Nat, +d: Nat) -> Nat:
  match n:
    case 0n:
      d
    case 1n+p:
      bits_of(p, k, Bool.pick(Nat, Nat.is_ge(k, Nat.pow(2n, d)), Nat.add(d, 1n), d))

# The fork depth for n items: the bit length of n, and no fork for a single item (a fork inside a forked task runs
# on that task's thread, so a lone item keeps the tree free for the forks below it).
def depth_for(+n: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(n, 1n), 0n, bits_of(32n, n, 0n))

def leaf_item(~A: Data, ~B: Data, ~C: Data, ~f: C -> A -> B, m: Maybe<&2, A>, +ctx: C, acc: List<&2, B>) -> List<&2, B>:
  match m:
    case None{}:
      acc
    case Some{+x}:
      f(ctx, x) <> acc

def leaf(~A: Data, ~B: Data, ~C: Data, ~f: C -> A -> B, n: Nat, +ctx: C, +items: List<&2, A>, +i: Nat, acc: List<&2, B>) -> List<&2, B>:
  match n:
    case 0n:
      List.reverse(&2, B, acc)
    case 1n+k:
      leaf(~A, ~B, ~C, ~f, k, ctx, items, Nat.add(i, 1n), leaf_item(~A, ~B, ~C, ~f, List.get(&2, A, items, i), ctx, acc))

def tree(~A: Data, ~B: Data, ~C: Data, ~f: C -> A -> B, +depth: Nat, +ctx: C, +items: List<&2, A>, +lo: Nat, +n: Nat) -> List<&2, B>:
  match depth:
    case 0n:
      leaf(~A, ~B, ~C, ~f, n, ctx, items, lo, Nil{})
    case 1n+d:
      +half = Nat.div(n, 2n)
      a b = tree(~A, ~B, ~C, ~f, d, ctx, items, lo, half) tree(~A, ~B, ~C, ~f, d, ctx, items, Nat.add(lo, half), Nat.sub(n, half))
      List.append(&2, B, a, b)

# [f(ctx, x) for x in items], in order, the items spread over a balanced fork tree.
def map(~A: Data, ~B: Data, ~C: Data, ~f: C -> A -> B, +ctx: C, +items: List<&2, A>) -> List<&2, B>:
  +n = List.length(&2, A, items)
  tree(~A, ~B, ~C, ~f, depth_for(n), ctx, items, 0n, n)
