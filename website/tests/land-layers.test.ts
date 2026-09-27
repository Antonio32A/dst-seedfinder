import { describe, expect, it } from "vitest";
import { landLayers } from "../lib/world-map/land-layers";

const VOID = 0;
const LOW = 1;
const HIGH = 2;
const LEVEL_WITH_HIGH = 3;
const RANKS = new Map([[LOW, 10], [HIGH, 20], [LEVEL_WITH_HIGH, 20]]);
const rankOf = (tile: number) => RANKS.get(tile);

const grid = (rows: number[][]) =>
        ({ width: rows[0].length, height: rows.length, tiles: new Uint16Array(rows.flat()) });

const quads = (interleaved: Uint16Array) => Array.from({ length: interleaved.length / 3 }, (_, index) =>
        [...interleaved.subarray(3 * index, 3 * index + 3)]);

const SIDE_OFFSETS = [[0, -1], [1, 0], [0, 1], [-1, 0]];
const CORNER_OFFSETS = [[1, -1], [1, 1], [-1, 1], [-1, -1]];

const cellBetween = (sides: number, corners: number) => {
    const rows = [[VOID, VOID, VOID], [VOID, VOID, VOID], [VOID, VOID, VOID]];
    const place = (offsets: number[][], bits: number) => offsets.forEach(([dx, dz], bit) => {
        if (bits & (1 << bit)) rows[1 + dz][1 + dx] = LOW;
    });
    place(SIDE_OFFSETS, sides);
    place(CORNER_OFFSETS, corners);
    const [layer] = landLayers(grid(rows), rankOf);
    return quads(layer.edges).find(([tx, tz]) => tx === 1 && tz === 1)?.[2];
};

const MIXED_CELLS: [sides: number, corners: number, cell: number][] = [
    [2, 4, 33], [4, 8, 34], [8, 1, 35], [1, 2, 36], [2, 12, 37], [4, 9, 38], [8, 3, 39], [1, 6, 40],
    [2, 8, 41], [4, 1, 42], [8, 2, 43], [1, 4, 44], [3, 4, 45], [6, 8, 46], [9, 2, 47], [12, 1, 48]
];

const MASKS = Array.from({ length: 15 }, (_, index) => index + 1);
const COVERED_CORNERS = [[1, 15, 40], [3, 15, 45], [5, 15, 6], [15, 15, 16]];

describe("the land layers", () => {
    it("fills a lone tile with cell 01 and bleeds onto its eight neighbours", () => {
        const [layer, ...rest] = landLayers(grid([[VOID, VOID, VOID], [VOID, LOW, VOID], [VOID, VOID, VOID]]), rankOf);
        expect(rest).toEqual([]);
        expect(layer.tile).toBe(LOW);
        expect(quads(layer.fills)).toEqual([[1, 1, 1]]);
        expect(quads(layer.edges)).toEqual(expect.arrayContaining([
            [1, 0, 5], [2, 1, 9], [1, 2, 2], [0, 1, 3],
            [0, 0, 19], [2, 0, 21], [2, 2, 25], [0, 2, 18]
        ]));
        expect(layer.edges).toHaveLength(8 * 3);
    });

    it("drops the corners of a 2×2 block that its sides already cover", () => {
        const [layer] = landLayers(grid([
            [VOID, VOID, VOID, VOID],
            [VOID, LOW, LOW, VOID],
            [VOID, LOW, LOW, VOID],
            [VOID, VOID, VOID, VOID]
        ]), rankOf);
        expect(quads(layer.fills)).toEqual([[1, 1, 1], [2, 1, 1], [1, 2, 1], [2, 2, 1]]);
        expect(quads(layer.edges)).toEqual([
            [0, 0, 19], [1, 0, 5], [2, 0, 5], [3, 0, 21],
            [0, 1, 3], [3, 1, 9],
            [0, 2, 3], [3, 2, 9],
            [0, 3, 18], [1, 3, 2], [2, 3, 2], [3, 3, 25]
        ]);
    });

    it.each(MASKS)("draws cell 1 + S on a tile bordered on sides S = %i", (sides) => {
        expect(cellBetween(sides, 0)).toBe(1 + sides);
    });

    it.each(MASKS)("draws cell 17 + C on a tile touched at corners C = %i", (corners) => {
        expect(cellBetween(0, corners)).toBe(17 + corners);
    });

    it.each(MIXED_CELLS)("draws a side and the corners it doesn't touch, S = %i and C = %i, as cell %i", (sides, corners, cell) => {
        expect(cellBetween(sides, corners)).toBe(cell);
    });

    it.each(COVERED_CORNERS)("ignores the corners next to a bordered side, S = %i and C = %i", (sides, corners, cell) => {
        expect(cellBetween(sides, corners)).toBe(cell);
    });

    it("stacks the layers bottom to top by rank, and only bleeds a layer onto lower ranked tiles", () => {
        const layers = landLayers(grid([[HIGH, LOW, VOID]]), rankOf);
        expect(layers.map(({ tile }) => tile)).toEqual([LOW, HIGH]);
        const [low, high] = layers;
        expect(quads(low.edges)).toEqual([[2, 0, 9]]);
        expect(quads(high.edges)).toEqual([[1, 0, 9]]);
    });

    it("bleeds neither of two equally ranked layers onto the other", () => {
        const layers = landLayers(grid([[LEVEL_WITH_HIGH, HIGH]]), rankOf);
        expect(layers.map(({ tile }) => tile)).toEqual([HIGH, LEVEL_WITH_HIGH]);
        for (const layer of layers) expect(layer.edges).toEqual(new Uint16Array());
    });
});
