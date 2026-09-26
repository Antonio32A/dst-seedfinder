import { DurableObject } from "cloudflare:workers";
import { chargeUnits, MAX_DOLLARS_PER_HOUR, timeLimitSeconds } from "@/lib/credits";
import {
    type FinishedJobStatus,
    isActiveStatus,
    type JobEvent,
    type JobProgress,
    type JobStatus,
    type Machine
} from "@/lib/job-events";
import type { SearchHit } from "@/lib/job-result";
import type { Platform } from "@/lib/seedfinder-config";
import { type Admission, dispatcherStub } from "./dispatcher";
import { closedEventStream, finishedEvents, SSE_HEADERS, SSE_HEARTBEAT, sseFrame } from "./job-stream";
import { type JobSettlement, loadJob, settleJob, toJobView, updateActiveJob } from "./jobs";
import { type Offer, OFFER_ATTEMPTS, pickOffers } from "./offers";
import {
    type DoneSummary,
    exitKind,
    type ExitKind,
    jobObject,
    type LineTail,
    MAX_CHUNK_BYTES,
    MAX_OUTPUT_BYTES,
    type OutputLine,
    parseExitHeader,
    parseOutputLine,
    placeChunk,
    splitLines
} from "./runner-output";
import {
    createInstance,
    destroyInstance,
    INSTANCE_LABEL_PREFIX,
    isRefusal,
    listInstances,
    mayHaveCreated,
    searchOffers
} from "./vast";

const BOOT_TIMEOUT_MS = 3 * 60_000;
const STARTING_LIMIT_MS = 10 * 60_000;
const DEADLINE_GRACE_MS = 10_000;
const SILENCE_MS = 60_000;
const QUEUE_POLL_MS = 60_000;
const VAST_RETRY_MS = 20_000;
const RETRY_MS = 30_000;
const KEEP_FINISHED_MS = 24 * 60 * 60_000;
const DESTROY_RETRY_WINDOW_MS = 60 * 60_000;
const HEARTBEAT_MS = 20_000;
const SPEED_WINDOW_MS = 30_000;
const MAX_RESULT_BYTES = 1_000_000;

const NO_MACHINE = "No machine was free for the search. Your credits were refunded.";
const BOOT_FAILED = "Couldn't start a machine for the search. Your credits were refunded.";
const TIMED_OUT = "The search didn't finish in time. Unused credits were refunded.";
const LOST = "Lost contact with the search machine. Unused credits were refunded.";
const CRASHED = "The search crashed. Unused credits were refunded.";
const CONFIG_REJECTED = "The finder rejected the search config. Unused credits were refunded.";
const CANCELLED = "The search was cancelled. Unused credits were refunded.";
const RESULT_TOO_LARGE = "The search found more than can be saved. Unused credits were refunded.";
const FLOODED = "The search printed more output than expected. Unused credits were refunded.";

/** What a JobRoom needs to know about its search, handed over by `POST /api/jobs`. */
export interface JobSpec {
    id: string;
    userId: string;
    maxCost: number;
    maxCostUnits: number;
    wanted: number;
    startSeed: number;
    config: string;
    platform: Platform;
    origin: string;
}

type ResultKind = "search" | "config-error" | "none";

interface EndingKind {
    status: FinishedJobStatus;
    error: string | null;
    result: ResultKind;
    fee: boolean;
}

interface Ending extends EndingKind {
    endedAt: number;
}

interface RoomState {
    status: JobStatus;
    queuePosition: number | null;
    startingSince: number | null;
    attempt: number;
    triedAsks: number[];
    rented: boolean;
    machine: Machine | null;
    instanceId: string | null;
    doomed: string[];
    leaked: boolean;
    tokenHash: string | null;
    bootDeadline: number | null;
    timeLimitMs: number | null;
    startedAt: number | null;
    lastPostAt: number | null;
    received: number;
    tail: LineTail;
    progress: JobProgress | null;
    summary: DoneSummary | null;
    configError: string | null;
    ending: Ending | null;
    settled: boolean;
    tornDown: boolean;
}

const failed = (error: string, result: ResultKind, fee = true): EndingKind => ({
    status: "failed",
    error,
    result,
    fee
});

const EXIT_ENDINGS: Record<ExitKind, EndingKind> = {
    done: { status: "done", error: null, result: "search", fee: true },
    "config-error": failed(CONFIG_REJECTED, "config-error"),
    crash: failed(CRASHED, "search")
};

const RUNNER_GET_STATUSES = new Set<JobStatus>(["starting", "running"]);
const RUNNER_POST_STATUSES = new Set<JobStatus>(["running"]);

const plain = (status: number, body: string, headers: Record<string, string> = {}) =>
    new Response(body, { status, headers: { "Cache-Control": "no-store", ...headers } });

async function sha256Hex(text: string): Promise<string> {
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** Compares two equal-length hex digests in constant time. */
function sameHex(given: string, expected: string): boolean {
    const difference = Array.from(expected).reduce((bits, char, index) => bits | (char.charCodeAt(0) ^ given.charCodeAt(index)), 0);
    return given.length === expected.length && difference === 0;
}

function randomHex(bytes: number): string {
    return Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/**
 * One search's whole lifecycle: waits for a Dispatcher slot, boots a vast.ai instance, serves the runner its config
 * and takes its output, streams events to browsers, settles D1 exactly once when it ends, and only frees its slot once
 * every instance it rented is gone.
 */
export class JobRoom extends DurableObject<Cloudflare.Env> {
    private job: JobSpec | null;
    private state: RoomState | null;
    private readonly subscribers = new Set<WritableStreamDefaultWriter<Uint8Array>>();
    private heartbeat: ReturnType<typeof setInterval> | null = null;
    private wrapping: Promise<void> | null = null;
    private speedSamples: { at: number; scanned: number }[] = [];

    private readonly alarmSteps: Record<JobStatus, (state: RoomState) => Promise<void>> = {
        queued: () => this.requeue(),
        starting: (state) => this.launch(state),
        running: (state) => this.watch(state),
        done: (state) => this.finish(state),
        failed: (state) => this.finish(state),
        cancelled: (state) => this.finish(state)
    };

    constructor(ctx: DurableObjectState, env: Cloudflare.Env) {
        super(ctx, env);
        this.job = ctx.storage.kv.get<JobSpec>("job") ?? null;
        this.state = ctx.storage.kv.get<RoomState>("state") ?? null;
    }

    /** Takes over a freshly reserved search and queues it. Repeated calls are no-ops. */
    async start(job: JobSpec): Promise<void> {
        if (this.state !== null) return;
        this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS hits (seq INTEGER PRIMARY KEY AUTOINCREMENT, seed INTEGER UNIQUE, hit TEXT NOT NULL)");
        this.ctx.storage.kv.put("job", job);
        this.job = job;
        this.save({
            status: "queued",
            queuePosition: null,
            startingSince: null,
            attempt: 0,
            triedAsks: [],
            rented: false,
            machine: null,
            instanceId: null,
            doomed: [],
            leaked: false,
            tokenHash: null,
            bootDeadline: null,
            timeLimitMs: null,
            startedAt: null,
            lastPostAt: null,
            received: 0,
            tail: { bytes: new Uint8Array(), skipping: false },
            progress: null,
            summary: null,
            configError: null,
            ending: null,
            settled: false,
            tornDown: false
        });
        await this.ctx.storage.setAlarm(Date.now() + QUEUE_POLL_MS);
        await this.requeue().catch(() => undefined);
    }

    /** The Dispatcher's word on this search. Returns false when the search no longer wants a slot. */
    async admit(admission: Admission): Promise<boolean> {
        const state = this.state;
        if (state === null || !isActiveStatus(state.status)) return false;
        if (state.status !== "queued") return true;
        if (admission.granted) {
            this.save({ status: "starting", queuePosition: null, startingSince: Date.now() });
            await this.ctx.storage.setAlarm(Date.now());
            await updateActiveJob(this.env.DB, this.spec.id, { status: "starting" }).catch(() => undefined);
        } else {
            this.save({ queuePosition: admission.position });
        }
        this.broadcast([this.statusEvent()]);
        return true;
    }

    /** Stops the search and settles it: charges the starting fee once a machine was rented, and the search time so far. */
    async cancel(): Promise<void> {
        const state = this.state;
        if (state === null) return;
        await this.end({
            status: "cancelled",
            error: CANCELLED,
            result: state.startedAt === null ? "none" : "search",
            fee: true
        });
    }

    /** Makes sure an active search has an alarm pending. Returns false when this room holds no search at all. */
    async poke(): Promise<boolean> {
        if (this.state === null) return false;
        if ((await this.ctx.storage.getAlarm()) === null) await this.ctx.storage.setAlarm(Date.now());
        return true;
    }

    /** The browser event stream: replays the status, the latest progress and every hit, then follows live until `end`. */
    async events(): Promise<Response> {
        const state = this.state;
        if (state === null) return plain(404, "Search not found.");
        const row = state.settled ? await loadJob(this.env.DB, this.spec.id) : null;
        if (row !== null) return closedEventStream(finishedEvents(row));
        const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
        const writer = writable.getWriter();
        this.subscribers.add(writer);
        this.heartbeat ??= setInterval(() => this.send(SSE_HEARTBEAT), HEARTBEAT_MS);
        const replay: JobEvent[] = [
            this.statusEvent(),
            ...(state.progress ? [{ type: "progress" as const, progress: state.progress }] : []),
            ...this.storedHits().map((hit): JobEvent => ({ type: "hit", hit }))
        ];
        replay.forEach((event) => this.write(writer, sseFrame(event)));
        return new Response(readable, { headers: SSE_HEADERS });
    }

    /** `GET /api/runner/<id>`: the config, once the bearer token checks out. The first call starts the billed search. */
    async runnerConfig(authorization: string | null): Promise<Response> {
        const refusal = await this.refuseRunner(authorization, RUNNER_GET_STATUSES);
        if (refusal !== null) return refusal;
        if ((this.state as RoomState).received > 0) return plain(409, "The search already started.");
        if ((this.state as RoomState).status === "starting") await this.begin();
        return new Response(this.spec.config, {
            headers: {
                "Content-Type": "application/json",
                "Cache-Control": "no-store"
            }
        });
    }

    /** `POST /api/runner/<id>`: appends output at `X-Offset`, and ends the search on the chunk with `X-Exit`. */
    async runnerOutput(authorization: string | null, offsetHeader: string | null, exitHeader: string | null, body: Uint8Array): Promise<Response> {
        const refusal = await this.refuseRunner(authorization, RUNNER_POST_STATUSES);
        if (refusal !== null) return refusal;
        const offset = Number(offsetHeader ?? Number.NaN);
        if (!Number.isSafeInteger(offset) || offset < 0) return plain(400, "Bad X-Offset.");
        if (body.byteLength > MAX_CHUNK_BYTES) return plain(413, "Chunk too large.");
        const placement = placeChunk((this.state as RoomState).received, offset);
        if (placement.kind === "gap") return plain(409, "Gap.", { "X-Offset": String(placement.expected) });

        const now = Date.now();
        const fresh = body.subarray(placement.skip);
        if ((this.state as RoomState).received + fresh.byteLength > MAX_OUTPUT_BYTES) {
            await this.record(failed(FLOODED, "search"), now);
            return plain(410, "Gone.");
        }
        this.append(fresh);
        this.save({ lastPostAt: now });
        const exit = parseExitHeader(exitHeader);
        const received = (this.state as RoomState).received;
        if (exit !== null && offset + body.byteLength >= received) await this.exited(exit, now);
        return plain(200, "OK", { "X-Offset": String(received) });
    }

    async alarm(): Promise<void> {
        const state = this.state;
        if (state === null) return;
        await this.alarmSteps[state.status](state);
    }

    private get spec(): JobSpec {
        return this.job as JobSpec;
    }

    private save(patch: Partial<RoomState>): void {
        this.state = { ...(this.state as RoomState), ...patch };
        this.ctx.storage.kv.put("state", this.state);
    }

    private statusEvent(): JobEvent {
        const { status, queuePosition, machine, attempt } = this.state as RoomState;
        return { type: "status", status, queuePosition, machine, attempt: attempt || null };
    }

    private storedHits(): SearchHit[] {
        return this.ctx.storage.sql
            .exec<{ hit: string }>("SELECT hit FROM hits ORDER BY seq")
            .toArray()
            .map(({ hit }) => JSON.parse(hit) as SearchHit);
    }

    private write(writer: WritableStreamDefaultWriter<Uint8Array>, bytes: Uint8Array): void {
        writer.write(bytes).catch(() => this.unsubscribe(writer));
    }

    private send(bytes: Uint8Array): void {
        this.subscribers.forEach((writer) => this.write(writer, bytes));
    }

    private broadcast(events: JobEvent[]): void {
        events.forEach((event) => this.send(sseFrame(event)));
    }

    private unsubscribe(writer: WritableStreamDefaultWriter<Uint8Array>): void {
        this.subscribers.delete(writer);
        writer.close().catch(() => undefined);
        if (this.subscribers.size > 0 || this.heartbeat === null) return;
        clearInterval(this.heartbeat);
        this.heartbeat = null;
    }

    private async refuseRunner(authorization: string | null, statuses: Set<JobStatus>): Promise<Response | null> {
        const digest = await sha256Hex(authorization?.match(/^Bearer (\S+)$/)?.[1] ?? "");
        const state = this.state;
        if (state === null || state.tokenHash === null) return plain(410, "Gone.");
        if (!sameHex(digest, state.tokenHash)) return plain(401, "Bad token.");
        return statuses.has(state.status) ? null : plain(410, "Gone.");
    }

    private async requeue(): Promise<void> {
        await this.ctx.storage.setAlarm(Date.now() + QUEUE_POLL_MS);
        const admission = await dispatcherStub(this.env).enqueue(this.spec.id);
        await this.admit(admission);
        if (this.state?.status === "queued") await updateActiveJob(this.env.DB, this.spec.id, { status: "queued" });
    }

    private bootFailure(): EndingKind {
        return failed((this.state as RoomState).rented ? BOOT_FAILED : NO_MACHINE, "none", false);
    }

    private async launch(state: RoomState): Promise<void> {
        const now = Date.now();
        const giveUpAt = (state.startingSince ?? now) + STARTING_LIMIT_MS;
        const booting = state.instanceId !== null && now < (state.bootDeadline ?? 0);
        if (now >= giveUpAt || (!booting && state.attempt >= OFFER_ATTEMPTS)) return this.record(this.bootFailure(), now);
        if (booting) return this.ctx.storage.setAlarm(Math.min(state.bootDeadline as number, giveUpAt));
        this.abandonInstance();
        await this.ctx.storage.setAlarm(now + VAST_RETRY_MS);
        await this.tryNextOffer();
    }

    /**
     * One boot attempt on the best offer not tried yet, from a fresh offer search. A vast.ai hiccup leaves it to the
     * pending alarm to try again; only a definite refusal of the offer uses up the attempt.
     */
    private async tryNextOffer(): Promise<void> {
        const row = await loadJob(this.env.DB, this.spec.id);
        if (row === null || row.cost !== null) return this.record(failed(BOOT_FAILED, "none", false), Date.now());
        await this.clearStrays();
        const tried = new Set((this.state as RoomState).triedAsks);
        const offers = await searchOffers(this.env.VAST_API_KEY ?? "").then(
            (response) => pickOffers(response).filter((offer) => offer.dollarsPerHour <= MAX_DOLLARS_PER_HOUR && !tried.has(offer.askId)),
            () => null
        );
        if (offers === null || this.state?.status !== "starting") return;
        if (offers.length === 0) return this.record(this.bootFailure(), Date.now());
        await this.boot(offers[0]);
    }

    private async boot(offer: Offer): Promise<void> {
        const state = this.state as RoomState;
        const job = this.spec;
        const { askId, ...machine } = offer;
        const token = randomHex(32);
        const timeLimitMs = Math.floor(timeLimitSeconds(job.maxCost, machine.dollarsPerHour) * 1000);
        const before = { attempt: state.attempt, triedAsks: state.triedAsks };
        this.save({
            attempt: state.attempt + 1,
            triedAsks: [...state.triedAsks, askId],
            machine,
            tokenHash: await sha256Hex(token),
            timeLimitMs
        });
        const created = await createInstance(this.env.VAST_API_KEY ?? "", {
            askId,
            label: `${INSTANCE_LABEL_PREFIX}${job.id}`,
            image: this.env.RUNNER_IMAGE ?? "",
            imageLogin: `-u ${this.env.GHCR_USER} -p ${this.env.GHCR_PULL_TOKEN} ghcr.io`,
            env: {
                CALLBACK_URL: `${job.origin}/api/runner/${job.id}`,
                RUNNER_TOKEN: token,
                JOB_LIMIT: String(job.wanted),
                JOB_TIME_LIMIT: String(timeLimitMs / 1000),
                JOB_START_SEED: String(job.startSeed)
            }
        }).then(
            (instanceId) => ({ instanceId, error: null }),
            (error: unknown) => ({ instanceId: null, error })
        );
        if (created.instanceId !== null) return this.adopt(created.instanceId);
        if (this.state?.status !== "starting") return;
        const refused = isRefusal(created.error);
        const unsure = mayHaveCreated(created.error);
        this.save({
            ...(refused ? {} : before),
            machine: null,
            tokenHash: null,
            rented: this.state.rented || unsure,
            leaked: this.state.leaked || unsure
        });
        if (refused) await this.ctx.storage.setAlarm(Date.now());
    }

    private async adopt(instanceId: string): Promise<void> {
        const state = this.state as RoomState;
        this.save({ rented: true });
        if (!isActiveStatus(state.status)) {
            this.save({ doomed: [...state.doomed, instanceId], tornDown: false });
            return this.ctx.storage.setAlarm(Date.now());
        }
        const bootDeadline = Date.now() + BOOT_TIMEOUT_MS;
        this.save({ instanceId, bootDeadline });
        if (state.status === "starting") {
            await this.ctx.storage.setAlarm(Math.min(bootDeadline, (state.startingSince ?? 0) + STARTING_LIMIT_MS));
        }
        await updateActiveJob(this.env.DB, this.spec.id, {
            status: state.status,
            instanceId,
            machine: state.machine ?? undefined
        });
        this.broadcast([this.statusEvent()]);
    }

    private abandonInstance(): void {
        const { instanceId, doomed } = this.state as RoomState;
        if (instanceId === null) return;
        this.save({ instanceId: null, doomed: [...doomed, instanceId], tokenHash: null, bootDeadline: null });
    }

    /**
     * Destroys every instance of this search but the current one: those it gave up on, and any vast.ai lists with its
     * label (a create that failed may have rented one anyway). True when none is left; failures stay queued for later.
     */
    private async clearStrays(): Promise<boolean> {
        const apiKey = this.env.VAST_API_KEY ?? "";
        const listed = await listInstances(apiKey, `${INSTANCE_LABEL_PREFIX}${this.spec.id}`).then(
            (instances) => instances.map(({ id }) => id),
            () => null
        );
        const { doomed, instanceId } = this.state as RoomState;
        const targets = [...new Set([...doomed, ...(listed ?? [])])].filter((id) => id !== instanceId);
        if (targets.length > 0) console.warn(`search ${this.spec.id}: destroying instances [${targets.join(", ")}], keeping ${instanceId ?? "none"}`);
        const outcomes = await Promise.allSettled(targets.map((id) => destroyInstance(apiKey, id)));
        const survivors = targets.filter((_, index) => outcomes[index].status === "rejected");
        this.save({ doomed: survivors, leaked: (this.state as RoomState).leaked && listed === null });
        return listed !== null && survivors.length === 0;
    }

    private async begin(): Promise<void> {
        const now = Date.now();
        const state = this.state as RoomState;
        this.save({ status: "running", startedAt: now, lastPostAt: now, bootDeadline: null });
        await this.ctx.storage.setAlarm(now + SILENCE_MS);
        await updateActiveJob(this.env.DB, this.spec.id, {
            status: "running",
            startedAt: now,
            instanceId: state.instanceId ?? undefined,
            machine: state.machine ?? undefined
        });
        this.broadcast([this.statusEvent()]);
    }

    private async watch(state: RoomState): Promise<void> {
        const now = Date.now();
        const lastPostAt = state.lastPostAt ?? now;
        const deadline = (state.startedAt ?? now) + (state.timeLimitMs ?? 0) + DEADLINE_GRACE_MS;
        const limits: [number, EndingKind, number][] = [
            [deadline, failed(TIMED_OUT, "search"), deadline],
            [lastPostAt + SILENCE_MS, failed(LOST, "search"), lastPostAt]
        ];
        const breached = limits.find(([at]) => now >= at);
        if (breached) return this.record(breached[1], breached[2]);
        if (state.doomed.length > 0 || state.leaked) await this.clearStrays();
        if (this.state?.status === "running") await this.ctx.storage.setAlarm(Math.min(...limits.map(([at]) => at)));
    }

    private append(bytes: Uint8Array): void {
        const state = this.state as RoomState;
        if (bytes.byteLength === 0) return;
        const { lines, tail } = splitLines(state.tail, bytes);
        this.save({ received: state.received + bytes.byteLength, tail });
        this.apply(lines);
    }

    private apply(lines: string[]): void {
        const parsed = lines.map(parseOutputLine).filter((line): line is OutputLine => line !== null);
        const events: JobEvent[] = [];
        for (const line of parsed) {
            const event = this.lineEffects[line.kind](line as never);
            if (event) events.push(event);
        }
        const progress = parsed.some((line) => line.kind === "progress") ? (this.state as RoomState).progress : null;
        this.broadcast([...events, ...(progress ? [{ type: "progress" as const, progress }] : [])]);
    }

    private readonly lineEffects: {
        [K in OutputLine["kind"]]: (line: Extract<OutputLine, {
            kind: K
        }>) => JobEvent | null
    } = {
        progress: ({ progress }) => {
            const now = Date.now();
            this.speedSamples = [...this.speedSamples.filter(({ at }) => at >= now - SPEED_WINDOW_MS), {
                at: now,
                scanned: progress.scanned
            }];
            const [oldest] = this.speedSamples;
            const since = oldest.at < now ? oldest : { at: (this.state as RoomState).startedAt ?? now, scanned: 0 };
            const seedsPerSecond = progress.seedsPerSecond ?? Math.round(((progress.scanned - since.scanned) * 1000) / Math.max(now - since.at, 1000));
            this.save({ progress: { ...progress, seedsPerSecond } });
            return null;
        },
        hit: ({ hit }) => {
            const inserted = this.ctx.storage.sql.exec(
                "INSERT OR IGNORE INTO hits (seed, hit) SELECT ?, ? WHERE (SELECT COUNT(*) FROM hits) < ?",
                hit.seed,
                JSON.stringify(hit),
                this.spec.wanted
            ).rowsWritten;
            return inserted > 0 ? { type: "hit", hit } : null;
        },
        done: ({ summary }) => {
            this.save({ summary });
            return null;
        },
        error: ({ error }) => {
            this.save({ configError: error });
            return null;
        }
    };

    private async exited(exit: number, endedAt: number): Promise<void> {
        const tail = new TextDecoder().decode((this.state as RoomState).tail.bytes);
        if (tail) this.apply([tail]);
        this.save({ tail: { bytes: new Uint8Array(), skipping: false } });
        const { summary, configError } = this.state as RoomState;
        await this.record(EXIT_ENDINGS[exitKind(exit, summary, configError)], endedAt);
    }

    /** Marks an active search as ended and leaves the teardown and settlement to an immediate alarm. */
    private async record(kind: EndingKind, endedAt: number): Promise<void> {
        if (!isActiveStatus((this.state as RoomState).status)) return;
        this.save({ status: kind.status, ending: { ...kind, endedAt }, queuePosition: null });
        await this.ctx.storage.setAlarm(Date.now());
    }

    /** Records the ending (if the search is still active) and waits for the settlement, joining one already under way. */
    private async end(kind: EndingKind): Promise<void> {
        await this.record(kind, Date.now());
        await this.wrapUpOnce();
    }

    private wrapUpOnce(): Promise<void> {
        if ((this.state as RoomState).settled) return this.wrapping ?? Promise.resolve();
        this.wrapping ??= this.wrapUp().finally(() => {
            this.wrapping = null;
        });
        return this.wrapping;
    }

    private async wrapUp(): Promise<void> {
        const state = this.state as RoomState;
        const job = this.spec;
        try {
            await settleJob(this.env.DB, {
                id: job.id,
                user_id: job.userId,
                max_cost: job.maxCostUnits
            }, this.settlement(state, state.ending as Ending));
            this.save({ settled: true });
        } finally {
            await this.announce();
        }
    }

    /** Sends `end` with the settled D1 row when it can be read, and closes every stream either way (a reconnect replays from D1). */
    private async announce(): Promise<void> {
        try {
            const row = await loadJob(this.env.DB, this.spec.id).catch(() => null);
            if (row !== null && row.cost !== null) this.broadcast([this.statusEvent(), {
                type: "end",
                job: toJobView(row)
            }]);
        } finally {
            [...this.subscribers].forEach((writer) => this.unsubscribe(writer));
        }
    }

    private async finish(state: RoomState): Promise<void> {
        if (state.settled && state.tornDown) return this.forget();
        await this.ctx.storage.setAlarm(Date.now() + RETRY_MS);
        if (!state.settled) await this.wrapUpOnce().catch(() => undefined);
        if (!state.tornDown) await this.tearDown(state.ending as Ending);
        const { settled, tornDown } = this.state as RoomState;
        if (settled && tornDown) await this.ctx.storage.setAlarm(Date.now() + KEEP_FINISHED_MS);
    }

    /** Destroys the search's instances, then frees its Dispatcher slot (after an hour of failed destroys, the sweeper takes over). */
    private async tearDown(ending: Ending): Promise<void> {
        this.abandonInstance();
        const cleared = await this.clearStrays();
        if (!cleared && Date.now() < ending.endedAt + DESTROY_RETRY_WINDOW_MS) return;
        await dispatcherStub(this.env).release(this.spec.id);
        this.save({ tornDown: true });
    }

    private async forget(): Promise<void> {
        await this.ctx.storage.deleteAlarm();
        await this.ctx.storage.deleteAll();
        this.state = null;
        this.job = null;
    }

    private settlement(state: RoomState, ending: Ending): JobSettlement {
        const job = this.spec;
        const searchMs = state.startedAt === null ? null : ending.endedAt - state.startedAt;
        const costUnits = chargeUnits(job.maxCostUnits, ending.fee && state.rented, searchMs, state.machine?.dollarsPerHour ?? MAX_DOLLARS_PER_HOUR);
        const results: Record<ResultKind, () => string | null> = {
            search: () => JSON.stringify(jobObject(job.platform, this.storedHits(), state.summary, {
                startSeed: job.startSeed,
                progress: state.progress
            })),
            "config-error": () => JSON.stringify({ error: state.configError }),
            none: () => null
        };
        const result = results[ending.result]();
        const fits = result === null || new TextEncoder().encode(result).byteLength <= MAX_RESULT_BYTES;
        return fits
            ? { status: ending.status, costUnits, result, error: ending.error }
            : { status: "failed", costUnits, result: null, error: RESULT_TOO_LARGE };
    }
}
