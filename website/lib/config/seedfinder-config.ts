import type { SwapCategory } from "@/lib/catalog/level-types";

export const CONFIG_VERSION = 1;

export const MAX_UINT32 = 4_294_967_295;
export const MAX_DISTANCE = 1_000_000;
export const WORLD_UNITS_PER_TILE = 4;

export const MAX_CRITERIA = 25;
export const MAX_RULES_PER_SECTION = 16;
export const MAX_PREFAB_IDS = 16;
export const MAX_SET_PIECES_PER_RULE = 16;
export const MAX_TASKS_PER_LIST = 25;
export const MIN_ROUTE_STOPS = 1;
export const MAX_ROUTE_STOPS = 6;
export const MAX_TILE_NAMES = 16;

export const MIN_WANTED = 1;
export const MAX_WANTED = 100;
export const DEFAULT_START_SEED = 0;

export const METRICS = ["straight", "walk"] as const;
export type Metric = (typeof METRICS)[number];
export const DEFAULT_METRIC: Metric = "straight";
export const DEFAULT_LINKS = false;

export const ROUTE_ORDERS = ["any", "fixed"] as const;
export type RouteOrder = (typeof ROUTE_ORDERS)[number];
export const DEFAULT_ROUTE_ORDER: RouteOrder = "any";

export const SHARDS = ["forest", "caves"] as const;
export type Shard = (typeof SHARDS)[number];
export const DEFAULT_SHARD: Shard = "forest";
export const SHARD_LABELS: Record<Shard, string> = { forest: "Forest", caves: "Caves" };
/**
 * The key of the flag that lets a distance use the shard's teleporter links: the forest's wormholes, the caves'
 * tentacle pillars.
 */
export const LINKS_KEY = { forest: "wormholes", caves: "pillars" } as const satisfies Record<Shard, string>;

export const PLATFORMS = ["windows", "linux"] as const;
export type Platform = (typeof PLATFORMS)[number];
export const DEFAULT_PLATFORM: Platform = "windows";
export const PLATFORM_LABELS: Record<Platform, string> = { windows: "Windows", linux: "Linux" };


export type PrefabSet = string | string[];
export type TileSet = string | string[];
export type SetPieceBound = number | [number, number];

export interface TaskFilter {
    required?: string[];
    excluded?: string[];
}

export type PrefabSwaps = Partial<Record<SwapCategory, string>>;

export interface SetPieceRule {
    tasks?: string[];
    required?: Record<string, SetPieceBound>;
    /** Names of `required` counted only where the generated world placed them (forest only). */
    placed?: string[];
}

/** Holds when any of its rules holds and, with `total`, the counts of all its rules' set pieces add up to it. */
export interface SetPieceGroup {
    any: SetPieceRule[];
    total?: SetPieceBound;
}

export type SetPieceItem = SetPieceRule | SetPieceGroup;

/** The rules of set piece items, with each group's rules in its place. */
export const setPieceRules = (items: SetPieceItem[]): SetPieceRule[] =>
    items.flatMap((item) => ("any" in item ? item.any : [item]));

/**
 * A rule's travel options: its metric and whether it may use the links, as `wormholes` in the forest and `pillars`
 * in the caves.
 */
export interface TravelFields {
    metric?: Metric;
    wormholes?: boolean;
    pillars?: boolean;
}

export interface Near extends TravelFields {
    prefab: PrefabSet;
    within: number;
}

export interface CountRule {
    prefab: PrefabSet;
    min?: number;
    max?: number;
    near?: Near;
}

export interface DistanceRule extends TravelFields {
    from: PrefabSet;
    to: PrefabSet;
    min?: number;
    max?: number;
}

export interface TileRule {
    from: TileSet;
    to: TileSet;
    max: number;
}

export interface BridgeRule {
    min?: number;
    max?: number;
}

export interface RouteRule extends TravelFields {
    from: PrefabSet;
    visit: PrefabSet[];
    to?: PrefabSet;
    max: number;
    order?: RouteOrder;
}

export interface Criterion {
    passive?: boolean;
    tasks?: TaskFilter;
    prefab_swaps?: PrefabSwaps;
    setpieces?: SetPieceItem[];
    counts?: CountRule[];
    distances?: DistanceRule[];
    tiles?: TileRule[];
    bridges?: BridgeRule[];
    routes?: RouteRule[];
}

export interface SeedfinderConfig {
    version: typeof CONFIG_VERSION;
    shard?: Shard;
    platform?: Platform;
    criteria?: Criterion[];
}

/** `timings` runs the search with `--verbose-timings`. */
export interface JobRequest {
    config: SeedfinderConfig;
    wanted: number;
    maxCost: number;
    startSeed?: number;
    timings?: boolean;
}
