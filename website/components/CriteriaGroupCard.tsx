"use client";

import { useId } from "react";
import type { CriteriaGroup } from "@/lib/search-state";
import type { Platform } from "@/lib/seedfinder-config";
import BiomeSection from "./BiomeSection";
import ResourceSection from "./ResourceSection";
import SetPieceSection from "./SetPieceSection";
import WorldSection from "./WorldSection";

interface CriteriaGroupCardProps {
  group: CriteriaGroup;
  index: number;
  total: number;
  platform: Platform;
  onChange: (group: CriteriaGroup) => void;
  onRemove: () => void;
}

export default function CriteriaGroupCard({ group, index, total, platform, onChange, onRemove }: CriteriaGroupCardProps) {
  const titleId = useId();
  return (
    <section className="framed group" aria-labelledby={titleId}>
      <div className="group__header">
        <h3 id={titleId} className="group__title">
          {total > 1 ? `Option ${index + 1}` : "The world must have…"}
        </h3>
        {total > 1 && (
          <button type="button" className="link-button link-button--danger" onClick={onRemove}>
            remove option {index + 1}
          </button>
        )}
      </div>
      <BiomeSection biomes={group.biomes} onChange={(biomes) => onChange({ ...group, biomes })} />
      <ResourceSection swaps={group.swaps} onChange={(swaps) => onChange({ ...group, swaps })} />
      <SetPieceSection rules={group.rules} onChange={(rules) => onChange({ ...group, rules })} />
      <WorldSection rows={group} platform={platform} onChange={(rows) => onChange({ ...group, ...rows })} />
    </section>
  );
}
