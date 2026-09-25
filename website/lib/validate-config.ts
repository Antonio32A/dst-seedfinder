import { SET_PIECE_BY_ID, SWAPS, TASK_BY_ID } from "@/lib/catalog";
import { hasAtMostTwoDecimals, MAX_MAX_COST, MIN_MAX_COST, roundCredits } from "@/lib/credits";
import {
  CONFIG_VERSION,
  DEFAULT_PLATFORM,
  MAX_CRITERIA,
  MAX_DISTANCE,
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
  PLATFORMS,
  ROUTE_ORDERS,
  type JobRequest,
  type Platform,
  type SeedfinderConfig,
} from "@/lib/seedfinder-config";
import { LAND_TILES, NON_LAND_TILE_NAMES, PREFAB_BY_ID, PREFAB_GROUP_IDS, PREFAB_VARIANTS } from "@/lib/world-catalog";

const TASK_IDS: ReadonlySet<string> = new Set(Object.keys(TASK_BY_ID));
const SET_PIECE_NAMES: ReadonlySet<string> = new Set(Object.keys(SET_PIECE_BY_ID));
const LAND_TILE_NAMES: ReadonlySet<string> = new Set(LAND_TILES.map((tile) => tile.name));
const TILE_NAMES: ReadonlySet<string> = new Set([...LAND_TILE_NAMES, ...NON_LAND_TILE_NAMES]);
const PREFAB_GROUP_NAMES: ReadonlySet<string> = new Set(
  [...PREFAB_GROUP_IDS, ...PREFAB_VARIANTS.keys()].filter((name) => !PREFAB_BY_ID.has(name)),
);
const SWAP_OPTIONS: ReadonlyMap<string, readonly string[]> = new Map(
  SWAPS.map((swap) => [swap.id, swap.options.map((option) => option.id)]),
);

class ValidationError extends Error {}

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
  if (typeof value !== "object" || value === null || Array.isArray(value)) fail(`${path} must be an object`);
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined));
}

function listAt(value: unknown, path: string, cap: number, noun: string, min = 0): unknown[] {
  if (!Array.isArray(value)) fail(`${path} must be a list`);
  if (value.length < min) fail(`${path} must not be empty`);
  if (value.length > cap) fail(`${path} has ${value.length} ${noun} (at most ${cap})`);
  return value;
}

function stringAt(value: unknown, path: string): string {
  if (typeof value !== "string") fail(`${path} must be a string`);
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
      }),
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
      const name = stringAt(item, `${path}[${index}]`);
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

const taskList = namesOf(
  (task, path) => TASK_IDS.has(task) || fail(`unknown task ${quoted(task)} in ${path}`),
  MAX_TASKS_PER_LIST,
  "tasks",
);

const prefabSet = nameSetOf(
  (prefab, path) =>
    PREFAB_BY_ID.has(prefab) ||
    fail(`unknown prefab ${quoted(prefab)} in ${path}${PREFAB_GROUP_NAMES.has(prefab) ? " (a catalog group name: list its prefab ids)" : ""}`),
  MAX_PREFAB_IDS,
  "prefab ids",
  "must be a prefab id or a list of prefab ids",
);

const tileSet = nameSetOf(
  (tile, path) => {
    if (!TILE_NAMES.has(tile)) fail(`unknown tile ${quoted(tile)} in ${path}`);
    if (!LAND_TILE_NAMES.has(tile)) fail(`tile ${quoted(tile)} in ${path} is not a land tile`);
  },
  MAX_TILE_NAMES,
  "tiles",
  "must be a tile name or a list of tile names",
);

const setPieceBound: Parse = (value, path) => {
  const valid = Array.isArray(value) ? value.length === 2 && value.every(isUint32) : isUint32(value);
  return valid ? value : fail(`${path} must be an integer in 0..${MAX_UINT32} or [min, max]`);
};

const setPieceBounds: Parse = (value, path) => {
  const pieces = Object.entries(recordAt(value, path));
  if (pieces.length > MAX_SET_PIECES_PER_RULE) fail(`${path} has ${pieces.length} set pieces (at most ${MAX_SET_PIECES_PER_RULE})`);
  const unknown = pieces.find(([name]) => !SET_PIECE_NAMES.has(name));
  if (unknown) fail(`unknown set piece ${quoted(unknown[0])} in ${path}`);
  return Object.fromEntries(pieces.map(([name, bound]) => [name, setPieceBound(bound, `${path}[${quoted(name)}]`)]));
};

const prefabSwaps: Parse = (value, path) => {
  const swaps = Object.entries(recordAt(value, path));
  const bad = swaps.find(([category, variant]) => !SWAP_OPTIONS.get(category)?.includes(variant as string));
  if (bad) fail(`unknown prefab swap ${quoted(bad[0])}: ${quoted(bad[1])} in ${path}`);
  return Object.fromEntries(swaps);
};

const metricFields: Fields = { metric: optional(choiceOf(METRICS)), wormholes: optional(flag) };

const routeShape = objectOf({
  from: required(prefabSet),
  visit: required(listOf(prefabSet, MAX_ROUTE_STOPS, "stops", MIN_ROUTE_STOPS)),
  to: optional(prefabSet),
  max: required(distance),
  order: optional(choiceOf(ROUTE_ORDERS)),
  ...metricFields,
});

const idsOf = (set: unknown): string[] => (set === undefined ? [] : ([] as string[]).concat(set as string | string[]));

const route: Parse = (value, path) => {
  const parsed = routeShape(value, path);
  const stopOf = new Map<string, number>();
  (parsed.visit as unknown[]).forEach((stop, index) =>
    new Set(idsOf(stop)).forEach((prefab) => {
      const earlier = stopOf.get(prefab);
      if (earlier !== undefined) fail(`${path}: ${quoted(prefab)} is in both visit[${earlier}] and visit[${index}]`);
      stopOf.set(prefab, index);
    }),
  );
  const endpoint = [...idsOf(parsed.from), ...idsOf(parsed.to)].filter((prefab) => stopOf.has(prefab)).sort()[0];
  if (endpoint !== undefined) fail(`${path}: ${quoted(endpoint)} is both a visit stop and the route's from/to`);
  return parsed;
};

const rules = (parse: Parse) => optional(listOf(parse, MAX_RULES_PER_SECTION, "rules"));

const criterion = objectOf({
  tasks: optional(objectOf({ required: optional(taskList), excluded: optional(taskList) })),
  prefab_swaps: optional(prefabSwaps),
  setpieces: rules(objectOf({ tasks: optional(taskList), required: optional(setPieceBounds) })),
  counts: rules(
    objectOf({
      prefab: required(prefabSet),
      min: optional(uint32),
      max: optional(uint32),
      near: optional(objectOf({ prefab: required(prefabSet), within: required(distance), ...metricFields })),
    }),
  ),
  distances: rules(
    objectOf({
      from: required(prefabSet),
      to: required(prefabSet),
      min: optional(distance),
      max: optional(distance),
      ...metricFields,
    }),
  ),
  tiles: rules(objectOf({ from: required(tileSet), to: required(tileSet), max: required(uint32) })),
  routes: rules(route),
});

const configShape = objectOf({
  version: optional((value) => (value === CONFIG_VERSION ? value : fail(`unsupported version ${quoted(value)}`))),
  platform: optional((value) =>
    PLATFORMS.includes(value as Platform) ? value : fail(`unknown platform ${quoted(value)} (${PLATFORMS.join(" or ")})`),
  ),
  settings: optional((value, path) => {
    const custom = Object.entries(recordAt(value, path)).find(([, level]) => level !== "default");
    return custom ? fail(`only default settings are supported (${custom[0]})`) : value;
  }),
  criteria: optional(listOf(criterion, MAX_CRITERIA, "entries")),
});

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
    const { platform, criteria } = configShape(value, ROOT);
    return {
      version: CONFIG_VERSION,
      platform: platform ?? DEFAULT_PLATFORM,
      ...(criteria === undefined ? {} : { criteria }),
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
 * Strictly validates an untrusted search config against search format v1 (`version` defaults to 1, `platform` to
 * `"windows"`, `settings` must all be `"default"`). Errors read like the finder's (`config: <message>`). The value is
 * normalized: `version` and `platform` are always set, `settings` is dropped and every other key is kept as written,
 * so it is safe to forward to the finder.
 */
export function validateConfig(config: unknown): Validation<SeedfinderConfig> {
  return validated(() => parseConfig(config));
}

/**
 * Strictly validates an untrusted job submission: its config (see `validateConfig`), `wanted`, `maxCost` and the
 * optional `startSeed` (uint32, the finder's `--start-seed`).
 */
export function validateJobRequest(body: unknown): Validation<JobRequest> {
  return validated(() => {
    const fields = recordAt(body, "the request");
    const unknownKey = Object.keys(fields).find((key) => !["config", "wanted", "maxCost", "startSeed"].includes(key));
    if (unknownKey !== undefined) fail(`unknown key ${quoted(unknownKey)} in the request`);
    return {
      config: parseConfig(fields.config),
      wanted: integerIn(fields.wanted, '"wanted"', MIN_WANTED, MAX_WANTED),
      maxCost: creditsIn(fields.maxCost, '"maxCost"', MIN_MAX_COST, MAX_MAX_COST),
      ...(fields.startSeed === undefined ? {} : { startSeed: integerIn(fields.startSeed, '"startSeed"', 0, MAX_UINT32) }),
    };
  });
}
