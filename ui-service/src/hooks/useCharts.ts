import { getCharts } from "../api/weatherApi";
import type { ChartData } from "../types/chart";
import { useAsyncResource } from "./useAsyncResource";

export function useCharts(from: string | undefined, to: string | undefined) {
  return useAsyncResource<ChartData>(() => getCharts(from, to), [from, to]);
}
