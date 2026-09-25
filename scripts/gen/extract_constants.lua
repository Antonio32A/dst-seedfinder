-- Extracts the placement circle position lists for every CIRCLE_EDGE / CIRCLE_RANDOM layout count reachable on the
-- default forest path, by calling the game's own placement.posfnCircEdge and placement.posfnCirc (whose Randomize
-- shuffle is neutralised with math.random(i) = i, so the lists come out in generation order; the port draws the
-- shuffle itself). Values are sin/cos/sqrt of constants under the host libm.
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_constants.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")
local array = BOOT.array
require("map/placement")

local function hex(x)
    return BOOT.tl.f64_bits(x)
end

local counts = {}
local obj_layout = require("map/object_layout")
local names = assert(loadfile(GEN .. "/lib/reach.lua"))(BOOT).layout_names()
for state = 0, 7 do
    BOOT.set_swaps(state)
    for _, name in ipairs(names) do
        local layout = obj_layout.LayoutForDefinition(name)
        if layout.type == LAYOUT.CIRCLE_EDGE or layout.type == LAYOUT.CIRCLE_RANDOM then
            local total = 0
            for _, v in pairs(layout.count or {}) do
                assert(type(v) == "number", "non-constant circle count in " .. name)
                total = total + v
            end
            counts[layout.type .. ":" .. total] = { kind = layout.type, count = total }
        end
    end
end

local function positions(fn, n)
    local raw = math.random
    math.random = function(i) return i end
    local list = fn(n)
    math.random = raw
    local out = array()
    for _, p in ipairs(list) do out[#out + 1] = { hex(p.x), hex(p.y) } end
    return out
end

local circles = array()
for _, key in ipairs(BOOT.sorted_keys(counts)) do
    local c = counts[key]
    local fn = c.kind == LAYOUT.CIRCLE_EDGE and placement.posfnCircEdge or placement.posfnCirc
    circles[#circles + 1] = { kind = c.kind, count = c.count, positions = positions(fn, c.count) }
end

BOOT.write_json({ circles = circles })
