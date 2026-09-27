"use client";

import ThemeToggle from "@/components/shell/ThemeToggle";
import type { MapCanvas } from "@/lib/world-map/map-canvas";

const TURNS = [
    { steps: -1, text: "<", label: "Rotate left (Q)" },
    { steps: 1, text: ">", label: "Rotate right (E)" }
] as const;

/** The map's bottom right corner: the seed, the rotate buttons once there's a map to turn, and the theme toggle. */
export default function MapCorner({ seed, map }: { seed?: number; map?: MapCanvas | null }) {
    return (
            <div className="map-bar map-corner" role="toolbar" aria-label="Map controls">
                {seed !== undefined && <span className="map-corner__seed">Seed {seed}</span>}
                {map !== undefined && TURNS.map(({ steps, text, label }) => (
                        <button key={steps} type="button" className="map-corner__turn" title={label} aria-label={label}
                                onClick={() => map?.turn(steps)}>
                            {text}
                        </button>
                ))}
                <ThemeToggle/>
            </div>
    );
}
