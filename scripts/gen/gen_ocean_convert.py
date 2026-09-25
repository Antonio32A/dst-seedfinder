#!/usr/bin/env python3
"""Writes data/ocean_convert.bend: the numbers Ocean_ConvertImpassibleToWater (map/ocean_gen.lua) runs with for the
default forest, i.e. each `data.key or default` with data = map/ocean_gen_config.lua (out/ocean.json, as the game
loads it; misspelt config keys do not count), the literals of its blend levels, edge falloff and void outline
tunings, and constants.lua's OCEAN_MAPWRAPPER_WARN_RANGE / OCEAN_WATERFALL_MAX_DIST. The blur kernel itself is
data/constants.bend's (gen_constants.cpp); this checks it was made for the same kernelSize and sigma.
`-` prints the module instead."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import blob  # noqa: E402

SCRIPTS = blob.ROOT / ".scratch" / "game-scripts"
NUMBER = r"(-?[0-9]*\.?[0-9]+)"

INTEGERS = ("shallowRadius", "fillOffset", "fillDepth", "noise_octave_water", "noise_octave_grave", "kernelSize")
DOUBLES = ("noise_persistence_water", "noise_persistence_grave", "noise_scale_water", "noise_scale_grave",
           "init_level_medium", "init_level_grave", "final_level_shallow", "final_level_medium", "final_level_coral",
           "final_level_grave")


def snake(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name).lower()


def number(text):
    value = float(text)
    return int(value) if value.is_integer() and "." not in text else value


def only(pattern, text, what):
    found = re.findall(pattern, text)
    assert len(found) == 1, (what, found)
    return found[0]


def function_body(source, header):
    start = source.index(header)
    end = source.index("\nend\n", start)
    return source[start:end]


def defaults(convert):
    """`local x = data.key or value` in Ocean_ConvertImpassibleToWater, plus do_squarefill's bare data.shallowRadius
    and the groundfill radius fallback."""
    found = {}
    for key, value in re.findall(r"=\s*data\.(\w+)\s+or\s+" + NUMBER, convert):
        assert found.get(key, value) == value, key
        found[key] = value
    assert "do_squarefill(data.shallowRadius)" in convert
    return {k: number(v) for k, v in found.items()}


def effective(config, found, key):
    if key in config:
        return config[key]
    assert key in found, key
    return found[key]


def levels(convert, tiles):
    """The three GenerateBlendedMap calls: (tile, value) rows of the two local level tables, and the defaults."""
    calls = re.findall(r"world:GenerateBlendedMap\(kernelSize, sigma, ([\w.]+), " + NUMBER + r"\)", convert)
    assert [c[0] for c in calls] == ["cmlevels", "glevels", "data.ellevels"], calls
    rows = {}
    for name in ("cmlevels", "glevels"):
        body = only(r"(?s)local " + name + r"\s*=\s*\{(.*?)\n\t\t\}", convert, name)
        rows[name] = [(tiles[t], float(v)) for t, v in re.findall(r"\{WORLD_TILES\.(\w+),\s*" + NUMBER + r"\}", body)]
        assert len(rows[name]) == 1, rows[name]
    return rows, [float(c[1]) for c in calls]


def falloff(convert):
    args = only(r"getEdgeFalloff\(x, y, width, height, OCEAN_MAPWRAPPER_WARN_RANGE \+ (\d+), "
                r"OCEAN_MAPWRAPPER_WARN_RANGE \+ (\d+), " + NUMBER + ", " + NUMBER + r"\)", convert, "falloff")
    return int(args[0]), int(args[1]), float(args[2]), float(args[3])


def tunings(convert):
    middle = only(r"middle = \{max = math\.floor\(OCEAN_WATERFALL_MAX_DIST \* " + NUMBER + r"\), deeper_chance = "
                  + NUMBER + ", shallower_chance = " + NUMBER + r"\}", convert, "middle")
    corner = only(r"corner = \{max = init_d, deeper_chance = " + NUMBER + ", shallower_chance = " + NUMBER + r"\}",
                  convert, "corner")
    assert "local offset = OCEAN_WATERFALL_MAX_DIST" in convert and "local init_d = OCEAN_WATERFALL_MAX_DIST" in convert
    return [float(v) for v in middle], [float(v) for v in corner]


def constant(constants, name):
    return int(only(r"(?m)^" + name + r" = (\d+)\s*$", constants, name))


def f64_const(m, name, value):
    bits = blob.f64_bits(value)
    m.const(name, f"({bits >> 32}, {bits & 0xFFFFFFFF})", "U32 & U32")


def main():
    source = (SCRIPTS / "map" / "ocean_gen.lua").read_text().replace("\r\n", "\n")
    constants = (SCRIPTS / "constants.lua").read_text().replace("\r\n", "\n")
    convert = function_body(source, "function Ocean_ConvertImpassibleToWater(")
    tiles = blob.sidecar("story.json")["enums"]["WORLD_TILES"]
    config = {e["key"]: e["value"] for e in blob.sidecar("ocean.json")["config"] if "value" in e}
    kernel = blob.sidecar("constants_c.json")["blur_kernel"]
    found = defaults(convert)
    m = blob.Module("ocean_convert", "scripts/gen/gen_ocean_convert.py",
                    "Ocean_ConvertImpassibleToWater's parameters for the default forest (ocean_gen_config over the "
                    "ocean_gen.lua defaults).", imports=())
    m.comment("Integers: square fill radius, ground fill offset and depth, noise octaves, blend kernel size.")
    for key in INTEGERS:
        value = effective(config, found, key)
        assert isinstance(value, int), (key, value)
        m.const(snake(key), value)
    m.comment("Doubles (hi, lo bits): noise persistence, scale and levels, final blend levels.")
    for key in DOUBLES:
        f64_const(m, snake(key), effective(config, found, key))
    sigma = effective(config, found, "sigma")
    assert kernel["size"] == effective(config, found, "kernelSize"), kernel
    assert int(kernel["sigma"], 16) == blob.f32_bits(sigma), (kernel, sigma)
    m.const("sigma_bits", blob.f32_bits(sigma))
    rows, fallbacks = levels(convert, tiles)
    m.comment("GenerateBlendedMap levels: the coral (cm) and shipgrave (g) tile with its value, and each call's default.")
    for name, key in (("cm", "cmlevels"), ("g", "glevels")):
        tile, value = rows[key][0]
        m.const(f"{name}_level_tile", tile)
        f64_const(m, f"{name}_level_value", value)
    for name, value in zip(("cm", "g", "el"), fallbacks):
        f64_const(m, f"{name}_default", value)
    near, far, low, high = falloff(convert)
    m.comment("getEdgeFalloff(x, y, w, h, WARN_RANGE + near, WARN_RANGE + far, low, high).")
    m.const("warn_range", constant(constants, "OCEAN_MAPWRAPPER_WARN_RANGE"))
    m.const("falloff_near", near)
    m.const("falloff_far", far)
    f64_const(m, "falloff_low", low)
    f64_const(m, "falloff_high", high)
    middle, corner = tunings(convert)
    m.comment("Void outline: OCEAN_WATERFALL_MAX_DIST, the middle tuning's max factor, deeper and shallower chances,",
              "and the corner tuning's chances.")
    m.const("waterfall_max_dist", constant(constants, "OCEAN_WATERFALL_MAX_DIST"))
    f64_const(m, "middle_max_factor", middle[0])
    f64_const(m, "middle_deeper", middle[1])
    f64_const(m, "middle_shallower", middle[2])
    f64_const(m, "corner_deeper", corner[0])
    f64_const(m, "corner_shallower", corner[1])
    m.emit()


if __name__ == "__main__":
    main()
