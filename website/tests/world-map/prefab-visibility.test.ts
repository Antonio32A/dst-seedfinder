import { describe, expect, it } from "vitest";
import { PREFAB_BY_ID, PREFABS } from "@/lib/catalog/world";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { allPrefabs, defaultShown, groupState, mapLegend, showPrefabs } from "@/lib/world-map/legend/prefab-visibility";

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
    const NEVER_DRAWN = [
        "antlion_spawner", "crabking_spawner", "seastack_spawner_rough", "seastack_spawner_swell",
        "wagstaff_machinery_marker", "waterplant_spawner_rough", "wobster_den_spawner_shore"
    ];

    it("starts with what the game's map draws, without a search", () => {
        const shown = defaultShown();
        const drawn = ["multiplayer_portal", "wormhole", "cave_entrance", "evergreen", "pigking", "seastack", "rock1", "pighouse"];
        expect(drawn.filter((prefab) => !shown.has(prefab))).toEqual([]);
        expect(shown.size).toBe(PREFABS.filter(({ defaultShown }) => defaultShown).length);
    });

    it("only shows prefabs that have an icon", () => {
        expect([...defaultShown()].filter((prefab) => !PREFAB_BY_ID.get(prefab)?.icon)).toEqual([]);
    });

    it("leaves out what the game draws nothing for at world start: spawner markers, unformed ice, spawn points and items", () => {
        const shown = defaultShown();
        const hidden = [...NEVER_DRAWN, "rock_ice", "spawnpoint_master", "spawnpoint_multiplayer", "log", "flint"];
        expect(hidden.filter((prefab) => shown.has(prefab))).toEqual([]);
    });

    it("also shows every prefab the search's counts, near filters, distances and routes name, in every option", () => {
        const named = ["beefalo", "evergreen", "flower", "grass", "knight", "moonbase", "pigking", "rook", "sapling", "spiderden", "walrus_camp"];
        expect([...defaultShown(SEARCH)].filter((prefab) => !defaultShown().has(prefab)).sort())
            .toEqual(named.filter((prefab) => !defaultShown().has(prefab)).sort());
        expect(named.filter((prefab) => !defaultShown(SEARCH).has(prefab))).toEqual([]);
    });

    it("shows a named spawner marker although the game doesn't draw it", () => {
        const spawners: SeedfinderConfig = { version: 1, criteria: [{ counts: [{ prefab: "antlion_spawner", min: 1 }] }] };
        expect(defaultShown(spawners)).toContain("antlion_spawner");
    });

    it("shows the game's default for a search without world rules", () => {
        const levelOnly: SeedfinderConfig = { version: 1, criteria: [{ tasks: { required: ["Killer bees!"] } }] };
        expect(defaultShown(levelOnly)).toEqual(defaultShown());
        expect(defaultShown({ version: 1 })).toEqual(defaultShown());
    });
});

describe("allPrefabs", () => {
    it("holds every prefab of the legend and nothing for an empty one", () => {
        expect([...allPrefabs(mapLegend(WORLD))].sort()).toEqual(
                ["a_prefab_from_a_newer_game", "deciduoustree", "evergreen", "multiplayer_portal", "wormhole"]);
        expect(allPrefabs([]).size).toBe(0);
    });
});
