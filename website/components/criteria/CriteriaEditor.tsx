"use client";

import { Fragment } from "react";
import { levelCatalogOf } from "@/lib/catalog/level-catalog";
import { MAX_CRITERIA } from "@/lib/config/seedfinder-config";
import { type CriteriaGroup, emptyGroup, type SearchState } from "@/lib/criteria/search-state";
import { replaceByKey, withoutKey } from "@/lib/criteria/state-helpers";
import CriteriaGroupCard from "./CriteriaGroupCard";
import PrefilterOdds from "./PrefilterOdds";

interface CriteriaEditorProps {
    state: SearchState;
    onChange: (update: (state: SearchState) => SearchState) => void;
}

export default function CriteriaEditor({ state, onChange }: CriteriaEditorProps) {
    const setGroups = (update: (groups: CriteriaGroup[]) => CriteriaGroup[]) =>
            onChange((current) => ({ ...current, groups: update(current.groups) }));
    const catalog = levelCatalogOf(state.shard);
    const multiple = state.groups.length > 1;
    const onlyActive = state.groups.filter((group) => !group.passive).length === 1;

    return (
            <section className="section" aria-labelledby="criteria">
                <h2 id="criteria" className="section-title">
                    What you&apos;re looking for
                </h2>
                <p className="muted small">
                    {multiple
                            ? "A world matches if it fits any option. Everything in an option must be true."
                            : "A world must match everything you pick here."}
                </p>
                <PrefilterOdds/>
                {state.groups.map((group, index) => (
                        <Fragment key={group.key}>
                            {index > 0 && (
                                    <div className="or-divider" role="separator">
                                        or
                                    </div>
                            )}
                            <CriteriaGroupCard
                                    group={group}
                                    catalog={catalog}
                                    index={index}
                                    total={state.groups.length}
                                    onlyActive={onlyActive}
                                    onChange={(changed) => setGroups((groups) => replaceByKey(groups, changed))}
                                    onRemove={() =>
                                            setGroups((groups) => {
                                                const kept = withoutKey(groups, group.key);
                                                return kept.some((item) => !item.passive) ? kept : kept.map((item, at) => (at === 0 ? {
                                                    ...item,
                                                    passive: false
                                                } : item));
                                            })
                                    }
                            />
                        </Fragment>
                ))}
                <p className="add-alternative">
                    <button
                            type="button"
                            className="link-button"
                            disabled={state.groups.length >= MAX_CRITERIA}
                            onClick={() => setGroups((groups) => [...groups, emptyGroup(groups.length > 0)])}
                    >
                        Or also accept...
                    </button>
                    {" "}
                    <span className="hint">Add another set of requirements. A world can match either.</span>
                </p>
            </section>
    );
}
