import Base
import ../rng/pcg.bend as Pcg
import ../lua/math_random.bend as MathRandom
import ../lua/table.bend as LuaTable
import ../storygen/order.bend as StoryOrder
import ../f64/repr.bend as F64Repr
import ../f64/arith.bend as F64Arith
import ../f64/cmp.bend as F64Cmp
import ../f64/random.bend as F64Random
import ../data/blob.bend as Blob
import ../data/strings.bend as Strings
import ../data/layouts.bend as Layouts
import ../data/constants.bend as Constants
import ../data/enums.bend as Enums

# object_layout.lua's LayoutForDefinition + ConvertLayoutToEntitylist on the baked layouts (data/layouts.bend): area
# contents with their math.random draws, the Lua 5.1 table orders of to_add and of the mutated layout.layout and
# layout.count (rebuilt from their baked node layouts with lua/table.bend), defs, StaticLayout and the shape layouts.

# One object of a layout's entity list: prefab string id (data/strings.bend), x, y as the Lua doubles, and the
# object's property ref (0 none, else a row + 1 of data/layout_props.bend, as data/layouts.bend object_props;
# 4294967295 for the monkeyisland_dockgen_safeareacenter record, whose data is its area object's width and height).
type Item is Data:
  Item{prefab: U32, x: F64Repr.F64, y: F64Repr.F64, props: U32}

type Pos is Data:
  Pos{x: F64Repr.F64, y: F64Repr.F64, props: U32}

type Obj is Data:
  Obj{pos: Pos, w: F64Repr.F64, h: F64Repr.F64}

type Group is Data:
  Group{key: U32, objs: List<&2, Obj>}

type Res is Data:
  RName{id: U32}
  RPlaced{id: U32, x: F64Repr.F64, y: F64Repr.F64}

type Add is Data:
  Add{key: U32, poss: List<&2, Pos>}

type Entry is Data:
  Entry{key: U32, value: U32}

type Job is Data:
  Job{kind: U32, value: U32, obj: Obj}

type Walk is Type:
  Walk{table: LuaTable.Table, step: LuaTable.Step, rng: Pcg.Rng}

def none() -> U32:
  4294967295

def skey(+id: U32) -> LuaTable.TKey:
  LuaTable.string_key(Strings.hash(id), id)

def key_id(+k: LuaTable.TKey) -> U32:
  match k:
    case LuaTable.TKey{_, _, +b}:
      b

def f64_of(got: U32 & U32) -> F64Repr.F64:
  (+h, +l) = got
  F64Repr.F64{h, l}

def fixed(+u: U32) -> F64Repr.F64:
  F64Arith.mul(F64Repr.from_i32(Blob.signed(u)), F64Repr.F64{1065353216, 0})

def ratio(+a: U32, +b: U32) -> F64Repr.F64:
  F64Arith.div(F64Repr.from_u32(a), F64Repr.from_u32(b))

def count_of(+xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

# layout.layout of a variant (data/layouts.bend groups) in pairs() order.

def prop_scan(pairs: List<&2, U32>, +k: U32, +found: U32) -> U32:
  match pairs:
    case Con{+i, Con{+ref, rest}}:
      prop_scan(rest, k, Bool.pick(U32, U32.is_eq(i, k), ref, found))
    case _:
      found

def fixed_or_zero(sized: Bool, +u: U32) -> F64Repr.F64:
  match sized:
    case True{}:
      fixed(u)
    case False{}:
      F64Repr.zero()

def object_of(+sized: Bool, +props: List<&2, U32>, +row: List<&2, U32>, +k: U32) -> Obj:
  Obj{Pos{fixed(Blob.at(row, 0)), fixed(Blob.at(row, 1)), prop_scan(props, k, 0)}, fixed_or_zero(sized, Blob.at(row, 2)),
    fixed_or_zero(sized, Blob.at(row, 3))}

def objs_loop(n: Nat, +sized: Bool, +props: List<&2, U32>, +row: List<&2, U32>, +k: U32) -> List<&2, Obj>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      object_of(sized, props, row, k) <> objs_loop(p, sized, props, Blob.drop(row, Bool.pick(U32, sized, 4, 2)), (k + 1 : U32))

def groups_loop(n: Nat, +props: List<&2, U32>, +row: List<&2, U32>, +k: U32) -> List<&2, Group>:
  match n row:
    case 1n+p Con{+key, Con{+count, Con{+sized, +rest}}}:
      +big = U32.is_ne(sized, 0)
      Group{key, objs_loop(U32.to_nat(count), big, props, rest, k)}
        <> groups_loop(p, props, Blob.drop(rest, (count * Bool.pick(U32, big, 4, 2) : U32)), (k + count : U32))
    case _ _:
      Nil{}

def groups_of(+v: U32) -> List<&2, Group>:
  +row = Layouts.groups(v)
  groups_loop(List.length(&2, U32, row), Layouts.object_props(v), row, 0)

def pos_items(poss: List<&2, Pos>, +key: U32) -> List<&2, Item>:
  match poss:
    case Nil{}:
      Nil{}
    case Con{Pos{+x, +y, +props}, rest}:
      Item{key, x, y, props} <> pos_items(rest, key)

def obj_poss(objs: List<&2, Obj>) -> List<&2, Pos>:
  match objs:
    case Nil{}:
      Nil{}
    case Con{Obj{+pos, _, _}, rest}:
      pos <> obj_poss(rest)

def groups_items(groups: List<&2, Group>) -> List<&2, Item>:
  match groups:
    case Nil{}:
      Nil{}
    case Con{Group{+key, +objs}, rest}:
      List.append(&2, Item, pos_items(obj_poss(objs), key), groups_items(rest))

# util.lua helpers on Lua arrays of string ids, with the game's draws (a draw of 2^32 - 1 reads past the end: nil).

def lits(+c: U32) -> List<&2, U32>:
  Layouts.closure_literals(c)

def part(+c: U32, +from: U32, +count: U32) -> List<&2, U32>:
  Blob.first(Blob.drop(lits(c), from), count)

def names(xs: List<&2, U32>) -> List<&2, Res>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      RName{x} <> names(rest)

def element_if(inside: Bool, +xs: List<&2, U32>, +r: U32) -> List<&2, U32>:
  match inside:
    case True{}:
      [Blob.at(xs, (r - 1 : U32))]
    case False{}:
      Nil{}

def element_of(+xs: List<&2, U32>, +r: U32) -> List<&2, U32>:
  element_if(Bool.and((r >= 1 : U32), (r <= count_of(xs) : U32)), xs, r)

def picked_one(got: U32 & Pcg.Rng, +xs: List<&2, U32>) -> List<&2, U32> & Pcg.Rng:
  (+r, s) = got
  (element_of(xs, r), s)

# PickSome(1, choices)
def pick_one(+xs: List<&2, U32>, s: Pcg.Rng) -> List<&2, U32> & Pcg.Rng:
  picked_one(MathRandom.random_upto(s, count_of(xs)), xs)

def taken(pending: Bool, +xs: List<&2, U32>, +r: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match pending:
    case True{}:
      List.append(&2, U32, element_of(xs, r), acc)
    case False{}:
      acc

def dups_loop(n: Nat, +xs: List<&2, U32>, +acc: List<&2, U32>, got: U32 & Pcg.Rng, +pending: Bool) -> List<&2, U32> & Pcg.Rng:
  match n:
    case 0n:
      (+r, s) = got
      (List.reverse(&2, U32, taken(pending, xs, r, acc)), s)
    case 1n+p:
      (+r, s) = got
      dups_loop(p, xs, taken(pending, xs, r, acc), MathRandom.random_upto(s, count_of(xs)), True{})

# PickSomeWithDups(num, choices)
def dups(+num: U32, +xs: List<&2, U32>, s: Pcg.Rng) -> List<&2, U32> & Pcg.Rng:
  dups_loop(U32.to_nat(num), xs, Nil{}, (0, s), False{})

def dups_drawn(got: U32 & Pcg.Rng, +xs: List<&2, U32>) -> List<&2, U32> & Pcg.Rng:
  (+num, s) = got
  dups(num, xs, s)

# PickSomeWithDups(math.random(m, n), choices)
def dups_range(+m: U32, +n: U32, +xs: List<&2, U32>, s: Pcg.Rng) -> List<&2, U32> & Pcg.Rng:
  dups_drawn(MathRandom.random_range(s, m, n), xs)

def item_drawn(got: U32 & Pcg.Rng, +xs: List<&2, U32>) -> U32 & Pcg.Rng:
  (+r, s) = got
  (StoryOrder.nth_or_last(xs, (r - 1 : U32), 0), s)

# GetRandomItem(choices) of a Lua array.
def random_item(+xs: List<&2, U32>, s: Pcg.Rng) -> U32 & Pcg.Rng:
  item_drawn(MathRandom.random_upto(s, count_of(xs)), xs)

def below_drawn(got: F64Repr.F64 & Pcg.Rng, +limit: F64Repr.F64) -> Bool & Pcg.Rng:
  (+x, s) = got
  (F64Cmp.lt(x, limit), s)

# math.random() < num / den
def chance(s: Pcg.Rng, +num: U32, +den: U32) -> Bool & Pcg.Rng:
  below_drawn(F64Random.random(s), ratio(num, den))

def keep_if(hit: Bool, +id: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      id <> acc
    case False{}:
      acc

def tries(n: Nat, +id: U32, +num: U32, +den: U32, +acc: List<&2, U32>, got: Bool & Pcg.Rng, +pending: Bool) -> List<&2, U32> & Pcg.Rng:
  match n:
    case 0n:
      (+hit, s) = got
      (keep_if(Bool.and(pending, hit), id, acc), s)
    case 1n+p:
      (+hit, s) = got
      tries(p, id, num, den, keep_if(Bool.and(pending, hit), id, acc), chance(s, num, den), True{})

# n times: if math.random() < num / den then table.insert(acc, id) (acc reversed).
def tries_on(got: List<&2, U32> & Pcg.Rng, n: Nat, +id: U32, +num: U32, +den: U32) -> List<&2, U32> & Pcg.Rng:
  (+acc, s) = got
  tries(n, id, num, den, acc, (False{}, s), False{})

def ended(got: List<&2, U32> & Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  (+acc, s) = got
  (names(List.reverse(&2, U32, acc)), s)

def as_res(got: List<&2, U32> & Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  (+xs, s) = got
  (names(xs), s)

def only_if(got: Bool & Pcg.Rng, +id: U32) -> List<&2, Res> & Pcg.Rng:
  (+hit, s) = got
  (names(keep_if(hit, id, Nil{})), s)

def either(got: Bool & Pcg.Rng, +c: U32) -> List<&2, Res> & Pcg.Rng:
  (+hit, s) = got
  (names([Bool.pick(U32, hit, Blob.at(lits(c), 0), Blob.at(lits(c), 1))]), s)

def half_drawn(got: F64Repr.F64 & Pcg.Rng, +above: Bool) -> Bool & Pcg.Rng:
  (+x, s) = got
  (Bool.pick(Bool, above, F64Cmp.gt(x, F64Repr.half()), F64Cmp.ge(x, F64Repr.half())), s)

# math.random() >= .5 (above False) or math.random() > 0.5 (above True)
def half(s: Pcg.Rng, +above: Bool) -> Bool & Pcg.Rng:
  half_drawn(F64Random.random(s), above)

def repeat(n: Nat, +id: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      repeat(p, id, id <> acc)

def grass_stumps(got: U32 & Pcg.Rng, +grass: List<&2, U32>) -> List<&2, Res> & Pcg.Rng:
  (+m, s) = got
  ended(tries_on((grass, s), U32.to_nat(m), Blob.at(lits(25), 1), 1, 2))

# layouts.lua grass_area
def grass_area(got: U32 & Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  (+k, s) = got
  grass_stumps(MathRandom.random_upto(s, 3), repeat(U32.to_nat(k), Blob.at(lits(25), 0), Nil{}))

def waterlogged_rest(got: List<&2, U32> & Pcg.Rng, +l: List<&2, U32>) -> List<&2, U32> & Pcg.Rng:
  (+acc, s) = got
  vines = tries_on((Blob.at(l, 3) <> Blob.at(l, 2) <> acc, s), 1n, Blob.at(l, 4), 1, 5)
  tries_on(tries_on(tries_on(tries_on(vines, 3n, Blob.at(l, 5), 3, 10), 3n, Blob.at(l, 6), 3, 10), 2n, Blob.at(l, 7), 3, 10), 10n, Blob.at(l, 8), 2, 5)

# layouts.lua waterlogged_tree_area
def waterlogged_area(s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  +l = lits(26)
  ended(waterlogged_rest(tries_on(([Blob.at(l, 0)], s), 6n, Blob.at(l, 1), 1, 10), l))

def monkey_tail(got: Bool & Pcg.Rng, +acc: List<&2, U32>) -> List<&2, Res> & Pcg.Rng:
  (+hit, s) = got
  +l = lits(27)
  +always = {[Blob.at(l, 6), Blob.at(l, 7), Blob.at(l, 8), Blob.at(l, 9)] : List<&2, U32>}
  (names(List.append(&2, U32, acc, List.append(&2, U32, always, keep_if(hit, Blob.at(l, 10), Nil{})))), s)

def monkey_picked(got: List<&2, U32> & Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  (+acc, s) = got
  monkey_tail(half(s, True{}), acc)

# layouts.lua monkeyisland_prefabs_area(area)
def monkey_area(+area: F64Repr.F64, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  +num = F64Repr.to_i32(F64Repr.floor(F64Arith.add(F64Arith.div(area, F64Repr.from_u32(5)), F64Repr.half())))
  monkey_picked(dups(num, part(27, 0, 6), s))

def goodie_appended(got: U32 & Pcg.Rng, +acc: List<&2, U32>) -> List<&2, U32> & Pcg.Rng:
  (+r, s) = got
  (List.append(&2, U32, acc, element_of(lits(43), r)), s)

def goodie_pick(hit: Bool, +acc: List<&2, U32>, s: Pcg.Rng) -> List<&2, U32> & Pcg.Rng:
  match hit:
    case True{}:
      goodie_appended(MathRandom.random_upto(s, 3), acc)
    case False{}:
      (acc, s)

def goodie_on(got: Bool & Pcg.Rng, +acc: List<&2, U32>) -> List<&2, U32> & Pcg.Rng:
  (+hit, s) = got
  goodie_pick(hit, acc, s)

def goodies_loop(n: Nat, got: List<&2, U32> & Pcg.Rng) -> List<&2, U32> & Pcg.Rng:
  match n:
    case 0n:
      got
    case 1n+p:
      (+acc, s) = got
      goodies_loop(p, goodie_on(chance(s, 1, 2), acc))

def goodies(hit: Bool, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match hit:
    case True{}:
      as_res(goodies_loop(3n, goodie_appended(MathRandom.random_upto(s, 3), Nil{})))
    case False{}:
      (Nil{}, s)

def goodies_drawn(got: Bool & Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  (+hit, s) = got
  goodies(hit, s)

def sculpture_pick(hit: Bool, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match hit:
    case True{}:
      as_res(dups(1, lits(34), s))
    case False{}:
      (Nil{}, s)

def sculpture_drawn(got: U32 & Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  (+r, s) = got
  sculpture_pick(U32.is_eq(r, 1), s)

def pumpkin_drawn(got: U32 & Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  (_, s) = got
  (names(lits(30)), s)

def placed_area(+obj: Obj) -> List<&2, Res>:
  match obj:
    case Obj{Pos{+x, +y, _}, _, _}:
      [RPlaced{Blob.at(lits(29), 0), x, y}]

def cooking_drawn(got: List<&2, U32> & Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  (+xs, s) = got
  (names(List.append(&2, U32, part(8, 0, 3), xs)), s)

def fishing_second(got: U32 & Pcg.Rng, +first: U32) -> List<&2, Res> & Pcg.Rng:
  (+second, s) = got
  (names([Blob.at(lits(10), 0), Blob.at(lits(10), 1), first, second]), s)

def fishing_first(got: U32 & Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  (+first, s) = got
  fishing_second(random_item(part(10, 8, 5), s), first)

# Boons 0..7 (map/boons.lua, Hallowed Nights off).
def boon_a(+c: U32, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match c:
    case 0:
      as_res(pick_one(part(0, 4, 2), s))
    case 1:
      as_res(dups_range(3, 5, part(1, 2, 1), s))
    case 2:
      as_res(pick_one(part(2, 3, 9), s))
    case 3:
      as_res(dups_range(3, 5, part(3, 2, 5), s))
    case 4:
      as_res(pick_one(part(4, 5, 2), s))
    case 5:
      as_res(dups_range(3, 5, part(5, 5, 1), s))
    case 7:
      as_res(dups_range(3, 5, part(7, 6, 1), s))
    case _:
      (Nil{}, s)

# Boons 8..12.
def boon_b(+c: U32, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match c:
    case 8:
      cooking_drawn(dups_range(3, 4, part(8, 3, 3), s))
    case 10:
      fishing_first(random_item(part(10, 2, 6), s))
    case 11:
      (Nil{}, s)
    case _:
      (names(lits(c)), s)

def boon_c_kind(dup: Bool, +c: U32, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match dup:
    case True{}:
      as_res(dups_range(3, 5, lits(c), s))
    case False{}:
      as_res(pick_one(lits(c), s))

# Boons 13..23: PickSome(1, ...) (odd, 21, 22) or PickSomeWithDups(math.random(3, 5), ...) (14..20 even).
def boon_c(+c: U32, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  boon_c_kind(Bool.and(U32.is_eq((c .&. 1 : U32), 0), (c <= 20 : U32)), c, s)

# layouts.lua area functions 25..34.
def layouts_a(+c: U32, +area: F64Repr.F64, +obj: Obj, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match c:
    case 25:
      grass_area(MathRandom.random_upto(s, 4))
    case 26:
      waterlogged_area(s)
    case 27:
      monkey_area(area, s)
    case 28:
      (names(lits(28)), s)
    case 29:
      (placed_area(obj), s)
    case 30:
      pumpkin_drawn(MathRandom.random_upto(s, 3))
    case 31:
      as_res(dups_range(2, 4, lits(31), s))
    case 34:
      sculpture_drawn(MathRandom.random_upto(s, 2))
    case _:
      as_res(dups(1, lits(c), s))

# layouts.lua area functions 35..44.
def layouts_b(+c: U32, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match c:
    case 39:
      either(half(s, False{}), c)
    case 40:
      either(half(s, False{}), c)
    case 41:
      either(half(s, False{}), c)
    case 42:
      either(half(s, False{}), c)
    case 43:
      goodies_drawn(chance(s, 3, 4))
    case 44:
      only_if(chance(s, 3, 10), Blob.at(lits(44), 0))
    case _:
      only_if(chance(s, 9, 10), Blob.at(lits(c), 0))

def area_high(high: Bool, +c: U32, +area: F64Repr.F64, +obj: Obj, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match high:
    case True{}:
      layouts_b(c, s)
    case False{}:
      layouts_a(c, area, obj, s)

def area_mid(mid: Bool, +c: U32, +area: F64Repr.F64, +obj: Obj, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match mid:
    case True{}:
      area_high((c >= 35 : U32), c, area, obj, s)
    case False{}:
      boon_c(c, s)

def boon_high(high: Bool, +c: U32, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match high:
    case True{}:
      boon_b(c, s)
    case False{}:
      boon_a(c, s)

def area_low(low: Bool, +c: U32, +area: F64Repr.F64, +obj: Obj, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match low:
    case True{}:
      boon_high((c >= 8 : U32), c, s)
    case False{}:
      area_mid((c >= 24 : U32), c, area, obj, s)

# A layout area closure (data/closures.bend category 2) called as area_contents(width * height, data).
def area_run(+c: U32, +area: F64Repr.F64, +obj: Obj, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  area_low((c < 13 : U32), c, area, obj, s)

# ConvertLayoutToEntitylist's areas: every area object in pairs(layout.layout) x ipairs order, its contents, and
# their positions (x then y: (c - size / 2) + math.random() * size), collected into to_add.

def area_scan(n: Nat, +row: List<&2, U32>, +key: U32) -> Entry:
  match n row:
    case 1n+p Con{+k, Con{+kind, Con{+value, +rest}}}:
      Bool.pick(Entry, U32.is_eq(k, key), Entry{kind, value}, area_scan(p, rest, key))
    case _ _:
      Entry{none(), 0}

def objs_jobs(objs: List<&2, Obj>, +area: Entry) -> List<&2, Job>:
  match objs:
    case Nil{}:
      Nil{}
    case Con{+obj, rest}:
      match area:
        case Entry{+kind, +value}:
          Job{kind, value, obj} <> objs_jobs(rest, Entry{kind, value})

def area_jobs(groups: List<&2, Group>, +areas: List<&2, U32>) -> List<&2, Job>:
  match groups:
    case Nil{}:
      Nil{}
    case Con{Group{+key, +objs}, rest}:
      List.append(&2, Job, objs_jobs(objs, area_scan(List.length(&2, U32, areas), areas, key)), area_jobs(rest, areas))

def area_closure(on: Bool, +c: U32, +area: F64Repr.F64, +obj: Obj, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match on:
    case True{}:
      area_run(c, area, obj, s)
    case False{}:
      (Nil{}, s)

def obj_area(+obj: Obj) -> F64Repr.F64:
  match obj:
    case Obj{_, +w, +h}:
      F64Arith.mul(w, h)

def contents_of(list: Bool, +kind: U32, +value: U32, +obj: Obj, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  match list:
    case True{}:
      (names(Layouts.area_lists(value)), s)
    case False{}:
      area_closure(U32.is_eq(kind, Layouts.kind_closure()), value, obj_area(obj), obj, s)

def contents(+kind: U32, +value: U32, +obj: Obj, s: Pcg.Rng) -> List<&2, Res> & Pcg.Rng:
  contents_of(U32.is_eq(kind, Layouts.kind_list()), kind, value, obj, s)

def head_is(adds: List<&2, Add>, +key: U32) -> Bool:
  match adds:
    case Con{Add{+k, _}, _}:
      U32.is_eq(k, key)
    case _:
      False{}

def add_pos(adds: List<&2, Add>, +hit: Bool, +key: U32, +pos: Pos) -> List<&2, Add>:
  match adds hit:
    case Con{Add{+k, +ps}, +rest} True{}:
      Add{k, List.append(&2, Pos, ps, [pos])} <> rest
    case Con{+h, +rest} False{}:
      h <> add_pos(rest, head_is(rest, key), key, pos)
    case Nil{} _:
      [Add{key, [pos]}]

def spot(+c: F64Repr.F64, +size: F64Repr.F64, +r: F64Repr.F64) -> F64Repr.F64:
  F64Arith.add(F64Arith.sub(c, F64Arith.div(size, F64Repr.two())), F64Arith.mul(r, size))

def name_placed_y(got: F64Repr.F64 & Pcg.Rng, +rx: F64Repr.F64, +obj: Obj, +adds: List<&2, Add>, +id: U32) -> List<&2, Add> & Pcg.Rng:
  (+ry, s) = got
  match obj:
    case Obj{Pos{+x, +y, +props}, +w, +h}:
      (add_pos(adds, head_is(adds, id), id, Pos{spot(x, w, rx), spot(y, h, ry), props}), s)

def name_placed(got: F64Repr.F64 & Pcg.Rng, +obj: Obj, +adds: List<&2, Add>, +id: U32) -> List<&2, Add> & Pcg.Rng:
  (+rx, s) = got
  name_placed_y(F64Random.random(s), rx, obj, adds, id)

def place_one(+r: Res, +obj: Obj, +adds: List<&2, Add>, s: Pcg.Rng) -> List<&2, Add> & Pcg.Rng:
  match r:
    case RName{+id}:
      name_placed(F64Random.random(s), obj, adds, id)
    case RPlaced{+id, +x, +y}:
      (add_pos(adds, head_is(adds, id), id, Pos{x, y, none()}), s)

def place_loop(rs: List<&2, Res>, +obj: Obj, got: List<&2, Add> & Pcg.Rng) -> List<&2, Add> & Pcg.Rng:
  match rs:
    case Nil{}:
      got
    case Con{+r, rest}:
      (+adds, s) = got
      place_loop(rest, obj, place_one(r, obj, adds, s))

def placed(got: List<&2, Res> & Pcg.Rng, +obj: Obj, +adds: List<&2, Add>) -> List<&2, Add> & Pcg.Rng:
  (+rs, s) = got
  place_loop(rs, obj, (adds, s))

def jobs_loop(jobs: List<&2, Job>, got: List<&2, Add> & Pcg.Rng) -> List<&2, Add> & Pcg.Rng:
  match jobs:
    case Nil{}:
      got
    case Con{Job{+kind, +value, +obj}, rest}:
      (+adds, s) = got
      jobs_loop(rest, placed(contents(kind, value, obj, s), obj, adds))

# Lua tables rebuilt from a baked node layout (data/layouts.bend layout_snapshot / count_snapshot): string keys,
# U32 values looked up by key in `entries`.

def entry_value(entries: List<&2, Entry>, +key: U32, +found: U32) -> U32:
  match entries:
    case Nil{}:
      found
    case Con{Entry{+k, +v}, rest}:
      entry_value(rest, key, Bool.pick(U32, U32.is_eq(k, key), v, found))

def snapshot_node(nil: Bool, +key: U32, +link: U32, +live: U32, +entries: List<&2, Entry>) -> LuaTable.Node:
  match nil:
    case True{}:
      LuaTable.Node{0, 0, 0, link, 0, 0}
    case False{}:
      LuaTable.Node{2, Strings.hash(key), key, link, live, Bool.pick(U32, U32.is_zero(live), 0, entry_value(entries, key, 0))}

def fill_nodes(n: Nat, nodes: Array<U32>, +row: List<&2, U32>, +i: U32, +entries: List<&2, Entry>) -> Array<U32>:
  match n row:
    case 1n+p Con{+key, Con{+next, Con{+live, +rest}}}:
      fill_nodes(p, LuaTable.write_node(nodes, i, snapshot_node(Blob.is_none(key), key, Bool.pick(U32, Blob.is_none(next), 0, (next + 1 : U32)), live, entries)), rest, (i + 1 : U32), entries)
    case _ _:
      nodes

def snapshot_table(+row: List<&2, U32>, +entries: List<&2, Entry>) -> LuaTable.Table:
  +lsize = Blob.at(row, 0)
  LuaTable.Table{fill_nodes(List.length(&2, U32, row), LuaTable.empty_nodes(lsize), Blob.drop(row, 3), 0, entries),
    LuaTable.new_cells(LuaTable.cell_capacity(0)), lsize, U32.is_ne(Blob.at(row, 2), 0), 0, LuaTable.cell_capacity(0), Blob.at(row, 1)}

def keep_entry(hit: Bool, +e: Entry, +acc: List<&2, Entry>) -> List<&2, Entry>:
  match hit:
    case True{}:
      e <> acc
    case False{}:
      acc

def entries_loop(n: Nat, got: LuaTable.Table & LuaTable.Step, +pos: U32, +acc: List<&2, Entry>) -> List<&2, Entry>:
  match n:
    case 0n:
      List.reverse(&2, Entry, acc)
    case 1n+p:
      (t, +step) = got
      match step:
        case LuaTable.Step{+status, +key, +value}:
          entries_loop(p, LuaTable.entry(t, (pos + 1 : U32)), (pos + 1 : U32), keep_entry(U32.is_eq(status, 1), Entry{key_id(key), value}, acc))

# The (key, value) entries of a table in pairs() order.
def entries_of(got: LuaTable.Table & U32) -> List<&2, Entry>:
  (t, +total) = got
  entries_loop(U32.to_nat(total), LuaTable.entry(t, 0), 0, Nil{})

# layout.defs: for each key of pairs(t) with defs, t[defs[k][math.random(1, #defs[k])]] = v and t[k] = nil, the
# traversal continuing with next(t, k) on the changed table.

def choices_scan(n: Nat, +row: List<&2, U32>, +key: U32) -> List<&2, U32>:
  match n row:
    case 1n+p Con{+k, Con{+count, +rest}}:
      Bool.pick(List<&2, U32>, U32.is_eq(k, key), Blob.first(rest, count), choices_scan(p, Blob.drop(rest, count), key))
    case _ _:
      Nil{}

def chosen(got: U32 & Pcg.Rng, t: LuaTable.Table, +choices: List<&2, U32>, +key: LuaTable.TKey, +value: U32) -> LuaTable.Table & Pcg.Rng:
  (+r, s) = got
  (LuaTable.remove(LuaTable.set(t, skey(StoryOrder.nth_or_last(choices, (r - 1 : U32), 0)), value), key), s)

def replaced(+choices: List<&2, U32>, t: LuaTable.Table, +key: LuaTable.TKey, +value: U32, s: Pcg.Rng) -> LuaTable.Table & Pcg.Rng:
  match choices:
    case Nil{}:
      (t, s)
    case Con{_, _}:
      chosen(MathRandom.random_range(s, 1, count_of(choices)), t, choices, key, value)

def walk_stepped(got: LuaTable.Table & LuaTable.Step, s: Pcg.Rng) -> Walk:
  (t, +step) = got
  Walk{t, step, s}

def walk_on(got: LuaTable.Table & Pcg.Rng, +key: LuaTable.TKey) -> Walk:
  (t, s) = got
  walk_stepped(LuaTable.next(t, key), s)

def walk(n: Nat, w: Walk, +defs: List<&2, U32>) -> LuaTable.Table & Pcg.Rng:
  match n:
    case 0n:
      match w:
        case Walk{t, _, s}:
          (t, s)
    case 1n+p:
      match w:
        case Walk{t, +step, s}:
          match step:
            case LuaTable.Step{+status, +key, +value}:
              match status:
                case 1:
                  walk(p, walk_on(replaced(choices_scan(List.length(&2, U32, defs), defs, key_id(key)), t, key, value, s), key), defs)
                case _:
                  (t, s)

def defs_applied(t: LuaTable.Table, +defs: List<&2, U32>, s: Pcg.Rng) -> LuaTable.Table & Pcg.Rng:
  walk(256n, walk_stepped(LuaTable.next(t, LuaTable.nil_key()), s), defs)

# The areas and defs passes over layout.layout, then its entries.

def group_entries(groups: List<&2, Group>, +i: U32) -> List<&2, Entry>:
  match groups:
    case Nil{}:
      Nil{}
    case Con{Group{+key, _}, rest}:
      Entry{key, i} <> group_entries(rest, (i + 1 : U32))

def group_store(groups: List<&2, Group>) -> List<&2, List<&2, Pos>>:
  match groups:
    case Nil{}:
      Nil{}
    case Con{Group{_, +objs}, rest}:
      obj_poss(objs) <> group_store(rest)

def add_slots(adds: List<&2, Add>) -> List<&2, StoryOrder.Slot>:
  match adds:
    case Nil{}:
      Nil{}
    case Con{Add{+key, _}, rest}:
      StoryOrder.Slot{Strings.hash(key), key} <> add_slots(rest)

def poss_of(adds: List<&2, Add>, +key: U32) -> List<&2, Pos>:
  match adds:
    case Nil{}:
      Nil{}
    case Con{Add{+k, +ps}, rest}:
      Bool.pick(List<&2, Pos>, U32.is_eq(k, key), ps, poss_of(rest, key))

def store_update(store: List<&2, List<&2, Pos>>, +i: U32, +extra: List<&2, Pos>) -> List<&2, List<&2, Pos>>:
  match store:
    case Nil{}:
      Nil{}
    case Con{+ps, +rest}:
      Bool.pick(List<&2, List<&2, Pos>>, U32.is_zero(i), List.append(&2, Pos, ps, extra) <> rest, ps <> store_update(rest, (i - 1 : U32), extra))

def store_at(store: List<&2, List<&2, Pos>>, +i: U32) -> List<&2, Pos>:
  match store:
    case Nil{}:
      Nil{}
    case Con{+ps, rest}:
      Bool.pick(List<&2, Pos>, U32.is_zero(i), ps, store_at(rest, (i - 1 : U32)))

def merge_one(got: LuaTable.Table & LuaTable.Found, +id: U32, +poss: List<&2, Pos>, +store: List<&2, List<&2, Pos>>) -> LuaTable.Table & List<&2, List<&2, Pos>>:
  (t, +found) = got
  match found:
    case LuaTable.Found{+full, +value}:
      match full:
        case True{}:
          (t, store_update(store, value, poss))
        case False{}:
          (LuaTable.set(t, skey(id), U32.from_nat(List.length(&2, List<&2, Pos>, store))), List.append(&2, List<&2, Pos>, store, [poss]))

def merge_loop(order: List<&2, U32>, +adds: List<&2, Add>, got: LuaTable.Table & List<&2, List<&2, Pos>>) -> LuaTable.Table & List<&2, List<&2, Pos>>:
  match order:
    case Nil{}:
      got
    case Con{+id, rest}:
      (t, +store) = got
      merge_loop(rest, adds, merge_one(LuaTable.get(t, skey(id)), id, poss_of(adds, id), store))

def remove_areas(+row: List<&2, U32>, t: LuaTable.Table) -> LuaTable.Table:
  match row:
    case Con{+key, Con{_, Con{_, +rest}}}:
      remove_areas(rest, LuaTable.remove(t, skey(key)))
    case _:
      t

def store_items(entries: List<&2, Entry>, +store: List<&2, List<&2, Pos>>) -> List<&2, Item>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Entry{+key, +value}, rest}:
      List.append(&2, Item, pos_items(store_at(store, value), key), store_items(rest, store))

def table_items(got: LuaTable.Table & Pcg.Rng, +store: List<&2, List<&2, Pos>>) -> List<&2, Item> & Pcg.Rng:
  (t, s) = got
  (store_items(entries_of(LuaTable.slot_count(t)), store), s)

def merged(got: LuaTable.Table & List<&2, List<&2, Pos>>, +v: U32, s: Pcg.Rng) -> List<&2, Item> & Pcg.Rng:
  (t, +store) = got
  table_items(defs_applied(remove_areas(Layouts.areas(v), t), Layouts.defs(v), s), store)

def areas_done(got: List<&2, Add> & Pcg.Rng, +v: U32, +groups: List<&2, Group>) -> List<&2, Item> & Pcg.Rng:
  (+adds, s) = got
  t = snapshot_table(Layouts.layout_snapshot(v), group_entries(groups, 0))
  merged(merge_loop(StoryOrder.order(add_slots(adds)), adds, (t, group_store(groups))), v, s)

def static_part(mutable: Bool, +v: U32, +groups: List<&2, Group>, s: Pcg.Rng) -> List<&2, Item> & Pcg.Rng:
  match mutable:
    case True{}:
      areas_done(jobs_loop(area_jobs(groups, Layouts.areas(v)), (Nil{}, s)), v, groups)
    case False{}:
      (groups_items(groups), s)

# The shape layouts (TranslateFunction over pairs(layout.count)).

def count_entries(+row: List<&2, U32>) -> List<&2, Entry>:
  match row:
    case Con{+key, Con{_, Con{+value, +rest}}}:
      Entry{key, value} <> count_entries(rest)
    case _:
      Nil{}

def walked_entries(got: LuaTable.Table & Pcg.Rng) -> List<&2, Entry> & Pcg.Rng:
  (t, s) = got
  (entries_of(LuaTable.slot_count(t)), s)

def count_pairs(walked: Bool, +v: U32, s: Pcg.Rng) -> List<&2, Entry> & Pcg.Rng:
  match walked:
    case True{}:
      walked_entries(defs_applied(snapshot_table(Layouts.count_snapshot(v), count_entries(Layouts.count(v))), Layouts.defs(v), s))
    case False{}:
      (count_entries(Layouts.count(v)), s)

def total_of(entries: List<&2, Entry>, +acc: U32) -> U32:
  match entries:
    case Nil{}:
      acc
    case Con{Entry{_, +n}, rest}:
      total_of(rest, (acc + n : U32))

def circle_poss(n: Nat, +row: List<&2, U32>) -> List<&2, Pos>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Pos{f64_of(Blob.f64(row, 0)), f64_of(Blob.f64(row, 4)), 0} <> circle_poss(p, Blob.drop(row, 8))

def circle_scan(n: Nat, +i: U32, +kind: U32, +count: U32) -> List<&2, Pos>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +row = Constants.circles(i)
      +hit = Bool.and(U32.is_eq(Blob.at(row, 0), kind), U32.is_eq(Blob.at(row, 1), count))
      Bool.pick(List<&2, Pos>, hit, circle_poss(U32.to_nat(count), Blob.drop(row, 2)), circle_scan(p, (i + 1 : U32), kind, count))

# genCircEdgePositions (kind 1) or genCircOffsetPositions before Randomize (kind 2), baked.
def circle(+kind: U32, +count: U32) -> List<&2, Pos>:
  circle_scan(U32.to_nat(Constants.circles_count()), 0, kind, count)

def nth_pos(poss: List<&2, Pos>, +k: U32) -> Pos:
  match poss:
    case Nil{}:
      Pos{F64Repr.zero(), F64Repr.zero(), 0}
    case Con{+p, rest}:
      Bool.pick(Pos, U32.is_zero(k), p, nth_pos(rest, (k - 1 : U32)))

def set_pos(poss: List<&2, Pos>, +k: U32, +v: Pos) -> List<&2, Pos>:
  match poss:
    case Nil{}:
      Nil{}
    case Con{+p, +rest}:
      Bool.pick(List<&2, Pos>, U32.is_zero(k), v <> rest, p <> set_pos(rest, (k - 1 : U32), v))

def swapped(+poss: List<&2, Pos>, +a: U32, +b: U32) -> List<&2, Pos>:
  set_pos(set_pos(poss, a, nth_pos(poss, b)), b, nth_pos(poss, a))

def swap_pending(pending: Bool, +poss: List<&2, Pos>, +i: U32, +r: U32) -> List<&2, Pos>:
  match pending:
    case True{}:
      swapped(poss, (i - 1 : U32), (U32.min(r, i) - 1 : U32))
    case False{}:
      poss

def randomize_loop(n: Nat, +i: U32, +poss: List<&2, Pos>, got: U32 & Pcg.Rng, +pending: Bool) -> List<&2, Pos> & Pcg.Rng:
  match n:
    case 0n:
      (+r, s) = got
      (swap_pending(pending, poss, (i + 1 : U32), r), s)
    case 1n+p:
      (+r, s) = got
      randomize_loop(p, (i - 1 : U32), swap_pending(pending, poss, (i + 1 : U32), r), MathRandom.random_upto(s, i), True{})

# placement.lua Randomize: for i = #positions down to 2, swap positions[i] with positions[math.random(i)].
def randomize(+poss: List<&2, Pos>, +count: U32, s: Pcg.Rng) -> List<&2, Pos> & Pcg.Rng:
  randomize_loop(U32.to_nat(Bool.pick(U32, (count >= 2 : U32), (count - 1 : U32), 0)), count, poss, (0, s), False{})

def half_of(+n: U32) -> F64Repr.F64:
  F64Arith.div(F64Repr.from_u32(n), F64Repr.two())

def grid_loop(n: Nat, +i: U32, +height: U32) -> List<&2, Pos>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Pos{F64Arith.add(F64Repr.neg(half_of(3)), F64Repr.from_u32((i % 3 : U32))), F64Arith.add(F64Repr.neg(half_of(height)), F64Repr.from_u32((i / 3 : U32))), 0}
        <> grid_loop(p, (i + 1 : U32), height)

# GetGridPositions(num) with the default width 3.
def grid(+count: U32) -> List<&2, Pos>:
  grid_loop(U32.to_nat(count), 1, ((count + 2 : U32) / 3 : U32))

def rect_at(+cur: F64Repr.F64) -> Pos:
  +three = F64Repr.from_u32(3)
  +h = half_of(3)
  +c2 = F64Arith.sub(cur, three)
  +c3 = F64Arith.sub(c2, three)
  +c4 = F64Arith.sub(c3, three)
  +last = F64Repr.pick(F64Cmp.lt(c3, three), F64Arith.sub(h, c3), F64Repr.neg(h))
  Pos{F64Repr.pick(F64Cmp.lt(cur, three), F64Arith.add(F64Repr.neg(h), cur), F64Repr.pick(F64Cmp.lt(c2, three), h, last)),
    F64Repr.pick(F64Cmp.lt(cur, three), F64Repr.neg(h), F64Repr.pick(F64Cmp.lt(c2, three), F64Arith.add(F64Repr.neg(h), c2), F64Repr.pick(F64Cmp.lt(c3, three), h, F64Arith.sub(h, c4)))), 0}

def rect_loop(n: Nat, +i: U32, +dist: F64Repr.F64) -> List<&2, Pos>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      rect_at(F64Arith.mul(F64Repr.from_u32(i), dist)) <> rect_loop(p, (i + 1 : U32), dist)

# GetRectangleEdgePositions(num) with the default 3 x 3 rectangle.
def rect(+count: U32) -> List<&2, Pos>:
  rect_loop(U32.to_nat(count), 1, F64Arith.div(F64Repr.from_u32(12), F64Repr.from_u32(count)))

def shape_positions(+kind: U32, +count: U32, s: Pcg.Rng) -> List<&2, Pos> & Pcg.Rng:
  match kind:
    case 1:
      (circle(1, count), s)
    case 2:
      randomize(circle(2, count), count, s)
    case 3:
      (grid(count), s)
    case _:
      (rect(count), s)

def assign(entries: List<&2, Entry>, +poss: List<&2, Pos>) -> List<&2, Item>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Entry{+key, +n}, rest}:
      List.append(&2, Item, pos_items(List.take(&2, Pos, poss, U32.to_nat(n)), key), assign(rest, List.drop(&2, Pos, poss, U32.to_nat(n))))

def shaped(got: List<&2, Pos> & Pcg.Rng, +entries: List<&2, Entry>, +items: List<&2, Item>) -> List<&2, Item> & Pcg.Rng:
  (+poss, s) = got
  (List.append(&2, Item, items, assign(entries, poss)), s)

def counted(got: List<&2, Entry> & Pcg.Rng, +v: U32, +items: List<&2, Item>) -> List<&2, Item> & Pcg.Rng:
  (+entries, s) = got
  shaped(shape_positions(Layouts.layout_type(v), total_of(entries, 0), s), entries, items)

def shapes_part(shape: Bool, +v: U32, +items: List<&2, Item>, s: Pcg.Rng) -> List<&2, Item> & Pcg.Rng:
  match shape:
    case True{}:
      counted(count_pairs(Bool.and(Layouts.has(v, Layouts.flag_defs()), Bool.not(List.is_empty(&2, U32, Layouts.count_snapshot(v)))), v, s), v, items)
    case False{}:
      (items, s)

def with_shapes(got: List<&2, Item> & Pcg.Rng, +v: U32) -> List<&2, Item> & Pcg.Rng:
  (+items, s) = got
  shapes_part(U32.is_ne(Layouts.layout_type(v), Enums.layout_static()), v, items, s)

def is_mutable(+v: U32) -> Bool:
  Bool.and(Bool.or(Layouts.has(v, Layouts.flag_areas()), Layouts.has(v, Layouts.flag_defs())), Bool.not(List.is_empty(&2, U32, Layouts.layout_snapshot(v))))

# ConvertLayoutToEntitylist(LayoutForDefinition(name)) for layout index `layout` (data/layouts.bend rows) under
# prefab swap state `state` (level/summary.bend Summary.swaps): the entity list in order and the RNG after its draws.
def convert(+state: U32, +layout: U32, rng: Pcg.Rng) -> List<&2, Item> & Pcg.Rng:
  +v = Layouts.variant(layout, state)
  with_shapes(static_part(is_mutable(v), v, groups_of(v), rng), v)

def prefab_fold(items: List<&2, Item>, +h: U32) -> U32:
  match items:
    case Nil{}:
      h
    case Con{Item{+prefab, _, _, _}, rest}:
      prefab_fold(rest, (h * 31 + prefab : U32))

# A check code of a conversion (for laws and traces): the prefab ids folded as h * 31 + id, then * 31 + the draw
# counter of the RNG after it (relative to math.randomseed(seed)).
def check_code(got: List<&2, Item> & Pcg.Rng, +seed: U32) -> U32:
  (+items, s) = got
  (prefab_fold(items, 0) * 31 + Pcg.counter(seed, s) : U32)
