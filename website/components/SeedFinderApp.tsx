"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { DEFAULT_MAX_COST, isValidMaxCost } from "@/lib/credits";
import {
  decodeShareParam,
  defaultState,
  DEFAULT_WANTED,
  fromSeedfinderConfig,
  hasCustomSettings,
  isEmptyGroup,
  SETTINGS_DROPPED_NOTICE,
  STORAGE_KEY,
  toSeedfinderConfig,
  validateSearch,
  WANTED_OPTIONS,
  type Preset,
  type SearchState,
} from "@/lib/search-state";
import { useAccount } from "@/lib/use-account";
import ConfirmDialog from "./ConfirmDialog";
import CriteriaEditor from "./CriteriaEditor";
import Intro from "./Intro";
import JobsList from "./JobsList";
import Presets from "./Presets";
import SearchPanel from "./SearchPanel";
import SiteHeader from "./SiteHeader";
import Toast, { type ToastMessage } from "./Toast";
import ToolsPanel from "./ToolsPanel";

interface StoredSearch {
  config: unknown;
  wanted: unknown;
  maxCost: unknown;
}

function readStored(): { config: unknown; wanted: number; maxCost: number } | null {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const stored = JSON.parse(raw) as StoredSearch;
    const wanted = WANTED_OPTIONS.find((option) => option === stored.wanted) ?? DEFAULT_WANTED;
    const maxCost = isValidMaxCost(stored.maxCost) ? stored.maxCost : DEFAULT_MAX_COST;
    return { config: stored.config, wanted, maxCost };
  } catch {
    return null;
  }
}

export default function SeedFinderApp() {
  const [state, setState] = useState<SearchState>(defaultState);
  const [wanted, setWanted] = useState(DEFAULT_WANTED);
  const [maxCost, setMaxCost] = useState(DEFAULT_MAX_COST);
  const [restored, setRestored] = useState(false);
  const [pendingPreset, setPendingPreset] = useState<Preset | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const account = useAccount();

  const config = useMemo(() => toSeedfinderConfig(state), [state]);
  const issues = useMemo(() => validateSearch(state), [state]);

  const notify = useCallback((text: string) => setToast({ id: Date.now(), text }), []);
  const dismissToast = useCallback(() => setToast(null), []);

  useEffect(() => {
    const url = new URL(window.location.href);
    const shared = url.searchParams.get("c");
    const stored = readStored();
    const initial = (shared ? decodeShareParam(shared) : null) ?? stored?.config;
    if (initial) setState(fromSeedfinderConfig(initial));
    if (hasCustomSettings(initial)) notify(`Search loaded. ${SETTINGS_DROPPED_NOTICE}`);
    if (stored) {
      setWanted(stored.wanted);
      setMaxCost(stored.maxCost);
    }
    if (shared !== null) {
      url.searchParams.delete("c");
      window.history.replaceState(null, "", url);
    }
    setRestored(true);
  }, [notify]);

  useEffect(() => {
    if (!restored) return;
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ config, wanted, maxCost }));
    } catch {}
  }, [config, wanted, maxCost, restored]);

  const pickPreset = (preset: Preset) => {
    if (state.groups.every(isEmptyGroup)) setState({ ...preset.build(), platform: state.platform });
    else setPendingPreset(preset);
  };

  return (
    <>
      <SiteHeader account={account} />
      <main className="content">
        <Intro />
        <Presets onPick={pickPreset} />
        <CriteriaEditor state={state} onChange={setState} />
        <SearchPanel
          config={config}
          issues={issues}
          platform={state.platform}
          onPlatformChange={(platform) => setState((current) => ({ ...current, platform }))}
          wanted={wanted}
          onWantedChange={setWanted}
          maxCost={maxCost}
          onMaxCostChange={setMaxCost}
          account={account}
          onNotify={notify}
        />
        {account.user && <JobsList account={account} onNotify={notify} />}
        <ToolsPanel config={config} onImport={setState} onReset={() => setState(defaultState())} onNotify={notify} />
      </main>
      <ConfirmDialog
        open={pendingPreset !== null}
        title="Replace your search?"
        message={`Loading “${pendingPreset?.name ?? ""}” replaces everything you've picked.`}
        confirmLabel="Replace"
        onConfirm={() => {
          if (pendingPreset) setState({ ...pendingPreset.build(), platform: state.platform });
          setPendingPreset(null);
        }}
        onCancel={() => setPendingPreset(null)}
      />
      <Toast message={toast} onDismiss={dismissToast} />
    </>
  );
}
