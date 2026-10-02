-- Extracts every layout reachable on the default forest path, once per prefab swap state (the layout modules resolve
-- swaps when they load, so they are reloaded after each SelectPrefabSwaps), as object_layout.LayoutForDefinition
-- returns them: flags, ground, the pairs() order of layout.layout, areas, defs and count, and for layouts without
-- areas or defs the final ConvertLayoutToEntitylist list. Also the map tag functions and the sandboxes.
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_layouts.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")
local Closures = dofile(GEN .. "/lib/closures.lua")
local closures = Closures.new()
local Reach = assert(loadfile(GEN .. "/lib/reach.lua"))(BOOT)
local array = BOOT.array
local Rooms = require("map/rooms")
local MapTags = require("map/maptags")

local LAYOUT_FIELDS = {
    type = true, scale = true, layout_file = true, ground_types = true, ground = true, layout = true, name = true,
    areas = true, defs = true, count = true, disable_transform = true, force_rotation = true, start_mask = true,
    fill_mask = true, layout_position = true, SafeFromDisconnect = true, add_topology = true, initfn = true,
    min_dist_from_land = true, rotation = true, tags = true, fill_ocean = true,
}

local tags_used, tag_names = {}, {}
local function use_tag(tag)
    if not tags_used[tag] then
        tags_used[tag] = true
        tag_names[#tag_names + 1] = tag
    end
end
for _, room in ipairs(Reach.room_names) do
    for _, tag in ipairs(Rooms.GetRoomByName(room).tags or {}) do use_tag(tag) end
end
for _, name in ipairs(Reach.task_names) do
    for _, tag in ipairs(require("map/tasks").GetTaskByName(name).room_tags or {}) do use_tag(tag) end
end
table.sort(tag_names)
local tags_out = array()
for _, tag in ipairs(tag_names) do
    local fns = MapTags()
    local fn = fns.Tag[tag]
    local results = array()
    local statics = {}
    if fn then
        for trial = 1, 8 do
            local data = deepcopy(fns.TagData)
            local raw = math.random
            math.random = function(n) return n and math.min(trial, n) or 0.5 end
            local first_kind, first_value = fn(data, BOOT.level)
            local second_kind, second_value = fn(data, BOOT.level)
            math.random = raw
            local key = tostring(first_kind) .. ":" .. tostring(first_value) .. "|" .. tostring(second_kind) .. ":" ..
                tostring(second_value)
            if not statics[key] then
                statics[key] = true
                results[#results + 1] = { first = { kind = first_kind, value = first_value },
                    second = { kind = second_kind, value = second_value } }
            end
        end
    end
    tags_out[#tags_out + 1] = {
        tag = tag,
        closure = fn and closures:ref(fn, "maptag:" .. tag) or nil,
        results = results,
    }
end

local layout_names = Reach.layout_names()
local sandboxes = Reach.sandboxes

local function object_list(list)
    local out = array()
    for _, o in ipairs(list) do
        local props = o.properties
        out[#out + 1] = { x = o.x, y = o.y, width = o.width, height = o.height,
            properties = (props ~= nil and next(props) ~= nil) and BOOT.json(props) or nil }
    end
    return out
end

local area_literals, area_literal_keys = array(), {}
local OPENERS = { ["function"] = 1, ["if"] = 1, ["do"] = 1, ["repeat"] = 1, ["end"] = -1, ["until"] = -1 }

local function long_bracket_end(text, pos)
    local eqs = text:match("^%[(=*)%[", pos)
    if not eqs then return nil end
    local _, stop = text:find("]" .. eqs .. "]", pos, true)
    return stop or #text
end

local function quoted_end(text, pos)
    local quote = text:sub(pos, pos)
    local i = pos + 1
    while i <= #text do
        local c = text:sub(i, i)
        if c == "\\" then
            i = i + 2
        elseif c == quote then
            return i
        else
            i = i + 1
        end
    end
    return #text
end

local function unescape(raw)
    return (loadstring("return " .. raw))()
end

local function lex_step(text, pos, state)
    local c = text:sub(pos, pos)
    if text:sub(pos, pos + 1) == "--" then
        local stop = long_bracket_end(text, pos + 2)
        return stop and stop + 1 or (text:find("\n", pos, true) or #text) + 1
    end
    if c == "\"" or c == "'" then
        local stop = quoted_end(text, pos)
        if state.depth > 0 then state.literals[#state.literals + 1] = unescape(text:sub(pos, stop)) end
        return stop + 1
    end
    local word = text:match("^[%a_][%w_]*", pos)
    if word then
        local delta = OPENERS[word]
        if delta and (state.depth > 0 or word == "function") then
            state.depth = state.depth + delta
            state.done = state.depth == 0
        end
        return pos + #word
    end
    return pos + 1
end

local function string_literals(fn)
    local info = debug.getinfo(fn, "S")
    local path = info.source:gsub("^@", "")
    local lines = {}
    local f = assert(io.open(path, "rb"))
    local n = 0
    for line in f:lines() do
        n = n + 1
        if n >= info.linedefined and n <= info.lastlinedefined then lines[#lines + 1] = line end
    end
    f:close()
    local text = table.concat(lines, "\n")
    local state = { depth = 0, literals = array(), done = false }
    local pos = 1
    while pos <= #text and not state.done do pos = lex_step(text, pos, state) end
    return state.literals
end

local function note_literals(fn, key)
    if not area_literal_keys[key] then
        area_literal_keys[key] = true
        area_literals[#area_literals + 1] = { closure = key, literals = string_literals(fn) }
    end
end

local function value_or_closure(v, context)
    if type(v) == "function" then
        local key = closures:ref(v, context)
        note_literals(v, key)
        return { closure = key }
    end
    if type(v) == "table" then
        local out = array()
        for _, item in ipairs(v) do
            if type(item) == "table" then
                out[#out + 1] = { prefab = item.prefab, x = item.x, y = item.y,
                    properties = item.properties and BOOT.json(item.properties) or nil }
            else
                out[#out + 1] = item
            end
        end
        return { list = out }
    end
    return v
end

local function ordered(t, fn)
    local out = array()
    for k, v in pairs(t or {}) do out[#out + 1] = { key = k, value = fn(v, k) } end
    return out
end

local function describe(name, definition, choices)
    local obj_layout = require("map/object_layout")
    local layout = obj_layout.LayoutForDefinition(definition or name, choices)
    if layout == nil then return { missing = true } end
    for k in pairs(layout) do assert(LAYOUT_FIELDS[k], "unknown layout field " .. tostring(k) .. " in " .. name) end
    local ground = nil
    if layout.ground ~= nil then
        ground = array()
        for r, row in ipairs(layout.ground) do
            local tiles = array()
            for c = 1, #layout.ground do
                local index = row[c]
                tiles[#tiles + 1] = (index ~= nil and index ~= 0) and layout.ground_types[index] or 0
            end
            ground[#ground + 1] = tiles
        end
    end
    local out = {
        type = layout.type,
        scale = layout.scale,
        layout_file = layout.layout_file,
        disable_transform = layout.disable_transform,
        force_rotation = layout.force_rotation,
        start_mask = layout.start_mask,
        fill_mask = layout.fill_mask,
        layout_position = layout.layout_position,
        SafeFromDisconnect = layout.SafeFromDisconnect,
        add_topology = layout.add_topology and BOOT.json(layout.add_topology) or nil,
        min_dist_from_land = layout.min_dist_from_land,
        initfn = layout.initfn and closures:ref(layout.initfn, "layout_initfn:" .. name) or nil,
        ground = ground,
        layout = ordered(layout.layout, function(v) return object_list(v) end),
        areas = layout.areas and ordered(layout.areas, function(v, k)
            return value_or_closure(v, "layout_area:" .. name .. ":" .. tostring(k))
        end) or nil,
        defs = layout.defs and ordered(layout.defs, function(v)
            local choices = array()
            for _, p in pairs(v) do choices[#choices + 1] = p end
            return choices
        end) or nil,
        count = layout.count and ordered(layout.count, function(v, k)
            return value_or_closure(v, "layout_count:" .. name .. ":" .. tostring(k))
        end) or nil,
    }
    if (layout.areas ~= nil or layout.defs ~= nil) and layout.layout ~= nil then out.layout_snapshot = BOOT.snapshot(layout.layout) end
    if layout.count ~= nil and layout.defs ~= nil then out.count_snapshot = BOOT.snapshot(layout.count) end
    if layout.areas == nil and layout.defs == nil and layout.type == LAYOUT.STATIC then
        local items = obj_layout.ConvertLayoutToEntitylist(layout)
        local entities = array()
        for _, item in ipairs(items) do
            entities[#entities + 1] = { prefab = item.prefab, x = item.x, y = item.y,
                properties = item.properties and next(item.properties) ~= nil and BOOT.json(item.properties) or nil }
        end
        out.entities = entities
    end
    return out
end

local layouts_out = array()
local states = {}
for state = 0, 7 do
    BOOT.set_swaps(state)
    local by_name = {}
    local i = 1
    while i <= #layout_names do
        local name = layout_names[i]
        by_name[name] = describe(name)
        i = i + 1
    end
    for _, maze in ipairs(Reach.mazes) do
        for _, cell in ipairs(maze.shapes) do
            by_name[cell.name] = describe(cell.name, cell.shape, { maze.choice })
        end
    end
    states[state] = by_name
end
local function add_layout(name)
    local per_state = array()
    for state = 0, 7 do per_state[#per_state + 1] = states[state][name] end
    layouts_out[#layouts_out + 1] = { name = name, states = per_state }
end
for _, name in ipairs(layout_names) do add_layout(name) end
for _, maze in ipairs(Reach.mazes) do
    for _, cell in ipairs(maze.shapes) do add_layout(cell.name) end
end

BOOT.write_json({
    layouts = layouts_out,
    mazes = #Reach.mazes > 0 and Reach.mazes or nil,
    sandboxes = sandboxes,
    maptags = tags_out,
    area_literals = area_literals,
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
