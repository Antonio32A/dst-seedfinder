import { describe, expect, it } from "vitest";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { defaultShownSetPieces, setPieceDetails, setPieceLegend, setPieceName } from "@/lib/world-map/legend/set-pieces";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });

const piece = (name: string, xk: number, zk: number, half: number, members: number[] = []) => ({
    name,
    source: "task" as const,
    transform: 0,
    xk,
    zk,
    bounds: new Int32Array([xk - half, zk - half, xk + half, zk + half]),
    members: new Uint32Array(members)
});

const WORLD = {
    prefabs: [
        prefab("berrybush", 13900, -14300, 14100, -14500, -6100, 16900),
        prefab("evergreen", 13800, -14400, 50000, 50000),
        prefab("moose_nesting_ground", 14000, -14400, -6000, 16800),
        prefab("wormhole", 28400, -11600)
    ],
    setPieces: [
        piece("MooseNest", 14000, -14400, 800, [0, 0, 0, 1, 1, 0, 2, 0]),
        piece("WormholeGrass", 28400, -11600, 400, [3, 0]),
        piece("MooseNest", -6000, 16800, 800, [0, 2, 2, 1]),
        piece("moontrees_2", 38800, -54400, 800)
    ]
};

describe("the set pieces' legend", () => {
    it("is a set pieces group with one entry per layout name, by name, with how many times the world placed it", () => {
        const legend = setPieceLegend(WORLD)!;
        expect(legend.count).toBe(4);
        expect(legend.prefabs).toEqual([
            { prefab: "moontrees_2", displayName: "moontrees_2", count: 1 },
            { prefab: "MooseNest", displayName: "MooseNest", count: 2 },
            { prefab: "WormholeGrass", displayName: "WormholeGrass", count: 1 }
        ]);
    });

    it("is absent when the dump doesn't say where the set pieces are, and empty when the world placed none", () => {
        expect(setPieceLegend({})).toBeNull();
        expect(setPieceLegend({ setPieces: [] })).toBeNull();
    });
});

describe("the set pieces a map shows", () => {
    it("starts with none without a search, or with a search that names none", () => {
        expect([...defaultShownSetPieces()]).toEqual([]);
        expect([...defaultShownSetPieces({
            version: 2,
            filters: [{ counts: [{ prefab: "pigking", min: 1 }] }]
        })]).toEqual([]);
    });

    it("shows every set piece the search's set piece rules name, in groups too", () => {
        const search: SeedfinderConfig = {
            version: 2,
            generation: {
                setpieces: [
                    { tasks: ["Magic meadow"], required: { MooseNest: 1 } },
                    { required: { MiscBoon: [2, 8], Level4Boon: [0, 0] } },
                    { any: [{ required: { WormholeGrass: 2 } }, {}] }
                ]
            }
        };
        expect([...defaultShownSetPieces(search)].sort()).toEqual(["Level4Boon", "MiscBoon", "MooseNest", "WormholeGrass"]);
    });
});

describe("a set piece's details", () => {
    it("has its name, source, centre, size in tiles and members, per prefab with the most first", () => {
        expect(setPieceDetails(WORLD, 0)).toEqual({
            index: 0,
            name: "MooseNest",
            source: "task",
            x: 140,
            z: -144,
            width: 4,
            height: 4,
            transform: "none",
            members: [
                { prefab: "berrybush", displayName: "Berry Bush (regular)", count: 2 },
                { prefab: "evergreen", displayName: "Evergreen", count: 1 },
                { prefab: "moose_nesting_ground", displayName: expect.any(String), count: 1 }
            ]
        });
    });

    it("sizes a set piece by its bounds, which needn't be whole tiles", () => {
        const circle = piece("CropCircle", -50832, -9232, 368);
        expect(setPieceDetails({ ...WORLD, setPieces: [circle] }, 0)).toMatchObject({
            width: 1.84,
            height: 1.84,
            members: []
        });
    });
});

describe("the caves' maze names", () => {
    it("name the mazes after their task and the Labyrinth, and leave the rest and the forest alone", () => {
        expect(setPieceName("ArchiveMaze", "caves")).toBe("Ancient Archive (maze)");
        expect(setPieceName("Labyrinth", "caves")).toBe("The Labyrinth (maze)");
        expect(setPieceName("CaveStart", "caves")).toBe("CaveStart");
        expect(setPieceName("ArchiveMaze")).toBe("ArchiveMaze");
        const world = { ...WORLD, shard: "caves" as const, setPieces: [piece("ArchiveMaze", 0, 0, 800), piece("Labyrinth", 0, 0, 800)] };
        expect(setPieceLegend(world)!.prefabs.map(({ displayName }) => displayName)).toEqual(["Ancient Archive (maze)", "The Labyrinth (maze)"]);
    });
});
