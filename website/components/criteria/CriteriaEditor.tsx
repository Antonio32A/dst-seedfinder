"use client";

import { Fragment } from "react";
import SetPieceSection from "@/components/criteria/set-pieces/SetPieceSection";
import { levelCatalogOf } from "@/lib/catalog/level-catalog";
import { MAX_FILTERS } from "@/lib/config/seedfinder-config";
import {
    emptyFilter,
    type GenerationPicks,
    type SearchState,
    type WorldFilter
} from "@/lib/criteria/search-state";
import { replaceByKey, withoutKey } from "@/lib/criteria/state-helpers";
import BiomeSection from "./BiomeSection";
import PrefilterOdds from "./PrefilterOdds";
import ResourceSection from "./ResourceSection";
import WorldFilterCard from "./WorldFilterCard";

interface CriteriaEditorProps {
    state: SearchState;
    onChange: (update: (state: SearchState) => SearchState) => void;
}

export default function CriteriaEditor({ state, onChange }: CriteriaEditorProps) {
    const setGeneration = (change: Partial<GenerationPicks>) =>
            onChange((current) => ({ ...current, generation: { ...current.generation, ...change } }));
    const setFilters = (update: (filters: WorldFilter[]) => WorldFilter[]) =>
            onChange((current) => ({ ...current, filters: update(current.filters) }));
    const catalog = levelCatalogOf(state.shard);
    const { generation, filters } = state;

    return (
            <>
                <section className="section" aria-labelledby="world-generation">
                    <h2 id="world-generation" className="section-title">
                        World Generation
                    </h2>
                    <p className="muted small">
                        These filters are computed extremely fast (millions of seeds per second), so these should be
                        configured first to speed up your search.
                    </p>
                    <PrefilterOdds/>
                    <div className="framed group">
                        <BiomeSection catalog={catalog} biomes={generation.biomes}
                                      onChange={(biomes) => setGeneration({ biomes })}/>
                        <ResourceSection catalog={catalog} swaps={generation.swaps}
                                         onChange={(swaps) => setGeneration({ swaps })}/>
                        <SetPieceSection catalog={catalog} rules={generation.rules} pieceGroups={generation.pieceGroups}
                                         onChange={setGeneration}/>
                    </div>
                </section>
                <section className="section" aria-labelledby="world-filters">
                    <h2 id="world-filters" className="section-title">
                        World Filters <span className="tag tag--accent">slow</span>
                    </h2>
                    <p className="muted small">
                        Checked on each generated world, so pick some world generation above to generate fewer
                        worlds.
                        {filters.length > 1 && " A world matches if it fits any option. Everything in an option must be true."}
                    </p>
                    {filters.map((filter, index) => (
                            <Fragment key={filter.key}>
                                {index > 0 && (
                                        <div className="or-divider" role="separator">
                                            or
                                        </div>
                                )}
                                <WorldFilterCard
                                        filter={filter}
                                        shard={state.shard}
                                        index={index}
                                        total={filters.length}
                                        onChange={(changed) => setFilters((current) => replaceByKey(current, changed))}
                                        onRemove={() => setFilters((current) => withoutKey(current, filter.key))}
                                />
                            </Fragment>
                    ))}
                    <p className="add-alternative">
                        <button
                                type="button"
                                className="link-button"
                                disabled={filters.length >= MAX_FILTERS}
                                onClick={() => setFilters((current) => [...current, emptyFilter()])}
                        >
                            Or also accept...
                        </button>
                        {" "}
                        <span className="hint">Add another set of world filters. A world can match either.</span>
                    </p>
                </section>
            </>
    );
}
