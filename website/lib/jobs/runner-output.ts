import type { Platform } from "@/lib/config/seedfinder-config";
import type { JobProgress } from "./job-events";
import { type SearchHit, SEED_SPACE, type StopReason } from "./job-result";

export const MAX_CHUNK_BYTES = 256 * 1024;
export const MAX_LINE_BYTES = 64 * 1024;
export const MAX_OUTPUT_BYTES = 16 * 1024 * 1024;

export interface DoneSummary {
    scanned: number;
    last_scanned: number | null;
    next_seed: number | null;
    stopped: StopReason;
}

export type OutputLine =
    | { kind: "progress"; progress: Omit<JobProgress, "seedsPerSecond"> & { seedsPerSecond: number | null } }
    | { kind: "hit"; hit: SearchHit }
    | { kind: "done"; summary: DoneSummary }
    | { kind: "error"; error: string };

/** The finder's job object (`--json`, § 8 of the search spec), assembled from line mode. */
export interface JobObject extends DoneSummary {
    version: 1;
    platform: Platform;
    hits: SearchHit[];
}

export type ChunkPlacement = { kind: "gap"; expected: number } | { kind: "append"; skip: number };

/** The unterminated end of the output so far; `skipping` while the line it belongs to is too long to keep. */
export interface LineTail {
    bytes: Uint8Array;
    skipping: boolean;
}

/** How a finished runner's search ended, from its exit code and what it printed. */
export type ExitKind = "done" | "config-error" | "crash";

const PROGRESS_LINE = /^scanned (\d+)\/\d+ matches (\d+) \((\d+) seeds\/s\)$/;
const WORLDGEN_PROGRESS_LINE = /^search: scanned (\d+), (?:levels \d+, )?worlds (\d+), generating (\d+)\b.*\bhits (\d+)\b/;
const HIT_LINE = /^(\d+) (\{.*\})$/;
const DONE_LINE = /^done (\{.*\})$/;
const CONFIG_ERROR_LINE = /^config: (.*)$/;
const ERROR_OBJECT_LINE = /^\{.*"error".*\}$/;

const asObject = (text: string): Record<string, unknown> | null => {
    try {
        const value: unknown = JSON.parse(text);
        return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
    } catch {
        return null;
    }
};

type LineParser = (match: RegExpMatchArray) => OutputLine | null;

const LINE_PARSERS: [RegExp, LineParser][] = [
    [
        PROGRESS_LINE,
        ([, scanned, hits, rate]) => ({
            kind: "progress",
            progress: { scanned: Number(scanned), hits: Number(hits), seedsPerSecond: Number(rate) }
        })
    ],
    [
        WORLDGEN_PROGRESS_LINE,
        ([, scanned, generated, generating, hits]) => ({
            kind: "progress",
            progress: {
                scanned: Number(scanned),
                hits: Number(hits),
                seedsPerSecond: null,
                worlds: { generated: Number(generated), generating: Number(generating) }
            }
        })
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

/** What one line of the runner's merged stdout/stderr means, or `null` for anything the site ignores. */
export function parseOutputLine(line: string): OutputLine | null {
    const trimmed = line.replace(/\r$/, "");
    for (const [pattern, parse] of LINE_PARSERS) {
        const match = trimmed.match(pattern);
        if (match) return parse(match);
    }
    return null;
}

/**
 * Splits newly arrived bytes (after the unterminated tail of the previous chunks) into whole lines and a new tail. Lines
 * longer than `MAX_LINE_BYTES` are dropped, and an unterminated one that grows past it is discarded as it arrives.
 */
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

/** The runner's `X-Exit` header as an exit code, or `null` when it is missing or not an integer. */
export function parseExitHeader(header: string | null): number | null {
    const text = header?.trim() ?? "";
    return /^-?\d{1,10}$/.test(text) ? Number(text) : null;
}

/**
 * How a search ended: `done` when the finder exited 0 (hits) or 1 (no hits) after printing its `done` summary, a
 * config error on exit 2 after a config error line, and a crash otherwise.
 */
export function exitKind(exit: number, summary: DoneSummary | null, configError: string | null): ExitKind {
    const finished = (exit === 0 || exit === 1) && summary !== null;
    const rejected = exit === 2 && configError !== null;
    return finished ? "done" : rejected ? "config-error" : "crash";
}

/**
 * Where a chunk POSTed at `offset` fits given `received` bytes so far: a gap when it starts past the end, otherwise how
 * many of its leading bytes are already stored (resends are harmless).
 */
export function placeChunk(received: number, offset: number): ChunkPlacement {
    return offset > received ? { kind: "gap", expected: received } : { kind: "append", skip: received - offset };
}

/** The scan position after `scanned` seeds from `start`, the way the finder reports it (§ 8). */
export function scanPosition(start: number, scanned: number): Omit<DoneSummary, "stopped"> {
    const next = (start + scanned) % SEED_SPACE;
    return {
        scanned,
        last_scanned: scanned === 0 ? null : (next - 1 + SEED_SPACE) % SEED_SPACE,
        next_seed: scanned >= SEED_SPACE ? null : next
    };
}

/**
 * The job object for a search: the done line's summary when the finder printed one, otherwise (cancelled, dead, over
 * time) the position of the latest progress line with `stopped: "time"`, so a follow-up search can continue from it.
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
    return { version: 1, platform, hits, ...position };
}
