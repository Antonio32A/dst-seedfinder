import { TILES } from "@/lib/catalog/world";

const PAPER = TILES.IMPASSABLE.color;

/**
 * RGBA bytes per tile id, from id 0 up to the highest id the world names or uses, in the catalog's minimap colours.
 * Tiles the catalog doesn't know get the minimap paper colour.
 */
export function tilePalette(tileNames: ReadonlyMap<number, string>, tiles: Uint16Array): Uint8Array {
    const size = Math.max(...tileNames.keys(), tiles.reduce((highest, id) => Math.max(highest, id), 0)) + 1;
    const palette = new Uint8Array(4 * size);
    for (let id = 0; id < size; id++) {
        const name = tileNames.get(id) ?? "";
        palette.set([...(Object.hasOwn(TILES, name) ? TILES[name].color : PAPER), 255], 4 * id);
    }
    return palette;
}
