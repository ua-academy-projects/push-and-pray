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
