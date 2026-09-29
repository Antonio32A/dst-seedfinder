import type { Shard } from "@/lib/config/seedfinder-config";
import { CAVE_PREFAB_BY_ID, CAVE_PREFABS, PREFAB_BY_ID, PREFABS, type WorldPrefab } from "./world";

export interface ShardCatalog {
    prefabs: readonly WorldPrefab[];
    byId: ReadonlyMap<string, WorldPrefab>;
}

const CATALOGS: Record<Shard, ShardCatalog> = {
    forest: { prefabs: PREFABS, byId: PREFAB_BY_ID },
    caves: { prefabs: CAVE_PREFABS, byId: CAVE_PREFAB_BY_ID }
};

/** The prefabs a shard's worlds can contain, with their display names, groups and map icons. */
export const shardCatalog = (shard: Shard): ShardCatalog => CATALOGS[shard];
