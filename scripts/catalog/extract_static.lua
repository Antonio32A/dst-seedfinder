-- Static worldgen extraction for the catalog.
-- Runs the unmodified game worldgen_main.lua (default forest, SURVIVAL_TOGETHER) under the harness stubs up to
-- forest_map.Generate, then walks the game's own loaded tables (tasksets, tasks, rooms, layouts, sandboxes, map tags,
-- bunches, prefab swaps, tiles, strings) and prints one JSON document on stdout.
-- usage: ../harness/bin/lua-dst extract_static.lua > build/static.json

local HERE = arg[0]:match("^(.*)/[^/]*$") or "."
HARNESS_SCRIPTS_DIR = HERE .. "/../../build/deps/game-scripts"
HARNESS_VERBOSE = false
local SAMPLE_TRIALS = tonumber(os.getenv("CATALOG_TRIALS") or "400")

local SENTINEL = {}
local captured = nil
HARNESS_LOAD_HOOKS = {
    ["map/forest_map"] = function(forest_map)
        forest_map.Generate = function(prefab, w, h, tasks, level, level_type)
            captured = { prefab = prefab, tasks = tasks, level = level }
            error(SENTINEL, 0)
        end
        return forest_map
    end,
}

dofile(HERE .. "/../harness/stubs.lua")

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

GEN_PARAMETERS = read_file(HERE .. "/../harness/gen_parameters_forest.json")
GEN_MODDATA = '{"index":{}}'
SEED = 1

local ok, err = xpcall(function() dofile(HARNESS_SCRIPTS_DIR .. "/worldgen_main.lua") end, function(e)
    if e == SENTINEL then return e end
    return debug.traceback(tostring(e), 2)
end)
assert(err == SENTINEL, "worldgen did not reach forest_map.Generate: " .. tostring(err))

local JSON_NULL = {}

local function is_array(t)
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
        if v ~= v or v == math.huge or v == -math.huge then
            out[#out + 1] = "null"
        elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then
            out[#out + 1] = string.format("%d", v)
        else
            out[#out + 1] = string.format("%.10g", v)
        end
    elseif kind == "string" then
        out[#out + 1] = (string.format("%q", v):gsub("\\\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t"))
    elseif kind == "table" then
        if next(v) == nil then
            out[#out + 1] = "{}"
        elseif is_array(v) then
            out[#out + 1] = "["
            for i, item in ipairs(v) do
                if i > 1 then out[#out + 1] = "," end
                encode(item, out)
            end
            out[#out + 1] = "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            local lookup = {}
            for k, item in pairs(v) do lookup[tostring(k)] = item end
            out[#out + 1] = "{"
            for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = "," end
                encode(k, out)
                out[#out + 1] = ":"
                encode(lookup[k], out)
            end
            out[#out + 1] = "}"
        end
    else
        out[#out + 1] = string.format("%q", "<" .. kind .. ">")
    end
end

local function keys_of(t)
    local ks = {}
    for k in pairs(t or {}) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
    return ks
end

local function set_to_list(s)
    return keys_of(s)
end

local tile_names = {}
for name, id in pairs(WORLD_TILES) do tile_names[id] = name end

local function tile_name(id)
    return id and (tile_names[id] or tostring(id)) or nil
end

local function describe_count(v, key)
    if type(v) ~= "function" then return v end
    local lo, hi = math.huge, -math.huge
    for trial = 1, 200 do
        local area = 20 + (trial % 20) * 25
        local okc, n = pcall(v, area, key, {})
        if okc and type(n) == "number" then
            lo = math.min(lo, n)
            hi = math.max(hi, n)
        end
    end
    if lo == math.huge then return { fn = true } end
    return { fn = true, min = lo, max = hi }
end

local PrefabSwaps = require("prefabswaps")
local tasks_mod = require("map/tasks")
local tasksets = require("map/tasksets")
local Rooms = require("map/rooms")
local obj_layout = require("map/object_layout")
local layouts_mod = require("map/layouts")
local startlocations = require("map/startlocations")
local forest_map = require("map/forest_map")
local MapTags = require("map/maptags")
local bunches = require("map/bunches")
local level = captured.level

-------------------------------------------------------------------------------------------------------------------
-- Settings

local customize = require("map/customize")
local settings = { levels = {}, boon_ranges = {}, multiply = {}, labels = {} }
for _, d in ipairs(customize.GetDescription("worldgen_frequency_descriptions")) do
    settings.levels[#settings.levels + 1] = { id = d.data, label = d.text }
end
for _, d in ipairs(settings.levels) do
    local m = forest_map.MULTIPLY[d.id]
    settings.multiply[d.id] = m
    if d.id == "never" then
        settings.boon_ranges[d.id] = { 0, 0 }
    else
        settings.boon_ranges[d.id] = { math.floor(3 * m), math.ceil(8 * m) }
    end
end
settings.labels = {
    boons = STRINGS.UI.CUSTOMIZATIONSCREEN.BOONS,
    touchstone = STRINGS.UI.CUSTOMIZATIONSCREEN.TOUCHSTONE,
    prefabswaps_start = STRINGS.UI.CUSTOMIZATIONSCREEN.PREFABSWAPS_START,
    traps = STRINGS.UI.CUSTOMIZATIONSCREEN.TRAPS,
    poi = STRINGS.UI.CUSTOMIZATIONSCREEN.POI,
    protected = STRINGS.UI.CUSTOMIZATIONSCREEN.PROTECTED,
}
settings.customize_items = {}
if rawget(_G, "stringidsorter") == nil then
    rawset(_G, "stringidsorter", function(a, b) return a < b end)
end
local ok_opts, opts = pcall(customize.GetWorldGenOptions, "forest", true)
if not ok_opts then io.stderr:write("GetWorldGenOptions failed: ", tostring(opts), "\n") end
for _, item in ipairs(ok_opts and opts or {}) do
    local label = STRINGS.UI.CUSTOMIZATIONSCREEN[string.upper(item.name or "")]
    settings.customize_items[item.name] = { image = item.image, atlas = item.atlas, default = item.default,
        group = item.group, label = label, options = item.options, widget_type = item.widget_type }
end

-------------------------------------------------------------------------------------------------------------------
-- Prefab swaps

local swaps = {}
for category, sets in pairs(PrefabSwaps.GetBasePrefabSwaps()) do
    local entry = {}
    for _, set in ipairs(sets) do
        entry[#entry + 1] = { name = set.name, prefabs = set.prefabs, weight = set.weight, primary = set.primary or false,
            exclude_locations = set.exclude_locations, required_locations = set.required_locations }
    end
    swaps[category] = entry
end

-------------------------------------------------------------------------------------------------------------------
-- Level / task set

local taskset = tasksets.GetGenTasks("default")
local start_loc = startlocations.GetStartLocation("default")

local level_info = {
    id = level.id,
    location = level.location,
    required_setpieces = level.required_setpieces,
    numrandom_set_pieces = level.numrandom_set_pieces,
    random_set_pieces = level.random_set_pieces,
    required_prefabs = level.required_prefabs,
    ocean_population = level.ocean_population,
    blocker_blank_room_name = level.blocker_blank_room_name,
    background_node_range = level.background_node_range,
    taskset_tasks = taskset.tasks,
    taskset_optionaltasks = taskset.optionaltasks,
    numoptionaltasks = taskset.numoptionaltasks,
    valid_start_tasks = taskset.valid_start_tasks,
    start_setpeice = start_loc.start_setpeice,
    start_node = start_loc.start_node,
    wormhole_prefab = level.overrides and level.overrides.wormhole_prefab or "wormhole",
}
local taskset_set_pieces = {}
for name, data in pairs(taskset.set_pieces or {}) do
    taskset_set_pieces[name] = { count = data.count or 1, tasks = data.tasks }
end
level_info.set_pieces = taskset_set_pieces
local ocean_prefill = {}
for name, data in pairs(taskset.ocean_prefill_setpieces or {}) do
    ocean_prefill[name] = { count = data.count or 1 }
end
level_info.ocean_prefill_setpieces = ocean_prefill

-------------------------------------------------------------------------------------------------------------------
-- Tasks

local task_ids = {}
for _, t in ipairs(taskset.tasks) do task_ids[#task_ids + 1] = { id = t, kind = "required" } end
for _, t in ipairs(taskset.optionaltasks) do task_ids[#task_ids + 1] = { id = t, kind = "optional" } end

local rooms_used = {}
local function use_room(name, via)
    if name == nil then return end
    rooms_used[name] = rooms_used[name] or {}
    rooms_used[name][via] = true
end

local tasks_out = {}
local task_room_tags = {}
for _, entry in ipairs(task_ids) do
    local t = tasks_mod.GetTaskByName(entry.id)
    assert(t, "missing task " .. entry.id)
    local room_choices = {}
    for room, count in pairs(t.room_choices or {}) do
        room_choices[room] = describe_count(count, room)
        use_room(room, "task:" .. entry.id)
    end
    use_room(t.background_room, "task_background:" .. entry.id)
    local entrance = t.entrance_room
    if type(entrance) == "table" then
        for _, r in ipairs(entrance) do use_room(r, "task_entrance:" .. entry.id) end
    else
        use_room(entrance, "task_entrance:" .. entry.id)
    end
    use_room(t.cove_room_name or "Blank", "task_cove:" .. entry.id)
    local set_pieces = {}
    for _, sp in ipairs(t.set_pieces or {}) do set_pieces[#set_pieces + 1] = sp.name end
    task_room_tags[entry.id] = t.room_tags
    tasks_out[entry.id] = {
        kind = entry.kind,
        moon = (t.level_set_piece_blocker == true) or (entry.id:find("^MoonIsland") ~= nil),
        level_set_piece_blocker = t.level_set_piece_blocker or false,
        room_bg = tile_name(t.room_bg),
        background_room = t.background_room,
        room_choices = room_choices,
        entrance_room = entrance,
        entrance_room_chance = t.entrance_room_chance,
        cove_room_name = t.cove_room_name,
        set_pieces = set_pieces,
        random_set_pieces = t.random_set_pieces,
        room_tags = t.room_tags,
        region_id = t.region_id,
        locks = t.locks,
        keys_given = t.keys_given,
        crosslink_factor = t.crosslink_factor,
    }
end

use_room(level_info.start_node, "start_node")
use_room(level_info.blocker_blank_room_name, "blocker_blank")
use_room("Blank", "blank")
for _, r in ipairs(level.ocean_population or {}) do use_room(r, "ocean_population") end
for id, t in pairs(tasks_out) do
    if t.region_id ~= nil and t.region_id ~= "mainland" then use_room("MoonIsland_Meadows", "region_link") end
end

-------------------------------------------------------------------------------------------------------------------
-- Rooms

local layouts_used = {}
local function use_layout(name, via)
    if name == nil then return end
    layouts_used[name] = layouts_used[name] or {}
    layouts_used[name][via] = true
end

local tag_fns = MapTags()
local tag_results = {}
local function evaluate_tag(tag)
    if tag_results[tag] then return tag_results[tag] end
    local fn = tag_fns.Tag[tag]
    local results = {}
    if fn then
        local seen = {}
        for _ = 1, 200 do
            local tagdata = deepcopy(tag_fns.TagData)
            local kind, value = fn(tagdata, level)
            if kind ~= nil then
                local key = tostring(kind) .. ":" .. tostring(value)
                if not seen[key] then
                    seen[key] = true
                    results[#results + 1] = { kind = kind, value = type(value) == "table" and "<table>" or value }
                end
            end
        end
    end
    tag_results[tag] = results
    return results
end

local rooms_out = {}
for name, via in pairs(rooms_used) do
    local room = Rooms.GetRoomByName(name)
    if room == nil then
        rooms_out[name] = { missing = true, used_by = set_to_list(via) }
    else
        local c = room.contents or {}
        local countprefabs, distributeprefabs, countstaticlayouts = {}, {}, {}
        for p, v in pairs(c.countprefabs or {}) do countprefabs[p] = describe_count(v, p) end
        for p, v in pairs(c.distributeprefabs or {}) do
            if type(v) == "table" then
                for _, alt in ipairs(v.prefabs or {}) do distributeprefabs[alt] = v.weight end
            else
                distributeprefabs[p] = v
            end
        end
        for l, v in pairs(c.countstaticlayouts or {}) do
            countstaticlayouts[l] = describe_count(v, l)
            use_layout(l, "room:" .. name)
        end
        local tags = {}
        for _, tag in ipairs(room.tags or {}) do tags[tag] = true end
        for task_via in pairs(via) do
            local task_id = task_via:match("^task[_%a]*:(.*)$")
            for _, tag in ipairs(task_id and task_room_tags[task_id] or {}) do tags[tag] = true end
        end
        local tag_items = {}
        for tag in pairs(tags) do
            for _, r in ipairs(evaluate_tag(tag)) do
                if r.kind == "ITEM" then
                    tag_items[#tag_items + 1] = { tag = tag, prefab = r.value }
                elseif r.kind == "STATIC" then
                    tag_items[#tag_items + 1] = { tag = tag, layout = r.value }
                    use_layout(r.value, "maptag:" .. tag)
                end
            end
        end
        rooms_out[name] = {
            used_by = set_to_list(via),
            value = tile_name(room.value),
            type = room.type,
            tags = set_to_list(tags),
            required_prefabs = room.required_prefabs,
            distributepercent = c.distributepercent,
            countprefabs = countprefabs,
            distributeprefabs = distributeprefabs,
            prefabdata = keys_of(c.prefabdata),
            countstaticlayouts = countstaticlayouts,
            countprefabs_uses_filters = c.countprefabs_uses_filters,
            tag_items = tag_items,
        }
    end
end

-------------------------------------------------------------------------------------------------------------------
-- Set pieces and layouts

local sandbox_modules = {
    boon = require("map/boons"),
    trap = require("map/traps"),
    poi = require("map/pointsofinterest"),
    protected = require("map/protected_resources"),
}
local sandboxes = {}
for kind, mod in pairs(sandbox_modules) do
    local areas = {}
    for area, pieces in pairs(mod.Sandbox) do
        local area_name = type(area) == "number" and tile_name(area) or area
        areas[area_name] = keys_of(pieces)
        for piece in pairs(pieces) do use_layout(piece, "sandbox:" .. kind .. ":" .. area_name) end
    end
    sandboxes[kind] = areas
end

for name in pairs(taskset.set_pieces or {}) do use_layout(name, "taskset_set_piece") end
for name in pairs(taskset.ocean_prefill_setpieces or {}) do use_layout(name, "ocean_prefill") end
for _, name in ipairs(level.required_setpieces or {}) do use_layout(name, "required_setpiece") end
for _, name in ipairs(level.random_set_pieces or {}) do use_layout(name, "random_setpiece") end
for id, t in pairs(tasks_out) do
    for _, name in ipairs(t.set_pieces) do use_layout(name, "task_set_piece:" .. id) end
end
use_layout(level_info.start_setpeice, "start_setpiece")

local function raw_static_types(layout_file)
    if not layout_file then return nil end
    local okf, raw = pcall(require, layout_file)
    if not okf or type(raw) ~= "table" then return nil end
    local types = {}
    for _, layer in ipairs(raw.layers or {}) do
        if layer.type == "objectgroup" then
            for _, obj in ipairs(layer.objects or {}) do
                if obj.type and obj.type ~= "" then types[obj.type] = (types[obj.type] or 0) + 1 end
            end
        end
    end
    return types
end

local function collect_strings(t, out, depth)
    depth = depth or 0
    if depth > 6 or type(t) ~= "table" then return end
    for k, v in pairs(t) do
        if type(v) == "string" then
            out[v] = true
        elseif type(v) == "table" then
            collect_strings(v, out, depth + 1)
        end
    end
end

local function sample_layout(name)
    local base = obj_layout.LayoutForDefinition(name)
    if base == nil then return nil end
    local randomized = base.areas ~= nil or base.defs ~= nil
    local trials = randomized and SAMPLE_TRIALS or 1
    local stats = {}
    local scenarios, data_strings = {}, {}
    for trial = 1, trials do
        local layout = obj_layout.LayoutForDefinition(name)
        local okc, items = pcall(obj_layout.ConvertLayoutToEntitylist, layout)
        if not okc then
            return { error = tostring(items), file = base.layout_file }
        end
        local counts = {}
        for _, item in ipairs(items) do
            counts[item.prefab] = (counts[item.prefab] or 0) + 1
            local props = item.properties
            if type(props) == "table" then
                if props.scenario then scenarios[props.scenario] = true end
                if props.data then collect_strings(props.data, data_strings) end
            end
        end
        for prefab, n in pairs(counts) do
            local s = stats[prefab]
            if s == nil then
                s = { min = n, max = n, seen = 0 }
                stats[prefab] = s
            end
            s.min = math.min(s.min, n)
            s.max = math.max(s.max, n)
            s.seen = s.seen + 1
        end
    end
    for _, s in pairs(stats) do
        if s.seen < trials then s.min = 0 end
        s.p = s.seen / trials
        s.seen = nil
    end
    local def_choices = {}
    for k, v in pairs(base.defs or {}) do def_choices[k] = v end
    return {
        file = base.layout_file,
        type = base.type,
        randomized = randomized,
        trials = trials,
        prefabs = stats,
        raw_types = raw_static_types(base.layout_file),
        defs = def_choices,
        area_names = keys_of(base.areas),
        scenarios = keys_of(scenarios),
        data_strings = keys_of(data_strings),
        count = base.count and (function()
            local c = {}
            for k, v in pairs(base.count) do c[k] = describe_count(v, k) end
            return c
        end)() or nil,
    }
end

local layouts_out = {}
local pending = keys_of(layouts_used)
while #pending > 0 do
    local name = table.remove(pending)
    if layouts_out[name] == nil then
        local okl, info = pcall(sample_layout, name)
        if not okl then info = { error = tostring(info) } end
        info = info or { missing = true }
        info.used_by = set_to_list(layouts_used[name])
        layouts_out[name] = info
    end
end

-------------------------------------------------------------------------------------------------------------------
-- Other generators

local bunches_out = {}
for spawner, data in pairs(bunches.Bunches) do
    local prefab = data.prefab
    if type(prefab) == "function" then
        local info = debug.getinfo(prefab, "S")
        bunches_out[spawner] = { prefab_fn = { file = info.source:match("game%-scripts/(.*)$"), first = info.linedefined, last = info.lastlinedefined },
            min = data.min, max = data.max }
    else
        bunches_out[spawner] = { prefab = prefab, min = data.min, max = data.max }
    end
end

local function upvalue(fn, wanted)
    for i = 1, 80 do
        local name, value = debug.getupvalue(fn, i)
        if name == nil then return nil end
        if name == wanted then return value end
    end
end

local monkey = upvalue(rawget(_G, "MonkeyIsland_GenerateDocks"), "MONKEYISLAND_PREFABSDATA") or {}
local monkey_out = {
    center_prefab = monkey.center_prefab,
    direction_prefab = monkey.direction_prefab,
    safety_prefab = monkey.safety_prefab,
    dock_prefabs = keys_of(monkey.dock_prefabs_withchance),
    endpoint_prefabs = keys_of(monkey.endpoint_prefabs_with_chance),
    always = { "dock_tile_registrator", "dock_woodposts" },
}

local pocket = require("prefabs/pocketdimensioncontainer_defs").POCKETDIMENSIONCONTAINER_DEFS
local world_entities = {}
for _, v in ipairs(pocket) do world_entities[#world_entities + 1] = v.prefab end

local proxies = {}
for _, p in ipairs({ "perma_grass", "perma_sapling", "ground_twigs" }) do proxies[p] = PrefabSwaps.ResolvePrefabProxy(p) end
local customization_proxies = {}
for _, p in ipairs({ "lunar_island_rock1", "lunar_island_rock2", "lunar_island_rocks" }) do
    customization_proxies[p] = PrefabSwaps.ResolveCustomizationPrefab(p)
end
local randomization = upvalue(PrefabSwaps.IsRandomizationPrefab, "_randomization_proxies") or {}
local proxy_names = upvalue(PrefabSwaps.ResolvePrefabProxy, "_proxies") or {}
local custom_names = upvalue(PrefabSwaps.ResolveCustomizationPrefab, "_customization_proxies") or {}
for k, v in pairs(proxy_names) do proxies[k] = v end
for k, v in pairs(custom_names) do customization_proxies[k] = v end

-------------------------------------------------------------------------------------------------------------------
-- Tiles

local function layer_properties(layers, id)
    for _, layer in ipairs(layers or {}) do
        if layer[1] == id then return layer[2] end
    end
    return {}
end

local tiles_out = {}
for name, id in pairs(GetWorldTileMap()) do
    local ground_tiles = require("worldtiledefs")
    local ground_names = rawget(_G, "GROUND_NAMES")
    local turf = ground_tiles and ground_tiles.turf and ground_tiles.turf[id]
    local ground_colors = layer_properties(ground_tiles.ground, id).colors
    tiles_out[name] = {
        id = id,
        land = TileGroupManager:IsLandTile(id),
        ocean = TileGroupManager:IsOceanTile(id),
        impassable = TileGroupManager:IsImpassableTile(id),
        noise = TileGroupManager:IsNoiseTile(id),
        invalid = TileGroupManager:IsInvalidTile(id),
        ground_name = ground_names and ground_names[id] or nil,
        turf = turf and turf.name or nil,
        legacy = WORLD_TILES[name] == nil,
        minimap_noise = layer_properties(ground_tiles.minimap, id).noise_texture,
        ground_minimap_color = ground_colors and ground_colors.minimap_color or nil,
    }
end

-------------------------------------------------------------------------------------------------------------------

local names = {}
for k, v in pairs(STRINGS.NAMES) do
    if type(v) == "string" then names[k] = v end
end

local doc = {
    settings = settings,
    swaps = swaps,
    level = level_info,
    tasks = tasks_out,
    rooms = rooms_out,
    layouts = layouts_out,
    sandboxes = sandboxes,
    bunches = bunches_out,
    monkeyisland = monkey_out,
    world_entities = world_entities,
    proxies = proxies,
    customization_proxies = customization_proxies,
    randomization_proxies = randomization,
    tiles = tiles_out,
    names = names,
}

local out = {}
encode(doc, out)
io.stdout:write(table.concat(out), "\n")
