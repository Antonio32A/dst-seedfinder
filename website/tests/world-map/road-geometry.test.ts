import { describe, expect, it } from "vitest";
import {
    PAVED_WEIGHT,
    ROAD_PARAMETERS,
    ROAD_STRIPS,
    ROAD_VERTEX_FLOATS,
    roadCurve,
    roadMesh,
    roadShape
} from "@/lib/world-map/canvas/road-geometry";

const STEPS = ROAD_PARAMETERS.subdivisionsPerSegment;
const STRAIGHT = new Int32Array([0, 0, 1000, 0]);
const BENT = new Int32Array([0, 0, 1000, 0, 1000, 1000]);

const vertices = (strip: Float32Array) =>
    Array.from(
        { length: strip.length / ROAD_VERTEX_FLOATS },
        (_, at) => [...strip.subarray(ROAD_VERTEX_FLOATS * at, ROAD_VERTEX_FLOATS * (at + 1))]
    );

describe("the road shapes", () => {
    it("give the paved road a centre strip with narrow edges, at the middle of the game's ranges", () => {
        expect(roadShape(PAVED_WEIGHT)).toEqual({ width: 2.5, edge: 0.75 });
    });

    it("give every other weight a dirt path of four times wider edges and no centre strip", () => {
        expect(roadShape(1)).toEqual({ width: 0, edge: 3 });
        expect(roadShape(2)).toEqual(roadShape(1));
    });
});

describe("a road's curve", () => {
    it("has the game's subdivisions per segment, and goes through every control point in world units", () => {
        const curve = roadCurve(BENT);
        expect(curve).toHaveLength(2 * (2 * STEPS + 1));
        expect([...curve.subarray(0, 2)]).toEqual([0, 0]);
        expect([...curve.subarray(2 * STEPS, 2 * STEPS + 2)]).toEqual([10, 0]);
        expect([...curve.subarray(curve.length - 2)]).toEqual([10, 10]);
    });

    it("stays on the line through two points", () => {
        const curve = roadCurve(STRAIGHT);
        for (let at = 0; at < curve.length; at += 2) expect(curve[at + 1]).toBeCloseTo(0, 5);
        const xs = Array.from({ length: curve.length / 2 }, (_, step) => curve[2 * step]);
        expect(xs).toEqual([...xs].sort((a, b) => a - b));
    });

    it("leaves the control polygon near a corner, as a Catmull-Rom spline does", () => {
        const [, z] = roadCurve(BENT).subarray(2 * (STEPS - 5), 2 * (STEPS - 5) + 2);
        expect(Math.abs(z)).toBeGreaterThan(0.1);
    });

    it("is empty for fewer than two points", () => {
        expect(roadCurve(new Int32Array([100, 100]))).toHaveLength(0);
        expect(roadCurve(new Int32Array(0))).toHaveLength(0);
    });
});

describe("a road's mesh", () => {
    const segments = 2 * STEPS;
    const paved = roadMesh(BENT, PAVED_WEIGHT);

    it("has an edge strip along each side and a centre strip between them", () => {
        expect(paved.edges).toHaveLength(2 * segments * 6 * ROAD_VERTEX_FLOATS);
        expect(paved.center).toHaveLength(segments * 6 * ROAD_VERTEX_FLOATS);
    });

    it("puts each edge's transparent side outside and its solid side against the centre", () => {
        const { width, edge } = roadShape(PAVED_WEIGHT);
        const texels = vertices(roadMesh(STRAIGHT, PAVED_WEIGHT).edges).map(([, z, u]) => ({ z, u }));
        for (const side of [-1, 1]) {
            const own = texels.filter(({ z }) => Math.sign(z) === side);
            expect(own.filter(({ z }) => Math.abs(z) > width / 2 + edge - 1e-4).every(({ u }) => u === 0)).toBe(true);
            expect(own.filter(({ z }) => Math.abs(z) < width / 2 + 1e-4).every(({ u }) => u === 1)).toBe(true);
        }
    });

    it("repeats the edge texture along the road once per two edge widths", () => {
        const straight = roadMesh(STRAIGHT, PAVED_WEIGHT);
        const lastV = Math.max(...vertices(straight.edges).map(([, , , v]) => v));
        expect(lastV).toBeCloseTo(10 / (2 * roadShape(PAVED_WEIGHT).edge), 3);
    });

    it("caps each end with one end cap and a corner on each side, reaching one edge width past the end", () => {
        const straight = roadMesh(STRAIGHT, PAVED_WEIGHT);
        const { edge } = roadShape(PAVED_WEIGHT);
        expect(straight.ends).toHaveLength(2 * 6 * ROAD_VERTEX_FLOATS);
        expect(straight.corners).toHaveLength(4 * 6 * ROAD_VERTEX_FLOATS);
        const xs = vertices(straight.ends).map(([x]) => x);
        expect(Math.min(...xs)).toBeCloseTo(-edge, 4);
        expect(Math.max(...xs)).toBeCloseTo(10 + edge, 4);
    });

    it("draws a dirt path as edges, corners and end caps only", () => {
        const dirt = roadMesh(BENT, 1);
        expect(dirt.center).toHaveLength(0);
        expect(dirt.edges.length).toBeGreaterThan(0);
        const zs = vertices(roadMesh(STRAIGHT, 1).edges).map(([, z]) => Math.abs(z));
        expect(Math.max(...zs)).toBeCloseTo(3, 4);
    });

    it("has nothing for a road too short to draw", () => {
        for (const strip of ROAD_STRIPS) expect(roadMesh(new Int32Array([0, 0]), PAVED_WEIGHT)[strip]).toHaveLength(0);
    });
});
