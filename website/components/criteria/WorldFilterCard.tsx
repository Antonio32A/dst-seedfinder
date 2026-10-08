"use client";

import WorldSection from "@/components/criteria/world/WorldSection";
import type { Shard } from "@/lib/config/seedfinder-config";
import type { WorldFilter } from "@/lib/criteria/search-state";

interface WorldFilterCardProps {
    filter: WorldFilter;
    shard: Shard;
    index: number;
    total: number;
    onChange: (filter: WorldFilter) => void;
    onRemove: () => void;
}

export default function WorldFilterCard({ filter, shard, index, total, onChange, onRemove }: WorldFilterCardProps) {
    return (
            <section className="framed group" aria-label={`Option ${index + 1}`}>
                {total > 1 && (
                        <div className="group__header">
                            <h3 className="group__title">Option {index + 1}</h3>
                            <button type="button" className="link-button link-button--danger" onClick={onRemove}>
                                remove option {index + 1}
                            </button>
                        </div>
                )}
                <WorldSection shard={shard} rows={filter} onChange={(rows) => onChange({ ...filter, ...rows })}/>
            </section>
    );
}
