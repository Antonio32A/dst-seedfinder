"use client";

import { useEffect, useId } from "react";
import type { Probe } from "@/lib/world-map/map-probe";

const coordinate = (value: number) => value.toFixed(2);

/** What a click on the map picked: the entity and its tile, or the tile alone. Escape closes it. */
export default function MapDetails({ probe: { entity, tile }, onClose }: { probe: Probe; onClose: () => void }) {
    const titleId = useId();

    useEffect(() => {
        const pressed = (event: KeyboardEvent) => {
            if (event.key === "Escape" && !event.defaultPrevented) onClose();
        };
        addEventListener("keydown", pressed);
        return () => removeEventListener("keydown", pressed);
    }, [onClose]);

    return (
            <section className="map-bar map-details" aria-labelledby={titleId}>
                <div className="map-details__header">
                    <h2 id={titleId} className="map-details__title">{entity?.displayName ?? tile?.displayName}</h2>
                    <button type="button" className="link-button" aria-label="Close the details" onClick={onClose}>
                        close
                    </button>
                </div>
                <dl className="map-details__facts">
                    {entity && (
                            <>
                                <dt>prefab</dt>
                                <dd><code>{entity.prefab}</code></dd>
                                <dt>index</dt>
                                <dd>{entity.index}</dd>
                                <dt>x, z</dt>
                                <dd>{coordinate(entity.x)}, {coordinate(entity.z)}</dd>
                            </>
                    )}
                    {tile && (
                            <>
                                <dt>tile</dt>
                                <dd>{tile.displayName} <code>{tile.name}</code></dd>
                            </>
                    )}
                </dl>
            </section>
    );
}
