-- Extracts the few game facts storygen needs beyond story.json: which tile values TileGroupManager:IsImpassableTile
-- accepts (InsertAdditionalSetPieces' isnt_blank; the values below 1024 and the range above the ocean tiles), and the map tag each room tag resolves to.
-- usage: scripts/harness/bin/lua-dst scripts/gen/extract_storygen.lua

local GEN = arg[0]:match("^(.*)/[^/]*$") or "."
local BOOT = dofile(GEN .. "/lib/boot.lua")

local impassable = BOOT.array()
for tile = 0, 1023 do
    if TileGroupManager:IsImpassableTile(tile) then
        impassable[#impassable + 1] = tile
    end
end

BOOT.write_json({ impassable_below_1024 = impassable, impassable_value = WORLD_TILES.IMPASSABLE,
    impassable_range_first = WORLD_TILES_IMPASSABLE_START, impassable_range_last = WORLD_TILES_IMPASSABLE_END })
