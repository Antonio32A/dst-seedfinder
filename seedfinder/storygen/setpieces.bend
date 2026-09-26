import Base
import ../lua/table.bend as LT
import ../lua/util.bend as LU
import ../level/prefix.bend as P
import ../level/summary.bend as W
import ../data/story.bend as SY
import ../data/enums.bend as EN
import ./graph.bend as GG
import ./order.bend as GO

# Story:InsertAdditionalSetPieces: every task's set_pieces (Level:ChooseSetPieces, in pairs(level.set_pieces) order)
# and random_set_pieces go into the first acceptable node of shuffledKeys(task.nodes) (countstaticlayouts[name] = 1).

# A set piece as string id << 16 | layout index.
def packed(+name: U32, +layout: U32) -> U32:
  ((name << 16n) .|. layout : U32)

def keyed_pieces(entries: List<&2, U32>, +task: U32) -> List<&2, U32>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, rest}:
      +tail = keyed_pieces(rest, task)
      +key = (entry .&. 63 : U32)
      +placed = U32.is_eq((((entry >> 6n) >> U32.to_nat(task)) .&. 1 : U32), 1)
      Bool.pick(List<&2, U32>, placed, packed(SY.piece_key(key), SY.piece_key_layout(key)) <> tail, tail)

def special_pieces(n: Nat, +codes: U32, +tasks: U32, +task: U32, +k: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +tail = special_pieces(p, codes, tasks, task, (k + 1 : U32))
      +code = P.field5(codes, k)
      Bool.pick(List<&2, U32>, U32.is_eq(P.field5(tasks, k), task), packed(SY.piece_special(code), SY.piece_special_layout(code)) <> tail, tail)

# task.set_pieces of a task.
def set_pieces(+level: W.Summary, +task: U32) -> List<&2, U32>:
  match level:
    case W.Summary{_, _, +entries, _, _, _, _}:
      keyed_pieces(entries, task)

# task.random_set_pieces of a task.
def random_set_pieces(+level: W.Summary, +task: U32) -> List<&2, U32>:
  match level:
    case W.Summary{_, _, _, +codes, +tasks, +count, _}:
      special_pieces(U32.to_nat(count), codes, tasks, task, 0)

def written(arr: Array<U32>, +i: U32, +v: U32) -> Array<U32>:
  arr[i] <- v

def fill_array(xs: List<&2, U32>, arr: Array<U32>, +i: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      arr
    case Con{+x, rest}:
      fill_array(rest, written(arr, i, x), (i + 1 : U32))

def read_out(n: Nat, got: Array<U32> & U32, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      (arr, +v) = got
      +rest = read_out(p, arr[(i + 1 : U32)], (i + 1 : U32))
      Bool.pick(List<&2, U32>, U32.is_eq(v, GG.none()), Nil{}, v <> rest)

type Picks is Data:
  Picks{order: List<&2, U32>, st: GG.St}

def unshuffled(sh: LU.Shuffled, +n: U32, +s: GG.St) -> Picks:
  match sh:
    case LU.Shuffled{items, rng}:
      Picks{read_out(U32.to_nat((n + 1 : U32)), items[0], 0), GG.with_rng(s, rng)}

# shuffledKeys(task.nodes): the keys in pairs() order, shuffleArray'd (n - 1 draws), as ipairs sees them.
def shuffled(+s: GG.St, +order: List<&2, U32>) -> Picks:
  +n = GO.count(order, 0)
  arr = fill_array(order, Array.new(U32, U32.to_nat(LT.ceil_log2((n + 2 : U32))), GG.none()), 0)
  unshuffled(LU.shuffle_array(arr, n, GG.rng_of(s)), n, s)

def acceptable(+s: GG.St, +node: U32, +random: Bool) -> Bool:
  +not_blank = Bool.pick(Bool, random, U32.is_ne(GG.nf(s, node, GG.f_type()), EN.node_type_blank()),
    Bool.not(SY.is_impassable(GG.nf(s, node, GG.f_value()))))
  Bool.not(GG.is_entrance(s, node)) && not_blank

def choice(order: List<&2, U32>, +s: GG.St, +random: Bool) -> U32:
  match order:
    case Nil{}:
      GG.none()
    case Con{+node, rest}:
      Bool.pick(U32, acceptable(s, node, random), node, choice(rest, s, random))

def placed_if(missing: Bool, +node: U32, +s: GG.St, +piece: U32) -> GG.St:
  match missing:
    case True{}:
      GG.say(s)
    case False{}:
      GG.place_piece(s, node, (piece >> 16n : U32), (piece .&. 65535 : U32))

def placed(+node: U32, +s: GG.St, +piece: U32) -> GG.St:
  placed_if(U32.is_eq(node, GG.none()), node, s, piece)

def place_one(+p: Picks, +piece: U32, +random: Bool) -> GG.Got:
  match p:
    case Picks{+order, +s}:
      +node = choice(order, s, random)
      GG.Got{node, placed(node, s, piece)}

# Placing set pieces: the state and whether a piece found no node (which ends the pass).
type Placing is Data:
  Placing{st: GG.St, stopped: Bool}

def placing_of(+g: GG.Got) -> Placing:
  match g:
    case GG.Got{+v, +s}:
      Placing{s, U32.is_eq(v, GG.none())}

def place_all(pieces: List<&2, U32>, +p: Placing, +order: List<&2, U32>, +random: Bool) -> GG.St:
  match pieces:
    case Nil{}:
      match p:
        case Placing{+s, _}:
          s
    case Con{+piece, rest}:
      match p:
        case Placing{+s, +stopped}:
          match stopped:
            case True{}:
              s
            case False{}:
              place_all(rest, placing_of(place_one(shuffled(s, order), piece, random)), order, random)

def pieces_of_graph(task_graph: Bool, +s: GG.St, +g: U32, +level: W.Summary) -> GG.St:
  match task_graph:
    case True{}:
      +task = GG.gf(s, g, GG.g_part())
      +order = GG.node_order(s, g)
      place_all(random_set_pieces(level, task), Placing{place_all(set_pieces(level, task), Placing{s, False{}}, order, False{}), False{}}, order, True{})
    case False{}:
      s

def pieces_loop(graphs: List<&2, U32>, +s: GG.St, +level: W.Summary) -> GG.St:
  match graphs:
    case Nil{}:
      s
    case Con{+g, rest}:
      pieces_loop(rest, pieces_of_graph(U32.is_eq(GG.gf(s, g, GG.g_kind()), GG.k_task()), s, g, level), level)

# Story:InsertAdditionalSetPieces over the given graphs (pairs order).
def insert_set_pieces(+s: GG.St, +graphs: List<&2, U32>, +level: W.Summary) -> GG.St:
  +before = GG.rng_of(s)
  GG.returned(pieces_loop(graphs, s, level), GG.f_insert_additional_set_pieces(), before)
