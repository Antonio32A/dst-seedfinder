"use client";

import { PRESETS, type Preset } from "@/lib/search-state";

export default function Presets({ onPick }: { onPick: (preset: Preset) => void }) {
  return (
    <section className="section" aria-labelledby="presets">
      <h2 id="presets" className="section-title">
        Presets
      </h2>
      <p className="muted small">Pick one and tweak it below.</p>
      <div className="presets">
        {PRESETS.map((preset) => (
          <button key={preset.id} type="button" className="preset" onClick={() => onPick(preset)}>
            <span>{preset.name}</span>
            <span className="preset__description">{preset.description}</span>
          </button>
        ))}
      </div>
    </section>
  );
}
