"use client";

import { useState } from "react";
import { groupState, type LegendGroup, showPrefabs } from "@/lib/world-map/legend/prefab-visibility";
import { formatCount } from "./format";

const ROAD_SWATCH = [75, 71, 60];

interface GroupRowProps {
    entry: LegendGroup;
    shown: ReadonlySet<string>;
    onChange: (shown: ReadonlySet<string>) => void;
    outlined?: boolean;
    /** Called with the prefabs under the pointer or focus, and none when it leaves. Rows without it don't highlight. */
    onHighlight?: (prefabs: readonly string[]) => void;
}

interface GroupsPanelProps {
    legend: LegendGroup[];
    shown: ReadonlySet<string>;
    onChange: (shown: ReadonlySet<string>) => void;
    onHighlight: (prefabs: readonly string[]) => void;
    /** The world's set pieces, `null` without any. */
    setPieces: LegendGroup | null;
    shownSetPieces: ReadonlySet<string>;
    onSetPiecesChange: (shown: ReadonlySet<string>) => void;
    /** The wormhole (tentacle pillar in the caves) connection lines toggle, `null` for a world without any. */
    links: { label: string; shown: boolean; colour: readonly number[]; onChange: (shown: boolean) => void } | null;
    /** The road toggle, `null` for a world without roads. */
    roads: { shown: boolean; onChange: (shown: boolean) => void } | null;
    onSelect: (selection: "all" | "none" | "reset") => void;
}

function GroupRow({ entry, shown, onChange, outlined = false, onHighlight }: GroupRowProps) {
    const [expanded, setExpanded] = useState(false);
    const { group, prefabs } = entry;
    const state = groupState(entry, shown);
    const ids = prefabs.map(({ prefab }) => prefab);
    const colour = `rgb(${group.colour.join()})`;
    const members = `${group.name} ${outlined ? "by layout" : "prefabs"}`;
    const highlighting = (prefabs: readonly string[]) => onHighlight && {
        onPointerEnter: () => onHighlight(prefabs),
        onPointerLeave: () => onHighlight([]),
        onFocus: () => onHighlight(prefabs),
        onBlur: () => onHighlight([])
    };
    return (
            <li>
                <div className="map-group" {...highlighting(ids)}>
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
                        <span>{group.name} <span className="map__count">{formatCount(entry.count)}</span></span>
                    </label>
                </div>
                {expanded && (
                        <ul className="map-group__prefabs" aria-label={members}>
                            {prefabs.map(({ prefab, displayName, count: instances }) => (
                                    <li key={prefab}>
                                        <label className="map-group__toggle" title={prefab} {...highlighting([prefab])}>
                                            <input type="checkbox" checked={shown.has(prefab)} onChange={(event) =>
                                                    onChange(showPrefabs(shown, [prefab], event.target.checked))}/>
                                            <span>{displayName} <span
                                                    className="map__count">{formatCount(instances)}</span></span>
                                        </label>
                                    </li>
                            ))}
                        </ul>
                )}
            </li>
    );
}

export default function GroupsPanel(props: GroupsPanelProps) {
    const { legend, shown, onChange, onHighlight, setPieces, shownSetPieces, onSetPiecesChange, links, roads, onSelect } = props;
    return (
            <details className="map-bar map-groups">
                <summary>Filters</summary>
                <div className="map-groups__controls">
                    {(["all", "none", "reset"] as const).map((selection) => (
                            <button key={selection} type="button" className="map-groups__control"
                                    onClick={() => onSelect(selection)}>{selection}</button>
                    ))}
                </div>
                <ul className="map-groups__list" aria-label="Entity groups">
                    {legend.map((entry) => (
                            <GroupRow key={entry.group.id} entry={entry} shown={shown} onChange={onChange}
                                      onHighlight={onHighlight}/>
                    ))}
                    {setPieces && (
                            <GroupRow entry={setPieces} shown={shownSetPieces} onChange={onSetPiecesChange} outlined/>
                    )}
                    {links && (
                            <li>
                                <div className="map-group">
                                    <label className="map-group__toggle">
                                        <input type="checkbox" checked={links.shown}
                                               onChange={(event) => links.onChange(event.target.checked)}/>
                                        <span className="map__swatch" style={{ background: `rgb(${links.colour.join()})` }}/>
                                        <span>{links.label}</span>
                                    </label>
                                </div>
                            </li>
                    )}
                    {roads && (
                            <li>
                                <div className="map-group">
                                    <label className="map-group__toggle">
                                        <input type="checkbox" checked={roads.shown}
                                               onChange={(event) => roads.onChange(event.target.checked)}/>
                                        <span className="map__swatch" style={{ background: `rgb(${ROAD_SWATCH.join()})` }}/>
                                        <span>Roads</span>
                                    </label>
                                </div>
                            </li>
                    )}
                </ul>
            </details>
    );
}
