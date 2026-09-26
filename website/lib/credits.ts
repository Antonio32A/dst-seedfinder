const UNITS_PER_CREDIT = 100;
const CREDITS_PER_DOLLAR_HOUR_SECOND = 40;

export const MAX_DOLLARS_PER_HOUR = 0.5;
export const DAILY_CREDITS = 1000;
export const DEFAULT_MAX_COST = 100;
export const MIN_MAX_COST = 20;
export const MAX_MAX_COST = 1_000_000;
export const MAX_COST_OPTIONS = [50, 100, 250, 500, 1000];
export const STARTING_FEE = 10;
export const MAX_SEARCH_SECONDS = 4 * 60 * 60;

const SECONDS = new Intl.NumberFormat("en", { maximumFractionDigits: 1 });

/** Credits (a decimal with at most 2 places) as the integer hundredths D1 stores. */
export function creditsToUnits(credits: number): number {
    return Math.round(credits * UNITS_PER_CREDIT);
}

/** Integer hundredths of a credit back to decimal credits. */
export function unitsToCredits(units: number): number {
    return units / UNITS_PER_CREDIT;
}

/** Rounds to the nearest hundredth of a credit. */
export function roundCredits(credits: number): number {
    return unitsToCredits(creditsToUnits(credits));
}

/** Credits one second of search costs on a machine at this price ($/h). */
export function creditsPerSecond(dollarsPerHour: number): number {
    return CREDITS_PER_DOLLAR_HOUR_SECOND * dollarsPerHour;
}

/** The search time a number of credits buys on a machine at this price ($/h), in seconds. */
export function creditsToSeconds(credits: number, dollarsPerHour: number = MAX_DOLLARS_PER_HOUR): number {
    return credits / creditsPerSecond(dollarsPerHour);
}

/**
 * A search's time limit on a machine at this price ($/h), in seconds: what its max cost buys after the starting fee,
 * but never more than `MAX_SEARCH_SECONDS`.
 */
export function timeLimitSeconds(maxCost: number, dollarsPerHour: number): number {
    return Math.min(MAX_SEARCH_SECONDS, creditsToSeconds(maxCost - STARTING_FEE, dollarsPerHour));
}

/** A search time for display in its two largest units: "9.6 s", "12 min 30 s", "4 h", "1 h 5 min". */
export function formatDuration(seconds: number): string {
    if (seconds < 60) return `${SECONDS.format(seconds)} s`;
    const [unit, unitSeconds, smallUnit, smallUnitSeconds] = seconds < 3600 ? (["min", 60, "s", 1] as const) : (["h", 3600, "min", 60] as const);
    const large = Math.floor(seconds / unitSeconds);
    const small = Math.floor((seconds % unitSeconds) / smallUnitSeconds);
    return small === 0 ? `${large} ${unit}` : `${large} ${unit} ${small} ${smallUnit}`;
}

/** Whether a number has no more than 2 decimal places (tolerating binary float noise). */
export function hasAtMostTwoDecimals(value: number): boolean {
    return Math.abs(value * UNITS_PER_CREDIT - creditsToUnits(value)) < 1e-6;
}

/** Whether a value is an acceptable max cost: a finite number of credits, 2 decimals at most, within the limits. */
export function isValidMaxCost(value: unknown): value is number {
    return (
        typeof value === "number" &&
        Number.isFinite(value) &&
        hasAtMostTwoDecimals(value) &&
        value >= MIN_MAX_COST &&
        value <= MAX_MAX_COST
    );
}

/** Credits for display: whole numbers as is, anything else with exactly 2 decimals ("1000", "987.30"). */
export function formatCredits(credits: number): string {
    const rounded = roundCredits(credits);
    return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2);
}

/**
 * What a finished search costs, in hundredths: its search time at the machine's price, rounded up and capped at the
 * reservation. A negative or non-finite time charges the full reservation.
 */
export function searchCostUnits(reservedUnits: number, searchMs: number, dollarsPerHour: number): number {
    const valid = Number.isFinite(searchMs) && searchMs >= 0;
    const units = (searchMs / 1000) * creditsPerSecond(dollarsPerHour) * UNITS_PER_CREDIT;
    return valid ? Math.min(reservedUnits, Math.max(0, Math.ceil(units - 1e-9))) : reservedUnits;
}

/**
 * What a search is charged, in hundredths: the starting fee when an instance was rented for it, plus its search time
 * (`searchMs`, null when it never started), capped at the reservation.
 */
export function chargeUnits(reservedUnits: number, feeCharged: boolean, searchMs: number | null, dollarsPerHour: number): number {
    const fee = feeCharged ? creditsToUnits(STARTING_FEE) : 0;
    const search = searchMs === null ? 0 : searchCostUnits(reservedUnits, searchMs, dollarsPerHour);
    return Math.min(reservedUnits, fee + search);
}
