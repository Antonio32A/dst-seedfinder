import Base
import ../data/catalog.bend as Catalog
import ../level/setpieces.bend as LevelSetpieces

# Per-boon count bounds in the same 8-bit layout as Pieces, plus bitmasks of the catalog ids
# each single-choice category may take (bit 0 = nothing chosen).
type Filter is Data:
  Filter{
    min_a: U32, min_b: U32, min_c: U32, min_d: U32, max_a: U32, max_b: U32, max_c: U32, max_d: U32,
    traps: U32, pois: U32, protecteds: U32
  }

def lane_high_bits() -> U32:
  2155905152

def lane_maximums() -> U32:
  2139062143

def lane_maximum() -> U32:
  127

def everything() -> U32:
  4294967295

def unfiltered() -> Filter:
  Filter{
    0, 0, 0, 0, lane_maximums(), lane_maximums(), lane_maximums(), lane_maximums(),
    everything(), everything(), everything()
  }

def lanes_at_least(+a: U32, +b: U32) -> Bool:
  U32.is_eq((((a .|. lane_high_bits()) - b) .&. lane_high_bits() : U32), lane_high_bits())

def has_bit(+mask: U32, +id: U32) -> Bool:
  U32.is_eq(((mask >> U32.to_nat((id .&. 31 : U32))) .&. 1 : U32), 1)

def matches(+f: Filter, +p: LevelSetpieces.Pieces) -> Bool:
  match f p:
    case Filter{+min_a, +min_b, +min_c, +min_d, +max_a, +max_b, +max_c, +max_d, +traps, +pois, +protecteds}
         LevelSetpieces.Pieces{+trap, +poi, +protected, +a, +b, +c, +d}:
      lanes_at_least(a, min_a) && lanes_at_least(b, min_b) && lanes_at_least(c, min_c) && lanes_at_least(d, min_d)
        && lanes_at_least(max_a, a) && lanes_at_least(max_b, b) && lanes_at_least(max_c, c) && lanes_at_least(max_d, d)
        && has_bit(traps, trap) && has_bit(pois, poi) && has_bit(protecteds, protected)

def set_lane(+boon: Bool, +word: U32, +lane_base: U32, +index: U32, +value: U32) -> U32:
  +inside = boon && (index >= lane_base : U32) && (index < (lane_base + 4 : U32) : U32)
  +shift = U32.to_nat((((index - lane_base : U32) % 4) * 8 : U32))
  Bool.pick(U32, inside, ((word .&. U32.not((255 << shift : U32))) .|. (U32.min(value, lane_maximum()) << shift) : U32), word)

def in_range(+value: U32, +low: U32, +high: U32) -> Bool:
  (low <= value : U32) && (value <= high : U32)

# Ids whose occurrence count of catalog id `index` (1 if chosen, else 0) lies in [low, high].
def allowed_ids(+index: U32, +low: U32, +high: U32) -> U32:
  +bit = (1 << U32.to_nat((index .&. 31 : U32)) : U32)
  (Bool.pick(U32, in_range(1, low, high), bit, 0) .|. Bool.pick(U32, in_range(0, low, high), U32.not(bit), 0) : U32)

def restrict_mask(+mask: U32, +applies: Bool, +allowed: U32) -> U32:
  Bool.pick(U32, applies, (mask .&. allowed : U32), mask)

def restrict(+f: Filter, +kind: U32, +index: U32, +low: U32, +high: U32) -> Filter:
  match f:
    case Filter{+min_a, +min_b, +min_c, +min_d, +max_a, +max_b, +max_c, +max_d, +traps, +pois, +protecteds}:
      +boon = U32.is_eq(kind, Catalog.kind_boon())
      +allowed = allowed_ids(index, low, high)
      +impossible_fixed = U32.is_eq(kind, Catalog.kind_fixed()) && Bool.not(in_range(index, low, high))
      Filter{
        set_lane(boon, min_a, 0, index, low), set_lane(boon, min_b, 4, index, low),
        set_lane(boon, min_c, 8, index, low), set_lane(boon, min_d, 12, index, low),
        set_lane(boon, max_a, 0, index, high), set_lane(boon, max_b, 4, index, high),
        set_lane(boon, max_c, 8, index, high), set_lane(boon, max_d, 12, index, high),
        restrict_mask(restrict_mask(traps, U32.is_eq(kind, Catalog.kind_trap()), allowed), impossible_fixed, 0),
        restrict_mask(pois, U32.is_eq(kind, Catalog.kind_point_of_interest()), allowed),
        restrict_mask(protecteds, U32.is_eq(kind, Catalog.kind_protected_resource()), allowed)
      }

def find_entry(entries: List<&2, Catalog.Entry>, +name: String) -> Maybe<&2, Catalog.Entry>:
  match entries:
    case Nil{}:
      None{}
    case Con{+entry, rest}:
      match entry:
        case Catalog.Entry{+entry_name, _, _}:
          Bool.pick(Maybe<&2, Catalog.Entry>, String.eq(entry_name, name), Some{entry}, find_entry(rest, name))

def parsed_bound(read: Maybe<&2, U32>, +text: String) -> Result<&1, &1, U32 & String, U32>:
  match read:
    case None{}:
      Fail{(2, "not a number: " ++ text)}
    case Some{value}:
      Done{value}

def bound_text(part: Maybe<&2, String>, +fallback: U32) -> Result<&1, &1, U32 & String, U32>:
  match part:
    case None{}:
      Done{fallback}
    case Some{+text}:
      parsed_bound(U32.read(text), text)

def bound(parts: List<&2, String>, +i: Nat, +fallback: U32) -> Result<&1, &1, U32 & String, U32>:
  bound_text(List.get(&2, String, parts, i), fallback)

def restrict_by_entry(
  found: Maybe<&2, Catalog.Entry>, +f: Filter, +name: String, +low: U32, +high: U32
) -> Result<&1, &1, U32 & String, Filter>:
  match found:
    case None{}:
      Fail{(2, "unknown set piece: " ++ name)}
    case Some{Catalog.Entry{_, +kind, +index}}:
      Done{restrict(f, kind, index, low, high)}

def with_bounds(
  +f: Filter, +name: String, low: Result<&1, &1, U32 & String, U32>, high: Result<&1, &1, U32 & String, U32>
) -> Result<&1, &1, U32 & String, Filter>:
  match low high:
    case Done{+l} Done{+h}:
      restrict_by_entry(find_entry(Catalog.catalog(), name), f, name, l, h)
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

# "Name" (at least one), "Name:min" or "Name:min:max".
def constrain(acc: Result<&1, &1, U32 & String, Filter>, +spec: String) -> Result<&1, &1, U32 & String, Filter>:
  match acc:
    case Fail{e}:
      Fail{e}
    case Done{+f}:
      +parts = String.split(spec, ':')
      +name = Maybe.default(&2, String, List.get(&2, String, parts, 0n), "")
      with_bounds(f, name, bound(parts, 1n, 1), bound(parts, 2n, lane_maximum()))

def parse(specs: List<&2, String>, acc: Result<&1, &1, U32 & String, Filter>) -> Result<&1, &1, U32 & String, Filter>:
  match specs:
    case Nil{}:
      acc
    case Con{+spec, rest}:
      parse(rest, constrain(acc, spec))
