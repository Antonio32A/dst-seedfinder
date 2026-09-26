"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { DEFAULT_MAX_COST, isValidMaxCost } from "@/lib/credits";
import {
    canSearchLocally,
    DEFAULT_SEARCH_TARGET,
    defaultThreads,
    SEARCH_TARGETS,
    type SearchTarget
} from "@/lib/local-search";
import {
    decodeShareParam,
    DEFAULT_WANTED,
    defaultState,
    fromSeedfinderConfig,
    hasCustomSettings,
    isEmptyGroup,
    type Preset,
    type SearchState,
    SETTINGS_DROPPED_NOTICE,
    STORAGE_KEY,
    toSeedfinderConfig,
    validateSearch,
    WANTED_OPTIONS
} from "@/lib/search-state";
import { clamp } from "@/lib/state-helpers";
import { useAccount } from "@/lib/use-account";
import { useLocalSearch } from "@/lib/use-local-search";
import ConfirmDialog from "./ConfirmDialog";
import CriteriaEditor from "./CriteriaEditor";
import Intro from "./Intro";
import JobsList from "./JobsList";
import LocalSearch from "./LocalSearch";
import Presets from "./Presets";
import SearchPanel from "./SearchPanel";
import SiteHeader from "./SiteHeader";
import Toast, { type ToastMessage } from "./Toast";
import ToolsPanel from "./ToolsPanel";

interface StoredSearch {
    config: unknown;
    wanted: unknown;
    maxCost: unknown;
    target?: unknown;
    threads?: unknown;
}

interface RestoredSearch {
    config: unknown;
    wanted: number;
    maxCost: number;
    target: SearchTarget;
    threads: number | null;
}

function readStored(): RestoredSearch | null {
    try {
        const raw = window.localStorage.getItem(STORAGE_KEY);
        if (!raw) return null;
        const stored = JSON.parse(raw) as StoredSearch;
        const wanted = WANTED_OPTIONS.find((option) => option === stored.wanted) ?? DEFAULT_WANTED;
        const maxCost = isValidMaxCost(stored.maxCost) ? stored.maxCost : DEFAULT_MAX_COST;
        const target = SEARCH_TARGETS.find((option) => option === stored.target) ?? DEFAULT_SEARCH_TARGET;
        const threads = Number.isInteger(stored.threads) ? (stored.threads as number) : null;
        return { config: stored.config, wanted, maxCost, target, threads };
    } catch {
        return null;
    }
}

export default function SeedFinderApp() {
    const [state, setState] = useState<SearchState>(defaultState);
    const [wanted, setWanted] = useState(DEFAULT_WANTED);
    const [maxCost, setMaxCost] = useState(DEFAULT_MAX_COST);
    const [target, setTarget] = useState<SearchTarget>(DEFAULT_SEARCH_TARGET);
    const [cores, setCores] = useState(1);
    const [threads, setThreads] = useState(1);
    const [browserSupported, setBrowserSupported] = useState<boolean | null>(null);
    const [restored, setRestored] = useState(false);
    const [pendingPreset, setPendingPreset] = useState<Preset | null>(null);
    const [toast, setToast] = useState<ToastMessage | null>(null);
    const account = useAccount();
    const localSearch = useLocalSearch();

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
        const logicalCores = Math.max(1, navigator.hardwareConcurrency || 1);
        const supported = canSearchLocally();
        setCores(logicalCores);
        setThreads(clamp(stored?.threads ?? defaultThreads(logicalCores), 1, logicalCores));
        setBrowserSupported(supported);
        setTarget(supported ? (stored?.target ?? DEFAULT_SEARCH_TARGET) : "cloud");
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
            window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ config, wanted, maxCost, target, threads }));
        } catch {
        }
    }, [config, wanted, maxCost, target, threads, restored]);

    const pickPreset = (preset: Preset) => {
        if (state.groups.every(isEmptyGroup)) setState({ ...preset.build(), platform: state.platform });
        else setPendingPreset(preset);
    };

    return (
            <>
                <SiteHeader account={account}/>
                <main className="content">
                    <Intro/>
                    <Presets onPick={pickPreset}/>
                    <CriteriaEditor state={state} onChange={setState}/>
                    <SearchPanel
                            config={config}
                            issues={issues}
                            platform={state.platform}
                            onPlatformChange={(platform) => setState((current) => ({ ...current, platform }))}
                            wanted={wanted}
                            onWantedChange={setWanted}
                            target={target}
                            onTargetChange={setTarget}
                            maxCost={maxCost}
                            onMaxCostChange={setMaxCost}
                            browser={{
                                supported: browserSupported,
                                cores,
                                threads,
                                onThreadsChange: setThreads,
                                running: localSearch.active,
                                onStart: localSearch.start
                            }}
                            account={account}
                            onNotify={notify}
                    />
                    {localSearch.state && (
                            <LocalSearch
                                    state={localSearch.state}
                                    onStop={localSearch.stop}
                                    onSearchFurther={(startSeed) => localSearch.state && localSearch.start({
                                        ...localSearch.state.request,
                                        startSeed
                                    })}
                                    onNotify={notify}
                            />
                    )}
                    {account.user && <JobsList account={account} onNotify={notify}/>}
                    <ToolsPanel config={config} onImport={setState} onReset={() => setState(defaultState())}
                                onNotify={notify}/>
                </main>
                <ConfirmDialog
                        open={pendingPreset !== null}
                        title="Replace your search?"
                        message={`Loading "${pendingPreset?.name ?? ""}" replaces everything you've picked.`}
                        confirmLabel="Replace"
                        onConfirm={() => {
                            if (pendingPreset) setState({ ...pendingPreset.build(), platform: state.platform });
                            setPendingPreset(null);
                        }}
                        onCancel={() => setPendingPreset(null)}
                />
                <Toast message={toast} onDismiss={dismissToast}/>
            </>
    );
}
