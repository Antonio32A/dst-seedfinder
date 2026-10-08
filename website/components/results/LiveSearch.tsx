"use client";

import { useEffect, useMemo, useState } from "react";
import type { LiveJob } from "@/lib/client/use-job-stream";
import { formatDuration, timeLimitSeconds } from "@/lib/jobs/credits";
import type { JobProgress, JobStatus, JobView, Machine } from "@/lib/jobs/job-events";
import JobResults, { type JobResultsProps } from "./JobResults";
import LiveStats, { checkedNote, type LiveRow } from "./LiveStats";
import SearchSpeeds from "./SearchSpeeds";
import SearchTimings from "./SearchTimings";

const MAX_ATTEMPTS = 3;

const COMPACT = new Intl.NumberFormat("en", { notation: "compact", maximumSignificantDigits: 3 });
const PRICE = new Intl.NumberFormat("en", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 3
});
const GHZ = new Intl.NumberFormat("en", { maximumFractionDigits: 1 });

interface LiveText {
    headline: string;
    notes: string[];
    rows: LiveRow[];
}

const count = (amount: number, noun: string) => `${COMPACT.format(amount)} ${amount === 1 ? noun : `${noun}s`}`;

interface Clock {
    maxCost: number;
    runningSince: number | null;
    now: number;
}

const progressRows = ({ scanned, worlds }: JobProgress): LiveRow[] => [
    { label: "Checked", value: count(scanned, "seed"), note: checkedNote(worlds !== undefined) },
    ...(worlds
            ? [
                {
                    label: "Generating",
                    value: count(worlds.generating, "world"),
                    note: "generated to check distances and turfs"
                },
                { label: "Generated", value: count(worlds.generated, "world") }
            ]
            : [])
];

const machineRows = ({ cpuName, cores, ghz, dollarsPerHour }: Machine, {
    maxCost,
    runningSince,
    now
}: Clock): LiveRow[] => {
    const limit = timeLimitSeconds(maxCost, dollarsPerHour);
    const left = runningSince === null ? `up to ${formatDuration(limit)}` : formatDuration(Math.max(0, Math.ceil(limit - (now - runningSince) / 1000)));
    return [
        {
            label: "Server",
            value: `${cpuName}, ${cores} cores at ${GHZ.format(ghz)} GHz, ${PRICE.format(dollarsPerHour)}/h`
        },
        { label: "Time left", value: left }
    ];
};

const finishing = (): LiveText => ({ headline: "Finishing up...", notes: [], rows: [] });

const LIVE_TEXT: Record<JobStatus, (live: LiveJob, clock: Clock) => LiveText> = {
    queued: ({ queuePosition }) => ({
        headline: "Waiting for a free server",
        notes: queuePosition === null ? [] : [queuePosition <= 1 ? "you're next" : `${queuePosition - 1} ahead of you`],
        rows: []
    }),
    starting: ({ attempt, machine }, clock) => ({
        headline: "Starting a server...",
        notes: [
            "This can take a few minutes, but usually takes about 30 seconds.",
            ...(attempt !== null && attempt > 1 ? [`trying another server (${attempt}/${MAX_ATTEMPTS})`] : [])
        ],
        rows: machine ? machineRows(machine, clock) : []
    }),
    running: ({ progress, machine }, clock) => ({
        headline: "Checking seeds...",
        notes: [],
        rows: [...(progress ? progressRows(progress) : []), ...(machine ? machineRows(machine, clock) : [])]
    }),
    done: finishing,
    failed: finishing,
    cancelled: finishing
};

interface LiveSearchProps extends Omit<JobResultsProps, "job"> {
    job: JobView;
    live: LiveJob;
    stopping: boolean;
    onStop: () => void;
}

export default function LiveSearch({ job, live, stopping, onStop, ...results }: LiveSearchProps) {
    const [now, setNow] = useState(Date.now);
    const runningSince = job.startedAt === null ? live.runningSince : Date.parse(job.startedAt);
    const ticking = live.status === "running" && runningSince !== null;
    const { headline, notes, rows } = LIVE_TEXT[live.status](live, { maxCost: job.maxCost, runningSince, now });

    useEffect(() => {
        if (!ticking) return;
        const timer = window.setInterval(() => setNow(Date.now()), 1000);
        return () => window.clearInterval(timer);
    }, [ticking]);
    const { status, progress, hits } = live;
    const shown = useMemo(
            () => ({
                ...job,
                status,
                result: progress || hits.length > 0 ? { hits, last_scanned: null, next_seed: null } : null
            }),
            [job, status, progress, hits]
    );

    return (
            <>
                <div className="live">
                    <div className="live__head">
                        <p className="live__headline" role="status">
                            {headline}
                        </p>
                        <button type="button" className="link-button link-button--danger" disabled={stopping}
                                onClick={onStop}>
                            {stopping ? "stopping..." : "stop search"}
                        </button>
                    </div>
                    {notes.map((note) => (
                            <p key={note} className="live__details">
                                {note}
                            </p>
                    ))}
                    {rows.length > 0 && <LiveStats rows={rows}/>}
                    {live.status === "running" && progress?.speeds && <SearchSpeeds speeds={progress.speeds}/>}
                    {live.status === "running" && progress?.timings &&
                            <SearchTimings timings={progress.timings} filters={job.config.filters}/>}
                    {live.offline && <p className="hint">Connection lost, reconnecting...</p>}
                </div>
                <JobResults job={shown} {...results} />
            </>
    );
}
