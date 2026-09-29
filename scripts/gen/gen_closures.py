#!/usr/bin/env python3
"""Writes data/closures.bend: the ids of the closure variants (distinct function body + upvalues) found in the
constant story, layout and ocean tables, which the data modules reference and the porting lanes implement by hand
(one Bend def per variant). Without `-` it also writes the sidecar out/closures.json (bodies, sites, contexts,
upvalues, referenced globals)."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402

FNV_OFFSET = 0x811C9DC5
FNV_PRIME = 0x01000193
CATEGORIES = ["task", "room", "layout_area", "layout_count", "layout_initfn", "maptag", "noise", "bunch"]


def category(context):
    head = context.split(":", 1)[0]
    if head == "room" and context.endswith(":prefabdata"):
        return "room"
    return head


def fingerprint(key):
    """FNV-1a (32 bit) of the closure variant's body and upvalues: what a hand port pins itself to."""
    h = FNV_OFFSET
    for byte in key.encode("utf-8"):
        h = ((h ^ byte) * FNV_PRIME) & 0xFFFFFFFF
    return h


def main():
    closures = ids.closures()
    m = blob.Module("closures", "scripts/gen/gen_closures.py",
                    "Closure variants referenced by the data modules (bodies in scripts/gen/out/closures.json).",
                    imports=("./blob.bend as Blob",))
    m.comment("Categories: " + ", ".join(f"{i} {c}" for i, c in enumerate(CATEGORIES)) + ".",
              "Evaluated in this build: IsSpecialEventActive(SPECIAL_EVENTS.HALLOWED_NIGHTS) is false, SIZE_VARIATION 3.")
    for c in closures:
        globals_text = ", ".join(f"{g['name']}={g['value']}" for g in c["globals"])
        body = c["body"] if len(c["body"]) <= 160 else c["body"][:157] + "..."
        m.comment(f"{c['id']}: {c['sites'][0]} {body}" + (f"  [{globals_text}]" if globals_text else ""))
    rows = []
    for c in closures:
        cats = sorted({CATEGORIES.index(category(x)) for x in c["contexts"]})
        rows.append(cats)
    m.lines.append("")
    m.table("closure_categories", rows, "Row id: the categories of the contexts it appears in.")
    m.const("closure_count", len(closures))
    cases = "\n".join(f"    case {c['id']}:\n      {fingerprint(c['key'])}" for c in closures)
    m.comment("Row id: the fingerprint (FNV-1a of the variant's body and upvalues) that hand ports pin themselves to.")
    m.code(f"def closure_fingerprint(+id: U32) -> U32:\n  match id:\n{cases}\n    case _:\n      0")
    m.emit()
    if sys.argv[1:] != ["-"]:
        (blob.GEN / "out" / "closures.json").write_text(json.dumps(
            [{k: c[k] for k in ("id", "body", "sites", "contexts", "upvalues", "globals")} for c in closures],
            indent=1) + "\n")


if __name__ == "__main__":
    main()
