"use client";

import { useMemo } from "react";
import { formatDuration, timeLimitSeconds } from "@/lib/credits";
import type { JobStatus, Machine, WorldProgress } from "@/lib/job-events";
import type { LiveJob } from "@/lib/use-job-stream";
import JobResults, { type JobResultsProps } from "./JobResults";

const MAX_ATTEMPTS = 3;

const COMPACT = new Intl.NumberFormat("en", { notation: "compact", maximumSignificantDigits: 3 });
const PRICE = new Intl.NumberFormat("en", { style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 3 });

/** A machine in plain words, like "64 cores, $0.18/h". */
export function machineText({ cores, dollarsPerHour }: Machine): string {
  return `${cores} cores, ${PRICE.format(dollarsPerHour)}/h`;
}

interface LiveText {
  headline: string;
  details: string[];
}

const worlds = (count: number) => `${COMPACT.format(count)} ${count === 1 ? "world" : "worlds"}`;

const worldDetails = ({ levels, generated, generating }: WorldProgress): string[] => [
  ...(levels === null ? [] : [`${COMPACT.format(levels)} seeds scanned`]),
  `generating ${worlds(generating)}`,
  `${worlds(generated)} generated`,
];

const finishing = (): LiveText => ({ headline: "Finishing up…", details: [] });

const LIVE_TEXT: Record<JobStatus, (live: LiveJob, maxCost: number) => LiveText> = {
  queued: ({ queuePosition }) => ({
    headline: "Waiting for a free server",
    details: queuePosition === null ? [] : [queuePosition <= 1 ? "you're next" : `${queuePosition - 1} ahead of you`],
  }),
  starting: ({ attempt }) => ({
    headline: "Starting a server…",
    details: attempt !== null && attempt > 1 ? [`trying another server (${attempt}/${MAX_ATTEMPTS})`] : [],
  }),
  running: ({ progress, machine }, maxCost) => ({
    headline: "Checking seeds…",
    details: [
      ...(progress?.worlds ? worldDetails(progress.worlds) : []),
      ...(progress ? [`${COMPACT.format(progress.seedsPerSecond)} seeds/s`] : []),
      ...(machine ? [machineText(machine), `up to ${formatDuration(timeLimitSeconds(maxCost, machine.dollarsPerHour))}`] : []),
    ],
  }),
  done: finishing,
  failed: finishing,
  cancelled: finishing,
};

interface LiveSearchProps extends JobResultsProps {
  live: LiveJob;
  stopping: boolean;
  onStop: () => void;
}

export default function LiveSearch({ job, live, stopping, onStop, ...results }: LiveSearchProps) {
  const { headline, details } = LIVE_TEXT[live.status](live, job.maxCost);
  const { status, progress, hits } = live;
  const shown = useMemo(
    () => ({
      ...job,
      status,
      result: progress || hits.length > 0 ? { hits, scanned: progress?.scanned, last_scanned: null, next_seed: null } : null,
    }),
    [job, status, progress, hits],
  );

  return (
    <>
      <div className="live">
        <div className="live__head">
          <p className="live__headline" role="status">
            {headline}
          </p>
          <button type="button" className="link-button link-button--danger" disabled={stopping} onClick={onStop}>
            {stopping ? "stopping…" : "stop search"}
          </button>
        </div>
        {details.length > 0 && (
          <p className="job__meta live__details">
            {details.map((detail) => (
              <span key={detail}>{detail}</span>
            ))}
          </p>
        )}
        {live.offline && <p className="hint">Connection lost, reconnecting…</p>}
      </div>
      <JobResults job={shown} {...results} />
    </>
  );
}
