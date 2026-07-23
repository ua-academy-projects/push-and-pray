export interface Location {
  name: string;
  country: string;
  latitude: number;
  longitude: number;
  timezone: string;
}

export interface CurrentWeather {
  observed_at: string;
  temperature: number;
  apparent_temperature: number;
  humidity: number;
  precipitation: number;
  weather_code: number;
  cloud_cover: number;
  wind_speed: number;
  wind_direction: number;
  surface_pressure: number;
  is_day: boolean;
}

export interface DailyWeather {
  weather_date: string;
  weather_code: number;
  temperature_max: number;
  temperature_min: number;
  apparent_temperature_max: number;
  apparent_temperature_min: number;
  sunrise: string;
  sunset: string;
  precipitation_sum: number;
  rain_sum: number;
  snowfall_sum: number;
  precipitation_hours: number;
  wind_speed_max: number;
  wind_gusts_max: number;
}

export interface HourlyWeather {
  weather_time: string;
  temperature: number;
  apparent_temperature: number;
  humidity: number;
  precipitation_probability: number | null;
  precipitation: number;
  weather_code: number;
  cloud_cover: number;
  visibility: number | null;
  wind_speed: number;
  wind_direction: number;
}

/** GET /api/weather. `daily[0]` is today; the rest are previous days, newest first. */
export interface WeatherResponse {
  location: Location | null;
  current: CurrentWeather | null;
  daily: DailyWeather[];
  hourly: HourlyWeather[];
  data_source: string | null;
  last_synchronized_at: string | null;
  synchronization_status: string | null;
  is_stale: boolean;
  stale_reason: string | null;
}
