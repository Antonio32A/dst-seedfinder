import { describe, expect, it } from "vitest";
import { entityLayer, MAP_GROUPS } from "../lib/world-map/entity-layer";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });

const WORLD = {
    prefabs: [
        prefab("evergreen", 150, -400, -1, 25),
        prefab("wormhole", 0, 0, 800, -800, 1200, 40, -60, -2400),
        prefab("pigking", 1000, 2000),
        prefab("a_prefab_from_a_newer_game", 300, 300)
    ],
    links: new Uint32Array([0, 1, 1, 0, 2, 3, 3, 2])
};

const rounded = (value: number) => Math.round(value * 1e4) / 1e4;

const dots = ({ positions, groups }: ReturnType<typeof entityLayer>) => [...groups].map((group, index) => [
    MAP_GROUPS[group].id,
    rounded(positions[2 * index]),
    rounded(positions[2 * index + 1])
]);

const countOf = (counts: readonly number[], id: string) =>
    counts[MAP_GROUPS.findIndex((group) => group.id === id)];

describe("the entity layer", () => {
    it("counts every entity in its catalog group", () => {
        const { counts } = entityLayer(WORLD);
        expect(countOf(counts, "trees")).toBe(2);
        expect(countOf(counts, "spawn & travel")).toBe(4);
        expect(countOf(counts, "landmarks")).toBe(1);
        expect(counts.reduce((total, count) => total + count, 0)).toBe(8);
    });

    it("puts a prefab the catalog doesn't know in the other group", () => {
        expect(countOf(entityLayer(WORLD).counts, "other")).toBe(1);
    });

    it("places a dot for every entity at its world position", () => {
        expect(dots(entityLayer(WORLD))).toEqual(expect.arrayContaining([
            ["trees", 1.5, -4],
            ["trees", -0.01, 0.25],
            ["spawn & travel", 0, 0],
            ["spawn & travel", 8, -8],
            ["spawn & travel", 12, 0.4],
            ["spawn & travel", -0.6, -24],
            ["landmarks", 10, 20],
            ["other", 3, 3]
        ]));
        expect(entityLayer(WORLD).groups).toHaveLength(8);
    });

    it("draws the groups listed first on top of the rest", () => {
        const order = [...new Set(dots(entityLayer(WORLD)).map(([group]) => group))];
        expect(order).toEqual(["other", "trees", "landmarks", "spawn & travel"]);
    });

    it("draws each wormhole link from its entry wormhole to its exit, shown with the wormholes' group", () => {
        const { links, linkGroup } = entityLayer(WORLD);
        expect([...links].map(rounded)).toEqual([0, 0, 8, -8, 8, -8, 0, 0, 12, 0.4, -0.6, -24, -0.6, -24, 12, 0.4]);
        expect(MAP_GROUPS[linkGroup].id).toBe("spawn & travel");
    });

    it("gives every group its own colour", () => {
        expect(new Set(MAP_GROUPS.map(({ colour }) => colour.join()))).toHaveProperty("size", MAP_GROUPS.length);
    });
});
