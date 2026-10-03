"use client";

import { useEffect, useState } from "react";
import type { MapCanvas } from "@/lib/world-map/canvas/map-canvas";

const TURN_LEFT = { steps: -1, text: "<", label: "Rotate left (Q)" };
const TURN_RIGHT = { steps: 1, text: ">", label: "Rotate right (E)" };
const CLEAR_FOG_LABEL = "Clear the fog";
const COPY_LINK_TITLE = "Copy a link to the map as you see it";

export default function MapCorner({ seed, map, onCopyLink }: {
    seed?: number;
    map?: MapCanvas | null;
    onCopyLink?: () => void;
}) {
    const [clear, setClear] = useState(false);
    const turnButton = ({ steps, text, label }: typeof TURN_LEFT) => (
            <button type="button" className="map-corner__button" title={label} aria-label={label}
                    onClick={() => map?.turn(steps)}>
                {text}
            </button>
    );

    useEffect(() => {
        map?.darken(!clear);
    }, [map, clear]);

    return (
            <div className="map-bar map-corner" role="toolbar" aria-label="Map controls">
                {seed !== undefined && <span className="map-corner__seed">Seed {seed}</span>}
                {onCopyLink && (
                        <button type="button" className="map-corner__button" title={COPY_LINK_TITLE} disabled={!map}
                                onClick={onCopyLink}>
                            Copy link
                        </button>
                )}
                {map !== undefined && (
                        <>
                            {turnButton(TURN_LEFT)}
                            <button type="button" className="map-corner__button" title={CLEAR_FOG_LABEL}
                                    aria-label={CLEAR_FOG_LABEL} aria-pressed={clear} onClick={() => setClear(!clear)}>
                                #
                            </button>
                            {turnButton(TURN_RIGHT)}
                        </>
                )}
            </div>
    );
}
