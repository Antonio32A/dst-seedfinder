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

/** D1 stores credits as integer hundredths. */
export function creditsToUnits(credits: number): number {
    return Math.round(credits * UNITS_PER_CREDIT);
}

export function unitsToCredits(units: number): number {
    return units / UNITS_PER_CREDIT;
}

export function roundCredits(credits: number): number {
    return unitsToCredits(creditsToUnits(credits));
}

export function creditsPerSecond(dollarsPerHour: number): number {
    return CREDITS_PER_DOLLAR_HOUR_SECOND * dollarsPerHour;
}

export function creditsToSeconds(credits: number, dollarsPerHour: number = MAX_DOLLARS_PER_HOUR): number {
    return credits / creditsPerSecond(dollarsPerHour);
}

export function timeLimitSeconds(maxCost: number, dollarsPerHour: number): number {
    return Math.min(MAX_SEARCH_SECONDS, creditsToSeconds(maxCost - STARTING_FEE, dollarsPerHour));
}

export function formatDuration(seconds: number): string {
    if (seconds < 60) return `${SECONDS.format(seconds)} s`;
    const [unit, unitSeconds, smallUnit, smallUnitSeconds] = seconds < 3600 ? (["min", 60, "s", 1] as const) : (["h", 3600, "min", 60] as const);
    const large = Math.floor(seconds / unitSeconds);
    const small = Math.floor((seconds % unitSeconds) / smallUnitSeconds);
    return small === 0 ? `${large} ${unit}` : `${large} ${unit} ${small} ${smallUnit}`;
}

export function hasAtMostTwoDecimals(value: number): boolean {
    return Math.abs(value * UNITS_PER_CREDIT - creditsToUnits(value)) < 1e-6;
}

export function isValidMaxCost(value: unknown): value is number {
    return (
        typeof value === "number" &&
        Number.isFinite(value) &&
        hasAtMostTwoDecimals(value) &&
        value >= MIN_MAX_COST &&
        value <= MAX_MAX_COST
    );
}

export function formatCredits(credits: number): string {
    const rounded = roundCredits(credits);
    return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2);
}

export function searchCostUnits(reservedUnits: number, searchMs: number, dollarsPerHour: number): number {
    const valid = Number.isFinite(searchMs) && searchMs >= 0;
    const units = (searchMs / 1000) * creditsPerSecond(dollarsPerHour) * UNITS_PER_CREDIT;
    return valid ? Math.min(reservedUnits, Math.max(0, Math.ceil(units - 1e-9))) : reservedUnits;
}

export function chargeUnits(reservedUnits: number, feeCharged: boolean, searchMs: number | null, dollarsPerHour: number): number {
    const fee = feeCharged ? creditsToUnits(STARTING_FEE) : 0;
    const search = searchMs === null ? 0 : searchCostUnits(reservedUnits, searchMs, dollarsPerHour);
    return Math.min(reservedUnits, fee + search);
}
