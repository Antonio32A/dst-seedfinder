import { chargeUnits, MAX_DOLLARS_PER_HOUR, timeLimitSeconds, unitsToCredits } from "@/lib/credits";
import { isActiveStatus, type Machine } from "@/lib/job-events";
import { dispatcherStub, jobRoomStub } from "./dispatcher";
import { ACTIVE_STATUS_SQL, settleJob, type JobRow } from "./jobs";
import { destroyInstance, INSTANCE_LABEL_PREFIX, listInstances, type VastInstance } from "./vast";

const QUIET_MS = 5 * 60_000;
const DEADLINE_GRACE_MS = 10_000;
const STUCK_RUNNING_MS = 10 * 60_000;
const STUCK_WAITING_MS = 30 * 60_000;
const LOST_JOB = "The search was lost. Your credits were refunded.";
const STUCK_JOB = "The search got stuck and was stopped. Unused credits were refunded.";

type SweptRow = Pick<JobRow, "id" | "user_id" | "max_cost" | "status" | "instance_id" | "machine" | "started_at" | "updated_at">;

function isStray(instance: VastInstance & { jobId: string }, row: SweptRow | undefined): boolean {
  if (row === undefined || !isActiveStatus(row.status)) return true;
  return row.status === "running" && row.instance_id !== null && row.instance_id !== instance.id;
}

const machineOf = (row: SweptRow) => (row.machine === null ? null : (JSON.parse(row.machine) as Machine));

/** When a running search's time limit (plus the grace) runs out, or null when it isn't running with a known machine. */
function deadlineOf(row: SweptRow): number | null {
  const machine = machineOf(row);
  if (row.status !== "running" || row.started_at === null || machine === null) return null;
  return row.started_at + timeLimitSeconds(unitsToCredits(row.max_cost), machine.dollarsPerHour) * 1000 + DEADLINE_GRACE_MS;
}

/** When an active search counts as quiet (its room gets poked): past its time limit if running, else after 5 minutes. */
function staleAt(row: SweptRow): number {
  return deadlineOf(row) ?? row.updated_at + QUIET_MS;
}

/** When an active search counts as stuck whatever its room says: 10 minutes past its time limit, else after 30 minutes. */
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
  const strays = ours.filter((instance) => isStray(instance, rows.get(instance.jobId)));
  await Promise.allSettled(strays.map(({ id }) => destroyInstance(apiKey, id)));
}

/**
 * Stops a stuck search from outside its room: destroys every instance labelled with it (failures are left to the next
 * sweep, which sees the search as over) and settles it as failed, charging the starting fee once it had an instance and
 * the search time up to now.
 */
async function stopStuckJob(env: Cloudflare.Env, row: SweptRow, now: number): Promise<void> {
  const apiKey = env.VAST_API_KEY ?? "";
  const instances = await listInstances(apiKey, `${INSTANCE_LABEL_PREFIX}${row.id}`).catch(() => []);
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
  const { results } = await env.DB.prepare(`SELECT * FROM jobs WHERE status IN (${ACTIVE_STATUS_SQL})`).all<SweptRow>();
  const stuck = results.filter((row) => snapshotAt > stuckAt(row));
  const outcomes = await Promise.allSettled(stuck.map((row) => stopStuckJob(env, row, snapshotAt)));
  const stopped = new Set(stuck.filter((_, index) => outcomes[index].status === "fulfilled").map(({ id }) => id));
  await dispatcherStub(env).reconcile(
    results.filter(({ id }) => !stopped.has(id)).map(({ id }) => id),
    snapshotAt,
  );
  const stale = results.filter((row) => !stuck.includes(row) && snapshotAt > staleAt(row));
  await Promise.allSettled(
    stale.map(async (row) => {
      const alive = await jobRoomStub(env, row.id)
        .poke()
        .catch(() => true);
      if (!alive) await settleJob(env.DB, row, { status: "failed", costUnits: 0, result: null, error: LOST_JOB });
    }),
  );
}

/**
 * The five-minute cron: destroys this Worker's `dst-seedfinder:*` instances whose search is over or unknown, stops and
 * settles searches that are stuck (whatever their room says), lets the Dispatcher drop slots of searches that aren't
 * active any more, and pokes rooms of searches that have been quiet too long (settling the ones whose room holds nothing).
 */
export async function sweep(env: Cloudflare.Env): Promise<void> {
  const outcomes = await Promise.allSettled([destroyStrays(env), superviseActiveJobs(env)]);
  const failure = outcomes.find((outcome): outcome is PromiseRejectedResult => outcome.status === "rejected");
  if (failure) throw failure.reason;
}
