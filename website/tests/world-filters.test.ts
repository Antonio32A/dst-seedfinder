import { describe, expect, it } from "vitest";
import { levelCatalogOf } from "@/lib/catalog/level-catalog";
import { dropsLevelTables, upgradeConfig } from "@/lib/config/upgrade-config";
import { optionName } from "@/lib/config/seedfinder-config";
import { validateConfig } from "@/lib/config/validate-config";
import { parseJobResult } from "@/lib/jobs/job-result";
import { parseOutputLine } from "@/lib/jobs/runner-output";
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

describe("a world filter's name", () => {
    const named = (): SearchState => {
        const state = search();
        state.filters[0].name = "  Pig King ";
        state.filters[1].name = "Nothing";
        state.filters[2].name = " ";
        return state;
    };

    it("is written trimmed when set, and comes back", () => {
        const config = toSeedfinderConfig(named());
        expect(config.filters?.map((filter) => filter.name)).toEqual(["Pig King", undefined]);
        expect(validateConfig(config).ok).toBe(true);
        expect(fromSeedfinderConfig(config).filters.map((filter) => filter.name)).toEqual(["Pig King", ""]);
    });

    it("labels its option, which is otherwise numbered", () => {
        const messages = validateSearch(named()).map((issue) => issue.message);
        expect(messages).toContain("Nothing: nothing picked, so it's ignored.");
        expect(optionName({ name: "Pig King" }, 0)).toBe("Pig King");
        expect(optionName({ name: " " }, 2)).toBe("Option 3");
        expect(optionName(undefined, 1)).toBe("Option 2");
    });

    it("comes with the hits it matched, from the finder", () => {
        const level = { prefab_swaps: {}, tasks: [] };
        const parsed = parseJobResult({
            hits: [{ seed: 7, entry: 1, name: "Pig King", level, results: [] }, { seed: 9, entry: 0, level, results: [] }],
            last_scanned: 9,
            next_seed: 10
        });
        expect(parsed?.kind === "search" && parsed.search.hits.map((hit) => hit.name)).toEqual(["Pig King", undefined]);
        const line = parseOutputLine(`7 ${JSON.stringify({ entry: 1, name: "Pig King", level, results: [] })}`);
        expect(line?.kind === "hit" && line.hit.name).toBe("Pig King");
    });

    it("is a string of at most 40 characters like the finder's", () => {
        expect(validateConfig({ filters: [{ name: "🐷".repeat(40) }] }).ok).toBe(true);
        expect(validateConfig({ filters: [{ name: "🐷".repeat(41) }] })).toEqual({
            ok: false,
            error: "config: filters[0].name has 41 characters (at most 40)"
        });
        expect(validateConfig({ filters: [{ name: 1 }] })).toEqual({
            ok: false,
            error: "config: filters[0].name must be a string"
        });
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
