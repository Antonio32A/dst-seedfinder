import { SWAPS } from "./catalog";
import { MAX_PREFAB_IDS } from "./seedfinder-config";
import { NAMED_ANCHORS, PREFAB_BY_ID, PREFAB_GROUPS, PREFABS, SAMPLE_WORLDS, type WorldPrefab } from "./world-catalog";

export interface PrefabFamily {
    label: string;
    ids: string[];
}

export type PickerEntry = { prefab: WorldPrefab; family?: undefined } | {
    family: PrefabFamily;
    members: WorldPrefab[]
};

export interface PickerGroup {
    id: string;
    name: string;
    ids: string[];
    pickable: boolean;
    entries: PickerEntry[];
}

export interface SetChip {
    label: string;
    ids: string[];
}

const ANCHOR_LABELS: ReadonlyMap<string, string> = new Map(NAMED_ANCHORS.map((anchor) => [anchor.id, anchor.label]));

const SWAP_OPTION_NAMES: ReadonlyMap<string, string> = new Map(
    SWAPS.flatMap((swap) => swap.options.map((option) => [option.id, option.name] as const))
);

const baseName = (name: string) => name.replace(/\s*\(.*\)$/, "");

/** The friendly name of a prefab id: its named-anchor label, else its catalog name. */
export function prefabName(id: string): string {
    return ANCHOR_LABELS.get(id) ?? PREFAB_BY_ID.get(id)?.name ?? id;
}

function familyLabel(members: WorldPrefab[]): string | undefined {
    const tally = members.reduce((counts, member) => {
        const base = baseName(member.name);
        return counts.set(base, (counts.get(base) ?? 0) + 1);
    }, new Map<string, number>());
    const [base, count] = [...tally].sort((a, b) => b[1] - a[1])[0];
    return count >= 2 ? `${base} (any kind)` : undefined;
}

function groupEntries(prefabs: WorldPrefab[]): PickerEntry[] {
    const families = prefabs.reduce((byKey, prefab) => {
        const key = prefab.variantOf ?? `id:${prefab.id}`;
        return byKey.set(key, [...(byKey.get(key) ?? []), prefab]);
    }, new Map<string, WorldPrefab[]>());
    return [...families.values()].flatMap((members): PickerEntry[] => {
        const label = members.length > 1 ? familyLabel(members) : undefined;
        return label ? [{
            family: { label, ids: members.map((member) => member.id) },
            members
        }] : members.map((prefab) => ({ prefab }));
    });
}

/** Every prefab by catalog group, with variants of one kind collapsed into a family ("Boulder (any kind)"). */
export const PICKER_GROUPS: PickerGroup[] = PREFAB_GROUPS.map((group) => ({
    id: group.id,
    name: group.name,
    ids: group.prefabs,
    pickable: group.prefabs.length <= MAX_PREFAB_IDS,
    entries: groupEntries(PREFABS.filter((prefab) => prefab.group === group.id))
}));

const FAMILIES: PrefabFamily[] = PICKER_GROUPS.flatMap((group) => group.entries.flatMap((entry) => (entry.family ? [entry.family] : [])));

const WHOLE_GROUPS: PrefabFamily[] = PICKER_GROUPS.filter((group) => group.pickable && group.ids.length > 1).map((group) => ({
    label: `${group.name} (all ${group.ids.length})`,
    ids: group.ids
}));

/** A prefab set as removable chips, collapsing complete groups and families into one chip each. */
export function setChips(ids: string[]): SetChip[] {
    const chosen = new Set(ids);
    const collapsed = [...WHOLE_GROUPS, ...FAMILIES].reduce<SetChip[]>((chips, family) => {
        const free = family.ids.every((id) => chosen.has(id));
        if (free) family.ids.forEach((id) => chosen.delete(id));
        return free ? [...chips, family] : chips;
    }, []);
    return [...collapsed, ...ids.filter((id) => chosen.has(id)).map((id) => ({ label: prefabName(id), ids: [id] }))];
}

/** A prefab set as short text for messages, e.g. "Pig King" or "Beefalo, Rook". */
export function setLabel(ids: string[]): string {
    return ids.length === 0 ? "nothing" : setChips(ids).map((chip) => chip.label).join(", ");
}

/** The summed [min, median, max] of a set's per-world counts over the sample worlds (never-seen prefabs count 0). */
export function sampleCounts(ids: string[]): [number, number, number] {
    return ids.reduce<[number, number, number]>(
        (sum, id) => {
            const [min, median, max] = PREFAB_BY_ID.get(id)?.counts ?? [0, 0, 0];
            return [sum[0] + min, sum[1] + median, sum[2] + max];
        },
        [0, 0, 0]
    );
}

/** A plain-words hint of how many a world usually has, e.g. "sample worlds have 3-67 (typically 20)". */
export function countHint(ids: string[]): string {
    const [min, median, max] = sampleCounts(ids);
    if (max === 0) return `not seen in ${SAMPLE_WORLDS} sample worlds`;
    return min === max ? `every sample world has ${min}` : `sample worlds have ${min}-${max} (typically ${median})`;
}

/** Whether every sampled world has the same number of the set, so a plain count rule can't tell worlds apart. */
export function fixedCount(ids: string[]): number | undefined {
    const [min, , max] = sampleCounts(ids);
    const always = ids.every((id) => PREFAB_BY_ID.get(id)?.always);
    return always && min === max ? min : undefined;
}

/** The highest count worth typing for a set: its number of ids when each is unique, else well above the sampled maximum. */
export function countCap(ids: string[]): number {
    if (ids.every((id) => PREFAB_BY_ID.get(id)?.unique)) return Math.max(ids.length, 1);
    return Math.max(100, 2 * sampleCounts(ids)[2]);
}

/** Short tags describing a prefab: how often it appears and what it depends on. */
export function prefabTags(prefab: WorldPrefab): string[] {
    const swap = prefab.swapOption && SWAP_OPTION_NAMES.get(prefab.swapOption);
    const presence = prefab.always && prefab.unique ? "1 per world" : prefab.always ? "in every world" : prefab.unique ? "at most 1" : undefined;
    return [prefab.unreachable ? "not in default worlds" : presence, swap && `only with ${swap}`].filter((tag): tag is string => Boolean(tag));
}

/** How many of a prefab the sample worlds had, as short text; empty for fixed singletons. */
export function prefabCountText(prefab: WorldPrefab): string {
    const [min, median, max] = prefab.counts ?? [0, 0, 0];
    if (max <= 1) return "";
    return min === max ? `always ${min}` : `${min}-${max}, typically ${median}`;
}
