import type { Size } from "@/lib/world-map/view/map-view";

const FILL_CELL = 1;
const SIDES = [[0, -1], [1, 0], [0, 1], [-1, 0]] as const;
const CORNERS = [[1, -1], [1, 1], [-1, 1], [-1, -1]] as const;
const CORNER_SIDES = [0b0011, 0b0110, 0b1100, 0b1001] as const;
const MIXED_CELLS: Record<number, Record<number, number>> = {
    1: { 2: 36, 4: 44, 6: 40 },
    2: { 4: 33, 8: 41, 12: 37 },
    3: { 4: 45 },
    4: { 1: 42, 8: 34, 9: 38 },
    6: { 8: 46 },
    8: { 1: 35, 2: 43, 3: 39 },
    9: { 2: 47 },
    12: { 1: 48 }
};

export interface LandTiles extends Size {
    /** Row-major tile ids, `tz * width + tx`. */
    tiles: Uint16Array;
}

export interface LandLayer {
    tile: number;
    /** Interleaved `tx, tz, cell` of the layer's own tiles, all map_edge cell 01. */
    fills: Uint16Array;
    /** Interleaved `tx, tz, cell` of the map_edge cells on the layer's lower ranked neighbours. */
    edges: Uint16Array;
}

/**
 * One layer per ranked tile id, bottom to top. A layer bleeds onto each tile it borders that is ranked below it or not
 * at all, with the cell for the sides it borders the tile on and the corners where it touches neither adjacent side.
 */
export function landLayers(land: LandTiles, rankOf: (tile: number) => number | undefined): LandLayer[] {
    const { width, height, tiles } = land;
    const outside = tiles.reduce((highest, tile) => Math.max(highest, tile), 0) + 1;
    const ranks = Float64Array.from({ length: outside + 1 }, (_, tile) =>
        (tile === outside ? undefined : rankOf(tile)) ?? -Infinity);
    const row = width + 2;
    const padded = new Uint32Array(row * (height + 2)).fill(outside);
    for (let tz = 0; tz < height; tz++) padded.set(tiles.subarray(tz * width, (tz + 1) * width), (tz + 1) * row + 1);
    const steps = (offsets: readonly (readonly [number, number])[]) => offsets.map(([dx, dz]) => dz * row + dx);
    const [sideSteps, cornerSteps] = [steps(SIDES), steps(CORNERS)];
    const neighbourSteps = [...sideSteps, ...cornerSteps];
    const fills = new Map<number, number[]>();
    const edges = new Map<number, number[]>();
    const quadsOf = (quads: Map<number, number[]>, tile: number) => quads.get(tile) ?? quads.set(tile, []).get(tile)!;
    const touches = (offsets: number[], at: number, tile: number) =>
        offsets.reduce((bits, step, bit) => bits | (padded[at + step] === tile ? 1 << bit : 0), 0);
    for (let tz = 0; tz < height; tz++) {
        for (let tx = 0; tx < width; tx++) {
            const at = (tz + 1) * row + tx + 1;
            const rank = ranks[padded[at]];
            if (rank !== -Infinity) quadsOf(fills, padded[at]).push(tx, tz, FILL_CELL);
            neighbourSteps.forEach((step, index) => {
                const neighbour = padded[at + step];
                const firstAbove = ranks[neighbour] > rank
                    && neighbourSteps.findIndex((earlier) => padded[at + earlier] === neighbour) === index;
                if (!firstAbove) return;
                const sides = touches(sideSteps, at, neighbour);
                const corners = CORNER_SIDES.reduce((bits, next, bit) =>
                    (sides & next ? bits & ~(1 << bit) : bits), touches(cornerSteps, at, neighbour));
                const cell = corners === 0 ? 1 + sides : sides === 0 ? 17 + corners : MIXED_CELLS[sides][corners];
                quadsOf(edges, neighbour).push(tx, tz, cell);
            });
        }
    }
    return [...fills.keys()].sort((a, b) => ranks[a] - ranks[b] || a - b).map((tile) => ({
        tile,
        fills: new Uint16Array(fills.get(tile)!),
        edges: new Uint16Array(edges.get(tile) ?? [])
    }));
}
