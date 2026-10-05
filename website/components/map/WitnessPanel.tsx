"use client";

import { useEffect, useId, useMemo, useState } from "react";
import type { Criterion, SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { describeWitness } from "@/lib/jobs/witness-text";
import { type EvalLoad, evaluateWorld } from "@/lib/world-map/search/evaluate-world";
import type { MapCanvas } from "@/lib/world-map/canvas/map-canvas";
import type { MapConfig } from "@/lib/world-map/map-route";
import { witnessShapes } from "@/lib/world-map/search/witness-overlay";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";
import type { WorldEval } from "@/lib/world-map/search/world-eval";

interface WitnessPanelProps {
    shared: MapConfig;
    world: GeneratedWorld;
    bytes: Uint8Array;
    map: MapCanvas | null;
}

interface WitnessChecksProps {
    evaluation: WorldEval;
    criterion: Criterion | undefined;
    world: GeneratedWorld;
    map: MapCanvas | null;
}

function WitnessChecks({ evaluation, criterion, world, map }: WitnessChecksProps) {
    const titleId = useId();
    const { matched, entry, entries, witnesses } = evaluation;
    const shapes = useMemo(() => witnessShapes(witnesses, criterion, world), [witnesses, criterion, world]);

    useEffect(() => {
        map?.witnesses(shapes);
        return () => map?.witnesses([]);
    }, [map, shapes]);

    return (
            <>
                <h3 id={titleId} className="map__witnesses-title">
                    Checks{entries > 1 && ` of option ${entry + 1}`}
                </h3>
                {!matched && <p className="notice notice--warning">This world doesn't match the search.</p>}
                {witnesses.length === 0 && <p className="muted">The search has no world checks.</p>}
                <ul className="map__checks" aria-labelledby={titleId}>
                    {witnesses.map((witness, at) => {
                        const { focus } = shapes[at];
                        return (
                                <li key={`${witness.section}-${witness.index}`}>
                                    <button type="button" className="map__check" disabled={focus === null}
                                            onClick={() => focus && map?.centre(focus)}>
                                        <span className={witness.ok ? "witness__ok" : "witness__failed"}>{witness.ok ? "ok" : "failed"}</span>{" "}
                                        {describeWitness(witness)}
                                    </button>
                                </li>
                        );
                    })}
                </ul>
            </>
    );
}

export default function WitnessPanel({ shared, world, bytes, map }: WitnessPanelProps) {
    const config = "config" in shared ? shared.config : null;
    const [loaded, setLoaded] = useState<{ config: SeedfinderConfig; bytes: Uint8Array; load: EvalLoad } | null>(null);

    useEffect(() => {
        if (config === null) return;
        const controller = new AbortController();
        void evaluateWorld(bytes, config, controller.signal).then((load) => {
            if (!controller.signal.aborted) setLoaded({ config, bytes, load });
        });
        return () => controller.abort();
    }, [config, bytes]);

    const load: EvalLoad = loaded?.config === config && loaded.bytes === bytes ? loaded.load : { status: "loading" };

    const error = "error" in shared
            ? `The search in this link can't be read: ${shared.error}`
            : load.status === "failed" ? load.error : null;
    return (
            <details className="map-bar map__witnesses" open>
                <summary>Search</summary>
                {error !== null ? (
                        <p className="notice notice--error" role="alert">{error}</p>
                ) : load.status === "ready" ? (
                        <WitnessChecks evaluation={load.evaluation}
                                       criterion={config?.criteria?.[load.evaluation.entry]}
                                       world={world} map={map}/>
                ) : (
                        <p className="hint" role="status">Checking the search on this world...</p>
                )}
            </details>
    );
}
