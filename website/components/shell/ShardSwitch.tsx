"use client";

import SegmentedControl from "@/components/ui/SegmentedControl";
import { SHARD_LABELS, type Shard, SHARDS } from "@/lib/config/seedfinder-config";

const HINTS: Record<Shard, string> = {
    forest: "Search the overworld's seeds.",
    caves: "Search the caves' seeds. Each shard has its own seed, so this looks at cave seeds. Switching keeps what also exists in the other shard, with the spawn becoming the stairs you arrive on."
};

interface ShardSwitchProps {
    shard: Shard;
    onChange: (shard: Shard) => void;
}

export default function ShardSwitch({ shard, onChange }: ShardSwitchProps) {
    return (
            <section className="section" aria-labelledby="shard">
                <h2 id="shard" className="section-title">
                    World
                </h2>
                <SegmentedControl
                        legend="Shard"
                        hideLegend
                        options={SHARDS.map((value) => ({ value, label: SHARD_LABELS[value] }))}
                        value={shard}
                        onChange={onChange}
                />
                <p className="hint">{HINTS[shard]}</p>
            </section>
    );
}
