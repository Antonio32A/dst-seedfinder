local G = GLOBAL
local rawget = G.rawget

if rawget(G, "WORLDGEN_MAIN") ~= 1 then
    return
end

local DEFAULT_SEEDS = "1-10"
local DEFAULT_LOOP = false
local DEFAULT_REPLAY_FIRST = false
local POSITION_FORMAT = "%.2f"
local DEFAULT_CHUNK_SIZE = 3000
local MIN_CHUNK_SIZE = 100
local TRACE_LIMIT = 60000
local MAX_TRIES = 5
local TAG = "GTWORLD"
local UNTRACED_METHODS = { LuaPrint = true }
local TOPOLOGY_OMIT = { colours = true, overrides = true, c = true }
local SHARDS = { forest = "forest", cave = "caves" }

local pcall, xpcall, tonumber, next, select = G.pcall, G.xpcall, G.tonumber, G.next, G.select
local debug, os, json = G.debug, rawget(G, "os"), G.json
local io_lib = rawget(G, "io")
local emit_print = print
local PrefabSwaps = require("prefabswaps")
local forest_map = require("map/forest_map")
local worldentities = require("worldentities")

local function config_value(name, fallback)
    local ok, value = pcall(GetModConfigData, name)
    if ok and value ~= nil then
        return value
    end
    return fallback
end

local function parse_seeds(spec)
    local seeds = {}
    for part in string.gmatch(tostring(spec), "[^,%s]+") do
        local first, last = string.match(part, "^(%d+)%-(%d+)$")
        first = tonumber(first or part)
        for seed = first, tonumber(last) or first do
            table.insert(seeds, seed)
        end
    end
    return seeds
end

local function generation_parameters()
    local ok, params = pcall(json.decode, G.GEN_PARAMETERS)
    if ok and type(params) == "table" and type(params.level_data) == "table" then
        return params
    end
end

local env_seeds = os and os.getenv and os.getenv("GTWORLD_SEEDS")
local SEEDS = parse_seeds(env_seeds or config_value("seeds", DEFAULT_SEEDS))
local LOOP = config_value("loop", DEFAULT_LOOP) == true
local REPLAY_FIRST = config_value("replay_first", DEFAULT_REPLAY_FIRST) == true
local CHUNK_SIZE = math.max(MIN_CHUNK_SIZE, math.floor(tonumber(config_value("chunk_size", DEFAULT_CHUNK_SIZE)) or DEFAULT_CHUNK_SIZE))
local PARAMS = generation_parameters()

if #SEEDS == 0 or PARAMS == nil or SHARDS[PARAMS.level_data.location] == nil then
    return
end

local SHARD = SHARDS[PARAMS.level_data.location]

local JSON_ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encode_string(s)
    local escaped = string.gsub(s, '[%c"\\%%]', function(c)
        return JSON_ESCAPES[c] or string.format("\\u%04x", string.byte(c))
    end)
    return '"' .. escaped .. '"'
end

local function encode_number(n)
    if n ~= n or n == math.huge or n == -math.huge then
        return "null"
    end
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
        return string.format("%.0f", n)
    end
    local short = string.format("%.15g", n)
    if tonumber(short) == n then
        return short
    end
    return string.format("%.17g", n)
end

local encode_value

local function key_order(a, b)
    return tostring(a) < tostring(b)
end

local function sorted_keys(t, omit)
    local keys = {}
    for k in pairs(t) do
        if not (omit and omit[k]) then
            table.insert(keys, k)
        end
    end
    table.sort(keys, key_order)
    return keys
end

local function encode_array(list, omit)
    local parts = {}
    for i = 1, #list do
        parts[i] = encode_value(list[i], omit)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function encode_table(t, omit)
    if t[1] ~= nil or next(t) == nil then
        return encode_array(t, omit)
    end
    local parts = {}
    for i, k in ipairs(sorted_keys(t, omit)) do
        parts[i] = encode_string(tostring(k)) .. ":" .. encode_value(t[k], omit)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local ENCODERS = { string = encode_string, number = encode_number, boolean = tostring, table = encode_table }

encode_value = function(v, omit)
    local encoder = ENCODERS[type(v)]
    return encoder and encoder(v, omit) or "null"
end

local function ordered_object(fields)
    local parts = {}
    for i, field in ipairs(fields) do
        parts[i] = encode_string(field[1]) .. ":" .. field[2]
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function encode_coordinate(v)
    if type(v) ~= "number" then
        return "null"
    end
    local text = string.format(POSITION_FORMAT, v)
    if string.find(text, ".", 1, true) then
        text = string.gsub(text, "%.?0+$", "")
    end
    return text
end

local launch = os and os.time and os.time() or 0
local records = 0

local function write_record_file(key, text)
    local file = io_lib.open("unsafedata/gtworld_" .. string.gsub(key, ":", "_") .. ".json", "w")
    if file then
        file:write(text)
        file:close()
    end
end

local function emit_record(kind, text)
    local key = kind .. ":" .. launch .. ":" .. records
    records = records + 1
    local total = math.max(1, math.ceil(#text / CHUNK_SIZE))
    for i = 1, total do
        local chunk = string.sub(text, (i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
        emit_print(TAG .. " " .. key .. " " .. i .. "/" .. total .. " " .. chunk .. "|")
    end
    if io_lib and io_lib.open then
        pcall(write_record_file, key, text)
    end
end

local function emit_error(seed, message)
    emit_record("error", ordered_object({
        { "seed", encode_value(seed) },
        { "message", encode_string(tostring(message)) },
    }))
end

local raw_random, raw_randomseed = math.random, math.randomseed
local draws = 0
local world = nil
local runs = 0
local mode = "fresh"

local trace = {}
for i = 1, TRACE_LIMIT * 4 do
    trace[i] = 0
end
local trace_length, trace_dropped = 0, 0
local method_names, method_ids, method_calls, method_draws = {}, {}, {}, {}

local function start_world(seed)
    trace_length, trace_dropped = 0, 0
    for i = 1, #method_names do
        method_calls[i], method_draws[i] = 0, 0
    end
    world = { seed = seed, run = runs, mode = mode, attempts = 0, checkpoints = {}, fields = {} }
    runs = runs + 1
end

local seed_args = nil

math.randomseed = function(seed, ...)
    draws = 0
    seed_args = { seed, ... }
    start_world(seed)
    return raw_randomseed(seed, ...)
end

math.random = function(...)
    draws = draws + 1
    return raw_random(...)
end

local STREAM_SCAN_LIMIT = 4000000

-- Steps since the last math.randomseed, engine draws included (`draws` counts only Lua calls): reads the next three
-- outputs, finds them by replaying the stream from the seed, and restores the stream to that position.
local function stream_position()
    if seed_args == nil then
        return nil
    end
    local first, second, third = raw_random(), raw_random(), raw_random()
    raw_randomseed(seed_args[1], seed_args[2], seed_args[3])
    local a, b, c = raw_random(), raw_random(), raw_random()
    local position = 0
    while a ~= first or b ~= second or c ~= third do
        a, b, c = b, c, raw_random()
        position = position + 1
        if position > STREAM_SCAN_LIMIT then
            return nil
        end
    end
    raw_randomseed(seed_args[1], seed_args[2], seed_args[3])
    for _ = 1, position do
        raw_random()
    end
    return position
end

local function checkpoint(label)
    if world then
        table.insert(world.checkpoints, { label, draws })
    end
end

local function stream_checkpoint(label)
    if world then
        table.insert(world.checkpoints, { label, draws, stream_position() })
    end
end

local function set_field(name, value)
    if world then
        world.fields[name] = value
    end
end

local function record_call(id, before, after)
    method_calls[id] = method_calls[id] + 1
    method_draws[id] = method_draws[id] + after - before
    local last = trace_length * 4
    if trace_length > 0 and trace[last - 3] == id and trace[last - 1] == trace[last]
        and trace[last] == before and after == before then
        trace[last - 2] = trace[last - 2] + 1
    elseif trace_length < TRACE_LIMIT then
        trace[last + 1], trace[last + 2], trace[last + 3], trace[last + 4] = id, 1, before, after
        trace_length = trace_length + 1
    else
        trace_dropped = trace_dropped + 1
    end
end

local function finish_call(id, before, ...)
    record_call(id, before, draws)
    return ...
end

local raw_methods = {}
local reset_probe_state
local PROBES = {}
local PRE_PROBES = {}
local probe_enabled = (os and os.getenv and os.getenv("GTWORLD_PROBES") or "1") ~= "0"

local function run_probe(probes, name, args, results)
    local probe = probes[name]
    if probe and probe_enabled and world then
        local ok, err = pcall(probe, args, results)
        if not ok then
            world.probe_errors = (world.probe_errors or 0) + 1
            world.probe_error = tostring(err)
        end
    end
end

local function finish_probed(id, before, name, args, ...)
    record_call(id, before, draws)
    run_probe(PROBES, name, args, { n = select("#", ...), ... })
    return ...
end

local function traced(name, method)
    raw_methods[name] = method
    local id = method_ids[name]
    if id == nil then
        table.insert(method_names, name)
        id = #method_names
        method_ids[name], method_calls[id], method_draws[id] = id, 0, 0
    end
    return function(...)
        if PRE_PROBES[name] then
            run_probe(PRE_PROBES, name, { n = select("#", ...), ... })
        end
        if PROBES[name] then
            local before = draws
            return finish_probed(id, before, name, { n = select("#", ...), ... }, method(...))
        end
        return finish_call(id, draws, method(...))
    end
end

local function is_traceable(name, value)
    return type(value) == "function" and type(name) == "string"
        and not UNTRACED_METHODS[name] and string.sub(name, 1, 2) ~= "__"
end

local function trace_method_table(methods)
    for name, method in pairs(methods) do
        if is_traceable(name, method) then
            methods[name] = traced(name, method)
        end
    end
end

local function trace_index_function(mt, index)
    local wrappers = {}
    mt.__index = function(self, key)
        local value = index(self, key)
        if not is_traceable(key, value) then
            return value
        end
        wrappers[key] = wrappers[key] or traced(key, value)
        return wrappers[key]
    end
end

local function install_worldsim_tracing()
    local worldsim = rawget(G, "WorldSim")
    local mt = worldsim ~= nil and debug.getmetatable(worldsim)
    local index = mt and mt.__index
    if type(index) == "table" then
        trace_method_table(index)
        return "method table"
    elseif type(index) == "function" then
        trace_index_function(mt, index)
        return "index function"
    end
    return "unavailable"
end

local function find_upvalue(fn, name)
    local i = 1
    while true do
        local upname, value = debug.getupvalue(fn, i)
        if upname == nil or upname == name then
            return value
        end
        i = i + 1
    end
end

local function finish_hook(post, self, ...)
    post(self)
    return ...
end

local function hook(owner, key, pre, post)
    local original = owner[key]
    owner[key] = function(self, ...)
        pre(self)
        return finish_hook(post, self, original(self, ...))
    end
    return original
end

local function nothing() end

local original_select_prefab_swaps = hook(PrefabSwaps, "SelectPrefabSwaps", nothing, function()
    checkpoint("prefab_swaps")
end)

local function selected_prefab_swaps()
    local chosen = {}
    for category, sets in pairs(find_upvalue(original_select_prefab_swaps, "_selected_sets") or {}) do
        for _, set in ipairs(sets) do
            if set.active then
                chosen[category] = set.name
            end
        end
    end
    return chosen
end

local function encode_task_set_pieces(level)
    local tasks, placement = {}, {}
    for _, task in ipairs(level.chosen_tasks or {}) do
        table.insert(tasks, task.id)
        table.insert(placement, ordered_object({
            { "task", encode_string(task.id) },
            { "set_pieces", encode_value(task.set_pieces or {}) },
            { "random_set_pieces", encode_value(task.random_set_pieces or {}) },
        }))
    end
    return encode_array(tasks), "[" .. table.concat(placement, ",") .. "]"
end

hook(G.Level, "ChooseTasks", nothing, function()
    checkpoint("choose_tasks")
end)

hook(G.Level, "ChooseSetPieces", function(level)
    checkpoint("add_set_pieces")
    set_field("set_pieces_added", encode_value(level.set_pieces or {}))
end, function(level)
    checkpoint("choose_set_pieces")
    local tasks, placement = encode_task_set_pieces(level)
    set_field("prefab_swaps", encode_value(selected_prefab_swaps()))
    set_field("set_pieces", encode_value(level.set_pieces or {}))
    set_field("tasks", tasks)
    set_field("task_set_pieces", placement)
end)

local function encode_positions(list)
    local parts = {}
    for i, ent in ipairs(list) do
        parts[i] = "[" .. encode_coordinate(ent.x) .. "," .. encode_coordinate(ent.z) .. "]"
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function collect_teleporters(prefab, list, out)
    for index, ent in ipairs(list) do
        local teleporter = type(ent.data) == "table" and ent.data.teleporter
        if type(teleporter) == "table" then
            table.insert(out, ordered_object({
                { "prefab", encode_string(prefab) },
                { "index", encode_number(index - 1) },
                { "id", encode_value(ent.id) },
                { "target", encode_value(teleporter.target) },
                { "x", encode_coordinate(ent.x) },
                { "z", encode_coordinate(ent.z) },
            }))
        end
    end
end

local function encode_entities(ents)
    local positions, counts, teleporters = {}, {}, {}
    for _, prefab in ipairs(sorted_keys(ents)) do
        local list = ents[prefab]
        local name = encode_string(tostring(prefab))
        table.insert(positions, name .. ":" .. encode_positions(list))
        table.insert(counts, name .. ":" .. #list)
        collect_teleporters(prefab, list, teleporters)
    end
    return "{" .. table.concat(positions, ",") .. "}", "{" .. table.concat(counts, ",") .. "}",
        "[" .. table.concat(teleporters, ",") .. "]"
end

local function encode_worldsim()
    local entries, totals, names, local_ids = {}, {}, {}, {}
    for i = 1, trace_length * 4 do
        entries[i] = trace[i]
    end
    for i = 1, trace_length * 4, 4 do
        local name = method_names[entries[i]]
        if local_ids[name] == nil then
            table.insert(names, name)
            local_ids[name] = #names
        end
        entries[i] = local_ids[name]
    end
    for id, name in ipairs(method_names) do
        if method_calls[id] > 0 then
            totals[name] = { method_calls[id], method_draws[id] }
        end
    end
    return ordered_object({
        { "methods", encode_array(names) },
        { "entries", encode_array(entries) },
        { "dropped_calls", encode_number(trace_dropped) },
        { "totals", encode_value(totals) },
    })
end


local function fmt_float(v)
    if type(v) ~= "number" then
        return "null"
    end
    if v ~= v then
        return "nan"
    elseif v == math.huge then
        return "inf"
    elseif v == -math.huge then
        return "-inf"
    end
    return string.format("%.9g", v)
end

local function raw_call(name, ...)
    local realgen = rawget(G, "REALGEN")
    local real = realgen and realgen.real_worldsim
    if real then
        return real[name](real, ...)
    end
    return raw_methods[name](G.WorldSim, ...)
end

local function probe_record(kind, fields)
    if world then
        world.probes = world.probes or {}
        table.insert(fields, 1, { "kind", encode_string(kind) })
        table.insert(fields, 2, { "attempt", encode_number(world.attempts) })
        table.insert(world.probes, ordered_object(fields))
    end
end

local vertex_names, vertex_seen = {}, {}

local function note_vertex(name)
    if not vertex_seen[name] then
        vertex_seen[name] = true
        table.insert(vertex_names, name)
    end
end

local function note_link(args)
    note_vertex(args[3])
    note_vertex(args[2])
end

local function encode_site_list()
    local parts = {}
    for i, name in ipairs(vertex_names) do
        local x, y = raw_call("GetSite", name)
        local cx, cy = raw_call("GetSiteCentroid", name)
        local px, py = raw_call("GetSitePolygon", name)
        local poly = {}
        for k = 1, #(px or {}) do
            poly[k] = fmt_float(px[k]) .. "," .. fmt_float(py[k])
        end
        local nums = { fmt_float(x), fmt_float(y), fmt_float(cx), fmt_float(cy) }
        parts[i] = "[" .. encode_string(name) .. "," .. encode_string(table.concat(nums, ",")) .. ","
            .. encode_string(table.concat(poly, ";")) .. "]"
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function encode_areas()
    local parts = {}
    for i, name in ipairs(vertex_names) do
        parts[i] = encode_number(raw_call("GetSiteArea", name))
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function encode_tiles_rle()
    local w, h = raw_call("GetWorldSize")
    local parts, last, run = {}, nil, 0
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local t = raw_call("GetTile", x, y)
            if t == last then
                run = run + 1
            else
                if last ~= nil then
                    table.insert(parts, last .. "*" .. run)
                end
                last, run = t, 1
            end
        end
    end
    table.insert(parts, last .. "*" .. run)
    return encode_number(w), encode_number(h), encode_string(table.concat(parts, ","))
end

local function probe_sites(label, with_areas)
    local fields = { { "label", encode_string(label) }, { "vertices", encode_site_list() } }
    if with_areas then
        table.insert(fields, { "areas", encode_areas() })
    end
    probe_record("sites", fields)
end

local function probe_tiles(label)
    local w, h, rle = encode_tiles_rle()
    probe_record("tiles", { { "label", encode_string(label) }, { "w", w }, { "h", h }, { "rle", rle } })
end

local voronoi_passes = 0

PROBES.AddLink = function(args) note_link(args) end
PROBES.AddExternalLink = function(args) note_link(args) end
PROBES.WorldGen_VoronoiPass = function(args)
    voronoi_passes = voronoi_passes + 1
    probe_sites("voronoi_pass_" .. voronoi_passes .. "_" .. tostring(args[2]), false)
end
PROBES.WorldGen_Commit = function(args, results)
    probe_record("commit", { { "ok", tostring(results[1]) } })
    probe_sites("commit", false)
end
PROBES.ConvertToTileMap = function()
    probe_sites("tilemap", true)
    probe_tiles("tilemap")
end
PROBES.SeparateIslands = function() probe_tiles("separate_islands") end
PROBES.ForceConnectivity = function() probe_tiles("force_connectivity") end
PROBES.DrawRoads = function() probe_tiles("draw_roads") end

local replace_single_calls = 0
local maze_tiles_recorded = false

reset_probe_state = function()
    vertex_names, vertex_seen, voronoi_passes, replace_single_calls = {}, {}, 0, 0
    maze_tiles_recorded = false
end
PROBES.ReplaceSingleNonLandTiles = function()
    replace_single_calls = replace_single_calls + 1
    if replace_single_calls == 1 then
        probe_tiles("land_done")
    end
end

local function encode_point_lists(results)
    local xs, ys, types = results[1] or {}, results[2] or {}, results[3] or {}
    local pts = {}
    for i = 1, #xs do
        pts[i] = xs[i] .. "," .. ys[i] .. "," .. tostring(types[i])
    end
    return encode_string(table.concat(pts, ";")), #xs
end

local function probe_tiles_before_mazes()
    if not maze_tiles_recorded then
        maze_tiles_recorded = true
        probe_tiles("before_mazes")
    end
end

PRE_PROBES.RunMaze = probe_tiles_before_mazes
PRE_PROBES.GetPointsForMetaMaze = probe_tiles_before_mazes

PROBES.RunCA = function(args)
    local width, height = raw_call("GetWorldSize")
    local xs, ys = raw_call("GetSitePolygon", args[2])
    local x0, y0, x1, y1 = width, height, -1, -1
    for i = 1, #(xs or {}) do
        x0, x1 = math.min(x0, math.floor(xs[i]) - 2), math.max(x1, math.ceil(xs[i]) + 2)
        y0, y1 = math.min(y0, math.floor(ys[i]) - 2), math.max(y1, math.ceil(ys[i]) + 2)
    end
    x0, y0, x1, y1 = math.max(0, x0), math.max(0, y0), math.min(width - 1, x1), math.min(height - 1, y1)
    local rows = {}
    for y = y0, y1 do
        local row = {}
        for x = x0, x1 do
            row[#row + 1] = raw_call("GetTile", x, y)
        end
        rows[#rows + 1] = table.concat(row, ",")
    end
    probe_record("runca", {
        { "id", encode_string(args[2]) },
        { "iterations", encode_value(args[3]) },
        { "seed_mode", encode_value(args[4]) },
        { "num_random_points", encode_value(args[5]) },
        { "draws_after", encode_number(draws) },
        { "region", encode_value({ x0, y0, x1, y1 }) },
        { "tiles", encode_string(table.concat(rows, ";")) },
    })
end

PROBES.RunMaze = function(args, results)
    local encoded, count = encode_point_lists(results)
    probe_record("runmaze", {
        { "maze_type", encode_value(args[2]) },
        { "val", encode_value(args[3]) },
        { "tile_a", encode_value(args[4]) },
        { "tile_b", encode_value(args[5]) },
        { "nodes", encode_value(args[6]) },
        { "draws_after", encode_number(draws) },
        { "count", encode_number(count) },
        { "pts", encoded },
    })
end

PROBES.GetPointsForMetaMaze = function(args, results)
    local encoded, count = encode_point_lists(results)
    probe_record("metamaze", {
        { "cell_size", encode_value(args[2]) },
        { "nodes", encode_value(args[3]) },
        { "draws_after", encode_number(draws) },
        { "count", encode_number(count) },
        { "pts", encoded },
    })
end

PROBES.DetectDisconnect = function(_, results)
    probe_record("disconnect", { { "count", encode_value(results[1]) } })
end

PROBES.GetPointsForSite = function(args, results)
    local encoded, count = encode_point_lists(results)
    probe_record("points", {
        { "id", encode_string(args[2]) },
        { "area", encode_number(raw_call("GetSiteArea", args[2])) },
        { "count", encode_number(count) },
        { "draws_before", encode_number(draws) },
        { "pts", encoded },
    })
end

PROBES.ReserveSpace = function(args, results)
    local tiles = args[7]
    probe_record("reserve", {
        { "id", encode_string(args[2]) },
        { "size", fmt_float(args[3]) },
        { "start_mask", encode_value(args[4]) },
        { "fill_mask", encode_value(args[5]) },
        { "position", encode_value(args[6]) },
        { "tiles", encode_number(type(tiles) == "table" and #tiles or -1) },
        { "area", encode_number(raw_call("GetSiteArea", args[2])) },
        { "x", encode_value(results[1]) },
        { "y", encode_value(results[2]) },
    })
end

PROBES.GenerateBlendedMap = function(args, results)
    local t, sum, count = results[1] or {}, 0, 0
    for i = 0, (results[2] or 0) * (results[3] or 0) - 1 do
        local v = t[i]
        if v then
            sum = sum + v * ((i % 7919) + 1)
            count = count + 1
        end
    end
    probe_record("blend", {
        { "kernel", encode_value(args[2]) }, { "sigma", encode_value(args[3]) },
        { "w", encode_value(results[2]) }, { "h", encode_value(results[3]) },
        { "count", encode_number(count) }, { "weighted_sum", string.format("%.17g", sum) },
        { "first", fmt_float(t[0]) }, { "mid", fmt_float(t[math.floor(count / 2)]) },
    })
end

local function world_fields(finished, status)
    local checkpoints = {}
    for i, entry in ipairs(finished.checkpoints) do
        checkpoints[i] = encode_array(entry)
    end
    local fields = {
        { "seed", encode_value(finished.seed) },
        { "launch", encode_number(launch) },
        { "run", encode_number(finished.run) },
        { "mode", encode_string(finished.mode) },
        { "shard", encode_string(SHARD) },
        { "status", encode_string(status) },
        { "attempts", encode_number(finished.attempts) },
        { "rng_checkpoints", "[" .. table.concat(checkpoints, ",") .. "]" },
        { "worldsim", encode_worldsim() },
    }
    for _, name in ipairs({ "prefab_swaps", "tasks", "set_pieces_added", "set_pieces", "task_set_pieces" }) do
        table.insert(fields, { name, finished.fields[name] or "null" })
    end
    table.insert(fields, { "probes", "[" .. table.concat(finished.probes or {}, ",") .. "]" })
    table.insert(fields, { "probe_errors", encode_number(finished.probe_errors or 0) })
    table.insert(fields, { "probe_error", encode_value(finished.probe_error) })
    return fields
end

local function encode_roads(roads)
    local parts = {}
    for i = 1, G.table.maxn(roads or {}) do
        parts[i] = encode_value(roads[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function map_fields(savedata)
    local map = savedata.map
    local positions, counts, teleporters = encode_entities(savedata.ents or {})
    return {
        { "width", encode_value(map.width) },
        { "height", encode_value(map.height) },
        { "meta", encode_value(savedata.meta) },
        { "world_tile_map", encode_value(map.world_tile_map) },
        { "topology", encode_value(map.topology, TOPOLOGY_OMIT) },
        { "roads", encode_roads(map.roads) },
        { "entity_counts", counts },
        { "teleporters", teleporters },
        { "entities", positions },
        { "tiles", encode_value(map.tiles) },
        { "nodeidtilemap", encode_value(map.nodeidtilemap) },
    }
end

local function emit_world(finished, savedata, status)
    local fields = world_fields(finished, status)
    if savedata ~= nil then
        for _, field in ipairs(map_fields(savedata)) do
            table.insert(fields, field)
        end
    end
    emit_record("world", ordered_object(fields))
end

local function loop_seeds()
    local seeds = {}
    for i = 2, #SEEDS do
        table.insert(seeds, SEEDS[i])
    end
    if REPLAY_FIRST then
        table.insert(seeds, SEEDS[1])
    end
    return seeds
end

local function generate_in_loop(seed)
    G.collectgarbage("collect")
    G.WorldSim:ResetAll()
    G.SEED = G.SetWorldGenSeed(seed)
    local world_gen_data = json.decode(G.GEN_PARAMETERS)
    G.SetDLCEnabled(world_gen_data.DLCEnabled)
    G.GenerateNew(false, world_gen_data)
end

local finish_world

local function run_loop()
    mode = "loop"
    for _, seed in ipairs(LOOP and loop_seeds() or {}) do
        local ok, err = xpcall(function() generate_in_loop(seed) end, debug.traceback)
        if not ok then
            emit_error(seed, err)
        end
        if not ok and world then
            finish_world(nil, "error")
        end
    end
    mode = "done"
    G.SEED = SEEDS[1]
    emit_record("done", ordered_object({ { "worlds", encode_number(runs) }, { "records", encode_number(records + 1) } }))
end

finish_world = function(savedata, status)
    local finished = world
    world = nil
    local ok, err = xpcall(function() emit_world(finished, savedata, status) end, debug.traceback)
    if not ok then
        emit_error(finished and finished.seed, err)
    end
    if mode == "fresh" then
        run_loop()
    end
end

local original_generate = forest_map.Generate
forest_map.Generate = function(...)
    if world then
        world.attempts = world.attempts + 1
    end
    stream_checkpoint("generate_begin")
    if reset_probe_state then
        reset_probe_state()
    end
    local savedata = original_generate(...)
    stream_checkpoint(savedata and "generate_end" or "generate_failed")
    if savedata == nil and world and world.attempts >= MAX_TRIES then
        finish_world(nil, "gave_up")
    end
    return savedata
end

local original_add_world_entities = worldentities.AddWorldEntities
worldentities.AddWorldEntities = function(savedata, ...)
    original_add_world_entities(savedata, ...)
    checkpoint("add_world_entities")
    if world then
        finish_world(savedata, "ok")
    end
end

local tracing = install_worldsim_tracing()
local engine_seed = rawget(G, "SEED")
G.SEED = SEEDS[1]

emit_record("info", ordered_object({
    { "app_version", encode_value(rawget(G, "APP_VERSION")) },
    { "launch", encode_number(launch) },
    { "engine_seed", encode_value(engine_seed) },
    { "seeds", encode_array(SEEDS) },
    { "loop", tostring(LOOP) },
    { "replay_first", tostring(REPLAY_FIRST) },
    { "worldsim_tracing", encode_string(tracing) },
    { "trace_limit", encode_number(TRACE_LIMIT) },
    { "chunk_size", encode_number(CHUNK_SIZE) },
    { "position_format", encode_string(POSITION_FORMAT) },
    { "has_io", tostring(io_lib ~= nil) },
    { "shard", encode_string(SHARD) },
    { "level_type", encode_value(PARAMS.level_type) },
    { "level_data", encode_value(PARAMS.level_data) },
}))
