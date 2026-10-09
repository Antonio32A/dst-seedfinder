import Base
import ../data/blob.bend as Blob
import ../data/layouts.bend as Layouts
import ../data/cave_story.bend as CaveStory
import ../lua/strhash.bend as StrHash
import ../data/strings.bend as Strings

# The direct lookup `table_at(i, j)` reads the unit that `Blob.at(table(i), j)` reads from the decoded row, for every row of
# the layout tables and the cave tasks (plus two rows past the end), at units up to 16 (past a short row's end included).

def variants_row(n: Nat, +i: U32, +j: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      Bool.and(U32.is_eq(Layouts.variants_at(i, j), Blob.at(Layouts.variants(i), j)),
        Bool.and(U32.is_eq(Layouts.ground_at(i, j), Blob.at(Layouts.ground(i), j)),
          variants_row(p, i, (j + 1 : U32))))

def variants_rows(n: Nat, +i: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      Bool.and(variants_row(16n, i, 0), variants_rows(p, (i + 1 : U32)))

def states_rows(n: Nat, +i: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      Bool.and(U32.is_eq(Layouts.states_at(i, 3), Blob.at(Layouts.states(i), 3)),
        Bool.and(U32.is_eq(Layouts.states_at(i, 9), Blob.at(Layouts.states(i), 9)), states_rows(p, (i + 1 : U32))))

def tasks_rows(n: Nat, +i: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      Bool.and(U32.is_eq(CaveStory.tasks_at(i, 5), Blob.at(CaveStory.tasks(i), 5)),
        Bool.and(U32.is_eq(CaveStory.tasks_at(i, 14), Blob.at(CaveStory.tasks(i), 14)), tasks_rows(p, (i + 1 : U32))))

law direct_lookup_equals_decoded_row:
  {Bool.and(variants_rows(U32.to_nat(Layouts.variants_count()), 0), Bool.and(states_rows(U32.to_nat(Layouts.states_count()), 0), tasks_rows(U32.to_nat((CaveStory.tasks_count() + 2 : U32)), 0))) == True{} : Bool}

def direct_lookup_equals_decoded_row():
  {==}

# The data tables decode across a chunk boundary (rows 31 and 32 of the string table, each with the luaS_hash of its
# bytes), and a row past the table's end is empty.
law data_rows_across_chunks:
  {[Strings.name(31), Strings.name(32)] == ["BGBadlands", "BGDeciduous"] : List<&2, String>}

def data_rows_across_chunks():
  {==}

law data_row_hashes:
  {[Strings.hash(31), Strings.hash(32)] == [StrHash.hash_string("BGBadlands"), StrHash.hash_string("BGDeciduous")] : List<&2, U32>}

def data_row_hashes():
  {==}

law data_row_past_end:
  {Strings.strings(Strings.strings_count()) == Nil{} : List<&2, U32>}

def data_row_past_end():
  {==}
