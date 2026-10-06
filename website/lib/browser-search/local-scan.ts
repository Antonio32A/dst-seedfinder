import { type SearchHit, type SearchOutput, SEED_SPACE, type StopReason } from "@/lib/jobs/job-result";
import { scanPosition } from "@/lib/jobs/runner-output";
import type { SpeedCounts } from "@/lib/jobs/search-speed";
import { type SearchTimings, sumTimings } from "@/lib/jobs/search-timings";

const FIRST_CHUNK = 64;
const MIN_CHUNK = 16;
const MAX_CHUNK = 1 << 24;
const MAX_GROWTH = 8;
const TARGET_CHUNK_MS = 5000;

/** `prefiltered` and `generated` count the seeds whose level table was checked and the worlds generated. */
export interface Chunk {
    position: number;
    from: number;
    to: number;
    scanned: number;
    prefiltered: number;
    generated: number;
    timings: SearchTimings | null;
    hits: SearchHit[];
    finished: boolean;
}

/**
 * Seeds are decided up to the first unfinished chunk's progress; the search is done once that decided prefix holds
 * `wanted` hits or covers every seed.
 */
export class LocalScan {
    private readonly chunks: Chunk[] = [];
    private claimed = 0;
    private chunkSize = FIRST_CHUNK;

    constructor(
        readonly startSeed: number,
        readonly wanted: number
    ) {
    }

    claim(): Chunk | null {
        if (this.claimed >= SEED_SPACE) return null;
        const from = (this.startSeed + this.claimed) % SEED_SPACE;
        const size = Math.min(this.chunkSize, SEED_SPACE - this.claimed, SEED_SPACE - from);
        const chunk: Chunk = {
            position: this.claimed,
            from,
            to: from + size - 1,
            scanned: 0,
            prefiltered: 0,
            generated: 0,
            timings: null,
            hits: [],
            finished: false
        };
        this.chunks.push(chunk);
        this.claimed += size;
        return chunk;
    }

    finish(chunk: Chunk, scanned: number, elapsedMs: number): void {
        chunk.scanned = scanned;
        chunk.prefiltered = Math.max(chunk.prefiltered, scanned);
        chunk.finished = true;
        if (scanned <= 0 || elapsedMs <= 0) return;
        const fitted = Math.round((scanned * TARGET_CHUNK_MS) / elapsedMs);
        this.chunkSize = Math.max(MIN_CHUNK, Math.min(fitted, this.chunkSize * MAX_GROWTH, MAX_CHUNK));
    }

    counts(): SpeedCounts {
        return this.chunks.reduce((total, chunk) => ({
            prefiltered: total.prefiltered + chunk.prefiltered,
            generated: total.generated + chunk.generated,
            decided: total.decided + chunk.scanned
        }), { prefiltered: 0, generated: 0, decided: 0 });
    }

    timings(): SearchTimings | null {
        return sumTimings(this.chunks.flatMap((chunk) => (chunk.timings ? [chunk.timings] : [])));
    }

    stopReason(): StopReason | null {
        const { hits, scanned } = this.decided();
        if (hits.length >= this.wanted) return "limit";
        return scanned >= SEED_SPACE ? "end" : null;
    }

    output(): SearchOutput {
        const decided = this.decided();
        const reason = this.stopReason();
        if (reason === "limit") {
            const hits = decided.hits.slice(0, this.wanted);
            const last = hits[hits.length - 1].seed;
            const position = (last - this.startSeed + SEED_SPACE) % SEED_SPACE;
            return { hits, ...scanPosition(this.startSeed, position + 1), stopped: reason };
        }
        const hits = this.chunks.flatMap((chunk) => chunk.hits);
        return { hits, ...scanPosition(this.startSeed, decided.scanned), ...(reason ? { stopped: reason } : {}) };
    }

    private decided(): { hits: SearchHit[]; scanned: number } {
        const unfinished = this.chunks.findIndex((chunk) => !chunk.finished);
        const prefix = unfinished === -1 ? this.chunks : this.chunks.slice(0, unfinished + 1);
        return {
            hits: prefix.flatMap((chunk) => chunk.hits),
            scanned: prefix.reduce((total, chunk) => total + chunk.scanned, 0)
        };
    }
}
