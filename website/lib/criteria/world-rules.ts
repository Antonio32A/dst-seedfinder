import { fixedCount, sampleCounts, setLabel } from "@/lib/catalog/prefab-sets";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import { LAND_TILES } from "@/lib/catalog/world";
import type { GameBuild } from "@/lib/config/game-builds";
import {
    type BridgeRule,
    type CountRule,
    DEFAULT_LINKS,
    DEFAULT_METRIC,
    DEFAULT_ROUTE_ORDER,
    type DistanceRule,
    type Filter,
    type IslandRule,
    LINKS_KEY,
    MAX_DISTANCE,
    MAX_PREFAB_IDS,
    MAX_ROUTE_STOPS,
    MAX_RULES_PER_SECTION,
    MAX_TILE_NAMES,
    MAX_UINT32,
    type Metric,
    METRICS,
    type PrefabSet,
    type RouteOrder,
    type RouteRule,
    type Shard,
    type TileRule,
    type TravelFields,
    WORLD_UNITS_PER_TILE
} from "@/lib/config/seedfinder-config";
import { asRecord } from "@/lib/records";
import { asArray, asStrings, newKey, nonEmpty } from "./state-helpers";

export type WorldCountMode = "atLeast" | "atMost" | "exactly" | "between" | "none";
export type DistanceMode = "within" | "atLeast" | "between";
export type AreaMode = "atMost" | "atLeast" | "between";

export interface Travel {
    metric: Metric;
    /**
     * Whether the rule may use the shard's teleporter links: wormholes in the forest, tentacle pillars in the caves.
     */
    links: boolean;
}

export interface NearRow extends Travel {
    prefabs: string[];
    within: number;
}

export interface CountRow {
    key: string;
    prefabs: string[];
    mode: WorldCountMode;
    min: number;
    max: number;
    near: NearRow | null;
}

export interface DistanceRow extends Travel {
    key: string;
    from: string[];
    to: string[];
    mode: DistanceMode;
    min: number;
    max: number;
}

export interface TileRow {
    key: string;
    from: string[];
    to: string[];
    max: number;
}

export interface BridgeRow {
    key: string;
    min: number;
    max: number | null;
}

export interface RouteStop {
    key: string;
    prefabs: string[];
}

export interface IslandRow {
    key: string;
    at: string[];
    mode: AreaMode;
    min: number;
    max: number;
    links: boolean;
}

export interface RouteRow extends Travel {
    key: string;
    from: string[];
    stops: RouteStop[];
    to: string[];
    roundTrip: boolean;
    order: RouteOrder;
    max: number;
}

export interface WorldRows {
    counts: CountRow[];
    distances: DistanceRow[];
    tiles: TileRow[];
    bridges: BridgeRow[];
    routes: RouteRow[];
    islands: IslandRow[];
}

export type WorldSection = keyof WorldRows;

export interface WorldIssue {
    severity: "error" | "warning";
    message: string;
}

export const MAP_SIZE_TILES = 425;
export const MAX_TILE_STEPS = 2 * MAP_SIZE_TILES;

export const WORLD_COUNT_MODES: { id: WorldCountMode; label: string }[] = [
    { id: "atLeast", label: "At least" },
    { id: "atMost", label: "At most" },
    { id: "exactly", label: "Exactly" },
    { id: "between", label: "Between" },
    { id: "none", label: "None" }
];

export const COUNT_FLOOR: Record<WorldCountMode, number> = { atLeast: 1, atMost: 1, exactly: 1, between: 0, none: 0 };

export const DISTANCE_MODES: { id: DistanceMode; label: string }[] = [
    { id: "within", label: "Within" },
    { id: "atLeast", label: "At least" },
    { id: "between", label: "Between" }
];

export const AREA_MODES: { id: AreaMode; label: string }[] = [
    { id: "atMost", label: "At most" },
    { id: "atLeast", label: "At least" },
    { id: "between", label: "Between" }
];

/** Fewer land tiles than the forest's mainland (40,000 to 50,000) and more than the Lunar island (2,000 to 4,000). */
export const OFF_MAINLAND_TILES = 30_000;

const tiles = (count: number) => count * WORLD_UNITS_PER_TILE;
const DEFAULT_TRAVEL: Travel = { metric: DEFAULT_METRIC, links: DEFAULT_LINKS };

/** The shard of a build whose worlds a filter checks. */
export interface WorldKind {
    shard: Shard;
    build: GameBuild;
}

const spawnOf = ({ shard, build }: WorldKind) => shardCatalog(shard, build).spawn;

export const newNear = (world: WorldKind): NearRow => ({
    ...DEFAULT_TRAVEL,
    prefabs: [spawnOf(world)],
    within: tiles(100)
});

export const newRouteStop = (prefabs: string[] = []): RouteStop => ({ key: newKey(), prefabs });

export const NEW_WORLD_ROW: { [S in WorldSection]: (world: WorldKind) => WorldRows[S][number] } = {
    counts: () => ({ key: newKey(), prefabs: [], mode: "atLeast", min: 1, max: 1, near: null }),
    distances: (world) => ({
        ...DEFAULT_TRAVEL,
        key: newKey(),
        from: [spawnOf(world)],
        to: [],
        mode: "within",
        min: 0,
        max: tiles(100)
    }),
    tiles: () => ({ key: newKey(), from: [], to: [], max: 3 }),
    bridges: () => ({ key: newKey(), min: tiles(60), max: null }),
    routes: (world) => ({
        ...DEFAULT_TRAVEL,
        key: newKey(),
        from: [spawnOf(world)],
        stops: [newRouteStop()],
        to: [],
        roundTrip: true,
        order: DEFAULT_ROUTE_ORDER,
        max: tiles(500)
    }),
    islands: (world) => ({
        key: newKey(),
        at: [spawnOf(world)],
        mode: "atMost",
        min: 0,
        max: OFF_MAINLAND_TILES,
        links: DEFAULT_LINKS
    })
};

export const worldRowCount = (rows: WorldRows): number =>
    rows.counts.length + rows.distances.length + rows.tiles.length + rows.bridges.length + rows.routes.length
    + rows.islands.length;

const asSet = (ids: string[]): PrefabSet => (ids.length === 1 ? ids[0] : ids);

const travelFields = ({ metric, links }: Travel, shard: Shard): TravelFields => ({
    ...(metric === DEFAULT_METRIC ? {} : { metric }),
    ...(links === DEFAULT_LINKS ? {} : { [LINKS_KEY[shard]]: links })
});

const COUNT_BOUNDS: Record<WorldCountMode, (row: CountRow) => { min?: number; max?: number }> = {
    atLeast: (row) => (row.min > 0 ? { min: row.min } : {}),
    atMost: (row) => ({ max: row.max }),
    exactly: (row) => ({ min: row.min, max: row.min }),
    between: (row) => ({ min: row.min, max: row.max }),
    none: () => ({ max: 0 })
};

const DISTANCE_BOUNDS: Record<DistanceMode, (row: DistanceRow) => { min?: number; max?: number }> = {
    within: (row) => ({ max: row.max }),
    atLeast: (row) => (row.min > 0 ? { min: row.min } : {}),
    between: (row) => ({ min: row.min, max: row.max })
};

const AREA_BOUNDS: Record<AreaMode, (row: IslandRow) => { min?: number; max?: number }> = {
    atMost: (row) => ({ max: row.max }),
    atLeast: (row) => (row.min > 0 ? { min: row.min } : {}),
    between: (row) => ({ min: row.min, max: row.max })
};

const filled = (...sets: string[][]) => sets.every((set) => set.length > 0);

const routeEnd = (row: RouteRow): string[] => (row.roundTrip ? row.from : row.to);

const countRule = (row: CountRow, shard: Shard): CountRule[] =>
    filled(row.prefabs, ...(row.near ? [row.near.prefabs] : []))
        ? [
            {
                prefab: asSet(row.prefabs),
                ...COUNT_BOUNDS[row.mode](row),
                ...(row.near ? {
                    near: {
                        prefab: asSet(row.near.prefabs),
                        within: row.near.within, ...travelFields(row.near, shard)
                    }
                } : {})
            }
        ]
        : [];

const distanceRule = (row: DistanceRow, shard: Shard): DistanceRule[] =>
    filled(row.from, row.to) ? [{
        from: asSet(row.from),
        to: asSet(row.to), ...DISTANCE_BOUNDS[row.mode](row), ...travelFields(row, shard)
    }] : [];

const tileRule = (row: TileRow, _shard: Shard): TileRule[] => (filled(row.from, row.to) ? [{
    from: asSet(row.from),
    to: asSet(row.to),
    max: row.max
}] : []);

const bridgeRule = ({
                        min,
                        max
                    }: BridgeRow): BridgeRule => ({ ...(min > 0 ? { min } : {}), ...(max === null ? {} : { max }) });

const routeRule = (row: RouteRow, shard: Shard): RouteRule[] => {
    const end = routeEnd(row);
    if (!filled(row.from, ...row.stops.map((stop) => stop.prefabs)) || row.stops.length === 0) return [];
    return [
        {
            from: asSet(row.from),
            visit: row.stops.map((stop) => asSet(stop.prefabs)),
            ...(end.length > 0 ? { to: asSet(end) } : {}),
            max: row.max,
            ...(row.order === DEFAULT_ROUTE_ORDER ? {} : { order: row.order }),
            ...travelFields(row, shard)
        }
    ];
};

const islandRule = (row: IslandRow, shard: Shard): IslandRule[] => (filled(row.at) ? [{
    at: asSet(row.at),
    ...AREA_BOUNDS[row.mode](row),
    ...(row.links === DEFAULT_LINKS ? {} : { [LINKS_KEY[shard]]: row.links })
}] : []);

export function worldSections(rows: WorldRows, shard: Shard): Filter {
    return {
        counts: nonEmpty(rows.counts.flatMap((row) => countRule(row, shard))),
        distances: nonEmpty(rows.distances.flatMap((row) => distanceRule(row, shard))),
        tiles: nonEmpty(rows.tiles.flatMap((row) => tileRule(row, shard))),
        bridges: nonEmpty(rows.bridges.map(bridgeRule)),
        routes: nonEmpty(rows.routes.flatMap((row) => routeRule(row, shard))),
        islands: nonEmpty(rows.islands.flatMap((row) => islandRule(row, shard)))
    };
}

const LAND_TILE_NAMES: ReadonlySet<string> = new Set(LAND_TILES.map((tile) => tile.name));

const namesIn = (value: unknown, known: (name: string) => boolean, cap: number): string[] => {
    const names = typeof value === "string" ? [value] : asStrings(value);
    return [...new Set(names.filter(known))].slice(0, cap);
};

const prefabIds = (value: unknown, { shard, build }: WorldKind) =>
    namesIn(value, (id) => shardCatalog(shard, build).byId.has(id), MAX_PREFAB_IDS);
const tileNames = (value: unknown) => namesIn(value, (name) => LAND_TILE_NAMES.has(name), MAX_TILE_NAMES);

const numberIn = (value: unknown, max: number, integer: boolean): number | undefined =>
    typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= max && (!integer || Number.isInteger(value)) ? value : undefined;

const distanceOf = (value: unknown) => numberIn(value, MAX_DISTANCE, false);
const uint32Of = (value: unknown) => numberIn(value, MAX_UINT32, true);

const travelOf = (record: Record<string, unknown>, { shard }: WorldKind): Travel => ({
    metric: METRICS.find((metric) => metric === record.metric) ?? DEFAULT_METRIC,
    links: record[LINKS_KEY[shard]] === true
});

function countModeOf(min: number | undefined, max: number | undefined): WorldCountMode {
    if (max === undefined) return "atLeast";
    if (max === 0 && !min) return "none";
    if (min === undefined) return "atMost";
    return min === max ? "exactly" : "between";
}

function distanceModeOf(min: number | undefined, max: number | undefined): DistanceMode {
    if (max === undefined) return "atLeast";
    return min === undefined ? "within" : "between";
}

function areaModeOf(min: number | undefined, max: number | undefined): AreaMode {
    if (max === undefined) return "atLeast";
    return min === undefined ? "atMost" : "between";
}

function nearOf(value: unknown, world: WorldKind): NearRow | null | undefined {
    if (value === undefined) return null;
    const record = asRecord(value);
    const prefabs = prefabIds(record.prefab, world);
    const within = distanceOf(record.within);
    return prefabs.length > 0 && within !== undefined ? { ...travelOf(record, world), prefabs, within } : undefined;
}

function countRowOf(value: unknown, world: WorldKind): CountRow[] {
    const record = asRecord(value);
    const prefabs = prefabIds(record.prefab, world);
    const near = nearOf(record.near, world);
    const [min, max] = [uint32Of(record.min), uint32Of(record.max)];
    if (prefabs.length === 0 || near === undefined) return [];
    return [{
        key: newKey(),
        prefabs,
        mode: countModeOf(min, max),
        min: min ?? 0,
        max: max ?? Math.max(min ?? 0, 1),
        near
    }];
}

function distanceRowOf(value: unknown, world: WorldKind): DistanceRow[] {
    const record = asRecord(value);
    const [from, to] = [prefabIds(record.from, world), prefabIds(record.to, world)];
    const [min, max] = [distanceOf(record.min), distanceOf(record.max)];
    if (!filled(from, to)) return [];
    return [{
        ...travelOf(record, world),
        key: newKey(),
        from,
        to,
        mode: distanceModeOf(min, max),
        min: min ?? 0,
        max: max ?? Math.max(min ?? 0, tiles(100))
    }];
}

function tileRowOf(value: unknown): TileRow[] {
    const record = asRecord(value);
    const [from, to, max] = [tileNames(record.from), tileNames(record.to), uint32Of(record.max)];
    return filled(from, to) && max !== undefined ? [{ key: newKey(), from, to, max }] : [];
}

function bridgeRowOf(value: unknown): BridgeRow[] {
    const record = asRecord(value);
    const [min, max] = [distanceOf(record.min), distanceOf(record.max)];
    return [{ key: newKey(), min: min ?? 0, max: max ?? null }];
}

function routeRowOf(value: unknown, world: WorldKind): RouteRow[] {
    const record = asRecord(value);
    const from = prefabIds(record.from, world);
    const stops = asArray(record.visit).slice(0, MAX_ROUTE_STOPS).map((stop) => newRouteStop(prefabIds(stop, world)));
    const to = prefabIds(record.to, world);
    const max = distanceOf(record.max);
    if (!filled(from, ...stops.map((stop) => stop.prefabs)) || stops.length === 0 || max === undefined) return [];
    const roundTrip = to.length > 0 && to.length === from.length && to.every((id) => from.includes(id));
    const order = record.order === "fixed" ? "fixed" : DEFAULT_ROUTE_ORDER;
    return [{ ...travelOf(record, world), key: newKey(), from, stops, to: roundTrip ? [] : to, roundTrip, order, max }];
}

function islandRowOf(value: unknown, world: WorldKind): IslandRow[] {
    const record = asRecord(value);
    const at = prefabIds(record.at, world);
    const [min, max] = [uint32Of(record.min), uint32Of(record.max)];
    if (!filled(at)) return [];
    return [{
        key: newKey(),
        at,
        mode: areaModeOf(min, max),
        min: min ?? 0,
        max: max ?? Math.max(min ?? 0, OFF_MAINLAND_TILES),
        links: travelOf(record, world).links
    }];
}

const rowsOf = <T>(value: unknown, world: WorldKind, parse: (item: unknown, world: WorldKind) => T[]): T[] =>
    asArray(value).slice(0, MAX_RULES_PER_SECTION).flatMap((item) => parse(item, world));

export function worldRowsOf(filter: Record<string, unknown>, world: WorldKind): WorldRows {
    return {
        counts: rowsOf(filter.counts, world, countRowOf),
        distances: rowsOf(filter.distances, world, distanceRowOf),
        tiles: rowsOf(filter.tiles, world, tileRowOf),
        bridges: rowsOf(filter.bridges, world, bridgeRowOf),
        routes: rowsOf(filter.routes, world, routeRowOf),
        islands: rowsOf(filter.islands, world, islandRowOf)
    };
}

type RowCheck<T> = (row: T, label: string, world: WorldKind) => WorldIssue | undefined;

const error = (message: string): WorldIssue => ({ severity: "error", message });
const warning = (message: string): WorldIssue => ({ severity: "warning", message });

const COUNT_CHECKS: RowCheck<CountRow>[] = [
    (row, label) => (row.prefabs.length === 0 ? error(`${label} needs something to count.`) : undefined),
    (row, label) => (row.near?.prefabs.length === 0 ? error(`${label} needs something to be near.`) : undefined),
    (row, label) => (row.mode === "between" && row.min > row.max ? error(`${label}: minimum is above maximum.`) : undefined),
    (row, label, { shard, build }) => {
        if (row.near || row.prefabs.length === 0) return undefined;
        const { min = 0, max = Infinity } = COUNT_BOUNDS[row.mode](row);
        const [sampleMin, , sampleMax] = sampleCounts(row.prefabs, shard, build);
        const fixed = fixedCount(row.prefabs, shard, build);
        const name = setLabel(row.prefabs, shard, build);
        if (min > sampleMax || max < sampleMin)
            return warning(`${label} rarely matches: sample worlds have ${sampleMin === sampleMax ? sampleMin : `${sampleMin}-${sampleMax}`} ${name}.`);
        return fixed !== undefined ? warning(`every sample world has exactly ${fixed} ${name}, so ${label} always matches. Remove it or count only ones near something.`) : undefined;
    }
];

const DISTANCE_CHECKS: RowCheck<DistanceRow>[] = [
    (row, label) => (filled(row.from, row.to) ? undefined : error(`${label} needs a start and an end.`)),
    (row, label) => (row.mode === "between" && row.min > row.max ? error(`${label}: minimum is above maximum.`) : undefined)
];

const TILE_CHECKS: RowCheck<TileRow>[] = [(row, label) => (filled(row.from, row.to) ? undefined : error(`${label} needs turf on both sides.`))];

const BRIDGE_CHECKS: RowCheck<BridgeRow>[] = [
    (row, label) => (row.max !== null && row.min > row.max ? error(`${label}: minimum is above maximum.`) : undefined)
];

const ISLAND_CHECKS: RowCheck<IslandRow>[] = [
    (row, label) => (filled(row.at) ? undefined : error(`${label} needs something to measure from.`)),
    (row, label) => (row.mode === "between" && row.min > row.max ? error(`${label}: minimum is above maximum.`) : undefined)
];

const ROUTE_CHECKS: RowCheck<RouteRow>[] = [
    (row, label) => (row.from.length === 0 ? error(`${label} needs a start.`) : undefined),
    (row, label) => (row.stops.some((stop) => stop.prefabs.length === 0) ? error(`${label} has an empty stop.`) : undefined),
    (row, label, { shard, build }) => {
        const endpoints = new Set([...row.from, ...routeEnd(row)]);
        const stopIds = row.stops.flatMap((stop) => [...new Set(stop.prefabs)]);
        const clash = stopIds.find((id, index) => endpoints.has(id) || stopIds.indexOf(id) !== index);
        if (clash === undefined) return undefined;
        const place = endpoints.has(clash) ? "is both a stop and the start or end" : "is in more than one stop";
        return error(`${label}: ${setLabel([clash], shard, build)} ${place}.`);
    }
];

const checkRows = <T>(rows: T[], noun: string, checks: RowCheck<T>[], world: WorldKind): WorldIssue[] =>
    rows.flatMap((row, index) => checks.flatMap((check) => check(row, `${noun} ${index + 1}`, world) ?? []));

export function worldIssues(rows: WorldRows, world: WorldKind): WorldIssue[] {
    return [
        ...checkRows(rows.counts, "count", COUNT_CHECKS, world),
        ...checkRows(rows.distances, "distance", DISTANCE_CHECKS, world),
        ...checkRows(rows.tiles, "turf rule", TILE_CHECKS, world),
        ...checkRows(rows.bridges, "turf bridge", BRIDGE_CHECKS, world),
        ...checkRows(rows.routes, "route", ROUTE_CHECKS, world),
        ...checkRows(rows.islands, "island", ISLAND_CHECKS, world)
    ];
}

interface Carried<T> {
    rows: T[];
    dropped: number;
}

/** The ids that exist on the other shard or build, the spawn becoming that shard's spawn. */
const carriedIds = (ids: string[], from: WorldKind, to: WorldKind): string[] => {
    const { byId } = shardCatalog(to.shard, to.build);
    const mapped = ids.map((id) => (id === spawnOf(from) ? spawnOf(to) : id)).filter((id) => byId.has(id));
    return [...new Set(mapped)];
};

const carriedSet = (ids: string[], from: WorldKind, to: WorldKind): { ids: string[]; lost: number } => {
    const carried = carriedIds(ids, from, to);
    return { ids: carried, lost: new Set(ids).size - carried.length };
};

/**
 * One row on the other shard: the prefabs it has there, or nothing when one of its sets ends up empty (the row is then
 * counted as one lost pick). A row keeps its tiles and travel options.
 */
function carryRow<T>(row: T, sets: string[][], from: WorldKind, to: WorldKind, rebuild: (carried: string[][]) => T): {
    row?: T;
    lost: number;
} {
    const carried = sets.map((ids) => carriedSet(ids, from, to));
    const survives = carried.every(({ ids }) => ids.length > 0);
    return survives ? {
        row: rebuild(carried.map(({ ids }) => ids)),
        lost: carried.reduce((sum, { lost }) => sum + lost, 0)
    } : { lost: 1 };
}

const carry = <T>(rows: T[], one: (row: T) => { row?: T; lost: number }): Carried<T> => {
    const results = rows.map(one);
    return {
        rows: results.flatMap(({ row }) => (row ? [row] : [])),
        dropped: results.reduce((sum, { lost }) => sum + lost, 0)
    };
};

/**
 * The world rows on another shard or build: every prefab that exists there stays (the spawn becomes the other shard's
 * spawn), a rule whose prefabs don't exist there is dropped. `dropped` counts the picks and rules lost.
 */
export function worldRowsFor(rows: WorldRows, from: WorldKind, to: WorldKind): { rows: WorldRows; dropped: number } {
    if (shardCatalog(from.shard, from.build) === shardCatalog(to.shard, to.build)) return { rows, dropped: 0 };
    const counts = carry(rows.counts, (row) => {
        const near = row.near;
        return carryRow(row, [row.prefabs, ...(near ? [near.prefabs] : [])], from, to, ([prefabs, nearPrefabs]) => ({
            ...row,
            prefabs,
            near: near ? { ...near, prefabs: nearPrefabs } : null
        }));
    });
    const distances = carry(rows.distances, (row) => carryRow(row, [row.from, row.to], from, to, ([a, b]) => ({
        ...row,
        from: a,
        to: b
    })));
    const routes = carry(rows.routes, (row) => {
        const prefabSets = [row.from, ...row.stops.map((stop) => stop.prefabs)];
        const required = carryRow(row, prefabSets, from, to, ([start, ...stops]) => ({
            ...row,
            from: start,
            stops: row.stops.map((stop, index) => ({ ...stop, prefabs: stops[index] }))
        }));
        const end = carriedSet(row.to, from, to);
        return required.row ? { row: { ...required.row, to: end.ids }, lost: required.lost + end.lost } : required;
    });
    const islands = carry(rows.islands, (row) => carryRow(row, [row.at], from, to, ([at]) => ({ ...row, at })));
    return {
        rows: {
            counts: counts.rows,
            distances: distances.rows,
            tiles: rows.tiles,
            bridges: rows.bridges,
            routes: routes.rows,
            islands: islands.rows
        },
        dropped: counts.dropped + distances.dropped + routes.dropped + islands.dropped
    };
}

/** Why `id` can't join `part` of the route, or undefined when it can. */
export function routeConflict(row: RouteRow, part: "ends" | number): (id: string) => string | undefined {
    const parts = [
        { ids: [...row.from, ...routeEnd(row)], name: "the start or end", own: part === "ends" },
        ...row.stops.map((stop, index) => ({ ids: stop.prefabs, name: `stop ${index + 1}`, own: part === index }))
    ];
    const others = parts.filter((other) => !other.own);
    return (id) => {
        const taken = others.find((other) => other.ids.includes(id));
        return taken && `already ${taken.name}`;
    };
}
