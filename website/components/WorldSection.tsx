"use client";

import type { ReactNode } from "react";
import { MAX_RULES_PER_SECTION } from "@/lib/seedfinder-config";
import { MAP_SIZE_TILES, NEW_WORLD_ROW, type WorldRows, type WorldSection as Section } from "@/lib/world-rules";
import CountRuleRow from "./CountRuleRow";
import DistanceRuleRow from "./DistanceRuleRow";
import RouteRuleRow from "./RouteRuleRow";
import TileRuleRow from "./TileRuleRow";

interface RowProps<T> {
    row: T;
    index: number;
    onChange: (row: T) => void;
    onRemove: () => void;
}

type RowComponents = { [S in Section]: (props: RowProps<WorldRows[S][number]>) => ReactNode };

const ROWS: RowComponents = {
    counts: CountRuleRow,
    distances: DistanceRuleRow,
    tiles: TileRuleRow,
    routes: RouteRuleRow
};

const SECTIONS: { id: Section; title: string; add: string }[] = [
    { id: "counts", title: "Counts", add: "Add count" },
    { id: "distances", title: "Distances", add: "Add distance" },
    { id: "tiles", title: "Turf", add: "Add turf rule" },
    { id: "routes", title: "Routes", add: "Add route" }
];

interface WorldSectionProps {
    rows: WorldRows;
    onChange: (rows: Partial<WorldRows>) => void;
}

function RowList<S extends Section>({ section, rows, onChange }: {
    section: S;
    rows: WorldRows[S];
    onChange: (rows: WorldRows[S]) => void
}) {
    const Row = ROWS[section] as (props: RowProps<WorldRows[S][number]>) => ReactNode;
    const items = rows as WorldRows[S][number][];
    return (
            <ul className="row-list">
                {items.map((row, index) => (
                        <Row
                                key={row.key}
                                row={row}
                                index={index}
                                onChange={(changed) => onChange(items.map((item) => (item.key === changed.key ? changed : item)) as WorldRows[S])}
                                onRemove={() => onChange(items.filter((item) => item.key !== row.key) as WorldRows[S])}
                        />
                ))}
            </ul>
    );
}

export default function WorldSection({ rows, onChange }: WorldSectionProps) {
    const full = SECTIONS.filter(({ id }) => rows[id].length >= MAX_RULES_PER_SECTION);
    const add = (section: Section) => onChange({ [section]: [...rows[section], NEW_WORLD_ROW[section]()] });

    return (
            <div className="subsection world-area">
                <h4 className="subsection__title">
                    World details <span className="tag tag--accent">slow</span>
                </h4>
                <p className="muted small">
                    These need each seed&apos;s world generated, about a second of CPU time per seed, so far fewer seeds
                    are checked than with the other filters. Narrow the search with biomes, resources or set pieces
                    first. Distances are in tiles, and the map is about {MAP_SIZE_TILES} tiles across.
                </p>
                {SECTIONS.filter(({ id }) => rows[id].length > 0).map(({ id, title }) => (
                        <div key={id} className="world-area__section">
                            <h5 className="world-area__title">{title}</h5>
                            <RowList section={id} rows={rows[id]} onChange={(changed) => onChange({ [id]: changed })}/>
                        </div>
                ))}
                <p className="world-area__add">
                    {SECTIONS.map(({ id, add: label }) => (
                            <button key={id} type="button" className="link-button"
                                    disabled={rows[id].length >= MAX_RULES_PER_SECTION} onClick={() => add(id)}>
                                {label}
                            </button>
                    ))}
                </p>
                {full.length > 0 &&
                        <p className="hint">{full.map(({ title }) => title).join(", ")}: max {MAX_RULES_PER_SECTION} per
                            option.</p>}
            </div>
    );
}
