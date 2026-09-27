import { describe, expect, it } from "vitest";
import { blurOcean, oceanTextures, type OceanSurface } from "../lib/world-map/ocean-textures";

const NONE = { radius: 0, passes: 0 };
const VOID = 0;
const LAND = 1;
const SWELL = 2;
const SWELL_COLOUR = [14, 34, 61] as const;
const surfaceOf = (tile: number): OceanSurface => (tile === LAND ? "land" : tile === SWELL ? SWELL_COLOUR : "void");

const world = (width: number, height: number, tileAt: (tx: number, tz: number) => number) => ({
    width,
    height,
    tiles: Uint16Array.from({ length: width * height }, (_, at) => tileAt(at % width, Math.floor(at / width)))
});

const texel = (texels: Uint8Array, width: number, tx: number, tz: number) =>
        [...texels.subarray((tz * width + tx) * 4, (tz * width + tx) * 4 + 4)];

const image = (rows: number[][][]) => ({
    size: { width: rows[0].length, height: rows.length },
    texels: new Uint8Array(rows.flat(2))
});

const channel = (texels: Uint8Array, index: number) => [...texels].filter((_, at) => at % 4 === index);

describe("the ocean blur", () => {
    it("replaces each blurred texel's colour with the truncated mean of the window inside the texture", () => {
        const { size, texels } = image([[[10, 0, 0, 0], [20, 0, 0, 0]], [[30, 0, 0, 0], [41, 0, 0, 0]]]);
        const blurred = blurOcean(texels, new Uint8Array(4).fill(1), size, { rgb: { radius: 1, passes: 1 }, alpha: NONE });
        expect(channel(blurred, 0)).toEqual([25, 25, 25, 25]);
    });

    it("keeps the texels that aren't blurred, which still count in their neighbours' means", () => {
        const { size, texels } = image([[[0, 3, 0, 7], [90, 60, 30, 7], [255, 255, 255, 7]]]);
        const blurred = blurOcean(texels, new Uint8Array([0, 1, 0]), size, { rgb: { radius: 1, passes: 1 }, alpha: NONE });
        expect([...blurred]).toEqual([0, 3, 0, 7, 115, 106, 95, 7, 255, 255, 255, 7]);
    });

    it("reads only the previous pass, so each pass spreads the colour one more window", () => {
        const { size, texels } = image([[[0, 0, 0, 0], [0, 0, 0, 0], [255, 0, 0, 0]]]);
        const blurred = blurOcean(texels, new Uint8Array(3).fill(1), size, { rgb: { radius: 1, passes: 2 }, alpha: NONE });
        expect(channel(blurred, 0)).toEqual([42, 70, 106]);
    });

    it("then blurs alpha on its own, holding the blurred texels on the texture's border opaque", () => {
        const rows = Array.from({ length: 3 }, () => Array.from({ length: 3 }, () => [9, 9, 9, 0]));
        rows[1][1] = [200, 100, 50, 0];
        const { size, texels } = image(rows);
        const blurred = blurOcean(texels, new Uint8Array(9).fill(1), size, { rgb: NONE, alpha: { radius: 1, passes: 2 } });
        expect(channel(blurred, 3)).toEqual([255, 255, 255, 255, 226, 255, 255, 255, 255]);
        expect([...blurred.subarray(16, 19)]).toEqual([200, 100, 50]);
    });
});

describe("the ocean textures", () => {
    it("leave land the game's default minimap colour, transparent", () => {
        const { colour, mask } = oceanTextures(world(9, 9, (tx) => (tx < 3 ? VOID : tx < 6 ? LAND : SWELL)), surfaceOf);
        expect(texel(colour, 9, 4, 4)).toEqual([23, 51, 62, 0]);
        expect(texel(mask, 9, 4, 4)[3]).toBe(0);
    });

    it("turn the void opaque black", () => {
        const { colour, mask } = oceanTextures(world(5, 5, () => VOID), surfaceOf);
        expect(texel(colour, 5, 2, 2)).toEqual([0, 0, 0, 255]);
        expect(texel(mask, 5, 2, 2)[3]).toBe(255);
    });

    it("give open ocean its tile's colour, clear", () => {
        const { colour, mask } = oceanTextures(world(40, 40, () => SWELL), surfaceOf);
        expect(texel(colour, 40, 20, 20)).toEqual([...SWELL_COLOUR, 0]);
        expect(texel(mask, 40, 20, 20)[3]).toBe(0);
    });

    it("spread the void further into the mask than into the colour", () => {
        const { colour, mask } = oceanTextures(world(40, 40, (tx) => (tx < 10 ? VOID : SWELL)), surfaceOf);
        expect(texel(colour, 40, 14, 20)[3]).toBe(0);
        expect(texel(mask, 40, 14, 20)[3]).toBeGreaterThan(0);
    });
});
