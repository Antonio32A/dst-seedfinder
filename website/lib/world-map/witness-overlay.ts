import { type Criterion, type PrefabSet, WORLD_UNITS_PER_TILE } from "@/lib/config/seedfinder-config";
import type { Witness, WitnessInstance, WitnessTile, WormholeJump } from "@/lib/jobs/job-result";
import type { WorldPoint } from "./map-view";
import type { GeneratedWorld } from "./world-dump";

export interface WitnessMark {
    prefab: string;
    at: WorldPoint;
    ok: boolean;
}

export interface WitnessSegment {
    from: WorldPoint;
    to: WorldPoint;
    ok: boolean;
    /** A wormhole jump, from its entry to its exit, rather than a walk. */
    jump: boolean;
}

/** What a witness draws on the map, and where the map centres to show it (`null` when it draws nothing). */
export interface WitnessShape {
    marks: WitnessMark[];
    segments: WitnessSegment[];
    focus: WorldPoint | null;
}

type Line = Omit<WitnessSegment, "ok">;

interface Parts {
    instances: WitnessInstance[];
    lines: Line[];
}

type SectionParts = { [S in Witness["section"]]: (witness: Extract<Witness, { section: S }>) => Parts };

const point = ({ x, z }: WorldPoint): WorldPoint => ({ x, z });

function travel(from: WitnessInstance, to: WitnessInstance, wormholes: WormholeJump[]): Parts {
    const path = [from, ...wormholes.flatMap(({ entry, exit }) => [entry, exit]), to];
    const lines = path.slice(1).map((end, step) => ({ from: point(path[step]), to: point(end), jump: step % 2 === 1 }));
    return { instances: path, lines };
}

const CORNERS = [[-1, -1], [1, -1], [1, 1], [-1, 1]];

const outline = ({ x, z }: WitnessTile): Line[] => {
    const corners = CORNERS.map(([dx, dz]) => ({ x: x + dx * WORLD_UNITS_PER_TILE / 2, z: z + dz * WORLD_UNITS_PER_TILE / 2 }));
    return corners.map((from, corner) => ({ from, to: corners[(corner + 1) % corners.length], jump: false }));
};

const NOTHING: Parts = { instances: [], lines: [] };

const joined = (parts: Parts[]): Parts => ({
    instances: parts.flatMap(({ instances }) => instances),
    lines: parts.flatMap(({ lines }) => lines)
});

const SECTION_PARTS: SectionParts = {
    counts: ({ instances }) =>
        joined(instances.map((instance) => (instance.near ? travel(instance, instance.near, []) : { ...NOTHING, instances: [instance] }))),
    tiles: ({ from_tile: from, to_tile: to }) =>
        from && to ? { ...NOTHING, lines: [...outline(from), ...outline(to), { from: point(from), to: point(to), jump: false }] } : NOTHING,
    distances: ({ from, to, wormholes }) => (from && to ? travel(from, to, wormholes) : NOTHING),
    routes: ({ legs }) => joined(legs.map(({ from, to, wormholes }) => travel(from, to, wormholes)))
};

const middle = (values: number[]) => (Math.min(...values) + Math.max(...values)) / 2;

/** The marks and lines that show a witness on the map: its instances, and the walks and jumps between them. */
export function witnessShape(witness: Witness): WitnessShape {
    const { instances: listed, lines } = (SECTION_PARTS[witness.section] as (witness: Witness) => Parts)(witness);
    const instances = [...new Map(listed.map((instance) => [`${instance.prefab}#${instance.index}`, instance])).values()];
    const points = [...instances, ...lines.flatMap(({ from, to }) => [from, to])];
    return {
        marks: instances.map(({ prefab, x, z }) => ({ prefab, at: { x, z }, ok: witness.ok })),
        segments: lines.map((line) => ({ ...line, ok: witness.ok })),
        focus: points.length === 0 ? null : { x: middle(points.map(({ x }) => x)), z: middle(points.map(({ z }) => z)) }
    };
}

function worldInstances(world: Pick<GeneratedWorld, "prefabs">, prefabs: PrefabSet): WitnessInstance[] {
    const names = new Set([prefabs].flat());
    return world.prefabs.filter(({ name }) => names.has(name)).flatMap(({ name, positions }) =>
        Array.from({ length: positions.length / 2 }, (_, index) => ({
            prefab: name,
            index,
            x: positions[2 * index] / 100,
            z: positions[2 * index + 1] / 100
        }))
    );
}

/**
 * The shapes of a config entry's witnesses on its world. A count without `near` lists no instances, so its marks are
 * the world's instances of its rule's prefabs.
 */
export function witnessShapes(
    witnesses: Witness[],
    criterion: Criterion | undefined,
    world: Pick<GeneratedWorld, "prefabs">
): WitnessShape[] {
    return witnesses.map((witness) => {
        if (witness.section !== "counts" || witness.total !== undefined) return witnessShape(witness);
        const rule = criterion?.counts?.[witness.index];
        return witnessShape(rule ? { ...witness, instances: worldInstances(world, rule.prefab) } : witness);
    });
}
