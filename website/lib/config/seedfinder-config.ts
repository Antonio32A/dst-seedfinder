import type { SwapCategory } from "@/lib/catalog/level-types";

export const CONFIG_VERSION = 1;

export const MAX_UINT32 = 4_294_967_295;
export const MAX_DISTANCE = 1_000_000;
export const WORLD_UNITS_PER_TILE = 4;

export const MAX_CRITERIA = 8;
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
export const DEFAULT_WORMHOLES = false;

export const ROUTE_ORDERS = ["any", "fixed"] as const;
export type RouteOrder = (typeof ROUTE_ORDERS)[number];
export const DEFAULT_ROUTE_ORDER: RouteOrder = "any";

export const SHARDS = ["forest", "caves"] as const;
export type Shard = (typeof SHARDS)[number];
export const DEFAULT_SHARD: Shard = "forest";
export const SHARD_LABELS: Record<Shard, string> = { forest: "Forest", caves: "Caves" };

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
}

export interface Near {
    prefab: PrefabSet;
    within: number;
    metric?: Metric;
    wormholes?: boolean;
}

export interface CountRule {
    prefab: PrefabSet;
    min?: number;
    max?: number;
    near?: Near;
}

export interface DistanceRule {
    from: PrefabSet;
    to: PrefabSet;
    min?: number;
    max?: number;
    metric?: Metric;
    wormholes?: boolean;
}

export interface TileRule {
    from: TileSet;
    to: TileSet;
    max: number;
}

export interface RouteRule {
    from: PrefabSet;
    visit: PrefabSet[];
    to?: PrefabSet;
    max: number;
    order?: RouteOrder;
    metric?: Metric;
    wormholes?: boolean;
}

export interface Criterion {
    passive?: boolean;
    tasks?: TaskFilter;
    prefab_swaps?: PrefabSwaps;
    setpieces?: SetPieceRule[];
    counts?: CountRule[];
    distances?: DistanceRule[];
    tiles?: TileRule[];
    routes?: RouteRule[];
}

export interface SeedfinderConfig {
    version: typeof CONFIG_VERSION;
    shard?: Shard;
    platform?: Platform;
    criteria?: Criterion[];
}

export interface JobRequest {
    config: SeedfinderConfig;
    wanted: number;
    maxCost: number;
    startSeed?: number;
}
