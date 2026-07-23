import { useCallback, useEffect, useState } from "react";
import { getSyncStatus } from "../api/weatherApi";
import type { SyncStatusResponse } from "../types/sync";
import { POLL_INTERVAL_MS } from "./useWeather";

export type SyncStatusState = "loading" | "ready" | "error";

/** Backs the StatusStrip. Polls independently of useWeather -- the strip must keep working
 * even if the main weather fetch is failing, and vice versa. `refresh()` is exposed so a
 * manual "Refresh now" can pull the new status immediately instead of waiting for the next
 * poll tick. */
export function useSyncStatus() {
  const [data, setData] = useState<SyncStatusResponse | null>(null);
  const [status, setStatus] = useState<SyncStatusState>("loading");

  const refresh = useCallback(async () => {
    try {
      const result = await getSyncStatus();
      setData(result);
      setStatus("ready");
    } catch {
      setStatus("error");
    }
  }, []);

  useEffect(() => {
    refresh();
    const intervalId = window.setInterval(refresh, POLL_INTERVAL_MS);
    return () => window.clearInterval(intervalId);
  }, [refresh]);

  return { data, status, refresh };
}
