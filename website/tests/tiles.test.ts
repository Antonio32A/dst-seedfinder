import { describe, expect, it } from "vitest";
import { TILES } from "../lib/catalog/world";

const luminance = (name: string) => {
    const [r, g, b] = TILES[name].color;
    return 0.299 * r + 0.587 * g + 0.114 * b;
};

describe("the tile table", () => {
    it("gives every tile a minimap colour", () => {
        for (const tile of Object.values(TILES)) {
            expect(tile.color).toHaveLength(3);
            for (const channel of tile.color) expect(Number.isInteger(channel) && channel >= 0 && channel <= 255).toBe(true);
        }
    });

    it("draws grass green and desert sandy", () => {
        const [grassRed, grassGreen, grassBlue] = TILES.GRASS.color;
        expect(grassGreen).toBeGreaterThan(Math.max(grassRed, grassBlue));
        const [desertRed, desertGreen, desertBlue] = TILES.DESERT_DIRT.color;
        expect(desertRed).toBeGreaterThanOrEqual(desertGreen);
        expect(desertGreen).toBeGreaterThan(desertBlue);
    });

    it("darkens the ocean from the shore out to the hazardous sea", () => {
        const depths = ["OCEAN_COASTAL_SHORE", "OCEAN_COASTAL", "OCEAN_SWELL", "OCEAN_ROUGH", "OCEAN_HAZARDOUS"];
        for (const name of depths) expect(TILES[name].color[2]).toBeGreaterThan(TILES[name].color[0]);
        const brightness = depths.map(luminance);
        expect(brightness).toEqual([...brightness].sort((a, b) => b - a));
    });

    it("draws the open sea in the game's own minimap colours, not its noise texture", () => {
        expect(TILES.OCEAN_COASTAL.color).toEqual([23, 51, 62]);
        expect(TILES.OCEAN_SWELL.color).toEqual([14, 34, 61]);
        expect(TILES.OCEAN_ROUGH.color).toEqual([19, 20, 40]);
        expect(TILES.OCEAN_HAZARDOUS.color).toEqual([8, 8, 14]);
    });

    it("draws impassable ground in the paper colour", () => {
        const [red, green, blue] = TILES.IMPASSABLE.color;
        expect([green, blue]).toEqual([red, red]);
        expect(TILES.IMPASSABLE.kind).toBe("impassable");
    });
});
