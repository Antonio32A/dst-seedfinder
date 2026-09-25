import { useEffect, useRef, useState } from "react";
import { jobEventsUrl, type JobView } from "./api-client";
import type { JobEvent, JobProgress, JobStatus, Machine } from "./job-events";
import type { SearchHit } from "./job-result";

/** What the live stream has said so far about one search. `offline` is set while the stream is reconnecting. */
export interface LiveJob {
  id: string;
  status: JobStatus;
  queuePosition: number | null;
  machine: Machine | null;
  attempt: number | null;
  progress: JobProgress | null;
  hits: SearchHit[];
  offline: boolean;
}

/** What `useJobStream` tells its caller: the settled job after `end`, and each time the stream is dropped for good. */
export interface JobStreamHandlers {
  onEnd: (job: JobView) => void;
  onLost: () => void;
}

type StreamEvent = Exclude<JobEvent, { type: "end" }> | { type: "end"; job: JobView };

type Appliers = { [T in StreamEvent["type"]]: (live: LiveJob, event: Extract<StreamEvent, { type: T }>) => LiveJob };

const APPLY: Appliers = {
  status: (live, { status, queuePosition, machine, attempt }) => ({ ...live, status, queuePosition, machine, attempt }),
  progress: (live, { progress }) => ({ ...live, progress }),
  hit: (live, { hit }) => (live.hits.some((known) => known.seed === hit.seed) ? live : { ...live, hits: [...live.hits, hit] }),
  end: (live, { job }) => ({ ...live, status: job.status }),
};

const FIRST_RETRY_MS = 1000;
const MAX_RETRY_MS = 30_000;

/** What is known of a search before its stream has said anything. */
export function liveJobOf({ id, status, machine }: Pick<JobView, "id" | "status" | "machine">): LiveJob {
  return { id, status, queuePosition: null, machine, attempt: null, progress: null, hits: [], offline: false };
}

/** Parses one `data:` payload of the event stream, or `null` if it isn't a known `JobEvent`. */
export function readJobEvent(data: unknown): StreamEvent | null {
  try {
    const event: unknown = JSON.parse(String(data));
    const type = (event as { type?: unknown } | null)?.type;
    return typeof type === "string" && Object.hasOwn(APPLY, type) ? (event as StreamEvent) : null;
  } catch {
    return null;
  }
}

/** Folds one event into what is known of a search. Replayed hits (same seed) are ignored, so a reconnect is harmless. */
export function applyJobEvent(live: LiveJob, event: StreamEvent): LiveJob {
  return (APPLY[event.type] as (live: LiveJob, event: StreamEvent) => LiveJob)(live, event);
}

/**
 * Follows a search's live events (`GET /api/jobs/<id>/events`) while `jobId` is set. The browser reconnects a dropped
 * stream by itself; one it gives up on is reopened with backoff (after `onLost`) until the search ends, and `onEnd` gets
 * the settled job.
 */
export function useJobStream(jobId: string | null, handlers: JobStreamHandlers): LiveJob | null {
  const [live, setLive] = useState<LiveJob | null>(null);
  const latestHandlers = useRef(handlers);
  useEffect(() => {
    latestHandlers.current = handlers;
  });

  useEffect(() => {
    if (jobId === null) return;
    let source: EventSource | null = null;
    let retryTimer = 0;
    let retries = 0;
    let ended = false;
    const update = (change: (live: LiveJob) => LiveJob) =>
      setLive((current) => change(current?.id === jobId ? current : liveJobOf({ id: jobId, status: "queued", machine: null })));

    const connect = () => {
      const stream = new EventSource(jobEventsUrl(jobId));
      source = stream;
      stream.onopen = () => {
        retries = 0;
        update((current) => ({ ...current, offline: false }));
      };
      stream.onmessage = (message) => {
        const event = readJobEvent(message.data);
        if (event === null) return;
        update((current) => applyJobEvent({ ...current, offline: false }, event));
        if (event.type !== "end") return;
        ended = true;
        stream.close();
        latestHandlers.current.onEnd(event.job);
      };
      stream.onerror = () => {
        if (ended) return;
        update((current) => ({ ...current, offline: true }));
        if (stream.readyState !== EventSource.CLOSED) return;
        latestHandlers.current.onLost();
        retryTimer = window.setTimeout(connect, Math.min(MAX_RETRY_MS, FIRST_RETRY_MS * 2 ** retries++));
      };
    };

    connect();
    return () => {
      ended = true;
      source?.close();
      window.clearTimeout(retryTimer);
    };
  }, [jobId]);

  return live?.id === jobId ? live : null;
}
