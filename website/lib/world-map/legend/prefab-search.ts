import { prefabName } from "@/lib/catalog/prefab-sets";
import type { WorldPoint } from "@/lib/world-map/view/map-view";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import { setPieceCounts } from "./set-pieces";

export interface MapTarget {
    kind: "prefab" | "set piece";
    /** A prefab id, or a set piece's layout name. */
    name: string;
}

export interface MapMatch extends MapTarget {
    displayName: string;
    count: number;
}

type SearchedWorld = Pick<GeneratedWorld, "prefabs" | "setPieces">;

/** Matches display names and ids containing `query`, ignoring case: the ones starting with it first, then by name. */
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

/** A prefab's instances in savedata order, a set piece's centres in placement order. */
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

/** Wraps around. From none, a step forwards goes to the first and one back to the last. */
export const stepInstance = (current: number | null, count: number, step: number): number =>
    ((current ?? (step > 0 ? -1 : count)) + step + count) % count;
