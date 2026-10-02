-- Extracts the constant story data of the default forest (task set "default", SURVIVAL_TOGETHER): tasks, rooms,
-- enums, lock/key tables, the level fields storygen reads, and every closure found in them, with the pairs() orders
-- as the use sites see them (after the game's own deepcopy calls) and the Lua 5.1 node layout of the tables that
-- storygen keeps inserting into. Prints one JSON document (the sidecar out/story.json).
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_story.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")
local Closures = dofile(GEN .. "/lib/closures.lua")
local closures = Closures.new()

local tasks_mod = require("map/tasks")
local Rooms = require("map/rooms")
local level = BOOT.level
local array = BOOT.array

local TASK_FIELDS = {
    id = true, locks = true, keys_given = true, region_id = true, entrance_room = true, entrance_room_chance = true,
    room_choices = true, room_choices_special = true, room_bg = true, background_room = true, cove_room_name = true,
    cove_room_chance = true, cove_room_max_edges = true, colour = true, maze_tiles = true, maze_tile_size = true,
    crosslink_factor = true, make_loop = true, room_tags = true, required_prefabs = true, hub_room = true,
    level_set_piece_blocker = true,
}
local ROOM_FIELDS = {
    colour = true, value = true, tags = true, contents = true, type = true, internal_type = true,
    required_prefabs = true, random_node_exit_weight = true, random_node_entrance_weight = true,
    custom_tiles = true, custom_objects = true, SafeFromDisconnect = true, __tostring = true,
}
local CONTENTS_FIELDS = {
    distributepercent = true, distributeprefabs = true, countprefabs = true, countstaticlayouts = true,
    prefabdata = true, countprefabs_uses_filters = true,
}

local function value_of(v, context)
    local kind = type(v)
    if kind == "function" then return { closure = closures:ref(v, context) } end
    if kind == "table" then
        local out = {}
        for k, item in pairs(v) do out[tostring(k)] = value_of(item, context) end
        return out
    end
    return v
end

local function ordered_entries(t, context)
    local out = array()
    for k, v in pairs(t) do
        out[#out + 1] = { key = k, value = value_of(v, context) }
    end
    return out
end

local function sequence(t)
    local out = array()
    for _, v in ipairs(t or {}) do out[#out + 1] = v end
    return out
end

local function sequence_info(t)
    if type(t) ~= "table" then return t end
    local raw = array()
    for k, v in pairs(t) do raw[#raw + 1] = { key = k, value = v } end
    return { ipairs = sequence(t), length = #t, pairs = raw }
end

local function known_fields(t, known, label)
    for k in pairs(t) do
        assert(known[k], "unknown field " .. tostring(k) .. " in " .. label)
    end
end

-------------------------------------------------------------------------------------------------------------------

local Reach = assert(loadfile(GEN .. "/lib/reach.lua"))(BOOT)
local taskset = Reach.taskset
local start_loc = Reach.start_location
local task_names = Reach.task_names

local tasks_out = array()
local locks_used = {}
for _, name in ipairs(task_names) do
    local original = tasks_mod.GetTaskByName(name)
    assert(original, "missing task " .. name)
    known_fields(original, TASK_FIELDS, "task " .. name)
    local task = deepcopy(original)
    for _, lock in ipairs(task.locks) do locks_used[lock] = true end
    local entrance = task.entrance_room
    tasks_out[#tasks_out + 1] = {
        id = task.id,
        kind = ({ [true] = "required" })[table.contains(taskset.tasks, name)] or "optional",
        locks = sequence_info(task.locks),
        keys_given = sequence_info(task.keys_given),
        region_id = task.region_id,
        entrance_room = type(entrance) == "table" and sequence(entrance) or entrance,
        entrance_room_chance = task.entrance_room_chance,
        room_choices = ordered_entries(task.room_choices or {}, "task:" .. name),
        room_choices_special = task.room_choices_special and ordered_entries(task.room_choices_special) or nil,
        room_bg = task.room_bg,
        background_room = task.background_room,
        cove_room_name = task.cove_room_name,
        cove_room_chance = task.cove_room_chance,
        cove_room_max_edges = task.cove_room_max_edges,
        maze_tiles = task.maze_tiles and value_of(task.maze_tiles) or nil,
        maze_tile_size = task.maze_tile_size,
        crosslink_factor = task.crosslink_factor,
        make_loop = task.make_loop,
        room_tags = task.room_tags and sequence_info(task.room_tags) or nil,
        required_prefabs = task.required_prefabs and sequence(task.required_prefabs) or nil,
        hub_room = task.hub_room,
        level_set_piece_blocker = task.level_set_piece_blocker,
    }
end

-------------------------------------------------------------------------------------------------------------------

local function generate_order(countprefabs)
    local generate_these = {}
    for prefab in pairs(countprefabs) do generate_these[prefab] = 1 end
    return BOOT.pairs_keys(generate_these)
end

local function contents_view(contents, context)
    if contents == nil then return nil end
    known_fields(contents, CONTENTS_FIELDS, context)
    local view = {
        distributepercent = contents.distributepercent,
        countprefabs_uses_filters = contents.countprefabs_uses_filters,
    }
    for _, field in ipairs({ "countprefabs", "distributeprefabs", "countstaticlayouts", "prefabdata" }) do
        local t = contents[field]
        if t ~= nil then
            view[field] = { entries = ordered_entries(t, context .. ":" .. field), snapshot = BOOT.snapshot(t) }
        end
    end
    if contents.countprefabs ~= nil then
        view.countprefabs.generate_order = generate_order(contents.countprefabs)
    end
    return view
end

local rooms_out = array()
for _, name in ipairs(Reach.room_names) do
    local original = Rooms.GetRoomByName(name)
    assert(original, "missing room " .. name)
    known_fields(original, ROOM_FIELDS, "room " .. name)
    local depth1 = deepcopy(original)
    local depth2 = deepcopy(depth1)
    local depth3 = deepcopy(depth2)
    local context = "room:" .. name
    local start = nil
    if name == start_loc.start_node and depth1.contents and depth1.contents.countprefabs then
        local countprefabs = deepcopy(original).contents.countprefabs
        countprefabs.spawnpoint = nil
        start = { countprefabs = array(BOOT.pairs_keys(countprefabs)), generate_order = generate_order(countprefabs) }
    end
    rooms_out[#rooms_out + 1] = {
        start = start,
        name = name,
        value = original.value,
        type = original.type,
        internal_type = original.internal_type,
        tags = original.tags and sequence_info(original.tags) or nil,
        required_prefabs = original.required_prefabs and sequence(original.required_prefabs) or nil,
        random_node_exit_weight = original.random_node_exit_weight,
        random_node_entrance_weight = original.random_node_entrance_weight,
        custom_tiles = original.custom_tiles ~= nil,
        custom_objects = original.custom_objects ~= nil,
        SafeFromDisconnect = original.SafeFromDisconnect,
        contents = {
            original = contents_view(original.contents, context),
            depth1 = contents_view(depth1.contents, context),
            depth2 = contents_view(depth2.contents, context),
            depth3 = contents_view(depth3.contents, context),
        },
    }
end

-------------------------------------------------------------------------------------------------------------------

local function enum(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local locks_keys = {}
for lock in pairs(locks_used) do
    locks_keys[tostring(lock)] = sequence_info(LOCKS_KEYS[lock])
end

local set_pieces = array()
for name, data in pairs(taskset.set_pieces or {}) do
    set_pieces[#set_pieces + 1] = { name = name, count = data.count, tasks = sequence(data.tasks) }
end
local ocean_prefill = array()
for name, data in pairs(taskset.ocean_prefill_setpieces or {}) do
    ocean_prefill[#ocean_prefill + 1] = { name = name, count = data.count }
end

BOOT.write_json({
    enums = {
        NODE_TYPE = enum(NODE_TYPE),
        NODE_INTERNAL_CONNECTION_TYPE = enum(NODE_INTERNAL_CONNECTION_TYPE),
        LOCKS = enum(LOCKS),
        KEYS = enum(KEYS),
        LAYOUT = enum(LAYOUT),
        LAYOUT_POSITION = enum(LAYOUT_POSITION),
        PLACE_MASK = enum(PLACE_MASK),
        WORLD_TILES = enum(WORLD_TILES),
    },
    locks_keys = locks_keys,
    size_variation = SIZE_VARIATION,
    taskset = {
        tasks = sequence(taskset.tasks),
        optionaltasks = sequence(taskset.optionaltasks),
        numoptionaltasks = taskset.numoptionaltasks,
        valid_start_tasks = sequence(taskset.valid_start_tasks),
        required_prefabs = sequence(taskset.required_prefabs),
        set_pieces = set_pieces,
        ocean_prefill_setpieces = ocean_prefill,
        ocean_population = sequence(taskset.ocean_population),
    },
    level = {
        id = level.id,
        required_setpieces = sequence(level.required_setpieces),
        numrandom_set_pieces = level.numrandom_set_pieces,
        random_set_pieces = sequence(level.random_set_pieces),
        required_prefabs = sequence(level.required_prefabs),
        ocean_population = sequence(level.ocean_population),
        blocker_blank_room_name = level.blocker_blank_room_name,
        background_node_range = level.background_node_range and sequence(level.background_node_range) or nil,
        start_setpeice = start_loc.start_setpeice,
        start_node = start_loc.start_node,
    },
    tasks = tasks_out,
    rooms = rooms_out,
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
