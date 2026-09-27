import { describe, expect, it } from "vitest";
import { entityLayer, MAP_GROUPS, mapWorld } from "../lib/world-map/entity-layer";

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

describe("the entity layer", () => {
    it("leaves the spawn points out of the map's world, keeping the portal, the wormholes and the sinkholes", () => {
        const world = {
            prefabs: [
                prefab("spawnpoint_multiplayer", 0, 0, 100, 100),
                prefab("multiplayer_portal", 0, 0),
                prefab("spawnpoint_master", 0, 0),
                prefab("cave_entrance", 500, 0),
                ...WORLD.prefabs
            ],
            links: WORLD.links
        };
        const mapped = mapWorld(world);
        expect(mapped.prefabs.map(({ name }) => name))
            .toEqual(["multiplayer_portal", "cave_entrance", "evergreen", "wormhole", "pigking", "a_prefab_from_a_newer_game"]);
        expect(mapped.links).toBe(world.links);
    });

    it("places a dot for every entity at its world position, in its group or in other outside the catalog", () => {
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

    it("knows each dot's prefab", () => {
        const layer = entityLayer(WORLD);
        const named = [...layer.prefabs].map((prefab, dot) => [layer.names[prefab], rounded(layer.positions[2 * dot])]);
        expect(named).toEqual(expect.arrayContaining([
            ["evergreen", 1.5],
            ["wormhole", 8],
            ["pigking", 10],
            ["a_prefab_from_a_newer_game", 3]
        ]));
        expect(layer.prefabs).toHaveLength(8);
    });

    it("draws the groups listed first on top of the rest", () => {
        const order = [...new Set(dots(entityLayer(WORLD)).map(([group]) => group))];
        expect(order).toEqual(["other", "trees", "landmarks", "spawn & travel"]);
    });

    it("draws each wormhole link from its entry wormhole to its exit, in their group's colour and shown with them", () => {
        const { links, linkGroup, linkPrefab } = entityLayer(WORLD);
        expect([...links].map(rounded)).toEqual([0, 0, 8, -8, 8, -8, 0, 0, 12, 0.4, -0.6, -24, -0.6, -24, 12, 0.4]);
        expect(MAP_GROUPS[linkGroup].id).toBe("spawn & travel");
        expect(entityLayer(WORLD).names[linkPrefab]).toBe("wormhole");
    });

    it("gives every group its own colour", () => {
        expect(new Set(MAP_GROUPS.map(({ colour }) => colour.join()))).toHaveProperty("size", MAP_GROUPS.length);
    });
});
