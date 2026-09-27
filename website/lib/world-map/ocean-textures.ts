import type { LandTiles } from "./land-layers";
import type { Size } from "./map-view";

const CHANNELS = 4;
const OPAQUE = 255;
const DEFAULT_MINIMAP_COLOUR = [23, 51, 62] as const;
const COLOUR_BLUR: OceanBlur = { rgb: { radius: 2, passes: 6 }, alpha: { radius: 1, passes: 2 } };
const MASK_BLUR: OceanBlur = { rgb: { radius: 0, passes: 0 }, alpha: { radius: 2, passes: 8 } };

/** What a tile is to the ocean: the void, land, or ocean of a minimap colour. */
export type OceanSurface = "void" | "land" | readonly [red: number, green: number, blue: number];

/** The two textures the game's minimapocean shader reads, one RGBA texel per tile, row-major like the tiles. */
export interface OceanTextures {
    colour: Uint8Array;
    mask: Uint8Array;
}

/** A box blur the engine repeats `passes` times, each over the (2·radius+1)² window around a texel. */
export interface BoxBlur {
    radius: number;
    passes: number;
}

/** The engine's two blur phases: first over rgb, then over alpha. */
export interface OceanBlur {
    rgb: BoxBlur;
    alpha: BoxBlur;
}

const inWindow = (at: number, length: number, radius: number) =>
    Math.min(length, at + radius + 1) - Math.max(0, at - radius);

function boxMeans(texels: Uint8Array, channel: number, { width, height }: Size, radius: number) {
    const rowSums = new Uint32Array(width * height);
    for (let z = 0; z < height; z++) {
        const row = z * width;
        let sum = 0;
        for (let x = 0; x < Math.min(radius, width); x++) sum += texels[(row + x) * CHANNELS + channel];
        for (let x = 0; x < width; x++) {
            if (x + radius < width) sum += texels[(row + x + radius) * CHANNELS + channel];
            rowSums[row + x] = sum;
            if (x - radius >= 0) sum -= texels[(row + x - radius) * CHANNELS + channel];
        }
    }
    const across = Uint32Array.from({ length: width }, (_, x) => inWindow(x, width, radius));
    const columnSums = new Uint32Array(width);
    for (let z = 0; z < Math.min(radius, height); z++) {
        for (let x = 0; x < width; x++) columnSums[x] += rowSums[z * width + x];
    }
    const means = new Uint8Array(width * height);
    for (let z = 0; z < height; z++) {
        const [entering, leaving, down] = [(z + radius) * width, (z - radius) * width, inWindow(z, height, radius)];
        if (z + radius < height) for (let x = 0; x < width; x++) columnSums[x] += rowSums[entering + x];
        for (let x = 0; x < width; x++) means[z * width + x] = columnSums[x] / (across[x] * down);
        if (z - radius >= 0) for (let x = 0; x < width; x++) columnSums[x] -= rowSums[leaving + x];
    }
    return means;
}

/**
 * Blurs an RGBA ocean texture the way the game's OceanRenderer does on the CPU. Each pass replaces every texel whose
 * `blurred` byte is set with the truncated mean of the window around it that lies inside the texture, reading only the
 * previous pass; the other texels keep their value but still count in their neighbours' means.
 */
export function blurOcean(texels: Uint8Array, blurred: Uint8Array, size: Size, blur: OceanBlur): Uint8Array {
    const { width, height } = size;
    const rows = Array.from({ length: height }, (_, z) => [z * width, z * width + width - 1]);
    const border = [...Array(width).keys()].flatMap((x) => [x, (height - 1) * width + x]).concat(rows.flat());
    const phase = (start: Uint8Array, { radius, passes }: BoxBlur, channels: number[], opaque: number[]) => {
        let current = start;
        for (let pass = 0; pass < passes; pass++) {
            const next = current.slice();
            for (const channel of channels) {
                const means = boxMeans(current, channel, size, radius);
                for (let at = 0; at < blurred.length; at++) {
                    if (blurred[at]) next[at * CHANNELS + channel] = means[at];
                }
            }
            for (const at of opaque) {
                if (blurred[at]) next[at * CHANNELS + 3] = OPAQUE;
            }
            current = next;
        }
        return current;
    };
    return phase(phase(texels, blur.rgb, [0, 1, 2], []), blur.alpha, [3], border);
}

/**
 * The game's minimap ocean textures of a world, as a client that joined it sees them. The void is opaque black, land
 * is the default minimap colour and ocean its tile's minimap colour, both transparent; then the void and the ocean are
 * blurred, the colour lightly and the mask, whose alpha is all the shader reads, much wider. Land is never blurred.
 */
export function oceanTextures(land: LandTiles, surfaceOf: (tile: number) => OceanSurface): OceanTextures {
    const surfaces: OceanSurface[] = [];
    for (const tile of new Set(land.tiles)) surfaces[tile] = surfaceOf(tile);
    const source = new Uint8Array(land.tiles.length * CHANNELS);
    const blurred = new Uint8Array(land.tiles.length);
    land.tiles.forEach((tile, at) => {
        const surface = surfaces[tile];
        blurred[at] = surface === "land" ? 0 : 1;
        if (surface === "void") source[at * CHANNELS + 3] = OPAQUE;
        else source.set(surface === "land" ? DEFAULT_MINIMAP_COLOUR : surface, at * CHANNELS);
    });
    return {
        colour: blurOcean(source, blurred, land, COLOUR_BLUR),
        mask: blurOcean(source, blurred, land, MASK_BLUR)
    };
}
