let keyCounter = 0;

export function newKey(): string {
    keyCounter += 1;
    return `k${keyCounter}-${Math.random().toString(36).slice(2, 8)}`;
}

/** Also rounds; `lo` wins when `hi < lo`. */
export function clamp(value: number, lo: number, hi: number): number {
    return Math.max(lo, Math.min(hi, Math.round(value)));
}

export function asArray(value: unknown): unknown[] {
    return Array.isArray(value) ? value : [];
}

export function asStrings(value: unknown): string[] {
    return asArray(value).filter((item): item is string => typeof item === "string");
}

export function nonEmpty<T>(items: T[]): T[] | undefined {
    return items.length > 0 ? items : undefined;
}

export function replaceByKey<T extends { key: string }>(items: T[], changed: T): T[] {
    return items.map((item) => (item.key === changed.key ? changed : item));
}

export function withoutKey<T extends { key: string }>(items: T[], key: string): T[] {
    return items.filter((item) => item.key !== key);
}

export function toggled<T>(items: T[], item: T, on: boolean): T[] {
    return on ? [...items, item] : items.filter((other) => other !== item);
}

/** `undefined` removes the entry. */
export function withEntry<T extends object, K extends keyof T>(record: T, key: K, value: T[K] | undefined): T {
    const { [key]: _removed, ...rest } = record;
    return (value === undefined ? rest : { ...rest, [key]: value }) as T;
}
