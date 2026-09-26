"use client";

import SegmentedControl from "@/components/ui/SegmentedControl";
import { SWAPS } from "@/lib/catalog/level";
import type { CriteriaGroup } from "@/lib/criteria/search-state";
import { withEntry } from "@/lib/criteria/state-helpers";

const ANY = "";

interface ResourceSectionProps {
    swaps: CriteriaGroup["swaps"];
    onChange: (swaps: CriteriaGroup["swaps"]) => void;
}

export default function ResourceSection({ swaps, onChange }: ResourceSectionProps) {
    return (
            <div className="subsection">
                <h4 className="subsection__title">Resource variety</h4>
                <p className="muted small">Each world gets one version of each of these resources.</p>
                <div className="swaps">
                    {SWAPS.map((swap) => (
                            <div key={swap.id}>
                                <SegmentedControl
                                        legend={swap.name}
                                        options={[{
                                            value: ANY,
                                            label: "Don't care"
                                        }, ...swap.options.map((option) => ({
                                            value: option.id,
                                            label: option.name,
                                            title: option.description
                                        }))]}
                                        value={swaps[swap.id] ?? ANY}
                                        onChange={(value) => onChange(withEntry(swaps, swap.id, value === ANY ? undefined : value))}
                                />
                                {swap.description && <p className="hint">{swap.description}</p>}
                            </div>
                    ))}
                </div>
            </div>
    );
}
