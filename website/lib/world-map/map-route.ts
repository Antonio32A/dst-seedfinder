import { DEFAULT_SHARD, type Platform, PLATFORMS, type SeedfinderConfig, type Shard } from "@/lib/config/seedfinder-config";
import { validateConfig } from "@/lib/config/validate-config";
import { decodeShareParam, encodeShareParam } from "@/lib/criteria/search-state";
import { SEED_SPACE } from "@/lib/jobs/job-result";

export type MapConfig = { config: SeedfinderConfig } | { error: string };

export type MapRoute = { platform: Platform; shard: Shard; seed: number } | { error: string };

/** The forest's map lives at `/map/<platform>/<seed>` and the caves' at `/map/<platform>/caves/<seed>`. */
export const mapPath = (platform: Platform, seed: number, config?: SeedfinderConfig, shard: Shard = config?.shard ?? DEFAULT_SHARD) =>
    `/map/${platform}/${shard === "caves" ? "caves/" : ""}${seed}${config === undefined ? "" : `?c=${encodeShareParam(config)}`}`;

export function parseMapRoute(platform: string, seed: string, shard: Shard = DEFAULT_SHARD): MapRoute {
    const known = PLATFORMS.find((option) => option === platform);
    if (known === undefined) return { error: `There's no "${platform}" platform. Use ${PLATFORMS.join(" or ")}.` };
    const value = /^\d{1,10}$/.test(seed) ? Number(seed) : SEED_SPACE;
    if (value >= SEED_SPACE) return { error: `"${seed}" isn't a seed. Seeds are whole numbers from 0 to ${SEED_SPACE - 1}.` };
    return { platform: known, shard, seed: value };
}

/** Where a typed seed's map lives on the platform and shard, or why the text isn't a seed. */
export function pickedMapPath(platform: Platform, seed: string, shard: Shard): { path: string } | { error: string } {
    const route = parseMapRoute(platform, seed.trim(), shard);
    return "error" in route ? route : { path: mapPath(route.platform, route.seed, undefined, route.shard) };
}

/** On the map's platform and shard, since `world eval` refuses a config for another. */
export function parseMapConfig(share: string, platform: Platform, shard: Shard = DEFAULT_SHARD): MapConfig {
    const checked = validateConfig(decodeShareParam(share));
    return checked.ok ? { config: { ...checked.value, platform, shard } } : { error: checked.error };
}
