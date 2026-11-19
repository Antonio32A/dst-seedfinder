import { CAVE_SWAPS } from "@/lib/catalog/cave-vocab";
import { type LevelCatalog, levelCatalogOf } from "@/lib/catalog/level-catalog";
import { SWAPS } from "@/lib/catalog/level";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import { LAND_TILES, NON_LAND_TILE_NAMES, PREFAB_GROUP_IDS } from "@/lib/catalog/world";
import { hasAtMostTwoDecimals, MAX_MAX_COST, MIN_MAX_COST, roundCredits } from "@/lib/jobs/credits";
import { isRecord } from "@/lib/records";
import { BUILD_NUMBERS_TEXT, gameBuildOf, hasShard } from "./builds";
import { GAME_BUILDS, type GameBuild } from "./game-builds";
import {
    CONFIG_VERSION,
    DEFAULT_PLATFORM,
    DEFAULT_SHARD,
    type JobRequest,
    LEGACY_CONFIG_BUILD,
    LEGACY_CONFIG_VERSIONS,
    LINKS_KEY,
    MAX_DISTANCE,
    MAX_FILTER_NAME_LENGTH,
    MAX_FILTERS,
    MAX_PREFAB_IDS,
    MAX_ROUTE_STOPS,
    MAX_RULES_PER_SECTION,
    MAX_SET_PIECES_PER_RULE,
    MAX_TASKS_PER_LIST,
    MAX_TILE_NAMES,
    MAX_UINT32,
    MAX_WANTED,
    METRICS,
    MIN_ROUTE_STOPS,
    MIN_WANTED,
    type Platform,
    PLATFORMS,
    ROUTE_ORDERS,
    type SeedfinderConfig,
    type Shard,
    SHARDS
} from "./seedfinder-config";
import { upgradeConfig } from "./upgrade-config";

const LAND_TILE_NAMES: ReadonlySet<string> = new Set(LAND_TILES.map((tile) => tile.name));
const TILE_NAMES: ReadonlySet<string> = new Set([...LAND_TILE_NAMES, ...NON_LAND_TILE_NAMES]);
const SWAP_OPTIONS: Record<Shard, ReadonlyMap<string, readonly string[]>> = {
    forest: new Map(SWAPS.map((swap) => [swap.id, swap.options.map((option) => option.id)])),
    caves: new Map(CAVE_SWAPS.map((swap) => [swap.category, swap.options]))
};

function prefabGroupNames(shard: Shard, build: GameBuild): ReadonlySet<string> {
    const { prefabs, byId } = shardCatalog(shard, build);
    const variants = prefabs.flatMap(({ variantOf }) => (variantOf ? [variantOf] : []));
    return new Set([...PREFAB_GROUP_IDS, ...variants].filter((name) => !byId.has(name)));
}

class ValidationError extends Error {
}

type Validation<T> = { ok: true; value: T } | { ok: false; error: string };
type Parse<T = unknown> = (value: unknown, path: string) => T;
type Fields = Record<string, { parse: Parse; required: boolean }>;

function fail(message: string): never {
    throw new ValidationError(message);
}

const ROOT = "the config";

const quoted = (name: unknown) => JSON.stringify(name);
const child = (path: string, key: string) => (path === ROOT ? key : `${path}.${key}`);

const required = (parse: Parse) => ({ parse, required: true });
const optional = (parse: Parse) => ({ parse, required: false });

function recordAt(value: unknown, path: string): Record<string, unknown> {
    if (!isRecord(value)) fail(`${path} must be an object`);
    return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined));
}

function listAt(value: unknown, path: string, cap: number, noun: string, min = 0): unknown[] {
    if (!Array.isArray(value)) fail(`${path} must be a list`);
    if (value.length < min) fail(`${path} must not be empty`);
    if (value.length > cap) fail(`${path} has ${value.length} ${noun} (at most ${cap})`);
    return value;
}

function objectOf(fields: Fields): Parse<Record<string, unknown>> {
    return (value, path) => {
        const raw = recordAt(value, path);
        const unknownKey = Object.keys(raw).find((key) => !Object.hasOwn(fields, key));
        if (unknownKey !== undefined) fail(`unknown key ${quoted(unknownKey)} in ${path}`);
        return Object.fromEntries(
            Object.entries(fields).flatMap(([key, field]) => {
                if (Object.hasOwn(raw, key)) return [[key, field.parse(raw[key], child(path, key))]];
                return field.required ? fail(`${child(path, key)} is required`) : [];
            })
        );
    };
}

function listOf(parse: Parse, cap: number, noun: string, min = 0): Parse<unknown[]> {
    return (value, path) => listAt(value, path, cap, noun, min).map((item, index) => parse(item, `${path}[${index}]`));
}

function isUint32(value: unknown): value is number {
    return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= MAX_UINT32;
}

const uint32: Parse<number> = (value, path) =>
    isUint32(value) ? value : fail(`${path} must be an integer in 0..${MAX_UINT32}`);

const distance: Parse<number> = (value, path) =>
    typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= MAX_DISTANCE
        ? value
        : fail(`${path} must be a number in 0..${MAX_DISTANCE}`);

const flag: Parse<boolean> = (value, path) =>
    typeof value === "boolean" ? value : fail(`${path} must be true or false`);

function choiceOf(options: readonly string[]): Parse<string> {
    return (value, path) =>
        options.includes(value as string) ? (value as string) : fail(`${path} must be ${options.map(quoted).join(" or ")}`);
}

function namesOf(check: (name: string, path: string) => void, cap: number, noun: string, min = 0): Parse<string[]> {
    return (value, path) =>
        listAt(value, path, cap, noun, min).map((item, index) => {
            const name = typeof item === "string" ? item : fail(`${path}[${index}] must be a string`);
            check(name, path);
            return name;
        });
}

function nameSetOf(check: (name: string, path: string) => void, cap: number, noun: string, typeError: string): Parse {
    const names = namesOf(check, cap, noun, 1);
    return (value, path) => {
        if (typeof value === "string") return names([value], path)[0];
        return Array.isArray(value) ? names(value, path) : fail(`${path} ${typeError}`);
    };
}

const taskListOf = (catalog: LevelCatalog) =>
    namesOf(
        (task, path) => catalog.taskById.has(task) || fail(`unknown task ${quoted(task)} in ${path}`),
        MAX_TASKS_PER_LIST,
        "tasks"
    );

const prefabSetOf = (shard: Shard, build: GameBuild) => {
    const { byId } = shardCatalog(shard, build);
    const groupNames = prefabGroupNames(shard, build);
    return nameSetOf(
        (prefab, path) =>
            byId.has(prefab) ||
            fail(`unknown prefab ${quoted(prefab)} in ${path}${groupNames.has(prefab) ? " (a catalog group name: list its prefab ids)" : ""}`),
        MAX_PREFAB_IDS,
        "prefab ids",
        "must be a prefab id or a list of prefab ids"
    );
};

const tileSet = nameSetOf(
    (tile, path) => {
        if (!TILE_NAMES.has(tile)) fail(`unknown tile ${quoted(tile)} in ${path}`);
        if (!LAND_TILE_NAMES.has(tile)) fail(`tile ${quoted(tile)} in ${path} is not a land tile`);
    },
    MAX_TILE_NAMES,
    "tiles",
    "must be a tile name or a list of tile names"
);

const boundAt: Parse = (bound, path) =>
    (Array.isArray(bound) ? bound.length === 2 && bound.every(isUint32) : isUint32(bound))
        ? bound
        : fail(`${path} must be an integer in 0..${MAX_UINT32} or [min, max]`);

const setPieceBoundsOf =
    (catalog: LevelCatalog): Parse =>
        (value, path) => {
            const pieces = Object.entries(recordAt(value, path));
            if (pieces.length > MAX_SET_PIECES_PER_RULE) fail(`${path} has ${pieces.length} set pieces (at most ${MAX_SET_PIECES_PER_RULE})`);
            const unknown = pieces.find(([name]) => !catalog.setPieceById.has(name));
            if (unknown) fail(`unknown set piece ${quoted(unknown[0])} in ${path}`);
            return Object.fromEntries(
                pieces.map(([name, bound]) => [name, boundAt(bound, `${path}[${quoted(name)}]`)])
            );
        };

const setPieceRuleOf = (catalog: LevelCatalog): Parse => {
    const shape = objectOf({
        tasks: optional(taskListOf(catalog)),
        required: optional(setPieceBoundsOf(catalog)),
        ...(catalog.shard === "forest" ? { placed: optional(namesOf(() => undefined, MAX_SET_PIECES_PER_RULE, "set pieces")) } : {})
    });
    return (value, path) => {
        const rule = shape(value, path);
        const placed = (rule.placed ?? []) as string[];
        const required = (rule.required ?? {}) as Record<string, unknown>;
        placed.forEach((name, index) => {
            if (placed.indexOf(name) < index) fail(`${child(path, "placed")} names ${quoted(name)} twice`);
            if (!Object.hasOwn(required, name)) fail(`${child(path, "placed")} names ${quoted(name)}, which isn't in required`);
        });
        return rule;
    };
};

const setPieceItemOf = (catalog: LevelCatalog): Parse => {
    const rule = setPieceRuleOf(catalog);
    const group = objectOf({ any: required(listOf(rule, MAX_RULES_PER_SECTION, "rules", 1)), total: optional(boundAt) });
    const isGroup = (value: unknown) => isRecord(value) && (Object.hasOwn(value, "any") || Object.hasOwn(value, "total"));
    return (value, path) => (isGroup(value) ? group(value, path) : rule(value, path));
};

const prefabSwapsOf =
    (shard: Shard): Parse =>
        (value, path) => {
            const swaps = Object.entries(recordAt(value, path));
            const bad = swaps.find(([category, variant]) =>
                !SWAP_OPTIONS[shard].get(category)?.includes(variant as string));
            if (bad) fail(`unknown prefab swap ${quoted(bad[0])}: ${quoted(bad[1])} in ${path}`);
            return Object.fromEntries(swaps);
        };

const metricFieldsOf = (shard: Shard): Fields => ({
    metric: optional(choiceOf(METRICS)),
    [LINKS_KEY[shard]]: optional(flag)
});

const routeShapeOf = (shard: Shard, build: GameBuild) => {
    const prefabSet = prefabSetOf(shard, build);
    return objectOf({
        from: required(prefabSet),
        visit: required(listOf(prefabSet, MAX_ROUTE_STOPS, "stops", MIN_ROUTE_STOPS)),
        to: optional(prefabSet),
        max: required(distance),
        order: optional(choiceOf(ROUTE_ORDERS)),
        ...metricFieldsOf(shard)
    });
};

const idsOf = (set: unknown): string[] => (set === undefined ? [] : ([] as string[]).concat(set as string | string[]));

const routeOf = (shard: Shard, build: GameBuild): Parse => {
    const routeShape = routeShapeOf(shard, build);
    return (value, path) => {
        const parsed = routeShape(value, path);
        const stopOf = new Map<string, number>();
        (parsed.visit as unknown[]).forEach((stop, index) =>
            new Set(idsOf(stop)).forEach((prefab) => {
                const earlier = stopOf.get(prefab);
                if (earlier !== undefined) fail(`${path}: ${quoted(prefab)} is in both visit[${earlier}] and visit[${index}]`);
                stopOf.set(prefab, index);
            })
        );
        const endpoint = [...idsOf(parsed.from), ...idsOf(parsed.to)]
            .filter((prefab) => stopOf.has(prefab))
            .sort()
            .at(0);
        if (endpoint !== undefined) fail(`${path}: ${quoted(endpoint)} is both a visit stop and the route's from/to`);
        return parsed;
    };
};

const rules = (parse: Parse) => optional(listOf(parse, MAX_RULES_PER_SECTION, "rules"));

const filterName: Parse<string> = (value, path) => {
    if (typeof value !== "string") fail(`${path} must be a string`);
    const length = [...value].length;
    return length <= MAX_FILTER_NAME_LENGTH
        ? value
        : fail(`${path} has ${length} characters (at most ${MAX_FILTER_NAME_LENGTH})`);
};

const filterOf = (shard: Shard, build: GameBuild): Parse => {
    const prefabSet = prefabSetOf(shard, build);
    const metricFields = metricFieldsOf(shard);
    return objectOf({
        name: optional(filterName),
        counts: rules(
            objectOf({
                prefab: required(prefabSet),
                min: optional(uint32),
                max: optional(uint32),
                near: optional(objectOf({ prefab: required(prefabSet), within: required(distance), ...metricFields }))
            })
        ),
        distances: rules(
            objectOf({
                from: required(prefabSet),
                to: required(prefabSet),
                min: optional(distance),
                max: optional(distance),
                ...metricFields
            })
        ),
        tiles: rules(objectOf({ from: required(tileSet), to: required(tileSet), max: required(uint32) })),
        bridges: rules(objectOf({ min: optional(distance), max: optional(distance) })),
        routes: rules(routeOf(shard, build)),
        islands: rules(
            objectOf({
                at: required(prefabSet),
                min: optional(uint32),
                max: optional(uint32),
                [LINKS_KEY[shard]]: optional(flag)
            })
        )
    });
};

const generationOf = (catalog: LevelCatalog) => {
    const taskList = taskListOf(catalog);
    return objectOf({
        tasks: optional(objectOf({ required: optional(taskList), excluded: optional(taskList) })),
        prefab_swaps: optional(prefabSwapsOf(catalog.shard)),
        setpieces: rules(setPieceItemOf(catalog))
    });
};

const shardOf: Parse = (value) =>
    SHARDS.includes(value as Shard) ? value : fail(`unknown shard ${quoted(value)} (${SHARDS.join(" or ")})`);

const versionOf: Parse = (value) => {
    if (value === CONFIG_VERSION) return value;
    return LEGACY_CONFIG_VERSIONS.includes(value)
        ? fail(`version ${quoted(value)} is an old config format: use version ${CONFIG_VERSION} and set "build" to a game build (${LEGACY_CONFIG_BUILD} for configs written before builds)`)
        : fail(`unsupported version ${quoted(value)}`);
};

const buildOf: Parse<GameBuild> = (value) =>
    gameBuildOf(value) ?? fail(`unknown build ${quoted(value)} (${BUILD_NUMBERS_TEXT})`);

const configShapeOf = (shard: Shard, build: GameBuild) =>
    objectOf({
        version: optional(versionOf),
        build: required(buildOf),
        shard: optional(shardOf),
        platform: optional((value) =>
            PLATFORMS.includes(value as Platform) ? value : fail(`unknown platform ${quoted(value)} (${PLATFORMS.join(" or ")})`)
        ),
        settings: optional((value, path) => {
            const custom = Object.entries(recordAt(value, path)).find(([, level]) => level !== "default");
            return custom ? fail(`only default settings are supported (${custom[0]})`) : value;
        }),
        generation: optional(generationOf(levelCatalogOf(shard, build))),
        filters: optional(listOf(filterOf(shard, build), MAX_FILTERS, "entries"))
    });

const CONFIG_SHAPES: ReadonlyMap<GameBuild, Record<Shard, Parse<Record<string, unknown>>>> = new Map(
    GAME_BUILDS.map(({ number }) => [number, { forest: configShapeOf("forest", number), caves: configShapeOf("caves", number) }])
);

/** The shard a config names; anything that isn't a shard name reads as the forest, the shard parse reports it. */
function shardNamed(config: Record<string, unknown>): Shard {
    return SHARDS.includes(config.shard as Shard) ? (config.shard as Shard) : DEFAULT_SHARD;
}

/** The build a config is for, which decides the names it can use, after its format version. */
function buildNamed(config: Record<string, unknown>): GameBuild {
    if (Object.hasOwn(config, "version")) versionOf(config.version, child(ROOT, "version"));
    if (!Object.hasOwn(config, "build")) fail(`build is required (a game build: ${BUILD_NUMBERS_TEXT})`);
    return buildOf(config.build, child(ROOT, "build"));
}

function validated<T>(check: () => T): Validation<T> {
    try {
        return { ok: true, value: check() };
    } catch (error) {
        if (error instanceof ValidationError) return { ok: false, error: error.message };
        throw error;
    }
}

function parseConfig(value: unknown): SeedfinderConfig {
    try {
        const config = recordAt(value, ROOT);
        const build = buildNamed(config);
        const shard = shardNamed(config);
        if (!hasShard(build, shard)) fail(`build ${build} does not support the ${shard} shard yet`);
        const { platform, generation, filters } = CONFIG_SHAPES.get(build)![shard](config, ROOT);
        return {
            version: CONFIG_VERSION,
            build,
            shard,
            platform: platform ?? DEFAULT_PLATFORM,
            ...(generation === undefined ? {} : { generation }),
            ...(filters === undefined ? {} : { filters })
        } as SeedfinderConfig;
    } catch (error) {
        if (error instanceof ValidationError) fail(`config: ${error.message}`);
        throw error;
    }
}

function integerIn(value: unknown, context: string, min: number, max: number): number {
    if (typeof value !== "number" || !Number.isInteger(value)) fail(`${context} must be a whole number`);
    if (value < min || value > max) fail(`${context} must be between ${min} and ${max}`);
    return value;
}

function creditsIn(value: unknown, context: string, min: number, max: number): number {
    if (value === undefined) fail(`the request is missing ${context}`);
    if (typeof value !== "number" || !Number.isFinite(value)) fail(`${context} must be a number of credits`);
    if (!hasAtMostTwoDecimals(value)) fail(`${context} can have at most 2 decimals`);
    if (value < min || value > max) fail(`${context} must be between ${min} and ${max} credits`);
    return roundCredits(value);
}

/**
 * Validates against search format v3, with the names of the config's build. `version`, `shard` and `platform` are
 * filled in, every `settings` level must be `"default"` and `settings` is dropped; errors read like the finder's.
 */
export function validateConfig(config: unknown): Validation<SeedfinderConfig> {
    return validated(() => parseConfig(config));
}

export function validateJobRequest(body: unknown): Validation<JobRequest> {
    return validated(() => {
        const fields = recordAt(body, "the request");
        const unknownKey = Object.keys(fields).find((key) => !["config", "wanted", "maxCost", "startSeed", "timings"].includes(key));
        if (unknownKey !== undefined) fail(`unknown key ${quoted(unknownKey)} in the request`);
        if (fields.timings !== undefined && typeof fields.timings !== "boolean") fail("\"timings\" must be true or false");
        return {
            config: parseConfig(upgradeConfig(fields.config)),
            wanted: integerIn(fields.wanted, "\"wanted\"", MIN_WANTED, MAX_WANTED),
            maxCost: creditsIn(fields.maxCost, "\"maxCost\"", MIN_MAX_COST, MAX_MAX_COST),
            ...(fields.startSeed === undefined ? {} : { startSeed: integerIn(fields.startSeed, "\"startSeed\"", 0, MAX_UINT32) }),
            ...(fields.timings ? { timings: true } : {})
        };
    });
}
