-- Closure registry shared by the lua generators: every function value found in a constant table is recorded by its
-- source span, normalised body text and upvalue values, so that identical bodies share one variant.

local Closures = {}
Closures.__index = Closures

local source_cache = {}

local function source_lines(file)
    if source_cache[file] == nil then
        local lines = {}
        local f = io.open(HARNESS_SCRIPTS_DIR .. "/" .. file, "rb")
        if f then
            for line in f:lines() do lines[#lines + 1] = line end
            f:close()
        end
        source_cache[file] = lines
    end
    return source_cache[file]
end

local OPENERS = { ["function"] = 1, ["if"] = 1, ["do"] = 1, ["repeat"] = 1, ["end"] = -1, ["until"] = -1 }

local function body_text(file, first, last)
    local lines = source_lines(file)
    local parts = {}
    for i = first, last do parts[#parts + 1] = lines[i] or "" end
    local text = table.concat(parts, "\n")
    local start = text:find("%f[%w_]function%f[^%w_]")
    if start == nil then return (text:gsub("%s+", " ")) end
    text = text:sub(start)
    local depth, stop = 0, #text
    for pos, word in text:gmatch("()([%a_][%w_]*)") do
        local delta = OPENERS[word]
        if delta then
            depth = depth + delta
            if depth == 0 then
                stop = pos + #word - 1
                break
            end
        end
    end
    return (text:sub(1, stop):gsub("%s+", " "))
end

local function describe_upvalue(v, depth)
    local kind = type(v)
    if kind == "number" or kind == "string" or kind == "boolean" then return v end
    if kind == "nil" then return "<nil>" end
    if kind == "function" then
        local info = debug.getinfo(v, "S")
        if info.what == "C" then return "<C function>" end
        return string.format("<function %s:%d-%d>", info.source:gsub("^@", ""):gsub("^.*/game%-scripts/", ""), info.linedefined,
            info.lastlinedefined)
    end
    if kind == "table" then
        if depth > 2 then return "<table>" end
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        if n > 40 then return string.format("<table of %d>", n) end
        local out = {}
        for k, item in pairs(v) do
            out[#out + 1] = tostring(k) .. "=" .. tostring(describe_upvalue(item, depth + 1))
        end
        table.sort(out)
        return "{" .. table.concat(out, ", ") .. "}"
    end
    return "<" .. kind .. ">"
end

local function global_value(path)
    local ok, v = pcall(function()
        local cur = _G
        for part in path:gmatch("[^%.]+") do
            if type(cur) ~= "table" then return nil end
            cur = rawget(cur, part)
        end
        return cur
    end)
    if ok then return v end
end

local function referenced_globals(body)
    local out = {}
    for path in body:gmatch("%f[%w_.][%u_][%u%d_]*[%.%w_]*") do
        local v = global_value(path)
        if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then
            out[#out + 1] = { name = path, value = v }
        end
    end
    for event in body:gmatch("IsSpecialEventActive%(SPECIAL_EVENTS%.([%u_]+)%)") do
        out[#out + 1] = { name = "IsSpecialEventActive(SPECIAL_EVENTS." .. event .. ")",
            value = IsSpecialEventActive(SPECIAL_EVENTS[event]) }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    local unique = {}
    for _, g in ipairs(out) do
        if #unique == 0 or unique[#unique].name ~= g.name then unique[#unique + 1] = g end
    end
    return unique
end

function Closures.new()
    return setmetatable({ by_key = {}, order = {} }, Closures)
end

function Closures:ref(fn, context)
    local info = debug.getinfo(fn, "S")
    local file = info.source:gsub("^@", ""):gsub("^.*/game%-scripts/", "")
    local upvalues = {}
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if name == nil then break end
        upvalues[#upvalues + 1] = { name = name, value = describe_upvalue(value, 0) }
    end
    local body = body_text(file, info.linedefined, info.lastlinedefined)
    local parts = { body }
    for _, u in ipairs(upvalues) do parts[#parts + 1] = u.name .. "=" .. tostring(u.value) end
    local key = table.concat(parts, "\0")
    local entry = self.by_key[key]
    if entry == nil then
        entry = { body = body, upvalues = upvalues, globals = referenced_globals(body), sites = {}, contexts = {} }
        self.by_key[key] = entry
        self.order[#self.order + 1] = key
    end
    local site = string.format("%s:%d-%d", file, info.linedefined, info.lastlinedefined)
    entry.sites[site] = true
    if context then entry.contexts[context] = true end
    return key
end

return Closures
