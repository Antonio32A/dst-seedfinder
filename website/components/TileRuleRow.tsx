"use client";

import { MAX_TILE_STEPS, type TileRow } from "@/lib/world-rules";
import RuleFrame from "./RuleFrame";
import Stepper from "./Stepper";
import TileSetField from "./TileSetField";

interface TileRuleRowProps {
  row: TileRow;
  index: number;
  onChange: (row: TileRow) => void;
  onRemove: () => void;
}

export default function TileRuleRow({ row, index, onChange, onRemove }: TileRuleRowProps) {
  return (
    <RuleFrame title={`Turf rule ${index + 1}`} onRemove={onRemove}>
      <TileSetField label="A tile of" names={row.from} onChange={(from) => onChange({ ...row, from })} />
      <div className="rule__controls">
        <span className="field-label">within</span>
        <Stepper label="Tile steps" value={row.max} min={0} max={MAX_TILE_STEPS} onChange={(max) => onChange({ ...row, max })} />
        <span>tile steps of</span>
      </div>
      <TileSetField label="a tile of" names={row.to} onChange={(to) => onChange({ ...row, to })} />
      <p className="hint">Steps go up, down, left or right, and can cross water.</p>
    </RuleFrame>
  );
}
