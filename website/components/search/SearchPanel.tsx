"use client";

import { useState } from "react";
import SegmentedControl from "@/components/ui/SegmentedControl";
import Stepper from "@/components/ui/Stepper";
import { type LocalSearchRequest, MEMORY_PER_THREAD_MB, type SearchTarget } from "@/lib/browser-search/local-search";
import { ApiError, createJob, loginUrl, type SessionUser } from "@/lib/client/api-client";
import type { Account } from "@/lib/client/use-account";
import {
    DEFAULT_START_SEED,
    type Platform,
    PLATFORM_LABELS,
    PLATFORMS,
    type SeedfinderConfig
} from "@/lib/config/seedfinder-config";
import { validateJobRequest } from "@/lib/config/validate-config";
import { type Issue, WANTED_OPTIONS } from "@/lib/criteria/search-state";
import { creditsToUnits, formatCredits } from "@/lib/jobs/credits";
import { isActiveStatus, MAX_ACTIVE_SEARCHES } from "@/lib/jobs/job-events";
import { SEED_SPACE } from "@/lib/jobs/job-result";
import MaxCostField from "./MaxCostField";

export interface BrowserSearchOptions {
    supported: boolean | null;
    cores: number;
    threads: number;
    onThreadsChange: (threads: number) => void;
    running: boolean;
    onStart: (request: LocalSearchRequest) => void;
}

interface SearchPanelProps {
    config: SeedfinderConfig;
    issues: Issue[];
    platform: Platform;
    onPlatformChange: (platform: Platform) => void;
    target: SearchTarget;
    onTargetChange: (target: SearchTarget) => void;
    wanted: number;
    onWantedChange: (wanted: number) => void;
    maxCost: number;
    onMaxCostChange: (maxCost: number) => void;
    browser: BrowserSearchOptions;
    account: Account;
    onNotify: (text: string) => void;
}

const START_SEED_PROBLEM = `The start seed has to be a whole number from 0 to ${SEED_SPACE - 1}.`;
const UNSUPPORTED = "This browser can't run the seedfinder: it needs WebAssembly threads.";
const MEMORY = new Intl.NumberFormat("en", { maximumFractionDigits: 1 });

const TARGET_HINTS: Record<SearchTarget, string> = {
    cloud: "Server that spends my money, but is usually faster. Uses credits and requires you to log in.",
    browser: "Runs on your computer in the browser, but slightly slower and stops if you close the tab."
};

function blockingProblem(issues: Issue[], credits: number | undefined, maxCost: number, startSeed: number | null): string | undefined {
    if (issues.some((issue) => issue.severity === "error")) return "Fix the errors above first.";
    if (startSeed === null) return START_SEED_PROBLEM;
    if (credits !== undefined && creditsToUnits(credits) < creditsToUnits(maxCost)) {
        return `Max cost is ${formatCredits(maxCost)} credits but you have ${formatCredits(credits)}. Lower it or wait for the 00:00 UTC refill.`;
    }
    return undefined;
}

interface CloudActionProps {
    user: SessionUser | null;
    atLimit: boolean;
    submitting: boolean;
    blocked: boolean;
    maxCost: number;
    onSubmit: () => void;
}

function CloudButton({ user, atLimit, submitting, blocked, onSubmit }: CloudActionProps) {
    if (!user) {
        return (
                <a className="button" href={loginUrl()}>
                    Log in with Discord to search
                </a>
        );
    }
    if (atLimit) {
        return (
                <a className="button" href="#jobs">
                    Watch your searches
                </a>
        );
    }
    return (
            <button type="button" disabled={submitting || blocked} onClick={onSubmit}>
                {submitting ? "Starting..." : "Find seeds"}
            </button>
    );
}

function CloudAction(props: CloudActionProps) {
    const { user, atLimit, maxCost } = props;
    return (
            <>
                <CloudButton {...props} />
                <span className="search__cost">
        {atLimit ? (
                `You can run up to ${MAX_ACTIVE_SEARCHES} searches at once.`
        ) : (
                <>
                    Reserves <strong>{formatCredits(maxCost)}</strong> credits{user ? ` (you have ${formatCredits(user.credits)})` : ""}.
                </>
        )}
      </span>
            </>
    );
}

function ThreadsField({ browser }: { browser: BrowserSearchOptions }) {
    const { cores, threads, onThreadsChange } = browser;
    return (
            <div>
                <div className="threads">
                    <span className="seg__legend">CPU threads</span>
                    <Stepper label="CPU threads" value={threads} min={1} max={cores} onChange={onThreadsChange}/>
                </div>
                <p className="hint">
                    {threads} {threads === 1 ? "thread" : "threads"} will consume
                    ~{MEMORY.format((threads * MEMORY_PER_THREAD_MB) / 1024)}GB of RAM.
                </p>
            </div>
    );
}

interface BrowserActionProps {
    browser: BrowserSearchOptions;
    blocked: boolean;
    wanted: number;
    onStart: () => void;
}

function BrowserAction({ browser, blocked, wanted, onStart }: BrowserActionProps) {
    if (browser.running) {
        return (
                <>
                    <a className="button" href="#browser-search">
                        Watch your search
                    </a>
                    <span className="search__cost">A browser search is already running.</span>
                </>
        );
    }
    return (
            <>
                <button type="button" disabled={blocked || browser.supported !== true} onClick={onStart}>
                    Find seeds
                </button>
                <span className="search__cost">
        <strong>Free</strong>, runs until it finds {wanted} {wanted === 1 ? "seed" : "seeds"} or you stop it.
      </span>
            </>
    );
}

export default function SearchPanel({
                                        config,
                                        issues,
                                        platform,
                                        onPlatformChange,
                                        target,
                                        onTargetChange,
                                        wanted,
                                        onWantedChange,
                                        maxCost,
                                        onMaxCostChange,
                                        browser,
                                        account,
                                        onNotify
                                    }: SearchPanelProps) {
    const [submitting, setSubmitting] = useState(false);
    const [error, setError] = useState("");
    const [startSeedDraft, setStartSeedDraft] = useState("");
    const { user, jobs } = account;
    const inBrowser = target === "browser";
    const startSeedText = startSeedDraft.trim() || String(DEFAULT_START_SEED);
    const startSeed = /^\d+$/.test(startSeedText) && Number(startSeedText) < SEED_SPACE ? Number(startSeedText) : null;
    const atLimit = !inBrowser && jobs.filter((job) => isActiveStatus(job.status)).length >= MAX_ACTIVE_SEARCHES;
    const problem = atLimit ? undefined : blockingProblem(issues, inBrowser ? undefined : user?.credits, maxCost, startSeed);

    const checkedRequest = () => {
        const checked = validateJobRequest({ config, wanted, maxCost, startSeed });
        if (!checked.ok) setError(`This search can't be sent: ${checked.error}`);
        return checked.ok ? checked.value : null;
    };

    const submit = async () => {
        const request = checkedRequest();
        if (request === null) return;
        setSubmitting(true);
        setError("");
        try {
            await createJob(request);
        } catch (caught) {
            if (caught instanceof ApiError && caught.status === 409) onNotify(`You already have ${MAX_ACTIVE_SEARCHES} searches going. They're under "Your searches".`);
            else setError(caught instanceof Error ? caught.message : "Something went wrong. Try again.");
        } finally {
            setSubmitting(false);
            await account.refresh();
        }
    };

    const startInBrowser = () => {
        const request = checkedRequest();
        if (request === null) return;
        setError("");
        browser.onStart({
            config: request.config,
            wanted: request.wanted,
            startSeed: request.startSeed ?? DEFAULT_START_SEED,
            threads: browser.threads
        });
    };

    return (
            <section className="section search" aria-labelledby="search">
                <h2 id="search" className="section-title">
                    Find seeds
                </h2>
                {issues.length > 0 && (
                        <ul className="issues">
                            {issues.map((issue, index) => (
                                    <li key={index} className={`notice notice--${issue.severity}`}>
                                        {issue.message}
                                    </li>
                            ))}
                        </ul>
                )}
                <div>
                    <SegmentedControl
                            legend="Search with"
                            options={[
                                {
                                    value: "browser",
                                    label: "Your browser",
                                    disabled: browser.supported === false,
                                    title: browser.supported === false ? UNSUPPORTED : undefined
                                },
                                { value: "cloud", label: "Cloud server" }
                            ]}
                            value={target}
                            onChange={onTargetChange}
                    />
                    <p className="hint">
                        {TARGET_HINTS[target]}
                        {browser.supported === false && ` ${UNSUPPORTED}`}
                    </p>
                </div>
                <div className="search__row">
                    <SegmentedControl
                            legend="Seeds to find"
                            options={WANTED_OPTIONS.map((value) => ({ value, label: String(value) }))}
                            value={wanted}
                            onChange={onWantedChange}
                    />
                    <label className="start-seed">
                        <span className="seg__legend">Start seed</span>
                        <input
                                type="text"
                                inputMode="numeric"
                                placeholder={String(DEFAULT_START_SEED)}
                                value={startSeedDraft}
                                onChange={(event) => setStartSeedDraft(event.target.value)}
                        />
                    </label>
                </div>
                <div>
                    <SegmentedControl
                            legend="Platform"
                            options={PLATFORMS.map((value) => ({ value, label: PLATFORM_LABELS[value] }))}
                            value={platform}
                            onChange={onPlatformChange}
                    />
                    <p className="hint">The OS of the computer that generates the world.</p>
                </div>
                {inBrowser ? <ThreadsField browser={browser}/> :
                        <MaxCostField value={maxCost} wanted={wanted} onChange={onMaxCostChange}/>}
                <div className="search__actions">
                    {inBrowser ? (
                            <BrowserAction browser={browser} blocked={problem !== undefined} wanted={wanted}
                                           onStart={startInBrowser}/>
                    ) : (
                            <CloudAction
                                    user={user}
                                    atLimit={atLimit}
                                    submitting={submitting}
                                    blocked={problem !== undefined}
                                    maxCost={maxCost}
                                    onSubmit={() => void submit()}
                            />
                    )}
                </div>
                {!inBrowser && !user && <p className="hint">Your settings are kept while you log in.</p>}
                {(inBrowser || user) && problem && <p className="notice notice--error">{problem}</p>}
                {error && (
                        <p className="notice notice--error" role="alert">
                            {error}
                        </p>
                )}
            </section>
    );
}
