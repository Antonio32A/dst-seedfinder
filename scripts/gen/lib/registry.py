"""The game builds the seed finder supports: builds.json at the repository root (hand-edited, append-only, with an
explicit latest build). Each entry has `number`, `label`, `channel`, `steam_branch`, `shards`, `website` and `catalog`
(the build whose scripts/catalog/<build>/ catalogs each shard uses)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / "builds.json"
CATALOG_FILES = {"forest": "catalog.json", "caves": "cave_catalog.json"}


def load():
    registry = json.loads(PATH.read_text(encoding="utf-8"))
    numbers = [b["number"] for b in registry["builds"]]
    assert len(set(numbers)) == len(numbers), f"{PATH.name}: a build is registered twice: {numbers}"
    assert registry["latest"] in numbers, f"{PATH.name}: the latest build {registry['latest']} is not registered"
    return registry


def builds():
    return load()["builds"]


def latest():
    return load()["latest"]


def entry(number):
    """The registry entry of build `number`."""
    found = [b for b in builds() if b["number"] == number]
    assert found, f"{PATH.name}: build {number} is not registered"
    return found[0]


def catalog_path(number, shard):
    """The catalog JSON build `number` uses for `shard` (forest or caves)."""
    return ROOT / "scripts" / "catalog" / str(entry(number)["catalog"][shard]) / CATALOG_FILES[shard]
