"use client";

import { SWAPS } from "@/lib/catalog";
import type { SwapCategory } from "@/lib/catalog-types";
import type { CriteriaGroup } from "@/lib/search-state";
import SegmentedControl from "./SegmentedControl";

const ANY = "";

interface ResourceSectionProps {
  swaps: CriteriaGroup["swaps"];
  onChange: (swaps: CriteriaGroup["swaps"]) => void;
}

export default function ResourceSection({ swaps, onChange }: ResourceSectionProps) {
  const set = (category: SwapCategory, value: string) => {
    const { [category]: _removed, ...rest } = swaps;
    onChange(value === ANY ? rest : { ...rest, [category]: value });
  };

  return (
    <div className="subsection">
      <h4 className="subsection__title">Resource variety</h4>
      <p className="muted small">Each world gets one version of each of these resources.</p>
      <div className="swaps">
        {SWAPS.map((swap) => (
          <div key={swap.id}>
            <SegmentedControl
              legend={swap.name}
              options={[{ value: ANY, label: "Don't care" }, ...swap.options.map((option) => ({ value: option.id, label: option.name, title: option.description }))]}
              value={swaps[swap.id] ?? ANY}
              onChange={(value) => set(swap.id, value)}
            />
            {swap.description && <p className="hint">{swap.description}</p>}
          </div>
        ))}
      </div>
    </div>
  );
}
