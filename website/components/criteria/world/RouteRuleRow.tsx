"use client";

import { useRef } from "react";
import Toggle from "@/components/ui/Toggle";
import { MAX_ROUTE_STOPS } from "@/lib/config/seedfinder-config";
import { replaceByKey, withoutKey } from "@/lib/criteria/state-helpers";
import { newRouteStop, routeConflict, type RouteRow } from "@/lib/criteria/world-rules";
import PrefabSetField from "./PrefabSetField";
import RuleFrame from "./RuleFrame";
import TileDistance from "./TileDistance";
import TravelOptions from "./TravelOptions";

type Update = (patch: Partial<RouteRow>) => void;

function StopActions({ row, index, update, onRemove }: {
    row: RouteRow;
    index: number;
    update: Update;
    onRemove: () => void;
}) {
    const stop = row.stops[index];
    const move = (offset: number) => {
        const stops = [...row.stops];
        stops.splice(index + offset, 0, ...stops.splice(index, 1));
        update({ stops });
        const target = index + offset === 0 || index + offset === row.stops.length - 1 ? -offset : offset;
        setTimeout(() => document.getElementById(`${stop.key}-${target}`)?.focus());
    };
    return (
            <span className="route-stop__actions">
      <button id={`${stop.key}--1`} type="button" className="link-button" aria-label={`Move stop ${index + 1} earlier`}
              disabled={index === 0} onClick={() => move(-1)}>
        ↑
      </button>
      <button id={`${stop.key}-1`} type="button" className="link-button" aria-label={`Move stop ${index + 1} later`}
              disabled={index === row.stops.length - 1} onClick={() => move(1)}>
        ↓
      </button>
      <button
              type="button"
              className="link-button link-button--danger"
              aria-label={`Remove stop ${index + 1}`}
              disabled={row.stops.length === 1}
              onClick={onRemove}
      >
        ×
      </button>
    </span>
    );
}

function Stops({ row, update }: { row: RouteRow; update: Update }) {
    const addStop = useRef<HTMLButtonElement>(null);
    const removeStop = (key: string) => {
        update({ stops: withoutKey(row.stops, key) });
        setTimeout(() => addStop.current?.focus());
    };
    return (
            <fieldset className="seg route-stops">
                <legend className="field-label">
                    Stops ({row.stops.length}/{MAX_ROUTE_STOPS})
                </legend>
                <ol>
                    {row.stops.map((stop, index) => (
                            <li key={stop.key} className="route-stop">
                                <PrefabSetField label={`Stop ${index + 1}`} ids={stop.prefabs}
                                                onChange={(prefabs) => update({
                                                    stops: replaceByKey(row.stops, {
                                                        ...stop,
                                                        prefabs
                                                    })
                                                })}
                                                blocked={routeConflict(row, index)} autoOpen/>
                                <StopActions row={row} index={index} update={update}
                                             onRemove={() => removeStop(stop.key)}/>
                            </li>
                    ))}
                </ol>
                <button ref={addStop} type="button" className="link-button"
                        disabled={row.stops.length >= MAX_ROUTE_STOPS}
                        onClick={() => update({ stops: [...row.stops, newRouteStop()] })}>
                    Add stop
                </button>
            </fieldset>
    );
}

interface RouteRuleRowProps {
    row: RouteRow;
    index: number;
    onChange: (row: RouteRow) => void;
    onRemove: () => void;
}

export default function RouteRuleRow({ row, index, onChange, onRemove }: RouteRuleRowProps) {
    const update: Update = (patch) => onChange({ ...row, ...patch });
    const ends = routeConflict(row, "ends");

    return (
            <RuleFrame title={`Route ${index + 1}`} onRemove={onRemove}>
                <PrefabSetField label="Start at" ids={row.from} onChange={(from) => update({ from })} blocked={ends}/>
                <Stops row={row} update={update}/>
                <div className="rule__scope chips">
                    <Toggle checked={row.roundTrip} onChange={(roundTrip) => update({ roundTrip })}>
                        return to the start
                    </Toggle>
                    <Toggle checked={row.order === "fixed"}
                            onChange={(fixed) => update({ order: fixed ? "fixed" : "any" })}>
                        visit the stops in this order
                    </Toggle>
                </div>
                {!row.roundTrip &&
                        <PrefabSetField label="End at (optional)" ids={row.to} onChange={(to) => update({ to })}
                                        blocked={ends}/>}
                <div className="rule__controls">
                    <span className="field-label">Whole route at most</span>
                    <TileDistance label="Route length" units={row.max} onChange={(max) => update({ max })}/>
                </div>
                {row.order === "any" &&
                        <p className="hint">The stops can be visited in whichever order is shortest.</p>}
                <TravelOptions travel={row} onChange={(travel) => update(travel)}/>
            </RuleFrame>
    );
}
