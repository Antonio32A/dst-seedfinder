let keyCounter = 0;

/** Returns a unique key for list items created in this session. */
export function newKey(): string {
  keyCounter += 1;
  return `k${keyCounter}-${Math.random().toString(36).slice(2, 8)}`;
}

/** Rounds and clamps a number into [lo, hi]; lo wins when hi < lo. */
export function clamp(value: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, Math.round(value)));
}

/** An untrusted value as a plain object, or `{}` when it isn't one. */
export function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

/** An untrusted value as a list, or `[]` when it isn't one. */
export function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

/** The strings of an untrusted list. */
export function asStrings(value: unknown): string[] {
  return asArray(value).filter((item): item is string => typeof item === "string");
}
