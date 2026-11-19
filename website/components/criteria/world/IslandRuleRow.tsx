"use client";

import Select from "@/components/ui/Select";
import Stepper from "@/components/ui/Stepper";
import { MAX_UINT32, type Shard } from "@/lib/config/seedfinder-config";
import { AREA_MODES, type AreaMode, type IslandRow } from "@/lib/criteria/world-rules";
import LinksToggle from "./LinksToggle";
import PrefabSetField from "./PrefabSetField";
import RuleFrame from "./RuleFrame";
import { useWorldKind } from "./WorldKind";

const BOUND_FIELDS: Record<AreaMode, ("min" | "max")[]> = {
    atMost: ["max"],
    atLeast: ["min"],
    between: ["min", "max"]
};

const SIZE_HINTS: Partial<Record<Shard, string>> = {
    forest: "The usual main island is around 40-50k tiles, and the Lunar island is around 2-4k tiles. Search for numbers like 10k to find smaller islands."
};

type Update = (patch: Partial<IslandRow>) => void;

function AreaBounds({ row, update }: { row: IslandRow; update: Update }) {
    const between = row.mode === "between";
    const range = { min: [0, between ? row.max : MAX_UINT32], max: [between ? row.min : 0, MAX_UINT32] };
    return BOUND_FIELDS[row.mode].map((field, index) => (
            <span key={field} className="rule__controls rule__controls--inline">
                {index > 0 && <span>and</span>}
                <Stepper label={`Land ${field === "min" ? "minimum" : "maximum"} in tiles`} value={row[field]}
                         min={range[field][0]} max={range[field][1]} wide
                         onChange={(tiles) => update({ [field]: tiles })}/>
                <span>tiles</span>
            </span>
    ));
}

interface IslandRuleRowProps {
    row: IslandRow;
    index: number;
    onChange: (row: IslandRow) => void;
    onRemove: () => void;
}

export default function IslandRuleRow({ row, index, onChange, onRemove }: IslandRuleRowProps) {
    const { shard } = useWorldKind();
    const update: Update = (patch) => onChange({ ...row, ...patch });
    const setMode = (mode: AreaMode) => update({
        mode,
        max: mode === "between" ? Math.max(row.max, row.min) : row.max
    });

    return (
            <RuleFrame title={`Island ${index + 1}`} onRemove={onRemove}>
                <PrefabSetField label="From" ids={row.at} onChange={(at) => update({ at })} autoOpen/>
                <div className="rule__controls">
                    <Select label="Land walking size" options={AREA_MODES} value={row.mode}
                            onChange={setMode}/>
                    <AreaBounds row={row} update={update}/>
                </div>
                <div className="travel">
                    <LinksToggle links={row.links} onChange={(links) => update({ links })}/>
                    {SIZE_HINTS[shard] && <p className="hint">{SIZE_HINTS[shard]}</p>}
                </div>
            </RuleFrame>
    );
}
