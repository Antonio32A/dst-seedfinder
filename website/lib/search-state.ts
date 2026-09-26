import type { SetPieceKind, SwapCategory } from "./catalog-types";
import {
  CONFIG_VERSION,
  DEFAULT_PLATFORM,
  MAX_CRITERIA,
  MAX_RULES_PER_SECTION,
  PLATFORMS,
  type Criterion,
  type Platform,
  type SeedfinderConfig,
  type SetPieceBound,
  type SetPieceRule,
} from "./seedfinder-config";
import { OPTIONAL_TASK_IDS, SET_PIECE_BY_ID, SWAPS, TASKS } from "./catalog";
import { asArray, asRecord, asStrings, clamp, newKey } from "./state-helpers";
import { validateConfig } from "./validate-config";
import { emptyWorldRows, worldIssues, worldRowCount, worldRowsOf, worldSections, type WorldRows } from "./world-rules";

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

export const MAX_BIOME_CHOICES = 5;
export const WANTED_OPTIONS = [1, 10, 25, 50, 100];
export const DEFAULT_WANTED = 25;
export const STORAGE_KEY = "dst-seedfinder:search:v1";

export const SETTINGS_DROPPED_NOTICE = "Custom world settings were dropped, only default settings are supported.";

export const COUNT_MODES: { id: CountMode; label: string }[] = [
  { id: "atLeast", label: "At least" },
  { id: "exactly", label: "Exactly" },
  { id: "between", label: "Between" },
  { id: "none", label: "None" },
];

const MODE_FLOOR: Record<CountMode, number> = { atLeast: 1, exactly: 1, between: 0, none: 0 };

const KIND_TOTALS: Partial<Record<SetPieceKind, { most: number; noun: string }>> = {
  boon: { most: 8, noun: "boons" },
  trap: { most: 1, noun: "traps" },
  poi: { most: 1, noun: "points of interest" },
  protected: { most: 1, noun: "guarded resources" },
};

const REQUIREMENT: Record<CountMode, (rule: PieceRule) => SetPieceBound> = {
  atLeast: (rule) => rule.min,
  exactly: (rule) => [rule.min, rule.min],
  between: (rule) => [rule.min, rule.max],
  none: () => [0, 0],
};

const TASK_IDS = TASKS.map((task) => task.id);

/** A group with nothing picked; `passive` groups are only checked on seeds the other groups already pick. */
export function emptyGroup(passive = false): CriteriaGroup {
  return { key: newKey(), passive, biomes: {}, swaps: {}, rules: [], ...emptyWorldRows() };
}

export function defaultState(): SearchState {
  return { platform: DEFAULT_PLATFORM, groups: [emptyGroup()] };
}

export function newRule(pieceId: string): PieceRule {
  const fixed = SET_PIECE_BY_ID[pieceId]?.kind === "fixed";
  return { key: newKey(), pieceId, mode: "atLeast", min: 1, max: 1, scopeMode: fixed ? "only" : "anywhere", scopeTasks: [] };
}

/** The realistic maximum count for a rule on default world settings. */
export function ruleMax(rule: PieceRule): number {
  const piece = SET_PIECE_BY_ID[rule.pieceId];
  if (!piece) return 0;
  const scope = ruleScope(rule);
  const onePerBiome = piece.kind === "fixed" && scope.length > 0 ? scope.filter((id) => piece.candidateTasks?.includes(id)).length : Infinity;
  return Math.min(piece.maxCount, KIND_TOTALS[piece.kind]?.most ?? Infinity, onePerBiome);
}

/** The rule as searched and shown: its counts clamped into the realistic range for its mode, with min never above max. */
export function effectiveRule(rule: PieceRule): PieceRule {
  const hi = Math.max(ruleMax(rule), MODE_FLOOR[rule.mode]);
  const min = clamp(rule.min, MODE_FLOOR[rule.mode], hi);
  return { ...rule, min, max: clamp(rule.max, min, hi) };
}

function compact<T extends object>(value: T): T | undefined {
  const entries = Object.entries(value).filter(([, item]) => item !== undefined);
  return entries.length > 0 ? (Object.fromEntries(entries) as T) : undefined;
}

function nonEmpty<T>(items: T[]): T[] | undefined {
  return items.length > 0 ? items : undefined;
}

/** The known tasks a rule is limited to, once each and in catalog order; empty means the whole world. */
export function ruleScope(rule: PieceRule): string[] {
  return rule.scopeMode === "only" ? TASK_IDS.filter((id) => rule.scopeTasks.includes(id)) : [];
}

function rulesToSetPieces(rules: PieceRule[]): SetPieceRule[] {
  const entries: { scopeKey: string; rule: { tasks?: string[]; required: Record<string, SetPieceBound> } }[] = [];
  for (const rule of rules) {
    const clamped = effectiveRule(rule);
    const tasks = ruleScope(rule);
    const scopeKey = tasks.join("\n");
    const existing = entries.find((entry) => entry.scopeKey === scopeKey && !Object.hasOwn(entry.rule.required, rule.pieceId));
    const target = existing ?? { scopeKey, rule: { ...(tasks.length > 0 ? { tasks } : {}), required: {} } };
    target.rule.required[rule.pieceId] = REQUIREMENT[rule.mode](clamped);
    if (!existing) entries.push(target);
  }
  return entries.map((entry) => entry.rule);
}

function biomesWith(group: CriteriaGroup, choice: BiomeChoice): string[] {
  return OPTIONAL_TASK_IDS.filter((id) => group.biomes[id] === choice);
}

function groupToCriterion(group: CriteriaGroup): Criterion | undefined {
  const sections = compact<Criterion>({
    tasks: compact({ required: nonEmpty(biomesWith(group, "include")), excluded: nonEmpty(biomesWith(group, "exclude")) }),
    prefab_swaps: compact(group.swaps),
    setpieces: nonEmpty(rulesToSetPieces(group.rules)),
    ...worldSections(group),
  });
  return sections && { passive: group.passive, ...sections };
}

/** Builds the strict seedfinder JSON config, omitting empty parts. */
export function toSeedfinderConfig(state: SearchState): SeedfinderConfig {
  const criteria = nonEmpty(state.groups.flatMap((group) => groupToCriterion(group) ?? []));
  return {
    version: CONFIG_VERSION,
    platform: state.platform,
    ...(criteria ? { criteria } : {}),
  };
}

function countFromRequirement(requirement: unknown): Pick<PieceRule, "mode" | "min" | "max"> | undefined {
  if (typeof requirement === "number") {
    return requirement >= 1 ? { mode: "atLeast", min: requirement, max: requirement } : { mode: "between", min: 0, max: Infinity };
  }
  const [min, max] = asArray(requirement);
  if (typeof min !== "number" || typeof max !== "number") return undefined;
  return { mode: max === 0 ? "none" : min === max ? "exactly" : "between", min, max };
}

function entryToRules(entry: unknown): PieceRule[] {
  const record = asRecord(entry);
  const scopeTasks = asStrings(record.tasks).filter((id) => TASK_IDS.includes(id));
  return Object.entries(asRecord(record.required)).flatMap(([pieceId, requirement]) => {
    const count = countFromRequirement(requirement);
    if (!Object.hasOwn(SET_PIECE_BY_ID, pieceId) || !count) return [];
    const scopeMode: ScopeMode = scopeTasks.length > 0 || SET_PIECE_BY_ID[pieceId].kind === "fixed" ? "only" : "anywhere";
    return [{ key: newKey(), pieceId, ...count, scopeMode, scopeTasks }];
  });
}

function criterionToGroup(criterion: unknown): CriteriaGroup {
  const record = asRecord(criterion);
  const tasks = asRecord(record.tasks);
  const swaps = asRecord(record.prefab_swaps);
  const biomeEntries = (ids: unknown, choice: BiomeChoice) =>
    asStrings(ids)
      .filter((id) => OPTIONAL_TASK_IDS.includes(id))
      .map((id) => [id, choice] as const);
  return {
    key: newKey(),
    passive: record.passive === true,
    biomes: Object.fromEntries([...biomeEntries(tasks.required, "include"), ...biomeEntries(tasks.excluded, "exclude")]),
    swaps: Object.fromEntries(
      SWAPS.filter((swap) => swap.options.some((option) => option.id === swaps[swap.id])).map((swap) => [swap.id, swaps[swap.id]]),
    ),
    rules: asArray(record.setpieces).slice(0, MAX_RULES_PER_SECTION).flatMap(entryToRules).slice(0, MAX_RULES_PER_SECTION),
    ...worldRowsOf(record),
  };
}

/** Rebuilds UI state from a (possibly old, hand-written or untrusted) seedfinder config, dropping unknown ids and settings. */
export function fromSeedfinderConfig(config: unknown): SearchState {
  const record = asRecord(config);
  const groups = asArray(record.criteria).slice(0, MAX_CRITERIA).map(criterionToGroup);
  return {
    platform: PLATFORMS.find((platform) => platform === record.platform) ?? DEFAULT_PLATFORM,
    groups: groups.length > 0 ? groups : [emptyGroup()],
  };
}

/** Whether an (older) config asked for world settings other than the defaults, which importing it drops. */
export function hasCustomSettings(config: unknown): boolean {
  return Object.values(asRecord(asRecord(config).settings)).some((level) => level !== "default");
}

/** Brings an older config up to the current format: the missing version is filled in and world settings are dropped. */
export function upgradeConfig(config: unknown): unknown {
  if (typeof config !== "object" || config === null || Array.isArray(config)) return config;
  return { version: CONFIG_VERSION, ...Object.fromEntries(Object.entries(config).filter(([key]) => key !== "settings")) };
}

const levelTableChoices = (group: CriteriaGroup) => Object.keys(group.biomes).length + Object.keys(group.swaps).length + group.rules.length;

/** Whether a group asks for nothing (and so is left out of the config). */
export function isEmptyGroup(group: CriteriaGroup): boolean {
  return levelTableChoices(group) + worldRowCount(group) === 0;
}

type GroupCheck = (group: CriteriaGroup) => Issue[];

const tooManyBiomes =
  (choice: BiomeChoice, label: string): GroupCheck =>
  (group) =>
    biomesWith(group, choice).length > MAX_BIOME_CHOICES
      ? [{ severity: "error", message: `more than ${MAX_BIOME_CHOICES} biomes are "${label}", but a world only has ${MAX_BIOME_CHOICES}.` }]
      : [];

const ruleIssues =
  (check: (rule: PieceRule, name: string) => Issue | undefined): GroupCheck =>
  (group) =>
    group.rules.flatMap((rule) => check(rule, SET_PIECE_BY_ID[rule.pieceId]?.name ?? rule.pieceId) ?? []);

const GROUP_CHECKS: GroupCheck[] = [
  tooManyBiomes("include", "Must have"),
  tooManyBiomes("exclude", "Must not have"),
  ruleIssues((rule, name) => {
    const unscoped = ruleScope(rule).length === 0;
    if (unscoped && SET_PIECE_BY_ID[rule.pieceId]?.kind === "fixed")
      return { severity: "warning", message: `every world has the same number of ${name}. Pick the biomes you want it in.` };
    return rule.scopeMode === "only" && unscoped
      ? { severity: "warning", message: `${name} has no biomes picked, so it counts everywhere.` }
      : undefined;
  }),
  ruleIssues((rule, name) =>
    SET_PIECE_BY_ID[rule.pieceId]?.alwaysPlaced && rule.mode === "none" && ruleScope(rule).length === 0
      ? { severity: "error", message: `${name} is in every world, so "None" can never match.` }
      : undefined,
  ),
  (group) => {
    const leastPerPiece = new Map<string, number>();
    for (const rule of group.rules) {
      if (rule.mode !== "none") leastPerPiece.set(rule.pieceId, Math.max(leastPerPiece.get(rule.pieceId) ?? 0, effectiveRule(rule).min));
    }
    return Object.entries(KIND_TOTALS).flatMap(([kind, { most, noun }]): Issue[] => {
      const needed = [...leastPerPiece].reduce((sum, [pieceId, least]) => sum + (SET_PIECE_BY_ID[pieceId]?.kind === kind ? least : 0), 0);
      return needed > most ? [{ severity: "error", message: `the set pieces ask for at least ${needed} ${noun} in total, but a world has at most ${most}.` }] : [];
    });
  },
  (group) =>
    !group.passive && worldRowCount(group) > 0 && levelTableChoices(group) === 0
      ? [{ severity: "warning", message: "only world details are picked, so every seed's world gets generated. Add a biome, resource or set piece to speed it up." }]
      : [],
  worldIssues,
];

/** Problems the user should see before searching; errors mean the search can never match. */
export function validateSearch(state: SearchState): Issue[] {
  const multiple = state.groups.length > 1;
  const capitalize = (text: string) => text.charAt(0).toUpperCase() + text.slice(1);
  const perGroup = state.groups.flatMap((group, index) => {
    const label = (message: string) => (multiple ? `Option ${index + 1}: ${message}` : capitalize(message));
    const emptyWarning: Issue[] =
      multiple && isEmptyGroup(group) ? [{ severity: "warning", message: "nothing picked, so it's ignored." }] : [];
    const issues = [...emptyWarning, ...GROUP_CHECKS.flatMap((check) => check(group))];
    return issues.map((issue) => ({ ...issue, message: label(issue.message) }));
  });
  const picked = state.groups.filter((group) => !isEmptyGroup(group));
  const nothing: Issue[] = picked.length === 0 ? [{ severity: "warning", message: "Nothing picked yet, so every world matches." }] : [];
  const allPassive: Issue[] =
    picked.length > 0 && picked.every((group) => group.passive)
      ? [{ severity: "error", message: "Every option is passive. At least one option has to pick the seeds the passive ones are checked on." }]
      : [];
  const issues = [...nothing, ...allPassive, ...perGroup];
  if (issues.some((issue) => issue.severity === "error")) return issues;
  const checked = validateConfig(toSeedfinderConfig(state));
  return checked.ok ? issues : [...issues, { severity: "error", message: `This search can't be sent: ${checked.error}` }];
}

/** Encodes a config as base64url for the `?c=` share parameter. */
export function encodeShareParam(config: SeedfinderConfig): string {
  const bytes = new TextEncoder().encode(JSON.stringify(config));
  const binary = Array.from(bytes, (byte) => String.fromCharCode(byte)).join("");
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Decodes a `?c=` share parameter into the (possibly old) config it holds, or null when it is malformed. */
export function decodeShareParam(param: string): unknown {
  try {
    const binary = atob(param.replace(/-/g, "+").replace(/_/g, "/"));
    const json = new TextDecoder().decode(Uint8Array.from(binary, (char) => char.charCodeAt(0)));
    return JSON.parse(json) as unknown;
  } catch {
    return null;
  }
}

function presetState(...groups: Partial<CriteriaGroup>[]): SearchState {
  return { platform: DEFAULT_PLATFORM, groups: groups.map((group) => ({ ...emptyGroup(), ...group })) };
}

export const PRESETS: Preset[] = [
  {
    id: "twiggy-juicy",
    name: "Twiggy trees + juicy berries",
    description: "Both swapped resources in the same world.",
    build: () => presetState({ swaps: { twigs: "twiggy trees", berries: "juicy berries" } }),
  },
  {
    id: "no-killer-bees",
    name: "No killer bees",
    description: "Skips all worlds with killer bees.",
    build: () => presetState({ biomes: { "Killer bees!": "exclude" } }),
  },
];
