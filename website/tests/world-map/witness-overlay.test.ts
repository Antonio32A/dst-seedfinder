import { describe, expect, it } from "vitest";
import type { IslandsWitness, WitnessInstance } from "@/lib/jobs/job-result";
import { landmassTiles, witnessShape, witnessShapes } from "@/lib/world-map/search/witness-overlay";

const at = (prefab: string, x: number, z: number, index = 0): WitnessInstance => ({ prefab, index, x, z });

const NO_TILES = { width: 0, height: 0, tiles: new Uint16Array(0), tileNames: new Map<number, string>() };

const PORTAL = at("multiplayer_portal", 40, 400);
const PIGKING = at("pigking", -500, -120);
const ENTRY = at("wormhole", -100, 600, 2);
const EXIT = at("wormhole", 600, 80, 3);

describe("a witness on the map", () => {
    it("walks a distance from its start to its end, jumping through its wormholes", () => {
        const shape = witnessShape({
            section: "distances",
            index: 0,
            ok: true,
            distance: 822.774,
            from: PORTAL,
            to: PIGKING,
            wormholes: [{ entry: ENTRY, exit: EXIT }]
        });
        expect(shape.segments).toEqual([
            { from: { x: 40, z: 400 }, to: { x: -100, z: 600 }, ok: true, jump: false },
            { from: { x: -100, z: 600 }, to: { x: 600, z: 80 }, ok: true, jump: true },
            { from: { x: 600, z: 80 }, to: { x: -500, z: -120 }, ok: true, jump: false }
        ]);
        expect(shape.marks.map(({ prefab }) => prefab)).toEqual(["multiplayer_portal", "wormhole", "wormhole", "pigking"]);
        expect(shape.focus).toEqual({ x: 50, z: 240 });
    });

    it("walks each leg of a route, marking each stop once", () => {
        const den = at("spiderden", 480, 70);
        const shape = witnessShape({
            section: "routes",
            index: 1,
            ok: false,
            length: 900,
            stops: [PORTAL, den, PIGKING],
            legs: [
                { from: PORTAL, to: den, distance: 400, wormholes: [{ entry: ENTRY, exit: EXIT }] },
                { from: den, to: PIGKING, distance: 500, wormholes: [] }
            ]
        });
        expect(shape.segments.map(({ from, to, jump }) => [from.x, to.x, jump])).toEqual([
            [40, -100, false],
            [-100, 600, true],
            [600, 480, false],
            [480, -500, false]
        ]);
        expect(shape.segments.every(({ ok }) => !ok)).toBe(true);
        expect(shape.marks.map(({ prefab }) => prefab)).toEqual(["multiplayer_portal", "wormhole", "wormhole", "spiderden", "pigking"]);
    });

    it("marks a count's instances, and links each to the one it's near", () => {
        const [first, second, third] = [at("beefalo", 85, -382), at("beefalo", 90, -377, 10), at("beefalo", 102, -397, 1)];
        const shape = witnessShape({
            section: "counts",
            index: 0,
            ok: true,
            count: 2,
            total: 3,
            instances: [{ ...first, near: second, distance: 7 }, { ...third, near: first, distance: 21 }]
        });
        expect(shape.marks.map(({ at }) => at)).toEqual([{ x: 85, z: -382 }, { x: 90, z: -377 }, { x: 102, z: -397 }]);
        expect(shape.segments).toEqual([
            { from: { x: 85, z: -382 }, to: { x: 90, z: -377 }, ok: true, jump: false },
            { from: { x: 102, z: -397 }, to: { x: 85, z: -382 }, ok: true, jump: false }
        ]);
    });

    it("marks a plain count's instances without lines", () => {
        const shape = witnessShape({ section: "counts", index: 0, ok: true, count: 1, instances: [at("cane", 3, 4)] });
        expect(shape).toEqual({
            marks: [{ prefab: "cane", at: { x: 3, z: 4 }, ok: true }],
            segments: [],
            focus: { x: 3, z: 4 }
        });
    });

    it("outlines a tile check's from and to tiles, and links them", () => {
        const shape = witnessShape({
            section: "tiles",
            index: 0,
            ok: true,
            distance: 3,
            from_tile: { tx: 82, ty: 174, x: -522, z: -154 },
            to_tile: { tx: 85, ty: 174, x: -510, z: -154 }
        });
        const corners = (segments: typeof shape.segments) => segments.map(({ from }) => [from.x, from.z]);
        expect(corners(shape.segments.slice(0, 4))).toEqual([[-524, -156], [-520, -156], [-520, -152], [-524, -152]]);
        expect(corners(shape.segments.slice(4, 8))).toEqual([[-512, -156], [-508, -156], [-508, -152], [-512, -152]]);
        expect(shape.segments[8]).toEqual({
            from: { x: -522, z: -154 },
            to: { x: -510, z: -154 },
            ok: true,
            jump: false
        });
        expect(shape.marks).toEqual([]);
        expect(shape.focus).toEqual({ x: -516, z: -154 });
    });

    it("draws a turf bridge between its rooms, outlining both, and centres on the room left behind", () => {
        const from = { node: "CentipedeCaveTask:BG_89:BGVentsRoom", type: 2, x: -668, z: -358 };
        const to = { node: "CentipedeCaveTask:8:VentsRoom", type: 0, x: 338, z: 370 };
        const shape = witnessShape({ section: "bridges", index: 0, ok: true, length: 1241.781, from, to, stray: "to" });
        const corners = (segments: typeof shape.segments) => segments.map(({ from }) => [from.x, from.z]);
        expect(corners(shape.segments.slice(0, 4))).toEqual([[-674, -364], [-662, -364], [-662, -352], [-674, -352]]);
        expect(corners(shape.segments.slice(4, 8))).toEqual([[332, 364], [344, 364], [344, 376], [332, 376]]);
        expect(shape.segments[8])
            .toEqual({ from: { x: -668, z: -358 }, to: { x: 338, z: 370 }, ok: true, jump: false });
        expect(shape.marks).toEqual([]);
        expect(shape.focus).toEqual({ x: 338, z: 370 });
        expect(witnessShape({ section: "bridges", index: 0, ok: true, length: 1241.781, from, to }).focus).toEqual({ x: -668, z: -358 });
    });

    it("draws nothing for a world without a turf bridge", () => {
        expect(witnessShape({ section: "bridges", index: 0, ok: false, length: null })).toEqual({ marks: [], segments: [], focus: null });
    });

    it("draws nothing for a distance without a pair", () => {
        const shape = witnessShape({ section: "distances", index: 2, ok: true, distance: null, wormholes: [] });
        expect(shape).toEqual({ marks: [], segments: [], focus: null });
    });

    it("marks every instance of a plain count's prefabs, from the world", () => {
        const world = {
            ...NO_TILES,
            prefabs: [
                { name: "rook", positions: Int32Array.from([100, 200, -300, 450]) },
                { name: "pigking", positions: Int32Array.from([0, 0]) },
                { name: "knight", positions: Int32Array.from([1000, 50]) }
            ]
        };
        const [plain, near] = witnessShapes(
            [
                { section: "counts", index: 0, ok: true, count: 3, instances: [] },
                {
                    section: "counts",
                    index: 1,
                    ok: true,
                    count: 1,
                    total: 2,
                    instances: [{ ...at("rook", 1, 2), near: at("knight", 10, 0.5) }]
                }
            ],
            {
                counts: [{ prefab: ["rook", "knight"], min: 1 }, {
                    prefab: "rook",
                    near: { prefab: "knight", within: 20 }
                }]
            },
            world
        );
        expect(plain.marks).toEqual([
            { prefab: "rook", at: { x: 1, z: 2 }, ok: true },
            { prefab: "rook", at: { x: -3, z: 4.5 }, ok: true },
            { prefab: "knight", at: { x: 10, z: 0.5 }, ok: true }
        ]);
        expect(near.marks.map(({ prefab }) => prefab)).toEqual(["rook", "knight"]);
    });
});

describe("an island on the map", () => {
    const TILE_IDS: Record<string, number> = { ".": 1, R: 2, G: 6, "~": 201 };
    const TILE_NAMES = new Map([[1, "IMPASSABLE"], [2, "ROAD"], [6, "GRASS"], [201, "OCEAN_COASTAL"]]);
    const ROWS = [
        "GG....",
        "G...R.",
        ".GG.R.",
        "..G..~",
        "G....G"
    ];
    const world = {
        prefabs: [],
        width: 6,
        height: 5,
        tileNames: TILE_NAMES,
        tiles: Uint16Array.from(ROWS.join(""), (cell) => TILE_IDS[cell])
    };
    const tile = (tx: number, ty: number) => ty * world.width + tx;
    const PORTAL_AT = at("multiplayer_portal", -12, -10);
    const witness = (landmasses: IslandsWitness["landmasses"]): IslandsWitness => ({
        section: "islands",
        index: 0,
        ok: true,
        area: landmasses.reduce((sum, { area }) => sum + area, 0),
        at: PORTAL_AT,
        tile: { tx: 0, ty: 0, x: -12, z: -10 },
        landmasses,
        bounds: { tx0: 0, ty0: 0, tx1: 1, ty1: 1 }
    });
    const ends = (segments: { from: { x: number; z: number }; to: { x: number; z: number } }[]) =>
        segments.map(({ from, to }) => [from.x, from.z, to.x, to.z]);

    it("floods a landmass up, down, left and right over land", () => {
        expect(landmassTiles(world, [{ tx: 0, ty: 0 }])).toEqual([tile(0, 0), tile(1, 0), tile(0, 1)]);
        expect(landmassTiles(world, [{ tx: 4, ty: 2 }])).toEqual([tile(4, 1), tile(4, 2)]);
    });

    it("doesn't join land that only touches at a corner", () => {
        expect(landmassTiles(world, [{ tx: 1, ty: 2 }])).toEqual([tile(1, 2), tile(2, 2), tile(2, 3)]);
        expect(landmassTiles(world, [{ tx: 5, ty: 4 }])).toEqual([tile(5, 4)]);
    });

    it("floods several landmasses at once, each tile once", () => {
        expect(landmassTiles(world, [{ tx: 0, ty: 0 }, { tx: 4, ty: 1 }, { tx: 1, ty: 0 }, { tx: 0, ty: 4 }]))
            .toEqual([tile(0, 0), tile(1, 0), tile(0, 1), tile(4, 1), tile(4, 2), tile(0, 4)]);
    });

    it("starts nowhere from water, an impassable tile or off the map", () => {
        const water = { tx: 5, ty: 3 };
        const impassable = { tx: 3, ty: 0 };
        expect(landmassTiles(world, [water, impassable, { tx: 6, ty: 0 }, { tx: 0, ty: 5 }])).toEqual([]);
    });

    it("outlines its landmass and marks the instance it was measured from", () => {
        const [shape] = witnessShapes([witness([{ tx: 0, ty: 0, area: 3 }])], undefined, world);
        expect(ends(shape.segments)).toEqual([
            [-14, -12, -6, -12],
            [-10, -8, -6, -8],
            [-14, -4, -10, -4],
            [-14, -12, -14, -4],
            [-10, -8, -10, -4],
            [-6, -12, -6, -8]
        ]);
        expect(shape.segments.every(({ ok, jump }) => ok && !jump)).toBe(true);
        expect(shape.marks).toEqual([{ prefab: "multiplayer_portal", at: { x: -12, z: -10 }, ok: true }]);
        expect(shape.focus).toEqual({ x: -12, z: -10 });
    });

    it("outlines every landmass the links reached", () => {
        const reached = witness([{ tx: 0, ty: 0, area: 3 }, { tx: 4, ty: 2, area: 2 }]);
        const [shape] = witnessShapes([reached], undefined, world);
        expect(ends(shape.segments)).toEqual([
            [-14, -12, -6, -12],
            [-10, -8, -6, -8],
            [2, -8, 6, -8],
            [-14, -4, -10, -4],
            [2, 0, 6, 0],
            [-14, -12, -14, -4],
            [-10, -8, -10, -4],
            [-6, -12, -6, -8],
            [2, -8, 2, 0],
            [6, -8, 6, 0]
        ]);
    });

    it("draws the box around its landmasses where the world has no land to flood", () => {
        const box = [[-14, -12, -6, -12], [-6, -12, -6, -4], [-6, -4, -14, -4], [-14, -4, -14, -12]];
        expect(ends(witnessShape(witness([{ tx: 0, ty: 0, area: 3 }])).segments)).toEqual(box);
        expect(ends(witnessShapes([witness([{ tx: 3, ty: 0, area: 3 }])], undefined, world)[0].segments)).toEqual(box);
    });

    it("draws nothing without an instance", () => {
        const none: IslandsWitness = { section: "islands", index: 0, ok: false, area: null, landmasses: [] };
        expect(witnessShapes([none], undefined, world)).toEqual([{ marks: [], segments: [], focus: null }]);
        expect(witnessShape(none)).toEqual({ marks: [], segments: [], focus: null });
    });
});
