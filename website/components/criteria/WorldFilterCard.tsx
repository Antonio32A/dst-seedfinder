"use client";

import { useState } from "react";
import WorldSection from "@/components/criteria/world/WorldSection";
import { MAX_FILTER_NAME_LENGTH, optionName, type Shard } from "@/lib/config/seedfinder-config";
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
    const [renaming, setRenaming] = useState(false);
    const name = optionName(filter, index);

    return (
            <section className="framed group" aria-label={name}>
                {(total > 1 || filter.name.trim() !== "") && (
                        <div className="group__header">
                            {renaming ? (
                                    <input
                                            className="group__rename"
                                            aria-label={`Name of option ${index + 1}`}
                                            autoFocus
                                            defaultValue={filter.name}
                                            placeholder={`Option ${index + 1}`}
                                            maxLength={MAX_FILTER_NAME_LENGTH}
                                            onBlur={(event) => {
                                                onChange({ ...filter, name: event.currentTarget.value.trim() });
                                                setRenaming(false);
                                            }}
                                            onKeyDown={(event) => {
                                                if (event.key === "Escape") event.currentTarget.value = filter.name;
                                                if (event.key === "Enter" || event.key === "Escape") event.currentTarget.blur();
                                            }}
                                    />
                            ) : (
                                    <div className="group__name">
                                        <h3 className="group__title">{name}</h3>
                                        <button type="button" className="link-button" aria-label={`Rename ${name}`}
                                                onClick={() => setRenaming(true)}>
                                            rename
                                        </button>
                                    </div>
                            )}
                            {total > 1 && (
                                    <button type="button" className="link-button link-button--danger" aria-label={`Remove ${name}`}
                                            onClick={onRemove}>
                                        remove
                                    </button>
                            )}
                        </div>
                )}
                <WorldSection shard={shard} rows={filter} onChange={(rows) => onChange({ ...filter, ...rows })}/>
            </section>
    );
}
