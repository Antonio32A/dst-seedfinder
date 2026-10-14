"use client";

import BuildField from "@/components/search/BuildField";
import SegmentedControl from "@/components/ui/SegmentedControl";
import type { GameBuild } from "@/lib/config/game-builds";
import { type Shard, SHARD_LABELS, SHARDS } from "@/lib/config/seedfinder-config";

const HINT = "The world type you wish to generate and the game build that generates it. Forest is the main world, and caves are well... caves!";

interface WorldSwitchProps {
    shard: Shard;
    onShardChange: (shard: Shard) => void;
    build: GameBuild;
    onBuildChange: (build: GameBuild) => void;
}

export default function WorldSwitch({ shard, onShardChange, build, onBuildChange }: WorldSwitchProps) {
    return (
            <section className="section" aria-labelledby="shard">
                <h2 id="shard" className="section-title">
                    World
                </h2>
                <div className="world-switch">
                    <SegmentedControl
                            legend="Shard"
                            options={SHARDS.map((value) => ({ value, label: SHARD_LABELS[value] }))}
                            value={shard}
                            onChange={onShardChange}
                    />
                    <BuildField build={build} onChange={onBuildChange}/>
                </div>
                <p className="hint">{HINT}</p>
            </section>
    );
}
