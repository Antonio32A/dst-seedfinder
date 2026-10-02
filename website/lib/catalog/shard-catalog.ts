import type { Shard } from "@/lib/config/seedfinder-config";
import {
    CAVE_ANCHORS,
    CAVE_LAND_TILES,
    CAVE_PREFAB_BY_ID,
    CAVE_PREFABS,
    CAVE_SAMPLE_WORLDS,
    LAND_TILES,
    type LandTile,
    NAMED_ANCHORS,
    type NamedAnchor,
    PREFAB_BY_ID,
    PREFAB_GROUP_IDS,
    type PrefabGroup,
    PREFABS,
    SAMPLE_WORLDS,
    type WorldPrefab
} from "./world";

export interface ShardCatalog {
    prefabs: readonly WorldPrefab[];
    byId: ReadonlyMap<string, WorldPrefab>;
    /** The prefab groups of the shard's prefabs, in display order. */
    groups: readonly PrefabGroup[];
    /** The places worth a shortcut, the spawn first. */
    anchors: readonly NamedAnchor[];
    landTiles: readonly LandTile[];
    /** How many real worlds the prefab counts come from. */
    sampleWorlds: number;
    /** Where a player starts: the spawn portal in the forest, the stairs they arrive on in the caves. */
    spawn: string;
    /** The things that teleport the player between two places: wormholes in the forest, tentacle pillars in the caves. */
    links: { noun: string; plural: string; prefabs: readonly string[] };
}

const groupsOf = (prefabs: readonly WorldPrefab[]): PrefabGroup[] =>
    PREFAB_GROUP_IDS.map((id) => ({
        id,
        name: id.charAt(0).toUpperCase() + id.slice(1),
        prefabs: prefabs.filter((prefab) => prefab.group === id).map((prefab) => prefab.id)
    })).filter((group) => group.prefabs.length > 0);

const CATALOGS: Record<Shard, ShardCatalog> = {
    forest: {
        prefabs: PREFABS,
        byId: PREFAB_BY_ID,
        groups: groupsOf(PREFABS),
        anchors: NAMED_ANCHORS,
        landTiles: LAND_TILES,
        sampleWorlds: SAMPLE_WORLDS,
        spawn: "multiplayer_portal",
        links: { noun: "wormhole", plural: "wormholes", prefabs: ["wormhole"] }
    },
    caves: {
        prefabs: CAVE_PREFABS,
        byId: CAVE_PREFAB_BY_ID,
        groups: groupsOf(CAVE_PREFABS),
        anchors: CAVE_ANCHORS,
        landTiles: CAVE_LAND_TILES,
        sampleWorlds: CAVE_SAMPLE_WORLDS,
        spawn: "cave_exit",
        links: { noun: "tentacle pillar", plural: "tentacle pillars", prefabs: ["tentacle_pillar", "tentacle_pillar_atrium"] }
    }
};

/** The prefabs a shard's worlds can contain, with their display names, groups and map icons, and what its world filters start from. */
export const shardCatalog = (shard: Shard): ShardCatalog => CATALOGS[shard];
