-- Shared setup for the lua generators in scripts/gen: runs the unmodified worldgen_main.lua (default forest,
-- SURVIVAL_TOGETHER, seed 1) under the harness stubs up to forest_map.Generate and exposes the loaded game state.
-- GEN_SHARD=caves makes BOOT.level the DST_CAVE level data and lib/reach.lua reach the caves' tasks and rooms.
-- usage: local BOOT = dofile(<gen>/lib/boot.lua)

local GEN = debug.getinfo(1, "S").source:match("^@(.*)/lib/[^/]*$")
local ROOT = GEN .. "/../.."
local BOOT = { gen = GEN }

HARNESS_SCRIPTS_DIR = ROOT .. "/build/deps/game-scripts"
HARNESS_VERBOSE = false

local SENTINEL = {}
local captured = nil
HARNESS_LOAD_HOOKS = {
    ["map/forest_map"] = function(forest_map)
        BOOT.generate = forest_map.Generate
        forest_map.Generate = function(prefab, w, h, tasks, level, level_type)
            captured = { prefab = prefab, tasks = tasks, level = level, level_type = level_type }
            error(SENTINEL, 0)
        end
        return forest_map
    end,
}

dofile(ROOT .. "/scripts/harness/stubs.lua")

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end
BOOT.read_file = read_file

GEN_PARAMETERS = read_file(ROOT .. "/scripts/harness/gen_parameters_forest.json")
GEN_MODDATA = '{"index":{}}'
SEED = 1

local ok, err = xpcall(function() dofile(HARNESS_SCRIPTS_DIR .. "/worldgen_main.lua") end, function(e)
    if e == SENTINEL then return e end
    return debug.traceback(tostring(e), 2)
end)
assert(err == SENTINEL, "worldgen did not reach forest_map.Generate: " .. tostring(err))
BOOT.level = captured.level
BOOT.tasks = captured.tasks
BOOT.shard = os.getenv("GEN_SHARD") or "forest"
assert(BOOT.shard == "forest" or BOOT.shard == "caves", "unknown GEN_SHARD " .. BOOT.shard)
if BOOT.shard == "caves" then
    BOOT.level = require("map/levels").GetDataForLevelID("DST_CAVE")
end

BOOT.tl = assert(package.loadlib(ROOT .. "/build/gen/tablelayout.so", "luaopen_tablelayout"))()

BOOT.PrefabSwaps = require("prefabswaps")

BOOT.SWAP_CATEGORIES = { "grass", "twigs", "berries" }
BOOT.SWAP_NAMES = {
    grass = { "regular grass", "grass gekko" },
    twigs = { "regular twigs", "twiggy trees" },
    berries = { "regular berries", "juicy berries" },
}

local LAYOUT_MODULES = { "map/layouts", "map/traps", "map/pointsofinterest", "map/protected_resources", "map/boons",
    "map/maze_layouts" }

function BOOT.swap_state_name(state)
    local parts = {}
    for i, cat in ipairs(BOOT.SWAP_CATEGORIES) do
        local bit = math.floor(state / 2 ^ (i - 1)) % 2
        parts[#parts + 1] = BOOT.SWAP_NAMES[cat][bit + 1]
    end
    return table.concat(parts, ", ")
end

function BOOT.set_swaps(state)
    local overrides = {}
    for i, cat in ipairs(BOOT.SWAP_CATEGORIES) do
        local bit = math.floor(state / 2 ^ (i - 1)) % 2
        overrides[cat] = BOOT.SWAP_NAMES[cat][bit + 1]
    end
    BOOT.PrefabSwaps.SelectPrefabSwaps("forest", nil, overrides)
    for i, cat in ipairs(BOOT.SWAP_CATEGORIES) do
        local bit = math.floor(state / 2 ^ (i - 1)) % 2
        local probe = ({ grass = "grassgekko", twigs = "twiggytree", berries = "berrybush_juicy" })[cat]
        assert(BOOT.PrefabSwaps.IsPrefabInactive(probe) == (bit == 0), "swap override failed for " .. cat)
    end
    for _, name in ipairs(LAYOUT_MODULES) do package.loaded[name] = nil end
    for name in pairs(package.loaded) do
        if name:find("^map/static_layouts/") then package.loaded[name] = nil end
    end
end

function BOOT.sorted_keys(t)
    local ks = {}
    for k in pairs(t or {}) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) < type(b)
    end)
    return ks
end

function BOOT.pairs_keys(t)
    local ks = {}
    for k in pairs(t or {}) do ks[#ks + 1] = k end
    return ks
end

function BOOT.snapshot(t)
    local l = BOOT.tl.layout(t)
    local slots = {}
    for i, n in ipairs(l.nodes) do
        slots[i] = { key = n.key, live = n.live, next = n.next }
    end
    local array = {}
    for i, live in ipairs(l.array) do array[i] = live end
    return { sizearray = l.sizearray, lsizenode = l.lsizenode, lastfree = l.lastfree, dummy = l.dummy,
        array = array, slots = slots }
end

function BOOT.fn_info(fn)
    local info = debug.getinfo(fn, "S")
    return { file = info.source:gsub("^@", ""):gsub("^.*/game%-scripts/", ""), first = info.linedefined, last = info.lastlinedefined }
end

local JSON_NULL = setmetatable({}, { __tostring = function() return "null" end })
BOOT.null = JSON_NULL
local ARRAY_MT = { __jsonarray = true }
function BOOT.array(t)
    return setmetatable(t or {}, ARRAY_MT)
end

local function is_array(t)
    if getmetatable(t) == ARRAY_MT then return true end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n == 0 then return false end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local function encode(v, out)
    local kind = type(v)
    if v == JSON_NULL or v == nil then
        out[#out + 1] = "null"
    elseif kind == "boolean" then
        out[#out + 1] = tostring(v)
    elseif kind == "number" then
        assert(v == v and v ~= math.huge and v ~= -math.huge, "non-finite number")
        if v == math.floor(v) and math.abs(v) < 2 ^ 53 then
            out[#out + 1] = string.format("%d", v)
        else
            out[#out + 1] = string.format("%.17g", v)
        end
    elseif kind == "string" then
        out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
            return string.format("\\u%04x", c:byte())
        end) .. '"'
    elseif kind == "table" then
        if is_array(v) then
            out[#out + 1] = "["
            for i = 1, #v do
                if i > 1 then out[#out + 1] = "," end
                encode(v[i], out)
            end
            out[#out + 1] = "]"
        elseif next(v) == nil then
            out[#out + 1] = "{}"
        else
            local keys = BOOT.sorted_keys(v)
            out[#out + 1] = "{"
            for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = "," end
                encode(tostring(k), out)
                out[#out + 1] = ":"
                encode(v[k], out)
            end
            out[#out + 1] = "}"
        end
    else
        error("cannot encode " .. kind)
    end
end

function BOOT.json(v)
    local out = {}
    encode(v, out)
    return table.concat(out)
end

function BOOT.write_json(v)
    io.stdout:write(BOOT.json(v), "\n")
end

BOOT.print = HARNESS_PRINT

return BOOT
