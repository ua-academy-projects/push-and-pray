import { useId, useState } from "react";
import type { RangePreset, UseDateRangeResult } from "../hooks/useDateRange";
import styles from "./DateRangeSelector.module.css";

interface DateRangeSelectorProps {
  range: UseDateRangeResult;
  idPrefix: string;
}

const PRESETS: { value: RangePreset; label: string }[] = [
  { value: "7", label: "Last 7 days" },
  { value: "10", label: "Last 10 days" },
  { value: "30", label: "Last 30 days" },
  { value: "all", label: "All available data" },
];

/** Presets plus a manual date picker. Used independently by the Averages section and the
 * History overlay -- each instance owns its own `range` (a separate `useDateRange()` call in
 * the parent), so picking a range in one never affects the other. */
export function DateRangeSelector({ range, idPrefix }: DateRangeSelectorProps) {
  const fromId = useId();
  const toId = useId();
  const [customFrom, setCustomFrom] = useState(range.from ?? "");
  const [customTo, setCustomTo] = useState(range.to ?? "");

  function applyCustomRange() {
    if (customFrom && customTo) range.setCustomRange(customFrom, customTo);
  }

  return (
    <div className={styles.row} role="group" aria-label="Date range">
      <div className={styles.presets}>
        {PRESETS.map((preset) => (
          <button
            key={preset.value}
            type="button"
            className={styles.presetButton}
            aria-pressed={range.preset === preset.value}
            onClick={() => range.setPreset(preset.value)}
          >
            {preset.label}
          </button>
        ))}
      </div>

      <div className={styles.customInputs}>
        <label htmlFor={`${idPrefix}-${fromId}`} className="visually-hidden">
          Custom range start
        </label>
        <input
          id={`${idPrefix}-${fromId}`}
          type="date"
          className={styles.dateInput}
          value={customFrom}
          onChange={(event) => setCustomFrom(event.target.value)}
        />
        <span aria-hidden="true">–</span>
        <label htmlFor={`${idPrefix}-${toId}`} className="visually-hidden">
          Custom range end
        </label>
        <input
          id={`${idPrefix}-${toId}`}
          type="date"
          className={styles.dateInput}
          value={customTo}
          onChange={(event) => setCustomTo(event.target.value)}
        />
        <button type="button" className={styles.presetButton} onClick={applyCustomRange}>
          Apply
        </button>
      </div>
    </div>
  );
}
