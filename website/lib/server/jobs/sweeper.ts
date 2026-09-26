import { chargeUnits, MAX_DOLLARS_PER_HOUR, timeLimitSeconds, unitsToCredits } from "@/lib/jobs/credits";
import { isActiveStatus, type Machine } from "@/lib/jobs/job-events";
import { destroyInstance, INSTANCE_LABEL_PREFIX, listInstances } from "@/lib/server/vast/vast";
import { dispatcherStub, jobRoomStub } from "./dispatcher";
import { ACTIVE_STATUS_SQL, type JobRow, settleJob } from "./jobs";

const QUIET_MS = 5 * 60_000;
const DEADLINE_GRACE_MS = 10_000;
const STUCK_RUNNING_MS = 10 * 60_000;
const STUCK_WAITING_MS = 30 * 60_000;
const LOST_JOB = "The search was lost. Your credits were refunded.";
const STUCK_JOB = "The search got stuck and was stopped. Unused credits were refunded.";

type SweptRow = Pick<JobRow, "id" | "user_id" | "max_cost" | "status" | "instance_id" | "machine" | "started_at" | "updated_at">;

const JOB_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const machineOf = (row: SweptRow) => (row.machine === null ? null : (JSON.parse(row.machine) as Machine));

function deadlineOf(row: SweptRow): number | null {
    const machine = machineOf(row);
    if (row.status !== "running" || row.started_at === null || machine === null) return null;
    return row.started_at + timeLimitSeconds(unitsToCredits(row.max_cost), machine.dollarsPerHour) * 1000 + DEADLINE_GRACE_MS;
}

/** Past this, the search's room gets poked. */
function staleAt(row: SweptRow): number {
    return deadlineOf(row) ?? row.updated_at + QUIET_MS;
}

/** Past this, the search is stopped whatever its room says. */
function stuckAt(row: SweptRow): number {
    const deadline = deadlineOf(row);
    return deadline === null ? row.updated_at + STUCK_WAITING_MS : deadline + STUCK_RUNNING_MS;
}

async function destroyStrays(env: Cloudflare.Env): Promise<void> {
    const apiKey = env.VAST_API_KEY;
    if (!apiKey) return;
    const ours = (await listInstances(apiKey))
        .filter((instance) => instance.label?.startsWith(INSTANCE_LABEL_PREFIX))
        .map((instance) => ({ ...instance, jobId: (instance.label as string).slice(INSTANCE_LABEL_PREFIX.length) }));
    if (ours.length === 0) return;
    const { results } = await env.DB.prepare("SELECT * FROM jobs WHERE id IN (SELECT value FROM json_each(?))")
        .bind(JSON.stringify(ours.map(({ jobId }) => jobId)))
        .all<SweptRow>();
    const rows = new Map(results.map((row) => [row.id, row]));
    const strays = ours.flatMap((instance) => {
        const status = rows.get(instance.jobId)?.status ?? "gone";
        return JOB_ID.test(instance.jobId) && (status === "gone" || !isActiveStatus(status)) ? [{
            ...instance,
            status
        }] : [];
    });
    strays.forEach(({
                        id,
                        jobId,
                        status
                    }) => console.warn(`sweeper: destroying instance ${id}, its search ${jobId} is ${status}`));
    await Promise.allSettled(strays.map(({ id }) => destroyInstance(apiKey, id)));
}

/** Failed destroys are left to the next sweep, which then sees the search as over. */
async function stopStuckJob(env: Cloudflare.Env, row: SweptRow, now: number): Promise<void> {
    const apiKey = env.VAST_API_KEY ?? "";
    const instances = await listInstances(apiKey, `${INSTANCE_LABEL_PREFIX}${row.id}`).catch(() => []);
    console.warn(`sweeper: stopping stuck search ${row.id} (${row.status}), destroying instances [${instances.map(({ id }) => id).join(", ")}]`);
    await Promise.allSettled(instances.map(({ id }) => destroyInstance(apiKey, id)));
    const searchMs = row.started_at === null ? null : now - row.started_at;
    const fee = row.instance_id !== null || row.started_at !== null;
    const costUnits = chargeUnits(row.max_cost, fee, searchMs, machineOf(row)?.dollarsPerHour ?? MAX_DOLLARS_PER_HOUR);
    await settleJob(env.DB, row, { status: "failed", costUnits, result: null, error: STUCK_JOB });
    await jobRoomStub(env, row.id)
        .poke()
        .catch(() => undefined);
}

async function superviseActiveJobs(env: Cloudflare.Env): Promise<void> {
    const snapshotAt = Date.now();
    const { results } = await env.DB.prepare(`SELECT *
                                              FROM jobs
                                              WHERE status IN (${ACTIVE_STATUS_SQL})`).all<SweptRow>();
    const stuck = results.filter((row) => snapshotAt > stuckAt(row));
    const outcomes = await Promise.allSettled(stuck.map((row) => stopStuckJob(env, row, snapshotAt)));
    const stopped = new Set(stuck.filter((_, index) => outcomes[index].status === "fulfilled").map(({ id }) => id));
    await dispatcherStub(env).reconcile(
        results.filter(({ id }) => !stopped.has(id)).map(({ id }) => id),
        snapshotAt
    );
    const stale = results.filter((row) => !stuck.includes(row) && snapshotAt > staleAt(row));
    await Promise.allSettled(
        stale.map(async (row) => {
            const alive = await jobRoomStub(env, row.id)
                .poke()
                .catch(() => true);
            if (!alive) await settleJob(env.DB, row, { status: "failed", costUnits: 0, result: null, error: LOST_JOB });
        })
    );
}

export async function sweep(env: Cloudflare.Env): Promise<void> {
    const outcomes = await Promise.allSettled([destroyStrays(env), superviseActiveJobs(env)]);
    const failure = outcomes.find((outcome): outcome is PromiseRejectedResult => outcome.status === "rejected");
    if (failure) throw failure.reason;
}
