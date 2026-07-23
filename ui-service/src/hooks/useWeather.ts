import { useCallback, useEffect, useState } from "react";
import { getWeather } from "../api/weatherApi";
import type { WeatherResponse } from "../types/weather";

/**
 * How often the UI re-checks for persisted data. Short enough (60s) that a successful
 * scheduled sync on the Backend (default every 60 minutes) reaches the screen within about
 * one interval, without the UI ever triggering a sync itself. See docs/architecture.md §12
 * decision 17. This is the one place that number lives.
 */
export const POLL_INTERVAL_MS = 60_000;

export type WeatherStatus = "loading" | "ready" | "error";

export interface UseWeatherResult {
  data: WeatherResponse | null;
  status: WeatherStatus;
  /** Re-reads persisted data from the Backend. Never calls the sync endpoint. Not currently
   * wired to any visible control -- see Header.tsx -- but kept available and tested. */
  reload: () => Promise<void>;
}

export function useWeather(): UseWeatherResult {
  const [data, setData] = useState<WeatherResponse | null>(null);
  const [status, setStatus] = useState<WeatherStatus>("loading");

  const reload = useCallback(async () => {
    try {
      const result = await getWeather();
      setData(result);
      setStatus("ready");
    } catch {
      setStatus("error");
    }
  }, []);

  useEffect(() => {
    reload();
    const intervalId = window.setInterval(reload, POLL_INTERVAL_MS);
    return () => window.clearInterval(intervalId);
  }, [reload]);

  return { data, status, reload };
}
