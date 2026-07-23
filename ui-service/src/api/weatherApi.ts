import type { WeatherResponse } from "../types/weather";

// The only backend URL the UI knows about -- no Open-Meteo URL, no History Service URL,
// no database configuration, and no synchronization endpoint ever appear here or anywhere
// else in this app. See docs/architecture.md §4.
const BASE_URL = import.meta.env.VITE_BACKEND_BASE_URL || "http://localhost:8000";

async function getJSON<T>(path: string): Promise<T> {
  const response = await fetch(`${BASE_URL}${path}`);
  if (!response.ok) {
    throw new Error(`Request to ${path} failed with status ${response.status}`);
  }
  return (await response.json()) as T;
}

/** The only read the UI needs for the main dashboard -- current, today, hourly, history,
 * and freshness metadata all come back in one response. Never calls Open-Meteo, never
 * triggers a synchronization. */
export function getWeather(): Promise<WeatherResponse> {
  return getJSON<WeatherResponse>("/api/weather");
}
