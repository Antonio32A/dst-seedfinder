import Base

# A persistent array of 2^16 U32 words (a complete binary tree, shared on copy), so storygen state is Data and can be
# read without handing it back.

type Mem is Data:
  MemLeaf{v: U32}
  MemNode{l: Mem, r: Mem}

def zeros(+n: Nat) -> Mem:
  match n:
    case 0n:
      MemLeaf{0}
    case 1n+p:
      +z = zeros(p)
      MemNode{z, z}

def bit(+i: U32, +p: Nat) -> Bool:
  U32.is_eq(((i >> p) .&. 1 : U32), 1)

# `right` is the bit of i that picks the child at this level (bit n - 1); only the child taken is bound, so a read
# or write keeps one subtree per level instead of both.
def get_loop(+n: Nat, right: Bool, +m: Mem, +i: U32) -> U32:
  match n:
    case 0n:
      match m:
        case MemLeaf{+v}:
          v
        case MemNode{_, _}:
          0
    case 1n+p:
      match right:
        case True{}:
          match m:
            case MemLeaf{+v}:
              v
            case MemNode{_, +r}:
              get_loop(p, bit(i, Nat.sub(p, 1n)), r, i)
        case False{}:
          match m:
            case MemLeaf{+v}:
              v
            case MemNode{+l, _}:
              get_loop(p, bit(i, Nat.sub(p, 1n)), l, i)

def set_loop(+n: Nat, right: Bool, +m: Mem, +i: U32, +v: U32) -> Mem:
  match n:
    case 0n:
      MemLeaf{v}
    case 1n+p:
      match right:
        case True{}:
          match m:
            case MemLeaf{_}:
              MemLeaf{v}
            case MemNode{+l, +r}:
              MemNode{l, set_loop(p, bit(i, Nat.sub(p, 1n)), r, i, v)}
        case False{}:
          match m:
            case MemLeaf{_}:
              MemLeaf{v}
            case MemNode{+l, +r}:
              MemNode{set_loop(p, bit(i, Nat.sub(p, 1n)), l, i, v), r}

def block_loop(+n: Nat, right: Bool, +m: Mem, +i: U32, +k: Nat, +b: Mem) -> Mem:
  match n:
    case 0n:
      b
    case 1n+p:
      match right:
        case True{}:
          match m:
            case MemLeaf{_}:
              b
            case MemNode{+l, +r}:
              MemNode{l, block_loop(p, bit(i, Nat.sub(Nat.add(k, p), 1n)), r, i, k, b)}
        case False{}:
          match m:
            case MemLeaf{_}:
              b
            case MemNode{+l, +r}:
              MemNode{block_loop(p, bit(i, Nat.sub(Nat.add(k, p), 1n)), l, i, k, b), r}

def depth() -> Nat:
  16n

# A subtree of 2^d words holding xs in index order (0 past its end).
def block(+d: Nat, +xs: List<&2, U32>) -> Mem:
  match d:
    case 0n:
      MemLeaf{Maybe.default(&2, U32, List.head(&2, U32, xs), 0)}
    case 1n+p:
      +half = Nat.pow(2n, p)
      MemNode{block(p, List.take(&2, U32, xs, half)), block(p, List.drop(&2, U32, xs, half))}

# The array with the aligned block of 2^k words that holds index i replaced by b (a `block` of depth k): the same as
# setting each of its words in turn.
def set_block(+m: Mem, +i: U32, +k: Nat, +b: Mem) -> Mem:
  block_loop(Nat.sub(depth(), k), bit(i, 15n), m, i, k, b)

def empty() -> Mem:
  zeros(depth())

def get(+m: Mem, +i: U32) -> U32:
  get_loop(depth(), bit(i, 15n), m, i)

def set(+m: Mem, +i: U32, +v: U32) -> Mem:
  set_loop(depth(), bit(i, 15n), m, i, v)
