import { getDaily } from "../api/weatherApi";
import type { DailyRecordsResponse } from "../types/statistics";
import { useAsyncResource } from "./useAsyncResource";

/** Backs the History overlay -- only fetches while `enabled` (the overlay is open), so it
 * doesn't do work while closed. */
export function useHistory(from: string | undefined, to: string | undefined, enabled: boolean) {
  return useAsyncResource<DailyRecordsResponse>(() => getDaily(from, to), [from, to], enabled);
}
