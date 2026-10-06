import type { Platform } from "@/lib/config/seedfinder-config";
import { isRecord } from "@/lib/records";
import type { JobProgress } from "./job-events";
import { type SearchHit, SEED_SPACE, type StopReason } from "./job-result";
import { parseSpeedLine, type SearchSpeeds } from "./search-speed";
import { parseTimingsLine, type SearchTimings } from "./search-timings";

export const MAX_CHUNK_BYTES = 256 * 1024;
export const MAX_LINE_BYTES = 64 * 1024;
export const MAX_OUTPUT_BYTES = 16 * 1024 * 1024;

export interface DoneSummary {
    scanned: number;
    last_scanned: number | null;
    next_seed: number | null;
    stopped: StopReason;
}

/** `prefiltered`: the seeds whose level table was checked. */
export type ProgressLine = Pick<JobProgress, "scanned" | "hits" | "worlds"> & { prefiltered: number };

export type OutputLine =
    | { kind: "progress"; progress: ProgressLine }
    | { kind: "speed"; speeds: SearchSpeeds }
    | { kind: "timings"; timings: SearchTimings }
    | { kind: "hit"; hit: SearchHit }
    | { kind: "done"; summary: DoneSummary }
    | { kind: "error"; error: string };

export interface JobObject extends DoneSummary {
    version: 1;
    platform: Platform;
    hits: SearchHit[];
    timings?: SearchTimings;
}

/** `skipping` while the current line is too long to keep. */
export interface LineTail {
    bytes: Uint8Array;
    skipping: boolean;
}

export type ExitKind = "done" | "config-error" | "crash";

const PROGRESS_LINE = /^scanned (\d+)\/\d+ matches (\d+) \(\d+ seeds\/s\)$/;
const WORLDGEN_PROGRESS_LINE = /^search: scanned (\d+), (?:levels (\d+), )?worlds (\d+), generating (\d+)\b.*\bhits (\d+)\b/;
const SPEED_LINE = /^speed /;
const TIMINGS_LINE = /^timings /;
const HIT_LINE = /^(\d+) (\{.*\})$/;
const DONE_LINE = /^done (\{.*\})$/;
const CONFIG_ERROR_LINE = /^config: (.*)$/;
const ERROR_OBJECT_LINE = /^\{.*"error".*\}$/;

const asObject = (text: string): Record<string, unknown> | null => {
    try {
        const value: unknown = JSON.parse(text);
        return isRecord(value) ? value : null;
    } catch {
        return null;
    }
};

type LineParser = (match: RegExpMatchArray) => OutputLine | null;

const LINE_PARSERS: [RegExp, LineParser][] = [
    [
        PROGRESS_LINE,
        ([, scanned, hits]) => ({
            kind: "progress",
            progress: { scanned: Number(scanned), hits: Number(hits), prefiltered: Number(scanned) }
        })
    ],
    [
        WORLDGEN_PROGRESS_LINE,
        ([, scanned, levels, generated, generating, hits]) => ({
            kind: "progress",
            progress: {
                scanned: Number(scanned),
                hits: Number(hits),
                prefiltered: Number((levels as string | undefined) ?? scanned),
                worlds: { generated: Number(generated), generating: Number(generating) }
            }
        })
    ],
    [
        SPEED_LINE,
        ({ input }) => {
            const speeds = parseSpeedLine(input ?? "");
            return speeds && { kind: "speed", speeds };
        }
    ],
    [
        TIMINGS_LINE,
        ({ input }) => {
            const timings = parseTimingsLine(input ?? "");
            return timings && { kind: "timings", timings };
        }
    ],
    [
        HIT_LINE,
        ([, seed, body]) => {
            const fields = asObject(body);
            if (fields === null || Number(seed) >= SEED_SPACE) return null;
            const { world: _world, ...hit } = fields;
            return { kind: "hit", hit: { ...hit, seed: Number(seed) } as unknown as SearchHit };
        }
    ],
    [
        DONE_LINE,
        ([, body]) => {
            const fields = asObject(body);
            if (fields === null) return null;
            const { hits: _hits, ...summary } = fields;
            return { kind: "done", summary: summary as unknown as DoneSummary };
        }
    ],
    [CONFIG_ERROR_LINE, ([line]) => ({ kind: "error", error: line })],
    [
        ERROR_OBJECT_LINE,
        ([line]) => {
            const error = asObject(line)?.error;
            return typeof error === "string" ? { kind: "error", error } : null;
        }
    ]
];

export function parseOutputLine(line: string): OutputLine | null {
    const trimmed = line.replace(/\r$/, "");
    for (const [pattern, parse] of LINE_PARSERS) {
        const match = trimmed.match(pattern);
        if (match) return parse(match);
    }
    return null;
}

export function splitLines(tail: LineTail, bytes: Uint8Array): { lines: string[]; tail: LineTail } {
    const joined = new Uint8Array(tail.bytes.length + bytes.length);
    joined.set(tail.bytes);
    joined.set(bytes, tail.bytes.length);
    const decoder = new TextDecoder();
    const lines: string[] = [];
    let skipping = tail.skipping;
    let start = 0;
    for (let end = joined.indexOf(0x0a); end !== -1; end = joined.indexOf(0x0a, start)) {
        if (!skipping && end - start <= MAX_LINE_BYTES) lines.push(decoder.decode(joined.subarray(start, end)));
        skipping = false;
        start = end + 1;
    }
    const rest = joined.subarray(start);
    const overlong = skipping || rest.length > MAX_LINE_BYTES;
    return { lines, tail: { bytes: overlong ? new Uint8Array() : rest.slice(), skipping: overlong } };
}

export function parseExitHeader(header: string | null): number | null {
    const text = header?.trim() ?? "";
    return /^-?\d{1,10}$/.test(text) ? Number(text) : null;
}

/** The finder exits 0 with hits, 1 without and 2 on a config error. */
export function exitKind(exit: number, summary: DoneSummary | null, configError: string | null): ExitKind {
    const finished = (exit === 0 || exit === 1) && summary !== null;
    const rejected = exit === 2 && configError !== null;
    return finished ? "done" : rejected ? "config-error" : "crash";
}

export function scanPosition(start: number, scanned: number): Omit<DoneSummary, "stopped"> {
    const next = (start + scanned) % SEED_SPACE;
    return {
        scanned,
        last_scanned: scanned === 0 ? null : (next - 1 + SEED_SPACE) % SEED_SPACE,
        next_seed: scanned >= SEED_SPACE ? null : next
    };
}

/**
 * Without a done summary (cancelled, dead or out of time), the latest progress becomes `stopped: "time"` so a follow-up
 * search can continue from it. The latest progress's timings are kept.
 */
export function jobObject(
    platform: Platform,
    hits: SearchHit[],
    summary: DoneSummary | null,
    fallback: { startSeed: number; progress: JobProgress | null }
): JobObject {
    const position = summary ?? {
        ...scanPosition(fallback.startSeed, fallback.progress?.scanned ?? 0),
        stopped: "time" as const
    };
    const timings = fallback.progress?.timings;
    return { version: 1, platform, hits, ...position, ...(timings ? { timings } : {}) };
}
