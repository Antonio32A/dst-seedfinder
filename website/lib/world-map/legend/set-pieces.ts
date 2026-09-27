import { prefabName } from "@/lib/catalog/prefab-sets";
import { type SeedfinderConfig, WORLD_UNITS_PER_TILE } from "@/lib/config/seedfinder-config";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import type { LegendGroup } from "./prefab-visibility";

export const SET_PIECE_COLOUR = [255, 100, 40] as const;

/** Every set piece the set piece rules of `search` name, in any of its options. */
export const defaultShownSetPieces = (search?: SeedfinderConfig): Set<string> => new Set((search?.criteria ?? [])
    .flatMap(({ setpieces = [] }) => setpieces.flatMap(({ required = {} }) => Object.keys(required))));

export function setPieceCounts(world: Pick<GeneratedWorld, "setPieces">): Map<string, number> {
    const counts = new Map<string, number>();
    for (const { name } of world.setPieces ?? []) counts.set(name, (counts.get(name) ?? 0) + 1);
    return counts;
}

/** One entry per layout name, `null` when the world has none or its dump doesn't say. */
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

export interface SetPieceMember {
    prefab: string;
    displayName: string;
    count: number;
}

export interface SetPieceDetails {
    index: number;
    name: string;
    /** Where the world generation got it from. */
    source: string;
    /** The centre, in world units. */
    x: number;
    z: number;
    /** The bounds' size, in tiles. */
    width: number;
    height: number;
    /** How the layout was rotated and flipped. */
    transform: string;
    /** The most common prefab first. */
    members: SetPieceMember[];
}

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
        source: source.replace("-", " "),
        x: xk / 100,
        z: zk / 100,
        width: (bounds[2] - bounds[0]) / 100 / WORLD_UNITS_PER_TILE,
        height: (bounds[3] - bounds[1]) / 100 / WORLD_UNITS_PER_TILE,
        transform: TRANSFORM_WORDS[transform & 7],
        members: [...counts]
            .map(([prefab, count]) => ({ prefab, displayName: prefabName(prefab), count }))
            .sort((a, b) => b.count - a.count || a.displayName.localeCompare(b.displayName))
    };
}
