"use client";

import Toggle from "@/components/ui/Toggle";
import { WORLD_UNITS_PER_TILE } from "@/lib/config/seedfinder-config";
import type { BridgeRow } from "@/lib/criteria/world-rules";
import RuleFrame from "./RuleFrame";
import TileDistance from "./TileDistance";

const DEFAULT_MAX_TILES = 100;

interface BridgeRuleRowProps {
    row: BridgeRow;
    index: number;
    onChange: (row: BridgeRow) => void;
    onRemove: () => void;
}

export default function BridgeRuleRow({ row, index, onChange, onRemove }: BridgeRuleRowProps) {
    const update = (patch: Partial<BridgeRow>) => onChange({ ...row, ...patch });
    const capped = (on: boolean) => update({ max: on ? Math.max(row.min, DEFAULT_MAX_TILES * WORLD_UNITS_PER_TILE) : null });

    return (
            <RuleFrame title={`Turf bridge ${index + 1}`} onRemove={onRemove}>
                <div className="rule__controls">
                    <span>A room cut off from the rest of the map, joined by a turf bridge at least</span>
                    <TileDistance label="Bridge minimum" units={row.min} maxUnits={row.max ?? undefined}
                                  onChange={(min) => update({ min })}/>
                    <span>long</span>
                </div>
                <div className="rule__scope">
                    <Toggle checked={row.max !== null} onChange={capped}>
                        and at most
                    </Toggle>
                    {row.max !== null && (
                            <div className="rule__controls">
                                <TileDistance label="Bridge maximum" units={row.max} minUnits={row.min}
                                              onChange={(max) => update({ max })}/>
                                <span>long</span>
                            </div>
                    )}
                </div>
                <p className="hint">
                    The world generation sometimes leaves one room far from the rooms it links to and places a thin path
                    of its turf across the map to reach it. This can cause weird, but cool world seeds where you
                    effectively have an island that's connected by a long bridge.
                    Normal links are under 25 tiles, but in the caves about 1 world in 1,500 has one over 60 tiles,
                    and about 1 in 10,000 one over 100.
                </p>
            </RuleFrame>
    );
}
