import { describe, expect, it } from "vitest";
import { parseWorldDump } from "../lib/world-map/world-dump";

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

const header = (seed: number, status: number, platform: number) =>
    [new TextEncoder().encode("DSTW"), u32(2), u32(seed), u32(status), u32(platform)];

const tiles = (ids: number[]) => {
    const padded = ids.length % 2 === 1 ? [...ids, 0] : ids;
    return new Uint8Array(new Uint16Array(padded).buffer);
};

const WIDTH = 3;
const HEIGHT = 1;

const world = (...extra: Uint8Array[]) => concat([
    ...header(1234, 1, 2),
    u32(747465),
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
        expect(dump).toMatchObject({ seed: 1234, platform: "linux", gameBuild: 747465 });
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

    it("skips a section it doesn't know", () => {
        const road = section("ROAD", [u32(3), i32(-7), u32(0xffffffff), ...text("TILE")]);
        expect(generated(world(road))).toEqual(generated(world()));
    });

    it("reads a world whose generation gave up from its 20-byte header", () => {
        expect(parseWorldDump(concat(header(99, 0, 1)))).toEqual({ status: "gave-up", seed: 99, platform: "windows" });
    });

    it("refuses a format 1 dump and a file that isn't a dump", () => {
        const v1 = concat([new TextEncoder().encode("DSTW"), u32(1), u32(1234), u32(1)]);
        expect(() => parseWorldDump(v1)).toThrow(/format 1/);
        expect(() => parseWorldDump(new TextEncoder().encode("{\"seed\": 1}"))).toThrow(/isn't a world dump/);
    });

    it("refuses a truncated dump", () => {
        const whole = world();
        expect(() => parseWorldDump(whole.subarray(0, whole.length - 4))).toThrow(/truncated/);
    });
});