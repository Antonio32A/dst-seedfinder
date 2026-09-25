-- Extracts the constant ocean-phase tables: bunch spawners (in the pairs() order BunchSpawnerRun uses), the ocean
-- generation config, and the noise tile functions as exact threshold lists (found by bisection over the doubles,
-- running the game's own functions).
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_ocean.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")
local Closures = dofile(GEN .. "/lib/closures.lua")
local closures = Closures.new()
local array = BOOT.array

local bunches = require("map/bunches")
local config = require("map/ocean_gen_config")
local noise_functions = require("noisetilefunctions")

local function sequence(t)
    local out = array()
    for _, v in ipairs(t or {}) do out[#out + 1] = v end
    return out
end

local bunches_out = array()
for name, data in pairs(bunches.Bunches) do
    local entry = { name = name, range = data.range, min = data.min, max = data.max, min_spacing = data.min_spacing,
        valid_tile_types = sequence(data.valid_tile_types) }
    for k in pairs(data) do
        assert(({ prefab = true, range = true, min = true, max = true, min_spacing = true, valid_tile_types = true })[k],
            "unknown bunch field " .. k)
    end
    if type(data.prefab) == "function" then
        entry.prefab_closure = closures:ref(data.prefab, "bunch:" .. name)
        entry.prefab_results = array({ "moonglass_wobster_den", "wobster_den" })
    else
        entry.prefab = data.prefab
    end
    bunches_out[#bunches_out + 1] = entry
end

local function ordered_config(t)
    local out = array()
    for k, v in pairs(t) do
        if type(v) == "table" then
            local rows = array()
            for _, row in ipairs(v) do rows[#rows + 1] = sequence(row) end
            out[#out + 1] = { key = k, rows = rows }
        else
            out[#out + 1] = { key = k, value = v }
        end
    end
    return out
end

local function previous_double(x)
    local m, e = math.frexp(x)
    if m == 0.5 then return x - 2 ^ (e - 54) end
    return x - 2 ^ (e - 53)
end

local function thresholds(fn)
    local candidates = {}
    for _, c in ipairs(BOOT.tl.constants(fn)) do
        if c > 0 and c <= 1 then candidates[#candidates + 1] = c end
    end
    table.sort(candidates)
    local steps = array()
    for _, c in ipairs(candidates) do
        if fn(previous_double(c)) ~= fn(c) then
            steps[#steps + 1] = { threshold = c, below = fn(previous_double(c)), above = fn(c) }
        end
    end
    local function piecewise(x)
        local value = fn(0.0)
        for _, step in ipairs(steps) do
            if x >= step.threshold then value = step.above end
        end
        return value
    end
    for i = 0, 100000 do
        local x = i / 100000
        assert(piecewise(x) == fn(x), "noise function is not the threshold table at " .. x)
    end
    return { first = fn(0.0), steps = steps }
end

local noise_out = array()
local tile_names = {}
for name, id in pairs(WORLD_TILES) do tile_names[id] = name end
for key, fn in pairs(noise_functions) do
    noise_out[#noise_out + 1] = { tile = key, tile_name = tile_names[key] or key, closure = closures:ref(fn, "noise:" .. tostring(key)),
        table = thresholds(fn) }
end
table.sort(noise_out, function(a, b) return tostring(a.tile) < tostring(b.tile) end)

BOOT.write_json({
    bunches = bunches_out,
    bunch_blockers = sequence(bunches.BunchBlockers),
    config = ordered_config(config),
    noise_functions = noise_out,
    closures = (function()
        local out = array()
        for _, key in ipairs(closures.order) do
            local e = closures.by_key[key]
            out[#out + 1] = { key = key, body = e.body, upvalues = array(e.upvalues), globals = array(e.globals),
                sites = array(BOOT.sorted_keys(e.sites)), contexts = array(BOOT.sorted_keys(e.contexts)) }
        end
        return out
    end)(),
})
