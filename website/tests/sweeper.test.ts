import { http, HttpResponse } from "msw";
import { beforeAll, describe, expect, it } from "vitest";
import type { JobRow } from "@/lib/server/jobs/jobs";
import { db, loadJob, network, seedJob, signIn, startSearch, until, useWorker, VAST_API, worker } from "./harness";

useWorker();

const MINUTE = 60_000;
const MACHINE = JSON.stringify({ cpuName: "Test CPU", cores: 64, ghz: 3, dollarsPerHour: 0.2 });
const label = (jobId: string) => `dst-seedfinder:${jobId}`;

async function credits(userId: string): Promise<number> {
    return (await db().prepare("SELECT credit_units FROM users WHERE id = ?").bind(userId).first<{
        credit_units: number
    }>())?.credit_units ?? 0;
}

async function reserve(userId: string, units: number): Promise<void> {
    await db().prepare("UPDATE users SET credit_units = credit_units - ? WHERE id = ?").bind(units, userId).run();
}

describe("the cron sweep", () => {
    const destroyed: string[] = [];
    const rows = new Map<string, JobRow | null>();
    let owner: string;
    let creditsBefore: number;
    let stuck: string;
    let lost: string;
    let healthy: string;
    let othersLive: string;
    let othersFinished: string;

    beforeAll(async () => {
        const user = await signIn();
        const other = await signIn();
        owner = user.profile.id;
        healthy = (await startSearch(user.session)).id;
        othersLive = (await startSearch(other.session)).id;
        othersFinished = await seedJob(other.profile.id);
        const now = Date.now();
        stuck = await seedJob(owner, {
            status: "running",
            max_cost: 20000,
            cost: null,
            finished_at: null,
            started_at: now - 7 * 24 * 60 * MINUTE,
            updated_at: now - 60 * MINUTE,
            machine: MACHINE
        });
        lost = await seedJob(owner, {
            status: "queued",
            cost: null,
            finished_at: null,
            max_cost: 5000,
            updated_at: now - 6 * MINUTE
        });
        await reserve(owner, 20000 + 5000);
        creditsBefore = await credits(owner);
        for (const id of [healthy, othersLive, othersFinished]) rows.set(id, await loadJob(id));

        const instances = [{ id: 7001, label: label(stuck) }, { id: 7002, label: label(healthy) }, {
            id: 7003,
            label: label(othersLive)
        }];
        network.use(
            http.get(`${VAST_API}/v1/instances`, ({ request }) => {
                const filter = new URL(request.url).searchParams.get("select_filters");
                const wanted = filter === null ? null : (JSON.parse(filter) as { label: { eq: string } }).label.eq;
                return HttpResponse.json({ instances: instances.filter((instance) => wanted === null || instance.label === wanted) });
            }),
            http.delete(`${VAST_API}/v0/instances/:id/`, ({ params }) => {
                destroyed.push(String(params.id));
                return HttpResponse.json({ success: true });
            })
        );
        const result = await worker().scheduled({ cron: "*/5 * * * *", scheduledTime: new Date() });
        expect(result.outcome).toBe("ok");
        await until(async () => (await loadJob(stuck))?.cost !== null && (await loadJob(lost))?.cost !== null);
    });

    it("stops a search stuck past its deadline and destroys its machine", async () => {
        expect(await loadJob(stuck)).toMatchObject({
            status: "failed",
            error: "The search got stuck and was stopped. Unused credits were refunded."
        });
        expect(destroyed).toContain("7001");
    });

    it("settles a quiet search whose room is gone, free", async () => {
        expect(await loadJob(lost)).toMatchObject({
            status: "failed",
            cost: 0,
            error: "The search was lost. Your credits were refunded."
        });
    });

    it("refunds what the settled searches didn't use", async () => {
        const settled = [await loadJob(stuck), await loadJob(lost)] as JobRow[];
        const refund = settled.reduce((sum, row) => sum + row.max_cost - (row.cost ?? 0), 0);
        expect(await credits(owner)).toBe(creditsBefore + refund);
    });

    it("leaves healthy searches and other users' jobs as they were, machines included", async () => {
        for (const [id, before] of rows) expect(await loadJob(id)).toEqual(before);
        expect(destroyed).not.toContain("7002");
        expect(destroyed).not.toContain("7003");
    });
});
