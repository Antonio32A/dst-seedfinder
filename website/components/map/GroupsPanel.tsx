"use client";

import { useState } from "react";
import { groupState, type LegendGroup, showPrefabs } from "@/lib/world-map/prefab-visibility";

interface GroupRowProps {
    entry: LegendGroup;
    shown: ReadonlySet<string>;
    onChange: (shown: ReadonlySet<string>) => void;
    /** Whether the group draws outlines rather than dots. */
    outlined?: boolean;
}

interface GroupsPanelProps {
    legend: LegendGroup[];
    shown: ReadonlySet<string>;
    onChange: (shown: ReadonlySet<string>) => void;
    /** The world's set pieces, `null` without any. */
    setPieces: LegendGroup | null;
    shownSetPieces: ReadonlySet<string>;
    onSetPiecesChange: (shown: ReadonlySet<string>) => void;
}

const count = (value: number) => value.toLocaleString("en-US");

function GroupRow({ entry, shown, onChange, outlined = false }: GroupRowProps) {
    const [expanded, setExpanded] = useState(false);
    const { group, prefabs } = entry;
    const state = groupState(entry, shown);
    const ids = prefabs.map(({ prefab }) => prefab);
    const colour = `rgb(${group.colour.join()})`;
    const members = `${group.name} ${outlined ? "by layout" : "prefabs"}`;
    return (
            <li>
                <div className="map-group">
                    <button type="button" className="map-group__expand" aria-expanded={expanded}
                            aria-label={members} onClick={() => setExpanded(!expanded)}>
                        {expanded ? "-" : "+"}
                    </button>
                    <label className="map-group__toggle">
                        <input type="checkbox" checked={state === "on"}
                               ref={(element) => {
                                   if (element) element.indeterminate = state === "mixed";
                               }}
                               onChange={(event) => onChange(showPrefabs(shown, ids, event.target.checked))}/>
                        <span className={`map__swatch${outlined ? " map__swatch--outline" : ""}`}
                              style={outlined ? { borderColor: colour } : { background: colour }}/>
                        <span>{group.name} <span className="map__count">{count(entry.count)}</span></span>
                    </label>
                </div>
                {expanded && (
                        <ul className="map-group__prefabs" aria-label={members}>
                            {prefabs.map(({ prefab, displayName, count: instances }) => (
                                    <li key={prefab}>
                                        <label className="map-group__toggle" title={prefab}>
                                            <input type="checkbox" checked={shown.has(prefab)} onChange={(event) =>
                                                    onChange(showPrefabs(shown, [prefab], event.target.checked))}/>
                                            <span>{displayName} <span
                                                    className="map__count">{count(instances)}</span></span>
                                        </label>
                                    </li>
                            ))}
                        </ul>
                )}
            </li>
    );
}

/**
 * The map's filters: the world's entity groups, each a toggle for all its prefabs that expands to one per prefab, and
 * its set pieces, a toggle that expands to one per layout name.
 */
export default function GroupsPanel(props: GroupsPanelProps) {
    const { legend, shown, onChange, setPieces, shownSetPieces, onSetPiecesChange } = props;
    return (
            <details className="map-bar map-groups">
                <summary>Filters</summary>
                <ul className="map-groups__list" aria-label="Entity groups">
                    {legend.map((entry) => (
                            <GroupRow key={entry.group.id} entry={entry} shown={shown} onChange={onChange}/>
                    ))}
                    {setPieces && (
                            <GroupRow entry={setPieces} shown={shownSetPieces} onChange={onSetPiecesChange} outlined/>
                    )}
                </ul>
            </details>
    );
}
