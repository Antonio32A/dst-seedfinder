/** Seeds per second through the level-table prefilter, worlds generated per second and seeds decided per second. */
export interface Rates {
    prefilter: number;
    generation: number;
    total: number;
}

/** `recent` covers the last `SPEED_WINDOW_MS`, `full` the whole run. */
export interface SearchSpeeds {
    recent: Rates;
    full: Rates;
}

export interface SpeedCounts {
    prefiltered: number;
    generated: number;
    decided: number;
}

export const SPEED_WINDOW_MS = 30_000;

const RATE = String.raw`(\d+(?:\.\d+)?)`;
const RATES = `${RATE}/${RATE}/${RATE}`;
const SPEED_LINE = new RegExp(`^speed 30s: ${RATES} full: ${RATES}$`);

const rates = (prefilter: string, generation: string, total: string): Rates => ({
    prefilter: Number(prefilter),
    generation: Number(generation),
    total: Number(total)
});

/** The finder's `speed 30s: P/G/T full: P/G/T` line. */
export function parseSpeedLine(line: string): SearchSpeeds | null {
    const match = line.match(SPEED_LINE);
    if (!match) return null;
    const [, p30, g30, t30, pFull, gFull, tFull] = match;
    return { recent: rates(p30, g30, t30), full: rates(pFull, gFull, tFull) };
}

const perSecond = (from: SpeedCounts, to: SpeedCounts, ms: number): Rates => {
    const seconds = Math.max(ms, 1) / 1000;
    return {
        prefilter: (to.prefiltered - from.prefiltered) / seconds,
        generation: (to.generated - from.generated) / seconds,
        total: (to.decided - from.decided) / seconds
    };
};

const NOTHING: SpeedCounts = { prefiltered: 0, generated: 0, decided: 0 };

/**
 * The speeds of a search whose counts are sampled as it runs, the way the finder computes its speed line: the window
 * starts at the newest sample at or before `SPEED_WINDOW_MS` ago (the run's start while it is younger).
 */
export class SpeedMeter {
    private samples: { at: number; counts: SpeedCounts }[];

    constructor(readonly startedAt: number) {
        this.samples = [{ at: startedAt, counts: NOTHING }];
    }

    record(at: number, counts: SpeedCounts): void {
        const since = at - SPEED_WINDOW_MS;
        const kept = [...this.samples, { at, counts }];
        const first = kept.findLastIndex((sample) => sample.at <= since);
        this.samples = kept.slice(Math.max(first, 0));
    }

    speeds(): SearchSpeeds {
        const oldest = this.samples[0];
        const newest = this.samples[this.samples.length - 1];
        return {
            recent: perSecond(oldest.counts, newest.counts, newest.at - oldest.at),
            full: perSecond(NOTHING, newest.counts, newest.at - this.startedAt)
        };
    }
}
