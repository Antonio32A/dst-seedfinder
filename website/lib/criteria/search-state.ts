import { type LevelCatalog, levelCatalogOf } from "@/lib/catalog/level-catalog";
import type { SetPieceKind, SwapCategory } from "@/lib/catalog/level-types";
import {
    CONFIG_VERSION,
    type Criterion,
    DEFAULT_PLATFORM,
    DEFAULT_SHARD,
    MAX_CRITERIA,
    MAX_RULES_PER_SECTION,
    type Platform,
    PLATFORMS,
    type SeedfinderConfig,
    type SetPieceBound,
    type SetPieceRule,
    type Shard,
    SHARDS,
    WORLD_UNITS_PER_TILE
} from "@/lib/config/seedfinder-config";
import { validateConfig } from "@/lib/config/validate-config";
import { asRecord, isRecord } from "@/lib/records";
import { asArray, asStrings, clamp, newKey, nonEmpty } from "./state-helpers";
import {
    NEW_WORLD_ROW,
    worldIssues,
    worldRowCount,
    type WorldRows,
    worldRowsFor,
    worldRowsOf,
    worldSections
} from "./world-rules";

export type BiomeChoice = "include" | "exclude";
export type CountMode = "atLeast" | "exactly" | "between" | "none";
export type ScopeMode = "anywhere" | "only";

export interface PieceRule {
    key: string;
    pieceId: string;
    mode: CountMode;
    min: number;
    max: number;
    scopeMode: ScopeMode;
    scopeTasks: string[];
}

export interface CriteriaGroup extends WorldRows {
    key: string;
    passive: boolean;
    biomes: Record<string, BiomeChoice>;
    swaps: Partial<Record<SwapCategory, string>>;
    rules: PieceRule[];
}

export interface SearchState {
    shard: Shard;
    platform: Platform;
    groups: CriteriaGroup[];
}

export interface Issue {
    severity: "error" | "warning";
    message: string;
}

export interface Preset {
    id: string;
    name: string;
    description: string;
    build: () => SearchState;
}

export const WANTED_OPTIONS = [1, 10, 25, 50, 100];
export const DEFAULT_WANTED = 1;
export const STORAGE_KEY = "dst-seedfinder:search:v1";

export const SETTINGS_DROPPED_NOTICE = "Custom world settings were dropped, only default settings are supported.";

export const COUNT_MODES: { id: CountMode; label: string }[] = [
    { id: "atLeast", label: "At least" },
    { id: "exactly", label: "Exactly" },
    { id: "between", label: "Between" },
    { id: "none", label: "None" }
];

const MODE_FLOOR: Record<CountMode, number> = { atLeast: 1, exactly: 1, between: 0, none: 0 };

const KIND_TOTALS: Partial<Record<SetPieceKind, { most: number; noun: string }>> = {
    boon: { most: 8, noun: "boons" },
    trap: { most: 1, noun: "traps" },
    poi: { most: 1, noun: "points of interest" },
    protected: { most: 1, noun: "guarded resources" }
};

const REQUIREMENT: Record<CountMode, (rule: PieceRule) => SetPieceBound> = {
    atLeast: (rule) => rule.min,
    exactly: (rule) => [rule.min, rule.min],
    between: (rule) => [rule.min, rule.max],
    none: () => [0, 0]
};

/** `passive` groups only check seeds the other groups already pick. */
export function emptyGroup(passive = false): CriteriaGroup {
    return {
        key: newKey(),
        passive,
        biomes: {},
        swaps: {},
        rules: [],
        counts: [],
        distances: [],
        tiles: [],
        routes: []
    };
}

export function defaultState(): SearchState {
    return { shard: DEFAULT_SHARD, platform: DEFAULT_PLATFORM, groups: [emptyGroup()] };
}

export function newRule(pieceId: string, catalog: LevelCatalog): PieceRule {
    const fixed = catalog.setPieceById[pieceId]?.kind === "fixed";
    return {
        key: newKey(),
        pieceId,
        mode: "atLeast",
        min: 1,
        max: 1,
        scopeMode: fixed ? "only" : "anywhere",
        scopeTasks: []
    };
}

export function ruleMax(rule: PieceRule, catalog: LevelCatalog): number {
    const piece = catalog.setPieceById[rule.pieceId];
    if (!piece) return 0;
    const scope = ruleScope(rule, catalog);
    const onePerBiome = piece.kind === "fixed" && scope.length > 0 ? scope.filter((id) => piece.candidateTasks?.includes(id)).length : Infinity;
    return Math.min(piece.maxCount, KIND_TOTALS[piece.kind]?.most ?? Infinity, onePerBiome);
}

export function effectiveRule(rule: PieceRule, catalog: LevelCatalog): PieceRule {
    const hi = Math.max(ruleMax(rule, catalog), MODE_FLOOR[rule.mode]);
    const min = clamp(rule.min, MODE_FLOOR[rule.mode], hi);
    return { ...rule, min, max: clamp(rule.max, min, hi) };
}

function compact<T extends object>(value: T): T | undefined {
    const entries = Object.entries(value).filter(([, item]) => item !== undefined);
    return entries.length > 0 ? (Object.fromEntries(entries) as T) : undefined;
}

/** Empty means the whole world. */
export function ruleScope(rule: PieceRule, catalog: LevelCatalog): string[] {
    return rule.scopeMode === "only" ? catalog.tasks.map((task) => task.id).filter((id) => rule.scopeTasks.includes(id)) : [];
}

function rulesToSetPieces(rules: PieceRule[], catalog: LevelCatalog): SetPieceRule[] {
    const entries: { scopeKey: string; rule: { tasks?: string[]; required: Record<string, SetPieceBound> } }[] = [];
    for (const rule of rules) {
        const clamped = effectiveRule(rule, catalog);
        const tasks = ruleScope(rule, catalog);
        const scopeKey = tasks.join("\n");
        const existing = entries.find((entry) => entry.scopeKey === scopeKey && !Object.hasOwn(entry.rule.required, rule.pieceId));
        const target = existing ?? { scopeKey, rule: { ...(tasks.length > 0 ? { tasks } : {}), required: {} } };
        target.rule.required[rule.pieceId] = REQUIREMENT[rule.mode](clamped);
        if (!existing) entries.push(target);
    }
    return entries.map((entry) => entry.rule);
}

function biomesWith(group: CriteriaGroup, choice: BiomeChoice, catalog: LevelCatalog): string[] {
    return catalog.optionalTaskIds.filter((id) => group.biomes[id] === choice);
}

function groupToCriterion(group: CriteriaGroup, catalog: LevelCatalog): Criterion | undefined {
    const sections = compact<Criterion>({
        tasks: compact({
            required: nonEmpty(biomesWith(group, "include", catalog)),
            excluded: nonEmpty(biomesWith(group, "exclude", catalog))
        }),
        prefab_swaps: compact(group.swaps),
        setpieces: nonEmpty(rulesToSetPieces(group.rules, catalog)),
        ...worldSections(group, catalog.shard)
    });
    return sections && { passive: group.passive, ...sections };
}

export function toSeedfinderConfig(state: SearchState): SeedfinderConfig {
    const catalog = levelCatalogOf(state.shard);
    const criteria = nonEmpty(state.groups.flatMap((group) => groupToCriterion(group, catalog) ?? []));
    return {
        version: CONFIG_VERSION,
        shard: state.shard,
        platform: state.platform,
        ...(criteria ? { criteria } : {})
    };
}

function countFromRequirement(requirement: unknown): Pick<PieceRule, "mode" | "min" | "max"> | undefined {
    if (typeof requirement === "number") {
        return requirement >= 1 ? { mode: "atLeast", min: requirement, max: requirement } : {
            mode: "between",
            min: 0,
            max: Infinity
        };
    }
    const [min, max] = asArray(requirement);
    if (typeof min !== "number" || typeof max !== "number") return undefined;
    return { mode: max === 0 ? "none" : min === max ? "exactly" : "between", min, max };
}

function entryToRules(entry: unknown, catalog: LevelCatalog): PieceRule[] {
    const record = asRecord(entry);
    const scopeTasks = asStrings(record.tasks).filter((id) => Object.hasOwn(catalog.taskById, id));
    return Object.entries(asRecord(record.required)).flatMap(([pieceId, requirement]) => {
        const count = countFromRequirement(requirement);
        if (!Object.hasOwn(catalog.setPieceById, pieceId) || !count) return [];
        const scopeMode: ScopeMode = scopeTasks.length > 0 || catalog.setPieceById[pieceId].kind === "fixed" ? "only" : "anywhere";
        return [{ key: newKey(), pieceId, ...count, scopeMode, scopeTasks }];
    });
}

function criterionToGroup(criterion: unknown, catalog: LevelCatalog): CriteriaGroup {
    const record = asRecord(criterion);
    const tasks = asRecord(record.tasks);
    const swaps = asRecord(record.prefab_swaps);
    const biomeEntries = (ids: unknown, choice: BiomeChoice) =>
        asStrings(ids)
            .filter((id) => catalog.optionalTaskIds.includes(id))
            .map((id) => [id, choice] as const);
    return {
        key: newKey(),
        passive: record.passive === true,
        biomes: Object.fromEntries([...biomeEntries(tasks.required, "include"), ...biomeEntries(tasks.excluded, "exclude")]),
        swaps: Object.fromEntries(
            catalog.swaps.filter((swap) => swap.options.some((option) => option.id === swaps[swap.id])).map((swap) => [swap.id, swaps[swap.id]])
        ),
        rules: asArray(record.setpieces).slice(0, MAX_RULES_PER_SECTION).flatMap((entry) => entryToRules(entry, catalog)).slice(0, MAX_RULES_PER_SECTION),
        ...worldRowsOf(record, catalog.shard)
    };
}

export function fromSeedfinderConfig(config: unknown): SearchState {
    const record = asRecord(config);
    const shard = SHARDS.find((candidate) => candidate === record.shard) ?? DEFAULT_SHARD;
    const catalog = levelCatalogOf(shard);
    const groups = asArray(record.criteria).slice(0, MAX_CRITERIA).map((criterion) => criterionToGroup(criterion, catalog));
    return {
        shard,
        platform: PLATFORMS.find((platform) => platform === record.platform) ?? DEFAULT_PLATFORM,
        groups: groups.length > 0 ? groups : [emptyGroup()]
    };
}

export function hasCustomSettings(config: unknown): boolean {
    return Object.values(asRecord(asRecord(config).settings)).some((level) => level !== "default");
}

export function upgradeConfig(config: unknown): unknown {
    if (!isRecord(config)) return config;
    return { version: CONFIG_VERSION, ...Object.fromEntries(Object.entries(config).filter(([key]) => key !== "settings")) };
}

/**
 * The search on another shard: every pick that also exists there stays (the resource varieties, and the world
 * details whose prefabs exist there, with the spawn becoming the other shard's spawn), the biomes and set pieces of
 * the old shard are dropped. `dropped` counts what was lost.
 */
export function switchShard(state: SearchState, shard: Shard): { state: SearchState; dropped: number } {
    if (state.shard === shard) return { state: state, dropped: 0 };
    const to = levelCatalogOf(shard);
    let dropped = 0;
    const groups = state.groups.map((group): CriteriaGroup => {
        const swaps = Object.fromEntries(
            Object.entries(group.swaps).filter(([category, variant]) => to.swaps.some((swap) => swap.id === category && swap.options.some((option) => option.id === variant)))
        );
        const rules = group.rules.filter((rule) => Object.hasOwn(to.setPieceById, rule.pieceId));
        const biomes = Object.fromEntries(Object.entries(group.biomes).filter(([id]) => to.optionalTaskIds.includes(id)));
        dropped += Object.keys(group.swaps).length - Object.keys(swaps).length;
        dropped += group.rules.length - rules.length;
        dropped += Object.keys(group.biomes).length - Object.keys(biomes).length;
        const world = worldRowsFor(group, state.shard, shard);
        dropped += world.dropped;
        return {
            ...group,
            swaps,
            biomes,
            rules: rules.map((rule) => ({
                ...rule,
                scopeTasks: rule.scopeTasks.filter((id) => Object.hasOwn(to.taskById, id))
            })),
            ...world.rows
        };
    });
    return { state: { ...state, shard, groups }, dropped };
}

const levelTableChoices = (group: CriteriaGroup) => Object.keys(group.biomes).length + Object.keys(group.swaps).length + group.rules.length;

export function isEmptyGroup(group: CriteriaGroup): boolean {
    return levelTableChoices(group) + worldRowCount(group) === 0;
}

type GroupCheck = (group: CriteriaGroup, catalog: LevelCatalog) => Issue[];

const tooManyBiomes =
    (choice: BiomeChoice, label: string): GroupCheck =>
        (group, catalog) =>
            biomesWith(group, choice, catalog).length > catalog.optionalPicked
                ? [{
                    severity: "error",
                    message: `more than ${catalog.optionalPicked} biomes are "${label}", but a world only has ${catalog.optionalPicked}.`
                }]
                : [];

const ruleIssues =
    (check: (rule: PieceRule, name: string, catalog: LevelCatalog) => Issue | undefined): GroupCheck =>
        (group, catalog) =>
            group.rules.flatMap((rule) => check(rule, catalog.setPieceById[rule.pieceId]?.name ?? rule.pieceId, catalog) ?? []);

const GROUP_CHECKS: GroupCheck[] = [
    tooManyBiomes("include", "Must have"),
    tooManyBiomes("exclude", "Must not have"),
    ruleIssues((rule, name, catalog) => {
        const unscoped = ruleScope(rule, catalog).length === 0;
        if (unscoped && catalog.setPieceById[rule.pieceId]?.kind === "fixed")
            return {
                severity: "warning",
                message: `every world has the same number of ${name}. Pick the biomes you want it in.`
            };
        return rule.scopeMode === "only" && unscoped
            ? { severity: "warning", message: `${name} has no biomes picked, so it counts everywhere.` }
            : undefined;
    }),
    ruleIssues((rule, name, catalog) =>
        catalog.setPieceById[rule.pieceId]?.alwaysPlaced && rule.mode === "none" && ruleScope(rule, catalog).length === 0
            ? { severity: "error", message: `${name} is in every world, so "None" can never match.` }
            : undefined
    ),
    (group, catalog) => {
        const leastPerPiece = new Map<string, number>();
        for (const rule of group.rules) {
            if (rule.mode !== "none") leastPerPiece.set(rule.pieceId, Math.max(leastPerPiece.get(rule.pieceId) ?? 0, effectiveRule(rule, catalog).min));
        }
        return Object.entries(KIND_TOTALS).flatMap(([kind, { most, noun }]): Issue[] => {
            const needed = [...leastPerPiece].reduce((sum, [pieceId, least]) => sum + (catalog.setPieceById[pieceId]?.kind === kind ? least : 0), 0);
            return needed > most ? [{
                severity: "error",
                message: `the set pieces ask for at least ${needed} ${noun} in total, but a world has at most ${most}.`
            }] : [];
        });
    },
    (group) =>
        !group.passive && worldRowCount(group) > 0 && levelTableChoices(group) === 0
            ? [{
                severity: "warning",
                message: "only world details are picked, so every seed's world gets generated. Add a biome, resource or set piece to speed it up."
            }]
            : [],
    (group, catalog) => worldIssues(group, catalog.shard)
];

/** An error means the search can never match. */
export function validateSearch(state: SearchState): Issue[] {
    const catalog = levelCatalogOf(state.shard);
    const multiple = state.groups.length > 1;
    const perGroup = state.groups.flatMap((group, index) => {
        const label = (message: string) => (multiple ? `Option ${index + 1}: ${message}` : message.charAt(0).toUpperCase() + message.slice(1));
        const emptyWarning: Issue[] =
            multiple && isEmptyGroup(group) ? [{
                severity: "warning",
                message: "nothing picked, so it's ignored."
            }] : [];
        const issues = [...emptyWarning, ...GROUP_CHECKS.flatMap((check) => check(group, catalog))];
        return issues.map((issue) => ({ ...issue, message: label(issue.message) }));
    });
    const picked = state.groups.filter((group) => !isEmptyGroup(group));
    const nothing: Issue[] = picked.length === 0 ? [{
        severity: "warning",
        message: "Nothing picked yet, so every world matches."
    }] : [];
    const allPassive: Issue[] =
        picked.length > 0 && picked.every((group) => group.passive)
            ? [{
                severity: "error",
                message: "Every option is passive. At least one option has to pick the seeds the passive ones are checked on."
            }]
            : [];
    const issues = [...nothing, ...allPassive, ...perGroup];
    if (issues.some((issue) => issue.severity === "error")) return issues;
    const checked = validateConfig(toSeedfinderConfig(state));
    return checked.ok ? issues : [...issues, {
        severity: "error",
        message: `This search can't be sent: ${checked.error}`
    }];
}

export function encodeShareParam(config: SeedfinderConfig): string {
    const bytes = new TextEncoder().encode(JSON.stringify(config));
    const binary = Array.from(bytes, (byte) => String.fromCharCode(byte)).join("");
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function decodeShareParam(param: string): unknown {
    try {
        const binary = atob(param.replace(/-/g, "+").replace(/_/g, "/"));
        const json = new TextDecoder().decode(Uint8Array.from(binary, (char) => char.charCodeAt(0)));
        return JSON.parse(json) as unknown;
    } catch {
        return null;
    }
}

function presetState(shard: Shard, ...groups: Partial<CriteriaGroup>[]): SearchState {
    return { shard, platform: DEFAULT_PLATFORM, groups: groups.map((group) => ({ ...emptyGroup(), ...group })) };
}

const atLeast = (shard: Shard, pieceId: string, min: number): PieceRule => ({
    ...newRule(pieceId, levelCatalogOf(shard)),
    min
});

const tiles = (count: number) => count * WORLD_UNITS_PER_TILE;

const FOREST_PRESETS: Preset[] = [
    {
        id: "walking-cane",
        name: "Guaranteed Walking Cane",
        description: "World will contain a walking cane.",
        build: () => presetState("forest", {
            rules: [atLeast("forest", "MiscBoon", 5)],
            counts: [{ ...NEW_WORLD_ROW.counts("forest"), prefabs: ["cane"] }]
        })
    },
    {
        id: "dark-sword-at-spawn",
        name: "Dark Sword at spawn",
        description: "Dark Sword within 15 tiles of the world spawn. Will take a few minutes.",
        build: () =>
            presetState("forest", {
                rules: [atLeast("forest", "Level4Boon", 4)],
                distances: [{ ...NEW_WORLD_ROW.distances("forest"), to: ["nightsword"], max: tiles(15) }]
            })
    },
    {
        id: "twiggy-juicy",
        name: "Twiggy trees + juicy berries",
        description: "Both swapped resources in the same world.",
        build: () => presetState("forest", { swaps: { twigs: "twiggy trees", berries: "juicy berries" } })
    },
    {
        id: "no-killer-bees",
        name: "No killer bees",
        description: "Skips all worlds with killer bees.",
        build: () => presetState("forest", { biomes: { "Killer bees!": "exclude" } })
    }
];

const CAVE_PRESETS: Preset[] = [
    {
        id: "guardian-walking-with-tentacles",
        name: "Ancient Guardian within 75 tiles (walking)",
        description: "The Ancient Guardian within 75 tiles of walking from the stairs, counting the jumps through Big Tentacles. Will take a few minutes.",
        build: () =>
            presetState("caves", {
                distances: [{
                    ...NEW_WORLD_ROW.distances("caves"),
                    to: ["minotaur_spawner"],
                    max: tiles(75),
                    metric: "walk",
                    links: true
                }]
            })
    },
    {
        id: "atrium-at-spawn",
        name: "Atrium Gateway at spawn",
        description: "The Ancient Gateway within 20 tiles of walking from the stairs, without the tentacles. This is usually a bugged world. This is a very rare world so it may take a few hours.",
        build: () =>
            presetState("caves", {
                distances: [{
                    ...NEW_WORLD_ROW.distances("caves"),
                    to: ["atrium_gate"],
                    max: tiles(20),
                    metric: "walk"
                }]
            })
    },
    {
        id: "twiggy-juicy",
        name: "Twiggy trees + juicy berries",
        description: "Both swapped resources in the same world.",
        build: () => presetState("caves", { swaps: { twigs: "twiggy trees", berries: "juicy berries" } })
    },
    {
        id: "jungle-without-spiders",
        name: "Cave jungle, no spider land",
        description: "The cave jungle biome without the spider land.",
        build: () => presetState("caves", { biomes: { CaveJungle: "include", SpiderLand: "exclude" } })
    }
];

export const PRESETS: Record<Shard, Preset[]> = { forest: FOREST_PRESETS, caves: CAVE_PRESETS };
