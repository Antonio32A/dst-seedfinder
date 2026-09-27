import { prefabName } from "@/lib/catalog/prefab-sets";
import type { WorldPoint } from "./map-view";
import type { GeneratedWorld } from "./world-dump";

export interface PrefabMatch {
    prefab: string;
    displayName: string;
    count: number;
}

/**
 * The prefabs present in `world` whose display name or id contains `query`, ignoring case: the ones that start with it
 * first, then by display name.
 */
export function searchPrefabs(world: Pick<GeneratedWorld, "prefabs">, query: string): PrefabMatch[] {
    const needle = query.trim().toLowerCase();
    const texts = (match: PrefabMatch) => [match.prefab, match.displayName].map((text) => text.toLowerCase());
    const starts = (match: PrefabMatch) => texts(match).some((text) => text.startsWith(needle));
    return world.prefabs
            .map(({ name, positions }) => ({ prefab: name, displayName: prefabName(name), count: positions.length / 2 }))
            .filter((match) => texts(match).some((text) => text.includes(needle)))
            .sort((a, b) => Number(starts(b)) - Number(starts(a)) || a.displayName.localeCompare(b.displayName));
}

/** Where each instance of `prefab` in `world` is, in savedata order. */
export function instancesOf(world: Pick<GeneratedWorld, "prefabs">, prefab: string): WorldPoint[] {
    const positions = world.prefabs.find(({ name }) => name === prefab)?.positions ?? new Int32Array(0);
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
