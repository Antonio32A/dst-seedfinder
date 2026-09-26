"use client";

import { useState } from "react";
import SegmentedControl from "@/components/ui/SegmentedControl";
import { clamp } from "@/lib/criteria/state-helpers";
import {
    formatCredits,
    formatDuration,
    isValidMaxCost,
    MAX_COST_OPTIONS,
    MAX_DOLLARS_PER_HOUR,
    MAX_MAX_COST,
    MIN_MAX_COST,
    roundCredits,
    STARTING_FEE,
    timeLimitSeconds
} from "@/lib/jobs/credits";

interface MaxCostFieldProps {
    value: number;
    wanted: number;
    onChange: (maxCost: number) => void;
}

export default function MaxCostField({ value, wanted, onChange }: MaxCostFieldProps) {
    const [draft, setDraft] = useState(() => formatCredits(value));
    const [shown, setShown] = useState(value);
    if (shown !== value) {
        setShown(value);
        if (Number(draft) !== value) setDraft(formatCredits(value));
    }

    const commitDraft = () => {
        const parsed = Number(draft);
        const next = draft.trim() !== "" && Number.isFinite(parsed) ? clamp(roundCredits(parsed), MIN_MAX_COST, MAX_MAX_COST) : value;
        onChange(next);
        setDraft(formatCredits(next));
    };

    return (
            <div>
                <div className="max-cost">
                    <SegmentedControl
                            legend="Max cost (credits)"
                            options={MAX_COST_OPTIONS.map((option) => ({ value: option, label: String(option) }))}
                            value={value}
                            onChange={onChange}
                    />
                    <label className="max-cost__custom">
                        <span className="sr-only">Custom max cost in credits</span>
                        <input
                                type="number"
                                inputMode="decimal"
                                min={MIN_MAX_COST}
                                max={MAX_MAX_COST}
                                step={0.01}
                                value={draft}
                                onChange={(event) => {
                                    setDraft(event.target.value);
                                    const parsed = Number(event.target.value);
                                    if (isValidMaxCost(parsed)) onChange(parsed);
                                }}
                                onBlur={commitDraft}
                        />
                    </label>
                </div>
                <p className="hint">
                    {STARTING_FEE} credits to start a server, then up
                    to {formatDuration(timeLimitSeconds(value, MAX_DOLLARS_PER_HOUR))} of search on a{" "}
                    {`$${MAX_DOLLARS_PER_HOUR.toFixed(2)}`}/h server, longer on cheaper ones. Stops
                    at {wanted} {wanted === 1 ? "seed" : "seeds"} or when the credits run out. Unused
                    credits are refunded.
                </p>
            </div>
    );
}
