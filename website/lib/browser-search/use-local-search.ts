import { useCallback, useEffect, useRef, useState } from "react";
import { type LocalSearchRequest, type LocalSearchState, startLocalSearch } from "./local-search";

export function useLocalSearch() {
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

    return { state, active, start, stop };
}

export type LocalSearch = ReturnType<typeof useLocalSearch>;
