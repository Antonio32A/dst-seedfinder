import { describe, expect, it } from "vitest";
import { parseWitnesses } from "../lib/jobs/job-result";
import { describeWitness } from "../lib/jobs/witness-text";

const at = (prefab: string, x: number, z: number) => ({ prefab, index: 0, x, z });

describe("a witness described", () => {
    it("names its rule and its figures", () => {
        expect(describeWitness({
            section: "distances",
            index: 1,
            ok: true,
            distance: 12,
            from: at("multiplayer_portal", 0, 0),
            to: at("pigking", 0, 12),
            wormholes: [{ entry: at("wormhole", 0, 1), exit: at("wormhole", 0, 11) }]
        })).toBe("Distance rule 2: multiplayer_portal -> pigking: 12 units (3 tiles), 1 wormhole jump");
        expect(describeWitness({
            section: "counts",
            index: 0,
            ok: false,
            count: 2,
            total: 3,
            instances: []
        })).toBe("Count rule 1: 2 of 3 nearby");
    });

    it("reads the caves' pillar jumps like wormhole jumps, in a distance and in a route's legs", () => {
        const jump = { entry: at("tentacle_pillar", 0, 1), exit: at("tentacle_pillar", 0, 11) };
        const [distance, route] = parseWitnesses([
            { section: "distances", index: 0, ok: true, distance: 12, from: at("cave_exit", 0, 0), to: at("atrium_gate", 0, 12), pillars: [jump] },
            { section: "routes", index: 1, ok: true, length: 12, stops: [], legs: [{ from: at("cave_exit", 0, 0), to: at("atrium_gate", 0, 12), distance: 12, pillars: [jump] }] }
        ]);
        expect(describeWitness(distance)).toBe("Distance rule 1: cave_exit -> atrium_gate: 12 units (3 tiles), 1 tentacle pillar jump");
        expect(route.section === "routes" && route.legs[0].wormholes).toEqual([jump]);
    });
});
