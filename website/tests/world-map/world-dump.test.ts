import { describe, expect, it } from "vitest";
import { parseWorldDump } from "@/lib/world-map/world/world-dump";

const u32 = (value: number) => new Uint8Array(new Uint32Array([value]).buffer);

const i32 = (value: number) => new Uint8Array(new Int32Array([value]).buffer);

const text = (value: string) => {
    const bytes = new TextEncoder().encode(value);
    return [u32(bytes.length), bytes, new Uint8Array((4 - bytes.length % 4) % 4)];
};

const concat = (parts: Uint8Array[]) => {
    const out = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
    parts.reduce((offset, part) => (out.set(part, offset), offset + part.length), 0);
    return out;
};

const section = (tag: string, parts: Uint8Array[]) => {
    const payload = concat(parts);
    return concat([new TextEncoder().encode(tag), u32(payload.length), payload]);
};

const header = (seed: number, status: number, platform: number, shard = 0) =>
    [new TextEncoder().encode("DSTW"), u32(3), u32(seed), u32(status), u32(platform), u32(shard)];

const tiles = (ids: number[]) => {
    const padded = ids.length % 2 === 1 ? [...ids, 0] : ids;
    return new Uint8Array(new Uint16Array(padded).buffer);
};

const WIDTH = 3;
const HEIGHT = 1;

const world = (...extra: Uint8Array[]) => concat([
    ...header(1234, 1, 2),
    u32(756039),
    u32(WIDTH),
    u32(HEIGHT),
    section("TNAM", [u32(2), u32(6), ...text("GRASS"), u32(201), ...text("OCEAN_COASTAL")]),
    section("TILE", [tiles([6, 201, 6])]),
    ...extra,
    section("ENTS", [
        u32(2),
        ...text("evergreen"), u32(2), i32(150), i32(-400), i32(-1), i32(25),
        ...text("wormhole"), u32(2), i32(0), i32(0), i32(800), i32(-800)
    ]),
    section("WORM", [u32(2), u32(0), u32(1), u32(1), u32(0)])
]);

const generated = (bytes: Uint8Array) => {
    const dump = parseWorldDump(bytes);
    if (dump.status !== "generated") throw new Error(`expected a generated world, got ${dump.status}`);
    return dump;
};

describe("reading a world dump", () => {
    it("reads a generated world's header and tiles", () => {
        const dump = generated(world());
        expect(dump).toMatchObject({ seed: 1234, platform: "linux", shard: "forest", gameBuild: 756039 });
        expect([dump.width, dump.height]).toEqual([WIDTH, HEIGHT]);
        expect([...dump.tiles]).toEqual([6, 201, 6]);
        expect(dump.tileNames).toEqual(new Map([[6, "GRASS"], [201, "OCEAN_COASTAL"]]));
    });

    it("reads every prefab's instances as centi positions, in savedata order", () => {
        const dump = generated(world());
        expect(dump.prefabs.map(({ name, positions }) => [name, [...positions]])).toEqual([
            ["evergreen", [150, -400, -1, 25]],
            ["wormhole", [0, 0, 800, -800]]
        ]);
    });

    it("reads the wormhole links as entry and exit pairs", () => {
        const dump = generated(world());
        expect([...dump.links]).toEqual([0, 1, 1, 0]);
    });

    it("reads the placed set pieces with their centre, bounds, transform and members", () => {
        const pieces = section("SETP", [
            u32(2),
            ...text("MooseNest"), u32(1), u32(5), i32(800), i32(-400), i32(0), i32(-1200), i32(1600), i32(400),
            u32(2), u32(0), u32(1), u32(1), u32(0),
            ...text("OceanMonument"), u32(4), u32(0), i32(-60), i32(0), i32(-60), i32(0), i32(-60), i32(0), u32(0)
        ]);
        const dump = generated(concat([world(), pieces]));
        expect(dump.setPieces?.map(({ name, source, transform, xk, zk, bounds, members }) =>
            [name, source, transform, xk, zk, [...bounds], [...members]])).toEqual([
            ["MooseNest", "task", 5, 800, -400, [0, -1200, 1600, 400], [0, 1, 1, 0]],
            ["OceanMonument", "ocean-prefill", 0, -60, 0, [-60, 0, -60, 0], []]
        ]);
    });

    it("has no set pieces when the dump has no SETP section", () => {
        expect(generated(world())).not.toHaveProperty("setPieces");
    });

    it("names a source code it doesn't know unknown", () => {
        const pieces = section("SETP", [u32(1), ...text("Future"), u32(99), u32(0), ...Array.from({ length: 6 }, () => i32(0)), u32(0)]);
        expect(generated(concat([world(), pieces])).setPieces?.[0].source).toBe("unknown");
    });

    it("skips a section it doesn't know", () => {
        const unknown = section("FUTR", [u32(3), i32(-7), u32(0xffffffff), ...text("TILE")]);
        expect(generated(world(unknown))).toEqual(generated(world()));
    });

    it("reads the roads with their weight and control points, in savedata order", () => {
        const roads = section("ROAD", [
            u32(2),
            u32(3), u32(3), i32(-100), i32(200), i32(0), i32(0), i32(-2147483648), i32(2147483647),
            u32(1), u32(0)
        ]);
        const dump = generated(concat([world(), roads]));
        expect(dump.roads?.map(({ weight, points }) => [weight, [...points]])).toEqual([
            [3, [-100, 200, 0, 0, -2147483648, 2147483647]],
            [1, []]
        ]);
    });

    it("reads an empty ROAD section as no roads", () => {
        expect(generated(concat([world(), section("ROAD", [u32(0)])])).roads).toEqual([]);
    });

    it("has no roads when the dump has no ROAD section", () => {
        expect(generated(world())).not.toHaveProperty("roads");
    });

    it("refuses a ROAD section cut short inside its points", () => {
        const roads = section("ROAD", [u32(1), u32(3), u32(4), i32(1), i32(2)]);
        expect(() => generated(concat([world(), roads]))).toThrow(/truncated/);
    });

    it("reads the caves shard from the header", () => {
        const caves = concat([...header(1234, 1, 2, 1), u32(756039), u32(WIDTH), u32(HEIGHT)]);
        expect(generated(caves).shard).toBe("caves");
    });

    it("reads the tentacle pillar links as entry and exit prefab and instance quadruples", () => {
        const pillars = section("PILL", [u32(2), u32(1), u32(0), u32(1), u32(1), u32(1), u32(1), u32(1), u32(0)]);
        expect([...generated(concat([world(), pillars])).pillarLinks]).toEqual([1, 0, 1, 1, 1, 1, 1, 0]);
    });

    it("has no pillar links without a PILL section", () => {
        expect(generated(world()).pillarLinks).toHaveLength(0);
    });

    it("reads a world whose generation gave up from its 24-byte header", () => {
        expect(parseWorldDump(concat(header(99, 0, 1)))).toEqual({ status: "gave-up", seed: 99, platform: "windows", shard: "forest" });
    });

    it("refuses an unknown shard", () => {
        expect(() => parseWorldDump(concat(header(99, 0, 1, 7)))).toThrow(/unknown shard/);
    });

    it("refuses a format 1 or 2 dump and a file that isn't a dump", () => {
        const v1 = concat([new TextEncoder().encode("DSTW"), u32(1), u32(1234), u32(1)]);
        const v2 = concat([new TextEncoder().encode("DSTW"), u32(2), u32(1234), u32(0), u32(2)]);
        expect(() => parseWorldDump(v1)).toThrow(/format 1/);
        expect(() => parseWorldDump(v2)).toThrow(/format 2/);
        expect(() => parseWorldDump(new TextEncoder().encode("{\"seed\": 1}"))).toThrow(/isn't a world dump/);
    });

    it("refuses a truncated dump", () => {
        const whole = world();
        expect(() => parseWorldDump(whole.subarray(0, whole.length - 4))).toThrow(/truncated/);
    });
});