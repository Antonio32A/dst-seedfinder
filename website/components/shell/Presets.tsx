"use client";

import type { Shard } from "@/lib/config/seedfinder-config";
import { type Preset, PRESETS } from "@/lib/criteria/search-state";

export default function Presets({ shard, onPick }: { shard: Shard; onPick: (preset: Preset) => void }) {
    return (
            <section className="section" aria-labelledby="presets">
                <h2 id="presets" className="section-title">
                    Presets
                </h2>
                <p className="muted small">Pick one and tweak it below.</p>
                <div className="presets">
                    {PRESETS[shard].map((preset) => (
                            <button key={preset.id} type="button" className="preset" onClick={() => onPick(preset)}>
                                <span>{preset.name}</span>
                                <span className="preset__description">{preset.description}</span>
                            </button>
                    ))}
                </div>
            </section>
    );
}
