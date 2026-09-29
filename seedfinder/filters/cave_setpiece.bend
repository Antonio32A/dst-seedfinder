import Base
import ../data/cave_catalog.bend as CaveCatalog
import ../level/cave_prefix.bend as CavePrefix
import ../level/cave_choose.bend as CaveChoose
import ./setpiece.bend as FilterSetpiece

# `setpiece find` on the caves shard: bounds on how many times AddSetPeices puts each level.set_pieces key in the level.
type Bound is Data:
  Bound{key: U32, low: U32, high: U32}

def highest() -> U32:
  255

def holds(bounds: List<&2, Bound>, +entries: List<&2, CaveChoose.Entry>) -> Bool:
  match bounds:
    case Nil{}:
      True{}
    case Con{Bound{+key, +low, +high}, rest}:
      +count = CaveChoose.count_of(entries, key)
      (low <= count : U32) && (count <= high : U32) && holds(rest, entries)

def matches(+bounds: List<&2, Bound>, +seed: U32) -> Bool:
  holds(bounds, CaveChoose.added_entries(CavePrefix.chosen(seed)))

def find_piece(pieces: List<&2, CaveCatalog.Name>, +name: String) -> Maybe<&2, U32>:
  match pieces:
    case Nil{}:
      None{}
    case Con{CaveCatalog.Name{+piece, +key}, rest}:
      Bool.pick(Maybe<&2, U32>, String.eq(piece, name), Some{key}, find_piece(rest, name))

def bounded(found: Maybe<&2, U32>, +bounds: List<&2, Bound>, +name: String, +low: U32, +high: U32) -> Result<&1, &1, U32 & String, List<&2, Bound>>:
  match found:
    case None{}:
      Fail{(2, "unknown set piece: " ++ name)}
    case Some{key}:
      Done{Bound{key, low, high} <> bounds}

def with_bounds(
  +bounds: List<&2, Bound>, +name: String, low: Result<&1, &1, U32 & String, U32>, high: Result<&1, &1, U32 & String, U32>
) -> Result<&1, &1, U32 & String, List<&2, Bound>>:
  match low high:
    case Done{+l} Done{+h}:
      bounded(find_piece(CaveCatalog.pieces(), name), bounds, name, l, h)
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

# "Name" (at least one), "Name:min" or "Name:min:max".
def constrain(acc: Result<&1, &1, U32 & String, List<&2, Bound>>, +spec: String) -> Result<&1, &1, U32 & String, List<&2, Bound>>:
  match acc:
    case Fail{e}:
      Fail{e}
    case Done{+bounds}:
      +parts = String.split(spec, ':')
      +name = Maybe.default(&2, String, List.get(&2, String, parts, 0n), "")
      with_bounds(bounds, name, FilterSetpiece.bound(parts, 1n, 1), FilterSetpiece.bound(parts, 2n, highest()))

def parse(specs: List<&2, String>, acc: Result<&1, &1, U32 & String, List<&2, Bound>>) -> Result<&1, &1, U32 & String, List<&2, Bound>>:
  match specs:
    case Nil{}:
      acc
    case Con{+spec, rest}:
      parse(rest, constrain(acc, spec))
