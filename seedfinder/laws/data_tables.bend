import Base
import ../data/blob.bend as Blob
import ../data/layouts.bend as Layouts
import ../data/cave_story.bend as CaveStory
import ../lua/strhash.bend as StrHash
import ../data/strings.bend as Strings
import ../data/builds.bend as Builds

# The direct lookup `table_at(i, j)` reads the unit that `Blob.at(table(i), j)` reads from the decoded row, for every row of
# the layout tables and the cave tasks (plus two rows past the end), at units up to 16 (past a short row's end included),
# in every registered build.

def variants_row(+build: Builds.Build, n: Nat, +i: U32, +j: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      Bool.and(U32.is_eq(Layouts.variants_at(build, i, j), Blob.at(Layouts.variants(build, i), j)),
        Bool.and(U32.is_eq(Layouts.ground_at(build, i, j), Blob.at(Layouts.ground(build, i), j)),
          variants_row(build, p, i, (j + 1 : U32))))

def variants_rows(+build: Builds.Build, n: Nat, +i: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      Bool.and(variants_row(build, 16n, i, 0), variants_rows(build, p, (i + 1 : U32)))

def states_rows(+build: Builds.Build, n: Nat, +i: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      Bool.and(U32.is_eq(Layouts.states_at(build, i, 3), Blob.at(Layouts.states(build, i), 3)),
        Bool.and(U32.is_eq(Layouts.states_at(build, i, 9), Blob.at(Layouts.states(build, i), 9)), states_rows(build, p, (i + 1 : U32))))

def tasks_rows(+build: Builds.Build, n: Nat, +i: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      Bool.and(U32.is_eq(CaveStory.tasks_at(build, i, 5), Blob.at(CaveStory.tasks(build, i), 5)),
        Bool.and(U32.is_eq(CaveStory.tasks_at(build, i, 14), Blob.at(CaveStory.tasks(build, i), 14)), tasks_rows(build, p, (i + 1 : U32))))

def lookups_hold(+build: Builds.Build) -> Bool:
  Bool.and(variants_rows(build, U32.to_nat(Layouts.variants_count(build)), 0), Bool.and(states_rows(build, U32.to_nat(Layouts.states_count(build)), 0),
    tasks_rows(build, U32.to_nat((CaveStory.tasks_count(build) + 2 : U32)), 0)))

# A string row's luaS_hash is the hash of its bytes, and the row past the table's end is empty.
def strings_hold(+build: Builds.Build) -> Bool:
  Bool.and(U32.is_eq(Strings.hash(build, 31), StrHash.hash_string(Strings.name(build, 31))),
    Bool.and(U32.is_eq(Strings.hash(build, 32), StrHash.hash_string(Strings.name(build, 32))),
      List.is_empty(&2, U32, Strings.strings(build, Strings.strings_count(build)))))

def every_build(~holds: @+build:Builds.Build -> Bool, numbers: List<&2, U32>) -> Bool:
  match numbers:
    case Nil{}:
      True{}
    case Con{+n, rest}:
      Bool.and(holds(Builds.Build{n}), every_build(~holds, rest))

law direct_lookup_equals_decoded_row:
  {every_build(~lookups_hold, Builds.numbers()) == True{} : Bool}

def direct_lookup_equals_decoded_row():
  {==}

law string_rows_hash_their_bytes:
  {every_build(~strings_hold, Builds.numbers()) == True{} : Bool}

def string_rows_hash_their_bytes():
  {==}

# The data tables decode across a chunk boundary (rows 31 and 32 of the string table, each with the luaS_hash of its
# bytes), and a row past the table's end is empty.
law data_rows_across_chunks:
  {[Strings.name(Builds.Build{756039}, 31), Strings.name(Builds.Build{756039}, 32)] == ["BGBadlands", "BGDeciduous"] : List<&2, String>}

def data_rows_across_chunks():
  {==}

law data_row_hashes:
  {[Strings.hash(Builds.Build{756039}, 31), Strings.hash(Builds.Build{756039}, 32)] == [StrHash.hash_string("BGBadlands"), StrHash.hash_string("BGDeciduous")] : List<&2, U32>}

def data_row_hashes():
  {==}

law data_row_past_end:
  {Strings.strings(Builds.Build{756039}, Strings.strings_count(Builds.Build{756039})) == Nil{} : List<&2, U32>}

def data_row_past_end():
  {==}
