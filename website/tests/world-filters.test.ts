import { describe, expect, it } from "vitest";
import { levelCatalogOf } from "@/lib/catalog/level-catalog";
import { dropsLevelTables, upgradeConfig } from "@/lib/config/upgrade-config";
import { validateConfig } from "@/lib/config/validate-config";
import {
    defaultState,
    droppedNotice,
    emptyFilter,
    fromSeedfinderConfig,
    LEVEL_TABLES_DROPPED_NOTICE,
    newRule,
    type SearchState,
    toSeedfinderConfig,
    validateSearch
} from "@/lib/criteria/search-state";
import { NEW_WORLD_ROW } from "@/lib/criteria/world-rules";

const forest = levelCatalogOf("forest");
const pigking = { from: "multiplayer_portal", to: "pigking", max: 600 };
const beefalo = { prefab: "beefalo", min: 25 };

const search = (): SearchState => {
    const state = defaultState();
    state.generation.rules = [{ ...newRule("MiscBoon", forest), min: 3 }];
    state.filters = [
        { ...emptyFilter(), distances: [{ ...NEW_WORLD_ROW.distances("forest"), to: ["pigking"], max: 600 }] },
        emptyFilter(),
        { ...emptyFilter(), counts: [{ ...NEW_WORLD_ROW.counts("forest"), prefabs: ["beefalo"], min: 25 }] }
    ];
    return state;
};

describe("a search's world generation and world filters", () => {
    it("writes the world generation once and each world filter with something picked", () => {
        const config = toSeedfinderConfig(search());
        expect(config.generation).toEqual({ setpieces: [{ required: { MiscBoon: 3 } }] });
        expect(config.filters).toEqual([
            { distances: [{ from: "multiplayer_portal", to: "pigking", max: 600 }] },
            { counts: [{ prefab: "beefalo", min: 25 }] }
        ]);
        expect(validateConfig(config).ok).toBe(true);
    });

    it("leaves out the filters when none has anything picked", () => {
        const state = search();
        state.filters = [emptyFilter(), emptyFilter()];
        expect(toSeedfinderConfig(state).filters).toBeUndefined();
    });

    it("labels each world filter's issues with its option", () => {
        const messages = validateSearch(search()).map((issue) => issue.message);
        expect(messages).toContain("Option 2: nothing picked, so it's ignored.");
    });

    it("warns when only world filters are picked, since every world gets generated", () => {
        const state = search();
        state.generation.rules = [];
        expect(validateSearch(state)[0]).toEqual({
            severity: "warning",
            message: expect.stringMatching(/^Only world filters are picked, so every seed's world gets generated/)
        });
    });

    it("rejects level-table sections in a filter like the finder", () => {
        expect(validateConfig({ filters: [{ tasks: { required: ["Killer bees!"] } }] })).toEqual({
            ok: false,
            error: "config: unknown key \"tasks\" in filters[0]"
        });
        expect(validateConfig({ criteria: [] })).toEqual({ ok: false, error: "config: unknown key \"criteria\" in the config" });
    });
});

describe("a v1 config", () => {
    const level = { setpieces: [{ required: { MiscBoon: 3 } }] };

    it("becomes the level table of its first entry that picks seeds, and one filter per entry", () => {
        const old = {
            version: 1,
            criteria: [{ passive: true, distances: [pigking] }, { ...level, counts: [beefalo] }]
        };
        expect(upgradeConfig(old)).toEqual({
            version: 2,
            generation: level,
            filters: [{ distances: [pigking] }, { counts: [beefalo] }]
        });
        expect(dropsLevelTables(old)).toBe(false);
        const upgraded = upgradeConfig(old) as object;
        expect(toSeedfinderConfig(fromSeedfinderConfig(old))).toEqual({ shard: "forest", platform: "windows", ...upgraded });
    });

    it("loses the level tables of entries that had other ones, and says so", () => {
        const old = { criteria: [{ ...level, counts: [beefalo] }, { tasks: { required: ["Killer bees!"] } }] };
        expect(upgradeConfig(old)).toEqual({ version: 2, generation: level, filters: [{ counts: [beefalo] }, {}] });
        expect(dropsLevelTables(old)).toBe(true);
        expect(droppedNotice(old)).toBe(LEVEL_TABLES_DROPPED_NOTICE);
    });

    it("without world rules has no filters, and is left alone once it's v2", () => {
        expect(upgradeConfig({ version: 1, settings: { boons: "default" }, criteria: [level] })).toEqual({ version: 2, generation: level });
        const current = { version: 2, generation: level };
        expect(upgradeConfig(current)).toEqual(current);
        expect(dropsLevelTables(current)).toBe(false);
    });
});
