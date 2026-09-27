import { prefabName } from "@/lib/catalog/prefab-sets";
import { PREFAB_GROUPS } from "@/lib/catalog/world";
import type { Criterion, PrefabSet, SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { groupOf, isMapped, MAP_GROUPS, type MapGroup } from "./entity-layer";
import type { GeneratedWorld } from "./world-dump";

export interface LegendPrefab {
    prefab: string;
    displayName: string;
    count: number;
}

export interface LegendGroup {
    group: MapGroup;
    /** The group's entities in the world. */
    count: number;
    /** The group's prefabs in the world, by display name. */
    prefabs: LegendPrefab[];
}

/** The map's groups that have entities in `world`, in {@link MAP_GROUPS} order, with their prefabs in it. */
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

/** Whether all of a legend group's prefabs are in `shown`, none is, or only some are. */
export function groupState({ prefabs }: LegendGroup, shown: ReadonlySet<string>): GroupState {
    const on = prefabs.filter(({ prefab }) => shown.has(prefab)).length;
    return on === prefabs.length ? "on" : on === 0 ? "off" : "mixed";
}

/** `shown` with `prefabs` turned on or off. */
export function showPrefabs(shown: ReadonlySet<string>, prefabs: readonly string[], on: boolean): Set<string> {
    const next = new Set(shown);
    for (const prefab of prefabs) {
        if (on) next.add(prefab);
        else next.delete(prefab);
    }
    return next;
}

const SHOWN_GROUP = "spawn & travel";

const namedBy = ({ counts = [], distances = [], routes = [] }: Criterion): (PrefabSet | undefined)[] => [
    ...counts.flatMap(({ prefab, near }) => [prefab, near?.prefab]),
    ...distances.flatMap(({ from, to }) => [from, to]),
    ...routes.flatMap(({ from, visit, to }) => [from, ...visit, to])
];

/**
 * The prefabs a map shows when it opens: the spawn & travel group the map draws (the portal, the wormholes and the
 * sinkholes), and every prefab the world rules of `search` name, in any of its options.
 */
export function defaultShown(search?: SeedfinderConfig): Set<string> {
    const named = (search?.criteria ?? []).flatMap(namedBy).flatMap((prefabs) => [prefabs ?? []].flat());
    const group = PREFAB_GROUPS.find(({ id }) => id === SHOWN_GROUP)!.prefabs;
    return new Set([...group.filter(isMapped), ...named]);
}
