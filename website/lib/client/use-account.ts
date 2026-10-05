import { useCallback, useEffect, useRef, useState } from "react";
import { isActiveStatus, type JobView, MAX_ACTIVE_SEARCHES } from "@/lib/jobs/job-events";
import { ApiError, fetchJobs, fetchMe, logout, type SessionUser } from "./api-client";

export interface Account {
    user: SessionUser | null;
    loading: boolean;
    jobs: JobView[];
    atLimit: boolean;
    refresh: () => Promise<void>;
    jobEnded: (job: JobView) => void;
    logOut: () => Promise<void>;
}

/** The signed-in user and their jobs, or null when the request failed for another reason than being signed out. */
async function fetchAccount(): Promise<{ user: SessionUser | null; jobs: JobView[] } | null> {
    try {
        const user = await fetchMe();
        return { user, jobs: user ? await fetchJobs() : [] };
    } catch (error) {
        return error instanceof ApiError && error.status === 401 ? { user: null, jobs: [] } : null;
    }
}

/** Unchanged jobs keep their identity so memoised results don't re-render. */
export function useAccount(): Account {
    const [user, setUser] = useState<SessionUser | null>(null);
    const [loading, setLoading] = useState(true);
    const [jobs, setJobs] = useState<JobView[]>([]);
    const latestRefresh = useRef(0);

    const refresh = useCallback(() => {
        const current = ++latestRefresh.current;
        return fetchAccount().then((account) => {
            if (current !== latestRefresh.current) return;
            if (account) {
                setUser(account.user);
                setJobs((shown) => account.jobs.map((job) =>
                    shown.find((old) => old.id === job.id && old.updatedAt === job.updatedAt) ?? job));
            }
            setLoading(false);
        });
    }, []);

    const logOut = useCallback(async () => {
        await logout().catch(() => undefined);
        await refresh();
    }, [refresh]);

    useEffect(() => {
        void refresh();
        return () => {
            latestRefresh.current += 1;
        };
    }, [refresh]);

    const jobEnded = useCallback(
        (ended: JobView) => {
            setJobs((shown) => shown.map((job) => (job.id === ended.id ? ended : job)));
            void refresh();
        },
        [refresh]
    );

    const atLimit = jobs.filter((job) => isActiveStatus(job.status)).length >= MAX_ACTIVE_SEARCHES;
    return { user, loading, jobs, atLimit, refresh, jobEnded, logOut };
}
