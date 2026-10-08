import { describe, expect, it } from "vitest";
import { levelCatalogOf } from "@/lib/catalog/level-catalog";
import { validateConfig } from "@/lib/config/validate-config";
import { parseWitnesses } from "@/lib/jobs/job-result";
import { describeWitness } from "@/lib/jobs/witness-text";
import {
    defaultState,
    fromSeedfinderConfig,
    newRule,
    switchShard,
    toSeedfinderConfig,
    validateSearch
} from "@/lib/criteria/search-state";

const forest = levelCatalogOf("forest");

const ensured = (pieceId: string) => ({ ...newRule(pieceId, forest), ensurePlaced: true });

describe("an ensure placed set piece", () => {
    const state = () => {
        const search = defaultState();
        search.generation.rules = [ensured("MooseNest"), newRule("MiscBoon", forest)];
        return search;
    };

    it("writes its name in its rule's `placed`, next to its bound", () => {
        const config = toSeedfinderConfig(state());
        expect(config.generation?.setpieces).toEqual([{ required: { MooseNest: 1, MiscBoon: 1 }, placed: ["MooseNest"] }]);
        expect(validateConfig(config).ok).toBe(true);
        expect(validateSearch(state()).filter((issue) => issue.severity === "error")).toEqual([]);
    });

    it("reads back checked", () => {
        const config = toSeedfinderConfig(state());
        const back = fromSeedfinderConfig(JSON.parse(JSON.stringify(config)));
        expect(back.generation.rules.map((rule) => [rule.pieceId, rule.ensurePlaced])).toEqual([["MooseNest", true], ["MiscBoon", false]]);
        expect(toSeedfinderConfig(back)).toEqual(config);
    });

    it("is dropped by a switch to the caves, which can't ensure placement", () => {
        const search = defaultState();
        search.generation.rules = [ensured("MiscBoon")];
        const { state: cave, dropped } = switchShard(search, "caves");
        expect(cave.generation.rules.map((rule) => [rule.pieceId, rule.ensurePlaced])).toEqual([["MiscBoon", false]]);
        expect(dropped).toBe(1);
        expect(toSeedfinderConfig(cave).generation?.setpieces).toEqual([{ required: { MiscBoon: 1 } }]);
    });
});

describe("validating `placed` like the finder", () => {
    const rule = (placed: unknown) => ({ generation: { setpieces: [{ required: { MooseNest: 1 }, placed }] } });

    it("only takes names of the rule's `required`, each once", () => {
        expect(validateConfig(rule(["Chessy_1"]))).toEqual({
            ok: false,
            error: "config: generation.setpieces[0].placed names \"Chessy_1\", which isn't in required"
        });
        expect(validateConfig(rule(["MooseNest", "MooseNest"]))).toEqual({
            ok: false,
            error: "config: generation.setpieces[0].placed names \"MooseNest\" twice"
        });
        expect(validateConfig(rule("MooseNest"))).toEqual({ ok: false, error: "config: generation.setpieces[0].placed must be a list" });
        expect(validateConfig(rule(["MooseNest"])).ok).toBe(true);
    });

    it("is unknown in the caves", () => {
        expect(validateConfig({ shard: "caves", generation: { setpieces: [{ required: { MiscBoon: 1 }, placed: ["MiscBoon"] }] } })).toEqual({
            ok: false,
            error: "config: unknown key \"placed\" in generation.setpieces[0]"
        });
    });
});

describe("the witness of a `placed` rule", () => {
    it("is a world check with the planned and placed copies, unlike the level table's set piece result", () => {
        const witnesses = parseWitnesses([
            { section: "setpieces", index: 0, ok: true, counts: { MooseNest: 7 } },
            { section: "setpieces", index: 0, ok: false, pieces: [{ name: "MooseNest", planned: 7, placed: 5 }] }
        ]);
        expect(witnesses).toEqual([{ section: "setpieces", index: 0, ok: false, pieces: [{ name: "MooseNest", planned: 7, placed: 5 }] }]);
        expect(describeWitness(witnesses[0])).toBe("Set piece rule 1: MooseNest 5 of 7 placed");
    });
});
