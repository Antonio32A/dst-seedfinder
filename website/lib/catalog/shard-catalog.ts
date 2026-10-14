import { type CatalogBuild, catalogBuild } from "@/lib/config/builds";
import type { GameBuild } from "@/lib/config/game-builds";
import type { Shard } from "@/lib/config/seedfinder-config";
import {
    CAVE_ANCHORS,
    CAVE_CATALOGS,
    type CaveCatalog,
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
    /**
     * The things that teleport the player between two places: wormholes in the forest, tentacle pillars in the caves.
     */
    links: { noun: string; plural: string; prefabs: readonly string[] };
}

const groupsOf = (prefabs: readonly WorldPrefab[]): PrefabGroup[] =>
    PREFAB_GROUP_IDS.map((id) => ({
        id,
        name: id.charAt(0).toUpperCase() + id.slice(1),
        prefabs: prefabs.filter((prefab) => prefab.group === id).map((prefab) => prefab.id)
    })).filter((group) => group.prefabs.length > 0);

const caveCatalog = ({ prefabs, sampleWorlds, landTiles }: CaveCatalog): ShardCatalog => ({
    prefabs,
    byId: new Map(prefabs.map((prefab) => [prefab.id, prefab])),
    groups: groupsOf(prefabs),
    anchors: CAVE_ANCHORS,
    landTiles,
    sampleWorlds,
    spawn: "cave_exit",
    links: {
        noun: "tentacle pillar",
        plural: "tentacle pillars",
        prefabs: ["tentacle_pillar", "tentacle_pillar_atrium"]
    }
});

const CATALOGS: { [S in Shard]: Record<CatalogBuild<S>, ShardCatalog> } = {
    forest: {
        756039: {
            prefabs: PREFABS,
            byId: PREFAB_BY_ID,
            groups: groupsOf(PREFABS),
            anchors: NAMED_ANCHORS,
            landTiles: LAND_TILES,
            sampleWorlds: SAMPLE_WORLDS,
            spawn: "multiplayer_portal",
            links: { noun: "wormhole", plural: "wormholes", prefabs: ["wormhole"] }
        }
    },
    caves: Object.fromEntries(
        Object.entries(CAVE_CATALOGS).map(([build, cave]) => [build, caveCatalog(cave)])
    ) as Record<keyof typeof CAVE_CATALOGS, ShardCatalog>
};

/**
 * The prefabs a shard's worlds can contain in the build, with their display names, groups and map icons, and what its
 * world filters start from.
 */
export const shardCatalog = <S extends Shard>(shard: S, build: GameBuild): ShardCatalog =>
    CATALOGS[shard][catalogBuild(build, shard)];
