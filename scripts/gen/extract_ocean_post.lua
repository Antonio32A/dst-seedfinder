-- Extracts the constants of the ocean phase after the conversion (lane G, M10): PopulateOcean's point search
-- increments, the monkey island dock generator's prefab data (pairs() orders), its tuning and the MonkeyIsland safe
-- area, the wormhole pairing constants, the prefab swap proxies, the level's required prefabs and the map constants.
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_ocean_post.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")
local array = BOOT.array

require("map/monkeyisland_worldgen")
local obj_layout = require("map/object_layout")

local function upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == nil then
            break
        elseif name == wanted then
            return value
        end
    end
    error("no upvalue " .. wanted)
end

local function source_of(path)
    return BOOT.read_file(BOOT.scratch .. "/game-scripts/" .. path)
end

local function chances(t)
    local out = array()
    for prefab, chance in pairs(t or {}) do
        out[#out + 1] = { prefab = prefab, chance = chance }
    end
    return out
end

local function numbers(text)
    local out = array()
    for n in string.gmatch(text, "%d+") do
        out[#out + 1] = tonumber(n)
    end
    return out
end

local docks = upvalue(MonkeyIsland_GenerateDocks, "MONKEYISLAND_PREFABSDATA")
local layout = obj_layout.LayoutForDefinition("MonkeyIsland")
local safe_area = layout.layout.monkeyisland_docksafearea[1]

local ocean_source = source_of("map/ocean_gen.lua")
local network_source = source_of("map/network.lua")

local function proxies(fn, name)
    local out = array()
    for proxy, real in pairs(upvalue(fn, name)) do
        out[#out + 1] = { proxy = proxy, real = type(real) == "table" and array(real) or array({ real }) }
    end
    return out
end

local required = array()
for _, prefab in ipairs(BOOT.level.required_prefabs or {}) do
    required[#required + 1] = prefab
end

local wormhole_prefab = BOOT.level.overrides and BOOT.level.overrides.wormhole_prefab
    or require("map/locations").forest.overrides.wormhole_prefab

local strings = array({ wormhole_prefab, "wormhole_MARKER", docks.center_prefab, docks.direction_prefab,
    docks.safety_prefab, "dock_tile_registrator", "dock_woodposts", "monkeyisland_docksafearea" })
for _, e in ipairs(chances(docks.dock_prefabs_withchance)) do strings[#strings + 1] = e.prefab end
for _, e in ipairs(chances(docks.endpoint_prefabs_with_chance)) do strings[#strings + 1] = e.prefab end
local customization = proxies(BOOT.PrefabSwaps.ResolveCustomizationPrefab, "_customization_proxies")
local randomization = proxies(BOOT.PrefabSwaps.IsRandomizationPrefab, "_randomization_proxies")
for _, list in ipairs({ customization, randomization }) do
    for _, p in ipairs(list) do
        strings[#strings + 1] = p.proxy
        for _, real in ipairs(p.real) do strings[#strings + 1] = real end
    end
end

BOOT.write_json({
    water_point_incs = numbers(assert(ocean_source:match("local incs = (%b{})"))),
    min_wormhole_id = tonumber(assert(network_source:match("self%.MIN_WORMHOLE_ID = (%d+)"))),
    wormhole_prefab = wormhole_prefab,
    docks = {
        center_prefab = docks.center_prefab,
        direction_prefab = docks.direction_prefab,
        safety_prefab = docks.safety_prefab,
        dock_post_chance = docks.dock_post_chance,
        dock_prefabs = chances(docks.dock_prefabs_withchance),
        endpoint_prefabs = chances(docks.endpoint_prefabs_with_chance),
        amount = TUNING.MONKEYISLANDGEN_DOCKAMOUNT,
        min_length = TUNING.MONKEYISLANDGEN_DOCKMINLENGTH,
        max_length = TUNING.MONKEYISLANDGEN_DOCKMAXLENGTH,
        safe_width = safe_area.width,
        safe_height = safe_area.height,
    },
    customization_proxies = customization,
    randomization_proxies = randomization,
    level_required_prefabs = required,
    ocean_population_edge_dist = OCEAN_POPULATION_EDGE_DIST,
    ocean_waterfall_max_dist = OCEAN_WATERFALL_MAX_DIST,
    tile_scale = TILE_SCALE,
    strings = strings,
})
