import { isRecord } from "@/lib/records";
import { CONFIG_VERSION, LEGACY_CONFIG_BUILD, LEGACY_CONFIG_VERSIONS } from "./seedfinder-config";

const LEVEL_SECTIONS = ["tasks", "prefab_swaps", "setpieces"];
const WORLD_SECTIONS = ["counts", "distances", "tiles", "bridges", "routes"];

const sectionsOf = (entry: Record<string, unknown>, keys: string[]) =>
    Object.fromEntries(keys.filter((key) => entry[key] !== undefined).map((key) => [key, entry[key]]));

const isEmpty = (record: Record<string, unknown>) => Object.keys(record).length === 0;

const entriesOf = (config: Record<string, unknown>) =>
    (Array.isArray(config.criteria) ? config.criteria : []).filter(isRecord);

const generationOf = (entries: Record<string, unknown>[]) =>
    sectionsOf(entries.find((entry) => entry.passive !== true) ?? {}, LEVEL_SECTIONS);

const isV1 = (config: Record<string, unknown>) => config.version === 1 || Object.hasOwn(config, "criteria");

const isLegacy = (config: Record<string, unknown>) =>
    config.version === undefined || LEGACY_CONFIG_VERSIONS.includes(config.version);

function v2Sections(config: Record<string, unknown>): Record<string, unknown> {
    const kept = Object.fromEntries(Object.entries(config).filter(([key]) => key !== "settings" && key !== "criteria"));
    if (!isV1(config)) return kept;
    const entries = entriesOf(config);
    const generation = generationOf(entries);
    const filters = entries.map((entry) => sectionsOf(entry, WORLD_SECTIONS));
    return {
        ...kept,
        ...(isEmpty(generation) ? {} : { generation }),
        ...(filters.every(isEmpty) ? {} : { filters })
    };
}

/**
 * A config of a legacy format version (none, 1 or 2) in the current format, for the build those were written for; any
 * other config is left as it is.
 */
export function upgradeConfig(config: unknown): unknown {
    if (!isRecord(config) || !isLegacy(config)) return config;
    return { ...v2Sections(config), version: CONFIG_VERSION, build: LEGACY_CONFIG_BUILD };
}

export function dropsLevelTables(config: unknown): boolean {
    if (!isRecord(config) || !isV1(config)) return false;
    const entries = entriesOf(config);
    const kept = JSON.stringify(generationOf(entries));
    return entries.some((entry) => {
        const own = sectionsOf(entry, LEVEL_SECTIONS);
        return !(entry.passive === true && isEmpty(own)) && JSON.stringify(own) !== kept;
    });
}
