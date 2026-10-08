import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { CAVE_OPTIONAL_TASK_IDS } from "@/lib/catalog/cave-vocab";
import { levelCatalogOf } from "@/lib/catalog/level-catalog";
import { validateConfig } from "@/lib/config/validate-config";
import { parseJobResult } from "@/lib/jobs/job-result";
import { parseOutputLine } from "@/lib/jobs/runner-output";
import {
    decodeShareParam,
    defaultState,
    emptyFilter,
    emptyGeneration,
    encodeShareParam,
    fromSeedfinderConfig,
    newRule,
    PRESETS,
    switchShard,
    toSeedfinderConfig,
    validateSearch
} from "@/lib/criteria/search-state";

const forest = levelCatalogOf("forest");
const caves = levelCatalogOf("caves");

describe("a search on the caves", () => {
    const search = (shard: "forest" | "caves") => ({ ...defaultState(), shard });

    it("carries the shard in its config", () => {
        expect(toSeedfinderConfig(search("caves")).shard).toBe("caves");
        expect(toSeedfinderConfig(defaultState()).shard).toBe("forest");
    });

    it("writes cave tasks and set pieces as the finder reads them", () => {
        const state = search("caves");
        state.generation.biomes = { MoreAltars: "include", SpiderLand: "exclude" };
        state.generation.swaps = { twigs: "twiggy trees" };
        state.generation.rules = [{ ...newRule("MiscBoon", caves), min: 2 }];
        const config = toSeedfinderConfig(state);
        expect(config.generation).toEqual({
            tasks: { required: ["MoreAltars"], excluded: ["SpiderLand"] },
            prefab_swaps: { twigs: "twiggy trees" },
            setpieces: [{ required: { MiscBoon: 2 } }]
        });
        expect(config.filters).toBeUndefined();
        expect(validateConfig(config).ok).toBe(true);
        expect(validateSearch(state).filter((issue) => issue.severity === "error")).toEqual([]);
    });

    it("reads a config back into the shard it names", () => {
        const back = fromSeedfinderConfig({ version: 1, shard: "caves", criteria: [{ tasks: { required: ["MoreAltars", "Great Plains"] } }] });
        expect(back.shard).toBe("caves");
        expect(back.generation.biomes).toEqual({ MoreAltars: "include" });
        expect(fromSeedfinderConfig({ version: 1 }).shard).toBe("forest");
    });

    it("allows at most eight biomes in a world, not five", () => {
        const state = search("caves");
        state.generation.biomes = Object.fromEntries(CAVE_OPTIONAL_TASK_IDS.slice(0, 6).map((id) => [id, "include" as const]));
        expect(validateSearch(state).some((issue) => issue.severity === "error")).toBe(false);
        state.generation.biomes = Object.fromEntries(CAVE_OPTIONAL_TASK_IDS.slice(0, 9).map((id) => [id, "include" as const]));
        expect(validateSearch(state).some((issue) => issue.severity === "error")).toBe(true);
    });
});

describe("switching shard", () => {
    it("keeps the resources both shards have and drops the rest", () => {
        const state = defaultState();
        state.generation.biomes = { "Killer bees!": "include" };
        state.generation.swaps = { grass: "grass gekko", twigs: "twiggy trees" };
        state.generation.rules = [newRule("MooseNest", forest), newRule("MiscBoon", forest)];
        const { state: cave, dropped } = switchShard(state, "caves");
        expect(cave.shard).toBe("caves");
        expect(cave.generation.biomes).toEqual({});
        expect(cave.generation.swaps).toEqual({ twigs: "twiggy trees" });
        expect(cave.generation.rules.map((rule) => rule.pieceId)).toEqual(["MiscBoon"]);
        expect(dropped).toBe(3);
    });

    it("does nothing when the shard is the same", () => {
        const state = defaultState();
        expect(switchShard(state, "forest")).toEqual({ state, dropped: 0 });
    });

    it("drops the world details whose prefabs the caves don't have", () => {
        const state = defaultState();
        state.filters[0].counts = [{ key: "a", prefabs: ["beefalo"], mode: "atLeast", min: 1, max: 1, near: null }];
        const { state: cave, dropped } = switchShard(state, "caves");
        expect(cave.filters[0].counts).toEqual([]);
        expect(dropped).toBe(1);
    });
});

describe("validating a config", () => {
    it("checks the tasks and set pieces against the shard the config names", () => {
        expect(validateConfig({ shard: "caves", generation: { tasks: { required: ["Great Plains"] } } })).toEqual({
            ok: false,
            error: "config: unknown task \"Great Plains\" in generation.tasks.required"
        });
        expect(validateConfig({ generation: { tasks: { required: ["MoreAltars"] } } })).toEqual({
            ok: false,
            error: "config: unknown task \"MoreAltars\" in generation.tasks.required"
        });
        expect(validateConfig({ shard: "caves", generation: { setpieces: [{ required: { CaveEntrance: 1 } }] } }).ok).toBe(false);
    });

    it("rejects an unknown shard like the finder", () => {
        expect(validateConfig({ shard: "nether" })).toEqual({ ok: false, error: "config: unknown shard \"nether\" (forest or caves)" });
    });

    it("has no gekko in the caves", () => {
        expect(validateConfig({ shard: "caves", generation: { prefab_swaps: { grass: "grass gekko" } } }).ok).toBe(false);
        expect(validateConfig({ shard: "caves", generation: { prefab_swaps: { grass: "regular grass" } } }).ok).toBe(true);
        expect(validateConfig({ generation: { prefab_swaps: { grass: "grass gekko" } } }).ok).toBe(true);
    });

    it("fills in the forest", () => {
        const checked = validateConfig({ version: 2 });
        expect(checked.ok && checked.value.shard).toBe("forest");
    });
});

describe("the output of a caves search", () => {
    const lines = readFileSync(fileURLToPath(new URL("./fixtures/caves-find.txt", import.meta.url)), "utf8").trim().split("\n");
    const parsed = lines.map(parseOutputLine);

    it("is read by the runner's output parser like a forest search's", () => {
        expect(parsed.map((line) => line?.kind)).toEqual(["hit", "hit", "done"]);
        const hit = parsed[0];
        expect(hit?.kind === "hit" && hit.hit.seed).toBe(3);
    });

    it("is a job result the site can show", () => {
        const hits = parsed.flatMap((line) => (line?.kind === "hit" ? [line.hit] : []));
        const result = parseJobResult({ version: 1, platform: "windows", hits, scanned: 9, last_scanned: 9, next_seed: 10, stopped: "limit" });
        expect(result?.kind === "search" && result.search.hits.map((hit) => hit.seed)).toEqual([3, 9]);
    });
});

describe("the world filters on the caves", () => {
    const caveGroup = () => ({
        ...emptyFilter(),
        counts: [{ key: "c", prefabs: ["rabbithouse"], mode: "atLeast" as const, min: 10, max: 10, near: null }],
        distances: [{
            key: "d",
            from: ["cave_exit"],
            to: ["minotaur_spawner"],
            mode: "within" as const,
            min: 0,
            max: 520,
            metric: "walk" as const,
            links: true
        }],
        routes: [{
            key: "r",
            from: ["cave_exit"],
            stops: [{ key: "s", prefabs: ["atrium_gate"] }],
            to: [],
            roundTrip: true,
            order: "any" as const,
            metric: "straight" as const,
            links: false,
            max: 2000
        }]
    });

    it("writes the pillar links as `pillars`, and the forest's as `wormholes`", () => {
        const config = toSeedfinderConfig({ shard: "caves", platform: "linux", generation: emptyGeneration(), filters: [caveGroup()] });
        expect(config.filters?.[0].distances).toEqual([{ from: "cave_exit", to: "minotaur_spawner", max: 520, metric: "walk", pillars: true }]);
        expect(config.filters?.[0].counts).toEqual([{ prefab: "rabbithouse", min: 10 }]);
        expect(config.filters?.[0].routes).toEqual([{ from: "cave_exit", visit: ["atrium_gate"], to: "cave_exit", max: 2000 }]);
        expect(validateConfig(config).ok).toBe(true);
        const forestRow = { ...caveGroup().distances[0], from: ["multiplayer_portal"], to: ["pigking"] };
        const forestConfig = toSeedfinderConfig({ shard: "forest", platform: "linux", generation: emptyGeneration(), filters: [{ ...emptyFilter(), distances: [forestRow] }] });
        expect(forestConfig.filters?.[0].distances?.[0]).toEqual({ from: "multiplayer_portal", to: "pigking", max: 520, metric: "walk", wormholes: true });
    });

    it("reads a saved caves config back with its rows and keeps the shard", () => {
        const config = toSeedfinderConfig({ shard: "caves", platform: "linux", generation: emptyGeneration(), filters: [caveGroup()] });
        const back = fromSeedfinderConfig(JSON.parse(JSON.stringify(config)));
        expect(back.shard).toBe("caves");
        expect(back.platform).toBe("linux");
        expect(back.filters[0].distances[0]).toMatchObject({ from: ["cave_exit"], to: ["minotaur_spawner"], metric: "walk", links: true });
        expect(toSeedfinderConfig(back)).toEqual(config);
        expect(toSeedfinderConfig(fromSeedfinderConfig(decodeShareParam(encodeShareParam(config))))).toEqual(config);
    });

    it("rejects the other shard's prefabs and link flag like the finder", () => {
        expect(validateConfig({ shard: "caves", filters: [{ counts: [{ prefab: "beefalo" }] }] })).toEqual({
            ok: false,
            error: "config: unknown prefab \"beefalo\" in filters[0].counts[0].prefab"
        });
        expect(validateConfig({ filters: [{ counts: [{ prefab: "cave_exit" }] }] })).toEqual({
            ok: false,
            error: "config: unknown prefab \"cave_exit\" in filters[0].counts[0].prefab"
        });
        expect(validateConfig({ shard: "caves", filters: [{ distances: [{ from: "cave_exit", to: "cave_hole", wormholes: true }] }] })).toEqual({
            ok: false,
            error: "config: unknown key \"wormholes\" in filters[0].distances[0]"
        });
        expect(validateConfig({ filters: [{ distances: [{ from: "pigking", to: "pigking", pillars: true }] }] }).ok).toBe(false);
        expect(validateConfig({ shard: "caves", filters: [{ distances: [{ from: "cave_exit", to: "cave_hole", pillars: true }] }] }).ok).toBe(true);
    });

    it("moves the rows to the other shard, the spawn becoming its spawn", () => {
        const state = { shard: "caves" as const, platform: "linux" as const, generation: emptyGeneration(), filters: [caveGroup()] };
        const forestState = switchShard(state, "forest");
        expect(forestState.state.shard).toBe("forest");
        expect(forestState.state.filters[0].counts).toEqual([]);
        expect(forestState.state.filters[0].distances).toEqual([]);
        expect(forestState.dropped).toBe(3);
        const shared = {
            ...emptyFilter(),
            distances: [{ ...caveGroup().distances[0], from: ["cave_exit"], to: ["bat", "minotaur_spawner"] }]
        };
        const moved = switchShard({ ...state, filters: [shared] }, "forest");
        expect(moved.state.filters[0].distances[0]).toMatchObject({ from: ["multiplayer_portal"], to: ["bat"], links: true });
    });

    it("keeps the prefabs both shards have", () => {
        const forestGroup = {
            ...emptyFilter(),
            distances: [{
                key: "d", from: ["multiplayer_portal"], to: ["bat", "pigking"], mode: "within" as const, min: 0, max: 100,
                metric: "straight" as const, links: false
            }]
        };
        const moved = switchShard({ ...defaultState(), filters: [forestGroup] }, "caves");
        expect(moved.state.filters[0].distances[0]).toMatchObject({ from: ["cave_exit"], metric: "straight" });
        expect(moved.state.filters[0].distances[0].to).toEqual(["bat"]);
        expect(moved.dropped).toBe(1);
    });

    it("has presets that are valid searches on their shard", () => {
        for (const shard of ["forest", "caves"] as const) {
            expect(PRESETS[shard].length).toBeGreaterThan(0);
            for (const preset of PRESETS[shard]) {
                const state = preset.build();
                expect(state.shard).toBe(shard);
                const config = toSeedfinderConfig(state);
                expect(validateConfig(config).ok, preset.id).toBe(true);
                expect(validateSearch(state).filter((issue) => issue.severity === "error"), preset.id).toEqual([]);
            }
        }
    });

    it("validates cave worlds the same way on both platforms", () => {
        const state = { shard: "caves" as const, platform: "windows" as const, generation: emptyGeneration(), filters: [caveGroup()] };
        expect(validateSearch(state)).toEqual(validateSearch({ ...state, platform: "linux" }));
    });
});

describe("the turf bridge rules", () => {
    const bridgeGroup = () => ({
        ...emptyFilter(),
        bridges: [{ key: "b", min: 240, max: null }, { key: "c", min: 0, max: 400 }, { key: "d", min: 100, max: 300 }]
    });

    it("writes a bridge's bounds as the finder reads them, leaving out a zero minimum and no maximum", () => {
        for (const shard of ["forest", "caves"] as const) {
            const config = toSeedfinderConfig({ shard, platform: "windows", generation: emptyGeneration(), filters: [bridgeGroup()] });
            expect(config.filters?.[0].bridges).toEqual([{ min: 240 }, { max: 400 }, { min: 100, max: 300 }]);
            expect(validateConfig(config).ok).toBe(true);
            expect(toSeedfinderConfig(fromSeedfinderConfig(JSON.parse(JSON.stringify(config))))).toEqual(config);
        }
    });

    it("keeps the bridges when switching shard", () => {
        const moved = switchShard({ shard: "caves", platform: "windows", generation: emptyGeneration(), filters: [bridgeGroup()] }, "forest");
        expect(moved.state.filters[0].bridges).toEqual(bridgeGroup().bridges);
        expect(moved.dropped).toBe(0);
    });

    it("rejects a bad bound like the finder", () => {
        expect(validateConfig({ shard: "caves", filters: [{ bridges: [{ min: -1 }] }] })).toEqual({
            ok: false,
            error: "config: filters[0].bridges[0].min must be a number in 0..1000000"
        });
        expect(validateConfig({ filters: [{ bridges: [{ max: 10, metric: "walk" }] }] })).toEqual({
            ok: false,
            error: "config: unknown key \"metric\" in filters[0].bridges[0]"
        });
    });

    it("says a bridge whose minimum is above its maximum can't match", () => {
        const group = { ...emptyFilter(), bridges: [{ key: "b", min: 500, max: 400 }] };
        expect(validateSearch({ shard: "caves", platform: "windows", generation: emptyGeneration(), filters: [group] })).toContainEqual({
            severity: "error",
            message: "Turf bridge 1: minimum is above maximum."
        });
    });
});
