import { compileSeedfinder } from "@/lib/browser-search/seedfinder-wasm";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { mergeOdds, parseOddsLine, type PrefilterOdds, sampleRanges, sampleSize } from "./odds";
import type { OddsMessage, OddsRun } from "./odds-worker";

const PROGRESS_LINE = /^scanned (\d+)\/\d+ /;

export interface OddsRunHandle {
    result: Promise<PrefilterOdds>;
    cancel: () => void;
}

class Cancelled extends Error {
}

export const isCancelled = (error: unknown) => error instanceof Cancelled;

/**
 * Generates the level tables of the first `sampleSize` seeds of the config's shard on `threads` workers. `onProgress`
 * gets the share of the sample that is done, and the promise rejects with `isCancelled` errors once `cancel` is called.
 */
export function runPrefilterOdds(
    config: SeedfinderConfig,
    threads: number,
    onProgress: (done: number) => void
): OddsRunHandle {
    const workers: Worker[] = [];
    let cancel = () => {
    };
    const result = new Promise<PrefilterOdds>((resolve, reject) => {
        const text = JSON.stringify(config);
        const size = sampleSize(config.shard);
        const ranges = sampleRanges(size, threads);
        const parts: PrefilterOdds[] = [];
        const scanned = ranges.map(() => 0);
        let settled = false;

        const stop = (outcome: () => void) => {
            if (settled) return;
            settled = true;
            for (const worker of workers) worker.terminate();
            outcome();
        };
        cancel = () => stop(() => reject(new Cancelled()));
        const fail = (message: string) => stop(() => reject(new Error(message)));

        compileSeedfinder().then((module) => {
            if (settled) return;
            ranges.forEach((range, index) => {
                const worker = new Worker(new URL("./odds-worker.ts", import.meta.url), { type: "module" });
                workers.push(worker);
                let lastError: string | null = null;
                worker.onmessage = ({ data }: MessageEvent<OddsMessage>) => {
                    if (data.type === "line") {
                        const progress = PROGRESS_LINE.exec(data.line);
                        const odds = data.stderr ? null : parseOddsLine(data.line);
                        if (progress) {
                            scanned[index] = Number(progress[1]);
                            onProgress(scanned.reduce((total, count) => total + count, 0) / size);
                        } else if (odds) parts[index] = odds;
                        else if (data.stderr) lastError = data.line;
                        return;
                    }
                    if (data.code !== 0 || !parts[index]) return fail(lastError ?? data.error ?? `The seedfinder exited with code ${data.code}.`);
                    scanned[index] = range.to - range.from + 1;
                    if (parts.filter(Boolean).length === ranges.length) stop(() => resolve(mergeOdds(parts)));
                };
                worker.onerror = (event) => {
                    event.preventDefault();
                    fail("The seedfinder couldn't load in this browser.");
                };
                const run: OddsRun = { module, ...range, config: text };
                worker.postMessage(run);
            });
        }, (caught: unknown) => fail(`The seedfinder couldn't be downloaded: ${caught instanceof Error ? caught.message : String(caught)}`));
    });
    return { result, cancel: () => cancel() };
}
