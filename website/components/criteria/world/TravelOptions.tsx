"use client";

import SegmentedControl from "@/components/ui/SegmentedControl";
import Toggle from "@/components/ui/Toggle";
import type { Metric } from "@/lib/config/seedfinder-config";
import type { Travel } from "@/lib/criteria/world-rules";

const METRIC_OPTIONS: { value: Metric; label: string }[] = [
    { value: "straight", label: "Straight line" },
    { value: "walk", label: "Walking" }
];

const METRIC_HINTS: Record<Metric, string> = {
    straight: "Ignores the sea, so the Lunar, Hermit and Monkey islands look close.",
    walk: "Walks around water, so the Lunar, Hermit and Monkey islands can't be reached."
};

interface TravelOptionsProps {
    travel: Travel;
    onChange: (travel: Travel) => void;
}

/** How a distance is measured: straight or walking, and whether wormhole jumps are allowed. */
export default function TravelOptions({ travel, onChange }: TravelOptionsProps) {
    return (
            <div className="travel">
                <SegmentedControl legend="Measured" options={METRIC_OPTIONS} value={travel.metric}
                                  onChange={(metric) => onChange({ ...travel, metric })}/>
                <Toggle checked={travel.wormholes} onChange={(wormholes) => onChange({ ...travel, wormholes })}>
                    allow wormholes
                </Toggle>
                <p className="hint">{METRIC_HINTS[travel.metric]}</p>
            </div>
    );
}
