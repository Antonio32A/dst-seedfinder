import { gameBuildOf, hasShard } from "@/lib/config/builds";
import { type GameBuild, LATEST_BUILD, WEBSITE_BUILDS } from "@/lib/config/game-builds";
import {
    DEFAULT_SHARD,
    type Platform,
    PLATFORMS,
    type SeedfinderConfig,
    type Shard,
    SHARD_LABELS,
    SHARDS
} from "@/lib/config/seedfinder-config";
import { upgradeConfig } from "@/lib/config/upgrade-config";
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

/** What a map shows: the world a build generates for a seed of a shard on a platform. */
export interface MapSeed {
    platform: Platform;
    shard: Shard;
    build: GameBuild;
    seed: number;
}

export type MapRoute = MapSeed | { error: string };

/**
 * A world's map lives at `/map/<platform>/<build>/<seed>` in the forest and at `/map/<platform>/caves/<build>/<seed>`
 * in the caves, opening on `view` when there's one.
 */
export function mapPath({ platform, shard, build, seed }: MapSeed, config?: SeedfinderConfig, view?: LinkedView) {
    const query = [config && `c=${encodeShareParam(config)}`, view && `v=${encodeMapView(view)}`].filter(Boolean).join("&");
    return `/map/${platform}/${shard === "caves" ? "caves/" : ""}${build}/${seed}${query && `?${query}`}`;
}

/**
 * Whole world units and a heading in `[0, 360)` on its 45 degree steps, so every view a link can open has one
 * spelling.
 */
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

function seedOf(text: string): number | { error: string } {
    const value = /^\d{1,10}$/.test(text) ? Number(text) : SEED_SPACE;
    return value < SEED_SPACE ? value : { error: `"${text}" isn't a seed. Seeds are whole numbers from 0 to ${SEED_SPACE - 1}.` };
}

function buildOf(text: string | undefined, shard: Shard): GameBuild | { error: string } {
    if (text === undefined) return LATEST_BUILD;
    const build = /^\d{1,10}$/.test(text) ? gameBuildOf(Number(text)) : undefined;
    if (build === undefined) return { error: `There's no build "${text}". Use ${WEBSITE_BUILDS.join(" or ")}.` };
    return hasShard(build, shard) ? build : { error: `Build ${build} has no ${SHARD_LABELS[shard].toLowerCase()} yet.` };
}

/**
 * The world of a map route's segments after its platform: an optional shard word (the forest without one), then the
 * seed, or the build then the seed (the latest build without one).
 */
export function parseMapRoute(platform: string, segments: readonly string[]): MapRoute {
    const known = PLATFORMS.find((option) => option === platform);
    if (known === undefined) return { error: `There's no "${platform}" platform. Use ${PLATFORMS.join(" or ")}.` };
    const named = SHARDS.find((option) => option === segments[0]);
    const shard = named ?? DEFAULT_SHARD;
    const rest = segments.slice(named === undefined ? 0 : 1);
    if (rest.length < 1 || rest.length > 2) return { error: `There's no map at "${segments.join("/")}".` };
    const build = buildOf(rest.at(-2), shard);
    const seed = seedOf(rest[rest.length - 1]);
    if (typeof build === "object") return build;
    return typeof seed === "object" ? seed : { platform: known, shard, build, seed };
}

/** Where a typed seed's map lives on the platform, shard and build, or why the text isn't a seed. */
export function pickedMapPath(
    platform: Platform,
    seed: string,
    shard: Shard,
    build: GameBuild
): { path: string } | { error: string } {
    const route = parseMapRoute(platform, [shard, String(build), seed.trim()]);
    return "error" in route ? route : { path: mapPath(route) };
}

/** On the map's platform, shard and build, since `world eval` refuses a config for another. */
export function parseMapConfig(share: string, { platform, shard, build }: Omit<MapSeed, "seed">): MapConfig {
    const checked = validateConfig(upgradeConfig(decodeShareParam(share)));
    return checked.ok ? { config: { ...checked.value, platform, shard, build } } : { error: checked.error };
}
