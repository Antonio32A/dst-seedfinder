import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { prefabName } from "@/lib/catalog/prefab-sets";
import type { LegendGroup } from "./prefab-visibility";
import type { GeneratedWorld, SetPieceSource } from "./world-dump";

/** The colour the map outlines set pieces in. */
export const SET_PIECE_COLOUR = [255, 100, 40] as const;

/** The set pieces a map shows when it opens: every one the set piece rules of `search` name, in any of its options. */
export const defaultShownSetPieces = (search?: SeedfinderConfig): Set<string> => new Set((search?.criteria ?? [])
    .flatMap(({ setpieces = [] }) => setpieces.flatMap(({ required = {} }) => Object.keys(required))));

/** How many times the world placed each layout, by its name, none when its dump doesn't say. */
export function setPieceCounts(world: Pick<GeneratedWorld, "setPieces">): Map<string, number> {
    const counts = new Map<string, number>();
    for (const { name } of world.setPieces ?? []) counts.set(name, (counts.get(name) ?? 0) + 1);
    return counts;
}

/**
 * The world's set pieces as a legend group, one entry per layout name, by name, with how many times the world placed
 * it. `null` when the world has none or its dump doesn't say.
 */
export function setPieceLegend(world: Pick<GeneratedWorld, "setPieces">): LegendGroup | null {
    const counts = setPieceCounts(world);
    if (counts.size === 0) return null;
    return {
        group: { id: "set pieces", name: "Set pieces", colour: SET_PIECE_COLOUR },
        count: world.setPieces!.length,
        prefabs: [...counts]
            .map(([name, count]) => ({ prefab: name, displayName: name, count }))
            .sort((a, b) => a.displayName.localeCompare(b.displayName))
    };
}

const SOURCE_WORDS: Record<SetPieceSource, string> = {
    room: "room",
    task: "task",
    start: "start",
    "map-tag": "map tag",
    "ocean-prefill": "ocean prefill",
    "ocean-room": "ocean room",
    unknown: "unknown"
};

const TRANSFORM_WORDS = [
    "none",
    "flipped, rotated 90° clockwise",
    "flipped",
    "rotated 90° clockwise",
    "flipped, rotated 180°",
    "rotated 90° anticlockwise",
    "rotated 180°",
    "flipped, rotated 90° anticlockwise"
];

const TILE_SIZE = 4;

export interface SetPieceMember {
    prefab: string;
    displayName: string;
    count: number;
}

export interface SetPieceDetails {
    /** The set piece's index in the world's set pieces. */
    index: number;
    name: string;
    /** Where the world generation got it from, in words. */
    source: string;
    /** Its centre, in world units. */
    x: number;
    z: number;
    /** Its bounds' size, in tiles. */
    width: number;
    height: number;
    /** How the layout was rotated and flipped, in words. */
    transform: string;
    /** Its members per prefab, the most first. */
    members: SetPieceMember[];
}

/** What the map says about the world's `index`-th set piece. */
export function setPieceDetails(world: Pick<GeneratedWorld, "prefabs" | "setPieces">, index: number): SetPieceDetails {
    const { name, source, transform, xk, zk, bounds, members } = world.setPieces![index];
    const counts = new Map<string, number>();
    for (let at = 0; at < members.length; at += 2) {
        const prefab = world.prefabs[members[at]].name;
        counts.set(prefab, (counts.get(prefab) ?? 0) + 1);
    }
    return {
        index,
        name,
        source: SOURCE_WORDS[source],
        x: xk / 100,
        z: zk / 100,
        width: (bounds[2] - bounds[0]) / 100 / TILE_SIZE,
        height: (bounds[3] - bounds[1]) / 100 / TILE_SIZE,
        transform: TRANSFORM_WORDS[transform & 7],
        members: [...counts]
            .map(([prefab, count]) => ({ prefab, displayName: prefabName(prefab), count }))
            .sort((a, b) => b.count - a.count || a.displayName.localeCompare(b.displayName))
    };
}
