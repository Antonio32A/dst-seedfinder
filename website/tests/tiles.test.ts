import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { LAND_TILES, TILES } from "../lib/catalog/world";

const PUBLIC = fileURLToPath(new URL("../public", import.meta.url));

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

    it("colours land the way the game's map draws it at full brightness", () => {
        const drawn: Record<string, [number, number, number]> = {
            GRASS: [174, 168, 66], FOREST: [102, 110, 55], SAVANNA: [193, 145, 54], DESERT_DIRT: [199, 163, 84],
        };
        for (const [name, colour] of Object.entries(drawn)) {
            const error = TILES[name].color.map((channel, index) => Math.abs(channel - colour[index]));
            expect(Math.max(...error)).toBeLessThanOrEqual(3);
        }
    });

    it("gives every land tile of the default worlds a minimap noise texture the site serves", () => {
        for (const { name } of LAND_TILES.filter((tile) => tile.inDefaultWorlds)) {
            const noise = TILES[name].minimapNoise ?? "";
            expect(noise).toMatch(/^\/world-map\/noise\/\w+\.png$/);
            expect(existsSync(join(PUBLIC, noise))).toBe(true);
        }
    });

    it("stacks the land layers in the game's minimap order, without the ocean or impassable ground", () => {
        const bottomToTop = ["ROAD", "MARSH", "ROCKY", "SAVANNA", "FOREST", "GRASS", "DIRT", "DECIDUOUS", "METEOR"];
        const ranks = bottomToTop.map((name) => TILES[name].minimapRank ?? NaN);
        expect(ranks).toEqual([...ranks].sort((a, b) => a - b));
        expect(new Set(ranks).size).toBe(ranks.length);
        expect(TILES.OCEAN_SWELL.minimapRank).toBeUndefined();
        expect(TILES.IMPASSABLE.minimapRank).toBeUndefined();
    });

    it("gives the ocean tiles their own minimap colours for the ocean pass", () => {
        expect(TILES.OCEAN_SWELL.oceanMinimapColor).toEqual([14, 34, 61]);
        expect(TILES.OCEAN_COASTAL_SHORE.oceanMinimapColor).toEqual([23, 51, 62]);
        expect(TILES.GRASS.oceanMinimapColor).toBeUndefined();
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
