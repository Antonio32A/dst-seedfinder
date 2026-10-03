import { DEFAULT_SHARD, type Platform, PLATFORMS, type SeedfinderConfig, type Shard } from "@/lib/config/seedfinder-config";
import { validateConfig } from "@/lib/config/validate-config";
import { decodeShareParam, encodeShareParam } from "@/lib/criteria/search-state";
import { clamp } from "@/lib/criteria/state-helpers";
import { SEED_SPACE } from "@/lib/jobs/job-result";
import type { LinkedView } from "@/lib/world-map/view/map-view";

const MAX_CENTRE = 8192;
const MIN_SPAN = 8;
const MAX_SPAN = 8192;
const HEADING_STEP = 45;
const VIEW_PARAM = /^(-?\d{1,6})_(-?\d{1,6})_(\d{1,6})_(-?\d{1,6})$/;

export type MapConfig = { config: SeedfinderConfig } | { error: string };

export type MapRoute = { platform: Platform; shard: Shard; seed: number } | { error: string };

/**
 * The forest's map lives at `/map/<platform>/<seed>` and the caves' at `/map/<platform>/caves/<seed>`, opening on
 * `view` when there's one.
 */
export function mapPath(
    platform: Platform,
    seed: number,
    config?: SeedfinderConfig,
    shard: Shard = config?.shard ?? DEFAULT_SHARD,
    view?: LinkedView
) {
    const query = [config && `c=${encodeShareParam(config)}`, view && `v=${encodeMapView(view)}`].filter(Boolean).join("&");
    return `/map/${platform}/${shard === "caves" ? "caves/" : ""}${seed}${query && `?${query}`}`;
}

/** Whole world units and a heading in `[0, 360)` on its 45 degree steps, so every view a link can open has one spelling. */
const roundedView = ({ centerX, centerZ, span, heading }: LinkedView): LinkedView => ({
    centerX: clamp(centerX, -MAX_CENTRE, MAX_CENTRE),
    centerZ: clamp(centerZ, -MAX_CENTRE, MAX_CENTRE),
    span: clamp(span, MIN_SPAN, MAX_SPAN),
    heading: ((Math.round(heading / HEADING_STEP) * HEADING_STEP) % 360 + 360) % 360
});

/** The map link's `v` param: `<centre x>_<centre z>_<span>_<heading>`, in world units and degrees. */
export function encodeMapView(view: LinkedView): string {
    const { centerX, centerZ, span, heading } = roundedView(view);
    return [centerX, centerZ, span, heading].join("_");
}

/** The view a map link's `v` param opens, clamped to the views a link can open, or none when it isn't one. */
export function parseMapView(param: string | string[] | undefined): LinkedView | undefined {
    const match = typeof param === "string" ? VIEW_PARAM.exec(param) : null;
    if (match === null) return undefined;
    const [centerX, centerZ, span, heading] = match.slice(1).map(Number);
    return roundedView({ centerX, centerZ, span, heading });
}

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
