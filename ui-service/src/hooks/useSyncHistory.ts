import { useCallback, useState } from "react";
import { getSyncHistory } from "../api/weatherApi";
import type { SyncLogEntry } from "../types/sync";

export type SyncHistoryStatus = "idle" | "loading" | "ready" | "error";

/** Fetched on demand (when the inline log panel is opened), not polled -- this is a log a
 * user actively opens, not data that needs to stay live in the background. */
export function useSyncHistory() {
  const [data, setData] = useState<SyncLogEntry[] | null>(null);
  const [status, setStatus] = useState<SyncHistoryStatus>("idle");

  const load = useCallback(async () => {
    setStatus("loading");
    try {
      const result = await getSyncHistory();
      setData(result);
      setStatus("ready");
    } catch {
      setStatus("error");
    }
  }, []);

  return { data, status, load };
}
