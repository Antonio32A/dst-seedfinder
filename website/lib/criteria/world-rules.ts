import { fixedCount, sampleCounts, setLabel } from "@/lib/catalog/prefab-sets";
import { LAND_TILES, PREFAB_BY_ID } from "@/lib/catalog/world";
import {
    type CountRule,
    type Criterion,
    DEFAULT_METRIC,
    DEFAULT_ROUTE_ORDER,
    DEFAULT_WORMHOLES,
    type DistanceRule,
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
    type TileRule,
    WORLD_UNITS_PER_TILE
} from "@/lib/config/seedfinder-config";
import { asRecord } from "@/lib/records";
import { asArray, asStrings, newKey, nonEmpty } from "./state-helpers";

export type WorldCountMode = "atLeast" | "atMost" | "exactly" | "between" | "none";
export type DistanceMode = "within" | "atLeast" | "between";

export interface Travel {
    metric: Metric;
    wormholes: boolean;
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

const SPAWN_PORTAL = "multiplayer_portal";
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
const DEFAULT_TRAVEL: Travel = { metric: DEFAULT_METRIC, wormholes: DEFAULT_WORMHOLES };

export const newNear = (): NearRow => ({ ...DEFAULT_TRAVEL, prefabs: [SPAWN_PORTAL], within: tiles(100) });

export const newRouteStop = (prefabs: string[] = []): RouteStop => ({ key: newKey(), prefabs });

export const NEW_WORLD_ROW: { [S in WorldSection]: () => WorldRows[S][number] } = {
    counts: () => ({ key: newKey(), prefabs: [], mode: "atLeast", min: 1, max: 1, near: null }),
    distances: () => ({
        ...DEFAULT_TRAVEL,
        key: newKey(),
        from: [SPAWN_PORTAL],
        to: [],
        mode: "within",
        min: 0,
        max: tiles(100)
    }),
    tiles: () => ({ key: newKey(), from: [], to: [], max: 3 }),
    routes: () => ({
        ...DEFAULT_TRAVEL,
        key: newKey(),
        from: [SPAWN_PORTAL],
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

const travelFields = ({ metric, wormholes }: Travel) => ({
    ...(metric === DEFAULT_METRIC ? {} : { metric }),
    ...(wormholes === DEFAULT_WORMHOLES ? {} : { wormholes })
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

const countRule = (row: CountRow): CountRule[] =>
    filled(row.prefabs, ...(row.near ? [row.near.prefabs] : []))
        ? [
            {
                prefab: asSet(row.prefabs),
                ...COUNT_BOUNDS[row.mode](row),
                ...(row.near ? {
                    near: {
                        prefab: asSet(row.near.prefabs),
                        within: row.near.within, ...travelFields(row.near)
                    }
                } : {})
            }
        ]
        : [];

const distanceRule = (row: DistanceRow): DistanceRule[] =>
    filled(row.from, row.to) ? [{
        from: asSet(row.from),
        to: asSet(row.to), ...DISTANCE_BOUNDS[row.mode](row), ...travelFields(row)
    }] : [];

const tileRule = (row: TileRow): TileRule[] => (filled(row.from, row.to) ? [{
    from: asSet(row.from),
    to: asSet(row.to),
    max: row.max
}] : []);

const routeRule = (row: RouteRow): RouteRule[] => {
    const end = routeEnd(row);
    if (!filled(row.from, ...row.stops.map((stop) => stop.prefabs)) || row.stops.length === 0) return [];
    return [
        {
            from: asSet(row.from),
            visit: row.stops.map((stop) => asSet(stop.prefabs)),
            ...(end.length > 0 ? { to: asSet(end) } : {}),
            max: row.max,
            ...(row.order === DEFAULT_ROUTE_ORDER ? {} : { order: row.order }),
            ...travelFields(row)
        }
    ];
};

export function worldSections(rows: WorldRows): Pick<Criterion, "counts" | "distances" | "tiles" | "routes"> {
    return {
        counts: nonEmpty(rows.counts.flatMap(countRule)),
        distances: nonEmpty(rows.distances.flatMap(distanceRule)),
        tiles: nonEmpty(rows.tiles.flatMap(tileRule)),
        routes: nonEmpty(rows.routes.flatMap(routeRule))
    };
}

const LAND_TILE_NAMES: ReadonlySet<string> = new Set(LAND_TILES.map((tile) => tile.name));

const namesIn = (value: unknown, known: (name: string) => boolean, cap: number): string[] => {
    const names = typeof value === "string" ? [value] : asStrings(value);
    return [...new Set(names.filter(known))].slice(0, cap);
};

const prefabIds = (value: unknown) => namesIn(value, (id) => PREFAB_BY_ID.has(id), MAX_PREFAB_IDS);
const tileNames = (value: unknown) => namesIn(value, (name) => LAND_TILE_NAMES.has(name), MAX_TILE_NAMES);

const numberIn = (value: unknown, max: number, integer: boolean): number | undefined =>
    typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= max && (!integer || Number.isInteger(value)) ? value : undefined;

const distanceOf = (value: unknown) => numberIn(value, MAX_DISTANCE, false);
const uint32Of = (value: unknown) => numberIn(value, MAX_UINT32, true);

const travelOf = (record: Record<string, unknown>): Travel => ({
    metric: METRICS.find((metric) => metric === record.metric) ?? DEFAULT_METRIC,
    wormholes: record.wormholes === true
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

function nearOf(value: unknown): NearRow | null | undefined {
    if (value === undefined) return null;
    const record = asRecord(value);
    const prefabs = prefabIds(record.prefab);
    const within = distanceOf(record.within);
    return prefabs.length > 0 && within !== undefined ? { ...travelOf(record), prefabs, within } : undefined;
}

function countRowOf(value: unknown): CountRow[] {
    const record = asRecord(value);
    const prefabs = prefabIds(record.prefab);
    const near = nearOf(record.near);
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

function distanceRowOf(value: unknown): DistanceRow[] {
    const record = asRecord(value);
    const [from, to] = [prefabIds(record.from), prefabIds(record.to)];
    const [min, max] = [distanceOf(record.min), distanceOf(record.max)];
    if (!filled(from, to)) return [];
    return [{
        ...travelOf(record),
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

function routeRowOf(value: unknown): RouteRow[] {
    const record = asRecord(value);
    const from = prefabIds(record.from);
    const stops = asArray(record.visit).slice(0, MAX_ROUTE_STOPS).map((stop) => newRouteStop(prefabIds(stop)));
    const to = prefabIds(record.to);
    const max = distanceOf(record.max);
    if (!filled(from, ...stops.map((stop) => stop.prefabs)) || stops.length === 0 || max === undefined) return [];
    const roundTrip = to.length > 0 && to.length === from.length && to.every((id) => from.includes(id));
    const order = record.order === "fixed" ? "fixed" : DEFAULT_ROUTE_ORDER;
    return [{ ...travelOf(record), key: newKey(), from, stops, to: roundTrip ? [] : to, roundTrip, order, max }];
}

const rowsOf = <T>(value: unknown, parse: (item: unknown) => T[]): T[] =>
    asArray(value).slice(0, MAX_RULES_PER_SECTION).flatMap(parse);

export function worldRowsOf(criterion: Record<string, unknown>): WorldRows {
    return {
        counts: rowsOf(criterion.counts, countRowOf),
        distances: rowsOf(criterion.distances, distanceRowOf),
        tiles: rowsOf(criterion.tiles, tileRowOf),
        routes: rowsOf(criterion.routes, routeRowOf)
    };
}

type RowCheck<T> = (row: T, label: string) => WorldIssue | undefined;

const error = (message: string): WorldIssue => ({ severity: "error", message });
const warning = (message: string): WorldIssue => ({ severity: "warning", message });

const COUNT_CHECKS: RowCheck<CountRow>[] = [
    (row, label) => (row.prefabs.length === 0 ? error(`${label} needs something to count.`) : undefined),
    (row, label) => (row.near?.prefabs.length === 0 ? error(`${label} needs something to be near.`) : undefined),
    (row, label) => (row.mode === "between" && row.min > row.max ? error(`${label}: minimum is above maximum.`) : undefined),
    (row, label) => {
        if (row.near || row.prefabs.length === 0) return undefined;
        const { min = 0, max = Infinity } = COUNT_BOUNDS[row.mode](row);
        const [sampleMin, , sampleMax] = sampleCounts(row.prefabs);
        const fixed = fixedCount(row.prefabs);
        const name = setLabel(row.prefabs);
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
    (row, label) => {
        const endpoints = new Set([...row.from, ...routeEnd(row)]);
        const stopIds = row.stops.flatMap((stop) => [...new Set(stop.prefabs)]);
        const clash = stopIds.find((id, index) => endpoints.has(id) || stopIds.indexOf(id) !== index);
        if (clash === undefined) return undefined;
        const place = endpoints.has(clash) ? "is both a stop and the start or end" : "is in more than one stop";
        return error(`${label}: ${setLabel([clash])} ${place}.`);
    }
];

const checkRows = <T>(rows: T[], noun: string, checks: RowCheck<T>[]): WorldIssue[] =>
    rows.flatMap((row, index) => checks.flatMap((check) => check(row, `${noun} ${index + 1}`) ?? []));

export function worldIssues(rows: WorldRows): WorldIssue[] {
    return [
        ...checkRows(rows.counts, "count", COUNT_CHECKS),
        ...checkRows(rows.distances, "distance", DISTANCE_CHECKS),
        ...checkRows(rows.tiles, "turf rule", TILE_CHECKS),
        ...checkRows(rows.routes, "route", ROUTE_CHECKS)
    ];
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
