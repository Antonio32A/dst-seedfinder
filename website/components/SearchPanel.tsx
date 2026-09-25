"use client";

import { useState } from "react";
import { ApiError, createJob, loginUrl, type JobView, type SessionUser } from "@/lib/api-client";
import { creditsToUnits, formatCredits } from "@/lib/credits";
import { isActiveStatus } from "@/lib/job-events";
import { WANTED_OPTIONS, type Issue } from "@/lib/search-state";
import {
  PLATFORM_LABELS,
  PLATFORMS,
  usesWorldFilters,
  worldFiltersUnavailable,
  type Platform,
  type SeedfinderConfig,
} from "@/lib/seedfinder-config";
import type { Account } from "@/lib/use-account";
import { validateJobRequest } from "@/lib/validate-config";
import MaxCostField from "./MaxCostField";
import SegmentedControl from "./SegmentedControl";

interface SearchPanelProps {
  config: SeedfinderConfig;
  issues: Issue[];
  platform: Platform;
  onPlatformChange: (platform: Platform) => void;
  wanted: number;
  onWantedChange: (wanted: number) => void;
  maxCost: number;
  onMaxCostChange: (maxCost: number) => void;
  account: Account;
  onNotify: (text: string) => void;
}

function blockingProblem(issues: Issue[], config: SeedfinderConfig, credits: number | undefined, maxCost: number): string | undefined {
  if (issues.some((issue) => issue.severity === "error")) return "Fix the errors above first.";
  const unavailable = usesWorldFilters(config) ? worldFiltersUnavailable(config.platform) : undefined;
  if (unavailable) return `${unavailable} Remove the world details to search.`;
  if (credits !== undefined && creditsToUnits(credits) < creditsToUnits(maxCost)) {
    return `Max cost is ${formatCredits(maxCost)} credits but you have ${formatCredits(credits)}. Lower it or wait for the 00:00 UTC refill.`;
  }
  return undefined;
}

interface SearchActionProps {
  user: SessionUser | null;
  activeJob: JobView | undefined;
  submitting: boolean;
  blocked: boolean;
  onSubmit: () => void;
}

function SearchAction({ user, activeJob, submitting, blocked, onSubmit }: SearchActionProps) {
  if (!user) {
    return (
      <a className="button" href={loginUrl()}>
        Log in with Discord to search
      </a>
    );
  }
  if (activeJob) {
    return (
      <a className="button" href={`#job-${activeJob.id}`}>
        Watch your search
      </a>
    );
  }
  return (
    <button type="button" disabled={submitting || blocked} onClick={onSubmit}>
      {submitting ? "Starting…" : "Find seeds"}
    </button>
  );
}

export default function SearchPanel({
  config,
  issues,
  platform,
  onPlatformChange,
  wanted,
  onWantedChange,
  maxCost,
  onMaxCostChange,
  account,
  onNotify,
}: SearchPanelProps) {
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const { user, jobs } = account;
  const activeJob = jobs.find((job) => isActiveStatus(job.status));
  const problem = activeJob ? undefined : blockingProblem(issues, config, user?.credits, maxCost);

  const submit = async () => {
    const checked = validateJobRequest({ config, wanted, maxCost });
    if (!checked.ok) {
      setError(`This search can't be sent: ${checked.error}`);
      return;
    }
    setSubmitting(true);
    setError("");
    try {
      await createJob(checked.value);
      onNotify("Search started. Follow it under “Your searches”.");
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 409) onNotify("You already have a search going. It's under “Your searches”.");
      else setError(caught instanceof Error ? caught.message : "Something went wrong. Try again.");
    } finally {
      setSubmitting(false);
      await account.refresh();
    }
  };

  return (
    <section className="section search" aria-labelledby="search">
      <h2 id="search" className="section-title">
        Search
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
          legend="Platform"
          options={PLATFORMS.map((value) => ({ value, label: PLATFORM_LABELS[value] }))}
          value={platform}
          onChange={onPlatformChange}
        />
        <p className="hint">The OS of the computer or server that creates the world. Only world details differ between them.</p>
      </div>
      <SegmentedControl
        legend="Seeds to find"
        options={WANTED_OPTIONS.map((value) => ({ value, label: String(value) }))}
        value={wanted}
        onChange={onWantedChange}
      />
      <MaxCostField value={maxCost} wanted={wanted} onChange={onMaxCostChange} />
      <div className="search__actions">
        <SearchAction user={user} activeJob={activeJob} submitting={submitting} blocked={problem !== undefined} onSubmit={() => void submit()} />
        <span className="search__cost">
          {activeJob ? (
            "You can run one search at a time."
          ) : (
            <>
              Reserves <strong>{formatCredits(maxCost)}</strong> credits{user ? ` (you have ${formatCredits(user.credits)})` : ""}.
            </>
          )}
        </span>
      </div>
      {!user && <p className="hint">Your settings are kept while you log in.</p>}
      {user && problem && <p className="notice notice--error">{problem}</p>}
      {error && (
        <p className="notice notice--error" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}
