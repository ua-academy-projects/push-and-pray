import { useCallback, useEffect, useState } from "react";
import { getForecast } from "../api/weatherApi";
import type { ForecastResponse } from "../types/forecast";
import { POLL_INTERVAL_MS } from "./useWeather";

export type ForecastStatus = "loading" | "ready" | "error";

/** Polls independently of useWeather, on the same interval, so a newly-arrived forecast shows
 * up automatically without the UI ever triggering a sync itself. */
export function useForecast(days = 10) {
  const [data, setData] = useState<ForecastResponse | null>(null);
  const [status, setStatus] = useState<ForecastStatus>("loading");

  const load = useCallback(async () => {
    try {
      const result = await getForecast(days);
      setData(result);
      setStatus("ready");
    } catch {
      setStatus("error");
    }
  }, [days]);

  useEffect(() => {
    load();
    const intervalId = window.setInterval(load, POLL_INTERVAL_MS);
    return () => window.clearInterval(intervalId);
  }, [load]);

  return { data, status };
}
