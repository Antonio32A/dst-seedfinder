-- Extracts the level table inputs of the caves shard (preset DST_CAVE, task set "cave_default", start location
-- "caves"): the level and location fields worldgen reads, the task set with the Lua 5.1 node layout of its set_pieces
-- (the table AddSetPeices keeps inserting into), every task's room_bg, the caves start rooms and which prefab swaps the
-- caves allow, and the story level data of the cave tasks and rooms (tasks as Level:EnqueueATask hands them to
-- storygen, the rooms they reach, the map tags of those rooms and the lock table). Prints one JSON document (the
-- sidecar out/caves.json).
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_caves.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")

local levels = require("map/levels")
local tasks_mod = require("map/tasks")
local tasksets = require("map/tasksets")
local startlocations = require("map/startlocations")
local Closures = dofile(GEN .. "/lib/closures.lua")
local Rooms = require("map/rooms")
local MapTags = require("map/maptags")
local array = BOOT.array
local closures = Closures.new()

local LOCATION = "cave"
local level = levels.GetDataForLevelID("DST_CAVE")
assert(level.location == LOCATION)
local taskset = tasksets.GetGenTasks(level.overrides.task_set)
local start_location = startlocations.GetStartLocation(level.overrides.start_location)

local function sequence(t)
    local out = array()
    for _, v in ipairs(t or {}) do out[#out + 1] = v end
    return out
end

local function overrides_of(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local task_names = sequence(taskset.tasks)
for _, name in ipairs(taskset.optionaltasks) do task_names[#task_names + 1] = name end
local tasks_out = array()
for _, name in ipairs(task_names) do
    local task = assert(tasks_mod.GetTaskByName(name), "missing task " .. name)
    tasks_out[#tasks_out + 1] = {
        id = task.id,
        room_bg = task.room_bg,
        level_set_piece_blocker = task.level_set_piece_blocker,
        region_id = task.region_id,
    }
end

local set_pieces = array()
for name, data in pairs(taskset.set_pieces) do
    set_pieces[#set_pieces + 1] = { name = name, count = data.count, tasks = sequence(data.tasks) }
end

local TASK_FIELDS = {
    id = true, locks = true, keys_given = true, region_id = true, entrance_room = true, room_choices = true,
    room_bg = true, background_room = true, cove_room_name = true, cove_room_chance = true,
    cove_room_max_edges = true, colour = true, maze_tiles = true, crosslink_factor = true, make_loop = true,
    room_tags = true, required_prefabs = true,
}
local ROOM_FIELDS = {
    colour = true, value = true, tags = true, contents = true, type = true, internal_type = true,
    required_prefabs = true, random_node_exit_weight = true, random_node_entrance_weight = true,
    custom_tiles = true, custom_objects = true, SafeFromDisconnect = true, __tostring = true,
}

local function known_fields(t, known, label)
    for k in pairs(t) do assert(known[k], "unknown field " .. tostring(k) .. " in " .. label) end
end

local function sequence_info(t)
    local raw = array()
    for k, v in pairs(t) do raw[#raw + 1] = { key = k, value = v } end
    return { ipairs = sequence(t), length = #t, pairs = raw }
end

local rooms_used, room_names = {}, {}
local function use_room(name)
    if name ~= nil and not rooms_used[name] then
        rooms_used[name] = true
        room_names[#room_names + 1] = name
    end
end

local tag_names, tags_used = {}, {}
local story_tasks = array()
local locks_used = {}
for index, name in ipairs(task_names) do
    local task = deepcopy(tasks_mod.GetTaskByName(name))
    known_fields(task, TASK_FIELDS, "task " .. name)
    for _, lock in ipairs(task.locks) do locks_used[lock] = true end
    for _, tag in ipairs(task.room_tags or {}) do
        if not tags_used[tag] then
            tags_used[tag] = true
            tag_names[#tag_names + 1] = tag
        end
    end
    local entrance = task.entrance_room
    if type(entrance) == "table" then
        for _, r in ipairs(entrance) do use_room(r) end
    else
        use_room(entrance)
    end
    local choices = array()
    for room, count in pairs(task.room_choices) do
        use_room(room)
        choices[#choices + 1] = { key = room,
            value = type(count) == "function" and { closure = closures:ref(count, "task:" .. name) } or count }
    end
    use_room(task.background_room)
    use_room(task.cove_room_name or "Blank")
    story_tasks[#story_tasks + 1] = {
        id = task.id,
        kind = index <= #taskset.tasks and "required" or "optional",
        locks = sequence_info(task.locks),
        keys_given = sequence_info(task.keys_given),
        entrance_room = type(entrance) == "table" and sequence(entrance) or entrance,
        room_choices = choices,
        room_bg = task.room_bg,
        background_room = task.background_room,
        cove_room_name = task.cove_room_name,
        cove_room_chance = task.cove_room_chance,
        cove_room_max_edges = task.cove_room_max_edges,
        crosslink_factor = task.crosslink_factor,
        make_loop = task.make_loop,
        maze = task.maze_tiles ~= nil,
        room_tags = sequence(task.room_tags),
    }
end
for _, r in ipairs(start_location.start_node) do use_room(r) end
use_room("BGImpassable")
use_room("Blank")

local function ca_layer(layer)
    return { tile = layer.tile, item_count = layer.item_count, item = layer.items[1] }
end

local function ca_view(room)
    if room.custom_tiles == nil then return nil end
    assert(room.custom_tiles.GeneratorFunction == RUNCA.GeneratorFunction, "unknown custom_tiles generator")
    local data = room.custom_tiles.data
    local translate = array()
    for _, layer in ipairs(data.translate) do translate[#translate + 1] = ca_layer(layer) end
    return {
        iterations = data.iterations, seed_mode = data.seed_mode, num_random_points = data.num_random_points,
        translate = translate, centroid = data.centroid and ca_layer(data.centroid) or nil,
    }
end

local story_rooms = array()
for _, name in ipairs(room_names) do
    local room = deepcopy(assert(Rooms.GetRoomByName(name), "missing room " .. name))
    known_fields(room, ROOM_FIELDS, "room " .. name)
    for _, tag in ipairs(room.tags or {}) do
        if not tags_used[tag] then
            tags_used[tag] = true
            tag_names[#tag_names + 1] = tag
        end
    end
    story_rooms[#story_rooms + 1] = {
        name = name, value = room.value, type = room.type, internal_type = room.internal_type,
        random_node_exit_weight = room.random_node_exit_weight,
        random_node_entrance_weight = room.random_node_entrance_weight,
        custom_tiles = room.custom_tiles ~= nil, custom_objects = room.custom_objects ~= nil,
        SafeFromDisconnect = room.SafeFromDisconnect == true,
        tags = sequence(room.tags),
        ca = ca_view(room),
    }
end

table.sort(tag_names)
local story_tags = array()
for _, tag in ipairs(tag_names) do
    local fn = MapTags().Tag[tag]
    local first, second = {}, {}
    if fn then
        local data = deepcopy(MapTags().TagData)
        first.kind, first.value = fn(data, BOOT.level)
        second.kind, second.value = fn(data, BOOT.level)
    end
    story_tags[#story_tags + 1] = { tag = tag, first = first, second = second }
end

local story_locks_keys = {}
for lock in pairs(locks_used) do
    story_locks_keys[tostring(lock)] = sequence_info(LOCKS_KEYS[lock])
end

local story_closures = array()
for _, key in ipairs(closures.order) do
    local e = closures.by_key[key]
    story_closures[#story_closures + 1] = { key = key, body = e.body, globals = array(e.globals) }
end

local PrefabSwaps = BOOT.PrefabSwaps
local swaps = array()
for category, sets in pairs(deepcopy(PrefabSwaps.GetBasePrefabSwaps())) do
    local out = array()
    for _, set in ipairs(sets) do
        local excluded = set.exclude_locations ~= nil and table.contains(set.exclude_locations, LOCATION)
        local unavailable = set.required_locations ~= nil and not table.contains(set.required_locations, LOCATION)
        out[#out + 1] = {
            name = set.name, weight = set.weight, primary = set.primary == true,
            valid = set.primary == true or not (excluded or unavailable),
        }
    end
    swaps[#swaps + 1] = { category = category, sets = out }
end

local world_tiles = {}
for name, number in pairs(WORLD_TILES) do world_tiles[name] = number end

BOOT.write_json({
    level = {
        id = level.id,
        location = level.location,
        overrides = overrides_of(level.overrides),
        background_node_range = sequence(level.background_node_range),
        required_setpieces = sequence(level.required_setpieces),
        numrandom_set_pieces = level.numrandom_set_pieces,
        random_set_pieces = sequence(level.random_set_pieces),
        required_prefabs = sequence(level.required_prefabs),
    },
    taskset = {
        tasks = sequence(taskset.tasks),
        optionaltasks = sequence(taskset.optionaltasks),
        numoptionaltasks = taskset.numoptionaltasks,
        valid_start_tasks = sequence(taskset.valid_start_tasks),
        required_prefabs = sequence(taskset.required_prefabs),
        set_pieces = set_pieces,
        set_pieces_layout = BOOT.snapshot(taskset.set_pieces),
    },
    tasks = tasks_out,
    start_location = {
        name = start_location.name,
        location = start_location.location,
        start_setpeice = start_location.start_setpeice,
        start_node = sequence(start_location.start_node),
    },
    prefab_swaps = swaps,
    story = {
        tasks = story_tasks,
        rooms = story_rooms,
        tags = story_tags,
        locks_keys = story_locks_keys,
        closures = story_closures,
    },
    world_tiles = world_tiles,
})
