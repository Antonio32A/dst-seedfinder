"use client";

import { type KeyboardEvent, useEffect, useId, useMemo, useState } from "react";
import type { MapCanvas } from "@/lib/world-map/canvas/map-canvas";
import { instancesOf, type MapMatch, type MapTarget, searchPrefabs, stepInstance } from "@/lib/world-map/legend/prefab-search";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";

const MAX_SUGGESTIONS = 40;
const NEAREST: ScrollIntoViewOptions = { block: "nearest" };
const FOCUS_SCALE = 3;

interface PrefabSearchProps {
    world: GeneratedWorld;
    map: MapCanvas | null;
    onChange: (target: MapTarget | null) => void;
}

const count = (value: number) => value.toLocaleString("en-US");

export default function PrefabSearch({ world, map, onChange }: PrefabSearchProps) {
    const listId = useId();
    const [query, setQuery] = useState("");
    const [open, setOpen] = useState(false);
    const [active, setActive] = useState(0);
    const [chosen, setChosen] = useState<MapMatch | null>(null);
    const [current, setCurrent] = useState<number | null>(null);
    const suggestions = useMemo(() => searchPrefabs(world, query).slice(0, MAX_SUGGESTIONS), [world, query]);
    const instances = useMemo(() => (chosen ? instancesOf(world, chosen) : []), [world, chosen]);

    useEffect(() => {
        map?.highlight(Float32Array.from(instances.flatMap(({ x, z }) => [x, z])));
    }, [map, instances]);

    const choose = (match: MapMatch | null) => {
        setChosen(match);
        setCurrent(null);
        setOpen(false);
        setQuery(match?.displayName ?? "");
        onChange(match && { kind: match.kind, name: match.name });
    };

    const step = (by: number) => {
        const next = stepInstance(current, instances.length, by);
        setCurrent(next);
        map?.centre(instances[next], FOCUS_SCALE);
    };

    const keys: Record<string, () => void> = {
        ArrowDown: () => setActive((active + 1) % suggestions.length),
        ArrowUp: () => setActive((active - 1 + suggestions.length) % suggestions.length),
        Enter: () => choose(suggestions[active] ?? null),
        Escape: () => setOpen(false)
    };
    const pressed = (event: KeyboardEvent) => {
        const key = keys[event.key];
        if (key === undefined || !open || suggestions.length === 0) return;
        event.preventDefault();
        key();
    };

    const shownAt = current === null ? null : { number: current + 1, ...instances[current] };
    return (
            <div className="map__search">
                <div className="map__search-box">
                    <input type="search" role="combobox" aria-label="Find a prefab or set piece in this world"
                           aria-expanded={open && suggestions.length > 0} aria-controls={listId}
                           aria-autocomplete="list"
                           aria-activedescendant={open && suggestions.length > 0 ? `${listId}-${active}` : undefined}
                           placeholder="Find prefab" value={query}
                           onChange={(event) => {
                               setQuery(event.target.value);
                               setActive(0);
                               setOpen(true);
                               if (event.target.value === "") choose(null);
                           }}
                           onFocus={() => setOpen(true)} onBlur={() => setOpen(false)} onKeyDown={pressed}/>
                    {open && suggestions.length > 0 && (
                            <ul id={listId} role="listbox" className="map__suggestions"
                                aria-label="Prefabs and set pieces in this world">
                                {suggestions.map((match, index) => (
                                        <li key={`${match.kind} ${match.name}`} id={`${listId}-${index}`} role="option"
                                            aria-selected={index === active}
                                            ref={index === active ? (element) => element?.scrollIntoView(NEAREST) : undefined}
                                            onPointerDown={(event) => event.preventDefault()}
                                            onClick={() => choose(match)}>
                                            {match.kind === "set piece"
                                                    ? <>{match.name} <span className="map__kind">set piece</span></>
                                                    : <>{match.displayName} <code>{match.name}</code></>}
                                            <span className="map__count"> {count(match.count)}</span>
                                        </li>
                                ))}
                            </ul>
                    )}
                </div>
                {chosen && (
                        <div className="map__found" aria-live="polite">
                            <span>
                                {chosen.displayName}{chosen.kind === "set piece" && " set piece"}:{" "}
                                {count(chosen.count)} in this world
                                {shownAt && (
                                        <span className="map__count">
                                            , showing {count(shownAt.number)} at
                                            x {shownAt.x.toFixed(2)}, z {shownAt.z.toFixed(2)}
                                        </span>
                                )}
                            </span>
                            <button type="button" className="link-button" onClick={() => step(-1)}>previous</button>
                            <button type="button" className="link-button" onClick={() => step(1)}>next</button>
                            <button type="button" className="link-button" onClick={() => choose(null)}>clear</button>
                        </div>
                )}
            </div>
    );
}
