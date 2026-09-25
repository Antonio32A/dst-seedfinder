import Base
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ./centi.bend as GC
import ../worldsim/grid.bend as GR
import ../ocean/ents.bend as OE
import ../filters/world.bend as WD
import ../data/gen_tags.bend as GT
import ./job.bend as GJ

# The filters' world (filters/world.bend) of a generated world, equal to what WD.of_bytes reads from the dump of the
# same world's savedata: the dump mod writes every position with printf("%.2f") (trailing zeros cut), and
# AddWorldEntities adds the pocket dimension containers at (0, 0) when the world has none.

def magnitude(+k: U32) -> U32:
  Bool.pick(U32, (k >= 2147483648 : U32), (0 - k : U32), k)

def whole_flag(+k: U32) -> U32:
  Bool.to_u32(U32.is_zero(U32.mod(magnitude(k), 100)))

def inst_of(+v: U32, +index: U32, +xk: U32, +zk: U32) -> WD.Inst:
  WD.Inst{v, index, FA.div(FR.from_i32(xk), GC.hundred()), FA.div(FR.from_i32(zk), GC.hundred()), xk, zk,
    (whole_flag(xk) .|. (whole_flag(zk) << 1n) : U32)}

def insts_of(ents: List<&2, OE.Ent>, +v: U32, +index: U32, +windows: Bool) -> List<&2, WD.Inst>:
  match ents:
    case Nil{}:
      Nil{}
    case Con{OE.Ent{_, +x, +z, _, _}, rest}:
      inst_of(v, index, GC.centi(x, windows), GC.centi(z, windows)) <> insts_of(rest, v, (index + 1 : U32), windows)

def is_pocket(+v: U32) -> Bool:
  U32.is_eq(v, GT.vocab_shadow_container()) || U32.is_eq(v, GT.vocab_rabbitkinghorn_container())

def pocket_default(pocket: Bool, +v: U32) -> List<&2, WD.Inst>:
  match pocket:
    case True{}:
      [WD.Inst{v, 0, FR.zero(), FR.zero(), 0, 0, 3}]
    case False{}:
      Nil{}

def group_of(ents: List<&2, OE.Ent>, +v: U32, +windows: Bool) -> List<&2, WD.Inst>:
  match ents:
    case Nil{}:
      pocket_default(is_pocket(v), v)
    case Con{+e, +rest}:
      insts_of(e <> rest, v, 0, windows)

def slot_set(fits: Bool, a: Array<U32>, +sid: U32, +v: U32) -> Array<U32>:
  match fits:
    case True{}:
      a[sid] <- v
      a
    case False{}:
      a

def sid_slots() -> U32:
  U32.pow(2, GT.sid_depth())

def lookup_fill(sids: List<&2, U32>, +v: U32, a: Array<U32>) -> Array<U32>:
  match sids:
    case Nil{}:
      a
    case Con{+sid, rest}:
      lookup_fill(rest, (v + 1 : U32), slot_set((sid < sid_slots() : U32), a, sid, v))

def no_vocab() -> U32:
  65535

# The catalog index of every string id (no_vocab() for the rest).
def lookup() -> Array<U32>:
  lookup_fill(GT.vocab_prefab_sids(), 0, Array.new(U32, GT.sid_depth(), no_vocab()))

def bucket_depth() -> Nat:
  9n

def bucket_put(known: Bool, got: Array<List<&2, OE.Ent>> & List<&2, OE.Ent>, +v: U32, +e: OE.Ent) -> Array<List<&2, OE.Ent>>:
  match known:
    case True{}:
      (a, old) = got
      Array.set(List<&2, OE.Ent>, a, v, e <> old)
    case False{}:
      (a, old) = got
      Array.set(List<&2, OE.Ent>, a, v, old)

def bucket_add(got: Array<U32> & U32, a: Array<List<&2, OE.Ent>>, +e: OE.Ent) -> Array<U32> & Array<List<&2, OE.Ent>>:
  (ids, +v) = got
  (ids, bucket_put(U32.is_ne(v, no_vocab()), Array.swap(List<&2, OE.Ent>, a, v, Nil{}), v, e))

def bucket_step(got: Array<U32> & Array<List<&2, OE.Ent>>, +e: OE.Ent) -> Array<U32> & Array<List<&2, OE.Ent>>:
  (ids, a) = got
  bucket_add(ids[OE.prefab_of(e)], a, e)

# savedata.ents per catalog prefab, oldest first, from the newest-first entity list.
def buckets(ents: List<&2, OE.Ent>, got: Array<U32> & Array<List<&2, OE.Ent>>) -> Array<U32> & Array<List<&2, OE.Ent>>:
  match ents:
    case Nil{}:
      got
    case Con{+e, rest}:
      buckets(rest, bucket_step(got, e))

type Grouped is Type:
  Grouped{groups: List<&2, List<&2, WD.Inst>>, wormholes: List<&2, OE.Ent>}

def groups_loop(n: Nat, got: Array<List<&2, OE.Ent>> & List<&2, OE.Ent>, +v: U32, +windows: Bool, +acc: List<&2, List<&2, WD.Inst>>, +wormholes: List<&2, OE.Ent>) -> Grouped:
  match n:
    case 0n:
      Grouped{List.reverse(&2, List<&2, WD.Inst>, acc), wormholes}
    case 1n+p:
      (a, +ents) = got
      groups_loop(p, Array.swap(List<&2, OE.Ent>, a, (v + 1 : U32), Nil{}), (v + 1 : U32), windows, group_of(ents, v, windows) <> acc,
        Bool.pick(List<&2, OE.Ent>, U32.is_eq(v, GT.vocab_wormhole()), ents, wormholes))

def ent_id(+e: OE.Ent) -> U32:
  match e:
    case OE.Ent{_, _, _, +id, _}:
      id

def ent_target(+e: OE.Ent) -> U32:
  match e:
    case OE.Ent{_, _, _, _, +target}:
      target

def last_with_id(ents: List<&2, OE.Ent>, +id: U32, +i: U32, +found: U32) -> U32:
  match ents:
    case Nil{}:
      found
    case Con{+e, rest}:
      last_with_id(rest, id, (i + 1 : U32), Bool.pick(U32, U32.is_eq(ent_id(e), id) && U32.is_ne(ent_target(e), 0), i, found))

def link_if(+exit: U32, +entry: U32, +groups: List<&2, List<&2, WD.Inst>>, +rest: List<&2, WD.Link>) -> List<&2, WD.Link>:
  Bool.pick(List<&2, WD.Link>, U32.is_eq(exit, no_vocab()), rest,
    WD.Link{WD.instance_at(groups, GT.vocab_wormhole(), entry), WD.instance_at(groups, GT.vocab_wormhole(), exit)} <> rest)

def links_loop(ents: List<&2, OE.Ent>, +all: List<&2, OE.Ent>, +groups: List<&2, List<&2, WD.Inst>>, +i: U32) -> List<&2, WD.Link>:
  match ents:
    case Nil{}:
      Nil{}
    case Con{+e, rest}:
      +more = links_loop(rest, all, groups, (i + 1 : U32))
      Bool.pick(List<&2, WD.Link>, U32.is_zero(ent_target(e)), more,
        link_if(last_with_id(all, ent_target(e), 0, no_vocab()), i, groups, more))

# The directed wormhole links in savedata order: every wormhole with a teleporter target to the wormhole of that id.
def links(+wormholes: List<&2, OE.Ent>, +groups: List<&2, List<&2, WD.Inst>>) -> List<&2, WD.Link>:
  links_loop(wormholes, wormholes, groups, 0)

def pair_word(+hold: U32, +tile: U32) -> U32:
  ((hold << 16n) .|. tile : U32)

# The tiles from cell c down to cell 0, two u16 per word (the even cell in the low half), prepended to acc.
def packed_loop(n: Nat, got: GR.Grid & U32, +c: U32, +hold: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      (g, +cell) = got
      +even = U32.is_zero((c .&. 1 : U32))
      packed_loop(p, GR.get(g, (c - 1 : U32)), (c - 1 : U32), Bool.pick(U32, even, 0, GR.tile_of(cell)),
        Bool.pick(List<&2, U32>, even, pair_word(hold, GR.tile_of(cell)) <> acc, acc))

def packed(g: GR.Grid, +n: U32) -> List<&2, U32>:
  packed_loop(U32.to_nat(n), GR.get(g, (n - 1 : U32)), (n - 1 : U32), 0, Nil{})

def world_of_groups(gr: Grouped, +seed: U32, +w: U32, +tiles: List<&2, U32>) -> WD.World:
  match gr:
    case Grouped{+groups, +wormholes}:
      WD.World{seed, w, w, GT.vocab_tile_ids(), groups, links(wormholes, groups), tiles}

def grouped(got: Array<U32> & Array<List<&2, OE.Ent>>, +windows: Bool) -> Grouped:
  (_, a) = got
  groups_loop(List.length(&2, U32, GT.vocab_prefab_sids()), Array.swap(List<&2, OE.Ent>, a, 0, Nil{}), 0, windows, Nil{}, Nil{})

# The filters' world of a generated world (the seed's world attempt on the platform).
def world(+seed: U32, +windows: Bool, final: GJ.Final) -> WD.World:
  match final:
    case GJ.Final{g, _, +ents, +w}:
      +tiles = packed(g, (w * w : U32))
      world_of_groups(grouped(buckets(ents, (lookup(), Array.new(List<&2, OE.Ent>, bucket_depth(), Nil{}))), windows), seed, w, tiles)
