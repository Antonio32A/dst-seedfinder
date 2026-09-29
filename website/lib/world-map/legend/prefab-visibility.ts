import { prefabName } from "@/lib/catalog/prefab-sets";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import type { SeedfinderConfig, Shard } from "@/lib/config/seedfinder-config";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import { groupOf, MAP_GROUPS, type MapGroup } from "./entity-layer";

export interface LegendPrefab {
    prefab: string;
    displayName: string;
    count: number;
}

export interface LegendGroup {
    group: Omit<MapGroup, "id"> & { id: string };
    count: number;
    /** Sorted by display name. */
    prefabs: LegendPrefab[];
}

export function mapLegend(world: Pick<GeneratedWorld, "prefabs"> & Partial<Pick<GeneratedWorld, "shard">>): LegendGroup[] {
    const shard = world.shard ?? "forest";
    const legend = MAP_GROUPS.map((group): LegendGroup => ({ group, count: 0, prefabs: [] }));
    for (const { name, positions } of world.prefabs) {
        const entry = legend[groupOf(name, shard)];
        entry.count += positions.length / 2;
        entry.prefabs.push({ prefab: name, displayName: prefabName(name, shard), count: positions.length / 2 });
    }
    for (const { prefabs } of legend) prefabs.sort((a, b) => a.displayName.localeCompare(b.displayName));
    return legend.filter(({ count }) => count > 0);
}

export type GroupState = "on" | "off" | "mixed";

export function groupState({ prefabs }: LegendGroup, shown: ReadonlySet<string>): GroupState {
    const on = prefabs.filter(({ prefab }) => shown.has(prefab)).length;
    return on === prefabs.length ? "on" : on === 0 ? "off" : "mixed";
}

export const allPrefabs = (legend: readonly LegendGroup[]): Set<string> =>
    new Set(legend.flatMap(({ prefabs }) => prefabs.map(({ prefab }) => prefab)));

export function showPrefabs(shown: ReadonlySet<string>, prefabs: readonly string[], on: boolean): Set<string> {
    const next = new Set(shown);
    for (const prefab of prefabs) {
        if (on) next.add(prefab);
        else next.delete(prefab);
    }
    return next;
}

/** Every prefab the game's map draws an icon for in a freshly generated world, and every prefab the world rules of `search` name, in any of its options. */
export function defaultShown(search?: SeedfinderConfig, shard: Shard = "forest"): Set<string> {
    const named = (search?.criteria ?? []).flatMap(({ counts = [], distances = [], routes = [] }) => [
        ...counts.flatMap(({ prefab, near }) => [prefab, near?.prefab]),
        ...distances.flatMap(({ from, to }) => [from, to]),
        ...routes.flatMap(({ from, visit, to }) => [from, ...visit, to])
    ]);
    const drawn = shardCatalog(shard).prefabs.filter(({ defaultShown }) => defaultShown).map(({ id }) => id);
    return new Set([...drawn, ...named.flatMap((prefabs) => [prefabs ?? []].flat())]);
}
