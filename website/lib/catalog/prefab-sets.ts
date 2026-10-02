import { MAX_PREFAB_IDS, type Shard } from "@/lib/config/seedfinder-config";
import { SWAPS } from "./level";
import { shardCatalog } from "./shard-catalog";
import type { WorldPrefab } from "./world";

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

const SWAP_OPTION_NAMES: ReadonlyMap<string, string> = new Map(
    SWAPS.flatMap((swap) => swap.options.map((option) => [option.id, option.name] as const))
);

const ANCHOR_LABELS: Record<Shard, ReadonlyMap<string, string>> = {
    forest: new Map(shardCatalog("forest").anchors.map((anchor) => [anchor.id, anchor.label])),
    caves: new Map(shardCatalog("caves").anchors.map((anchor) => [anchor.id, anchor.label]))
};

export function prefabName(id: string, shard: Shard = "forest"): string {
    return ANCHOR_LABELS[shard].get(id) ?? shardCatalog(shard).byId.get(id)?.name ?? id;
}

function familyLabel(members: WorldPrefab[]): string | undefined {
    const tally = members.reduce((counts, member) => {
        const base = member.name.replace(/\s*\(.*\)$/, "");
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

interface ShardSets {
    pickerGroups: PickerGroup[];
    collapsible: PrefabFamily[];
}

const pickerGroupsOf = (shard: Shard): PickerGroup[] => {
    const { groups, prefabs } = shardCatalog(shard);
    return groups.map((group) => ({
        id: group.id,
        name: group.name,
        ids: group.prefabs,
        pickable: group.prefabs.length <= MAX_PREFAB_IDS,
        entries: groupEntries(prefabs.filter((prefab) => prefab.group === group.id))
    }));
};

function setsOf(shard: Shard): ShardSets {
    const pickerGroups = pickerGroupsOf(shard);
    const families = pickerGroups.flatMap((group) => group.entries.flatMap((entry) => (entry.family ? [entry.family] : [])));
    const wholeGroups = pickerGroups.filter((group) => group.pickable && group.ids.length > 1).map((group) => ({
        label: `${group.name} (all ${group.ids.length})`,
        ids: group.ids
    }));
    return { pickerGroups, collapsible: [...wholeGroups, ...families] };
}

const SETS: Record<Shard, ShardSets> = { forest: setsOf("forest"), caves: setsOf("caves") };

/** The prefab picker's groups of a shard's prefabs. */
export const pickerGroups = (shard: Shard = "forest"): PickerGroup[] => SETS[shard].pickerGroups;

export function setChips(ids: string[], shard: Shard = "forest"): SetChip[] {
    const chosen = new Set(ids);
    const collapsed = SETS[shard].collapsible.reduce<SetChip[]>((chips, family) => {
        const free = family.ids.every((id) => chosen.has(id));
        if (free) family.ids.forEach((id) => chosen.delete(id));
        return free ? [...chips, family] : chips;
    }, []);
    return [...collapsed, ...ids.filter((id) => chosen.has(id)).map((id) => ({ label: prefabName(id, shard), ids: [id] }))];
}

export function setLabel(ids: string[], shard: Shard = "forest"): string {
    return ids.length === 0 ? "nothing" : setChips(ids, shard).map((chip) => chip.label).join(", ");
}

const prefabOf = (id: string, shard: Shard) => shardCatalog(shard).byId.get(id);

export function sampleCounts(ids: string[], shard: Shard = "forest"): [number, number, number] {
    return ids.reduce<[number, number, number]>(
        (sum, id) => {
            const [min, median, max] = prefabOf(id, shard)?.counts ?? [0, 0, 0];
            return [sum[0] + min, sum[1] + median, sum[2] + max];
        },
        [0, 0, 0]
    );
}

export function countHint(ids: string[], shard: Shard = "forest"): string {
    const [min, median, max] = sampleCounts(ids, shard);
    const sampled = shardCatalog(shard).sampleWorlds;
    if (max === 0) return `not seen in ${sampled} sample worlds`;
    return min === max ? `every sample world has ${min}` : `sample worlds have ${min}-${max} (typically ${median})`;
}

export function fixedCount(ids: string[], shard: Shard = "forest"): number | undefined {
    const [min, , max] = sampleCounts(ids, shard);
    const always = ids.every((id) => prefabOf(id, shard)?.always);
    return always && min === max ? min : undefined;
}

export function countCap(ids: string[], shard: Shard = "forest"): number {
    if (ids.every((id) => prefabOf(id, shard)?.unique)) return Math.max(ids.length, 1);
    return Math.max(100, 2 * sampleCounts(ids, shard)[2]);
}

export function prefabTags(prefab: WorldPrefab): string[] {
    const swap = prefab.swapOption && SWAP_OPTION_NAMES.get(prefab.swapOption);
    const presence = prefab.always && prefab.unique ? "1 per world" : prefab.always ? "in every world" : prefab.unique ? "at most 1" : undefined;
    return [prefab.unreachable ? "not in default worlds" : presence, swap && `only with ${swap}`].filter((tag): tag is string => Boolean(tag));
}

export function prefabCountText(prefab: WorldPrefab): string {
    const [min, median, max] = prefab.counts ?? [0, 0, 0];
    if (max <= 1) return "";
    return min === max ? `always ${min}` : `${min}-${max}, typically ${median}`;
}
