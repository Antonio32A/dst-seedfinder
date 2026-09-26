"use client";

import { countCap, countHint } from "@/lib/prefab-sets";
import { PREFAB_BY_ID } from "@/lib/world-catalog";
import {
    COUNT_FLOOR,
    type CountRow,
    type NearRow,
    newNear,
    WORLD_COUNT_MODES,
    type WorldCountMode
} from "@/lib/world-rules";
import PrefabSetField from "./PrefabSetField";
import RuleFrame from "./RuleFrame";
import Stepper from "./Stepper";
import TileDistance from "./TileDistance";
import Toggle from "./Toggle";
import TravelOptions from "./TravelOptions";

const BOUND_FIELDS: Record<WorldCountMode, ["min" | "max", string][]> = {
    atLeast: [["min", "Count minimum"]],
    atMost: [["max", "Count maximum"]],
    exactly: [["min", "Exact count"]],
    between: [
        ["min", "Count minimum"],
        ["max", "Count maximum"]
    ],
    none: []
};

const alwaysOne = (id: string) => {
    const prefab = PREFAB_BY_ID.get(id);
    return prefab?.always && prefab.unique ? "always exactly 1" : undefined;
};

type Update = (patch: Partial<CountRow>) => void;

function CountBounds({ row, update }: { row: CountRow; update: Update }) {
    const cap = countCap(row.prefabs);
    const floor = COUNT_FLOOR[row.mode];
    const range = {
        min: [floor, row.mode === "between" ? row.max : cap],
        max: [row.mode === "between" ? row.min : floor, cap]
    };
    return BOUND_FIELDS[row.mode].map(([field, label], index) => (
            <span key={field} className="rule__controls rule__controls--inline">
      {index > 0 && <span>and</span>}
                <Stepper label={label} value={row[field]} min={range[field][0]} max={range[field][1]}
                         onChange={(value) => update({ [field]: value })}/>
    </span>
    ));
}

function NearControls({ near, counted, onChange }: {
    near: NearRow | null;
    counted: string[];
    onChange: (near: NearRow | null) => void
}) {
    const overlaps = near?.prefabs.some((id) => counted.includes(id));
    return (
            <div className="rule__scope">
                <Toggle checked={near !== null} onChange={(on) => onChange(on ? newNear() : null)}>
                    only count ones near something
                </Toggle>
                {near && (
                        <div className="nested">
                            <PrefabSetField label="Near" ids={near.prefabs}
                                            onChange={(prefabs) => onChange({ ...near, prefabs })}/>
                            <div className="rule__controls">
                                <span className="field-label">Within</span>
                                <TileDistance label="Near distance" units={near.within}
                                              onChange={(within) => onChange({ ...near, within })}/>
                            </div>
                            {overlaps && <p className="hint">A thing never counts as near itself.</p>}
                            <TravelOptions travel={near} onChange={(travel) => onChange({ ...near, ...travel })}/>
                        </div>
                )}
            </div>
    );
}

interface CountRuleRowProps {
    row: CountRow;
    index: number;
    onChange: (row: CountRow) => void;
    onRemove: () => void;
}

export default function CountRuleRow({ row, index, onChange, onRemove }: CountRuleRowProps) {
    const update: Update = (patch) => onChange({ ...row, ...patch });
    const setMode = (mode: WorldCountMode) => {
        const min = Math.max(row.min, COUNT_FLOOR[mode]);
        update({ mode, min, max: Math.max(row.max, mode === "between" ? min : COUNT_FLOOR[mode]) });
    };

    return (
            <RuleFrame title={`Count ${index + 1}`} onRemove={onRemove}>
                <PrefabSetField label="What to count" ids={row.prefabs} onChange={(prefabs) => update({ prefabs })}
                                blocked={alwaysOne} autoOpen/>
                <div className="rule__controls">
                    <label>
                        <span className="field-label">How many</span>
                        <select value={row.mode} onChange={(event) => setMode(event.target.value as WorldCountMode)}>
                            {WORLD_COUNT_MODES.map((mode) => (
                                    <option key={mode.id} value={mode.id}>
                                        {mode.label}
                                    </option>
                            ))}
                        </select>
                    </label>
                    <CountBounds row={row} update={update}/>
                    {row.prefabs.length > 0 && <span className="hint">{countHint(row.prefabs)}</span>}
                </div>
                <NearControls near={row.near} counted={row.prefabs} onChange={(near) => update({ near })}/>
            </RuleFrame>
    );
}
