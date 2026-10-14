import { describe, expect, it } from "vitest";
import { levelCatalogOf } from "@/lib/catalog/level-catalog";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import { GAME_BUILDS, LATEST_BUILD, WEBSITE_BUILDS } from "@/lib/config/game-builds";
import { CONFIG_VERSION, LEGACY_CONFIG_BUILD } from "@/lib/config/seedfinder-config";
import { upgradeConfig } from "@/lib/config/upgrade-config";
import { validateConfig, validateJobRequest } from "@/lib/config/validate-config";
import {
    defaultState,
    fromSeedfinderConfig,
    newRule,
    switchBuild,
    toSeedfinderConfig
} from "@/lib/criteria/search-state";
import { NEW_WORLD_ROW } from "@/lib/criteria/world-rules";
import { MAP_PREVIEW_VERSION, mapPreviewPath, parseMapPreviewUrl } from "@/lib/world-map/map-preview-url";
import { dumpArgs } from "@/lib/world-map/world/world-dump";

const V3 = { version: 3, build: 756039 } as const;
const OLD_FORMAT = "is an old config format: use version 3 and set \"build\" to a game build (756039 for configs written before builds)";

describe("the build registry", () => {
    it("offers the latest build on the site", () => {
        expect(CONFIG_VERSION).toBe(3);
        expect(LEGACY_CONFIG_BUILD).toBe(756039);
        expect(GAME_BUILDS.map((build) => build.number)).toContain(LATEST_BUILD);
        expect(WEBSITE_BUILDS).toContain(LATEST_BUILD);
    });

    it("resolves every build's shards through the catalog its entry names", () => {
        expect(levelCatalogOf("forest", 757748)).toBe(levelCatalogOf("forest", 756039));
        expect(levelCatalogOf("caves", 757748)).toBe(levelCatalogOf("caves", 756039));
        expect(shardCatalog("forest", 757748)).toBe(shardCatalog("forest", 756039));
        expect(shardCatalog("caves", 757748).byId.has("batbosscave")).toBe(true);
        expect(shardCatalog("caves", 756039).byId.has("batbosscave")).toBe(false);
        expect(levelCatalogOf(undefined, 756039).shard).toBe("forest");
    });
});

describe("upgrading a config", () => {
    it.each([
        ["no version", {}],
        ["version 1", { version: 1 }],
        ["version 2", { version: 2 }]
    ])("makes one with %s a version 3 config for build 756039", (_, config) => {
        expect(upgradeConfig({ ...config, platform: "linux" })).toEqual({ ...V3, platform: "linux" });
    });

    it("writes a version 2 config's sections as they are and drops its settings", () => {
        const config = { version: 2, shard: "caves", settings: { boons: "default" }, filters: [{ bridges: [{ min: 10 }] }] };
        expect(upgradeConfig(config)).toEqual({ ...V3, shard: "caves", filters: [{ bridges: [{ min: 10 }] }] });
    });

    it.each([
        { ...V3, platform: "linux" },
        { version: 3, build: 757748, settings: { boons: "default" } },
        { version: 3 },
        { version: 4, build: 756039 },
        { version: "2" }
    ])("leaves %j as it is", (config) => {
        expect(upgradeConfig(config)).toBe(config);
    });
});

describe("validating a config's version and build", () => {
    it.each([
        [{ version: 1, build: 756039 }, `version 1 ${OLD_FORMAT}`],
        [{ version: 2 }, `version 2 ${OLD_FORMAT}`],
        [{ version: 4, build: 756039 }, "unsupported version 4"],
        [{ version: "3", build: 756039 }, "unsupported version \"3\""],
        [{ version: 3 }, "build is required (a game build: 756039 or 757748)"],
        [{}, "build is required (a game build: 756039 or 757748)"],
        [{ version: 3, build: 123 }, "unknown build 123 (756039 or 757748)"],
        [{ version: 3, build: "756039" }, "unknown build \"756039\" (756039 or 757748)"]
    ])("refuses %j like the finder", (config, error) => {
        expect(validateConfig(config)).toEqual({ ok: false, error: `config: ${error}` });
    });

    it("accepts a build by its number, on the shards it has", () => {
        expect(validateConfig({ version: 3, build: 757748 })).toEqual({
            ok: true,
            value: { version: 3, build: 757748, shard: "forest", platform: "windows" }
        });
        expect(validateConfig({ build: 756039, shard: "caves" })).toEqual({
            ok: true,
            value: { ...V3, shard: "caves", platform: "windows" }
        });
        expect(validateConfig({ version: 3, build: 757748, shard: "caves" })).toEqual({
            ok: true,
            value: { version: 3, build: 757748, shard: "caves", platform: "windows" }
        });
    });

    it("checks the names against the build's catalog", () => {
        const config = { version: 3, build: 757748, generation: { tasks: { required: ["Killer bees!"] } } };
        expect(validateConfig(config).ok).toBe(true);
        expect(validateConfig({ ...config, generation: { tasks: { required: ["MoreAltars"] } } })).toEqual({
            ok: false,
            error: "config: unknown task \"MoreAltars\" in generation.tasks.required"
        });
    });
});

describe("a search request from an old browser", () => {
    it.each([
        ["v2", { version: 2, platform: "linux", filters: [{ counts: [{ prefab: "pigking", min: 1 }] }] }],
        ["v1", { version: 1, platform: "linux", criteria: [{ counts: [{ prefab: "pigking", min: 1 }] }] }]
    ])("is accepted with its %s config as one for build 756039", (_, config) => {
        expect(validateJobRequest({ config, wanted: 1, maxCost: 20 })).toEqual({
            ok: true,
            value: {
                config: { ...V3, shard: "forest", platform: "linux", filters: [{ counts: [{ prefab: "pigking", min: 1 }] }] },
                wanted: 1,
                maxCost: 20
            }
        });
    });

    it("is refused when its config names a build the finder doesn't have", () => {
        expect(validateJobRequest({ config: { version: 3, build: 1 }, wanted: 1, maxCost: 20 }))
            .toEqual({ ok: false, error: "config: unknown build 1 (756039 or 757748)" });
    });
});

describe("a search's build", () => {
    const search = () => {
        const state = { ...defaultState(), build: 757748 as const };
        state.generation.rules = [newRule("MiscBoon", levelCatalogOf("forest", 757748))];
        state.filters[0].counts = [{ ...NEW_WORLD_ROW.counts(state), prefabs: ["pigking"] }];
        return state;
    };

    it("starts on the latest build", () => {
        expect(defaultState().build).toBe(LATEST_BUILD);
        expect(toSeedfinderConfig(defaultState())).toEqual({ ...V3, shard: "forest", platform: "windows" });
    });

    it("is written into its config and read back", () => {
        const config = toSeedfinderConfig(search());
        expect(config).toMatchObject({ version: 3, build: 757748 });
        expect(validateConfig(config).ok).toBe(true);
        const back = fromSeedfinderConfig(JSON.parse(JSON.stringify(config)));
        expect(back.build).toBe(757748);
        expect(toSeedfinderConfig(back)).toEqual(config);
    });

    it("is the build a legacy config was written for, or the latest when a config names an unknown one", () => {
        expect(fromSeedfinderConfig({ version: 2 }).build).toBe(756039);
        expect(fromSeedfinderConfig({ version: 3, build: 1 }).build).toBe(LATEST_BUILD);
    });

    it("keeps every pick the other build's catalog has when switching", () => {
        const state = search();
        const switched = switchBuild(state, 756039);
        expect(switched.dropped).toBe(0);
        expect(switched.state).toEqual({ ...state, build: 756039 });
        expect(switchBuild(state, 757748)).toEqual({ state, dropped: 0 });
    });
});

describe("a world dump", () => {
    it("is generated by the build it's for", () => {
        expect(dumpArgs(7, "linux", "caves", 756039)).toEqual(
            ["world", "dump", "7", "--platform", "linux", "--shard", "caves", "--build", "756039", "-o", "/world.dstw"]
        );
    });
});

describe("a map preview", () => {
    const preview = (path: string) => parseMapPreviewUrl(new URL(path, "https://example.com"));

    it("keeps the storage keys of build 756039's previews", () => {
        expect(MAP_PREVIEW_VERSION).toBe(1);
        for (const path of ["/og/map/linux/1234.png", "/og/map/linux/756039/1234.png", "/og/map/linux/forest/756039/1234.png"]) {
            expect(preview(path)).toEqual({
                platform: "linux",
                shard: "forest",
                build: 756039,
                seed: 1234,
                view: undefined,
                key: "previews/756039.1/linux/forest/1234/full.png",
                dumpKey: "dumps/756039.1/linux/forest/1234.dstw"
            });
        }
        expect(preview("/og/map/windows/caves/756039/7.png?v=1_2_300_45")).toMatchObject({
            key: "previews/756039.1/windows/caves/7/1_2_300_45.png",
            dumpKey: "dumps/756039.1/windows/caves/7.dstw"
        });
        expect(preview("/og/map/windows/caves/7.png")).toMatchObject({ key: "previews/756039.1/windows/caves/7/full.png" });
    });

    it("keeps another build's previews apart", () => {
        expect(preview("/og/map/linux/757748/1234.png")).toMatchObject({
            build: 757748,
            key: "previews/757748.1/linux/forest/1234/full.png",
            dumpKey: "dumps/757748.1/linux/forest/1234.dstw"
        });
    });

    it("is linked at its map's route with the build", () => {
        const world = { platform: "linux", shard: "caves", build: 756039, seed: 7 } as const;
        expect(mapPreviewPath(world)).toBe("/og/map/linux/caves/756039/7.png?r=756039.1");
        expect(mapPreviewPath({ ...world, shard: "forest", build: 757748 })).toBe("/og/map/linux/757748/7.png?r=757748.1");
        expect(preview(mapPreviewPath(world))).toMatchObject(world);
    });

    it.each([
        ["/og/map/linux/123/1234.png", /no build/],
        ["/og/map/linux/abc.png", /seed/],
        ["/og/map/linux/1234.jpg", /no map preview/]
    ])("is refused at %s", (path, error) => {
        expect(preview(path)).toEqual({ error: expect.stringMatching(error) });
    });
});
