"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import Toggle from "@/components/ui/Toggle";
import {
    type PickerEntry,
    pickerGroups,
    prefabCountText,
    type PrefabFamily,
    prefabName,
    prefabTags
} from "@/lib/catalog/prefab-sets";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import type { WorldPrefab } from "@/lib/catalog/world";
import { MAX_PREFAB_IDS, type Shard } from "@/lib/config/seedfinder-config";
import type { WorldKind } from "@/lib/criteria/world-rules";
import { useWorldKind } from "./WorldKind";

export type Blocked = (id: string) => string | undefined;

interface PrefabPickerProps {
    title: string;
    selected: string[];
    blocked?: Blocked;
    onDone: (ids: string[]) => void;
    onClose: () => void;
}

interface Draft {
    ids: string[];
    full: boolean;
    blocked: Blocked;
    toggle: (ids: string[], on: boolean) => void;
}

const anchorPrefabs = ({ shard, build }: WorldKind): WorldPrefab[] => {
    const { anchors, byId } = shardCatalog(shard, build);
    return anchors.flatMap((anchor) => byId.get(anchor.id) ?? []);
};

const SEARCH_EXAMPLES: Record<Shard, string> = {
    forest: "Search, e.g. beefalo, boulder, pig king",
    caves: "Search, e.g. rabbit, slurper, ancient guardian"
};

const matches = (needle: string, ...texts: string[]) => needle === "" || texts.some((text) => text.toLowerCase().includes(needle));

function Checkbox({ checked, mixed = false, disabled, onChange }: {
    checked: boolean;
    mixed?: boolean;
    disabled: boolean;
    onChange: (on: boolean) => void;
}) {
    return (
            <input
                    type="checkbox"
                    checked={checked}
                    disabled={disabled}
                    ref={(element) => {
                        if (element) element.indeterminate = mixed;
                    }}
                    onChange={(event) => onChange(event.target.checked)}
            />
    );
}

function PrefabOption({ prefab, draft, world }: { prefab: WorldPrefab; draft: Draft; world: WorldKind }) {
    const checked = draft.ids.includes(prefab.id);
    const reason = draft.blocked(prefab.id);
    const counts = prefabCountText(prefab);
    return (
            <li>
                <label className="pick" title={prefab.id}>
                    <Checkbox checked={checked} disabled={!checked && (reason !== undefined || draft.full)}
                              onChange={(on) => draft.toggle([prefab.id], on)}/>
                    <span className="pick__text">
          <span className="pick__name">{prefabName(prefab.id, world.shard, world.build)}</span>
                        {[...(reason ? [reason] : []), ...prefabTags(prefab)].map((tag) => (
                                <span key={tag} className="tag">
              {tag}
            </span>
                        ))}
                        {counts && <span className="pick__counts">{counts}</span>}
        </span>
                </label>
            </li>
    );
}

function FamilyOption({ family, members, draft, open, world }: {
    family: PrefabFamily;
    members: WorldPrefab[];
    draft: Draft;
    open: boolean;
    world: WorldKind;
}) {
    const [expanded, setExpanded] = useState<boolean>();
    const free = members.filter((member) => !draft.blocked(member.id)).map((member) => member.id);
    const picked = free.filter((id) => draft.ids.includes(id));
    const all = free.length > 0 && picked.length === free.length;
    const room = draft.ids.length - picked.length + free.length <= MAX_PREFAB_IDS;
    const shown = expanded ?? (open || picked.length > 0);
    return (
            <li>
                <div className="pick pick--family">
                    <label className="pick__main">
                        <Checkbox checked={all} mixed={!all && picked.length > 0}
                                  disabled={!all && (free.length === 0 || !room)}
                                  onChange={(on) => draft.toggle(free, on)}/>
                        <span className="pick__name">{family.label}</span>
                    </label>
                    <button type="button" className="link-button small" aria-expanded={shown}
                            onClick={() => setExpanded(!shown)}>
                        {shown ? "hide kinds" : `${members.length} kinds`}
                    </button>
                </div>
                {shown && (
                        <ul className="picker__items picker__items--nested">
                            {members.map((member) => (
                                    <PrefabOption key={member.id} prefab={member} draft={draft} world={world}/>
                            ))}
                        </ul>
                )}
            </li>
    );
}

function GroupToggle({ ids, draft }: { ids: string[]; draft: Draft }) {
    const free = ids.filter((id) => !draft.blocked(id));
    const all = free.length > 0 && free.every((id) => draft.ids.includes(id));
    const room = new Set([...draft.ids, ...free]).size <= MAX_PREFAB_IDS;
    return (
            <button type="button" className="link-button small" disabled={!all && (free.length === 0 || !room)}
                    onClick={() => draft.toggle(free, !all)}>
                {all ? "remove all" : "add all"}
            </button>
    );
}

function visibleEntries(
        entries: PickerEntry[],
        needle: string,
        groupName: string,
        listed: (prefab: WorldPrefab) => boolean,
        world: WorldKind
): PickerEntry[] {
    return entries.flatMap((entry) => {
        const members = entry.family ? entry.members : [entry.prefab];
        const label = entry.family ? entry.family.label : prefabName(entry.prefab.id, world.shard, world.build);
        const reachable = members.filter(listed);
        const names = members.flatMap((member) => [member.name, member.id]);
        if (reachable.length === 0 || !matches(needle, groupName, label, ...names)) return [];
        if (!entry.family || reachable.length === entry.members.length) return [entry];
        return reachable.length > 1 ? [{ ...entry, members: reachable }] : [{ prefab: reachable[0] }];
    });
}

function EntryList({ entries, draft, open, world }: {
    entries: PickerEntry[];
    draft: Draft;
    open: boolean;
    world: WorldKind;
}) {
    return (
            <ul className="picker__items">
                {entries.map((entry) =>
                        entry.family ? (
                                <FamilyOption key={entry.family.label} family={entry.family} members={entry.members}
                                              draft={draft} open={open} world={world}/>
                        ) : (
                                <PrefabOption key={entry.prefab.id} prefab={entry.prefab} draft={draft} world={world}/>
                        )
                )}
            </ul>
    );
}

export default function PrefabPicker({
                                         title,
                                         selected,
                                         blocked = () => undefined,
                                         onDone,
                                         onClose
                                     }: PrefabPickerProps) {
    const world = useWorldKind();
    const { byId } = shardCatalog(world.shard, world.build);
    const dialog = useRef<HTMLDialogElement>(null);
    const search = useRef<HTMLInputElement>(null);
    const titleId = useId();
    const [query, setQuery] = useState("");
    const [showAll, setShowAll] = useState(false);
    const [ids, setIds] = useState(selected);

    useEffect(() => {
        if (!dialog.current?.open) dialog.current?.showModal();
        search.current?.focus();
    }, []);

    const needle = query.trim().toLowerCase();
    const groups = useMemo(() => {
        const listed = (prefab: WorldPrefab) => showAll || !prefab.unreachable || selected.includes(prefab.id);
        return pickerGroups(world.shard, world.build).map((group) => ({
            group,
            entries: visibleEntries(group.entries, needle, group.name, listed, world),
            addable: group.pickable ? group.ids.filter((id) => showAll || !byId.get(id)?.unreachable) : []
        })).filter(({ entries }) => entries.length > 0);
    }, [needle, showAll, selected, world, byId]);
    const anchors = anchorPrefabs(world)
            .filter((prefab) =>
                    matches(needle, prefabName(prefab.id, world.shard, world.build), prefab.name, prefab.id));

    const draft: Draft = {
        ids,
        full: ids.length >= MAX_PREFAB_IDS,
        blocked,
        toggle: (changed, on) =>
                setIds((current) => (on
                        ? [...new Set([...current, ...changed])].slice(0, MAX_PREFAB_IDS)
                        : current.filter((id) => !changed.includes(id))))
    };

    return (
            <dialog ref={dialog} className="modal picker" aria-labelledby={titleId} onClose={onClose}>
                <div className="picker__top">
                    <div className="picker__heading">
                        <h3 id={titleId}>{title}</h3>
                        <button type="button" className="link-button" onClick={onClose}>
                            cancel
                        </button>
                    </div>
                    <input type="search" aria-label="Search things in the world"
                           placeholder={SEARCH_EXAMPLES[world.shard]} value={query}
                           onChange={(event) => setQuery(event.target.value)} ref={search}/>
                    <div className="picker__bar">
          <span className="counter" aria-live="polite">
            <strong>{ids.length}</strong>/{MAX_PREFAB_IDS} picked
          </span>
                        <Toggle checked={showAll} onChange={setShowAll}>
                            show things not in default worlds
                        </Toggle>
                        <button type="button" disabled={ids.length + selected.length === 0} onClick={() => onDone(ids)}>
                            Done
                        </button>
                    </div>
                </div>
                <div className="picker__body">
                    {groups.length === 0 && anchors.length === 0 &&
                            <p className="muted">Nothing matches &quot;{query}&quot;.</p>}
                    {anchors.length > 0 && (
                            <section className="picker__kind">
                                <h4>Common places</h4>
                                <ul className="picker__items">
                                    {anchors.map((prefab) => (
                                            <PrefabOption key={prefab.id} prefab={prefab} draft={draft} world={world}/>
                                    ))}
                                </ul>
                            </section>
                    )}
                    {groups.map(({ group, entries, addable }) => (
                            <section key={group.id} className="picker__kind">
                                <div className="picker__kind-head">
                                    <h4>{group.name}</h4>
                                    {addable.length > 1 && <GroupToggle ids={addable} draft={draft}/>}
                                </div>
                                <EntryList entries={entries} draft={draft} open={needle !== ""} world={world}/>
                            </section>
                    ))}
                </div>
            </dialog>
    );
}
