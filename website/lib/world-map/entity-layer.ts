import { PREFAB_BY_ID, PREFAB_GROUP_IDS, PREFAB_GROUPS, type PrefabGroupId } from "@/lib/catalog/world";
import type { GeneratedWorld } from "./world-dump";

export type MapGroupId = PrefabGroupId | "other";

type Colour = readonly [r: number, g: number, b: number];

export interface MapGroup {
    id: MapGroupId;
    name: string;
    colour: Colour;
}

const COLOURS: Record<MapGroupId, Colour> = {
    "spawn & travel": [255, 51, 204],
    "bosses & spawners": [220, 20, 20],
    landmarks: [255, 210, 0],
    clockwork: [255, 128, 0],
    sculptures: [205, 160, 255],
    statues: [235, 235, 235],
    trees: [20, 90, 30],
    rocks: [110, 115, 125],
    plants: [120, 215, 50],
    "mobs & dens": [165, 75, 35],
    structures: [120, 70, 230],
    items: [250, 230, 160],
    "set-piece loot": [0, 200, 170],
    ocean: [110, 215, 255],
    markers: [95, 60, 110],
    other: [45, 45, 45]
};

/** The map's entity groups in legend order: the catalog's prefab groups, then "other" for prefabs outside it. */
export const MAP_GROUPS: readonly MapGroup[] = [
    ...PREFAB_GROUPS.map(({ id, name }) => ({ id, name, colour: COLOURS[id] })),
    { id: "other", name: "Other", colour: COLOURS.other }
];

const OTHER = MAP_GROUPS.length - 1;
const WORMHOLE = "wormhole";

export interface EntityLayer {
    /** Interleaved `x, z` world positions, one per dot. */
    positions: Float32Array;
    /** Each dot's index in {@link MAP_GROUPS}. */
    groups: Uint8Array;
    /** Entities per group, indexed like {@link MAP_GROUPS}. */
    counts: number[];
    /** Interleaved `x, z` of the entry then the exit wormhole, per wormhole link. */
    links: Float32Array;
    /** The group whose visibility the wormhole links follow, the wormholes' own. */
    linkGroup: number;
}

/** The index in {@link MAP_GROUPS} of a prefab's group. */
export const groupOf = (prefab: string) => {
    const group = PREFAB_BY_ID.get(prefab)?.group;
    return group === undefined ? OTHER : PREFAB_GROUP_IDS.indexOf(group);
};

/**
 * Sorts a world's entities into the map's groups, as one dot per entity. The dots of the groups listed first come
 * last, so they're drawn on top.
 */
export function entityLayer(world: Pick<GeneratedWorld, "prefabs" | "links">): EntityLayer {
    const counts = MAP_GROUPS.map(() => 0);
    for (const { name, positions } of world.prefabs) counts[groupOf(name)] += positions.length / 2;
    const next = counts.map((_, group) => counts.slice(group + 1).reduce((sum, count) => sum + count, 0));
    const total = counts.reduce((sum, count) => sum + count, 0);
    const positions = new Float32Array(2 * total);
    const groups = new Uint8Array(total);
    for (const { name, positions: centi } of world.prefabs) {
        const group = groupOf(name);
        const dot = next[group];
        groups.fill(group, dot, dot + centi.length / 2);
        for (let at = 0; at < centi.length; at++) positions[2 * dot + at] = centi[at] / 100;
        next[group] += centi.length / 2;
    }
    const wormholes = world.prefabs.find(({ name }) => name === WORMHOLE)?.positions ?? new Int32Array(0);
    const ends = [...world.links].flatMap((wormhole) => [wormholes[2 * wormhole], wormholes[2 * wormhole + 1]]);
    const links = Float32Array.from(ends, (centi) => centi / 100);
    return { positions, groups, counts, links, linkGroup: groupOf(WORMHOLE) };
}
