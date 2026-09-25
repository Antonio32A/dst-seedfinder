#!/usr/bin/env python3
"""Writes data/ocean_post.bend from out/ocean_post.json (extract_ocean_post.lua): PopulateOcean's point search
increments, the monkey island dock generator's data, wormhole pairing, prefab swap proxies, the level's required
prefabs and the ocean map constants. `-` prints the module instead."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402
import ids  # noqa: E402


def chance_rows(entries):
    return [[ids.sid(e["prefab"])] + blob.f64(e["chance"]) + blob.word(blob.random_threshold(e["chance"]))
            for e in entries]


def f64_const(m, name, value):
    bits = blob.f64_bits(value)
    m.const(name, f"({bits >> 32}, {bits & 0xFFFFFFFF})", "U32 & U32")


def main():
    d = blob.sidecar("ocean_post.json")
    docks = d["docks"]
    m = blob.Module("ocean_post", "scripts/gen/gen_ocean_post.py",
                    "Ocean phase constants after the conversion: water points, docks, wormholes, proxies, required prefabs.")
    m.table("water_point_incs", [[blob.unit(v) for v in d["water_point_incs"]]],
            "Row 0: GetRandomWaterPoints' scan increments in order.")
    m.const("min_wormhole_id", d["min_wormhole_id"])
    m.const("wormhole_prefab", ids.sid(d["wormhole_prefab"]))
    m.const("wormhole_marker", ids.sid("wormhole_MARKER"))
    m.const("dock_center_prefab", ids.sid(docks["center_prefab"]))
    m.const("dock_direction_prefab", ids.sid(docks["direction_prefab"]))
    m.const("dock_safety_prefab", ids.sid(docks["safety_prefab"]))
    m.const("dock_tile_registrator", ids.sid("dock_tile_registrator"))
    m.const("dock_woodposts", ids.sid("dock_woodposts"))
    f64_const(m, "dock_post_chance", docks["dock_post_chance"])
    m.const("dock_post_threshold", blob.random_threshold(docks["dock_post_chance"]))
    m.table("dock_prefabs", chance_rows(docks["dock_prefabs"]),
            "Row i in pairs(dock_prefabs_withchance) order: prefab, chance (f64, 4 units), math.random() < chance threshold.")
    m.table("endpoint_prefabs", chance_rows(docks["endpoint_prefabs"]),
            "Row i in pairs(endpoint_prefabs_with_chance) order: prefab, chance (f64, 4 units), threshold.")
    m.const("dock_amount", docks["amount"])
    m.const("dock_min_length", docks["min_length"])
    m.const("dock_max_length", docks["max_length"])
    f64_const(m, "dock_safe_width", docks["safe_width"])
    f64_const(m, "dock_safe_height", docks["safe_height"])
    m.table("customization_proxies", [[ids.sid(p["proxy"])] + [ids.sid(r) for r in p["real"]]
                                      for p in d["customization_proxies"]],
            "Row i in pairs() order: proxy prefab, the real prefab.")
    m.table("randomization_proxies", [[ids.sid(p["proxy"])] + [ids.sid(r) for r in p["real"]]
                                      for p in d["randomization_proxies"]],
            "Row i in pairs() order: proxy prefab, then the prefabs math.random(#choices) picks from.")
    m.table("level_required_prefabs", [[ids.sid(p) for p in d["level_required_prefabs"]]],
            "Row 0: level.required_prefabs in ipairs order.")
    results = [r for b in blob.sidecar("ocean.json")["bunches"] for r in (b.get("prefab_results") or [])]
    m.table("bunch_closure_results", [[ids.sid(r) for r in results]],
            "Row 0: the prefabs the bunch prefab closure (wobster_den_spawner_shore) returns: on a moon beach tile, else.")
    m.const("ocean_population_edge_dist", d["ocean_population_edge_dist"])
    m.const("ocean_waterfall_max_dist", d["ocean_waterfall_max_dist"])
    m.const("tile_scale", d["tile_scale"])
    m.emit()


if __name__ == "__main__":
    main()
