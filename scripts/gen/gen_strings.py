#!/usr/bin/env python3
"""Writes data/strings.bend: every constant string of the story, layout, distribute and ocean data, with its Lua 5.1
luaS_hash (the TString hash Lua uses for table keys) and bytes. `-` prints the module instead of writing it; without
arguments it also writes the sidecar out/strings.json (id, string, hash) used by lane S tests and M2 fuzzing."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402


def lua_hash(s):
    data = s.encode("utf-8")
    length = len(data)
    h = length & 0xFFFFFFFF
    step = (length >> 5) + 1
    i = length
    while i >= step:
        h = (h ^ (((h << 5) & 0xFFFFFFFF) + (h >> 2) + data[i - 1])) & 0xFFFFFFFF
        i -= step
    return h


def main():
    t = ids.table()
    m = blob.Module("strings", "scripts/gen/gen_strings.py",
                    "Constant strings: id -> (luaS_hash, bytes). Tasks first (world_catalog task ids), then sorted.")
    rows = [blob.word(lua_hash(s)) + blob.text(s) for s in t["strings"]]
    m.table("strings", rows, "Row id: hash (2 units), byte count, bytes packed two per unit.")
    m.const("others_base", t["others_base"])
    m.code('''
# Lua 5.1 luaS_hash of string id.
def hash(+id: U32) -> U32:
  B.word(strings(id), 0)

# Byte length of string id.
def length(+id: U32) -> U32:
  B.at(strings(id), 2)

# The bytes of string id as a String (one Char per byte).
def name(+id: U32) -> String:
  B.text(B.drop(strings(id), 2))
''')
    m.emit()
    if sys.argv[1:] != ["-"]:
        side = [{"id": i, "string": s, "hash": lua_hash(s)} for i, s in enumerate(t["strings"])]
        (blob.GEN / "out" / "strings.json").write_text(json.dumps({
            "others_base": t["others_base"],
            "strings": side}, indent=0) + "\n")


if __name__ == "__main__":
    main()
