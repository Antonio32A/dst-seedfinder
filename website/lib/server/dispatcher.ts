import { DurableObject } from "cloudflare:workers";

const DEFAULT_MAX_INSTANCES = 10;

export const MAX_WAITING = 200;

/** Whether a search holds an instance slot, or else its 1-based place in the queue. */
export interface Admission {
  granted: boolean;
  position: number | null;
}

interface EntryRow extends Record<string, SqlStorageValue> {
  job_id: string;
  holding: number;
}

/** The Dispatcher singleton every JobRoom talks to. */
export function dispatcherStub(env: Cloudflare.Env): DurableObjectStub<Dispatcher> {
  return env.DISPATCHER.get(env.DISPATCHER.idFromName("global"));
}

/** The JobRoom Durable Object that owns one search. */
export function jobRoomStub(env: Cloudflare.Env, jobId: string) {
  return env.JOB_ROOM.get(env.JOB_ROOM.idFromName(jobId));
}

/**
 * Caps live vast.ai instances at `MAX_INSTANCES`: searches wait in a FIFO queue, take a slot when one frees up, and
 * queued JobRooms are told their admission whenever it changes.
 */
export class Dispatcher extends DurableObject<Cloudflare.Env> {
  constructor(ctx: DurableObjectState, env: Cloudflare.Env) {
    super(ctx, env);
    ctx.storage.sql.exec(
      `CREATE TABLE IF NOT EXISTS entries (
         seq INTEGER PRIMARY KEY AUTOINCREMENT,
         job_id TEXT NOT NULL UNIQUE,
         added_at INTEGER NOT NULL,
         holding INTEGER NOT NULL DEFAULT 0
       )`,
    );
  }

  /**
   * Queues a search (a no-op if it is already queued or holding a slot) and returns its current admission. Other rooms
   * are only told when theirs changed.
   */
  async enqueue(jobId: string): Promise<Admission> {
    await this.change(() => {
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO entries (job_id, added_at) VALUES (?, ?)", jobId, Date.now());
    }, jobId);
    return this.admissions().get(jobId) ?? { granted: false, position: null };
  }

  /** How many searches are waiting for a slot. */
  async waiting(): Promise<number> {
    return this.ctx.storage.sql.exec<{ count: number }>("SELECT COUNT(*) AS count FROM entries WHERE holding = 0").one().count;
  }

  /** Frees a search's slot or takes it out of the queue, then lets the next searches in. */
  async release(jobId: string): Promise<void> {
    await this.change(() => this.ctx.storage.sql.exec("DELETE FROM entries WHERE job_id = ?", jobId));
  }

  /** Drops entries older than `before` whose search is no longer active in D1, in case a JobRoom never released. */
  async reconcile(activeJobIds: string[], before: number): Promise<void> {
    const active = new Set(activeJobIds);
    const stale = this.ctx.storage.sql
      .exec<EntryRow>("SELECT job_id, holding FROM entries WHERE added_at < ?", before)
      .toArray()
      .filter(({ job_id }) => !active.has(job_id));
    if (stale.length > 0) await this.change(() => this.forget(stale.map(({ job_id }) => job_id)));
  }

  private admissions(): Map<string, Admission> {
    const rows = this.ctx.storage.sql.exec<EntryRow>("SELECT job_id, holding FROM entries ORDER BY seq").toArray();
    let position = 0;
    return new Map(
      rows.map(({ job_id, holding }): [string, Admission] => [
        job_id,
        holding === 1 ? { granted: true, position: null } : { granted: false, position: ++position },
      ]),
    );
  }

  private forget(jobIds: string[]): void {
    jobIds.forEach((jobId) => this.ctx.storage.sql.exec("DELETE FROM entries WHERE job_id = ?", jobId));
  }

  /**
   * Applies a change to the entries, hands free slots to the head of the queue, and tells every room other than
   * `callerId` whose admission moved. Rooms that answer that they no longer want a slot are dropped, which may move
   * others again.
   */
  private async change(apply: () => void, callerId?: string): Promise<void> {
    const before = this.admissions();
    apply();
    const maxInstances = Number(this.env.MAX_INSTANCES) || DEFAULT_MAX_INSTANCES;
    const sql = this.ctx.storage.sql;
    const holding = sql.exec<{ count: number }>("SELECT COUNT(*) AS count FROM entries WHERE holding = 1").one().count;
    sql.exec(
      "UPDATE entries SET holding = 1 WHERE seq IN (SELECT seq FROM entries WHERE holding = 0 ORDER BY seq LIMIT ?)",
      Math.max(0, maxInstances - holding),
    );
    const moved = [...this.admissions()].filter(([jobId, admission]) => {
      const previous = before.get(jobId);
      return jobId !== callerId && (previous?.granted !== admission.granted || previous?.position !== admission.position);
    });
    const replies = await Promise.all(
      moved.map(([jobId, admission]) =>
        jobRoomStub(this.env, jobId)
          .admit(admission)
          .catch(() => true),
      ),
    );
    const gone = moved.filter((_, index) => !replies[index]).map(([jobId]) => jobId);
    if (gone.length > 0) await this.change(() => this.forget(gone), callerId);
  }
}
