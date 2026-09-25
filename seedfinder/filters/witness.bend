import Base
import ./bignum.bend as BN
import ../f64/repr.bend as FR
import ../f64/arith.bend as FA
import ../f64/cmp.bend as FC
import ./walk.bend as WL
import ./world.bend as WD
import ../data/search_vocab.bend as V

# Witness JSON as .scratch/search/evaluate.py --json prints it (json.dumps with separators (",", ":")).

def prefab_name(+id: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, V.prefabs(), U32.to_nat(id)), "")

def is_negative(+k: U32) -> Bool:
  (k >= 2147483648 : U32)

def magnitude(+k: U32) -> U32:
  Bool.pick(U32, is_negative(k), (0 - k : U32), k)

def two_digits(+n: U32) -> String:
  String.from_list([Chr{(48 + n / 10 : U32)}, Chr{(48 + n % 10 : U32)}])

def trim_zeros_rev(s: String) -> String:
  match s:
    case SCon{Chr{48}, rest}:
      trim_zeros_rev(rest)
    case other:
      other

def fraction_text(+digits: String) -> String:
  +trimmed = String.reverse(trim_zeros_rev(String.reverse(digits)))
  Bool.pick(String, String.is_empty(trimmed), "0", trimmed)

# A coordinate from its value times 100 (an int32) as Python prints the JSON number it came from.
def coordinate(+k: U32, +integer: Bool) -> String:
  +sign = Bool.pick(String, is_negative(k), "-", "")
  +m = magnitude(k)
  Bool.pick(String, integer, sign ++ U32.show((m / 100 : U32)), sign ++ U32.show((m / 100 : U32)) ++ "." ++ fraction_text(two_digits((m % 100 : U32))))

def three_digits(+n: Nat) -> String:
  +d = U32.from_nat(n)
  String.from_list([Chr{(48 + d / 100 : U32)}, Chr{(48 + (d / 10) % 10 : U32)}, Chr{(48 + d % 10 : U32)}])

# n / 1000 as Python's repr of round(x, 3): at most 3 decimals, at least one.
def thousandths_text(+n: Nat) -> String:
  Nat.show(Nat.div(n, 1000n)) ++ "." ++ fraction_text(three_digits(Nat.mod(n, 1000n)))

def rounded_scaled(+scaled: List<&2, U32>) -> Nat:
  +whole = BN.shr(scaled, 1074n)
  +order = BN.compare(BN.low_bits(scaled, 1074n), BN.shl([1], 1073n))
  +up = U32.is_eq(order, 2) || (U32.is_eq(order, 1) && U32.is_eq(BN.bit(whole, 0n), 1))
  +n = BN.add(whole, Bool.pick(List<&2, U32>, up, [1], Nil{}))
  Nat.add(U32.to_nat(BN.word(n, 0n)), Nat.mul(U32.to_nat(BN.word(n, 1n)), Nat.mul(65536n, 65536n)))

# round(d, 3) of a double d >= 0, as Python prints it.
def double_text(+d: FR.F64) -> String:
  thousandths_text(rounded_scaled(BN.mul_small(BN.of_double(d), 1000)))

# round(length, 3) of an exact walk length, as Python prints its double.
def length_text(+l: WL.Length) -> String:
  thousandths_text(WL.thousandths(l))

# "prefab", "index", "x", "z" of an instance, without the braces.
def instance_fields(+i: WD.Inst) -> String:
  match i:
    case WD.Inst{+prefab, +index, _, _, +xk, +zk, +flags}:
      "\"prefab\":\"" ++ prefab_name(prefab) ++ "\",\"index\":" ++ U32.show(index) ++ ",\"x\":"
        ++ coordinate(xk, U32.is_eq((flags .&. 1 : U32), 1)) ++ ",\"z\":" ++ coordinate(zk, U32.is_eq((flags .&. 2 : U32), 2))

# {"prefab", "index", "x", "z"} of an instance.
def instance(+i: WD.Inst) -> String:
  "{" ++ instance_fields(i) ++ "}"

def signed_text(+v: U32) -> String:
  Bool.pick(String, is_negative(v), "-" ++ U32.show(magnitude(v)), U32.show(v))

# The centre of a tile as Python prints (t - size/2.0) * 4: an integral float.
def centre_text(+t: U32, +size: U32) -> String:
  signed_text((t * 4 - size * 2 : U32)) ++ ".0"

# {"tx", "ty", "x", "z"} of a tile.
def tile(+index: U32, +width: U32, +height: U32) -> String:
  +tx = (index % width : U32)
  +ty = (index / width : U32)
  "{\"tx\":" ++ U32.show(tx) ++ ",\"ty\":" ++ U32.show(ty) ++ ",\"x\":" ++ centre_text(tx, width) ++ ",\"z\":" ++ centre_text(ty, height) ++ "}"
