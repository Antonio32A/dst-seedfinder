import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { validateConfig } from "@/lib/config/validate-config";
import { emptyGroup, type SearchState, toSeedfinderConfig, validateSearch } from "@/lib/criteria/search-state";
import { parseOutputLine } from "@/lib/jobs/runner-output";
import { parseWorldEval } from "@/lib/world-map/search/world-eval";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const FINDER = `${ROOT}build/seedfinder`;
const DUMPS = `${ROOT}build/groundtruth/dstw_caves`;
const SEEDS = [1, 120];

const state: SearchState = {
    shard: "caves",
    platform: "linux",
    groups: [{
        ...emptyGroup(),
        counts: [{ key: "c", prefabs: ["rabbithouse"], mode: "atLeast", min: 30, max: 30, near: null }],
        distances: [{
            key: "d",
            from: ["cave_exit"],
            to: ["atrium_gate"],
            mode: "within",
            min: 0,
            max: 400,
            metric: "straight",
            links: true
        }]
    }]
};

/** The finder exits 1 when nothing matches, so only its output counts. */
const run = (...args: string[]) => spawnSync(FINDER, ["--threads", "2", "--", ...args], { encoding: "utf8" }).stdout;

const evaluate = (config: string, seed: number) =>
    parseWorldEval(run("world", "eval", "--config", config, "--world", `${DUMPS}/${seed}.dstw`, "--json").trim());

describe.skipIf(!existsSync(FINDER) || !existsSync(DUMPS))("a caves search with world criteria, from the website config through the finder", () => {
    const config = toSeedfinderConfig(state);
    const path = `${mkdtempSync(`${tmpdir()}/cave-world-`)}/search.json`;
    writeFileSync(path, JSON.stringify(config));
    const lines = run("world", "find", String(SEEDS[0]), String(SEEDS[1]), "--config", path, "--worlds", DUMPS, "--limit", "100").trim().split("\n").map(parseOutputLine);
    const hits = lines.flatMap((line) => (line?.kind === "hit" ? [line.hit] : []));

    it("is a valid search the site can send", () => {
        expect(validateSearch(state).filter((issue) => issue.severity === "error")).toEqual([]);
        expect(validateConfig(config).ok).toBe(true);
        expect(config.criteria?.[0].distances).toEqual([{ from: "cave_exit", to: "atrium_gate", max: 400, pillars: true }]);
    });

    it("prints hit lines the runner parses, with witnesses for the count and the pillar-link distance", () => {
        expect(lines.at(-1)?.kind).toBe("done");
        expect(hits.length).toBeGreaterThan(0);
        for (const hit of hits) {
            expect(hit.level.tasks).toHaveLength(41);
            expect(hit.results.map(({ section }) => section)).toEqual(["counts", "distances"]);
            expect(hit.results.every(({ ok }) => ok)).toBe(true);
        }
    });

    it("agrees with `world eval` on the real dumps, hit or not", () => {
        const hitSeeds = new Set(hits.map(({ seed }) => seed));
        const sample = [...hitSeeds].slice(0, 6).concat([2, 3, 4, 5, 6, 7, 8, 9].filter((seed) => !hitSeeds.has(seed)));
        for (const seed of sample) expect(evaluate(path, seed)?.matched, `seed ${seed}`).toBe(hitSeeds.has(seed));
    });
});
