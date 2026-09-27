import { type Platform, PLATFORMS, type SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { validateConfig } from "@/lib/config/validate-config";
import { decodeShareParam, encodeShareParam } from "@/lib/criteria/search-state";
import { SEED_SPACE } from "@/lib/jobs/job-result";

export type MapConfig = { config: SeedfinderConfig } | { error: string };

export type MapRoute = { platform: Platform; seed: number } | { error: string };

/** The path of a seed's world map on a platform, drawing `config`'s witnesses when given. */
export const mapPath = (platform: Platform, seed: number, config?: SeedfinderConfig) =>
    `/map/${platform}/${seed}${config === undefined ? "" : `?c=${encodeShareParam(config)}`}`;

/** Reads the `/map/<platform>/<seed>` route params, with a readable error for the ones that don't name a world. */
export function parseMapRoute(platform: string, seed: string): MapRoute {
    const known = PLATFORMS.find((option) => option === platform);
    if (known === undefined) return { error: `There's no "${platform}" platform. Use ${PLATFORMS.join(" or ")}.` };
    const value = /^\d{1,10}$/.test(seed) ? Number(seed) : SEED_SPACE;
    if (value >= SEED_SPACE) return { error: `"${seed}" isn't a seed. Seeds are whole numbers from 0 to ${SEED_SPACE - 1}.` };
    return { platform: known, seed: value };
}

/** Reads a map's `?c=` share param as the config to evaluate on the map's world, so on the map's platform. */
export function parseMapConfig(share: string, platform: Platform): MapConfig {
    const checked = validateConfig(decodeShareParam(share));
    return checked.ok ? { config: { ...checked.value, platform } } : { error: checked.error };
}
