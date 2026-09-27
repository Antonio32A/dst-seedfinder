"use client";

import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { type LocalSearchRequest, type LocalSearchState, startLocalSearch } from "./local-search";

export interface LocalSearch {
    state: LocalSearchState | null;
    active: boolean;
    start: (request: LocalSearchRequest) => void;
    stop: () => void;
}

const LocalSearchContext = createContext<LocalSearch | null>(null);

/** Keeps the browser search, and its results, across the app's pages: it lives in the root layout. */
export function LocalSearchProvider({ children }: { children: ReactNode }) {
    const [state, setState] = useState<LocalSearchState | null>(null);
    const stopCurrent = useRef<(() => void) | null>(null);
    const active = state?.status === "starting" || state?.status === "running";

    const start = useCallback((request: LocalSearchRequest) => {
        stopCurrent.current?.();
        stopCurrent.current = startLocalSearch(request, setState);
    }, []);

    const stop = useCallback(() => stopCurrent.current?.(), []);

    useEffect(() => () => stopCurrent.current?.(), []);

    useEffect(() => {
        if (!active) return;
        const confirmLeave = (event: BeforeUnloadEvent) => event.preventDefault();
        window.addEventListener("beforeunload", confirmLeave);
        return () => window.removeEventListener("beforeunload", confirmLeave);
    }, [active]);

    const search = useMemo(() => ({ state, active, start, stop }), [state, active, start, stop]);
    return <LocalSearchContext.Provider value={search}>{children}</LocalSearchContext.Provider>;
}

export function useLocalSearch(): LocalSearch {
    const search = useContext(LocalSearchContext);
    if (search === null) throw new Error("useLocalSearch needs a LocalSearchProvider above it.");
    return search;
}
