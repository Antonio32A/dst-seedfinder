import { useCallback, useEffect, useRef, useState } from "react";
import { ApiError, fetchJobs, fetchMe, logout, type JobView, type SessionUser } from "./api-client";

export interface Account {
  user: SessionUser | null;
  loading: boolean;
  jobs: JobView[];
  refresh: () => Promise<void>;
  logOut: () => Promise<void>;
}

const ACTIVE_STATUSES = new Set(["queued", "running"]);
const POLL_MS = 5000;

/**
 * Loads the logged-in Discord user and their searches, polling while a search is still running. Only the newest
 * refresh is applied, a failed one keeps what is shown (unless it says the session ended), and unchanged jobs keep
 * their identity so memoised results don't re-render.
 */
export function useAccount(): Account {
  const [user, setUser] = useState<SessionUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [jobs, setJobs] = useState<JobView[]>([]);
  const latestRefresh = useRef(0);

  const refresh = useCallback(async () => {
    const current = ++latestRefresh.current;
    const isLatest = () => current === latestRefresh.current;
    try {
      const me = await fetchMe();
      const fresh = me ? await fetchJobs() : [];
      if (!isLatest()) return;
      setUser(me);
      setJobs((shown) => fresh.map((job) => shown.find((old) => old.id === job.id && old.updatedAt === job.updatedAt) ?? job));
    } catch (error) {
      if (isLatest() && error instanceof ApiError && error.status === 401) {
        setUser(null);
        setJobs([]);
      }
    } finally {
      if (isLatest()) setLoading(false);
    }
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

  const active = jobs.some((job) => ACTIVE_STATUSES.has(job.status));
  useEffect(() => {
    if (!active) return;
    const timer = window.setInterval(() => void refresh(), POLL_MS);
    return () => window.clearInterval(timer);
  }, [active, refresh]);

  return { user, loading, jobs, refresh, logOut };
}
