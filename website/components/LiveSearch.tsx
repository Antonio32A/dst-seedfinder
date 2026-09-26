"use client";

import { Fragment, useMemo } from "react";
import { formatDuration, timeLimitSeconds } from "@/lib/credits";
import type { JobProgress, JobStatus, Machine } from "@/lib/job-events";
import type { LiveJob } from "@/lib/use-job-stream";
import JobResults, { type JobResultsProps } from "./JobResults";

const MAX_ATTEMPTS = 3;

const COMPACT = new Intl.NumberFormat("en", { notation: "compact", maximumSignificantDigits: 3 });
const PRICE = new Intl.NumberFormat("en", { style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 3 });
const GHZ = new Intl.NumberFormat("en", { maximumFractionDigits: 1 });

interface LiveRow {
  label: string;
  value: string;
  note?: string;
}

interface LiveText {
  headline: string;
  notes: string[];
  rows: LiveRow[];
}

const count = (amount: number, noun: string) => `${COMPACT.format(amount)} ${amount === 1 ? noun : `${noun}s`}`;

const progressRows = ({ scanned, seedsPerSecond, worlds }: JobProgress): LiveRow[] => [
  { label: "Scanned", value: count(worlds?.levels ?? scanned, "seed"), note: "quick check of biomes and set pieces" },
  ...(worlds
    ? [
        { label: "Generating", value: count(worlds.generating, "world"), note: "built in full to check distances and turfs" },
        { label: "Generated", value: count(worlds.generated, "world") },
      ]
    : []),
  { label: "Speed", value: `${COMPACT.format(seedsPerSecond)} seeds/s` },
];

const machineRows = ({ cpuName, cores, ghz, dollarsPerHour }: Machine, maxCost: number): LiveRow[] => [
  { label: "Server", value: `${cpuName}, ${cores} cores at ${GHZ.format(ghz)} GHz, ${PRICE.format(dollarsPerHour)}/h` },
  { label: "Time limit", value: `up to ${formatDuration(timeLimitSeconds(maxCost, dollarsPerHour))}` },
];

const finishing = (): LiveText => ({ headline: "Finishing up...", notes: [], rows: [] });

const LIVE_TEXT: Record<JobStatus, (live: LiveJob, maxCost: number) => LiveText> = {
  queued: ({ queuePosition }) => ({
    headline: "Waiting for a free server",
    notes: queuePosition === null ? [] : [queuePosition <= 1 ? "you're next" : `${queuePosition - 1} ahead of you`],
    rows: [],
  }),
  starting: ({ attempt, machine }, maxCost) => ({
    headline: "Starting a server...",
    notes: [
      "This can take a few minutes, but usually takes about 30 seconds.",
      ...(attempt !== null && attempt > 1 ? [`trying another server (${attempt}/${MAX_ATTEMPTS})`] : []),
    ],
    rows: machine ? machineRows(machine, maxCost) : [],
  }),
  running: ({ progress, machine }, maxCost) => ({
    headline: "Checking seeds...",
    notes: [],
    rows: [...(progress ? progressRows(progress) : []), ...(machine ? machineRows(machine, maxCost) : [])],
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
  const { headline, notes, rows } = LIVE_TEXT[live.status](live, job.maxCost);
  const { status, progress, hits } = live;
  const shown = useMemo(
    () => ({ ...job, status, result: progress || hits.length > 0 ? { hits, last_scanned: null, next_seed: null } : null }),
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
            {stopping ? "stopping..." : "stop search"}
          </button>
        </div>
        {notes.map((note) => (
          <p key={note} className="live__details">
            {note}
          </p>
        ))}
        {rows.length > 0 && (
          <dl className="live__stats">
            {rows.map(({ label, value, note }) => (
              <Fragment key={label}>
                <dt>{label}</dt>
                <dd>
                  {value}
                  {note && <span className="muted"> - {note}</span>}
                </dd>
              </Fragment>
            ))}
          </dl>
        )}
        {live.offline && <p className="hint">Connection lost, reconnecting...</p>}
      </div>
      <JobResults job={shown} {...results} />
    </>
  );
}
