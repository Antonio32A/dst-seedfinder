import type {
    DistancesWitness,
    GroupRuleResult,
    PlacedPiece,
    Witness,
    WitnessInstance,
    WitnessRoom,
    WitnessSection
} from "./job-result";

const UNITS_PER_TILE = 4;

const WHOLE = new Intl.NumberFormat();
const DISTANCE = new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 });

const WITNESS_LABELS: Record<WitnessSection, string> = {
    setpieces: "Set piece",
    counts: "Count",
    distances: "Distance",
    tiles: "Tiles",
    bridges: "Turf bridge",
    routes: "Route"
};

/** A world rule as the timings name it, e.g. "Distance rule 2". */
export const ruleLabel = (section: string, index: number) =>
    `${(WITNESS_LABELS as Record<string, string | undefined>)[section] ?? section} rule ${index + 1}`;

/** `count` and `one` or `many`, e.g. "1 seed", "2,000 seeds". */
export const plural = (count: number, one: string, many = `${one}s`) => `${WHOLE.format(count)} ${count === 1 ? one : many}`;

const distance = (units: number) => `${DISTANCE.format(units)} units (${DISTANCE.format(units / UNITS_PER_TILE)} tiles)`;

const chain = (instances: (WitnessInstance | undefined)[]) =>
    instances.map((instance) => instance?.prefab ?? "?").join(" -> ");

/** A topology node id like `CentipedeCaveTask:BG_89:BGVentsRoom` as its room and task. */
const roomName = (room: WitnessRoom | undefined) => {
    const [task, ...rest] = room?.node.split(":") ?? ["?"];
    return rest.length > 0 ? `${rest.at(-1)} (${task})` : task;
};

const jumps = (witness: DistancesWitness) => {
    const noun = witness.wormholes[0]?.entry.prefab.startsWith("tentacle_pillar") ? "tentacle pillar jump" : "wormhole jump";
    return witness.wormholes.length > 0 ? `, ${plural(witness.wormholes.length, noun)}` : "";
};

const placedText = ({ name, planned, placed }: PlacedPiece) => `${name} ${WHOLE.format(placed)} of ${WHOLE.format(planned)} placed`;

const groupRuleText = ({ counts, pieces }: GroupRuleResult) => [
    ...pieces.map(placedText),
    ...Object.entries(counts)
        .filter(([name]) => !pieces.some((piece) => piece.name === name))
        .map(([name, count]) => `${name} ${WHOLE.format(count)} planned`)
].join(", ");

type WitnessFigures = { [S in WitnessSection]: (witness: Extract<Witness, { section: S }>) => string };

const WITNESS_FIGURES: WitnessFigures = {
    setpieces: (witness) => {
        if (!witness.any) return witness.pieces.map(placedText).join(", ");
        return witness.total === undefined
            ? witness.any.map(groupRuleText).join(" or ")
            : `${witness.any.map(groupRuleText).join(", ")}: ${WHOLE.format(witness.total)} in total`;
    },
    counts: (witness) =>
        witness.total === undefined ? `${WHOLE.format(witness.count)} found` : `${WHOLE.format(witness.count)} of ${WHOLE.format(witness.total)} nearby`,
    tiles: (witness) => plural(witness.distance, "tile step"),
    distances: (witness) =>
        witness.distance === null
            ? "no pair"
            : `${chain([witness.from, witness.to])}: ${distance(witness.distance)}${jumps(witness)}`,
    bridges: (witness) =>
        witness.length === null ? "no bridge" : `${roomName(witness.from)} -> ${roomName(witness.to)}: ${distance(witness.length)}`,
    routes: (witness) => `${chain(witness.stops)}: ${distance(witness.length)}`
};

/** A world check as a search hit lists it: its rule, then what the world has for it. */
export const describeWitness = (witness: Witness) =>
    `${WITNESS_LABELS[witness.section]} rule ${witness.index + 1}: ${(WITNESS_FIGURES[witness.section] as (witness: Witness) => string)(witness)}`;
