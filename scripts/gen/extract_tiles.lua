-- Extracts what the C++ tile stages read from the Lua side (lane G): the TileGroupManager ranges and special tiles
-- (worldsim LoadTileGroups), the tiles forest_map.Generate passes to ForceConnectivity/DrawRoads and
-- ValidateGroundTile returns, and ROAD_PARAMETERS as the floats SetRoadParameters stores.
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_tiles.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")

local function ranges(prefix)
    return BOOT.array({
        { _G["LEGACY_WORLD_TILES_" .. prefix .. "_START"], _G["LEGACY_WORLD_TILES_" .. prefix .. "_END"] },
        { _G["WORLD_TILES_" .. prefix .. "_START"], _G["WORLD_TILES_" .. prefix .. "_END"] },
    })
end

BOOT.write_json({
    land = ranges("LAND"),
    ocean = ranges("OCEAN"),
    impassable = ranges("IMPASSABLE"),
    noise = ranges("NOISE"),
    tiles = {
        impassable = WORLD_TILES.IMPASSABLE, invalid = WORLD_TILES.INVALID, fake_ground = WORLD_TILES.FAKE_GROUND,
        dirt = WORLD_TILES.DIRT, rocky = WORLD_TILES.ROCKY, road = WORLD_TILES.ROAD,
    },
    roads = {
        subdivisions = ROAD_PARAMETERS.NUM_SUBDIVISIONS_PER_SEGMENT,
        min_width = ROAD_PARAMETERS.MIN_WIDTH, max_width = ROAD_PARAMETERS.MAX_WIDTH,
        min_edge_width = ROAD_PARAMETERS.MIN_EDGE_WIDTH, max_edge_width = ROAD_PARAMETERS.MAX_EDGE_WIDTH,
        width_jitter_scale = ROAD_PARAMETERS.WIDTH_JITTER_SCALE,
    },
})
