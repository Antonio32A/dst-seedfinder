"use client";

import { useState } from "react";
import { ApiError, createJob, loginUrl, type SessionUser } from "@/lib/api-client";
import { creditsToUnits, formatCredits } from "@/lib/credits";
import { isActiveStatus, MAX_ACTIVE_SEARCHES } from "@/lib/job-events";
import { SEED_SPACE } from "@/lib/job-result";
import { WANTED_OPTIONS, type Issue } from "@/lib/search-state";
import {
  DEFAULT_START_SEED,
  PLATFORM_LABELS,
  PLATFORMS,
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

const START_SEED_PROBLEM = `The start seed has to be a whole number from 0 to ${SEED_SPACE - 1}.`;

function blockingProblem(issues: Issue[], credits: number | undefined, maxCost: number, startSeed: number | null): string | undefined {
  if (issues.some((issue) => issue.severity === "error")) return "Fix the errors above first.";
  if (startSeed === null) return START_SEED_PROBLEM;
  if (credits !== undefined && creditsToUnits(credits) < creditsToUnits(maxCost)) {
    return `Max cost is ${formatCredits(maxCost)} credits but you have ${formatCredits(credits)}. Lower it or wait for the 00:00 UTC refill.`;
  }
  return undefined;
}

interface SearchActionProps {
  user: SessionUser | null;
  atLimit: boolean;
  submitting: boolean;
  blocked: boolean;
  onSubmit: () => void;
}

function SearchAction({ user, atLimit, submitting, blocked, onSubmit }: SearchActionProps) {
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
  const [startSeedDraft, setStartSeedDraft] = useState("");
  const { user, jobs } = account;
  const startSeedText = startSeedDraft.trim() || String(DEFAULT_START_SEED);
  const startSeed = /^\d+$/.test(startSeedText) && Number(startSeedText) < SEED_SPACE ? Number(startSeedText) : null;
  const atLimit = jobs.filter((job) => isActiveStatus(job.status)).length >= MAX_ACTIVE_SEARCHES;
  const problem = atLimit ? undefined : blockingProblem(issues, user?.credits, maxCost, startSeed);

  const submit = async () => {
    const checked = validateJobRequest({ config, wanted, maxCost, startSeed });
    if (!checked.ok) {
      setError(`This search can't be sent: ${checked.error}`);
      return;
    }
    setSubmitting(true);
    setError("");
    try {
      await createJob(checked.value);
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 409) onNotify(`You already have ${MAX_ACTIVE_SEARCHES} searches going. They're under "Your searches".`);
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
      <div>
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
        <p className="hint">Seeds are checked in order from this one, wrapping around after {SEED_SPACE - 1}.</p>
      </div>
      <div className="search__actions">
        <SearchAction user={user} atLimit={atLimit} submitting={submitting} blocked={problem !== undefined} onSubmit={() => void submit()} />
        <span className="search__cost">
          {atLimit ? (
            `You can run up to ${MAX_ACTIVE_SEARCHES} searches at once.`
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
