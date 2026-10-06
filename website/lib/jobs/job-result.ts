import type { SwapCategory } from "@/lib/catalog/level-types";
import { asRecord, isRecord } from "@/lib/records";
import { parseTimings, type SearchTimings } from "./search-timings";

export const SEED_SPACE = 2 ** 32;

export type StopReason = "limit" | "time" | "end";

export interface WitnessInstance {
    prefab: string;
    index: number;
    x: number;
    z: number;
}

export interface CountedInstance extends WitnessInstance {
    near?: WitnessInstance;
    distance?: number;
}

export interface WitnessTile {
    tx: number;
    ty: number;
    x: number;
    z: number;
}

/** A room of the world's topology: its node id, its `NODE_TYPE` and its centre in world units. */
export interface WitnessRoom {
    node: string;
    type: number;
    x: number;
    z: number;
}

/** A jump through a teleporter link: a wormhole in the forest, a tentacle pillar in the caves. */
export interface WormholeJump {
    entry: WitnessInstance;
    exit: WitnessInstance;
}

export interface RouteLeg {
    from: WitnessInstance;
    to: WitnessInstance;
    distance: number;
    wormholes: WormholeJump[];
}

interface WitnessBase {
    index: number;
    ok: boolean;
}

export interface CountsWitness extends WitnessBase {
    section: "counts";
    count: number;
    total?: number;
    instances: CountedInstance[];
}

export interface TilesWitness extends WitnessBase {
    section: "tiles";
    distance: number;
    from_tile?: WitnessTile;
    to_tile?: WitnessTile;
}

export interface DistancesWitness extends WitnessBase {
    section: "distances";
    distance: number | null;
    from?: WitnessInstance;
    to?: WitnessInstance;
    wormholes: WormholeJump[];
}

export interface BridgesWitness extends WitnessBase {
    section: "bridges";
    length: number | null;
    /** The room whose turf the bridge is made of. */
    from?: WitnessRoom;
    to?: WitnessRoom;
    /** The end left far from the rest of the map. */
    stray?: "from" | "to";
}

export interface RoutesWitness extends WitnessBase {
    section: "routes";
    length: number;
    stops: WitnessInstance[];
    legs: RouteLeg[];
}

export type Witness = CountsWitness | TilesWitness | DistancesWitness | BridgesWitness | RoutesWitness;

export type WitnessSection = Witness["section"];

export interface LevelTask {
    task: string;
    set_pieces: string[];
    random_set_pieces: string[];
}

export interface LevelTable {
    prefab_swaps: Partial<Record<SwapCategory, string>>;
    tasks: LevelTask[];
}

export interface SearchHit {
    seed: number;
    entry: number | null;
    level: LevelTable;
    results: Witness[];
}

export interface SearchOutput {
    hits: SearchHit[];
    scanned?: number;
    last_scanned: number | null;
    next_seed: number | null;
    stopped?: StopReason;
    timings?: SearchTimings;
}

export type JobResult = { kind: "search"; search: SearchOutput } | { kind: "error"; error: string };

type Parser<T> = (value: unknown) => T | undefined;
type Parsers<T> = { [K in keyof T]-?: Parser<T[K]> };

const text: Parser<string> = (value) => (typeof value === "string" ? value : undefined);

const finite: Parser<number> = (value) => (typeof value === "number" && Number.isFinite(value) ? value : undefined);

const integerUpTo =
    (max: number): Parser<number> =>
        (value) =>
            Number.isInteger(value) && (value as number) >= 0 && (value as number) <= max
                ? (value as number)
                : undefined;

const uint32 = integerUpTo(SEED_SPACE - 1);
const seedCount = integerUpTo(SEED_SPACE);
const boolean: Parser<boolean> = (value) => (typeof value === "boolean" ? value : undefined);

const oneOf =
    <T extends string>(options: readonly T[]): Parser<T> =>
        (value) =>
            options.find((option) => option === value);

const nullable =
    <T>(parse: Parser<T>): Parser<T | null> =>
        (value) =>
            value === null ? null : parse(value);

const withDefault =
    <T>(parse: Parser<T>, fallback: T): Parser<T> =>
        (value) =>
            parse(value) ?? fallback;

const listOf =
    <T>(parse: Parser<T>): Parser<T[]> =>
        (value) =>
            Array.isArray(value) ? value.map(parse).filter((item): item is T => item !== undefined) : [];

function parseFields(fields: Record<string, unknown>, parsers: Record<string, Parser<unknown>>): [string, unknown][] {
    return Object.entries(parsers).map(([key, parse]) => [key, parse(fields[key])]);
}

function shape<R extends object, O extends object = object>(
    required: Parsers<R>,
    optional?: Parsers<O>
): Parser<R & Partial<O>> {
    return (value) => {
        if (!isRecord(value)) return undefined;
        const needed = parseFields(value, required as Record<string, Parser<unknown>>);
        if (needed.some(([, parsed]) => parsed === undefined)) return undefined;
        const extra = parseFields(value, (optional ?? {}) as Record<string, Parser<unknown>>)
            .filter(([, parsed]) => parsed !== undefined);
        return Object.fromEntries([...needed, ...extra]) as R & Partial<O>;
    };
}

const instanceParsers: Parsers<WitnessInstance> = { prefab: text, index: uint32, x: finite, z: finite };
const instance = shape<WitnessInstance>(instanceParsers);
const countedInstance = shape<WitnessInstance, Omit<CountedInstance, keyof WitnessInstance>>(instanceParsers, {
    near: instance,
    distance: finite
});
const jump = shape<WormholeJump>({ entry: instance, exit: instance });
const jumps = listOf(jump);
const tile = shape<WitnessTile>({ tx: uint32, ty: uint32, x: finite, z: finite });
const room = shape<WitnessRoom>({ node: text, type: uint32, x: finite, z: finite });
const witnessBase = { index: withDefault(uint32, 0), ok: withDefault(boolean, true) };

const WITNESS_PARSERS: Record<WitnessSection, Parser<Omit<Witness, "section">>> = {
    counts: shape({ ...witnessBase, count: uint32, instances: listOf(countedInstance) }, { total: uint32 }),
    tiles: shape({ ...witnessBase, distance: uint32 }, { from_tile: tile, to_tile: tile }),
    distances: shape({ ...witnessBase, distance: nullable(finite), wormholes: jumps }, {
        from: instance,
        to: instance
    }),
    bridges: shape({ ...witnessBase, length: nullable(finite) }, {
        from: room,
        to: room,
        stray: oneOf<"from" | "to">(["from", "to"])
    }),
    routes: shape({
        ...witnessBase,
        length: finite,
        stops: listOf(instance),
        legs: listOf(shape<RouteLeg>({ from: instance, to: instance, distance: finite, wormholes: jumps }))
    })
};

const witnessSection = oneOf(Object.keys(WITNESS_PARSERS) as WitnessSection[]);

/** The caves' witnesses list their jumps as `pillars`, the forest's as `wormholes`. */
function withJumps(value: unknown): unknown {
    if (!isRecord(value)) return value;
    const { pillars, legs, ...rest } = value;
    return {
        ...rest,
        ...(pillars === undefined ? {} : { wormholes: pillars }),
        ...(Array.isArray(legs) ? { legs: legs.map(withJumps) } : {})
    };
}

const witness: Parser<Witness> = (raw) => {
    const value = withJumps(raw);
    const section = witnessSection(asRecord(value).section);
    const parsed = section && WITNESS_PARSERS[section](value);
    return parsed ? ({ ...parsed, section } as Witness) : undefined;
};

/** The world checks (parts B-E) of a results array, without its level-table checks. */
export const parseWitnesses = (results: unknown): Witness[] => listOf(witness)(results) ?? [];

const SWAP_CATEGORIES: SwapCategory[] = ["grass", "twigs", "berries"];

const prefabSwaps: Parser<LevelTable["prefab_swaps"]> = (value) => {
    const fields = asRecord(value);
    return Object.fromEntries(
        SWAP_CATEGORIES
            .map((category) => [category, text(fields[category])])
            .filter(([, option]) => option !== undefined)
    );
};

const EMPTY_LEVEL: LevelTable = { prefab_swaps: {}, tasks: [] };
const strings = listOf(text);

const level = shape<LevelTable>({
    prefab_swaps: prefabSwaps,
    tasks: listOf(shape<LevelTask>({ task: text, set_pieces: strings, random_set_pieces: strings }))
});

const hit = shape<SearchHit>({
    seed: uint32,
    entry: withDefault(nullable(uint32), null),
    level: withDefault(level, EMPTY_LEVEL),
    results: listOf(witness)
});

const search = shape<Pick<SearchOutput, "hits" | "last_scanned" | "next_seed">, Pick<SearchOutput, "scanned" | "stopped">>(
    {
        hits: (value) => (Array.isArray(value) ? listOf(hit)(value) : undefined),
        last_scanned: withDefault(nullable(uint32), null),
        next_seed: withDefault(nullable(uint32), null)
    },
    { scanned: seedCount, stopped: oneOf<StopReason>(["limit", "time", "end"]) }
);

/** Never throws; `null` when the result is neither a job object nor `{"error": ...}`. */
export function parseJobResult(result: unknown): JobResult | null {
    const error = text(asRecord(result).error);
    if (error !== undefined) return { kind: "error", error };
    const parsed = search(result);
    const timings = parseTimings(asRecord(result).timings);
    return parsed ? { kind: "search", search: timings ? { ...parsed, timings } : parsed } : null;
}

/** The scan may wrap around the seed space. */
export function scannedRange({ scanned, last_scanned: last }: SearchOutput): [number, number] | null {
    const partial = scanned !== undefined && scanned > 0 && scanned < SEED_SPACE && last !== null;
    return partial ? [(((last - scanned + 1) % SEED_SPACE) + SEED_SPACE) % SEED_SPACE, last] : null;
}
