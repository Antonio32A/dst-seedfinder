import { describe, expect, it } from "vitest";
import { entityLayer, groupOf, MAP_GROUPS, mapWorld } from "@/lib/world-map/legend/entity-layer";

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

const dots = ({ positions, prefabs, names }: ReturnType<typeof entityLayer>) => [...prefabs].map((prefab, index) => [
    names[prefab],
    rounded(positions[2 * index]),
    rounded(positions[2 * index + 1])
]);

describe("the entity layer", () => {
    it("leaves the spawn points out of the map's world, keeping the portal and the rest", () => {
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

    it("keeps the set pieces' members on their prefabs in the map's world, without the spawn points", () => {
        const start = {
            name: "DefaultStart",
            source: "start" as const,
            transform: 0,
            xk: 0,
            zk: 0,
            bounds: new Int32Array([-800, -800, 800, 800]),
            members: new Uint32Array([0, 0, 1, 0, 2, 0, 4, 1])
        };
        const world = {
            prefabs: [
                prefab("multiplayer_portal", 0, 0),
                prefab("spawnpoint_master", 0, 0),
                prefab("spawnpoint_multiplayer", 0, 0),
                ...WORLD.prefabs
            ],
            setPieces: [start]
        };
        const mapped = mapWorld(world);
        expect(mapped.setPieces).toEqual([{ ...start, members: new Uint32Array([0, 0, 2, 1]) }]);
        expect(mapWorld({ ...WORLD, setPieces: undefined }).setPieces).toBeUndefined();
    });

    it("places a dot for every entity at its world position, in its group or in other outside the catalog", () => {
        const layer = entityLayer(WORLD);
        expect(dots(layer)).toEqual(expect.arrayContaining([
            ["evergreen", 1.5, -4],
            ["evergreen", -0.01, 0.25],
            ["wormhole", 0, 0],
            ["wormhole", 8, -8],
            ["wormhole", 12, 0.4],
            ["wormhole", -0.6, -24],
            ["pigking", 10, 20],
            ["a_prefab_from_a_newer_game", 3, 3]
        ]));
        expect(layer.groups).toHaveLength(8);
        for (const [index, group] of layer.groups.entries()) {
            expect(group).toBe(groupOf(layer.names[layer.prefabs[index]]));
        }
        expect(MAP_GROUPS[groupOf("a_prefab_from_a_newer_game")].id).toBe("other");
    });

    it("draws the groups listed first on top of the rest", () => {
        const { groups } = entityLayer(WORLD);
        expect([...groups]).toEqual([...groups].sort((a, b) => b - a));
    });

    it("draws each wormhole link from its entry wormhole to its exit, in their group's colour", () => {
        const { links, linkGroup } = entityLayer(WORLD);
        expect([...links].map(rounded)).toEqual([0, 0, 8, -8, 8, -8, 0, 0, 12, 0.4, -0.6, -24, -0.6, -24, 12, 0.4]);
        expect(linkGroup).toBe(groupOf("wormhole"));
    });
});
