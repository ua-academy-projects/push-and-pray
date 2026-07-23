/** GET /api/weather/charts?from=&to= -- ordered ascending by date. */
export interface ChartPeriod {
  from: string | null;
  to: string | null;
  available_days: number;
}

export interface TemperaturePoint {
  date: string;
  average: number;
  minimum: number;
  maximum: number;
}

export interface HumidityPoint {
  date: string;
  average: number | null;
}

export interface PrecipitationPoint {
  date: string;
  total: number;
}

export interface WindPoint {
  date: string;
  average: number | null;
  maximum: number;
}

export interface ChartData {
  period: ChartPeriod;
  temperature: TemperaturePoint[];
  humidity: HumidityPoint[];
  precipitation: PrecipitationPoint[];
  wind: WindPoint[];
}
