"use client";

import { useEffect, useId } from "react";
import type { Probe } from "@/lib/world-map/map-probe";

const coordinate = (value: number) => value.toFixed(2);
const tiles = (value: number) => Number(value.toFixed(2)).toString();

interface MapDetailsProps {
    probe: Probe;
    onClose: () => void;
    /** Called with the index of the set piece whose details to show instead. */
    onOpenSetPiece: (index: number) => void;
}

/** What a click on the map picked: the entity and its tile, the set piece, or the tile alone. Escape closes it. */
export default function MapDetails({ probe: { entity, setPiece, tile }, onClose, onOpenSetPiece }: MapDetailsProps) {
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
                    <h2 id={titleId} className="map-details__title">
                        {entity?.displayName ?? setPiece?.name ?? tile?.displayName}
                    </h2>
                    <button type="button" className="link-button" aria-label="Close the details" onClick={onClose}>
                        close
                    </button>
                </div>
                {entity?.setPiece && (
                        <p className="map-details__part">
                            part of set piece{" "}
                            <button type="button" className="link-button"
                                    onClick={() => onOpenSetPiece(entity.setPiece!.index)}>
                                {entity.setPiece.name}
                            </button>
                        </p>
                )}
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
                    {setPiece && (
                            <>
                                <dt>source</dt>
                                <dd>{setPiece.source}</dd>
                                <dt>centre</dt>
                                <dd>{coordinate(setPiece.x)}, {coordinate(setPiece.z)}</dd>
                                <dt>size</dt>
                                <dd>{tiles(setPiece.width)} × {tiles(setPiece.height)} tiles</dd>
                                <dt>transform</dt>
                                <dd>{setPiece.transform}</dd>
                                <dt>members</dt>
                                <dd>
                                    <ul className="map-details__members">
                                        {setPiece.members.map(({ prefab, displayName, count }) => (
                                                <li key={prefab} title={prefab}>
                                                    {displayName} <span className="map__count">{count}</span>
                                                </li>
                                        ))}
                                    </ul>
                                </dd>
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
