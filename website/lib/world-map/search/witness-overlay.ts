import { TILES } from "@/lib/catalog/world";
import { type Filter, WORLD_UNITS_PER_TILE } from "@/lib/config/seedfinder-config";
import type { Witness, WitnessInstance, WormholeJump } from "@/lib/jobs/job-result";
import type { WorldPoint } from "@/lib/world-map/view/map-view";
import type { GeneratedWorld } from "@/lib/world-map/world/world-dump";

export interface WitnessMark {
    prefab: string;
    at: WorldPoint;
    ok: boolean;
}

export interface WitnessSegment {
    from: WorldPoint;
    to: WorldPoint;
    ok: boolean;
    /** A wormhole jump rather than a walk. */
    jump: boolean;
}

export interface WitnessShape {
    marks: WitnessMark[];
    segments: WitnessSegment[];
    /** Where the map centres to show the witness, `null` when it draws nothing. */
    focus: WorldPoint | null;
}

type Line = Omit<WitnessSegment, "ok">;

interface Parts {
    instances: WitnessInstance[];
    lines: Line[];
    focus?: WorldPoint;
}

type SectionParts = { [S in Witness["section"]]: (witness: Extract<Witness, { section: S }>) => Parts };

const point = ({ x, z }: WorldPoint): WorldPoint => ({ x, z });

function travel(from: WitnessInstance, to: WitnessInstance, wormholes: WormholeJump[]): Parts {
    const path = [from, ...wormholes.flatMap(({ entry, exit }) => [entry, exit]), to];
    const lines = path.slice(1).map((end, step) => ({ from: point(path[step]), to: point(end), jump: step % 2 === 1 }));
    return { instances: path, lines };
}

const BRIDGE_WIDTH_TILES = 3;

const rectangle = (x0: number, z0: number, x1: number, z1: number): Line[] => {
    const corners = [{ x: x0, z: z0 }, { x: x1, z: z0 }, { x: x1, z: z1 }, { x: x0, z: z1 }];
    return corners.map((from, corner) => ({ from, to: corners[(corner + 1) % corners.length], jump: false }));
};

const outline = ({ x, z }: WorldPoint, tiles = 1): Line[] => {
    const half = tiles * WORLD_UNITS_PER_TILE / 2;
    return rectangle(x - half, z - half, x + half, z + half);
};

const HALF_TILE = WORLD_UNITS_PER_TILE / 2;

const NOTHING: Parts = { instances: [], lines: [] };

type TileGrid = Pick<GeneratedWorld, "width" | "height">;
type LandGrid = TileGrid & Pick<GeneratedWorld, "tiles" | "tileNames">;

type Run = [line: number, start: number, end: number];

/** Where the tile `ty * width + tx` is in a grid padded with one tile on every side. */
const paddedIndex = (at: number, width: number) => (Math.floor(at / width) + 1) * (width + 2) + at % width + 1;

/** The runs of steps where `edge(line, step)` holds, along each of `lines + 1` lines of `length` steps. */
function runs(lines: number, length: number, edge: (line: number, step: number) => boolean): Run[] {
    const found: Run[] = [];
    for (let line = 0; line <= lines; line++) {
        let start = -1;
        for (let step = 0; step <= length; step++) {
            const on = step < length && edge(line, step);
            if (on && start < 0) start = step;
            if (on || start < 0) continue;
            found.push([line, start, step]);
            start = -1;
        }
    }
    return found;
}

/**
 * The tiles (`ty * width + tx`, ascending) of the landmasses that hold `starts`: land tiles joined up, down, left or
 * right, never through a corner alone, as the finder's islands rule joins them.
 */
export function landmassTiles(world: LandGrid, starts: readonly { tx: number; ty: number }[]): number[] {
    const { width, height, tiles, tileNames } = world;
    const landIds = new Set([...tileNames].flatMap(([id, name]) =>
        (Object.hasOwn(TILES, name) && TILES[name].kind === "land" ? [id] : [])));
    const row = width + 2;
    const open = new Uint8Array(row * (height + 2));
    tiles.forEach((tile, at) => {
        open[paddedIndex(at, width)] = Number(landIds.has(tile));
    });
    const reached: number[] = [];
    const visit = (at: number) => {
        if (open[at] === 0) return;
        open[at] = 0;
        reached.push(at);
    };
    starts.filter(({ tx, ty }) => tx < width && ty < height)
        .forEach(({ tx, ty }) => visit(paddedIndex(ty * width + tx, width)));
    for (let next = 0; next < reached.length; next++) [1, -1, row, -row].forEach((step) => visit(reached[next] + step));
    return reached.map((at) => (Math.floor(at / row) - 1) * width + at % row - 1).sort((a, b) => a - b);
}

/** The border between `tiles` and every other tile of the map, in straight runs. */
function tilesOutline({ width, height }: TileGrid, tiles: readonly number[]): Line[] {
    const row = width + 2;
    const inside = new Uint8Array(row * (height + 2));
    tiles.forEach((at) => {
        inside[paddedIndex(at, width)] = 1;
    });
    const has = (tx: number, ty: number) => inside[(ty + 1) * row + tx + 1];
    const x = (tx: number) => (tx - width / 2) * WORLD_UNITS_PER_TILE - HALF_TILE;
    const z = (ty: number) => (ty - height / 2) * WORLD_UNITS_PER_TILE - HALF_TILE;
    const across = runs(height, width, (ty, tx) => has(tx, ty - 1) !== has(tx, ty))
        .map(([ty, from, to]) => ({ from: { x: x(from), z: z(ty) }, to: { x: x(to), z: z(ty) }, jump: false }));
    const down = runs(width, height, (tx, ty) => has(tx - 1, ty) !== has(tx, ty))
        .map(([tx, from, to]) => ({ from: { x: x(tx), z: z(from) }, to: { x: x(tx), z: z(to) }, jump: false }));
    return [...across, ...down];
}

const joined = (parts: Parts[]): Parts => ({
    instances: parts.flatMap(({ instances }) => instances),
    lines: parts.flatMap(({ lines }) => lines)
});

const SECTION_PARTS: SectionParts = {
    setpieces: () => NOTHING,
    counts: ({ instances }) =>
        joined(instances.map((instance) => (instance.near ? travel(instance, instance.near, []) : {
            ...NOTHING,
            instances: [instance]
        }))),
    tiles: ({ from_tile: from, to_tile: to }) =>
        from && to ? {
            ...NOTHING,
            lines: [...outline(from), ...outline(to), { from: point(from), to: point(to), jump: false }]
        } : NOTHING,
    distances: ({ from, to, wormholes }) => (from && to ? travel(from, to, wormholes) : NOTHING),
    bridges: ({ from, to, stray = "from" }) =>
        from && to ? {
            ...NOTHING,
            lines: [...outline(from, BRIDGE_WIDTH_TILES), ...outline(to, BRIDGE_WIDTH_TILES), {
                from: point(from),
                to: point(to),
                jump: false
            }],
            focus: point(stray === "from" ? from : to)
        } : NOTHING,
    routes: ({ legs }) => joined(legs.map(({ from, to, wormholes }) => travel(from, to, wormholes))),
    islands: ({ at, tile, bounds }) => {
        if (!at) return NOTHING;
        if (!tile || !bounds) return { instances: [at], lines: [], focus: point(at) };
        const x = (tx: number) => tile.x + (tx - tile.tx) * WORLD_UNITS_PER_TILE - HALF_TILE;
        const z = (ty: number) => tile.z + (ty - tile.ty) * WORLD_UNITS_PER_TILE - HALF_TILE;
        const box = rectangle(x(bounds.tx0), z(bounds.ty0), x(bounds.tx1 + 1), z(bounds.ty1 + 1));
        return { instances: [at], lines: box, focus: point(at) };
    }
};

const middle = (values: number[]) => (Math.min(...values) + Math.max(...values)) / 2;

function shapeOf(ok: boolean, { instances: listed, lines, focus }: Parts): WitnessShape {
    const instances = [...new Map(listed.map((instance) => [`${instance.prefab}#${instance.index}`, instance])).values()];
    const points = [...instances, ...lines.flatMap(({ from, to }) => [from, to])];
    return {
        marks: instances.map(({ prefab, x, z }) => ({ prefab, at: { x, z }, ok })),
        segments: lines.map((line) => ({ ...line, ok })),
        focus: focus ?? (points.length === 0 ? null : {
            x: middle(points.map(({ x }) => x)),
            z: middle(points.map(({ z }) => z))
        })
    };
}

/** Without the world's tiles, an islands witness is drawn as the box around its landmasses. */
export const witnessShape = (witness: Witness): WitnessShape =>
    shapeOf(witness.ok, (SECTION_PARTS[witness.section] as (witness: Witness) => Parts)(witness));

/**
 * A count without `near` lists no instances, so its marks are the world's instances of its rule's prefabs. An islands
 * witness outlines its landmasses, flooded again over the world's tiles.
 */
export function witnessShapes(
    witnesses: Witness[],
    filter: Filter | undefined,
    world: Pick<GeneratedWorld, "prefabs"> & LandGrid
): WitnessShape[] {
    return witnesses.map((witness) => {
        if (witness.section === "islands") {
            const parts = SECTION_PARTS.islands(witness);
            const reached = landmassTiles(world, witness.landmasses);
            return shapeOf(witness.ok, reached.length > 0 ? { ...parts, lines: tilesOutline(world, reached) } : parts);
        }
        const rule = filter?.counts?.[witness.index];
        const plain = witness.section === "counts" && witness.total === undefined;
        if (!plain || rule === undefined) return witnessShape(witness);
        const names = new Set([rule.prefab].flat());
        const instances = world.prefabs.filter(({ name }) => names.has(name)).flatMap(({ name, positions }) =>
            Array.from({ length: positions.length / 2 }, (_, index) => ({
                prefab: name,
                index,
                x: positions[2 * index] / 100,
                z: positions[2 * index + 1] / 100
            }))
        );
        return witnessShape({ ...witness, instances });
    });
}
