import { describe, expect, it } from "vitest";
import { instancesOf, searchPrefabs, stepInstance } from "../lib/world-map/prefab-search";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });

const WORLD = {
    prefabs: [
        prefab("a_prefab_from_a_newer_game", 300, 300, 400, 400),
        prefab("evergreen", 150, -400, -1, 25, 3000, 3000),
        prefab("pigking", 1000, 2000),
        prefab("pigtorch", 0, 0, 100, 100),
        prefab("wormhole", 0, 0, 800, -800)
    ]
};

describe("the prefab search", () => {
    it("finds the prefabs in the world by name or id, with how many instances each has", () => {
        expect(searchPrefabs(WORLD, "pig")).toEqual([
            { prefab: "pigking", displayName: "Pig King", count: 1 },
            { prefab: "pigtorch", displayName: "Pig Torch", count: 2 }
        ]);
        expect(searchPrefabs(WORLD, "WORM")).toEqual([{ prefab: "wormhole", displayName: "Worm Hole", count: 2 }]);
    });

    it("finds prefabs the catalog doesn't know, by their id", () => {
        expect(searchPrefabs(WORLD, "newer")).toEqual([
            { prefab: "a_prefab_from_a_newer_game", displayName: "a_prefab_from_a_newer_game", count: 2 }
        ]);
    });

    it("lists the names starting with the query first, then by name", () => {
        expect(searchPrefabs(WORLD, "e").map(({ prefab }) => prefab)).toEqual([
            "evergreen",
            "a_prefab_from_a_newer_game",
            "wormhole"
        ]);
    });

    it("gives a prefab's instances in savedata order", () => {
        expect(instancesOf(WORLD, "evergreen")).toEqual([{ x: 1.5, z: -4 }, { x: -0.01, z: 0.25 }, { x: 30, z: 30 }]);
        expect(instancesOf(WORLD, "not_in_this_world")).toEqual([]);
    });

    it("cycles through every instance in savedata order, forwards from the first and backwards from the last", () => {
        const visit = (step: number) => Array.from({ length: 4 }).reduce<number[]>((visited) =>
                [...visited, stepInstance(visited.at(-1) ?? null, 3, step)], []);
        expect(visit(1)).toEqual([0, 1, 2, 0]);
        expect(visit(-1)).toEqual([2, 1, 0, 2]);
    });
});
