"use client";

import { useCallback, useState } from "react";
import { createJob, type JobView } from "@/lib/api-client";
import { copyText } from "@/lib/clipboard";
import { creditsToUnits, formatCredits } from "@/lib/credits";
import { PLATFORM_LABELS } from "@/lib/seedfinder-config";
import type { Account } from "@/lib/use-account";
import ConfirmDialog from "./ConfirmDialog";
import JobResults, { type JobResultsProps } from "./JobResults";

const STATUS_LABELS: Record<JobView["status"], string> = {
  queued: "Queued",
  running: "Searching…",
  done: "Done",
  failed: "Failed",
  cancelled: "Cancelled",
};

const DATE_FORMAT = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

interface Continuation {
  job: JobView;
  startSeed: number;
}

interface JobItemProps extends JobResultsProps {
  failure?: string;
}

function JobItem({ job, failure, ...results }: JobItemProps) {
  return (
    <li className="job">
      <div className="job__meta">
        <span className={`job__status job__status--${job.status}`}>{STATUS_LABELS[job.status] ?? job.status}</span>
        <span>{job.wanted} seeds wanted</span>
        {job.config.platform && <span>{PLATFORM_LABELS[job.config.platform]} world</span>}
        <span>
          {job.cost === null
            ? `reserved ${formatCredits(job.maxCost)}`
            : `cost ${formatCredits(job.cost)} of max ${formatCredits(job.maxCost)}`}
        </span>
        <time dateTime={job.createdAt}>{DATE_FORMAT.format(new Date(job.createdAt))}</time>
      </div>
      {job.error && <p className="notice notice--error">{job.error}</p>}
      <JobResults job={job} {...results} />
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
  const [startingJobId, setStartingJobId] = useState<string | null>(null);
  const [failure, setFailure] = useState<{ jobId: string; message: string } | null>(null);

  const copy = useCallback(
    async (text: string, what: string) => onNotify((await copyText(text)) ? `${what} copied.` : "Couldn't copy. Select the text instead."),
    [onNotify],
  );

  const searchFurther = async ({ job, startSeed }: Continuation) => {
    setPending(null);
    setStartingJobId(job.id);
    setFailure(null);
    try {
      await createJob({ config: job.config, wanted: job.wanted, maxCost: job.maxCost, startSeed });
      onNotify(`Search started from seed ${startSeed}.`);
    } catch (caught) {
      setFailure({ jobId: job.id, message: caught instanceof Error ? caught.message : "Something went wrong. Try again." });
    } finally {
      setStartingJobId(null);
      await account.refresh();
    }
  };

  const blockedReason = (job: JobView) =>
    user && creditsToUnits(user.credits) < creditsToUnits(job.maxCost)
      ? `needs ${formatCredits(job.maxCost)} credits, you have ${formatCredits(user.credits)}`
      : undefined;

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
            onCopy={copy}
            further={{
              busy: startingJobId === job.id,
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
        onConfirm={() => pending && void searchFurther(pending)}
        onCancel={() => setPending(null)}
      />
    </section>
  );
}
