"use client";

import { Fragment, useCallback, useMemo } from "react";
import type { LocalSearchState } from "@/lib/browser-search/local-search";
import { copyText } from "@/lib/client/clipboard";
import JobResults, { type ShownJob } from "./JobResults";
import { checkedNote } from "./checked-note";

const COMPACT = new Intl.NumberFormat("en", { notation: "compact", maximumSignificantDigits: 3 });

const HEADLINES: Partial<Record<LocalSearchState["status"], string>> = {
    starting: "Loading the seedfinder...",
    running: "Checking seeds in your browser..."
};

interface LocalSearchProps {
    state: LocalSearchState;
    onStop: () => void;
    onSearchFurther: (startSeed: number) => void;
    onNotify: (text: string) => void;
}

export default function LocalSearch({ state, onStop, onSearchFurther, onNotify }: LocalSearchProps) {
    const { request, status, search, seedsPerSecond, generatesWorlds, error } = state;
    const headline = HEADLINES[status];
    const scanned = search.scanned ?? 0;

    const copy = useCallback(
            async (text: string, what: string) => onNotify((await copyText(text)) ? `${what} copied.` : "Couldn't copy. Select the text instead."),
            [onNotify]
    );

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
        { label: "Speed", value: `${COMPACT.format(seedsPerSecond)} seeds/s` },
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
                            {status === "running" && (
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
                        </div>
                )}
                {status === "cancelled" && <p className="muted">You stopped this search.</p>}
                {error && (
                        <p className="notice notice--error" role="alert">
                            {error}
                        </p>
                )}
                <JobResults job={job} onCopy={copy} further={{ busy: false, onStart: onSearchFurther }}/>
            </section>
    );
}
