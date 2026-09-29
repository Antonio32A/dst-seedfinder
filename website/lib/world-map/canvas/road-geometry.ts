export const ROAD_PARAMETERS = {
    subdivisionsPerSegment: 50,
    minWidth: 2,
    maxWidth: 3,
    minEdgeWidth: 0.5,
    maxEdgeWidth: 1
} as const;

/** The weight of the paved road, the one the game draws with the wide centre strip. */
export const PAVED_WEIGHT = 3;
export const ROAD_STRIPS = ["corners", "ends", "edges", "center"] as const;
export type RoadStrip = (typeof ROAD_STRIPS)[number];
/** Floats per vertex: world `x, z`, then the texture's `u, v`. */
export const ROAD_VERTEX_FLOATS = 4;

const UNITS_PER_KILO = 100;
const EDGE_WIDTHS_PER_REPEAT = 2;
const DIRT_EDGE_SCALE = 4;

export interface RoadShape {
    /** The centre strip's width. */
    width: number;
    /** The width of each edge strip, and how far the end caps reach. */
    edge: number;
}

export type RoadMesh = Record<RoadStrip, Float32Array>;

interface Frames {
    curve: Float32Array;
    /** Unit normal `nx, nz` per curve point. */
    normals: Float32Array;
    /** Distance from the start, per curve point. */
    along: Float32Array;
}

interface Row {
    a: readonly [number, number];
    b: readonly [number, number];
    v: number;
}

const mean = (low: number, high: number) => (low + high) / 2;

/**
 * The strip widths the game generates a road with, at the middle of the ranges its jitter draws from: the paved road
 * has a centre strip with narrow edges, anything else is a dirt path that is all wide edges.
 */
export function roadShape(weight: number): RoadShape {
    const { minWidth, maxWidth, minEdgeWidth, maxEdgeWidth } = ROAD_PARAMETERS;
    return weight === PAVED_WEIGHT
        ? { width: mean(minWidth, maxWidth), edge: mean(minEdgeWidth, maxEdgeWidth) }
        : { width: 0, edge: DIRT_EDGE_SCALE * mean(minEdgeWidth, maxEdgeWidth) };
}

const catmullRom = (p0: number, p1: number, p2: number, p3: number, t: number) =>
    0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3);

/**
 * The Catmull-Rom spline through a road's control points (interleaved `xk, zk`, world units times 100), the first and last
 * point repeated as its padding, with the game's subdivisions per segment. Interleaved `x, z` in world units; empty
 * for fewer than two points.
 */
export function roadCurve(points: Int32Array): Float32Array {
    const count = points.length / 2;
    if (count < 2) return new Float32Array(0);
    const steps = ROAD_PARAMETERS.subdivisionsPerSegment;
    const control = (index: number, axis: number) =>
        points[2 * Math.min(Math.max(index, 0), count - 1) + axis] / UNITS_PER_KILO;
    const curve = new Float32Array(2 * ((count - 1) * steps + 1));
    for (let step = 0; step < curve.length / 2; step++) {
        const segment = Math.min(Math.floor(step / steps), count - 2);
        for (let axis = 0; axis < 2; axis++) {
            curve[2 * step + axis] = catmullRom(
                control(segment - 1, axis), control(segment, axis), control(segment + 1, axis), control(segment + 2, axis),
                (step - segment * steps) / steps
            );
        }
    }
    return curve;
}

const offset = ({ curve, normals }: Frames, step: number, lateral: number, forward = 0, depth = 0) => [
    curve[2 * step] + normals[2 * step] * lateral + normals[2 * step + 1] * forward * depth,
    curve[2 * step + 1] + normals[2 * step + 1] * lateral - normals[2 * step] * forward * depth
] as const;

function quads(rows: Row[], uA: number, uB: number): number[] {
    const vertices: number[] = [];
    for (let at = 1; at < rows.length; at++) {
        const [previous, next] = [rows[at - 1], rows[at]];
        const corners = [[previous.a, uA, previous.v], [previous.b, uB, previous.v], [next.a, uA, next.v], [next.b, uB, next.v]] as const;
        for (const corner of [0, 1, 2, 2, 1, 3]) {
            const [[x, z], u, v] = corners[corner];
            vertices.push(x, z, u, v);
        }
    }
    return vertices;
}

const ribbon = (frames: Frames, from: number, to: number, uFrom: number, uTo: number, { edge }: RoadShape) =>
    quads(Array.from({ length: frames.along.length }, (_, step) => ({
        a: offset(frames, step, from),
        b: offset(frames, step, to),
        v: frames.along[step] / (EDGE_WIDTHS_PER_REPEAT * edge)
    })), uFrom, uTo);

/** Two rows across the road at curve point `step`: on the road's end line, then `edge` further out along `forward` (1 or -1). */
const cap = (frames: Frames, step: number, forward: number, from: number, to: number, edge: number): Row[] => [
    { a: offset(frames, step, from), b: offset(frames, step, to), v: 0 },
    { a: offset(frames, step, from, forward, edge), b: offset(frames, step, to, forward, edge), v: 1 }
];

/**
 * A road's triangle lists, one per strip type, in the game's layout: an edge strip along each side (transparent on the
 * outside, solid against the centre), the centre strip between them, and at each end a cap across the centre with a
 * corner beside it on each side. Each vertex is {@link ROAD_VERTEX_FLOATS} floats: world `x, z`, then `u, v`, with the
 * edge texture repeating along the road once per two edge widths.
 */
export function roadMesh(points: Int32Array, weight: number): RoadMesh {
    const curve = roadCurve(points);
    const count = curve.length / 2;
    const normals = new Float32Array(curve.length);
    const along = new Float32Array(count);
    for (let step = 0; step < count; step++) {
        const [before, after] = [Math.max(step - 1, 0), Math.min(step + 1, count - 1)];
        const [dx, dz] = [curve[2 * after] - curve[2 * before], curve[2 * after + 1] - curve[2 * before + 1]];
        const length = Math.hypot(dx, dz) || 1;
        normals.set([-dz / length, dx / length], 2 * step);
        if (step > 0) along[step] = along[step - 1] + Math.hypot(curve[2 * step] - curve[2 * step - 2], curve[2 * step + 1] - curve[2 * step - 1]);
    }
    const frames: Frames = { curve, normals, along };
    const shape = roadShape(weight);
    const inner = shape.width / 2;
    const outer = inner + shape.edge;
    const last = count - 1;
    const endsAt = [[0, -1], [last, 1]] as const;
    const build = (parts: number[][]) => Float32Array.from(last < 1 ? [] : parts.flat());
    return {
        corners: build(endsAt.flatMap(([step, forward]) => [-1, 1].map((side) =>
            quads(cap(frames, step, forward, side * inner, side * outer, shape.edge), 0, 1)))),
        ends: build(endsAt.map(([step, forward]) => quads(cap(frames, step, forward, -inner, inner, shape.edge), 0, 1))),
        edges: build([ribbon(frames, -outer, -inner, 0, 1, shape), ribbon(frames, inner, outer, 1, 0, shape)]),
        center: build(shape.width > 0 ? [ribbon(frames, -inner, inner, 0, 1, shape)] : [])
    };
}
