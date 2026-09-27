import { beforeAll, describe, expect, it } from "vitest";
import { api, chunkedBody, db, SEARCH_REQUEST, type SignedIn, signIn, useWorker } from "./harness";

useWorker();

const MAX_BODY_BYTES = 512 * 1024;
const JSON_TYPE = { "Content-Type": "application/json" };

interface Ledger {
    jobs: number;
    credits: number;
}

async function ledger(userId: string): Promise<Ledger> {
    const row = await db()
        .prepare("SELECT (SELECT COUNT(*) FROM jobs WHERE user_id = ?1) AS jobs, credit_units AS credits FROM users WHERE id = ?1")
        .bind(userId)
        .first<Ledger>();
    return row as Ledger;
}

describe("POST /api/jobs", () => {
    let user: SignedIn;

    beforeAll(async () => {
        user = await signIn();
    });

    const refusals = [
        { name: "a streamed body over the limit", status: 413, headers: JSON_TYPE, body: () => chunkedBody(MAX_BODY_BYTES + 1) },
        { name: "a buffered body over the limit", status: 413, headers: JSON_TYPE, body: () => " ".repeat(MAX_BODY_BYTES + 1) },
        { name: "no Content-Type", status: 415, headers: {}, body: () => new TextEncoder().encode(JSON.stringify(SEARCH_REQUEST)) },
        { name: "Content-Type: text/plain", status: 415, headers: { "Content-Type": "text/plain" }, body: () => JSON.stringify(SEARCH_REQUEST) },
        {
            name: "a form body",
            status: 415,
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: () => new URLSearchParams({ config: "{}" }).toString()
        }
    ];

    it.each(refusals)("refuses $name with $status, reserving nothing", async ({ status, headers, body }) => {
        const before = await ledger(user.profile.id);
        const response = await api("/api/jobs", { method: "POST", session: user.session, headers, body: body() });
        expect(response.status).toBe(status);
        expect(await response.json()).toEqual({ error: expect.any(String) });
        expect(await ledger(user.profile.id)).toEqual(before);
    });

    it("accepts JSON with a charset", async () => {
        const response = await api("/api/jobs", {
            method: "POST",
            session: user.session,
            headers: { "Content-Type": "application/json; charset=utf-8" },
            body: JSON.stringify(SEARCH_REQUEST)
        });
        expect(response.status).toBe(201);
        expect((await ledger(user.profile.id)).jobs).toBe(1);
    });
});
