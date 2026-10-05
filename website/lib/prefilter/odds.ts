import { DEFAULT_SHARD, type Shard } from "@/lib/config/seedfinder-config";
import { SEED_SPACE } from "@/lib/jobs/job-result";
import { isRecord } from "@/lib/records";

const SAMPLE_SEEDS: Record<Shard, number> = { forest: 10_000_000, caves: 1_000_000 };

export const sampleSize = (shard: Shard | undefined): number => SAMPLE_SEEDS[shard ?? DEFAULT_SHARD];

const COUNT_FORMAT = new Intl.NumberFormat("en");

/** How many of `seeds` seeds have each task and set piece, and how many pass the config's level-table filter. */
export interface PrefilterOdds {
    seeds: number;
    candidates: number;
    tasks: Record<string, number>;
    setpieces: Record<string, number>;
}

export interface SeedRange {
    from: number;
    to: number;
}

const ODDS_LINE = /^odds (\{.*\})$/;

const isCount = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

const counts = (value: unknown): Record<string, number> | null => {
    if (!isRecord(value)) return null;
    const entries = Object.entries(value);
    return entries.every(([, count]) => isCount(count)) ? Object.fromEntries(entries as [string, number][]) : null;
};

export function parseOddsLine(line: string): PrefilterOdds | null {
    const body = ODDS_LINE.exec(line)?.[1];
    if (body === undefined) return null;
    let fields: unknown;
    try {
        fields = JSON.parse(body);
    } catch {
        return null;
    }
    if (!isRecord(fields) || !isCount(fields.seeds) || !isCount(fields.candidates)) return null;
    const tasks = counts(fields.tasks);
    const setpieces = counts(fields.setpieces);
    return tasks && setpieces ? { seeds: fields.seeds, candidates: fields.candidates, tasks, setpieces } : null;
}

const sumByName = (parts: Record<string, number>[]): Record<string, number> => {
    const total: Record<string, number> = {};
    for (const part of parts) {
        for (const [name, count] of Object.entries(part)) total[name] = (total[name] ?? 0) + count;
    }
    return total;
};

export const mergeOdds = (parts: PrefilterOdds[]): PrefilterOdds => ({
    seeds: parts.reduce((total, part) => total + part.seeds, 0),
    candidates: parts.reduce((total, part) => total + part.candidates, 0),
    tasks: sumByName(parts.map((part) => part.tasks)),
    setpieces: sumByName(parts.map((part) => part.setpieces))
});

/** Splits the first `size` seeds into at most `slices` consecutive ranges of nearly the same size. */
export function sampleRanges(size: number, slices: number): SeedRange[] {
    const count = Math.min(Math.max(1, slices), size);
    return Array.from({ length: count }, (_, index) => ({
        from: Math.floor((index * size) / count),
        to: Math.floor(((index + 1) * size) / count) - 1
    }));
}

export const formatShare = (count: number, seeds: number): string => `${seeds > 0 ? ((count / seeds) * 100).toFixed(2) : "0.00"}%`;

/** The seed space's size, scaled up from the sample's share of candidates. */
export const estimateApplicableSeeds = ({ candidates, seeds }: Pick<PrefilterOdds, "candidates" | "seeds">): number =>
    seeds > 0 ? Math.round((candidates / seeds) * SEED_SPACE) : 0;

export const formatApplicableSeeds = (odds: Pick<PrefilterOdds, "candidates" | "seeds">): string =>
    `${COUNT_FORMAT.format(estimateApplicableSeeds(odds))} (${formatShare(odds.candidates, odds.seeds)})`;
