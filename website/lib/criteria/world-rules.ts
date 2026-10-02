import { fixedCount, sampleCounts, setLabel } from "@/lib/catalog/prefab-sets";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import {
    type CountRule,
    type Criterion,
    DEFAULT_LINKS,
    DEFAULT_METRIC,
    DEFAULT_ROUTE_ORDER,
    type DistanceRule,
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

export interface Travel {
    metric: Metric;
    /** Whether the rule may use the shard's teleporter links: wormholes in the forest, tentacle pillars in the caves. */
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

export interface RouteStop {
    key: string;
    prefabs: string[];
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
    routes: RouteRow[];
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

const tiles = (count: number) => count * WORLD_UNITS_PER_TILE;
const DEFAULT_TRAVEL: Travel = { metric: DEFAULT_METRIC, links: DEFAULT_LINKS };

const spawnOf = (shard: Shard) => shardCatalog(shard).spawn;

export const newNear = (shard: Shard): NearRow => ({ ...DEFAULT_TRAVEL, prefabs: [spawnOf(shard)], within: tiles(100) });

export const newRouteStop = (prefabs: string[] = []): RouteStop => ({ key: newKey(), prefabs });

export const NEW_WORLD_ROW: { [S in WorldSection]: (shard: Shard) => WorldRows[S][number] } = {
    counts: () => ({ key: newKey(), prefabs: [], mode: "atLeast", min: 1, max: 1, near: null }),
    distances: (shard) => ({
        ...DEFAULT_TRAVEL,
        key: newKey(),
        from: [spawnOf(shard)],
        to: [],
        mode: "within",
        min: 0,
        max: tiles(100)
    }),
    tiles: () => ({ key: newKey(), from: [], to: [], max: 3 }),
    routes: (shard) => ({
        ...DEFAULT_TRAVEL,
        key: newKey(),
        from: [spawnOf(shard)],
        stops: [newRouteStop()],
        to: [],
        roundTrip: true,
        order: DEFAULT_ROUTE_ORDER,
        max: tiles(500)
    })
};

export const worldRowCount = (rows: WorldRows): number =>
    rows.counts.length + rows.distances.length + rows.tiles.length + rows.routes.length;

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

export function worldSections(rows: WorldRows, shard: Shard): Pick<Criterion, "counts" | "distances" | "tiles" | "routes"> {
    return {
        counts: nonEmpty(rows.counts.flatMap((row) => countRule(row, shard))),
        distances: nonEmpty(rows.distances.flatMap((row) => distanceRule(row, shard))),
        tiles: nonEmpty(rows.tiles.flatMap((row) => tileRule(row, shard))),
        routes: nonEmpty(rows.routes.flatMap((row) => routeRule(row, shard)))
    };
}

const LAND_TILE_NAMES: ReadonlySet<string> = new Set(shardCatalog("forest").landTiles.map((tile) => tile.name));

const namesIn = (value: unknown, known: (name: string) => boolean, cap: number): string[] => {
    const names = typeof value === "string" ? [value] : asStrings(value);
    return [...new Set(names.filter(known))].slice(0, cap);
};

const prefabIds = (value: unknown, shard: Shard) => namesIn(value, (id) => shardCatalog(shard).byId.has(id), MAX_PREFAB_IDS);
const tileNames = (value: unknown) => namesIn(value, (name) => LAND_TILE_NAMES.has(name), MAX_TILE_NAMES);

const numberIn = (value: unknown, max: number, integer: boolean): number | undefined =>
    typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= max && (!integer || Number.isInteger(value)) ? value : undefined;

const distanceOf = (value: unknown) => numberIn(value, MAX_DISTANCE, false);
const uint32Of = (value: unknown) => numberIn(value, MAX_UINT32, true);

const travelOf = (record: Record<string, unknown>, shard: Shard): Travel => ({
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

function nearOf(value: unknown, shard: Shard): NearRow | null | undefined {
    if (value === undefined) return null;
    const record = asRecord(value);
    const prefabs = prefabIds(record.prefab, shard);
    const within = distanceOf(record.within);
    return prefabs.length > 0 && within !== undefined ? { ...travelOf(record, shard), prefabs, within } : undefined;
}

function countRowOf(value: unknown, shard: Shard): CountRow[] {
    const record = asRecord(value);
    const prefabs = prefabIds(record.prefab, shard);
    const near = nearOf(record.near, shard);
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

function distanceRowOf(value: unknown, shard: Shard): DistanceRow[] {
    const record = asRecord(value);
    const [from, to] = [prefabIds(record.from, shard), prefabIds(record.to, shard)];
    const [min, max] = [distanceOf(record.min), distanceOf(record.max)];
    if (!filled(from, to)) return [];
    return [{
        ...travelOf(record, shard),
        key: newKey(),
        from,
        to,
        mode: distanceModeOf(min, max),
        min: min ?? 0,
        max: max ?? Math.max(min ?? 0, tiles(100))
    }];
}

function tileRowOf(value: unknown, _shard: Shard): TileRow[] {
    const record = asRecord(value);
    const [from, to, max] = [tileNames(record.from), tileNames(record.to), uint32Of(record.max)];
    return filled(from, to) && max !== undefined ? [{ key: newKey(), from, to, max }] : [];
}

function routeRowOf(value: unknown, shard: Shard): RouteRow[] {
    const record = asRecord(value);
    const from = prefabIds(record.from, shard);
    const stops = asArray(record.visit).slice(0, MAX_ROUTE_STOPS).map((stop) => newRouteStop(prefabIds(stop, shard)));
    const to = prefabIds(record.to, shard);
    const max = distanceOf(record.max);
    if (!filled(from, ...stops.map((stop) => stop.prefabs)) || stops.length === 0 || max === undefined) return [];
    const roundTrip = to.length > 0 && to.length === from.length && to.every((id) => from.includes(id));
    const order = record.order === "fixed" ? "fixed" : DEFAULT_ROUTE_ORDER;
    return [{ ...travelOf(record, shard), key: newKey(), from, stops, to: roundTrip ? [] : to, roundTrip, order, max }];
}

const rowsOf = <T>(value: unknown, shard: Shard, parse: (item: unknown, shard: Shard) => T[]): T[] =>
    asArray(value).slice(0, MAX_RULES_PER_SECTION).flatMap((item) => parse(item, shard));

export function worldRowsOf(criterion: Record<string, unknown>, shard: Shard): WorldRows {
    return {
        counts: rowsOf(criterion.counts, shard, countRowOf),
        distances: rowsOf(criterion.distances, shard, distanceRowOf),
        tiles: rowsOf(criterion.tiles, shard, tileRowOf),
        routes: rowsOf(criterion.routes, shard, routeRowOf)
    };
}

type RowCheck<T> = (row: T, label: string, shard: Shard) => WorldIssue | undefined;

const error = (message: string): WorldIssue => ({ severity: "error", message });
const warning = (message: string): WorldIssue => ({ severity: "warning", message });

const COUNT_CHECKS: RowCheck<CountRow>[] = [
    (row, label) => (row.prefabs.length === 0 ? error(`${label} needs something to count.`) : undefined),
    (row, label) => (row.near?.prefabs.length === 0 ? error(`${label} needs something to be near.`) : undefined),
    (row, label) => (row.mode === "between" && row.min > row.max ? error(`${label}: minimum is above maximum.`) : undefined),
    (row, label, shard) => {
        if (row.near || row.prefabs.length === 0) return undefined;
        const { min = 0, max = Infinity } = COUNT_BOUNDS[row.mode](row);
        const [sampleMin, , sampleMax] = sampleCounts(row.prefabs, shard);
        const fixed = fixedCount(row.prefabs, shard);
        const name = setLabel(row.prefabs, shard);
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

const ROUTE_CHECKS: RowCheck<RouteRow>[] = [
    (row, label) => (row.from.length === 0 ? error(`${label} needs a start.`) : undefined),
    (row, label) => (row.stops.some((stop) => stop.prefabs.length === 0) ? error(`${label} has an empty stop.`) : undefined),
    (row, label, shard) => {
        const endpoints = new Set([...row.from, ...routeEnd(row)]);
        const stopIds = row.stops.flatMap((stop) => [...new Set(stop.prefabs)]);
        const clash = stopIds.find((id, index) => endpoints.has(id) || stopIds.indexOf(id) !== index);
        if (clash === undefined) return undefined;
        const place = endpoints.has(clash) ? "is both a stop and the start or end" : "is in more than one stop";
        return error(`${label}: ${setLabel([clash], shard)} ${place}.`);
    }
];

const checkRows = <T>(rows: T[], noun: string, checks: RowCheck<T>[], shard: Shard): WorldIssue[] =>
    rows.flatMap((row, index) => checks.flatMap((check) => check(row, `${noun} ${index + 1}`, shard) ?? []));

export function worldIssues(rows: WorldRows, shard: Shard): WorldIssue[] {
    return [
        ...checkRows(rows.counts, "count", COUNT_CHECKS, shard),
        ...checkRows(rows.distances, "distance", DISTANCE_CHECKS, shard),
        ...checkRows(rows.tiles, "turf rule", TILE_CHECKS, shard),
        ...checkRows(rows.routes, "route", ROUTE_CHECKS, shard)
    ];
}

interface Carried<T> {
    rows: T[];
    dropped: number;
}

/** The ids that exist on the other shard, the spawn becoming that shard's spawn. */
const carriedIds = (ids: string[], from: Shard, to: Shard): string[] => {
    const { byId } = shardCatalog(to);
    const mapped = ids.map((id) => (id === spawnOf(from) ? spawnOf(to) : id)).filter((id) => byId.has(id));
    return [...new Set(mapped)];
};

const carriedSet = (ids: string[], from: Shard, to: Shard): { ids: string[]; lost: number } => {
    const carried = carriedIds(ids, from, to);
    return { ids: carried, lost: new Set(ids).size - carried.length };
};

/**
 * One row on the other shard: the prefabs it has there, or nothing when one of its sets ends up empty (the row is then
 * counted as one lost pick). A row keeps its tiles and travel options.
 */
function carryRow<T>(row: T, sets: string[][], from: Shard, to: Shard, rebuild: (carried: string[][]) => T): { row?: T; lost: number } {
    const carried = sets.map((ids) => carriedSet(ids, from, to));
    const survives = carried.every(({ ids }) => ids.length > 0);
    return survives ? { row: rebuild(carried.map(({ ids }) => ids)), lost: carried.reduce((sum, { lost }) => sum + lost, 0) } : { lost: 1 };
}

const carry = <T>(rows: T[], one: (row: T) => { row?: T; lost: number }): Carried<T> => {
    const results = rows.map(one);
    return { rows: results.flatMap(({ row }) => (row ? [row] : [])), dropped: results.reduce((sum, { lost }) => sum + lost, 0) };
};

/**
 * The world rows on the other shard: every prefab that exists there stays (the spawn becomes the other shard's spawn), a
 * rule whose prefabs don't exist there is dropped. `dropped` counts the picks and rules lost.
 */
export function worldRowsFor(rows: WorldRows, from: Shard, to: Shard): { rows: WorldRows; dropped: number } {
    if (from === to) return { rows, dropped: 0 };
    const counts = carry(rows.counts, (row) => {
        const near = row.near;
        return carryRow(row, [row.prefabs, ...(near ? [near.prefabs] : [])], from, to, ([prefabs, nearPrefabs]) => ({
            ...row,
            prefabs,
            near: near ? { ...near, prefabs: nearPrefabs } : null
        }));
    });
    const distances = carry(rows.distances, (row) => carryRow(row, [row.from, row.to], from, to, ([a, b]) => ({ ...row, from: a, to: b })));
    const routes = carry(rows.routes, (row) => {
        const required = carryRow(row, [row.from, ...row.stops.map((stop) => stop.prefabs)], from, to, ([start, ...stops]) => ({
            ...row,
            from: start,
            stops: row.stops.map((stop, index) => ({ ...stop, prefabs: stops[index] }))
        }));
        const end = carriedSet(row.to, from, to);
        return required.row ? { row: { ...required.row, to: end.ids }, lost: required.lost + end.lost } : required;
    });
    return {
        rows: { counts: counts.rows, distances: distances.rows, tiles: rows.tiles, routes: routes.rows },
        dropped: counts.dropped + distances.dropped + routes.dropped
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
