import Base
import ../rng/pcg.bend as Pcg
import ../f64/repr.bend as F64Repr
import ../populate/layout.bend as PopulateLayout

# Goldens: the real game Lua under DST's PCG32 (object_layout.ConvertLayoutToEntitylist of the caves' layouts).

def word_fold(+h: U32, +w: U32) -> U32:
  (h * 31 + w : U32)

def item_fold(+h: U32, +i: PopulateLayout.Item) -> U32:
  match i:
    case PopulateLayout.Item{+prefab, F64Repr.F64{+xh, +xl}, F64Repr.F64{+yh, +yl}, _}:
      word_fold(word_fold(word_fold(word_fold(word_fold(h, prefab), xh), xl), yh), yl)

def items_fold(items: List<&2, PopulateLayout.Item>, +h: U32) -> U32:
  match items:
    case Nil{}:
      h
    case Con{+i, rest}:
      items_fold(rest, item_fold(h, i))

# The items of a layout conversion folded with their positions' bits, then the draw counter of the RNG after it.
def items_code(got: List<&2, PopulateLayout.Item> & Pcg.Rng, +seed: U32) -> U32:
  (+items, s) = got
  (items_fold(items, 0) * 31 + Pcg.counter(seed, s) : U32)

law layout_evergreensinkhole_1_0:
  {items_code(PopulateLayout.convert(0, 133, Pcg.at_counter(1, 0)), 1) == 3451176608 : U32}

def layout_evergreensinkhole_1_0():
  {==}

law layout_lures_and_worms_1_0:
  {items_code(PopulateLayout.convert(0, 321, Pcg.at_counter(1, 0)), 1) == 677353996 : U32}

def layout_lures_and_worms_1_0():
  {==}
