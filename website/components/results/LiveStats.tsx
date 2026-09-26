import { Fragment } from "react";

export interface LiveRow {
    label: string;
    value: string;
    note?: string;
}

export function checkedNote(generatesWorlds: boolean): string {
    return generatesWorlds
            ? "total seeds, most are ruled out by biomes, resources and set pieces"
            : "total seeds, all decided by biomes, resources and set pieces";
}

export default function LiveStats({ rows }: { rows: LiveRow[] }) {
    return (
            <dl className="live__stats">
                {rows.map(({ label, value, note }) => (
                        <Fragment key={label}>
                            <dt>{label}</dt>
                            <dd>
                                {value}
                                {note && <span className="muted"> - {note}</span>}
                            </dd>
                        </Fragment>
                ))}
            </dl>
    );
}
