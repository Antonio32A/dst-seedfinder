"use client";

import SegmentedControl from "@/components/ui/SegmentedControl";
import { SHARD_LABELS, type Shard, SHARDS } from "@/lib/config/seedfinder-config";

const HINT = "The world type you wish to generate. Forest is the main world, and caves are well... caves!";

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
                <p className="hint">{HINT}</p>
            </section>
    );
}
