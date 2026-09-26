import { useCallback, useEffect, useRef, useState } from "react";
import { ApiError, fetchJobs, fetchMe, logout, type JobView, type SessionUser } from "./api-client";

export interface Account {
  user: SessionUser | null;
  loading: boolean;
  jobs: JobView[];
  refresh: () => Promise<void>;
  jobEnded: (job: JobView) => void;
  logOut: () => Promise<void>;
}

/**
 * Loads the logged-in Discord user and their searches; `jobEnded` swaps in a search its live stream reports settled.
 * Only the newest refresh is applied, a failed one keeps what is shown (unless it says the session ended), and unchanged
 * jobs keep their identity so memoised results don't re-render.
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

  const jobEnded = useCallback(
    (ended: JobView) => {
      setJobs((shown) => shown.map((job) => (job.id === ended.id ? ended : job)));
      void refresh();
    },
    [refresh],
  );

  return { user, loading, jobs, refresh, jobEnded, logOut };
}
