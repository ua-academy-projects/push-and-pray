/** One predicted future day from GET /api/weather/forecast. Distinct from a recorded
 * DailyRecord -- fewer fields, no averages (nothing to average yet), and expected to change
 * before the date arrives. */
export interface ForecastDay {
  weather_date: string;
  weather_code: number;
  temperature_min: number;
  temperature_max: number;
  apparent_temperature_min: number;
  apparent_temperature_max: number;
  precipitation_probability_max: number | null;
}

export interface ForecastResponse {
  location: { name: string; country: string; latitude: number; longitude: number; timezone: string } | null;
  forecast: ForecastDay[];
}
