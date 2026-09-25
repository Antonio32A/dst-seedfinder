"use client";

import { useCallback, useState } from "react";
import { cancelJob, createJob, type JobView } from "@/lib/api-client";
import { copyText } from "@/lib/clipboard";
import { creditsToUnits, formatCredits, STARTING_FEE } from "@/lib/credits";
import { isActiveStatus, type JobStatus } from "@/lib/job-events";
import { PLATFORM_LABELS } from "@/lib/seedfinder-config";
import type { Account } from "@/lib/use-account";
import { liveJobOf, type LiveJob } from "@/lib/use-job-stream";
import ConfirmDialog from "./ConfirmDialog";
import JobResults, { type JobResultsProps } from "./JobResults";
import LiveSearch, { machineText } from "./LiveSearch";

const STATUS_LABELS: Record<JobStatus, string> = {
  queued: "Queued",
  starting: "Starting…",
  running: "Searching…",
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

interface JobItemProps extends JobResultsProps {
  live: LiveJob | null;
  stopping: boolean;
  onStop: (request: StopRequest) => void;
  failure?: string;
}

function JobItem({ job, live, stopping, onStop, failure, ...results }: JobItemProps) {
  const current = isActiveStatus(job.status) ? (live ?? liveJobOf(job)) : null;
  const status = current?.status ?? job.status;
  return (
    <li className="job" id={`job-${job.id}`}>
      <div className="job__meta">
        <span className={`job__status job__status--${status}`}>{STATUS_LABELS[status] ?? status}</span>
        <span>{job.wanted} seeds wanted</span>
        {job.config.platform && <span>{PLATFORM_LABELS[job.config.platform]} world</span>}
        <span>
          {job.cost === null
            ? `reserved ${formatCredits(job.maxCost)}`
            : `cost ${formatCredits(job.cost)} of max ${formatCredits(job.maxCost)}`}
        </span>
        {!current && job.machine && <span>{machineText(job.machine)}</span>}
        <time dateTime={job.createdAt}>{DATE_FORMAT.format(new Date(job.createdAt))}</time>
      </div>
      {job.error && <p className="notice notice--error">{job.error}</p>}
      {current ? (
        <LiveSearch job={job} live={current} stopping={stopping} onStop={() => onStop({ jobId: job.id, status })} {...results} />
      ) : (
        <JobResults job={job} {...results} />
      )}
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
  const { jobs, user, live } = account;
  const [pending, setPending] = useState<Continuation | null>(null);
  const [stopRequest, setStopRequest] = useState<StopRequest | null>(null);
  const [busyJobId, setBusyJobId] = useState<string | null>(null);
  const [failure, setFailure] = useState<{ jobId: string; message: string } | null>(null);
  const searching = jobs.some((job) => isActiveStatus(job.status));

  const copy = useCallback(
    async (text: string, what: string) => onNotify((await copyText(text)) ? `${what} copied.` : "Couldn't copy. Select the text instead."),
    [onNotify],
  );

  const runFor = async (jobId: string, action: () => Promise<string>) => {
    setBusyJobId(jobId);
    setFailure(null);
    try {
      onNotify(await action());
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
      return `Search started from seed ${startSeed}.`;
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
    if (searching) return "one search at a time, wait for yours to finish";
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
            live={live?.id === job.id ? live : null}
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
            ? `Same search, starting at seed ${pending.startSeed}, for up to ${pending.job.wanted} more seeds. Reserves ${formatCredits(pending.job.maxCost)} credits, unused ones are refunded.`
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
