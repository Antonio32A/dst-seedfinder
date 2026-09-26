let keyCounter = 0;

export function newKey(): string {
    keyCounter += 1;
    return `k${keyCounter}-${Math.random().toString(36).slice(2, 8)}`;
}

/** Also rounds; `lo` wins when `hi < lo`. */
export function clamp(value: number, lo: number, hi: number): number {
    return Math.max(lo, Math.min(hi, Math.round(value)));
}

export function asRecord(value: unknown): Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

export function asArray(value: unknown): unknown[] {
    return Array.isArray(value) ? value : [];
}

export function asStrings(value: unknown): string[] {
    return asArray(value).filter((item): item is string => typeof item === "string");
}
