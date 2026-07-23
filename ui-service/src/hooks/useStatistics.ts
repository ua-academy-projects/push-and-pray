import { getStatisticsAll, getStatisticsPeriod } from "../api/weatherApi";
import type { PeriodStatistics } from "../types/statistics";
import { useAsyncResource } from "./useAsyncResource";

/** `from`/`to` both undefined -> GET /api/weather/statistics/all; otherwise the period
 * endpoint. Re-fetches whenever the range changes. */
export function useStatistics(from: string | undefined, to: string | undefined) {
  return useAsyncResource<PeriodStatistics>(
    () => (from && to ? getStatisticsPeriod(from, to) : getStatisticsAll()),
    [from, to],
  );
}
