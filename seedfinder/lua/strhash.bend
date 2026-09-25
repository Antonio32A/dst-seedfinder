import Base

# Lua 5.1 luaS_hash (lstring.c): h = len; step = (len >> 5) + 1; for l1 = len, len - step, ... while l1 >= step:
# h ^= (h << 5) + (h >> 2) + byte[l1 - 1]. No seed. Strings are byte sequences (Bend Chars are UTF-8 encoded).
# Interned strings: see .scratch/port/status/M2.md "String interface".

def mix(+h: U32, +c: U32) -> U32:
  (h .^. (((h << 5n) + (h >> 2n)) + c) : U32)

def walk(bytes: List<&2, U32>, +h: U32, +l1: U32, +step: U32, +gap: U32) -> U32:
  match bytes:
    case Nil{}:
      h
    case Con{+c, rest}:
      +visit = Bool.and(U32.is_zero(gap), (l1 >= step : U32))
      walk(rest, Bool.pick(U32, visit, mix(h, c), h), Bool.pick(U32, visit, (l1 - step : U32), l1), step, Bool.pick(U32, visit, (step - 1 : U32), (gap - 1 : U32)))

def step_of(+len: U32) -> U32:
  ((len >> 5n) + 1 : U32)

# luaS_hash of a string of `len` bytes given last byte first.
def hash_reversed(reversed: List<&2, U32>, +len: U32) -> U32:
  walk(reversed, len, len, step_of(len), 0)

def reverse_count(bytes: List<&2, U32>, acc: List<&2, U32>, +len: U32) -> List<&2, U32> & U32:
  match bytes:
    case Nil{}:
      (acc, len)
    case Con{+c, rest}:
      reverse_count(rest, c <> acc, (len + 1 : U32))

def hash_pair(got: List<&2, U32> & U32) -> U32:
  (reversed, +len) = got
  hash_reversed(reversed, len)

# luaS_hash of a byte sequence given in order.
def hash_bytes(bytes: List<&2, U32>) -> U32:
  hash_pair(reverse_count(bytes, Nil{}, 0))

def push_continuation(+code: U32, +shift: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  (((code >> shift) .&. 63 : U32) + 128 : U32) <> acc

def utf8_length(+code: U32) -> U32:
  (1 + Bool.to_u32((code >= 128 : U32)) + Bool.to_u32((code >= 2048 : U32)) + Bool.to_u32((code >= 65536 : U32)) : U32)

def push_sized(+size: U32, +code: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match size:
    case 1:
      code <> acc
    case 2:
      push_continuation(code, 0n, ((code >> 6n) + 192 : U32) <> acc)
    case 3:
      push_continuation(code, 0n, push_continuation(code, 6n, ((code >> 12n) + 224 : U32) <> acc))
    case _:
      push_continuation(code, 0n, push_continuation(code, 6n, push_continuation(code, 12n, ((code >> 18n) + 240 : U32) <> acc)))

def utf8_reversed(chars: String, acc: List<&2, U32>, +len: U32) -> List<&2, U32> & U32:
  match chars:
    case SNil{}:
      (acc, len)
    case SCon{Chr{+code}, rest}:
      utf8_reversed(rest, push_sized(utf8_length(code), code, acc), (len + utf8_length(code) : U32))

# luaS_hash of a Bend string (its UTF-8 bytes; worldgen ids are ASCII).
def hash_string(s: String) -> U32:
  hash_pair(utf8_reversed(s, Nil{}, 0))
