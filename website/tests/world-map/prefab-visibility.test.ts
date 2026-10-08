import { describe, expect, it } from "vitest";
import { PREFAB_BY_ID, PREFABS } from "@/lib/catalog/world";
import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { MAP_GROUPS } from "@/lib/world-map/legend/entity-layer";
import {
    allPrefabs,
    defaultShown,
    groupState,
    type LegendGroup,
    mapLegend,
    showPrefabs
} from "@/lib/world-map/legend/prefab-visibility";

const prefab = (name: string, ...positions: number[]) => ({ name, positions: new Int32Array(positions) });

const WORLD = {
    prefabs: [
        prefab("evergreen", 150, -400, -1, 25),
        prefab("deciduoustree", 1000, 2000),
        prefab("a_prefab_from_a_newer_game", 300, 300),
        prefab("multiplayer_portal", 0, 0)
    ]
};

const SEARCH: SeedfinderConfig = {
    version: 2,
    generation: { tasks: { required: ["Killer bees!"] }, setpieces: [{ required: { MooseNest: 1 } }] },
    filters: [
        {
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
    const legend = mapLegend(WORLD);

    it("lists only the groups with entities, in legend order, with the unknown prefabs last under other", () => {
        const order = legend.map(({ group }) => MAP_GROUPS.findIndex(({ id }) => id === group.id));
        expect(order).toEqual([...order].sort((a, b) => a - b));
        expect(legend.at(-1)!.group.id).toBe("other");
        expect(legend.at(-1)!.prefabs).toEqual([
            { prefab: "a_prefab_from_a_newer_game", displayName: "a_prefab_from_a_newer_game", count: 1 }
        ]);
    });

    it("counts each group's entities and lists its prefabs by display name with their counts", () => {
        const evergreen = legend.flatMap(({ prefabs }) => prefabs).find(({ prefab }) => prefab === "evergreen");
        expect(evergreen?.count).toBe(2);
        expect(legend.reduce((sum, { count }) => sum + count, 0)).toBe(5);
        for (const { count, prefabs } of legend) {
            expect(prefabs.reduce((sum, entry) => sum + entry.count, 0)).toBe(count);
            const names = prefabs.map(({ displayName }) => displayName);
            expect(names).toEqual([...names].sort((a, b) => a.localeCompare(b)));
        }
    });
});

describe("toggling the map's prefabs", () => {
    const group = (...prefabs: string[]): LegendGroup => ({
        group: { id: "test", name: "Test", colour: [0, 0, 0] },
        count: prefabs.length,
        prefabs: prefabs.map((prefab) => ({ prefab, displayName: prefab, count: 1 }))
    });
    const trees = group("evergreen", "deciduoustree");

    it("shows a group on when all its prefabs are, off when none is, and mixed when only some are", () => {
        expect(groupState(trees, new Set(["evergreen", "deciduoustree", "wormhole"]))).toBe("on");
        expect(groupState(trees, new Set(["wormhole"]))).toBe("off");
        expect(groupState(trees, new Set(["evergreen", "wormhole"]))).toBe("mixed");
    });

    it("turns a group's prefabs, or one prefab, on or off and leaves the rest as they were", () => {
        const shown = new Set(["evergreen", "wormhole"]);
        const ids = trees.prefabs.map(({ prefab }) => prefab);
        expect([...showPrefabs(shown, ids, true)].sort()).toEqual(["deciduoustree", "evergreen", "wormhole"]);
        expect([...showPrefabs(shown, ids, false)]).toEqual(["wormhole"]);
        expect([...showPrefabs(shown, ["wormhole"], false)]).toEqual(["evergreen"]);
        expect([...shown]).toEqual(["evergreen", "wormhole"]);
    });
});

describe("the prefabs a map shows", () => {
    const UNDRAWN = PREFABS.find(({ defaultShown: drawn }) => !drawn)!.id;

    it("only starts with prefabs that have an icon", () => {
        const shown = defaultShown();
        expect(shown.size).toBeGreaterThan(0);
        expect([...shown].filter((prefab) => !PREFAB_BY_ID.get(prefab)?.icon)).toEqual([]);
    });

    it("also shows every prefab the search's counts, near filters, distances and routes name, in every option", () => {
        const named = ["beefalo", "evergreen", "flower", "grass", "knight", "moonbase", "pigking", "rook", "sapling", "spiderden", "walrus_camp"];
        expect(named.filter((prefab) => !defaultShown(SEARCH).has(prefab))).toEqual([]);
    });

    it("shows a named prefab although the game doesn't draw it", () => {
        const search: SeedfinderConfig = { version: 2, filters: [{ counts: [{ prefab: UNDRAWN, min: 1 }] }] };
        expect(defaultShown()).not.toContain(UNDRAWN);
        expect(defaultShown(search)).toContain(UNDRAWN);
    });

    it("shows the game's default for a search without world rules", () => {
        const levelOnly: SeedfinderConfig = { version: 2, generation: { tasks: { required: ["Killer bees!"] } } };
        expect(defaultShown(levelOnly)).toEqual(defaultShown());
        expect(defaultShown({ version: 2 })).toEqual(defaultShown());
    });
});

describe("allPrefabs", () => {
    it("holds every prefab of the legend and nothing for an empty one", () => {
        expect([...allPrefabs(mapLegend(WORLD))].sort()).toEqual(
            ["a_prefab_from_a_newer_game", "deciduoustree", "evergreen", "multiplayer_portal"]);
        expect(allPrefabs([]).size).toBe(0);
    });
});
