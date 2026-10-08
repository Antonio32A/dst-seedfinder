import { isRecord } from "@/lib/records";
import { CONFIG_VERSION } from "./seedfinder-config";

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

export function upgradeConfig(config: unknown): unknown {
    if (!isRecord(config)) return config;
    const kept = Object.fromEntries(Object.entries(config).filter(([key]) => key !== "settings" && key !== "criteria"));
    if (!isV1(config)) return { version: CONFIG_VERSION, ...kept };
    const entries = entriesOf(config);
    const generation = generationOf(entries);
    const filters = entries.map((entry) => sectionsOf(entry, WORLD_SECTIONS));
    return {
        ...kept,
        version: CONFIG_VERSION,
        ...(isEmpty(generation) ? {} : { generation }),
        ...(filters.every(isEmpty) ? {} : { filters })
    };
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
