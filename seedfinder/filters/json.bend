import Base

# A strict JSON reader (RFC 8259, as Python's json.loads): objects, arrays, strings with every escape including
# \uXXXX, numbers, true, false and null. A non-negative integer in 0..4294967295 (also -0) is a JNum; any other number
# is a JReal holding its source text, which the lexer checked against the JSON number grammar. An object is a JObj of
# JField entries in source order (repeated keys are kept).
type Json is Data:
  JNull{}
  JBool{value: Bool}
  JNum{value: U32}
  JReal{text: String}
  JStr{value: String}
  JArr{items: List<&2, Json>}
  JObj{fields: List<&2, Json>}
  JField{key: String, value: Json}

type Token is Data:
  TValue{value: Json}
  TOpen{object: Bool}
  TClose{object: Bool}
  TComma{}
  TColon{}
  TSkip{}
  TEnd{}
  TBad{message: String}

type Lexed is Data:
  Lexed{token: Token, rest: String}

type Frame is Data:
  FArr{items: List<&2, Json>}
  FObj{fields: List<&2, Json>}
  FKey{key: String}

type Expect is Data:
  XValue{}
  XValueOrClose{}
  XKeyOrClose{}
  XKey{}
  XColon{}
  XNext{}
  XEnd{}

type Parser is Data:
  Parser{expect: Expect, frames: List<&2, Frame>, top: Maybe<&2, Json>}

def bad(+message: String, rest: String) -> Lexed:
  Lexed{TBad{"config: malformed JSON: " ++ message}, rest}

def hex_digit(+code: U32) -> U32:
  Bool.pick(U32, (code <= 57 : U32), (code - 48 : U32), (((code .|. 32) - 87) : U32))

def is_hex(+code: U32) -> Bool:
  +lower = (code .|. 32 : U32)
  ((48 <= code : U32) && (code <= 57 : U32)) || ((97 <= lower : U32) && (lower <= 102 : U32))

def simple_escape(+code: U32) -> U32:
  Bool.pick(U32, U32.is_eq(code, 110), 10, Bool.pick(U32, U32.is_eq(code, 116), 9,
    Bool.pick(U32, U32.is_eq(code, 114), 13, Bool.pick(U32, U32.is_eq(code, 98), 8,
      Bool.pick(U32, U32.is_eq(code, 102), 12, code)))))

def is_simple_escape(+code: U32) -> Bool:
  U32.is_eq(code, 34) || U32.is_eq(code, 92) || U32.is_eq(code, 47) || U32.is_eq(code, 110) || U32.is_eq(code, 116)
    || U32.is_eq(code, 114) || U32.is_eq(code, 98) || U32.is_eq(code, 102)

type Hex is Data:
  Hex{ok: Bool, value: U32, rest: String}

def hex4_step(n: Nat, s: String, +acc: U32) -> Hex:
  match n s:
    case 0n rest:
      Hex{True{}, acc, rest}
    case 1n+p SCon{Chr{+code}, tail}:
      Bool.pick(Hex, is_hex(code), hex4_step(p, tail, ((acc << 4n) + hex_digit(code) : U32)), Hex{False{}, 0, SNil{}})
    case 1n+p SNil{}:
      Hex{False{}, 0, SNil{}}

def is_high_surrogate(+code: U32) -> Bool:
  (55296 <= code : U32) && (code <= 56319 : U32)

def is_low_surrogate(+code: U32) -> Bool:
  (56320 <= code : U32) && (code <= 57343 : U32)

def combined(+high: U32, +low: U32) -> U32:
  (65536 + ((high - 55296) << 10n) + (low - 56320) : U32)

def low_half(+high: U32, low: Hex, +fallback: Hex) -> Hex:
  match low:
    case Hex{True{}, +code, +rest}:
      Bool.pick(Hex, is_low_surrogate(code), Hex{True{}, combined(high, code), rest}, fallback)
    case _:
      fallback

def surrogate_pair(+high: U32, +rest: String) -> Hex:
  match rest:
    case SCon{Chr{92}, SCon{Chr{117}, tail}}:
      low_half(high, hex4_step(4n, tail, 0), Hex{True{}, high, rest})
    case _:
      Hex{True{}, high, rest}

def unicode_escape(first: Hex) -> Hex:
  match first:
    case Hex{True{}, +code, +rest}:
      Bool.pick(Hex, is_high_surrogate(code), surrogate_pair(code, rest), Hex{True{}, code, rest})
    case other:
      other

type Unescaped is Data:
  Unescaped{ok: Bool, code: U32, rest: String}

def unicode_char(h: Hex) -> Unescaped:
  match h:
    case Hex{ok, code, rest}:
      Unescaped{ok, code, rest}

def escape_of(+code: U32, +rest: String) -> Unescaped:
  Bool.pick(Unescaped, U32.is_eq(code, 117), unicode_char(unicode_escape(hex4_step(4n, rest, 0))),
    Unescaped{is_simple_escape(code), simple_escape(code), rest})

type Piece is Data:
  PChar{code: U32, rest: String}
  PClose{rest: String}
  PBad{message: String, rest: String}

def piece_of_escape(e: Unescaped) -> Piece:
  match e:
    case Unescaped{True{}, +code, rest}:
      PChar{code, rest}
    case Unescaped{False{}, _, rest}:
      PBad{"invalid escape", rest}

def escape_piece(s: String) -> Piece:
  match s:
    case SNil{}:
      PBad{"unterminated string", SNil{}}
    case SCon{Chr{+escaped}, tail}:
      piece_of_escape(escape_of(escaped, tail))

def char_piece(+code: U32, +rest: String) -> Piece:
  match code:
    case 34:
      PClose{rest}
    case 92:
      escape_piece(rest)
    case _:
      Bool.pick(Piece, (code < 32 : U32), PBad{"invalid control character in a string", rest}, PChar{code, rest})

def string_piece(s: String) -> Piece:
  match s:
    case SNil{}:
      PBad{"unterminated string", SNil{}}
    case SCon{Chr{+code}, rest}:
      char_piece(code, rest)

def read_string(fuel: Nat, piece: Piece, acc: String) -> Lexed:
  match fuel piece:
    case 0n _:
      bad("unterminated string", SNil{})
    case 1n+p PChar{+code, rest}:
      read_string(p, string_piece(rest), SCon{Chr{code}, acc})
    case 1n+p PClose{rest}:
      Lexed{TValue{JStr{String.reverse(acc)}}, rest}
    case 1n+p PBad{+message, rest}:
      bad(message, rest)

def is_digit(+code: U32) -> Bool:
  (48 <= code : U32) && (code <= 57 : U32)

def is_number_char(+code: U32) -> Bool:
  is_digit(code) || U32.is_eq(code, 46) || U32.is_eq(code, 101) || U32.is_eq(code, 69) || U32.is_eq(code, 43)
    || U32.is_eq(code, 45)

def invalid_number() -> U32:
  9

def is_exponent(+code: U32) -> Bool:
  U32.is_eq(code, 101) || U32.is_eq(code, 69)

def integer_start(+code: U32) -> U32:
  Bool.pick(U32, U32.is_eq(code, 48), 2, Bool.pick(U32, is_digit(code), 3, invalid_number()))

def after_integer(+more_digits: Bool, +code: U32) -> U32:
  Bool.pick(U32, U32.is_eq(code, 46), 4, Bool.pick(U32, is_exponent(code), 6,
    Bool.pick(U32, more_digits && is_digit(code), 3, invalid_number())))

def in_fraction(+code: U32) -> U32:
  Bool.pick(U32, is_digit(code), 5, Bool.pick(U32, is_exponent(code), 6, invalid_number()))

def after_exponent(+code: U32) -> U32:
  Bool.pick(U32, U32.is_eq(code, 43) || U32.is_eq(code, 45), 7, Bool.pick(U32, is_digit(code), 8, invalid_number()))

def digit_state(+next: U32, +code: U32) -> U32:
  Bool.pick(U32, is_digit(code), next, invalid_number())

# The JSON number grammar over its characters: 0 start, 1 after '-', 2 after a leading 0, 3 in the integer digits,
# 4 after '.', 5 in the fraction, 6 after 'e', 7 after the exponent sign, 8 in the exponent, 9 invalid.
def number_step(+state: U32, +code: U32) -> U32:
  match state:
    case 0:
      Bool.pick(U32, U32.is_eq(code, 45), 1, integer_start(code))
    case 1:
      integer_start(code)
    case 2:
      after_integer(False{}, code)
    case 3:
      after_integer(True{}, code)
    case 4:
      digit_state(5, code)
    case 5:
      in_fraction(code)
    case 6:
      after_exponent(code)
    case 7:
      digit_state(8, code)
    case 8:
      digit_state(8, code)
    case _:
      invalid_number()

def number_state(s: String, +state: U32) -> U32:
  match s:
    case SNil{}:
      state
    case SCon{Chr{+code}, rest}:
      number_state(rest, number_step(state, code))

def is_number_end(+state: U32) -> Bool:
  U32.is_eq(state, 2) || U32.is_eq(state, 3) || U32.is_eq(state, 5) || U32.is_eq(state, 8)

def fits_after(+acc: U32, +code: U32) -> Bool:
  is_digit(code) && ((acc < 429496729 : U32) || (U32.is_eq(acc, 429496729) && (code <= 53 : U32)))

type Whole is Data:
  Whole{fits: Bool, value: U32}

def whole_digits(s: String, +acc: U32, +fits: Bool) -> Whole:
  match s:
    case SNil{}:
      Whole{fits, acc}
    case SCon{Chr{+code}, rest}:
      whole_digits(rest, (acc * 10 + code - 48 : U32), fits && fits_after(acc, code))

def as_number(w: Whole, +text: String) -> Json:
  match w:
    case Whole{True{}, +value}:
      JNum{value}
    case _:
      JReal{text}

def is_integer_text(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+code}, rest}:
      is_digit(code) && is_integer_text(rest)

def number_value(+text: String) -> Json:
  Bool.pick(Json, String.eq(text, "-0"), JNum{0},
    Bool.pick(Json, is_integer_text(text), as_number(whole_digits(text, 0, True{}), text), JReal{text}))

def number_token(+text: String, +rest: String) -> Lexed:
  Bool.pick(Lexed, is_number_end(number_state(text, 0)), Lexed{TValue{number_value(text)}, rest}, bad("invalid number " ++ text, rest))

type Peek is Data:
  PDigit{code: U32, rest: String}
  PStop{rest: String}

def peek_char(+code: U32, +rest: String) -> Peek:
  Bool.pick(Peek, is_number_char(code), PDigit{code, rest}, PStop{SCon{Chr{code}, rest}})

def peek_number(s: String) -> Peek:
  match s:
    case SNil{}:
      PStop{SNil{}}
    case SCon{Chr{+code}, rest}:
      peek_char(code, rest)

def read_number(fuel: Nat, p: Peek, acc: String) -> Lexed:
  match fuel p:
    case 0n _:
      bad("number too long", SNil{})
    case 1n+f PDigit{+code, rest}:
      read_number(f, peek_number(rest), SCon{Chr{code}, acc})
    case 1n+f PStop{rest}:
      number_token(String.reverse(acc), rest)

def word(+expected: String, +value: Json, +rest: String) -> Lexed:
  +matched = String.starts_with(rest, expected)
  Bool.pick(Lexed, matched, Lexed{TValue{value}, String.drop(rest, String.length(expected))}, bad("unexpected text", rest))

def is_space(+code: U32) -> Bool:
  U32.is_eq(code, 32) || U32.is_eq(code, 9) || U32.is_eq(code, 10) || U32.is_eq(code, 13)

def lex_other(+code: U32, +rest: String) -> Lexed:
  Bool.pick(Lexed, is_space(code), Lexed{TSkip{}, rest},
    Bool.pick(Lexed, is_digit(code) || U32.is_eq(code, 45), read_number(16777216n, peek_number(rest), SCon{Chr{code}, SNil{}}),
      bad("unexpected character " ++ String.from_list([Chr{code}]), rest)))

def lex(s: String) -> Lexed:
  match s:
    case SNil{}:
      Lexed{TEnd{}, SNil{}}
    case SCon{Chr{+code}, +rest}:
      match code:
        case 34:
          read_string(16777216n, string_piece(rest), SNil{})
        case 123:
          Lexed{TOpen{True{}}, rest}
        case 91:
          Lexed{TOpen{False{}}, rest}
        case 125:
          Lexed{TClose{True{}}, rest}
        case 93:
          Lexed{TClose{False{}}, rest}
        case 44:
          Lexed{TComma{}, rest}
        case 58:
          Lexed{TColon{}, rest}
        case 116:
          word("rue", JBool{True{}}, rest)
        case 102:
          word("alse", JBool{False{}}, rest)
        case 110:
          word("ull", JNull{}, rest)
        case _:
          lex_other(code, rest)

def malformed(+detail: String) -> U32 & String:
  (2, "config: malformed JSON: " ++ detail)

def attach(frames: List<&2, Frame>, value: Json) -> Result<&1, &1, U32 & String, Parser>:
  match frames:
    case Nil{}:
      Done{Parser{XEnd{}, Nil{}, Some{value}}}
    case Con{FArr{items}, rest}:
      Done{Parser{XNext{}, FArr{value <> items} <> rest, None{}}}
    case Con{FKey{key}, Con{FObj{fields}, rest}}:
      Done{Parser{XNext{}, FObj{JField{key, value} <> fields} <> rest, None{}}}
    case _:
      Fail{malformed("unexpected structure")}

def closed(frames: List<&2, Frame>, +object: Bool) -> Result<&1, &1, U32 & String, Parser>:
  match frames:
    case Con{FArr{items}, rest}:
      Bool.pick(Result<&1, &1, U32 & String, Parser>, object, Fail{malformed("mismatched brackets")},
        attach(rest, JArr{List.reverse(&2, Json, items)}))
    case Con{FObj{fields}, rest}:
      Bool.pick(Result<&1, &1, U32 & String, Parser>, object, attach(rest, JObj{List.reverse(&2, Json, fields)}),
        Fail{malformed("mismatched brackets")})
    case _:
      Fail{malformed("unexpected closing bracket")}

def opened(+object: Bool, frames: List<&2, Frame>) -> Result<&1, &1, U32 & String, Parser>:
  Done{Parser{Bool.pick(Expect, object, XKeyOrClose{}, XValueOrClose{}), Bool.pick(Frame, object, FObj{Nil{}}, FArr{Nil{}}) <> frames, None{}}}

def expecting_value(token: Token, frames: List<&2, Frame>) -> Result<&1, &1, U32 & String, Parser>:
  match token:
    case TValue{value}:
      attach(frames, value)
    case TOpen{+object}:
      opened(object, frames)
    case _:
      Fail{malformed("expecting a value")}

def key_frame(value: Json, frames: List<&2, Frame>) -> Result<&1, &1, U32 & String, Parser>:
  match value:
    case JStr{key}:
      Done{Parser{XColon{}, FKey{key} <> frames, None{}}}
    case _:
      Fail{malformed("object keys must be strings")}

def expecting_key(token: Token, frames: List<&2, Frame>, close: Bool) -> Result<&1, &1, U32 & String, Parser>:
  match token close:
    case TValue{value} _:
      key_frame(value, frames)
    case TClose{True{}} True{}:
      closed(frames, True{})
    case _ _:
      Fail{malformed("expecting a property name")}

def after_comma(frames: List<&2, Frame>) -> Result<&1, &1, U32 & String, Parser>:
  match frames:
    case Con{FArr{items}, rest}:
      Done{Parser{XValue{}, FArr{items} <> rest, None{}}}
    case Con{FObj{fields}, rest}:
      Done{Parser{XKey{}, FObj{fields} <> rest, None{}}}
    case _:
      Fail{malformed("unexpected comma")}

def expecting_next(token: Token, frames: List<&2, Frame>) -> Result<&1, &1, U32 & String, Parser>:
  match token:
    case TComma{}:
      after_comma(frames)
    case TClose{+object}:
      closed(frames, object)
    case _:
      Fail{malformed("expecting ',' or a closing bracket")}

def expecting_colon(token: Token, frames: List<&2, Frame>) -> Result<&1, &1, U32 & String, Parser>:
  match token:
    case TColon{}:
      Done{Parser{XValue{}, frames, None{}}}
    case _:
      Fail{malformed("expecting ':'")}

def value_or_close(token: Token, frames: List<&2, Frame>) -> Result<&1, &1, U32 & String, Parser>:
  match token:
    case TClose{False{}}:
      closed(frames, False{})
    case other:
      expecting_value(other, frames)

def advance(p: Parser, token: Token) -> Result<&1, &1, U32 & String, Parser>:
  match p:
    case Parser{XValue{}, frames, _}:
      expecting_value(token, frames)
    case Parser{XValueOrClose{}, frames, _}:
      value_or_close(token, frames)
    case Parser{XKeyOrClose{}, frames, _}:
      expecting_key(token, frames, True{})
    case Parser{XKey{}, frames, _}:
      expecting_key(token, frames, False{})
    case Parser{XColon{}, frames, _}:
      expecting_colon(token, frames)
    case Parser{XNext{}, frames, _}:
      expecting_next(token, frames)
    case Parser{XEnd{}, _, _}:
      Fail{malformed("extra data")}

def finish(p: Parser) -> Result<&1, &1, U32 & String, Json>:
  match p:
    case Parser{XEnd{}, _, Some{value}}:
      Done{value}
    case _:
      Fail{malformed("incomplete")}

def parse_loop(fuel: Nat, state: Result<&1, &1, U32 & String, Parser>, lexed: Lexed) -> Result<&1, &1, U32 & String, Json>:
  match fuel state lexed:
    case 0n _ _:
      Fail{malformed("too deep")}
    case 1n+p Fail{e} _:
      Fail{e}
    case 1n+p Done{parser} Lexed{TEnd{}, _}:
      finish(parser)
    case 1n+p Done{_} Lexed{TBad{message}, _}:
      Fail{(2, message)}
    case 1n+p Done{parser} Lexed{TSkip{}, rest}:
      parse_loop(p, Done{parser}, lex(rest))
    case 1n+p Done{parser} Lexed{token, rest}:
      parse_loop(p, advance(parser, token), lex(rest))

# Parses a whole JSON text; a failure is (2, "config: malformed JSON: <detail>").
def parse(+text: String) -> Result<&1, &1, U32 & String, Json>:
  parse_loop(Nat.add(String.length(text), 1n), Done{Parser{XValue{}, Nil{}, None{}}}, lex(text))

def hex_char(+nibble: U32) -> Char:
  Chr{Bool.pick(U32, (nibble < 10 : U32), (nibble + 48 : U32), (nibble + 87 : U32))}

def u_escape(+code: U32) -> String:
  "\\u" ++ String.from_list([hex_char(((code >> 12n) .&. 15 : U32)), hex_char(((code >> 8n) .&. 15 : U32)),
    hex_char(((code >> 4n) .&. 15 : U32)), hex_char((code .&. 15 : U32))])

def astral_escape(+code: U32) -> String:
  +offset = (code - 65536 : U32)
  u_escape((55296 + (offset >> 10n) : U32)) ++ u_escape((56320 + (offset .&. 1023) : U32))

def control_escape(+code: U32) -> String:
  Bool.pick(String, U32.is_eq(code, 10), "\\n", Bool.pick(String, U32.is_eq(code, 13), "\\r",
    Bool.pick(String, U32.is_eq(code, 9), "\\t", Bool.pick(String, U32.is_eq(code, 8), "\\b",
      Bool.pick(String, U32.is_eq(code, 12), "\\f", u_escape(code))))))

def escaped_char(+ascii: Bool, +code: U32) -> String:
  Bool.pick(String, U32.is_eq(code, 34) || U32.is_eq(code, 92), SCon{Chr{92}, SCon{Chr{code}, SNil{}}},
    Bool.pick(String, (code < 32 : U32), control_escape(code),
      Bool.pick(String, ascii && (code >= 65536 : U32), astral_escape(code),
        Bool.pick(String, ascii && (code >= 127 : U32), u_escape(code), SCon{Chr{code}, SNil{}}))))

def escaped(+ascii: Bool, s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+code}, rest}:
      escaped_char(ascii, code) ++ escaped(ascii, rest)

# A string as Python's json.dumps writes it: quoted, with \" \\ \n \r \t \b \f and \u00XX escapes, and (ascii)
# \uXXXX escapes for everything past 126.
def quote(+ascii: Bool, +s: String) -> String:
  "\"" ++ escaped(ascii, s) ++ "\""

type Work is Data:
  WText{text: String}
  WJson{json: Json}

def listed(+ascii: Bool, items: List<&2, Json>, +closing: String) -> List<&2, Work>:
  match items:
    case Nil{}:
      [WText{closing}]
    case Con{JField{+key, value}, Nil{}}:
      [WText{quote(ascii, key) ++ ": "}, WJson{value}, WText{closing}]
    case Con{JField{+key, value}, rest}:
      WText{quote(ascii, key) ++ ": "} <> WJson{value} <> WText{", "} <> listed(ascii, rest, closing)
    case Con{item, Nil{}}:
      [WJson{item}, WText{closing}]
    case Con{item, rest}:
      WJson{item} <> WText{", "} <> listed(ascii, rest, closing)

def expand(+ascii: Bool, json: Json) -> List<&2, Work>:
  match json:
    case JNull{}:
      [WText{"null"}]
    case JBool{value}:
      [WText{Bool.pick(String, value, "true", "false")}]
    case JNum{value}:
      [WText{U32.show(value)}]
    case JReal{text}:
      [WText{text}]
    case JStr{value}:
      [WText{quote(ascii, value)}]
    case JArr{items}:
      WText{"["} <> listed(ascii, items, "]")
    case JObj{fields}:
      WText{"{"} <> listed(ascii, fields, "}")
    case JField{+key, value}:
      [WText{quote(ascii, key) ++ ": "}, WJson{value}]

def dump_loop(fuel: Nat, +ascii: Bool, work: List<&2, Work>, acc: String) -> String:
  match fuel work:
    case 0n _:
      acc
    case 1n+p Nil{}:
      acc
    case 1n+p Con{WText{text}, rest}:
      dump_loop(p, ascii, rest, acc ++ text)
    case 1n+p Con{WJson{json}, rest}:
      dump_loop(p, ascii, List.append(&2, Work, expand(ascii, json), rest), acc)

def dump_with(+ascii: Bool, json: Json) -> String:
  dump_loop(1000000n, ascii, [WJson{json}], "")

# The JSON text of a value as Python's json.dumps (default separators) writes it; a real prints its source text.
def dump(json: Json) -> String:
  dump_with(True{}, json)

# The same with non-ASCII characters kept (ensure_ascii=False).
def dump_text(json: Json) -> String:
  dump_with(False{}, json)
