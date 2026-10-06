"use client";

import { useState } from "react";
import SegmentedControl from "@/components/ui/SegmentedControl";
import type { Rates, SearchSpeeds as Speeds } from "@/lib/jobs/search-speed";
import LiveStats from "./LiveStats";

type SpeedView = "recent" | "full";

const COMPACT = new Intl.NumberFormat("en", { notation: "compact", maximumSignificantDigits: 3 });
const SMALL = new Intl.NumberFormat("en", { maximumFractionDigits: 1 });

const rate = (perSecond: number) => `${(perSecond < 100 ? SMALL : COMPACT).format(perSecond)}/s`;

const ROWS: { key: keyof Rates; label: string; note: string }[] = [
    { key: "prefilter", label: "Prefiltering", note: "seeds checked by biomes, resources and set pieces" },
    { key: "generation", label: "Generation", note: "worlds generated to check the world rules" },
    { key: "total", label: "Total", note: "seeds fully decided" }
];

/** The speeds of a search over the last 30 seconds or the whole run, shown alike for the cloud and the browser. */
export default function SearchSpeeds({ speeds }: { speeds: Speeds }) {
    const [view, setView] = useState<SpeedView>("recent");
    const shown = speeds[view];
    return (
            <div className="speeds">
                <SegmentedControl
                        legend="Speed"
                        options={[{ value: "recent", label: "30s" }, { value: "full", label: "full" }]}
                        value={view}
                        onChange={setView}
                />
                <LiveStats rows={ROWS.map(({ key, label, note }) => ({ label, value: rate(shown[key]), note }))}/>
            </div>
    );
}
