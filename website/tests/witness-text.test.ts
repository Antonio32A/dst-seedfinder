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

    it("names a turf bridge's rooms by room and task, and says when there's none", () => {
        const [bridge, none] = parseWitnesses([
            {
                section: "bridges", index: 0, ok: true, length: 1241.781,
                from: { node: "CentipedeCaveTask:BG_89:BGVentsRoom", type: 2, x: -668, z: -358 },
                to: { node: "CentipedeCaveTask:8:VentsRoom", type: 0, x: 338, z: 370 },
                stray: "from"
            },
            { section: "bridges", index: 1, ok: false, length: null }
        ]);
        expect(bridge).toMatchObject({ stray: "from", from: { type: 2, x: -668 } });
        expect(describeWitness(bridge))
            .toBe("Turf bridge rule 1: BGVentsRoom (CentipedeCaveTask) -> VentsRoom (CentipedeCaveTask): 1,241.8 units (310.4 tiles)");
        expect(describeWitness(none)).toBe("Turf bridge rule 2: no bridge");
    });

    it("says how much land an island rule's instance can walk to, and how many landmasses the links join", () => {
        const portal = at("multiplayer_portal", -310, 522);
        const tile = { tx: 135, ty: 343, x: -310, z: 522 };
        const [alone, joined, none] = parseWitnesses([
            {
                section: "islands", index: 0, ok: true, area: 412, at: portal, tile,
                landmasses: [{ tx: 135, ty: 343, area: 412 }],
                bounds: { tx0: 120, ty0: 330, tx1: 150, ty1: 360 }
            },
            {
                section: "islands", index: 1, ok: false, area: 46200, at: portal, tile,
                landmasses: [
                    { tx: 135, ty: 343, area: 412 },
                    { tx: 200, ty: 200, area: 43000 },
                    { tx: 60, ty: 380, area: 2788 }
                ],
                bounds: { tx0: 12, ty0: 20, tx1: 410, ty1: 400 }
            },
            { section: "islands", index: 2, ok: false, area: null }
        ]);
        expect(alone).toMatchObject({
            at: portal,
            tile,
            landmasses: [{ tx: 135, ty: 343, area: 412 }],
            bounds: { tx0: 120, ty1: 360 }
        });
        expect(describeWitness(alone)).toBe("Island rule 1: multiplayer_portal on a landmass of 412 tiles");
        expect(describeWitness(joined))
            .toBe("Island rule 2: multiplayer_portal on 3 landmasses of 46,200 tiles in all, joined by wormholes");
        expect(describeWitness(joined, "caves"))
            .toBe("Island rule 2: multiplayer_portal on 3 landmasses of 46,200 tiles in all, joined by tentacle pillars");
        expect(none).toEqual({ section: "islands", index: 2, ok: false, area: null, landmasses: [] });
        expect(describeWitness(none)).toBe("Island rule 3: no instance");
    });

    it("drops an island witness without its area", () => {
        expect(parseWitnesses([{ section: "islands", index: 0, ok: true, landmasses: [] }])).toEqual([]);
    });
});
