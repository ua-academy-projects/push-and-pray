/** GET /api/weather/statistics/daily/{date}. */
export interface DailyStatistics {
  date: string;
  average_temperature: number;
  average_temperature_method: "hourly" | "min_max_fallback";
  minimum_temperature: number;
  maximum_temperature: number;
  average_apparent_temperature: number;
  average_humidity: number | null;
  total_precipitation: number;
  average_wind_speed: number | null;
  maximum_wind_speed: number;
  average_cloud_cover: number | null;
  dominant_weather_condition: string;
}

/** GET /api/weather/statistics?from=&to= and GET /api/weather/statistics/all -- same shape. */
export interface PeriodStatistics {
  period_start: string | null;
  period_end: string | null;
  available_days: number;
  average_temperature: number | null;
  average_daily_minimum_temperature: number | null;
  average_daily_maximum_temperature: number | null;
  lowest_temperature: number | null;
  highest_temperature: number | null;
  average_humidity: number | null;
  total_precipitation: number | null;
  average_daily_precipitation: number | null;
  rainy_days: number;
  snowy_days: number;
  clear_days: number;
  cloudy_days: number;
  average_wind_speed: number | null;
  maximum_wind_speed: number | null;
  warmest_day: string | null;
  coldest_day: string | null;
  most_common_weather_condition: string | null;
}

/** GET /api/weather/daily/{date} and rows of GET /api/weather/daily -- the raw recorded row,
 * including the Stage 3 average_* fields (distinct from DailyStatistics, which reframes the
 * same date as a statistics summary). */
export interface DailyRecord {
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
  average_temperature: number;
  average_temperature_method: "hourly" | "min_max_fallback";
  average_apparent_temperature: number;
  average_humidity: number | null;
  average_wind_speed: number | null;
  average_cloud_cover: number | null;
}

export interface DailyRecordsResponse {
  location: { name: string; country: string; latitude: number; longitude: number; timezone: string } | null;
  daily: DailyRecord[];
}
