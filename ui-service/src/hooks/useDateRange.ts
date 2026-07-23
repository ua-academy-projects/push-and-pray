import { useCallback, useMemo, useState } from "react";
import { kyivTodayString } from "../utils/dateFormat";

export type RangePreset = "7" | "10" | "30" | "all";

export interface UseDateRangeResult {
  preset: RangePreset | "custom";
  from: string | undefined;
  to: string | undefined;
  setPreset: (preset: RangePreset) => void;
  setCustomRange: (from: string, to: string) => void;
}

function daysAgo(days: number): string {
  const [year, month, day] = kyivTodayString().split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCDate(date.getUTCDate() - (days - 1));
  return date.toISOString().slice(0, 10);
}

/** Manages one section's selected date range independently -- the Averages section and the
 * History overlay each hold their own instance, so picking a range in one never affects the
 * other (see docs/architecture.md). `from`/`to` are both `undefined` for the "All available
 * data" preset, matching the Backend's own "omit both bounds" convention for unbounded
 * queries. */
export function useDateRange(defaultPreset: RangePreset = "30"): UseDateRangeResult {
  const [preset, setPresetState] = useState<RangePreset | "custom">(defaultPreset);
  const [customFrom, setCustomFrom] = useState<string>();
  const [customTo, setCustomTo] = useState<string>();

  const { from, to } = useMemo(() => {
    if (preset === "custom") {
      return { from: customFrom, to: customTo };
    }
    if (preset === "all") {
      return { from: undefined, to: undefined };
    }
    return { from: daysAgo(Number(preset)), to: kyivTodayString() };
  }, [preset, customFrom, customTo]);

  const setPreset = useCallback((next: RangePreset) => setPresetState(next), []);
  const setCustomRange = useCallback((nextFrom: string, nextTo: string) => {
    setCustomFrom(nextFrom);
    setCustomTo(nextTo);
    setPresetState("custom");
  }, []);

  return { preset, from, to, setPreset, setCustomRange };
}
