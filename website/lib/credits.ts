const MS_PER_CREDIT = 100;
const UNITS_PER_CREDIT = 100;
const MS_PER_UNIT = MS_PER_CREDIT / UNITS_PER_CREDIT;

export const DAILY_CREDITS = 1000;
export const DEFAULT_MAX_COST = 100;
export const MIN_MAX_COST = 1;
export const MAX_MAX_COST = 1000;
export const MAX_COST_OPTIONS = [50, 100, 250, 500, 1000];

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

/** The compute time a number of credits buys, in seconds. */
export function creditsToSeconds(credits: number): number {
  return (creditsToUnits(credits) * MS_PER_UNIT) / 1000;
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
 * What a finished search really costs, in hundredths: its compute time at 1 unit per ms, capped at the reservation.
 * A missing or nonsensical execution time charges the full reservation.
 */
export function settledCostUnits(reservedUnits: number, executionMs: unknown): number {
  const valid = typeof executionMs === "number" && Number.isFinite(executionMs) && executionMs >= 0;
  return valid ? Math.min(reservedUnits, Math.ceil(executionMs / MS_PER_UNIT)) : reservedUnits;
}
