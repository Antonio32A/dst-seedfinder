-- Extracts what PopulateVoronoi's distribute step sees for every reachable room: for each deepcopy depth (1 = task
-- rooms, 2 = background and cove rooms), each GetRandomItem outcome of the swappable entries and each prefab swap
-- state, the table that resolveswappableprefabs + filterPrefabsForGlobalSwaps hand to pickspawnprefab (in its pairs()
-- order, with weights), and for every land tile the pairs() order of pickspawnprefab's filtered `items` table.
-- Everything runs through the game's own functions; the orders are recorded by wrapping the global pairs.
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_distribute.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")
local array = BOOT.array
require("map/graphnode")
local Rooms = require("map/rooms")

local function upvalue(fn, wanted)
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if name == nil then break end
        if name == wanted then return value end
    end
    error("no upvalue " .. wanted)
end

local resolveswappableprefabs = upvalue(Node.PopulateVoronoi, "resolveswappableprefabs")
local filterPrefabsForGlobalSwaps = upvalue(Node.PopulateVoronoi, "filterPrefabsForGlobalSwaps")
local pickspawnprefab = upvalue(BOOT.generate, "pickspawnprefab")

local land_tiles = {}
for name, id in pairs(WORLD_TILES) do
    if TileGroupManager:IsLandTile(id) then land_tiles[#land_tiles + 1] = id end
end
table.sort(land_tiles)

local raw_pairs = pairs
local recording = nil
local function recording_pairs(t)
    if recording ~= nil then
        local keys = {}
        for k, v in raw_pairs(t) do keys[#keys + 1] = { k, v } end
        recording[#recording + 1] = keys
    end
    return raw_pairs(t)
end

local function entries_of(t)
    local out = array()
    for k, v in raw_pairs(t) do out[#out + 1] = { key = k, value = v } end
    return out
end

local function signature(entries)
    local parts = {}
    for _, e in ipairs(entries) do parts[#parts + 1] = tostring(e.key) .. "=" .. string.format("%.17g", e.value) end
    return table.concat(parts, ",")
end

local Reach = assert(loadfile(GEN .. "/lib/reach.lua"))(BOOT)

local variants, variant_index = array(), {}
local picks, pick_index = array(), {}

local function intern(list, index, key, value)
    local id = index[key]
    if id == nil then
        list[#list + 1] = value
        id = #list - 1
        index[key] = id
    end
    return id
end

local function tile_picks(tbl)
    local by_tile = array()
    for _, tile in ipairs(land_tiles) do
        recording = {}
        _G.pairs = recording_pairs
        pickspawnprefab(tbl, tile)
        _G.pairs = raw_pairs
        local seen = recording
        recording = nil
        local items = seen[2] or {}
        local entries = array()
        for _, kv in ipairs(items) do entries[#entries + 1] = { key = kv[1], value = kv[2] } end
        by_tile[#by_tile + 1] = intern(picks, pick_index, signature(entries), entries)
    end
    return by_tile
end

local function choice_vectors(swappable)
    local vectors = { {} }
    for _, entry in ipairs(swappable) do
        local grown = {}
        for _, prefix in ipairs(vectors) do
            for k = 1, entry.count do
                local v = { unpack(prefix) }
                v[#v + 1] = k
                grown[#grown + 1] = v
            end
        end
        vectors = grown
    end
    return vectors
end

local function resolve(base, vector)
    local queue = { unpack(vector) }
    local real = GetRandomItem
    GetRandomItem = function(choices)
        local k = table.remove(queue, 1)
        local picked = nil
        for _, v in raw_pairs(choices) do
            k = k - 1
            if k == 0 then picked = v break end
        end
        return picked
    end
    local tbl = resolveswappableprefabs(base)
    GetRandomItem = real
    assert(#queue == 0)
    local filtered = filterPrefabsForGlobalSwaps(tbl, {})
    return filtered
end

local rooms_out = array()
for _, name in ipairs(Reach.room_names) do
    do
        local original = Rooms.GetRoomByName(name)
        if original.contents and original.contents.distributeprefabs and original.contents.distributepercent then
            local copies = { deepcopy(original) }
            copies[2] = deepcopy(copies[1])
            local depths = array()
            for depth = 1, 2 do
                local base = copies[depth].contents.distributeprefabs
                local swappable = array()
                for k, v in raw_pairs(base) do
                    if type(v) == "table" then
                        local prefabs = array()
                        for _, p in raw_pairs(v.prefabs) do prefabs[#prefabs + 1] = p end
                        swappable[#swappable + 1] = { key = k, count = #prefabs, prefabs = prefabs, weight = v.weight }
                    end
                end
                local cases = array()
                for _, vector in ipairs(choice_vectors(swappable)) do
                    for state = 0, 7 do
                        BOOT.PrefabSwaps.SelectPrefabSwaps("forest", nil, (function()
                            local o = {}
                            for i, cat in ipairs(BOOT.SWAP_CATEGORIES) do
                                o[cat] = BOOT.SWAP_NAMES[cat][math.floor(state / 2 ^ (i - 1)) % 2 + 1]
                            end
                            return o
                        end)())
                        local tbl = resolve(base, vector)
                        local entries = entries_of(tbl)
                        local sig = signature(entries)
                        local id = variant_index[sig]
                        if id == nil then
                            variants[#variants + 1] = { entries = entries, tiles = tile_picks(tbl) }
                            id = #variants - 1
                            variant_index[sig] = id
                        end
                        cases[#cases + 1] = { choices = array(vector), state = state, variant = id }
                    end
                end
                depths[#depths + 1] = { swappable = swappable, cases = cases }
            end
            rooms_out[#rooms_out + 1] = { name = name, depths = depths }
        end
    end
end

local ocean_out = array()
for _, name in ipairs(BOOT.level.ocean_population) do
    local room = deepcopy(Rooms.GetRoomByName(name))
    local contents = room.contents or {}
    local entry = { name = name, tile = room.value }
    if contents.distributeprefabs ~= nil and contents.distributepercent ~= nil then
        for _, v in raw_pairs(contents.distributeprefabs) do assert(type(v) ~= "table", "swappable ocean prefab") end
        recording = {}
        _G.pairs = recording_pairs
        pickspawnprefab(contents.distributeprefabs, room.value)
        _G.pairs = raw_pairs
        local items = recording[2] or {}
        recording = nil
        local picked = array()
        for _, kv in ipairs(items) do picked[#picked + 1] = { key = kv[1], value = kv[2] } end
        entry.entries = entries_of(contents.distributeprefabs)
        entry.pick = picked
    end
    ocean_out[#ocean_out + 1] = entry
end

BOOT.write_json({ land_tiles = array(land_tiles), rooms = rooms_out, variants = variants, picks = picks,
    ocean = ocean_out })
