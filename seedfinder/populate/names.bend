import Base
import ../data/strings.bend as Strings
import ../lua/strhash.bend as StrHash
import ../data/builds.bend as Builds

def scan(+build: Builds.Build, n: Nat, +id: U32, +hash: U32) -> U32:
  match n:
    case 0n:
      4294967295
    case 1n+p:
      Bool.pick(U32, U32.is_eq(Strings.hash(build, id), hash), id, scan(build, p, (id + 1 : U32), hash))

# The string id (data/strings.bend) of a name, NONE when the game data has no such string.
def string_id(+build: Builds.Build, name: String) -> U32:
  scan(build, U32.to_nat(Strings.strings_count(build)), 0, StrHash.hash_string(name))
