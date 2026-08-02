import type { UseSessionStateResult } from "../src/hooks/useSessionState";
import type { ChartData } from "../src/types/chart";
import type { ForecastResponse } from "../src/types/forecast";
import type { SessionResponse } from "../src/types/session";
import type { DailyRecordsResponse, PeriodStatistics } from "../src/types/statistics";
import type { SyncLogEntry, SyncStatusResponse } from "../src/types/sync";
import type { WeatherResponse } from "../src/types/weather";

export function buildWeatherResponse(overrides: Partial<WeatherResponse> = {}): WeatherResponse {
  const today = new Date().toISOString().slice(0, 10);

  return {
    location: {
      name: "Ivano-Frankivsk",
      country: "Ukraine",
      latitude: 48.9226,
      longitude: 24.7111,
      timezone: "Europe/Kyiv",
    },
    current: {
      observed_at: new Date().toISOString(),
      temperature: 24.5,
      apparent_temperature: 25.1,
      humidity: 61,
      precipitation: 0,
      weather_code: 1,
      cloud_cover: 20,
      wind_speed: 8.5,
      wind_direction: 220,
      surface_pressure: 1008,
      is_day: true,
    },
    daily: [
      {
        weather_date: today,
        weather_code: 1,
        temperature_max: 25,
        temperature_min: 15,
        apparent_temperature_max: 26,
        apparent_temperature_min: 14,
        sunrise: new Date().toISOString(),
        sunset: new Date().toISOString(),
        precipitation_sum: 0,
        rain_sum: 0,
        snowfall_sum: 0,
        precipitation_hours: 0,
        wind_speed_max: 10,
        wind_gusts_max: 15,
      },
    ],
    hourly: [
      {
        weather_time: new Date().toISOString(),
        temperature: 24,
        apparent_temperature: 23.5,
        humidity: 60,
        precipitation_probability: 5,
        precipitation: 0,
        weather_code: 1,
        cloud_cover: 15,
        visibility: 10000,
        wind_speed: 7,
        wind_direction: 200,
      },
    ],
    data_source: "Open-Meteo",
    last_synchronized_at: new Date().toISOString(),
    synchronization_status: "success",
    is_stale: false,
    stale_reason: null,
    ...overrides,
  };
}

export function buildEmptyWeatherResponse(): WeatherResponse {
  return {
    location: null,
    current: null,
    daily: [],
    hourly: [],
    data_source: null,
    last_synchronized_at: null,
    synchronization_status: null,
    is_stale: true,
    stale_reason: "synchronization time unavailable",
  };
}

const LOCATION = {
  name: "Ivano-Frankivsk",
  country: "Ukraine",
  latitude: 48.9226,
  longitude: 24.7111,
  timezone: "Europe/Kyiv",
};

export function buildForecastResponse(overrides: Partial<ForecastResponse> = {}): ForecastResponse {
  const today = new Date();
  return {
    location: LOCATION,
    forecast: Array.from({ length: 10 }, (_, index) => {
      const date = new Date(today.getTime() + index * 86_400_000);
      return {
        weather_date: date.toISOString().slice(0, 10),
        weather_code: 1,
        temperature_min: 12 + index,
        temperature_max: 22 + index,
        apparent_temperature_min: 11 + index,
        apparent_temperature_max: 23 + index,
        precipitation_probability_max: 10,
      };
    }),
    ...overrides,
  };
}

export function buildPeriodStatistics(overrides: Partial<PeriodStatistics> = {}): PeriodStatistics {
  return {
    period_start: "2026-06-01",
    period_end: "2026-06-30",
    available_days: 30,
    average_temperature: 19.4,
    average_daily_minimum_temperature: 12.1,
    average_daily_maximum_temperature: 25.6,
    lowest_temperature: 8.2,
    highest_temperature: 29.7,
    average_humidity: 58.3,
    total_precipitation: 42.5,
    average_daily_precipitation: 1.4,
    rainy_days: 9,
    snowy_days: 0,
    clear_days: 14,
    cloudy_days: 7,
    average_wind_speed: 11.2,
    maximum_wind_speed: 38.6,
    warmest_day: "2026-06-21",
    coldest_day: "2026-06-03",
    most_common_weather_condition: "clear",
    ...overrides,
  };
}

export function buildChartData(overrides: Partial<ChartData> = {}): ChartData {
  const days = Array.from({ length: 30 }, (_, index) => {
    const date = new Date(Date.UTC(2026, 5, 1 + index));
    return date.toISOString().slice(0, 10);
  });

  return {
    period: { from: days[0], to: days[days.length - 1], available_days: days.length },
    temperature: days.map((date, index) => ({ date, average: 18 + (index % 5), minimum: 10 + (index % 5), maximum: 26 + (index % 5) })),
    humidity: days.map((date, index) => ({ date, average: 50 + (index % 10) })),
    precipitation: days.map((date, index) => ({ date, total: index % 4 === 0 ? 3.2 : 0 })),
    wind: days.map((date, index) => ({ date, average: 8 + (index % 6), maximum: 20 + (index % 6) })),
    ...overrides,
  };
}

export function buildDailyRecordsResponse(overrides: Partial<DailyRecordsResponse> = {}): DailyRecordsResponse {
  const days = Array.from({ length: 5 }, (_, index) => {
    const date = new Date(Date.now() - index * 86_400_000);
    return date.toISOString().slice(0, 10);
  });

  return {
    location: LOCATION,
    daily: days.map((weather_date) => ({
      weather_date,
      weather_code: 1,
      temperature_max: 24,
      temperature_min: 14,
      apparent_temperature_max: 25,
      apparent_temperature_min: 13,
      sunrise: new Date().toISOString(),
      sunset: new Date().toISOString(),
      precipitation_sum: 0,
      rain_sum: 0,
      snowfall_sum: 0,
      precipitation_hours: 0,
      wind_speed_max: 12,
      wind_gusts_max: 18,
      average_temperature: 19,
      average_temperature_method: "hourly",
      average_apparent_temperature: 18.5,
      average_humidity: 55,
      average_wind_speed: 9,
      average_cloud_cover: 30,
    })),
    ...overrides,
  };
}

export function buildSyncStatusResponse(overrides: Partial<SyncStatusResponse> = {}): SyncStatusResponse {
  return {
    synchronization_status: "success",
    last_synchronized_at: new Date().toISOString(),
    last_attempted_at: new Date().toISOString(),
    next_scheduled_at: null,
    sync_in_progress: false,
    is_stale: false,
    stale_reason: null,
    ...overrides,
  };
}

export function buildSyncLogEntries(overrides: Partial<SyncLogEntry>[] = []): SyncLogEntry[] {
  const base: SyncLogEntry = {
    id: 1,
    location_id: 1,
    started_at: new Date().toISOString(),
    completed_at: new Date().toISOString(),
    status: "success",
    source: "scheduler",
    trigger_type: "scheduler",
    open_meteo_request_url: null,
    open_meteo_status_code: 200,
    open_meteo_duration_ms: 240,
    records_received: 34,
    daily_records_received: 10,
    forecast_records_received: 10,
    hourly_records_received: 24,
    error_message: null,
    created_at: new Date().toISOString(),
  };

  if (overrides.length === 0) {
    return [
      base,
      { ...base, id: 2, status: "failed", error_message: "Open-Meteo request timed out", daily_records_received: null, forecast_records_received: null, hourly_records_received: null },
    ];
  }
  return overrides.map((override, index) => ({ ...base, id: index + 1, ...override }));
}

export function buildSessionResponse(overrides: Partial<SessionResponse> = {}): SessionResponse {
  return {
    session_id: "test-session-id",
    state: {
      averages_range: { preset: "30", range_from: null, range_to: null },
      history_range: { preset: "30", range_from: null, range_to: null },
      history_open: false,
    },
    ...overrides,
  };
}

/** Stub for components that take `session` as a prop but aren't the ones under test for
 * session behavior itself -- defaults to "loading" so useSessionSyncedRange never hydrates or
 * pushes patches, keeping these tests focused on their own component. */
export function buildSessionStateStub(overrides: Partial<UseSessionStateResult> = {}): UseSessionStateResult {
  return {
    state: null,
    status: "loading",
    patch: () => {},
    ...overrides,
  };
}
