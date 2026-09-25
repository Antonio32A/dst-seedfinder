import Base

# The canonical text format shared by the oracle dumps and `seedfinder trace` (.scratch/port/CONVENTIONS.md
# "Canonical records"): one record per line, `kind key=value key=value ...`.

def hex_digit(+d: U32) -> String:
  SCon{Chr{Bool.pick(U32, (d < 10 : U32), (48 + d : U32), (87 + d : U32))}, SNil{}}

def hex_loop(n: Nat, +x: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      hex_loop(p, (x >> 4n : U32), hex_digit((x .&. 15 : U32)) ++ acc)

# 8 lowercase hex digits (an F32's bits, a 32-bit hash).
def hex32(+x: U32) -> String:
  hex_loop(8n, x, "")

# 16 lowercase hex digits of hi:lo (an F64's bits, a PCG state, a 64-bit hash).
def hex64(+hi: U32, +lo: U32) -> String:
  hex32(hi) ++ hex32(lo)

def escaped(+code: U32) -> String:
  Bool.pick(String, U32.is_eq(code, 34) || U32.is_eq(code, 92), SCon{Chr{92}, SCon{Chr{code}, SNil{}}}, SCon{Chr{code}, SNil{}})

def escape_all(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+code}, rest}:
      escaped(code) ++ escape_all(rest)

# A string value: double quotes, with `"` and `\` escaped by a backslash.
def quoted(+s: String) -> String:
  "\"" ++ escape_all(s) ++ "\""

def field(+key: String, +value: String) -> String:
  key ++ "=" ++ value

def number(+key: String, +value: U32) -> String:
  field(key, U32.show(value))

def record(+kind: String, fields: List<&2, String>) -> String:
  String.join(kind <> fields, " ")

type Lexer is Data:
  Lexer{quoting: Bool, escaping: Bool, current: List<&2, U32>, tokens: List<&2, String>}

def text_of(codes: List<&2, U32>, acc: String) -> String:
  match codes:
    case Nil{}:
      acc
    case Con{+code, rest}:
      text_of(rest, SCon{Chr{code}, acc})

def flushed(current: List<&2, U32>, tokens: List<&2, String>) -> List<&2, String>:
  match current:
    case Nil{}:
      tokens
    case _:
      text_of(current, "") <> tokens

def lex_next(splits: Bool, +quoting: Bool, +escaping: Bool, +code: U32, current: List<&2, U32>, tokens: List<&2, String>) -> Lexer:
  match splits:
    case True{}:
      Lexer{quoting, False{}, Nil{}, flushed(current, tokens)}
    case False{}:
      +quote = U32.is_eq(code, 34) && Bool.not(escaping)
      Lexer{Bool.pick(Bool, quote, Bool.not(quoting), quoting), quoting && Bool.not(escaping) && U32.is_eq(code, 92),
        code <> current, tokens}

def lex_char(st: Lexer, +code: U32) -> Lexer:
  match st:
    case Lexer{+quoting, +escaping, current, tokens}:
      lex_next(Bool.not(quoting) && U32.is_eq(code, 32), quoting, escaping, code, current, tokens)

def lex(s: String, st: Lexer) -> Lexer:
  match s:
    case SNil{}:
      st
    case SCon{Chr{+code}, rest}:
      lex(rest, lex_char(st, code))

def lexed(st: Lexer) -> List<&2, String>:
  match st:
    case Lexer{_, _, +current, +tokens}:
      List.reverse(&2, String, flushed(current, tokens))

# The tokens of a record line: the kind, then `key=value` fields (quoted values may contain spaces).
def tokens(+line: String) -> List<&2, String>:
  lexed(lex(line, Lexer{False{}, False{}, Nil{}, Nil{}}))

# The raw value of `key` in a tokenized record (a quoted value keeps its quotes), if present.
def value_of(+key: String, fields: List<&2, String>) -> Maybe<&2, String>:
  match fields:
    case Nil{}:
      None{}
    case Con{+token, rest}:
      Bool.pick(Maybe<&2, String>, String.starts_with(token, key ++ "="), Some{String.drop(token, Nat.add(String.length(key), 1n))},
        value_of(key, rest))

def text_or(m: Maybe<&2, String>, +fallback: String) -> String:
  Maybe.default(&2, String, m, fallback)

def number_or(m: Maybe<&2, String>, +fallback: U32) -> U32:
  match m:
    case None{}:
      fallback
    case Some{s}:
      Maybe.default(&2, U32, U32.read(s), fallback)

def is_kind(+kind: String, +line: String) -> Bool:
  String.starts_with(line, kind ++ " ") || String.eq(line, kind)

def keep_record(matched: Bool, +line: String, tail: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match matched:
    case True{}:
      tokens(line) <> tail
    case False{}:
      tail

# Every record of the given kind, tokenized, in input order.
def records(+kind: String, lines: List<&2, String>) -> List<&2, List<&2, String>>:
  match lines:
    case Nil{}:
      Nil{}
    case Con{+line, rest}:
      keep_record(is_kind(kind, line), line, records(kind, rest))
