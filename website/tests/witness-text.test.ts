import { describe, expect, it } from "vitest";
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
});
