import type { ChartData } from "../types/chart";
import type { ForecastResponse } from "../types/forecast";
import type { SessionResponse, UIStatePatch } from "../types/session";
import type { DailyRecord, DailyRecordsResponse, DailyStatistics, PeriodStatistics } from "../types/statistics";
import type { SyncLogEntry, SyncStatusResponse } from "../types/sync";
import type { WeatherResponse } from "../types/weather";

// The only backend URL the UI knows about -- no Open-Meteo URL, no Fetcher Service URL,
// no database configuration, and no internal (/internal/*) endpoint ever appears here or
// anywhere else in this app. See docs/architecture.md §4.
const BASE_URL = import.meta.env.VITE_BACKEND_BASE_URL || "http://localhost:8000";

async function getJSON<T>(path: string): Promise<T> {
  const response = await fetch(`${BASE_URL}${path}`);
  if (!response.ok) {
    throw new Error(`Request to ${path} failed with status ${response.status}`);
  }
  return (await response.json()) as T;
}

function toQuery(params: Record<string, string | number | undefined>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) search.set(key, String(value));
  }
  const query = search.toString();
  return query ? `?${query}` : "";
}

/** The main dashboard read -- current, today, hourly, and freshness metadata all come back in
 * one response. Never calls Open-Meteo, never triggers a synchronization. */
export function getWeather(): Promise<WeatherResponse> {
  return getJSON<WeatherResponse>("/api/weather");
}

/** Recorded daily rows, newest first. Omit both bounds for every stored date. */
export function getDaily(from?: string, to?: string): Promise<DailyRecordsResponse> {
  return getJSON<DailyRecordsResponse>(`/api/weather/daily${toQuery({ from, to })}`);
}

export function getDailyByDate(date: string): Promise<DailyRecord> {
  return getJSON<DailyRecord>(`/api/weather/daily/${date}`);
}

/** Predicted days from daily_forecast -- never daily_weather. */
export function getForecast(days = 10): Promise<ForecastResponse> {
  return getJSON<ForecastResponse>(`/api/weather/forecast${toQuery({ days })}`);
}

export function getStatisticsDaily(date: string): Promise<DailyStatistics> {
  return getJSON<DailyStatistics>(`/api/weather/statistics/daily/${date}`);
}

export function getStatisticsPeriod(from: string, to: string): Promise<PeriodStatistics> {
  return getJSON<PeriodStatistics>(`/api/weather/statistics${toQuery({ from, to })}`);
}

export function getStatisticsAll(): Promise<PeriodStatistics> {
  return getJSON<PeriodStatistics>("/api/weather/statistics/all");
}

/** Chart-ready time series, ordered ascending by date. Omit both bounds for every stored date. */
export function getCharts(from?: string, to?: string): Promise<ChartData> {
  return getJSON<ChartData>(`/api/weather/charts${toQuery({ from, to })}`);
}

export function getSyncStatus(): Promise<SyncStatusResponse> {
  return getJSON<SyncStatusResponse>("/api/sync-status");
}

export function getSyncHistory(limit = 20): Promise<SyncLogEntry[]> {
  return getJSON<SyncLogEntry[]>(`/api/sync/history${toQuery({ limit })}`);
}

/** Ensures a session exists for this browser and returns its stored UI preferences (selected
 * graph period, filters, toggles) -- never weather/business data. The Backend mints a new
 * session id on the first call (no sessionId yet) and returns it in the body; the UI holds
 * that id in localStorage, not a cookie, so this works across the Vagrant LAN deployment's
 * separate origins without SameSite/HTTPS requirements. See docs/architecture.md. */
export async function getSession(sessionId?: string): Promise<SessionResponse> {
  const response = await fetch(`${BASE_URL}/api/session`, {
    headers: sessionId ? { "X-Session-Id": sessionId } : undefined,
  });
  if (!response.ok) {
    throw new Error(`Request to /api/session failed with status ${response.status}`);
  }
  return (await response.json()) as SessionResponse;
}

/** Persists a partial UI-state change for this browser's session. Only ever called with a
 * session id already minted by getSession(). */
export async function putSessionState(sessionId: string, patch: UIStatePatch): Promise<SessionResponse> {
  const response = await fetch(`${BASE_URL}/api/session/state`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", "X-Session-Id": sessionId },
    body: JSON.stringify(patch),
  });
  if (!response.ok) {
    throw new Error(`Request to /api/session/state failed with status ${response.status}`);
  }
  return (await response.json()) as SessionResponse;
}
