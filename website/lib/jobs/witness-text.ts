import type { DistancesWitness, Witness, WitnessInstance, WitnessSection } from "./job-result";

const UNITS_PER_TILE = 4;

const WHOLE = new Intl.NumberFormat();
const DISTANCE = new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 });

const WITNESS_LABELS: Record<WitnessSection, string> = {
    counts: "Count",
    distances: "Distance",
    tiles: "Tiles",
    routes: "Route"
};

/** `count` and `one` or `many`, e.g. "1 seed", "2,000 seeds". */
export const plural = (count: number, one: string, many = `${one}s`) => `${WHOLE.format(count)} ${count === 1 ? one : many}`;

const distance = (units: number) => `${DISTANCE.format(units)} units (${DISTANCE.format(units / UNITS_PER_TILE)} tiles)`;

const chain = (instances: (WitnessInstance | undefined)[]) =>
    instances.map((instance) => instance?.prefab ?? "?").join(" -> ");

const jumps = (witness: DistancesWitness) => {
    const noun = witness.wormholes[0]?.entry.prefab.startsWith("tentacle_pillar") ? "tentacle pillar jump" : "wormhole jump";
    return witness.wormholes.length > 0 ? `, ${plural(witness.wormholes.length, noun)}` : "";
};

type WitnessFigures = { [S in WitnessSection]: (witness: Extract<Witness, { section: S }>) => string };

const WITNESS_FIGURES: WitnessFigures = {
    counts: (witness) =>
        witness.total === undefined ? `${WHOLE.format(witness.count)} found` : `${WHOLE.format(witness.count)} of ${WHOLE.format(witness.total)} nearby`,
    tiles: (witness) => plural(witness.distance, "tile step"),
    distances: (witness) =>
        witness.distance === null
            ? "no pair"
            : `${chain([witness.from, witness.to])}: ${distance(witness.distance)}${jumps(witness)}`,
    routes: (witness) => `${chain(witness.stops)}: ${distance(witness.length)}`
};

/** A world check as a search hit lists it: its rule, then what the world has for it. */
export const describeWitness = (witness: Witness) =>
    `${WITNESS_LABELS[witness.section]} rule ${witness.index + 1}: ${(WITNESS_FIGURES[witness.section] as (witness: Witness) => string)(witness)}`;
