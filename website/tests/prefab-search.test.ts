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

const setPiece = (name: string, xk: number, zk: number) => ({
    name,
    source: "task" as const,
    transform: 0,
    xk,
    zk,
    bounds: new Int32Array([xk - 800, zk - 800, xk + 800, zk + 800]),
    members: new Uint32Array(0)
});

const SET_WORLD = {
    ...WORLD,
    setPieces: [setPiece("MooseNest", 14000, -14400), setPiece("DefaultPigking", 1000, 2000), setPiece("MooseNest", -6000, 16800)]
};

describe("the prefab search", () => {
    it("finds the prefabs in the world by name or id, with how many instances each has", () => {
        expect(searchPrefabs(WORLD, "pig")).toEqual([
            { kind: "prefab", name: "pigking", displayName: "Pig King", count: 1 },
            { kind: "prefab", name: "pigtorch", displayName: "Pig Torch", count: 2 }
        ]);
        expect(searchPrefabs(WORLD, "WORM")).toEqual([{ kind: "prefab", name: "wormhole", displayName: "Worm Hole", count: 2 }]);
    });

    it("finds prefabs the catalog doesn't know, by their id", () => {
        expect(searchPrefabs(WORLD, "newer")).toEqual([
            { kind: "prefab", name: "a_prefab_from_a_newer_game", displayName: "a_prefab_from_a_newer_game", count: 2 }
        ]);
    });

    it("lists the names starting with the query first, then by name", () => {
        expect(searchPrefabs(WORLD, "e").map(({ name }) => name)).toEqual([
            "evergreen",
            "a_prefab_from_a_newer_game",
            "wormhole"
        ]);
    });

    it("gives a prefab's instances in savedata order", () => {
        expect(instancesOf(WORLD, { kind: "prefab", name: "evergreen" }))
                .toEqual([{ x: 1.5, z: -4 }, { x: -0.01, z: 0.25 }, { x: 30, z: 30 }]);
        expect(instancesOf(WORLD, { kind: "prefab", name: "not_in_this_world" })).toEqual([]);
    });

    it("finds the set pieces in the world by layout name, after the prefabs that start with the query", () => {
        expect(searchPrefabs(SET_WORLD, "pig")).toEqual([
            { kind: "prefab", name: "pigking", displayName: "Pig King", count: 1 },
            { kind: "prefab", name: "pigtorch", displayName: "Pig Torch", count: 2 },
            { kind: "set piece", name: "DefaultPigking", displayName: "DefaultPigking", count: 1 }
        ]);
        expect(searchPrefabs(SET_WORLD, "moose")).toEqual([{ kind: "set piece", name: "MooseNest", displayName: "MooseNest", count: 2 }]);
        expect(searchPrefabs(WORLD, "moose")).toEqual([]);
    });

    it("gives a set piece's instances at their centres, in placement order", () => {
        expect(instancesOf(SET_WORLD, { kind: "set piece", name: "MooseNest" })).toEqual([{ x: 140, z: -144 }, { x: -60, z: 168 }]);
        expect(instancesOf(WORLD, { kind: "set piece", name: "MooseNest" })).toEqual([]);
    });

    it("cycles through every instance in savedata order, forwards from the first and backwards from the last", () => {
        const visit = (step: number) => Array.from({ length: 4 }).reduce<number[]>((visited) =>
                [...visited, stepInstance(visited.at(-1) ?? null, 3, step)], []);
        expect(visit(1)).toEqual([0, 1, 2, 0]);
        expect(visit(-1)).toEqual([2, 1, 0, 2]);
    });
});
