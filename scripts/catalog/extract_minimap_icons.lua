-- Runs each prefab constructor as the master simulation under harness stubs and prints, as JSON, the icon, priority and
-- draw-over-fog flag its MiniMapEntity was last given.
local HERE = arg[0]:match("^(.*)/[^/]*$") or "."
local GS = HERE .. "/../../build/deps/game-scripts"
package.path = GS .. "/?.lua;" .. package.path
print = function() end

local sink
sink = setmetatable({}, {
    __index = function(t, k)
        if type(k) == "string" and (k:match("Position$") or k:match("Pos$") or k:match("Scale$") or k:match("Rotation$")) then return function() return 0, 0, 0 end end
        if k == "GetMass" then return function() return 0 end end
        return sink
    end,
    __call = function() return sink end,
    __add = function() return 0 end, __sub = function() return 0 end, __mul = function() return 0 end,
    __div = function() return 0 end, __lt = function() return false end, __le = function() return false end,
    __concat = function(a, b) return "" end, __unm = function() return 0 end,
})

for _, n in ipairs{"min", "max", "floor", "ceil", "random", "sqrt", "abs", "sin", "cos", "atan2", "fmod", "pow"} do
    local f = math[n]
    math[n] = function(...)
        local a = {...}
        for i = 1, select("#", ...) do if type(a[i]) ~= "number" then a[i] = 1 end end
        return f(unpack(a))
    end
end
function kleifileexists() return true end
function getrealtime() return 0 end
function kleiloadlua(f) return loadfile(GS .. "/" .. f:gsub("^scripts/", "")) end
function toarray(...) return {...} end
MODS_ROOT = "../mods/"; PLATFORM = "LINUX_STEAM"; IS_STEAM_DECK = false; APP_VERSION = "X"; BRANCH = "release"
CONFIGURATION = "PRODUCTION"; DIST_PLATFORM = "Steam"; ENCODE_SAVES = false; CAN_USE_DBUI = false; MODS_ENABLED = false
function utf8char(c) return string.char(c % 256) end
function utf8substr(s,i,j) return string.sub(s,i,j) end
function utf8strlen(s) return #s end
function utf8strtoupper(s) return s:upper() end
function utf8strtolower(s) return s:lower() end
function walltime() return 0 end
function kleiregistermods() end
TheSim = setmetatable({}, {__index = function(t,k)
    if k:match("^Find") and k ~= "FindFirstEntityWithTag" then return function() return {} end end
    return function() return sink end
end})
TheInput = sink; TheFrontEnd = sink; TheCamera = sink; ThePlayer = nil
TheShard = sink; Profile = sink; TheMixer = sink; TheGenericKV = sink; TheInventory = sink
ProfileStatsSet = function() end
AwardPlayerAchievement = function() end
softresolvefilepath = function(f) return f end
resolvefilepath = function(f) return f end
local ntg = 0
TileGroupManager = setmetatable({}, {__index = setmetatable({AddTileGroup = function() ntg = ntg + 1 return ntg end}, {__index = function() return function() end end})})
Entity = sink
function hash(s) local h = 5381 for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end return h end
bit = {
    band = function(a, b) local r, p = 0, 1 a = a % 4294967296 b = b % 4294967296 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a = math.floor(a / 2) b = math.floor(b / 2) p = p * 2 end return r end,
    bor = function(a, b) local r, p = 0, 1 a = a % 4294967296 b = b % 4294967296 while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then r = r + p end a = math.floor(a / 2) b = math.floor(b / 2) p = p * 2 end return r end,
    lshift = function(a, n) return (a * 2 ^ n) % 4294967296 end,
    rshift = function(a, n) return math.floor((a % 4294967296) / 2 ^ n) end,
    bnot = function(a) return 4294967295 - (a % 4294967296) end,
}
bit.bxor = function(a, b) return bit.band(bit.bor(a, b), bit.bnot(bit.band(a, b))) end
MapLayerManager = sink
Ents = {}; NumEnts = 0
ModManager = setmetatable({}, {__index = function() return function() return {} end end})
ModUtil = sink

function global() end
function IsConsole() return false end
function IsNotConsole() return true end
function IsPS4() return false end
function IsPS5() return false end
function IsPSN() return false end
function IsXB1() return false end
function IsSteam() return true end
function IsWin32() return false end
function IsLinux() return true end
function IsRail() return false end
function IsSteamDeck() return false end
function ValidateLineNumber() end
MAIN = 1
CHEATS_ENABLED = false
package.assetpath = {}
for _, m in ipairs{"debugprint","config","vector3","mainfunctions","preloadsounds","json","tuning","strings","stringutil","constants","class","util","vecutil","vec3util","datagrid","ocean_util","actions","debugtools","simutil","scheduler","stategraph","behaviourtree","prefabs","tiledefs","tilegroups","prefabskin","entityscript","entityreplica","recipes","brain","standardcomponents","mathutil","math2d","componentutil","prefablist"} do
    local ok, e = pcall(require, m)
    if not ok then io.stderr:write("REQFAIL ", m, " ", tostring(e), "\n") end
end
require("equipslotutil").Initialize()
for _, n in ipairs{"DoTaskInTime", "DoStaticTaskInTime", "DoPeriodicTask", "DoStaticPeriodicTask", "ListenForEvent", "RemoveEventCallback", "WatchWorldState", "StopWatchingWorldState", "StartUpdatingComponent", "StopUpdatingComponent"} do
    EntityScript[n] = function() return sink end
end
setmetatable(_G, {__index = function(t, k)
    if type(k) == "string" and k:match("^net_") then return function() return setmetatable({}, {__index = function(_, m) return function() return 0 end end}) end end
    if k == "num_updating_ents" then return 0 end
    if type(k) == "string" and k:match("^[A-Za-z_]") and not k:match("^__") then return sink end
    return nil
end})

local function new_recorder()
    local state = {enabled = true}
    local setters = {SetIcon = "icon", SetPriority = "priority", SetDrawOverFogOfWar = "over_fog", SetEnabled = "enabled"}
    return setmetatable({}, {__index = function(t, k)
        if k == "__state" then return state end
        return function(self, ...)
            if setters[k] then state[setters[k]] = ... end
            return sink
        end
    end})
end

function GetTime() return 0 end
function GetTick() return 0 end
function GetStaticTime() return 0 end
TheWorld = setmetatable({ismastersim = true, has_ocean = true, Map = sink, Pathfinder = sink}, {__index = function(t, k)
    if k == "state" then return setmetatable({}, {__index = function() return false end}) end
    if k == "components" then return setmetatable({}, {__index = function() return sink end}) end
    return function() return sink end
end})
TheNet = setmetatable({}, {__index = function(t,k) return function() return false end end})
TheNet.GetIsMasterSimulation = function() return true end
TheNet.GetServerGameMode = function() return "survival" end

function SpawnPrefab() return sink end
local cur
function CreateEntity(name)
    local ent = {}
    local scr
    ent.GetGUID = function() NumEnts = NumEnts + 1; return NumEnts end
    local tags = {}
    ent.AddTag = function(self, t) tags[t] = true end
    ent.RemoveTag = function(self, t) tags[t] = nil end
    ent.HasTag = function(self, t) return tags[t] == true end
    ent.HasTags = function(self, ...) local a = {...} if type(a[1]) == "table" then a = a[1] end for _, t in ipairs(a) do if not tags[t] then return false end end return true end
    ent.HasOneOfTags = function(self, ...) local a = {...} if type(a[1]) == "table" then a = a[1] end for _, t in ipairs(a) do if tags[t] then return true end end return false end
    ent.GetDebugString = function() return "" end
    setmetatable(ent, {__index = function(t, k)
        local adder = tostring(k):match("^Add(.+)$")
        if adder then
            return function(self)
                if adder == "MiniMapEntity" then
                    local mm = new_recorder(); scr.MiniMapEntity = mm; if cur.primary == scr then cur.mm = mm end
                    return mm
                end
                scr[adder] = sink
                return sink
            end
        end
        return function() return sink end
    end})
    scr = EntityScript(ent)
    if not cur.primary then cur.primary = scr end
    Ents[scr.GUID] = scr
    return scr
end

local function quoted(text)
    assert(text:match("^[%w_.]+$"), "unexpected icon name " .. text)
    return '"' .. text .. '"'
end

local results = {}
for _, file in ipairs(PREFABFILES) do
    local fn = loadfile(GS .. "/prefabs/" .. file .. ".lua")
    local loaded, prefabs = pcall(function() return {fn()} end)
    if not loaded then io.stderr:write("RUNFAIL ", file, " ", tostring(prefabs), "\n") else
        for _, prefab in ipairs(prefabs) do
            if type(prefab) == "table" and prefab.name and prefab.fn then
                cur = {}
                local complete = xpcall(prefab.fn, function(message) return message end)
                local state = cur.mm and cur.mm.__state
                if state and state.enabled ~= false and type(state.icon) == "string" and state.icon ~= "" then
                    results[prefab.name] = {icon = state.icon, priority = state.priority, over_fog = state.over_fog, complete = complete}
                end
            end
        end
    end
end

local names = {}
for name in pairs(results) do names[#names + 1] = name end
table.sort(names)
local rows = {}
for _, name in ipairs(names) do
    local row = results[name]
    local fields = {'"icon":' .. quoted(row.icon)}
    if type(row.priority) == "number" and row.priority ~= 0 then fields[#fields + 1] = '"priority":' .. string.format("%d", row.priority) end
    if row.over_fog == true then fields[#fields + 1] = '"over_fog":true' end
    if not row.complete then fields[#fields + 1] = '"incomplete":true' end
    rows[#rows + 1] = '  ' .. quoted(name) .. ': {' .. table.concat(fields, ", ") .. '}'
end
io.write("{\n", table.concat(rows, ",\n"), "\n}\n")
