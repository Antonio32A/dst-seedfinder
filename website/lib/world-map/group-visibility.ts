import { MAP_GROUPS, type MapGroupId } from "./entity-layer";

const STORAGE_KEY = "dst-seedfinder:map-groups:v1";
const HIDDEN_BY_DEFAULT: ReadonlySet<MapGroupId> = new Set([
    "trees",
    "plants",
    "rocks",
    "mobs & dens",
    "items",
    "other"
]);

/** Whether the map draws each entity group. */
export type GroupVisibility = Record<MapGroupId, boolean>;

/** The groups this browser shows on the map: the ones it toggled, and the defaults for the rest. */
export function readGroupVisibility(): GroupVisibility {
    let stored: Partial<Record<string, unknown>> = {};
    try {
        stored = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "{}") ?? {};
    } catch {
    }
    return Object.fromEntries(MAP_GROUPS.map(({ id }) => {
        const shown = stored[id];
        return [id, typeof shown === "boolean" ? shown : !HIDDEN_BY_DEFAULT.has(id)];
    })) as GroupVisibility;
}

/** Remembers the groups this browser shows. */
export function storeGroupVisibility(visibility: GroupVisibility): void {
    try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(visibility));
    } catch {
    }
}
