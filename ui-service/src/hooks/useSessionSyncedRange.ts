import { useEffect, useRef } from "react";
import type { RangePreset, UseDateRangeResult } from "./useDateRange";
import type { UseSessionStateResult } from "./useSessionState";

/** Hydrates one useDateRange instance from the persisted session exactly once, the first time
 * the session finishes loading, then pushes every later change back to it. Averages and
 * History each own an independent instance of both this hook and useDateRange, so persisting
 * one never touches the other's state -- the same independence useDateRange itself already
 * guarantees for its in-memory state (see docs/architecture.md). */
export function useSessionSyncedRange(
  session: UseSessionStateResult,
  key: "averages_range" | "history_range",
  range: UseDateRangeResult,
) {
  const hydrated = useRef(false);

  useEffect(() => {
    if (session.status !== "ready" || hydrated.current) return;
    hydrated.current = true;

    const persisted = session.state?.[key];
    if (!persisted) return;
    if (persisted.preset === "custom" && persisted.range_from && persisted.range_to) {
      range.setCustomRange(persisted.range_from, persisted.range_to);
    } else if (persisted.preset !== "custom") {
      range.setPreset(persisted.preset as RangePreset);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session.status]);

  useEffect(() => {
    if (!hydrated.current) return; // don't overwrite the persisted value before it's applied
    session.patch({ [key]: { preset: range.preset, range_from: range.from ?? null, range_to: range.to ?? null } });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [range.preset, range.from, range.to]);
}
