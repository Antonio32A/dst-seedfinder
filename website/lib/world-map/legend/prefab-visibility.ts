import { prefabName } from "@/lib/catalog/prefab-sets";
import { PREFAB_GROUPS } from "@/lib/catalog/world";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import { groupOf, isMapped, MAP_GROUPS, type MapGroup } from "./entity-layer";

export interface LegendPrefab {
    prefab: string;
    displayName: string;
    count: number;
}

export interface LegendGroup {
    group: Omit<MapGroup, "id"> & { id: string };
    count: number;
    /** By display name. */
    prefabs: LegendPrefab[];
}

/** The groups with entities in `world`, in {@link MAP_GROUPS} order. */
export function mapLegend(world: Pick<GeneratedWorld, "prefabs">): LegendGroup[] {
    const legend = MAP_GROUPS.map((group): LegendGroup => ({ group, count: 0, prefabs: [] }));
    for (const { name, positions } of world.prefabs) {
        const entry = legend[groupOf(name)];
        entry.count += positions.length / 2;
        entry.prefabs.push({ prefab: name, displayName: prefabName(name), count: positions.length / 2 });
    }
    for (const { prefabs } of legend) prefabs.sort((a, b) => a.displayName.localeCompare(b.displayName));
    return legend.filter(({ count }) => count > 0);
}

export type GroupState = "on" | "off" | "mixed";

export function groupState({ prefabs }: LegendGroup, shown: ReadonlySet<string>): GroupState {
    const on = prefabs.filter(({ prefab }) => shown.has(prefab)).length;
    return on === prefabs.length ? "on" : on === 0 ? "off" : "mixed";
}

export function showPrefabs(shown: ReadonlySet<string>, prefabs: readonly string[], on: boolean): Set<string> {
    const next = new Set(shown);
    for (const prefab of prefabs) {
        if (on) next.add(prefab);
        else next.delete(prefab);
    }
    return next;
}

const SHOWN_GROUP = "spawn & travel";
const HIDDEN_FROM_GROUP = "wormhole";

/** The spawn & travel group without wormholes, and every prefab the world rules of `search` name, in any of its options. */
export function defaultShown(search?: SeedfinderConfig): Set<string> {
    const named = (search?.criteria ?? []).flatMap(({ counts = [], distances = [], routes = [] }) => [
        ...counts.flatMap(({ prefab, near }) => [prefab, near?.prefab]),
        ...distances.flatMap(({ from, to }) => [from, to]),
        ...routes.flatMap(({ from, visit, to }) => [from, ...visit, to])
    ]);
    const group = PREFAB_GROUPS.find(({ id }) => id === SHOWN_GROUP)!.prefabs;
    return new Set([...group.filter((prefab) => isMapped(prefab) && prefab !== HIDDEN_FROM_GROUP), ...named.flatMap((prefabs) => [prefabs ?? []].flat())]);
}
