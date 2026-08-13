export type Category = "crude_oil" | "gasoline";
export type RangeValue = "1" | "7" | "30" | "90" | "180" | "365" | "all";
export type Metric = "price" | "change";
export type Layout = "separate" | "compare";
export type ChartStyle = "line" | "area" | "points";
export type TableOrder = "asc" | "desc";
export type Scale = "linear" | "log";
export type MovingAverage = "off" | "3" | "7";

export interface Observation {
  id: string;
  instrument_code: string;
  instrument_name: string;
  category: Category;
  price: string;
  currency: string;
  unit: string;
  source: string;
  source_series_id: string;
  source_period: string;
  source_observed_at: string;
  scheduled_for: string;
  fetched_at: string;
  source_url: string;
  raw_data: Record<string, unknown>;
  created_at: string;
}

export interface Instrument {
  code: string;
  name: string;
  category: Category;
  currency: string;
  unit: string;
}

export interface Preferences {
  selected: string[] | null;
  range: RangeValue;
  metric: Metric;
  layout: Layout;
  style: ChartStyle;
  table_order: TableOrder;
  table_limit: 25 | 50 | 100 | 250;
  scale: Scale;
  moving_average: MovingAverage;
  smooth: boolean;
}

export interface SeriesPoint {
  time: number;
  value: number;
  raw: number;
  observation: Observation;
}

export interface ChartGroup {
  key: string;
  title: string;
  unit: string;
  series: Array<{
    code: string;
    name: string;
    color: string;
    points: SeriesPoint[];
  }>;
}

export type LoadState = "loading" | "ready" | "error";
