import { parseWitnesses, type Witness } from "@/lib/jobs/job-result";
import { asRecord } from "@/lib/records";

export interface WorldEval {
    matched: boolean;
    /** The first entry that holds, as on a search hit, else the first. */
    entry: number;
    entries: number;
    witnesses: Witness[];
}

const listed = (value: unknown) => (Array.isArray(value) ? (value as unknown[]) : []);

/** Reads the `SEED {json}` line of `world eval --json`, `null` for any other line. */
export function parseWorldEval(output: string): WorldEval | null {
    let fields: Record<string, unknown>;
    try {
        fields = asRecord(JSON.parse(output.slice(output.indexOf(" ") + 1)));
    } catch {
        return null;
    }
    if (typeof fields.match !== "boolean") return null;
    const entries = listed(fields.entries);
    const [first] = listed(fields.matched_entries);
    const entry = typeof first === "number" ? first : 0;
    return {
        matched: fields.match,
        entry,
        entries: entries.length,
        witnesses: parseWitnesses(asRecord(entries[entry]).results)
    };
}
