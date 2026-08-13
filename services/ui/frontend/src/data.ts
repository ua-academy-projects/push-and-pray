import { eventTime } from "./format";
import type {
  ChartGroup,
  Instrument,
  Metric,
  Observation,
  RangeValue,
  SeriesPoint,
} from "./types";

export const SERIES_COLORS: Record<string, string> = {
  WTI_USD_BBL: "#de8051",
  BRENT_USD_BBL: "#72b6a1",
  RBOB_GASOLINE_USD_GAL: "#d5b65f",
};

export const fallbackColor = (index: number): string =>
  ["#7c9fd4", "#b58bd0", "#d47b8e", "#8fb56d"][index % 4];

export function uniqueChronological(items: Observation[]): Observation[] {
  const byTime = new Map<number, Observation>();
  [...items]
    .sort((a, b) => Date.parse(a.scheduled_for) - Date.parse(b.scheduled_for))
    .forEach((item) => byTime.set(Date.parse(eventTime(item)), item));
  return [...byTime.values()].sort(
    (a, b) => Date.parse(eventTime(a)) - Date.parse(eventTime(b)),
  );
}

export function filterVisible(
  observations: Observation[],
  selected: string[],
  range: RangeValue,
): Observation[] {
  const selectedCodes = new Set(selected);
  const matching = observations.filter((item) => selectedCodes.has(item.instrument_code));
  if (!matching.length || range === "all") return matching;
  const newest = Math.max(...matching.map((item) => Date.parse(eventTime(item))));
  const cutoff = newest - Number(range) * 86_400_000;
  return matching.filter((item) => Date.parse(eventTime(item)) >= cutoff);
}

export function groupByInstrument(items: Observation[]): Record<string, Observation[]> {
  return items.reduce<Record<string, Observation[]>>((groups, item) => {
    (groups[item.instrument_code] ??= []).push(item);
    return groups;
  }, {});
}

export function toSeriesPoints(items: Observation[], metric: Metric): SeriesPoint[] {
  const rows = uniqueChronological(items);
  if (!rows.length) return [];
  const base = Number(rows[0].price);
  return rows.map((observation) => {
    const raw = Number(observation.price);
    return {
      time: Date.parse(eventTime(observation)),
      raw,
      value: metric === "change" ? (raw / base - 1) * 100 : raw,
      observation,
    };
  });
}

export function rollingAverage(points: SeriesPoint[], windowSize: number): SeriesPoint[] {
  return points.map((point, index) => {
    const window = points.slice(Math.max(0, index - windowSize + 1), index + 1);
    const value = window.reduce((sum, item) => sum + item.value, 0) / window.length;
    return { ...point, value };
  });
}

export function createChartGroups(
  items: Observation[],
  instruments: Instrument[],
  metric: Metric,
  layout: "separate" | "compare",
): ChartGroup[] {
  const grouped = groupByInstrument(items);
  const instrumentIndex = new Map(instruments.map((item) => [item.code, item]));
  const makeSeries = (code: string, rows: Observation[], index: number) => ({
    code,
    name: instrumentIndex.get(code)?.name ?? rows[0]?.instrument_name ?? code,
    color: SERIES_COLORS[code] ?? fallbackColor(index),
    points: toSeriesPoints(rows, metric),
  });

  if (layout === "separate") {
    return Object.entries(grouped).map(([code, rows], index) => {
      const instrument = instrumentIndex.get(code);
      return {
        key: code,
        title: instrument?.name ?? rows[0]?.instrument_name ?? code,
        unit: metric === "change" ? "Change from first visible point" : rows[0]?.unit ?? "",
        series: [makeSeries(code, rows, index)],
      };
    });
  }

  if (metric === "change") {
    return [
      {
        key: "comparison",
        title: "Relative performance",
        unit: "Change from first visible point",
        series: Object.entries(grouped).map(([code, rows], index) =>
          makeSeries(code, rows, index),
        ),
      },
    ];
  }

  const byUnit = Object.entries(grouped).reduce<Record<string, Array<[string, Observation[]]>>>(
    (groups, entry) => {
      const unit = entry[1][0]?.unit ?? "Unknown unit";
      (groups[unit] ??= []).push(entry);
      return groups;
    },
    {},
  );

  return Object.entries(byUnit).map(([unit, entries]) => ({
    key: unit,
    title: entries.length > 1 ? "Crude benchmarks" : entries[0]?.[1][0]?.instrument_name ?? unit,
    unit,
    series: entries.map(([code, rows], index) => makeSeries(code, rows, index)),
  }));
}
