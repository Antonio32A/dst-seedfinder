"use client";

import { DISTANCE_MODES, type DistanceMode, type DistanceRow } from "@/lib/world-rules";
import PrefabSetField from "./PrefabSetField";
import RuleFrame from "./RuleFrame";
import TileDistance from "./TileDistance";
import TravelOptions from "./TravelOptions";

const BOUND_FIELDS: Record<DistanceMode, ("min" | "max")[]> = {
    within: ["max"],
    atLeast: ["min"],
    between: ["min", "max"]
};

type Update = (patch: Partial<DistanceRow>) => void;

function DistanceBounds({ row, update }: { row: DistanceRow; update: Update }) {
    const between = row.mode === "between";
    const range = { min: { maxUnits: between ? row.max : undefined }, max: { minUnits: between ? row.min : 0 } };
    return BOUND_FIELDS[row.mode].map((field, index) => (
            <span key={field} className="rule__controls rule__controls--inline">
      {index > 0 && <span>and</span>}
                <TileDistance label={`Distance ${field === "min" ? "minimum" : "maximum"}`} units={row[field]}
                              onChange={(units) => update({ [field]: units })} {...range[field]} />
    </span>
    ));
}

interface DistanceRuleRowProps {
    row: DistanceRow;
    index: number;
    onChange: (row: DistanceRow) => void;
    onRemove: () => void;
}

export default function DistanceRuleRow({ row, index, onChange, onRemove }: DistanceRuleRowProps) {
    const update: Update = (patch) => onChange({ ...row, ...patch });
    const setMode = (mode: DistanceMode) => update({
        mode,
        max: mode === "between" ? Math.max(row.max, row.min) : row.max
    });

    return (
            <RuleFrame title={`Distance ${index + 1}`} onRemove={onRemove}>
                <PrefabSetField label="From" ids={row.from} onChange={(from) => update({ from })}/>
                <PrefabSetField label="To" ids={row.to} onChange={(to) => update({ to })} autoOpen/>
                <div className="rule__controls">
                    <label>
                        <span className="field-label">Closest pair is</span>
                        <select value={row.mode} onChange={(event) => setMode(event.target.value as DistanceMode)}>
                            {DISTANCE_MODES.map((mode) => (
                                    <option key={mode.id} value={mode.id}>
                                        {mode.label}
                                    </option>
                            ))}
                        </select>
                    </label>
                    <DistanceBounds row={row} update={update}/>
                </div>
                <TravelOptions travel={row} onChange={(travel) => update(travel)}/>
            </RuleFrame>
    );
}
