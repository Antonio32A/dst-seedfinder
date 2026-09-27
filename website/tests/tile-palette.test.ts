import { describe, expect, it } from "vitest";
import { TILES } from "../lib/catalog/world";
import { tilePalette } from "../lib/world-map/tile-palette";

const colourOf = (palette: Uint8Array, id: number) => [...palette.subarray(4 * id, 4 * id + 4)];

describe("the tile palette", () => {
    const names = new Map([[6, "GRASS"], [201, "OCEAN_COASTAL"], [3, "A_TILE_FROM_A_NEWER_GAME"]]);
    const palette = tilePalette(names, new Uint16Array([6, 201, 3, 250]));

    it("colours each tile id with its tile's minimap colour", () => {
        expect(colourOf(palette, 6)).toEqual([...TILES.GRASS.color, 255]);
        expect(colourOf(palette, 201)).toEqual([...TILES.OCEAN_COASTAL.color, 255]);
    });

    it("draws a tile the catalog doesn't know, or an unnamed id, in the paper colour", () => {
        const paper = [...TILES.IMPASSABLE.color, 255];
        expect(colourOf(palette, 3)).toEqual(paper);
        expect(colourOf(palette, 250)).toEqual(paper);
    });

    it("covers a whole world's worth of tiles", () => {
        const world = new Uint16Array(425 * 425).fill(6);
        world[world.length - 1] = 7;
        expect(tilePalette(new Map([[6, "GRASS"]]), world)).toHaveLength(4 * 8);
    });
});