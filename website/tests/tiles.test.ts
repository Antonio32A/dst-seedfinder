import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { LAND_TILES, TILES } from "@/lib/catalog/world";

const PUBLIC = fileURLToPath(new URL("../public", import.meta.url));

describe("the tile table", () => {
    it("gives every tile a minimap colour", () => {
        for (const tile of Object.values(TILES)) {
            expect(tile.color).toHaveLength(3);
            for (const channel of tile.color) expect(Number.isInteger(channel) && channel >= 0 && channel <= 255).toBe(true);
        }
    });

    it("gives every land tile of the default worlds a minimap noise texture the site serves", () => {
        for (const { name } of LAND_TILES.filter((tile) => tile.inDefaultWorlds)) {
            const noise = TILES[name].minimapNoise ?? "";
            expect(noise).toMatch(/^\/world-map\/noise\/.+\.png$/);
            expect(existsSync(join(PUBLIC, noise))).toBe(true);
        }
    });

    it("gives only ocean tiles an ocean minimap colour, and no ocean tile a land layer", () => {
        for (const tile of Object.values(TILES)) {
            if (tile.oceanMinimapColor !== undefined) expect(tile.kind).toBe("ocean");
            if (tile.kind === "ocean") expect(tile.minimapRank).toBeUndefined();
        }
    });
});
