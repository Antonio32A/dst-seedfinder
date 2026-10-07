import { describe, expect, it } from "vitest";
import { levelCatalogOf } from "@/lib/catalog/level-catalog";
import { validateConfig } from "@/lib/config/validate-config";
import {
    defaultState,
    fromSeedfinderConfig,
    newPieceGroup,
    newRule,
    type PieceRule,
    switchShard,
    toSeedfinderConfig,
    totalMax,
    validateSearch
} from "@/lib/criteria/search-state";
import { parseWitnesses } from "@/lib/jobs/job-result";
import { describeWitness } from "@/lib/jobs/witness-text";

const forest = levelCatalogOf("forest");

const grouped = (...rules: PieceRule[]) => ({ ...newPieceGroup(), rules });

describe("a set piece group", () => {
    const state = () => {
        const search = defaultState();
        search.groups[0].rules = [newRule("Level4Boon", forest)];
        search.groups[0].pieceGroups = [
            grouped({ ...newRule("MooseNest", forest), ensurePlaced: true }, newRule("Chessy_1", forest))
        ];
        return search;
    };

    it("writes `any` with one rule per set piece, after the other rules", () => {
        const config = toSeedfinderConfig(state());
        expect(config.criteria?.[0].setpieces).toEqual([
            { required: { Level4Boon: 1 } },
            { any: [{ required: { MooseNest: 1 }, placed: ["MooseNest"] }, { required: { Chessy_1: 1 } }] }
        ]);
        expect(validateConfig(config).ok).toBe(true);
        expect(validateSearch(state()).filter((issue) => issue.severity === "error")).toEqual([]);
    });

    it("reads back as a group", () => {
        const config = toSeedfinderConfig(state());
        const back = fromSeedfinderConfig(JSON.parse(JSON.stringify(config)));
        expect(back.groups[0].rules.map((rule) => rule.pieceId)).toEqual(["Level4Boon"]);
        expect(back.groups[0].pieceGroups.map((group) => group.rules.map((rule) => [rule.pieceId, rule.ensurePlaced])))
            .toEqual([[["MooseNest", true], ["Chessy_1", false]]]);
        expect(toSeedfinderConfig(back)).toEqual(config);
    });

    it("is left out while it's empty, with a warning", () => {
        const search = defaultState();
        search.groups[0].rules = [newRule("Level4Boon", forest)];
        search.groups[0].pieceGroups = [grouped()];
        expect(toSeedfinderConfig(search).criteria?.[0].setpieces).toEqual([{ required: { Level4Boon: 1 } }]);
        expect(validateSearch(search)).toContainEqual({
            severity: "warning",
            message: "A set piece group has no set pieces, so it's ignored."
        });
    });

    it("only warns about a pick that can never match, since the others still can", () => {
        const always = [...forest.setPieceById.values()].find((piece) => piece.alwaysPlaced);
        expect(always).toBeDefined();
        const search = defaultState();
        search.groups[0].pieceGroups = [grouped({ ...newRule(always!.id, forest), mode: "none" }, newRule("Chessy_1", forest))];
        const issues = validateSearch(search).filter((issue) => issue.message.includes("can never match"));
        expect(issues.map((issue) => issue.severity)).toEqual(["warning"]);
    });

    it("keeps its caves set pieces on a switch to the caves and drops the others", () => {
        const caves = levelCatalogOf("caves");
        const shared = [...caves.setPieceById.keys()].find((id) => forest.setPieceById.has(id));
        expect(shared).toBeDefined();
        const search = defaultState();
        search.groups[0].pieceGroups = [
            grouped({ ...newRule(shared!, forest), ensurePlaced: true }, newRule("MooseNest", forest)),
            grouped(newRule("MooseNest", forest))
        ];
        const { state: cave, dropped } = switchShard(search, "caves");
        expect(cave.groups[0].pieceGroups.map((group) => group.rules.map((rule) => [rule.pieceId, rule.ensurePlaced])))
            .toEqual([[[shared, false]]]);
        expect(dropped).toBe(3);
    });
});

describe("validating groups like the finder", () => {
    const config = (item: unknown) => ({ criteria: [{ setpieces: [item] }] });

    it("takes 1 to 16 rules and nothing else", () => {
        expect(validateConfig(config({ any: [{ required: { MooseNest: 1 } }] })).ok).toBe(true);
        expect(validateConfig(config({ any: [] }))).toEqual({
            ok: false,
            error: "config: criteria[0].setpieces[0].any must not be empty"
        });
        expect(validateConfig(config({ any: [{ any: [{}] }] }))).toEqual({
            ok: false,
            error: "config: unknown key \"any\" in criteria[0].setpieces[0].any[0]"
        });
        expect(validateConfig(config({ any: [{}], required: { MooseNest: 1 } }))).toEqual({
            ok: false,
            error: "config: unknown key \"required\" in criteria[0].setpieces[0]"
        });
        expect(validateConfig(config({ any: Array.from({ length: 17 }, () => ({})) }))).toEqual({
            ok: false,
            error: "config: criteria[0].setpieces[0].any has 17 rules (at most 16)"
        });
    });

    it("checks the `placed` names of its rules", () => {
        expect(validateConfig(config({ any: [{ required: { MooseNest: 1 }, placed: ["Chessy_1"] }] }))).toEqual({
            ok: false,
            error: "config: criteria[0].setpieces[0].any[0].placed names \"Chessy_1\", which isn't in required"
        });
    });
});

describe("the witness of a group", () => {
    it("lists its rules as alternatives, unlike the level table's result for it", () => {
        const witnesses = parseWitnesses([
            { section: "setpieces", index: 1, ok: true, any: [{ ok: true, counts: { MooseNest: 1 } }] },
            {
                section: "setpieces", index: 1, ok: true, any: [
                    { ok: false, counts: { MooseNest: 1 }, pieces: [{ name: "MooseNest", planned: 1, placed: 0 }] },
                    { ok: true, counts: { Chessy_1: 1 }, pieces: [] }
                ]
            }
        ]);
        expect(witnesses).toHaveLength(1);
        expect(describeWitness(witnesses[0])).toBe("Set piece rule 2: MooseNest 0 of 1 placed or Chessy_1 1 planned");
    });
});

describe("a set piece group with a total", () => {
    const canes = () => {
        const search = defaultState();
        search.groups[0].pieceGroups = [{
            ...grouped({ ...newRule("MiscBoon", forest), mode: "none" }, newRule("Level4Boon", forest)),
            match: "atLeast",
            min: 5
        }];
        return search;
    };

    it("writes `total` and leaves each set piece's own count at 0", () => {
        const config = toSeedfinderConfig(canes());
        expect(config.criteria?.[0].setpieces).toEqual([
            { any: [{ required: { MiscBoon: 0 } }, { required: { Level4Boon: 0 } }], total: 5 }
        ]);
        expect(validateConfig(config).ok).toBe(true);
        expect(validateSearch(canes())).toEqual([]);
    });

    it("reads back with its total", () => {
        const config = toSeedfinderConfig(canes());
        const back = fromSeedfinderConfig(JSON.parse(JSON.stringify(config)));
        expect(back.groups[0].pieceGroups.map(({ match, min }) => [match, min])).toEqual([["atLeast", 5]]);
        expect(toSeedfinderConfig(back)).toEqual(config);
    });

    it("caps the total at what a world can have of each kind", () => {
        const search = canes();
        search.groups[0].pieceGroups[0] = { ...search.groups[0].pieceGroups[0], match: "between", min: 3, max: 30 };
        expect(totalMax(search.groups[0].pieceGroups[0], forest)).toBe(8);
        expect(toSeedfinderConfig(search).criteria?.[0].setpieces?.[0]).toMatchObject({ total: [3, 8] });
    });

    it("is validated like a set piece bound", () => {
        const config = (item: unknown) => ({ criteria: [{ setpieces: [item] }] });
        expect(validateConfig(config({ any: [{}], total: [1] }))).toEqual({
            ok: false,
            error: "config: criteria[0].setpieces[0].total must be an integer in 0..4294967295 or [min, max]"
        });
        expect(validateConfig(config({ any: [{}], total: [1, 2] })).ok).toBe(true);
    });

    it("describes its world check with the sum", () => {
        const witnesses = parseWitnesses([{
            section: "setpieces", index: 0, ok: true, total: 5, any: [
                { ok: true, counts: { MiscBoon: 3 }, pieces: [] },
                { ok: true, counts: { Level4Boon: 2 }, pieces: [] }
            ]
        }]);
        expect(describeWitness(witnesses[0])).toBe("Set piece rule 1: MiscBoon 3 planned, Level4Boon 2 planned: 5 in total");
    });
});
