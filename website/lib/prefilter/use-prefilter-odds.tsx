"use client";

import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import type { Shard, SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { formatShare, type PrefilterOdds } from "./odds";
import { isCancelled, runPrefilterOdds } from "./run-odds";

const RECALCULATE_DELAY_MS = 800;

export type OddsKind = "task" | "setpiece";

export interface PrefilterOddsState {
    supported: boolean;
    status: "idle" | "running" | "ready" | "failed";
    progress: number;
    error: string | null;
    /** The latest run, whose candidates are those of the config it ran with. */
    latest: PrefilterOdds | null;
    /** The share of worlds that have a task or set piece in the current shard, or null before it's known. */
    share: (kind: OddsKind, id: string) => string | null;
    calculate: () => void;
}

const PrefilterOddsContext = createContext<PrefilterOddsState | null>(null);

interface ProviderProps {
    config: SeedfinderConfig;
    threads: number;
    supported: boolean;
    children: ReactNode;
}

/**
 * The odds are measured on a sample of seeds. Once asked for, they follow the config: the level-table filter's share is
 * measured again shortly after each change.
 */
export function PrefilterOddsProvider({ config, threads, supported, children }: ProviderProps) {
    const [enabled, setEnabled] = useState(false);
    const [status, setStatus] = useState<PrefilterOddsState["status"]>("idle");
    const [progress, setProgress] = useState(0);
    const [error, setError] = useState<string | null>(null);
    const [latest, setLatest] = useState<PrefilterOdds | null>(null);
    const [byShard, setByShard] = useState<Partial<Record<Shard, PrefilterOdds>>>({});
    const configKey = JSON.stringify(config);
    const configRef = useRef(config);
    configRef.current = config;
    const threadsRef = useRef(threads);
    threadsRef.current = threads;

    useEffect(() => {
        if (!enabled) return;
        let cancel = () => {
        };
        const timer = window.setTimeout(() => {
            const handle = runPrefilterOdds(configRef.current, threadsRef.current, setProgress);
            cancel = handle.cancel;
            setStatus("running");
            setProgress(0);
            handle.result.then(
                (odds) => {
                    setLatest(odds);
                    setByShard((current) => ({ ...current, [configRef.current.shard ?? "forest"]: odds }));
                    setError(null);
                    setStatus("ready");
                },
                (caught: unknown) => {
                    if (isCancelled(caught)) return;
                    setError(caught instanceof Error ? caught.message : String(caught));
                    setStatus("failed");
                }
            );
        }, latest === null ? 0 : RECALCULATE_DELAY_MS);
        return () => {
            window.clearTimeout(timer);
            cancel();
        };
    }, [enabled, configKey]); // eslint-disable-line react-hooks/exhaustive-deps

    const shard: Shard = config.shard ?? "forest";
    const sample = byShard[shard];
    const share = useCallback(
            (kind: OddsKind, id: string) => {
                if (!sample) return null;
                return formatShare((kind === "task" ? sample.tasks : sample.setpieces)[id] ?? 0, sample.seeds);
            },
            [sample]
    );
    const calculate = useCallback(() => setEnabled(true), []);

    const value = useMemo(
            () => ({ supported, status, progress, error, latest, share, calculate }),
            [supported, status, progress, error, latest, share, calculate]
    );
    return <PrefilterOddsContext.Provider value={value}>{children}</PrefilterOddsContext.Provider>;
}

export function usePrefilterOdds(): PrefilterOddsState {
    const state = useContext(PrefilterOddsContext);
    if (state === null) throw new Error("usePrefilterOdds needs a PrefilterOddsProvider above it.");
    return state;
}
