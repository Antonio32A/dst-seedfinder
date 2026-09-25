-- Minimal engine environment for running DST worldgen Lua outside the game.
-- Every stub here is RNG-neutral: none of them call math.random.

local SCRIPTS_DIR = assert(HARNESS_SCRIPTS_DIR, "HARNESS_SCRIPTS_DIR must be set")

local function readable(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

HARNESS_LOAD_HOOKS = HARNESS_LOAD_HOOKS or {}

function kleiloadlua(filename)
    local rel = filename:gsub("\\", "/"):gsub("^scripts/", "")
    local path = SCRIPTS_DIR .. "/" .. rel
    if not readable(path) then
        return nil
    end
    local fn, err = loadfile(path)
    if not fn then
        error(err)
    end
    local modname = rel:gsub("%.lua$", "")
    local hook = HARNESS_LOAD_HOOKS[modname]
    if hook then
        return function(...)
            return hook(fn(...))
        end
    end
    return fn
end

local function noop() end
local function sink_object(name, overrides)
    return setmetatable(overrides or {}, {
        __index = function(t, k)
            return noop
        end,
    })
end

MODS_ROOT = "../mods/"
PLATFORM = "LINUX_STEAM"
IS_STEAM_DECK = false
APP_VERSION = "HARNESS"
BRANCH = "release"
CONFIGURATION = "PRODUCTION"
DIST_PLATFORM = "Steam"
ENCODE_SAVES = false
CAN_USE_DBUI = false
MODS_ENABLED = true

function getrealtime() return 0 end

WorldSim = sink_object("WorldSim", {
    LuaPrint = function(self, ...)
        if HARNESS_VERBOSE then io.stderr:write(table.concat({ ... }, "\t"), "\n") end
    end,
    GenerateSessionIdentifier = function() return "HARNESS" end,
})

TheSim = nil

HARNESS_PRINT = print
print = function(...)
    if HARNESS_VERBOSE then
        io.stderr:write(table.concat((function(...)
            local t = {}
            for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
            return t
        end)(...), "\t"), "\n")
    end
end

function utf8char(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end
    if code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end
function utf8substr(s, i, j) return string.sub(s, i, j) end
function utf8strlen(s) return #s end
function utf8strtoupper(s) return string.upper(s) end
function utf8strtolower(s) return string.lower(s) end

function toarray(...) return { ... } end
function kleifileexists() return true end

local function engine_object(methods)
    methods = setmetatable(methods or {}, { __index = function() return noop end })
    return setmetatable({}, { __index = methods })
end

local next_tile_group = 0
TileGroupManager = engine_object({
    AddTileGroup = function()
        next_tile_group = next_tile_group + 1
        return next_tile_group
    end,
})
function walltime() return 0 end
function kleiregistermods() end
