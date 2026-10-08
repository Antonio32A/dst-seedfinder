import { type LevelCatalog, levelCatalogOf } from "@/lib/catalog/level-catalog";
import type { SetPieceKind, SwapCategory } from "@/lib/catalog/level-types";
import {
    CONFIG_VERSION,
    DEFAULT_PLATFORM,
    DEFAULT_SHARD,
    type Filter,
    type Generation,
    MAX_FILTERS,
    MAX_RULES_PER_SECTION,
    optionName,
    type Platform,
    PLATFORMS,
    type SeedfinderConfig,
    type SetPieceBound,
    type SetPieceGroup,
    type SetPieceItem,
    type SetPieceRule,
    type Shard,
    SHARDS,
    WORLD_UNITS_PER_TILE
} from "@/lib/config/seedfinder-config";
import { dropsLevelTables, upgradeConfig } from "@/lib/config/upgrade-config";
import { validateConfig } from "@/lib/config/validate-config";
import { asRecord } from "@/lib/records";
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
    ensurePlaced: boolean;
}

export type GroupMatch = "any" | Exclude<CountMode, "none">;

/** Set pieces of which a world needs any one, or, with a total match, that many of all of them together. */
export interface PieceGroup {
    key: string;
    rules: PieceRule[];
    match: GroupMatch;
    min: number;
    max: number;
}

/** The picks decided from the seed alone, before its world is generated: they pick the worlds to generate. */
export interface GenerationPicks {
    biomes: Record<string, BiomeChoice>;
    swaps: Partial<Record<SwapCategory, string>>;
    rules: PieceRule[];
    pieceGroups: PieceGroup[];
}

/** World details checked on a generated world; a world matches when any filter holds. */
export interface WorldFilter extends WorldRows {
    key: string;
    name: string;
}

export interface SearchState {
    shard: Shard;
    platform: Platform;
    generation: GenerationPicks;
    filters: WorldFilter[];
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
export const LEVEL_TABLES_DROPPED_NOTICE =
    "Its options had different biomes, resources or set pieces, so only the first option's were kept.";

export const COUNT_MODES: { id: CountMode; label: string }[] = [
    { id: "atLeast", label: "At least" },
    { id: "exactly", label: "Exactly" },
    { id: "between", label: "Between" },
    { id: "none", label: "None" }
];

export const GROUP_MATCHES: { id: GroupMatch; label: string }[] = [
    { id: "any", label: "Any one" },
    { id: "atLeast", label: "Total at least" },
    { id: "exactly", label: "Total exactly" },
    { id: "between", label: "Total between" }
];

const MODE_FLOOR: Record<CountMode, number> = { atLeast: 1, exactly: 1, between: 0, none: 0 };

const KIND_TOTALS: Partial<Record<SetPieceKind, { most: number; noun: string }>> = {
    boon: { most: 8, noun: "boons" },
    trap: { most: 1, noun: "traps" },
    poi: { most: 1, noun: "points of interest" },
    protected: { most: 1, noun: "guarded resources" }
};

const REQUIREMENT: Record<CountMode, (count: Pick<PieceRule, "min" | "max">) => SetPieceBound> = {
    atLeast: (rule) => rule.min,
    exactly: (rule) => [rule.min, rule.min],
    between: (rule) => [rule.min, rule.max],
    none: () => [0, 0]
};

export function emptyGeneration(): GenerationPicks {
    return { biomes: {}, swaps: {}, rules: [], pieceGroups: [] };
}

export function emptyFilter(): WorldFilter {
    return { key: newKey(), name: "", counts: [], distances: [], tiles: [], bridges: [], routes: [] };
}

export function defaultState(): SearchState {
    return {
        shard: DEFAULT_SHARD,
        platform: DEFAULT_PLATFORM,
        generation: emptyGeneration(),
        filters: [emptyFilter()]
    };
}

export function newRule(pieceId: string, catalog: LevelCatalog): PieceRule {
    const fixed = catalog.setPieceById.get(pieceId)?.kind === "fixed";
    return {
        key: newKey(),
        pieceId,
        mode: "atLeast",
        min: 1,
        max: 1,
        scopeMode: fixed ? "only" : "anywhere",
        scopeTasks: [],
        ensurePlaced: false
    };
}

export function newPieceGroup(): PieceGroup {
    return { key: newKey(), rules: [], match: "any", min: 1, max: 1 };
}

export function ruleMax(rule: PieceRule, catalog: LevelCatalog): number {
    const piece = catalog.setPieceById.get(rule.pieceId);
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

/** The most a group's set pieces can add up to, each kind capped at what a world can have. */
export function totalMax(pieceGroup: PieceGroup, catalog: LevelCatalog): number {
    const byKind = new Map<SetPieceKind, number>();
    for (const rule of pieceGroup.rules) {
        const kind = catalog.setPieceById.get(rule.pieceId)?.kind;
        if (kind) byKind.set(kind, (byKind.get(kind) ?? 0) + ruleMax(rule, catalog));
    }
    return [...byKind].reduce((sum, [kind, most]) => sum + Math.min(most, KIND_TOTALS[kind]?.most ?? Infinity), 0);
}

export function effectiveTotal(pieceGroup: PieceGroup, catalog: LevelCatalog): PieceGroup {
    const floor = pieceGroup.match === "any" ? 0 : MODE_FLOOR[pieceGroup.match];
    const hi = Math.max(totalMax(pieceGroup, catalog), floor);
    const min = clamp(pieceGroup.min, floor, hi);
    return { ...pieceGroup, min, max: clamp(pieceGroup.max, min, hi) };
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
    const entries: { scopeKey: string; rule: SetPieceRule & { required: Record<string, SetPieceBound> } }[] = [];
    for (const rule of rules) {
        const clamped = effectiveRule(rule, catalog);
        const tasks = ruleScope(rule, catalog);
        const scopeKey = tasks.join("\n");
        const existing = entries.find((entry) =>
            entry.scopeKey === scopeKey && !Object.hasOwn(entry.rule.required, rule.pieceId));
        const target = existing ?? { scopeKey, rule: { ...(tasks.length > 0 ? { tasks } : {}), required: {} } };
        target.rule.required[rule.pieceId] = REQUIREMENT[rule.mode](clamped);
        if (rule.ensurePlaced && catalog.shard === "forest") target.rule.placed = [...(target.rule.placed ?? []), rule.pieceId];
        if (!existing) entries.push(target);
    }
    return entries.map((entry) => entry.rule);
}

function ruleToSetPiece(rule: PieceRule, catalog: LevelCatalog, bound?: SetPieceBound): SetPieceRule {
    const tasks = ruleScope(rule, catalog);
    return {
        ...(tasks.length > 0 ? { tasks } : {}),
        required: { [rule.pieceId]: bound ?? REQUIREMENT[rule.mode](effectiveRule(rule, catalog)) },
        ...(rule.ensurePlaced && catalog.shard === "forest" ? { placed: [rule.pieceId] } : {})
    };
}

/** With a total match, only the total bounds the set pieces, so each of them is at least 0. */
function pieceGroupItem(pieceGroup: PieceGroup, catalog: LevelCatalog): SetPieceGroup {
    if (pieceGroup.match === "any") return { any: pieceGroup.rules.map((rule) => ruleToSetPiece(rule, catalog)) };
    return {
        any: pieceGroup.rules.map((rule) => ruleToSetPiece(rule, catalog, 0)),
        total: REQUIREMENT[pieceGroup.match](effectiveTotal(pieceGroup, catalog))
    };
}

function setPieceItems(generation: GenerationPicks, catalog: LevelCatalog): SetPieceItem[] {
    const anyOf = generation.pieceGroups
        .filter((pieceGroup) => pieceGroup.rules.length > 0)
        .map((pieceGroup) => pieceGroupItem(pieceGroup, catalog));
    return [...rulesToSetPieces(generation.rules, catalog), ...anyOf];
}

function biomesWith(generation: GenerationPicks, choice: BiomeChoice, catalog: LevelCatalog): string[] {
    return catalog.optionalTaskIds.filter((id) => generation.biomes[id] === choice);
}

function toGeneration(generation: GenerationPicks, catalog: LevelCatalog): Generation | undefined {
    return compact<Generation>({
        tasks: compact({
            required: nonEmpty(biomesWith(generation, "include", catalog)),
            excluded: nonEmpty(biomesWith(generation, "exclude", catalog))
        }),
        prefab_swaps: compact(generation.swaps),
        setpieces: nonEmpty(setPieceItems(generation, catalog))
    });
}

export function toSeedfinderConfig(state: SearchState): SeedfinderConfig {
    const catalog = levelCatalogOf(state.shard);
    const generation = toGeneration(state.generation, catalog);
    const filters = nonEmpty(state.filters.flatMap((filter) => {
        const sections = compact<Filter>(worldSections(filter, state.shard));
        const name = filter.name.trim();
        return sections ? [{ ...(name ? { name } : {}), ...sections }] : [];
    }));
    return {
        version: CONFIG_VERSION,
        shard: state.shard,
        platform: state.platform,
        ...(generation ? { generation } : {}),
        ...(filters ? { filters } : {})
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
    const scopeTasks = asStrings(record.tasks).filter((id) => catalog.taskById.has(id));
    const placed = catalog.shard === "forest" ? asStrings(record.placed) : [];
    return Object.entries(asRecord(record.required)).flatMap(([pieceId, requirement]) => {
        const count = countFromRequirement(requirement);
        const piece = catalog.setPieceById.get(pieceId);
        if (!piece || !count) return [];
        const scopeMode: ScopeMode = scopeTasks.length > 0 || piece.kind === "fixed" ? "only" : "anywhere";
        return [{ key: newKey(), pieceId, ...count, scopeMode, scopeTasks, ensurePlaced: placed.includes(pieceId) }];
    });
}

const isGroupItem = (item: unknown) => Object.hasOwn(asRecord(item), "any");

function itemToPieceGroup(item: unknown, catalog: LevelCatalog): PieceGroup {
    const record = asRecord(item);
    const total = record.total === undefined ? undefined : countFromRequirement(record.total);
    const rules = itemsToRules(asArray(record.any), catalog);
    const match = total?.mode === "none" ? "between" : total?.mode ?? "any";
    return { ...newPieceGroup(), ...(total && { min: total.min, max: total.max }), rules, match };
}

const itemsToRules = (items: unknown[], catalog: LevelCatalog) =>
    items.flatMap((item) => entryToRules(item, catalog)).slice(0, MAX_RULES_PER_SECTION);

function generationPicksOf(generation: unknown, catalog: LevelCatalog): GenerationPicks {
    const record = asRecord(generation);
    const items = asArray(record.setpieces).slice(0, MAX_RULES_PER_SECTION);
    const tasks = asRecord(record.tasks);
    const swaps = asRecord(record.prefab_swaps);
    const biomeEntries = (ids: unknown, choice: BiomeChoice) =>
        asStrings(ids)
            .filter((id) => catalog.optionalTaskIds.includes(id))
            .map((id) => [id, choice] as const);
    return {
        biomes: Object.fromEntries([
            ...biomeEntries(tasks.required, "include"),
            ...biomeEntries(tasks.excluded, "exclude")
        ]),
        swaps: Object.fromEntries(
            catalog.swaps
                .filter((swap) => swap.options.some((option) => option.id === swaps[swap.id]))
                .map((swap) => [swap.id, swaps[swap.id]])
        ),
        rules: itemsToRules(items.filter((item) => !isGroupItem(item)), catalog),
        pieceGroups: items
            .filter(isGroupItem)
            .map((item) => itemToPieceGroup(item, catalog))
            .filter((pieceGroup) => pieceGroup.rules.length > 0)
    };
}

/** Reads a config of any format version (upgradeConfig). */
export function fromSeedfinderConfig(config: unknown): SearchState {
    const record = asRecord(upgradeConfig(config));
    const shard = SHARDS.find((candidate) => candidate === record.shard) ?? DEFAULT_SHARD;
    const filters = asArray(record.filters)
        .slice(0, MAX_FILTERS)
        .map(asRecord)
        .map((filter): WorldFilter => ({
            key: newKey(),
            name: typeof filter.name === "string" ? filter.name : "",
            ...worldRowsOf(filter, shard)
        }));
    return {
        shard,
        platform: PLATFORMS.find((platform) => platform === record.platform) ?? DEFAULT_PLATFORM,
        generation: generationPicksOf(record.generation, levelCatalogOf(shard)),
        filters: filters.length > 0 ? filters : [emptyFilter()]
    };
}

export function hasCustomSettings(config: unknown): boolean {
    return Object.values(asRecord(asRecord(config).settings)).some((level) => level !== "default");
}

/** What loading the config leaves out, as a notice (empty when nothing). */
export function droppedNotice(config: unknown): string {
    return [
        hasCustomSettings(config) ? SETTINGS_DROPPED_NOTICE : "",
        dropsLevelTables(config) ? LEVEL_TABLES_DROPPED_NOTICE : ""
    ].filter(Boolean).join(" ");
}

function movedGeneration(generation: GenerationPicks, shard: Shard): { generation: GenerationPicks; dropped: number } {
    const to = levelCatalogOf(shard);
    let dropped = 0;
    const swaps = Object.fromEntries(
        Object.entries(generation.swaps).filter(([category, variant]) => to.swaps.some((swap) =>
            swap.id === category && swap.options.some((option) => option.id === variant)))
    );
    const moveRules = (rules: PieceRule[]) => {
        const kept = rules.filter((rule) => to.setPieceById.has(rule.pieceId));
        dropped += rules.length - kept.length + kept.filter((rule) => rule.ensurePlaced && shard !== "forest").length;
        return kept.map((rule) => ({
            ...rule,
            scopeTasks: rule.scopeTasks.filter((id) => to.taskById.has(id)),
            ensurePlaced: rule.ensurePlaced && shard === "forest"
        }));
    };
    const rules = moveRules(generation.rules);
    const pieceGroups = generation.pieceGroups
        .map((pieceGroup) => ({ ...pieceGroup, rules: moveRules(pieceGroup.rules) }))
        .filter((pieceGroup) => pieceGroup.rules.length > 0);
    const biomes = Object.fromEntries(
        Object.entries(generation.biomes).filter(([id]) => to.optionalTaskIds.includes(id))
    );
    dropped += Object.keys(generation.swaps).length - Object.keys(swaps).length;
    dropped += Object.keys(generation.biomes).length - Object.keys(biomes).length;
    return { generation: { swaps, biomes, rules, pieceGroups }, dropped };
}

/**
 * The search on another shard: every pick that also exists there stays (the resource varieties, and the world
 * details whose prefabs exist there, with the spawn becoming the other shard's spawn), the biomes and set pieces of
 * the old shard are dropped. `dropped` counts what was lost.
 */
export function switchShard(state: SearchState, shard: Shard): { state: SearchState; dropped: number } {
    if (state.shard === shard) return { state, dropped: 0 };
    const moved = movedGeneration(state.generation, shard);
    let dropped = moved.dropped;
    const filters = state.filters.map((filter): WorldFilter => {
        const world = worldRowsFor(filter, state.shard, shard);
        dropped += world.dropped;
        return { ...filter, ...world.rows };
    });
    return { state: { ...state, shard, generation: moved.generation, filters }, dropped };
}

/** A total match ignores its set pieces' own counts. */
const groupedRules = (generation: GenerationPicks) =>
    generation.pieceGroups.flatMap((pieceGroup) => pieceGroup.match === "any"
        ? pieceGroup.rules
        : pieceGroup.rules.map((rule): PieceRule => ({ ...rule, mode: "between", min: 0 })));

const generationChoices = (generation: GenerationPicks) =>
    Object.keys(generation.biomes).length + Object.keys(generation.swaps).length + generation.rules.length
    + groupedRules(generation).length;

export function isEmptySearch(state: SearchState): boolean {
    return generationChoices(state.generation) === 0 && state.filters.every((filter) => worldRowCount(filter) === 0);
}

type GenerationCheck = (generation: GenerationPicks, catalog: LevelCatalog) => Issue[];

const tooManyBiomes =
    (choice: BiomeChoice, label: string): GenerationCheck =>
        (generation, catalog) =>
            biomesWith(generation, choice, catalog).length > catalog.optionalPicked
                ? [{
                    severity: "error",
                    message: `more than ${catalog.optionalPicked} biomes are "${label}", but a world only has ${catalog.optionalPicked}.`
                }]
                : [];

/** A set piece group only needs one of its picks, so a pick in one that can never match is just a warning. */
const ruleIssues =
    (check: (rule: PieceRule, name: string, catalog: LevelCatalog) => Issue | undefined): GenerationCheck =>
        (generation, catalog) => {
            const issuesOf = (rule: PieceRule) =>
                check(rule, catalog.setPieceById.get(rule.pieceId)?.name ?? rule.pieceId, catalog) ?? [];
            return [
                ...generation.rules.flatMap(issuesOf),
                ...groupedRules(generation).flatMap(issuesOf).map((issue): Issue => ({ ...issue, severity: "warning" }))
            ];
        };

const GENERATION_CHECKS: GenerationCheck[] = [
    tooManyBiomes("include", "Must have"),
    tooManyBiomes("exclude", "Must not have"),
    ruleIssues((rule, name, catalog) => {
        const unscoped = ruleScope(rule, catalog).length === 0;
        if (unscoped && catalog.setPieceById.get(rule.pieceId)?.kind === "fixed")
            return {
                severity: "warning",
                message: `every world has the same number of ${name}. Pick the biomes you want it in.`
            };
        return rule.scopeMode === "only" && unscoped
            ? { severity: "warning", message: `${name} has no biomes picked, so it counts everywhere.` }
            : undefined;
    }),
    ruleIssues((rule, name, catalog) =>
        catalog.setPieceById.get(rule.pieceId)?.alwaysPlaced && rule.mode === "none" && ruleScope(rule, catalog).length === 0
            ? { severity: "error", message: `${name} is in every world, so "None" can never match.` }
            : undefined
    ),
    (generation, catalog) => {
        const leastPerPiece = new Map<string, number>();
        for (const rule of generation.rules) {
            if (rule.mode !== "none") leastPerPiece.set(rule.pieceId, Math.max(leastPerPiece.get(rule.pieceId) ?? 0, effectiveRule(rule, catalog).min));
        }
        return Object.entries(KIND_TOTALS).flatMap(([kind, { most, noun }]): Issue[] => {
            const needed = [...leastPerPiece].reduce(
                (sum, [pieceId, least]) => sum + (catalog.setPieceById.get(pieceId)?.kind === kind ? least : 0),
                0
            );
            return needed > most ? [{
                severity: "error",
                message: `the set pieces ask for at least ${needed} ${noun} in total, but a world has at most ${most}.`
            }] : [];
        });
    },
    (generation) =>
        generation.pieceGroups.some((pieceGroup) => pieceGroup.rules.length === 0)
            ? [{ severity: "warning", message: "a set piece group has no set pieces, so it's ignored." }]
            : []
];

const capitalized = (message: string) => message.charAt(0).toUpperCase() + message.slice(1);

function filterIssues(state: SearchState): Issue[] {
    const multiple = state.filters.length > 1;
    return state.filters.flatMap((filter, index) => {
        const labelled = multiple || filter.name.trim() !== "";
        const label = (message: string) => (labelled ? `${optionName(filter, index)}: ${message}` : capitalized(message));
        const empty: Issue[] = multiple && worldRowCount(filter) === 0
            ? [{ severity: "warning", message: "nothing picked, so it's ignored." }]
            : [];
        return [...empty, ...worldIssues(filter, state.shard)]
            .map((issue) => ({ ...issue, message: label(issue.message) }));
    });
}

function coverageIssues(state: SearchState): Issue[] {
    if (generationChoices(state.generation) > 0) return [];
    return state.filters.some((filter) => worldRowCount(filter) > 0)
        ? [{
            severity: "warning",
            message: "Only world filters are picked, so every seed's world gets generated. Add a biome, resource or set piece to speed it up."
        }]
        : [{ severity: "warning", message: "Nothing picked yet, so every world matches." }];
}

/** An error means the search can never match. */
export function validateSearch(state: SearchState): Issue[] {
    const catalog = levelCatalogOf(state.shard);
    const generation = GENERATION_CHECKS.flatMap((check) => check(state.generation, catalog))
        .map((issue) => ({ ...issue, message: capitalized(issue.message) }));
    const issues = [...coverageIssues(state), ...generation, ...filterIssues(state)];
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

function presetState(shard: Shard, generation: Partial<GenerationPicks>, filter: Partial<WorldRows> = {}): SearchState {
    return {
        shard,
        platform: DEFAULT_PLATFORM,
        generation: { ...emptyGeneration(), ...generation },
        filters: [{ ...emptyFilter(), ...filter }]
    };
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
        build: () => presetState(
            "forest",
            { rules: [atLeast("forest", "MiscBoon", 5)] },
            { counts: [{ ...NEW_WORLD_ROW.counts("forest"), prefabs: ["cane"] }] }
        )
    },
    {
        id: "dark-sword-at-spawn",
        name: "Dark Sword at spawn",
        description: "Dark Sword within 15 tiles of the world spawn. Will take a few minutes.",
        build: () =>
            presetState(
                "forest",
                { rules: [atLeast("forest", "Level4Boon", 4)] },
                { distances: [{ ...NEW_WORLD_ROW.distances("forest"), to: ["nightsword"], max: tiles(15) }] }
            )
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
            presetState("caves", {}, {
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
            presetState("caves", {}, {
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
