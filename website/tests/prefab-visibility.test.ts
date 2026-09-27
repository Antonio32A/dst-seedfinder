import { describe, expect, it } from "vitest";
import type { SeedfinderConfig } from "../lib/config/seedfinder-config";
import { defaultShown, groupState, mapLegend, showPrefabs } from "../lib/world-map/prefab-visibility";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });

const WORLD = {
    prefabs: [
        prefab("evergreen", 150, -400, -1, 25),
        prefab("wormhole", 0, 0, 800, -800),
        prefab("deciduoustree", 1000, 2000),
        prefab("a_prefab_from_a_newer_game", 300, 300),
        prefab("multiplayer_portal", 0, 0)
    ]
};

const SPAWN_AND_TRAVEL = ["cave_entrance", "multiplayer_portal", "wormhole"];

const SEARCH: SeedfinderConfig = {
    version: 1,
    criteria: [
        {
            passive: true,
            tasks: { required: ["Killer bees!"] },
            setpieces: [{ required: { MooseNest: 1 } }],
            counts: [{ prefab: ["rook", "knight"], min: 1 }, {
                prefab: "beefalo",
                near: { prefab: "grass", within: 20 }
            }],
            distances: [{ from: "pigking", to: ["evergreen", "flower"], max: 50 }],
            tiles: [{ from: "GRASS", to: ["DECIDUOUS"], max: 30 }]
        },
        {
            routes: [{
                from: "moonbase",
                visit: ["walrus_camp", ["spiderden", "sapling"]],
                to: "cave_entrance",
                max: 5000
            }]
        }
    ]
};

describe("the map's legend", () => {
    it("lists the groups in the world, in legend order, each with its prefabs by name and their counts", () => {
        expect(mapLegend(WORLD).map(({ group, count, prefabs }) => [group.id, count, prefabs])).toEqual([
            ["spawn & travel", 3, [
                { prefab: "multiplayer_portal", displayName: "Spawn (Florid Postern)", count: 1 },
                { prefab: "wormhole", displayName: "Worm Hole", count: 2 }
            ]],
            ["trees", 3, [
                { prefab: "deciduoustree", displayName: "Birchnut Tree", count: 1 },
                { prefab: "evergreen", displayName: "Evergreen", count: 2 }
            ]],
            ["other", 1, [{
                prefab: "a_prefab_from_a_newer_game",
                displayName: "a_prefab_from_a_newer_game",
                count: 1
            }]]
        ]);
    });
});

describe("toggling the map's prefabs", () => {
    const trees = mapLegend(WORLD).find(({ group }) => group.id === "trees")!;

    it("shows a group on when all its prefabs are, off when none is, and mixed when only some are", () => {
        expect(groupState(trees, new Set(["evergreen", "deciduoustree", "wormhole"]))).toBe("on");
        expect(groupState(trees, new Set(["wormhole"]))).toBe("off");
        expect(groupState(trees, new Set(["evergreen", "wormhole"]))).toBe("mixed");
    });

    it("turns a group's prefabs, or one prefab, on or off and leaves the rest as they were", () => {
        const shown = new Set(["evergreen", "wormhole"]);
        const group = trees.prefabs.map(({ prefab }) => prefab);
        expect([...showPrefabs(shown, group, true)].sort()).toEqual(["deciduoustree", "evergreen", "wormhole"]);
        expect([...showPrefabs(shown, group, false)]).toEqual(["wormhole"]);
        expect([...showPrefabs(shown, ["wormhole"], false)]).toEqual(["evergreen"]);
        expect([...shown]).toEqual(["evergreen", "wormhole"]);
    });
});

describe("the prefabs a map shows", () => {
    it("starts with only the spawn & travel group, without the spawn points the map leaves out, without a search", () => {
        expect([...defaultShown()].sort()).toEqual(SPAWN_AND_TRAVEL);
    });

    it("also shows every prefab the search's counts, near filters, distances and routes name, in every option", () => {
        expect([...defaultShown(SEARCH)].sort()).toEqual([
            ...SPAWN_AND_TRAVEL, "beefalo", "evergreen", "flower", "grass", "knight", "moonbase", "pigking", "rook",
            "sapling", "spiderden", "walrus_camp"
        ].sort());
    });

    it("shows only the spawn & travel group for a search without world rules", () => {
        const levelOnly: SeedfinderConfig = { version: 1, criteria: [{ tasks: { required: ["Killer bees!"] } }] };
        expect([...defaultShown(levelOnly)].sort()).toEqual(SPAWN_AND_TRAVEL);
        expect([...defaultShown({ version: 1 })].sort()).toEqual(SPAWN_AND_TRAVEL);
    });
});
