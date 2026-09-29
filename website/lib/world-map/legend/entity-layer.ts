import { shardCatalog } from "@/lib/catalog/shard-catalog";
import { PREFAB_GROUP_IDS, PREFAB_GROUPS, type PrefabGroupId } from "@/lib/catalog/world";
import type { Shard } from "@/lib/config/seedfinder-config";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";

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

export const MAP_GROUPS: readonly MapGroup[] = [
    ...PREFAB_GROUPS.map(({ id, name }) => ({ id, name, colour: COLOURS[id] })),
    { id: "other", name: "Other", colour: COLOURS.other }
];

const OTHER = MAP_GROUPS.length - 1;
const LINK_PREFAB: Record<Shard, string> = { forest: "wormhole", caves: "tentacle_pillar" };
export const SPAWN = "multiplayer_portal";
/** The map leaves the spawn points out: the portal stands for them. */
const UNMAPPED: ReadonlySet<string> = new Set(["spawnpoint_master", "spawnpoint_multiplayer"]);

/** Drops the unmapped prefabs and renumbers the set pieces' members and the pillar links to the ones left. */
export function mapWorld<World extends Pick<GeneratedWorld, "prefabs" | "setPieces"> & Partial<Pick<GeneratedWorld, "pillarLinks">>>(
    world: World
): World {
    const kept = world.prefabs.flatMap(({ name }, prefab) => (UNMAPPED.has(name) ? [] : [prefab]));
    const renumbered = new Map(kept.map((prefab, index) => [prefab, index]));
    const members = (pairs: Uint32Array) => {
        const mapped: number[] = [];
        for (let at = 0; at < pairs.length; at += 2) {
            const prefab = renumbered.get(pairs[at]);
            if (prefab !== undefined) mapped.push(prefab, pairs[at + 1]);
        }
        return Uint32Array.from(mapped);
    };
    const pillars = world.pillarLinks ?? new Uint32Array(0);
    const pillarLinks = Uint32Array.from(Array.from({ length: pillars.length / 4 }, (_, link) => {
        const [entry, entryIndex, exit, exitIndex] = pillars.subarray(4 * link, 4 * link + 4);
        return [renumbered.get(entry)!, entryIndex, renumbered.get(exit)!, exitIndex];
    }).flat());
    return {
        ...world,
        prefabs: kept.map((prefab) => world.prefabs[prefab]),
        pillarLinks,
        setPieces: world.setPieces?.map((piece) => ({ ...piece, members: members(piece.members) }))
    };
}

export interface EntityLayer {
    /** Interleaved `x, z` world positions, one per dot. */
    positions: Float32Array;
    /** Each dot's index in {@link MAP_GROUPS}. */
    groups: Uint8Array;
    names: string[];
    /** Each dot's prefab, as its index in {@link names}. */
    prefabs: Uint16Array;
    /** Interleaved `x, z` of the entry then the exit wormhole, or tentacle pillar in the caves, per link. */
    links: Float32Array;
    shard: Shard;
    linkGroup: number;
}

export const groupOf = (prefab: string, shard: Shard = "forest") => {
    const group = shardCatalog(shard).byId.get(prefab)?.group;
    return group === undefined ? OTHER : PREFAB_GROUP_IDS.indexOf(group);
};

/** Interleaved `x, z` of the entry then the exit of each wormhole link, or tentacle pillar link in the caves. */
function linkEnds(world: Pick<GeneratedWorld, "prefabs" | "links"> & Partial<Pick<GeneratedWorld, "pillarLinks">>, shard: Shard) {
    if (shard === "caves") {
        const pillars = world.pillarLinks ?? new Uint32Array(0);
        const ends = Array.from({ length: pillars.length / 2 }, (_, end) => {
            const { positions } = world.prefabs[pillars[2 * end]];
            return [positions[2 * pillars[2 * end + 1]], positions[2 * pillars[2 * end + 1] + 1]];
        });
        return Float32Array.from(ends.flat(), (centi) => centi / 100);
    }
    const wormholes = world.prefabs.find(({ name }) => name === LINK_PREFAB.forest)?.positions ?? new Int32Array(0);
    const ends = [...world.links].flatMap((wormhole) => [wormholes[2 * wormhole], wormholes[2 * wormhole + 1]]);
    return Float32Array.from(ends, (centi) => centi / 100);
}

/** One dot per entity, the groups listed first last, so they're drawn on top. */
export function entityLayer(
    world: Pick<GeneratedWorld, "prefabs" | "links"> & Partial<Pick<GeneratedWorld, "shard" | "pillarLinks">>
): EntityLayer {
    const shard = world.shard ?? "forest";
    const counts = MAP_GROUPS.map(() => 0);
    for (const { name, positions } of world.prefabs) counts[groupOf(name, shard)] += positions.length / 2;
    const next = counts.map((_, group) => counts.slice(group + 1).reduce((sum, count) => sum + count, 0));
    const total = counts.reduce((sum, count) => sum + count, 0);
    const positions = new Float32Array(2 * total);
    const groups = new Uint8Array(total);
    const prefabs = new Uint16Array(total);
    world.prefabs.forEach(({ name, positions: centi }, prefab) => {
        const group = groupOf(name, shard);
        const dot = next[group];
        groups.fill(group, dot, dot + centi.length / 2);
        prefabs.fill(prefab, dot, dot + centi.length / 2);
        for (let at = 0; at < centi.length; at++) positions[2 * dot + at] = centi[at] / 100;
        next[group] += centi.length / 2;
    });
    const links = linkEnds(world, shard);
    const names = world.prefabs.map(({ name }) => name);
    return { positions, groups, names, prefabs, links, shard, linkGroup: groupOf(LINK_PREFAB[shard], shard) };
}
