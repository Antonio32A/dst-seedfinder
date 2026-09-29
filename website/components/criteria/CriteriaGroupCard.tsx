"use client";

import { useId } from "react";
import SetPieceSection from "@/components/criteria/set-pieces/SetPieceSection";
import WorldSection from "@/components/criteria/world/WorldSection";
import Toggle from "@/components/ui/Toggle";
import type { LevelCatalog } from "@/lib/catalog/level-catalog";
import type { CriteriaGroup } from "@/lib/criteria/search-state";
import BiomeSection from "./BiomeSection";
import ResourceSection from "./ResourceSection";

interface CriteriaGroupCardProps {
    group: CriteriaGroup;
    catalog: LevelCatalog;
    index: number;
    total: number;
    onlyActive: boolean;
    onChange: (group: CriteriaGroup) => void;
    onRemove: () => void;
}

export default function CriteriaGroupCard({
                                              group,
                                              catalog,
                                              index,
                                              total,
                                              onlyActive,
                                              onChange,
                                              onRemove
                                          }: CriteriaGroupCardProps) {
    const titleId = useId();
    const locked = !group.passive && onlyActive;
    return (
            <section className="framed group" aria-labelledby={titleId}>
                <div className="group__header">
                    <h3 id={titleId} className="group__title">
                        {total > 1 ? `Option ${index + 1}` : "The world must have..."}
                    </h3>
                    {total > 1 && (
                            <button type="button" className="link-button link-button--danger" onClick={onRemove}>
                                remove option {index + 1}
                            </button>
                    )}
                </div>
                {(total > 1 || group.passive) && (
                        <div className="group__passive">
                            <Toggle
                                    checked={group.passive}
                                    disabled={locked}
                                    title={locked ? "At least one option has to pick seeds, so this one can't be passive." : undefined}
                                    onChange={(passive) => onChange({ ...group, passive })}
                            >
                                Passive
                            </Toggle>
                            <p className="hint">
                                {group.passive
                                        ? "Only checked on seeds the other options already look at, so it barely slows the search. When it and a later option both match, this one is reported."
                                        : "Picks seeds to check. Make it passive to only check it on seeds the other options already look at."}
                            </p>
                        </div>
                )}
                <BiomeSection catalog={catalog} biomes={group.biomes} onChange={(biomes) => onChange({ ...group, biomes })}/>
                <ResourceSection catalog={catalog} swaps={group.swaps} onChange={(swaps) => onChange({ ...group, swaps })}/>
                <SetPieceSection catalog={catalog} rules={group.rules} onChange={(rules) => onChange({ ...group, rules })}/>
                {catalog.hasWorlds ? (
                        <WorldSection rows={group} onChange={(rows) => onChange({ ...group, ...rows })}/>
                ) : (
                        <p className="muted small">
                            World details (prefab counts, distances, tiles and routes) aren&apos;t available for the {catalog.shard} yet.
                        </p>
                )}
            </section>
    );
}
