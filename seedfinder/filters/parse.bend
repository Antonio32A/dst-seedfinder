import Base
import ./json.bend as J
import ./decimal.bend as DC
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC

# Config reading helpers shared by part A (filters/config.bend) and parts B-E (filters/rules.bend). Every failure is
# (2, "config: <message>") with the messages of .scratch/search/config.py.

def failure(+message: String) -> U32 & String:
  (2, "config: " ++ message)

def indexed(+path: String, +index: U32) -> String:
  path ++ "[" ++ U32.show(index) ++ "]"

# A name as json.dumps(name, ensure_ascii=False) writes it.
def quoted(+name: String) -> String:
  J.quote(False{}, name)

def field(fields: List<&2, J.Json>, +key: String) -> Maybe<&2, J.Json>:
  match fields:
    case Nil{}:
      None{}
    case Con{J.JField{+name, value}, rest}:
      Bool.pick(Maybe<&2, J.Json>, String.eq(name, key), Some{value}, field(rest, key))
    case Con{_, rest}:
      field(rest, key)

def is_member(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}:
      False{}
    case Con{+head, rest}:
      String.eq(head, name) || is_member(rest, name)

def check_key(+allowed: List<&2, String>, +path: String, +key: String) -> Result<&1, &1, U32 & String, Unit>:
  Bool.pick(Result<&1, &1, U32 & String, Unit>, is_member(allowed, key), Done{Unit{}}, Fail{failure("unknown key " ++ quoted(key) ++ " in " ++ path)})

def check_keys(fields: List<&2, J.Json>, +allowed: List<&2, String>, +path: String) -> Result<&1, &1, U32 & String, Unit>:
  match fields:
    case Nil{}:
      Done{Unit{}}
    case Con{J.JField{+key, _}, rest}:
      do Result<&1, &1, U32 & String, Unit>:
        ok : Unit <- check_key(allowed, path, key)
        check_keys(rest, allowed, path)
    case Con{_, rest}:
      check_keys(rest, allowed, path)

def first_repeated(fields: List<&2, J.Json>, +seen: List<&2, String>) -> Maybe<&2, String>:
  match fields:
    case Nil{}:
      None{}
    case Con{J.JField{+key, _}, rest}:
      Bool.pick(Maybe<&2, String>, is_member(seen, key), Some{key}, first_repeated(rest, key <> seen))
    case Con{_, rest}:
      first_repeated(rest, seen)

def without_repeats(repeated: Maybe<&2, String>, fields: List<&2, J.Json>, +path: String) -> Result<&1, &1, U32 & String, List<&2, J.Json>>:
  match repeated:
    case None{}:
      Done{fields}
    case Some{key}:
      Fail{failure("duplicate key " ++ quoted(key) ++ " in " ++ path)}

# The fields of an object without repeated keys ("<path> must be an object", "duplicate key ...").
def object_fields(json: J.Json, +path: String) -> Result<&1, &1, U32 & String, List<&2, J.Json>>:
  match json:
    case J.JObj{+fields}:
      without_repeats(first_repeated(fields, Nil{}), fields, path)
    case _:
      Fail{failure(path ++ " must be an object")}

# The fields of an object with only the allowed keys.
def keyed_fields(json: J.Json, +allowed: List<&2, String>, +path: String) -> Result<&1, &1, U32 & String, List<&2, J.Json>>:
  do Result<&1, &1, U32 & String, List<&2, J.Json>>:
    +fields : List<&2, J.Json> <- object_fields(json, path)
    ok : Unit <- check_keys(fields, allowed, path)
    return fields

def optional_fields(m: Maybe<&2, J.Json>, +path: String) -> Result<&1, &1, U32 & String, List<&2, J.Json>>:
  match m:
    case None{}:
      Done{Nil{}}
    case Some{json}:
      object_fields(json, path)

def items_of(json: J.Json, +path: String) -> Result<&1, &1, U32 & String, List<&2, J.Json>>:
  match json:
    case J.JArr{items}:
      Done{items}
    case _:
      Fail{failure(path ++ " must be a list")}

def optional_items(m: Maybe<&2, J.Json>, +path: String) -> Result<&1, &1, U32 & String, List<&2, J.Json>>:
  match m:
    case None{}:
      Done{Nil{}}
    case Some{json}:
      items_of(json, path)

def length_of(items: List<&2, J.Json>) -> U32:
  match items:
    case Nil{}:
      0
    case Con{_, rest}:
      (1 + length_of(rest) : U32)

def capped(+items: List<&2, J.Json>, +cap: U32, +noun: String, +path: String) -> Result<&1, &1, U32 & String, List<&2, J.Json>>:
  +count = length_of(items)
  Bool.pick(Result<&1, &1, U32 & String, List<&2, J.Json>>, (count <= cap : U32), Done{items},
    Fail{failure(path ++ " has " ++ U32.show(count) ++ " " ++ noun ++ " (at most " ++ U32.show(cap) ++ ")")})

def not_empty(+items: List<&2, J.Json>, +path: String) -> Result<&1, &1, U32 & String, List<&2, J.Json>>:
  Bool.pick(Result<&1, &1, U32 & String, List<&2, J.Json>>, List.is_empty(&2, J.Json, items),
    Fail{failure(path ++ " must not be empty")}, Done{items})

# A list of 1..cap items ("must not be empty", "<path> has <n> <noun> (at most <cap>)").
def nonempty_capped(+items: List<&2, J.Json>, +cap: U32, +noun: String, +path: String) -> Result<&1, &1, U32 & String, List<&2, J.Json>>:
  do Result<&1, &1, U32 & String, List<&2, J.Json>>:
    some : List<&2, J.Json> <- not_empty(items, path)
    capped(some, cap, noun, path)

def string_of(json: J.Json, +path: String) -> Result<&1, &1, U32 & String, String>:
  match json:
    case J.JStr{s}:
      Done{s}
    case _:
      Fail{failure(path ++ " must be a string")}

def required(m: Maybe<&2, J.Json>, +path: String, +key: String) -> Result<&1, &1, U32 & String, J.Json>:
  match m:
    case None{}:
      Fail{failure(path ++ "." ++ key ++ " is required")}
    case Some{json}:
      Done{json}

# The field `key` of the fields, which must be present.
def required_field(+fields: List<&2, J.Json>, +path: String, +key: String) -> Result<&1, &1, U32 & String, J.Json>:
  required(field(fields, key), path, key)

def integer_message(+path: String) -> U32 & String:
  failure(path ++ " must be an integer in 0..4294967295")

# A uint32 ("<path> must be an integer in 0..4294967295").
def integer(json: J.Json, +path: String) -> Result<&1, &1, U32 & String, U32>:
  match json:
    case J.JNum{n}:
      Done{n}
    case _:
      Fail{integer_message(path)}

def optional_integer(m: Maybe<&2, J.Json>, +path: String) -> Result<&1, &1, U32 & String, Maybe<&2, U32>>:
  match m:
    case None{}:
      Done{None{}}
    case Some{json}:
      do Result<&1, &1, U32 & String, Maybe<&2, U32>>:
        n : U32 <- integer(json, path)
        return Some{n}

def million() -> FR.F64:
  FR.F64{1093567616, 0}

def in_distance_range(+p: DC.Parsed) -> Bool:
  match p:
    case DC.Parsed{+finite, +value}:
      finite && FC.le(FR.zero(), value) && FC.le(value, million())

def distance_value(+p: DC.Parsed, +path: String) -> Result<&1, &1, U32 & String, FR.F64>:
  match p:
    case DC.Parsed{_, +value}:
      Bool.pick(Result<&1, &1, U32 & String, FR.F64>, in_distance_range(p), Done{value},
        Fail{failure(path ++ " must be a number in 0..1000000")})

# A distance: a JSON number in 0..1000000 as its double ("<path> must be a number in 0..1000000").
def distance(json: J.Json, +path: String) -> Result<&1, &1, U32 & String, FR.F64>:
  match json:
    case J.JNum{+n}:
      distance_value(DC.Parsed{True{}, FR.from_u32(n)}, path)
    case J.JReal{+text}:
      distance_value(DC.parse(text), path)
    case _:
      Fail{failure(path ++ " must be a number in 0..1000000")}

def optional_distance(m: Maybe<&2, J.Json>, +path: String) -> Result<&1, &1, U32 & String, Maybe<&2, FR.F64>>:
  match m:
    case None{}:
      Done{None{}}
    case Some{json}:
      do Result<&1, &1, U32 & String, Maybe<&2, FR.F64>>:
        d : FR.F64 <- distance(json, path)
        return Some{d}

def flag(json: J.Json, +path: String) -> Result<&1, &1, U32 & String, Bool>:
  match json:
    case J.JBool{value}:
      Done{value}
    case _:
      Fail{failure(path ++ " must be true or false")}

def optional_flag(m: Maybe<&2, J.Json>, +path: String) -> Result<&1, &1, U32 & String, Bool>:
  match m:
    case None{}:
      Done{False{}}
    case Some{json}:
      flag(json, path)

def is_text(json: J.Json, +text: String) -> Bool:
  match json:
    case J.JStr{value}:
      String.eq(value, text)
    case _:
      False{}

# True for the second of two choices, False for the first ('<path> must be "a" or "b"'); absent is the first.
def binary_choice(m: Maybe<&2, J.Json>, +first: String, +second: String, +path: String) -> Result<&1, &1, U32 & String, Bool>:
  match m:
    case None{}:
      Done{False{}}
    case Some{+json}:
      Bool.pick(Result<&1, &1, U32 & String, Bool>, is_text(json, first) || is_text(json, second), Done{is_text(json, second)},
        Fail{failure(path ++ " must be " ++ quoted(first) ++ " or " ++ quoted(second))})

def index_of(names: List<&2, String>, +name: String, +i: U32) -> Maybe<&2, U32>:
  match names:
    case Nil{}:
      None{}
    case Con{+entry, rest}:
      Bool.pick(Maybe<&2, U32>, String.eq(entry, name), Some{i}, index_of(rest, name, (i + 1 : U32)))

def contains_id(ids: List<&2, U32>, +id: U32) -> Bool:
  match ids:
    case Nil{}:
      False{}
    case Con{+head, rest}:
      U32.is_eq(head, id) || contains_id(rest, id)

def distinct_from(ids: List<&2, U32>, +seen: List<&2, U32>) -> List<&2, U32>:
  match ids:
    case Nil{}:
      List.reverse(&2, U32, seen)
    case Con{+id, rest}:
      distinct_from(rest, Bool.pick(List<&2, U32>, contains_id(seen, id), seen, id <> seen))

# The ids in first-occurrence order.
def distinct(+ids: List<&2, U32>) -> List<&2, U32>:
  distinct_from(ids, Nil{})
