-- The tasks and rooms reachable on the shard's path: the default forest (task set "default", start location "default")
-- or, with GEN_SHARD=caves, the caves (the DST_CAVE level's task set and start location).

local BOOT = ...
local tasks_mod = require("map/tasks")
local tasksets = require("map/tasksets")
local startlocations = require("map/startlocations")

local Reach = {}

local caves = BOOT.shard == "caves"
Reach.taskset = tasksets.GetGenTasks(caves and BOOT.level.overrides.task_set or "default")
Reach.start_location = startlocations.GetStartLocation(caves and BOOT.level.overrides.start_location or "default")

Reach.task_names = {}
for _, t in ipairs(Reach.taskset.tasks) do Reach.task_names[#Reach.task_names + 1] = t end
for _, t in ipairs(Reach.taskset.optionaltasks) do Reach.task_names[#Reach.task_names + 1] = t end

local rooms_used, room_names = {}, {}
local function use_room(name)
    if name ~= nil and not rooms_used[name] then
        rooms_used[name] = true
        room_names[#room_names + 1] = name
    end
end

for _, name in ipairs(Reach.task_names) do
    local task = assert(tasks_mod.GetTaskByName(name), "missing task " .. name)
    local entrance = task.entrance_room
    if type(entrance) == "table" then
        for _, r in ipairs(entrance) do use_room(r) end
    else
        use_room(entrance)
    end
    for room in pairs(task.room_choices or {}) do use_room(room) end
    use_room(task.background_room)
    use_room(task.cove_room_name or "Blank")
end
local start_nodes = Reach.start_location.start_node
if type(start_nodes) ~= "table" then start_nodes = { start_nodes } end
for _, r in ipairs(start_nodes) do use_room(r) end
use_room(BOOT.level.blocker_blank_room_name)
use_room("Blank")
for _, r in ipairs(BOOT.level.ocean_population or {}) do use_room(r) end
if not caves then use_room("MoonIsland_Meadows") end
use_room("BGImpassable")
table.sort(room_names)
Reach.room_names = room_names

local Rooms = require("map/rooms")
local MapTags = require("map/maptags")
local array = BOOT.array

local layout_names, seen = {}, {}
local function use_layout(name)
    if name ~= nil and not seen[name] then
        seen[name] = true
        layout_names[#layout_names + 1] = name
    end
end

for name in pairs(Reach.taskset.set_pieces or {}) do use_layout(name) end
for name in pairs(Reach.taskset.ocean_prefill_setpieces or {}) do use_layout(name) end
for _, name in ipairs(BOOT.level.required_setpieces or {}) do use_layout(name) end
for _, name in ipairs(BOOT.level.random_set_pieces or {}) do use_layout(name) end
use_layout(Reach.start_location.start_setpeice)
for _, room in ipairs(Reach.room_names) do
    local r = Rooms.GetRoomByName(room)
    for name in pairs(r.contents and r.contents.countstaticlayouts or {}) do use_layout(name) end
end

local sandbox_modules = {
    boons = require("map/boons"), traps = require("map/traps"), pointsofinterest = require("map/pointsofinterest"),
    protected_resources = require("map/protected_resources"),
}
local forest_areas = { Any = true, Rare = true }
for _, name in ipairs(Reach.task_names) do
    local t = require("map/tasks").GetTaskByName(name)
    if not t.level_set_piece_blocker and t.room_bg ~= nil then forest_areas[t.room_bg] = true end
end
Reach.sandboxes = {}
for kind, mod in pairs(sandbox_modules) do
    local areas = array()
    for area, pieces in pairs(mod.Sandbox) do
        local names = array()
        for piece in pairs(pieces) do names[#names + 1] = piece end
        areas[#areas + 1] = { area = area, pieces = names, forest = forest_areas[area] == true }
        if forest_areas[area] then
            for piece in pairs(pieces) do use_layout(piece) end
        end
    end
    Reach.sandboxes[kind] = areas
end

for _, room in ipairs(Reach.room_names) do
    for _, tag in ipairs(Rooms.GetRoomByName(room).tags or {}) do
        local fn = MapTags().Tag[tag]
        if fn then
            for trial = 1, 8 do
                local raw = math.random
                math.random = function(n) return n and math.min(trial, n) or 0.5 end
                local kind, value = fn(deepcopy(MapTags().TagData), BOOT.level)
                math.random = raw
                if kind == "STATIC" then use_layout(value) end
            end
        end
    end
end
table.sort(layout_names)

local maze_layouts = require("map/maze_layouts")
Reach.mazes = array()
if caves then
    for _, choice in ipairs(BOOT.sorted_keys(maze_layouts.AllLayouts)) do
        local shapes = array()
        for _, shape in ipairs(BOOT.sorted_keys(maze_layouts.AllLayouts[choice])) do
            shapes[#shapes + 1] = { shape = shape, name = choice .. "/" .. shape }
        end
        Reach.mazes[#Reach.mazes + 1] = { choice = choice, shapes = shapes }
    end
end

function Reach.layout_names()
    return layout_names
end

return Reach
