import { type Platform, PLATFORMS } from "@/lib/config/seedfinder-config";
import { SEED_SPACE } from "@/lib/jobs/job-result";

export type MapRoute = { platform: Platform; seed: number } | { error: string };

/** The path of a seed's world map on a platform. */
export const mapPath = (platform: Platform, seed: number) => `/map/${platform}/${seed}`;

/** Reads the `/map/<platform>/<seed>` route params, with a readable error for the ones that don't name a world. */
export function parseMapRoute(platform: string, seed: string): MapRoute {
    const known = PLATFORMS.find((option) => option === platform);
    if (known === undefined) return { error: `There's no "${platform}" platform. Use ${PLATFORMS.join(" or ")}.` };
    const value = /^\d{1,10}$/.test(seed) ? Number(seed) : SEED_SPACE;
    if (value >= SEED_SPACE) return { error: `"${seed}" isn't a seed. Seeds are whole numbers from 0 to ${SEED_SPACE - 1}.` };
    return { platform: known, seed: value };
}
