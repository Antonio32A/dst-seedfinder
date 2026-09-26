"use client";

import { useCallback, useMemo, useState } from "react";
import { cancelJob, createJob, type JobView } from "@/lib/api-client";
import { copyText } from "@/lib/clipboard";
import { creditsToUnits, formatCredits, STARTING_FEE } from "@/lib/credits";
import { isActiveStatus, MAX_ACTIVE_SEARCHES, type JobStatus } from "@/lib/job-events";
import { parseJobResult } from "@/lib/job-result";
import type { Account } from "@/lib/use-account";
import { liveJobOf, useJobStream } from "@/lib/use-job-stream";
import ConfirmDialog from "./ConfirmDialog";
import JobResults, { type JobResultsProps } from "./JobResults";
import LiveSearch from "./LiveSearch";

const STATUS_LABELS: Record<JobStatus, string> = {
  queued: "Queued",
  starting: "Starting...",
  running: "Searching...",
  done: "Done",
  failed: "Failed",
  cancelled: "Stopped",
};

const STOP_NOTES: Partial<Record<JobStatus, string>> = {
  queued: "You'll lose your place in line. Nothing has been charged.",
  starting: `If a server has already started, the ${STARTING_FEE} credit start fee is charged.`,
  running: `Seeds found so far are kept. You pay the ${STARTING_FEE} credit start fee plus the time it ran.`,
};

const DATE_FORMAT = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

interface Continuation {
  job: JobView;
  startSeed: number;
}

interface StopRequest {
  jobId: string;
  status: JobStatus;
}

interface JobItemProps extends Omit<JobResultsProps, "job"> {
  job: JobView;
  onEnded: (job: JobView) => void;
  onLost: () => void;
  stopping: boolean;
  onStop: (request: StopRequest) => void;
  failure?: string;
}

function JobItem({ job, onEnded, onLost, stopping, onStop, failure, ...results }: JobItemProps) {
  const active = isActiveStatus(job.status);
  const live = useJobStream(active ? job.id : null, { onEnd: onEnded, onLost });
  const current = active ? (live ?? liveJobOf(job)) : null;
  const status = current?.status ?? job.status;
  const [openAtFirst] = useState(active);
  const found = useMemo(() => {
    const parsed = active ? null : parseJobResult(job.result);
    return parsed?.kind === "search" ? parsed.search.hits.length : null;
  }, [active, job.result]);
  return (
    <li className="job" id={`job-${job.id}`}>
      <details className="job__details" open={openAtFirst}>
        <summary className="job__meta">
          <span className={`job__status job__status--${status}`}>{STATUS_LABELS[status] ?? status}</span>
          {found !== null && <span>{found === 1 ? "1 seed" : `${found} seeds`} found</span>}
          {job.cost !== null && <span>cost {formatCredits(job.cost)} credits</span>}
          <time dateTime={job.createdAt}>{DATE_FORMAT.format(new Date(job.createdAt))}</time>
        </summary>
        {job.error && <p className="notice notice--error">{job.error}</p>}
        {current ? (
          <LiveSearch job={job} live={current} stopping={stopping} onStop={() => onStop({ jobId: job.id, status })} {...results} />
        ) : (
          <JobResults job={job} {...results} />
        )}
      </details>
      {failure && (
        <p className="notice notice--error" role="alert">
          {failure}
        </p>
      )}
    </li>
  );
}

interface JobsListProps {
  account: Account;
  onNotify: (text: string) => void;
}

export default function JobsList({ account, onNotify }: JobsListProps) {
  const { jobs, user } = account;
  const [pending, setPending] = useState<Continuation | null>(null);
  const [stopRequest, setStopRequest] = useState<StopRequest | null>(null);
  const [busyJobId, setBusyJobId] = useState<string | null>(null);
  const [failure, setFailure] = useState<{ jobId: string; message: string } | null>(null);
  const atLimit = jobs.filter((job) => isActiveStatus(job.status)).length >= MAX_ACTIVE_SEARCHES;

  const copy = useCallback(
    async (text: string, what: string) => onNotify((await copyText(text)) ? `${what} copied.` : "Couldn't copy. Select the text instead."),
    [onNotify],
  );

  const runFor = async (jobId: string, action: () => Promise<string | void>) => {
    setBusyJobId(jobId);
    setFailure(null);
    try {
      const message = await action();
      if (message) onNotify(message);
    } catch (caught) {
      setFailure({ jobId, message: caught instanceof Error ? caught.message : "Something went wrong. Try again." });
    } finally {
      setBusyJobId(null);
      await account.refresh();
    }
  };

  const searchFurther = ({ job, startSeed }: Continuation) => {
    setPending(null);
    void runFor(job.id, async () => {
      await createJob({ config: job.config, wanted: job.wanted, maxCost: job.maxCost, startSeed });
    });
  };

  const stop = ({ jobId }: StopRequest) => {
    setStopRequest(null);
    void runFor(jobId, async () => {
      await cancelJob(jobId);
      return "Search stopped.";
    });
  };

  const blockedReason = (job: JobView) => {
    if (atLimit) return `up to ${MAX_ACTIVE_SEARCHES} searches at once, wait for one to finish`;
    return user && creditsToUnits(user.credits) < creditsToUnits(job.maxCost)
      ? `needs ${formatCredits(job.maxCost)} credits, you have ${formatCredits(user.credits)}`
      : undefined;
  };

  return (
    <section className="section" aria-labelledby="jobs">
      <h2 id="jobs" className="section-title">
        Your searches
      </h2>
      {jobs.length === 0 && <p className="muted">No searches yet.</p>}
      <ul className="jobs">
        {jobs.map((job) => (
          <JobItem
            key={job.id}
            job={job}
            onEnded={account.jobEnded}
            onLost={() => void account.refresh()}
            stopping={busyJobId === job.id}
            onStop={setStopRequest}
            onCopy={copy}
            further={{
              busy: busyJobId === job.id,
              blocked: blockedReason(job),
              onStart: (startSeed) => setPending({ job, startSeed }),
            }}
            failure={failure?.jobId === job.id ? failure.message : undefined}
          />
        ))}
      </ul>
      <ConfirmDialog
        open={pending !== null}
        title="Search further?"
        message={
          pending
            ? `Same search, starting at seed ${pending.startSeed}, for up to ${pending.job.wanted} more ${pending.job.wanted === 1 ? "seed" : "seeds"}. Reserves ${formatCredits(pending.job.maxCost)} credits, unused ones are refunded.`
            : ""
        }
        confirmLabel="Search further"
        onConfirm={() => pending && searchFurther(pending)}
        onCancel={() => setPending(null)}
      />
      <ConfirmDialog
        open={stopRequest !== null}
        title="Stop this search?"
        message={(stopRequest && STOP_NOTES[stopRequest.status]) ?? ""}
        confirmLabel="Stop search"
        danger
        onConfirm={() => stopRequest && stop(stopRequest)}
        onCancel={() => setStopRequest(null)}
      />
    </section>
  );
}
