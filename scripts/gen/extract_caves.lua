-- Extracts the level table inputs of the caves shard (preset DST_CAVE, task set "cave_default", start location
-- "caves"): the level and location fields worldgen reads, the task set with the Lua 5.1 node layout of its set_pieces
-- (the table AddSetPeices keeps inserting into), every task's room_bg, the caves start rooms and which prefab swaps the
-- caves allow. Prints one JSON document (the sidecar out/caves.json).
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_caves.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")

local levels = require("map/levels")
local tasks_mod = require("map/tasks")
local tasksets = require("map/tasksets")
local startlocations = require("map/startlocations")
local array = BOOT.array

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
    world_tiles = world_tiles,
})
