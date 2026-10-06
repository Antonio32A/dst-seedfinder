import { asRecord, isRecord } from "@/lib/records";

/** One world rule of an option, labelled like its witness (`section`, `index`). */
export interface RuleTiming {
    section: string;
    index: number;
    ms: number;
}

/**
 * One option (criteria entry): the ms its level table took over every prefiltered seed and how many seeds passed it,
 * then the worlds its rules were checked on and the ms of each rule.
 */
export interface OptionTiming {
    prefilter_ms: number;
    passed: number;
    worlds: number;
    rules: RuleTiming[];
}

/**
 * The finder's `timings {...}` line (`world find --verbose-timings`), summed over the runs of a search: `seeds` is how
 * many seeds every option's level table went over, `hits_ms` the time spent on the found seeds' witnesses.
 */
export interface SearchTimings {
    elapsed_ms: number;
    seeds: number;
    prefilter_ms: number;
    generation_ms: number;
    hits_ms: number;
    options: OptionTiming[];
}

const TIMINGS_LINE = /^timings (\{.*\})$/;

const count = (value: unknown): number => (typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0);

const listOf = <T>(value: unknown, item: (raw: unknown) => T): T[] => (Array.isArray(value) ? value.map(item) : []);

const rule = (raw: unknown): RuleTiming => {
    const fields = asRecord(raw);
    const section = typeof fields.section === "string" ? fields.section : "";
    return { section, index: count(fields.index), ms: count(fields.ms) };
};

const option = (raw: unknown): OptionTiming => {
    const fields = asRecord(raw);
    return {
        prefilter_ms: count(fields.prefilter_ms),
        passed: count(fields.passed),
        worlds: count(fields.worlds),
        rules: listOf(fields.rules, rule)
    };
};

/** Never throws; `null` when the value isn't a timings object. */
export function parseTimings(value: unknown): SearchTimings | null {
    if (!isRecord(value) || !Array.isArray(value.options)) return null;
    return {
        elapsed_ms: count(value.elapsed_ms),
        seeds: count(value.seeds),
        prefilter_ms: count(value.prefilter_ms),
        generation_ms: count(value.generation_ms),
        hits_ms: count(value.hits_ms),
        options: listOf(value.options, option)
    };
}

export function parseTimingsLine(line: string): SearchTimings | null {
    const body = line.match(TIMINGS_LINE)?.[1];
    if (body === undefined) return null;
    try {
        return parseTimings(JSON.parse(body));
    } catch {
        return null;
    }
}

const addRules = (a: RuleTiming[], b: RuleTiming[]): RuleTiming[] =>
    (a.length >= b.length ? a : b).map((longer, index) => ({
        ...longer,
        ms: (a[index]?.ms ?? 0) + (b[index]?.ms ?? 0)
    }));

const addOptions = (a: OptionTiming[], b: OptionTiming[]): OptionTiming[] =>
    (a.length >= b.length ? a : b).map((_, index) => ({
        prefilter_ms: (a[index]?.prefilter_ms ?? 0) + (b[index]?.prefilter_ms ?? 0),
        passed: (a[index]?.passed ?? 0) + (b[index]?.passed ?? 0),
        worlds: (a[index]?.worlds ?? 0) + (b[index]?.worlds ?? 0),
        rules: addRules(a[index]?.rules ?? [], b[index]?.rules ?? [])
    }));

/** The timings of runs that searched side by side (the browser's workers), added up. */
export function sumTimings(all: SearchTimings[]): SearchTimings | null {
    if (all.length === 0) return null;
    return all.reduce((total, next) => ({
        elapsed_ms: total.elapsed_ms + next.elapsed_ms,
        seeds: total.seeds + next.seeds,
        prefilter_ms: total.prefilter_ms + next.prefilter_ms,
        generation_ms: total.generation_ms + next.generation_ms,
        hits_ms: total.hits_ms + next.hits_ms,
        options: addOptions(total.options, next.options)
    }));
}

/** The threads' summed times as shares of `elapsedMs`, the real time they ran side by side for. */
export function inRealTime(timings: SearchTimings, elapsedMs: number): SearchTimings {
    if (timings.elapsed_ms <= 0) return timings;
    const scale = (ms: number) => Math.round((ms * elapsedMs) / timings.elapsed_ms);
    return {
        ...timings,
        elapsed_ms: Math.round(elapsedMs),
        prefilter_ms: scale(timings.prefilter_ms),
        generation_ms: scale(timings.generation_ms),
        hits_ms: scale(timings.hits_ms),
        options: timings.options.map((option) => ({
            ...option,
            prefilter_ms: scale(option.prefilter_ms),
            rules: option.rules.map((rule) => ({ ...rule, ms: scale(rule.ms) }))
        }))
    };
}

/** The ms an option spent on its rules. */
export const rulesMs = (timing: OptionTiming): number => timing.rules.reduce((total, { ms }) => total + ms, 0);
