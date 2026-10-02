"use client";

import SegmentedControl from "@/components/ui/SegmentedControl";
import Toggle from "@/components/ui/Toggle";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import type { Metric, Shard } from "@/lib/config/seedfinder-config";
import type { Travel } from "@/lib/criteria/world-rules";
import { useWorldShard } from "./WorldShard";

const METRIC_OPTIONS: { value: Metric; label: string }[] = [
    { value: "straight", label: "Straight line" },
    { value: "walk", label: "Walking" }
];

const METRIC_HINTS: Record<Shard, Record<Metric, string>> = {
    forest: {
        straight: "Ignores the sea, so the Lunar, Hermit and Monkey islands look close.",
        walk: "Walks around water, so the Lunar, Hermit and Monkey islands can't be reached."
    },
    caves: {
        straight: "Ignores the cave walls, so places on the other side of the rock look close.",
        walk: "Walks around the cave walls, so places behind the rock can be far away or unreachable."
    }
};

interface TravelOptionsProps {
    travel: Travel;
    onChange: (travel: Travel) => void;
}

export default function TravelOptions({ travel, onChange }: TravelOptionsProps) {
    const shard = useWorldShard();
    return (
            <div className="travel">
                <SegmentedControl legend="Measured" options={METRIC_OPTIONS} value={travel.metric}
                                  onChange={(metric) => onChange({ ...travel, metric })}/>
                <Toggle checked={travel.links} onChange={(links) => onChange({ ...travel, links })}>
                    allow {shardCatalog(shard).links.plural}
                </Toggle>
                <p className="hint">{METRIC_HINTS[shard][travel.metric]}</p>
            </div>
    );
}
