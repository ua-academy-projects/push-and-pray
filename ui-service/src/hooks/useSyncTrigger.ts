import { useCallback, useState } from "react";
import { postSyncTrigger } from "../api/weatherApi";
import type { SyncTriggerResult } from "../types/sync";

export type SyncTriggerState = "idle" | "loading" | "done";

/** The manual "Refresh now" action -- the one path by which a user click can cause a
 * synchronization, proxied through the Backend (see docs/architecture.md §7). `onSettled` is
 * called after every attempt (success or failure) so the caller can re-pull weather/sync
 * status/sync log without this hook needing to know about any of them. */
export function useSyncTrigger(onSettled?: () => void) {
  const [state, setState] = useState<SyncTriggerState>("idle");
  const [result, setResult] = useState<SyncTriggerResult | null>(null);

  const trigger = useCallback(async () => {
    setState("loading");
    try {
      const response = await postSyncTrigger();
      setResult(response);
    } catch {
      setResult({ status: "failed", message: "Could not reach the Backend", daily_records: null, forecast_records: null, hourly_records: null });
    } finally {
      setState("done");
      onSettled?.();
    }
  }, [onSettled]);

  return { trigger, state, result };
}
