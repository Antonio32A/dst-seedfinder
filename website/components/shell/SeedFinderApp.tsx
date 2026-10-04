"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import CriteriaEditor from "@/components/criteria/CriteriaEditor";
import JobsList from "@/components/results/JobsList";
import LocalSearch from "@/components/results/LocalSearch";
import { PrefilterOddsProvider } from "@/lib/prefilter/use-prefilter-odds";
import SearchPanel from "@/components/search/SearchPanel";
import ConfirmDialog from "@/components/ui/ConfirmDialog";
import Toast, { type ToastMessage } from "@/components/ui/Toast";
import {
    CORES_PER_THREAD,
    DEFAULT_SEARCH_TARGET,
    SEARCH_TARGETS,
    type SearchTarget
} from "@/lib/browser-search/local-search";
import { canRunSeedfinder } from "@/lib/browser-search/seedfinder-wasm";
import { useLocalSearch } from "@/lib/browser-search/use-local-search";
import { copyText } from "@/lib/client/clipboard";
import { rememberMapOrigin } from "@/lib/client/map-origin";
import { useAccount } from "@/lib/client/use-account";
import { SHARD_LABELS, type Shard } from "@/lib/config/seedfinder-config";
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
    switchShard,
    toSeedfinderConfig,
    validateSearch,
    WANTED_OPTIONS
} from "@/lib/criteria/search-state";
import { clamp } from "@/lib/criteria/state-helpers";
import { DEFAULT_MAX_COST, isValidMaxCost } from "@/lib/jobs/credits";
import Intro from "./Intro";
import Presets from "./Presets";
import ShardSwitch from "./ShardSwitch";
import SiteHeader from "./SiteHeader";
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
    const copy = useCallback(
            async (text: string, what: string) => notify((await copyText(text)) ? `${what} copied.` : "Couldn't copy. Select the text instead."),
            [notify]
    );

    useEffect(() => rememberMapOrigin("/"), []);

    useEffect(() => {
        const url = new URL(window.location.href);
        const shared = url.searchParams.get("c");
        const stored = readStored();
        const initial = (shared ? decodeShareParam(shared) : null) ?? stored?.config;
        if (initial) setState(fromSeedfinderConfig(initial));
        if (hasCustomSettings(initial)) notify(`Search loaded. ${SETTINGS_DROPPED_NOTICE}`);
        const logicalCores = Math.max(1, navigator.hardwareConcurrency || 1);
        const supported = canRunSeedfinder();
        setCores(logicalCores);
        setThreads(clamp(stored?.threads ?? Math.floor(logicalCores / CORES_PER_THREAD), 1, logicalCores));
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

    const changeShard = (shard: Shard) => {
        const switched = switchShard(state, shard);
        setState(switched.state);
        if (switched.dropped > 0) {
            notify(`Switched to the ${SHARD_LABELS[shard].toLowerCase()}. Dropped ${switched.dropped} pick${switched.dropped === 1 ? "" : "s"} that only exist in the other shard.`);
        }
    };

    const pickPreset = (preset: Preset) => {
        if (state.groups.every(isEmptyGroup)) setState({ ...preset.build(), platform: state.platform });
        else setPendingPreset(preset);
    };

    return (
            <>
                <SiteHeader account={account}/>
                <main className="content">
                    <Intro/>
                    <ShardSwitch shard={state.shard} onChange={changeShard}/>
                    <Presets shard={state.shard} onPick={pickPreset}/>
                    <PrefilterOddsProvider config={config} threads={threads} supported={browserSupported === true}>
                        <CriteriaEditor state={state} onChange={setState}/>
                    </PrefilterOddsProvider>
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
                                    onCopy={copy}
                            />
                    )}
                    {account.user && <JobsList account={account} onCopy={copy} onNotify={notify}/>}
                    <ToolsPanel config={config} onImport={setState} onReset={() => setState(defaultState())}
                                onCopy={copy} onNotify={notify}/>
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
