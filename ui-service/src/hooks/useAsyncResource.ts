import { useEffect, useState } from "react";

export type AsyncStatus = "loading" | "ready" | "error";

export interface UseAsyncResourceResult<T> {
  data: T | null;
  status: AsyncStatus;
}

/** Shared "fetch on dependency change" shape used by useStatistics/useCharts/useHistory --
 * each section loads and can fail independently, per docs/architecture.md's Averages/History
 * requirement. Re-fetches whenever `deps` changes; does nothing while `enabled` is false (the
 * History overlay only fetches while open). */
export function useAsyncResource<T>(fetcher: () => Promise<T>, deps: unknown[], enabled = true): UseAsyncResourceResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [status, setStatus] = useState<AsyncStatus>("loading");

  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;
    setStatus("loading");
    fetcher()
      .then((result) => {
        if (!cancelled) {
          setData(result);
          setStatus("ready");
        }
      })
      .catch(() => {
        if (!cancelled) setStatus("error");
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, ...deps]);

  return { data, status };
}
