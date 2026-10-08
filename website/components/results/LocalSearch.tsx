"use client";

import { useMemo } from "react";
import type { LocalSearchState } from "@/lib/browser-search/local-search";
import JobResults, { type JobResultsProps, type ShownJob } from "./JobResults";
import LiveStats, { checkedNote } from "./LiveStats";
import SearchSpeeds from "./SearchSpeeds";
import SearchTimings from "./SearchTimings";

const COMPACT = new Intl.NumberFormat("en", { notation: "compact", maximumSignificantDigits: 3 });

const HEADLINES: Partial<Record<LocalSearchState["status"], string>> = {
    starting: "Loading the seedfinder...",
    running: "Checking seeds in your browser..."
};

interface LocalSearchProps {
    state: LocalSearchState;
    onStop: () => void;
    onSearchFurther: (startSeed: number) => void;
    onCopy: JobResultsProps["onCopy"];
}

export default function LocalSearch({ state, onStop, onSearchFurther, onCopy }: LocalSearchProps) {
    const { request, status, search, speeds, timings, generatesWorlds, error } = state;
    const headline = HEADLINES[status];
    const scanned = search.scanned ?? 0;

    const job = useMemo<ShownJob>(() => {
        const empty = status === "starting" || (status === "failed" && search.hits.length === 0);
        const live = { hits: search.hits, last_scanned: null, next_seed: null };
        return { status, config: request.config, result: empty ? null : headline ? live : search, error };
    }, [headline, status, request.config, search, error]);

    const rows = [
        {
            label: "Checked",
            value: `${COMPACT.format(scanned)} ${scanned === 1 ? "seed" : "seeds"}`,
            note: checkedNote(generatesWorlds)
        },
        { label: "Threads", value: String(request.threads) }
    ];

    return (
            <section className="section" aria-labelledby="browser-search">
                <h2 id="browser-search" className="section-title">
                    Browser search
                </h2>
                {headline && (
                        <div className="live">
                            <div className="live__head">
                                <p className="live__headline" role="status">
                                    {headline}
                                </p>
                                <button type="button" className="link-button link-button--danger" onClick={onStop}>
                                    stop search
                                </button>
                            </div>
                            <p className="live__details">Keep this tab open. Closing or reloading it stops the
                                search.</p>
                            {status === "running" && <LiveStats rows={rows}/>}
                            {status === "running" && speeds && <SearchSpeeds speeds={speeds}/>}
                            {status === "running" && timings && <SearchTimings timings={timings}/>}
                        </div>
                )}
                {status === "cancelled" && <p className="muted">You stopped this search.</p>}
                {error && (
                        <p className="notice notice--error" role="alert">
                            {error}
                        </p>
                )}
                <JobResults job={job} onCopy={onCopy} further={{ busy: false, onStart: onSearchFurther }}/>
            </section>
    );
}
