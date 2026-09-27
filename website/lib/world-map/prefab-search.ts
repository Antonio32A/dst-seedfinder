import { prefabName } from "@/lib/catalog/prefab-sets";
import type { WorldPoint } from "./map-view";
import { setPieceCounts } from "./set-pieces";
import type { GeneratedWorld } from "./world-dump";

/** What the map can find: a prefab by its id, or a set piece by its layout name. */
export interface MapTarget {
    kind: "prefab" | "set piece";
    name: string;
}

export interface MapMatch extends MapTarget {
    displayName: string;
    count: number;
}

type SearchedWorld = Pick<GeneratedWorld, "prefabs" | "setPieces">;

/**
 * The prefabs and set pieces present in `world` whose display name or id contains `query`, ignoring case: the ones
 * that start with it first, then by display name.
 */
export function searchPrefabs(world: SearchedWorld, query: string): MapMatch[] {
    const needle = query.trim().toLowerCase();
    const texts = (match: MapMatch) => [match.name, match.displayName].map((text) => text.toLowerCase());
    const starts = (match: MapMatch) => texts(match).some((text) => text.startsWith(needle));
    return [
        ...world.prefabs.map(({ name, positions }): MapMatch =>
            ({ kind: "prefab", name, displayName: prefabName(name), count: positions.length / 2 })),
        ...[...setPieceCounts(world)].map(([name, count]): MapMatch =>
            ({ kind: "set piece", name, displayName: name, count }))
    ]
        .filter((match) => texts(match).some((text) => text.includes(needle)))
        .sort((a, b) => Number(starts(b)) - Number(starts(a)) || a.displayName.localeCompare(b.displayName));
}

/**
 * Where each instance of `target` in `world` is: a prefab's in savedata order, a set piece's centres in placement
 * order.
 */
export function instancesOf(world: SearchedWorld, { kind, name }: MapTarget): WorldPoint[] {
    if (kind === "set piece") {
        const pieces = (world.setPieces ?? []).filter((piece) => piece.name === name);
        return pieces.map(({ xk, zk }) => ({ x: xk / 100, z: zk / 100 }));
    }
    const positions = world.prefabs.find((prefab) => prefab.name === name)?.positions ?? new Int32Array(0);
    return Array.from({ length: positions.length / 2 }, (_, index) => ({
        x: positions[2 * index] / 100,
        z: positions[2 * index + 1] / 100
    }));
}

/**
 * The instance `step` places after `current` of `count`, wrapping around. From none, a step forwards goes to the first
 * and one back to the last.
 */
export const stepInstance = (current: number | null, count: number, step: number): number =>
    ((current ?? (step > 0 ? -1 : count)) + step + count) % count;
