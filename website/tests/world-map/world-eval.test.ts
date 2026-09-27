import { describe, expect, it } from "vitest";
import { parseWorldEval } from "@/lib/world-map/search/world-eval";

const PORTAL = { prefab: "multiplayer_portal", index: 0, x: 46, z: 402 };
const PIGKING = { prefab: "pigking", index: 0, x: -512, z: -120 };

const TASKS = { section: "tasks", index: 0, ok: true };
const COUNT = { section: "counts", index: 0, ok: false, count: 0, instances: [] };
const DISTANCE = {
    section: "distances",
    index: 0,
    ok: true,
    distance: 822.774,
    from: PORTAL,
    to: PIGKING,
    wormholes: []
};

const output = (fields: object) => `1 ${JSON.stringify({ platform: "linux", ...fields })}`;

describe("a world's evaluation", () => {
    it("shows the world checks of the first entry that holds, like a search hit", () => {
        const evaluation = parseWorldEval(output({
            match: true,
            entries: [{ ok: false, results: [COUNT] }, { ok: true, results: [TASKS, DISTANCE] }],
            matched_entries: [1]
        }));
        expect(evaluation).toEqual({ matched: true, entry: 1, entries: 2, witnesses: [DISTANCE] });
    });

    it("shows the first entry's checks when none holds", () => {
        const evaluation = parseWorldEval(output({
            match: false,
            entries: [{ ok: false, results: [COUNT] }, { ok: false, results: [DISTANCE] }],
            matched_entries: []
        }));
        expect(evaluation).toEqual({ matched: false, entry: 0, entries: 2, witnesses: [COUNT] });
    });

    it.each(["", "1 not json", "1 {\"entries\":[]}"])("isn't read from %j", (line) => {
        expect(parseWorldEval(line)).toBeNull();
    });
});
