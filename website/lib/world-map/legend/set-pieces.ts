import { prefabName } from "@/lib/catalog/prefab-sets";
import { type SeedfinderConfig, WORLD_UNITS_PER_TILE } from "@/lib/config/seedfinder-config";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import type { LegendGroup, LegendPrefab } from "./prefab-visibility";

export const SET_PIECE_COLOUR = [255, 100, 40] as const;

export const defaultShownSetPieces = (search?: SeedfinderConfig): Set<string> => new Set((search?.criteria ?? [])
    .flatMap(({ setpieces = [] }) => setpieces.flatMap(({ required = {} }) => Object.keys(required))));

const tally = (names: Iterable<string>) => {
    const counts = new Map<string, number>();
    for (const name of names) counts.set(name, (counts.get(name) ?? 0) + 1);
    return counts;
};

export const setPieceCounts = (world: Pick<GeneratedWorld, "setPieces">) =>
    tally((world.setPieces ?? []).map(({ name }) => name));

/** `null` when the world has none or its dump doesn't say. */
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
    transform: string;
    /** The most common prefab first. */
    members: LegendPrefab[];
}

export function setPieceDetails(
    world: Pick<GeneratedWorld, "prefabs" | "setPieces"> & Partial<Pick<GeneratedWorld, "shard">>,
    index: number
): SetPieceDetails {
    const { name, source, transform, xk, zk, bounds, members } = world.setPieces![index];
    const counts = tally(Array.from({ length: members.length / 2 }, (_, at) => world.prefabs[members[2 * at]].name));
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
            .map(([prefab, count]) => ({ prefab, displayName: prefabName(prefab, world.shard), count }))
            .sort((a, b) => b.count - a.count || a.displayName.localeCompare(b.displayName))
    };
}
