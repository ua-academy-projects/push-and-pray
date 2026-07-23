import { useEffect } from "react";
import { useDateRange } from "../hooks/useDateRange";
import { useHistory } from "../hooks/useHistory";
import { dayLabel, kyivTodayString } from "../utils/dateFormat";
import { getWeatherInfo } from "../utils/weatherCode";
import { DateRangeSelector } from "./DateRangeSelector";
import styles from "./HistoryOverlay.module.css";

interface HistoryOverlayProps {
  open: boolean;
  onClose: () => void;
}

/** A plain list (no chart) of recorded daily data, in its own overlay with its own independent
 * date-range control -- History is deliberately not one of the always-visible sections. Only
 * fetches while `open`, so opening the page never pulls this data unnecessarily. */
export function HistoryOverlay({ open, onClose }: HistoryOverlayProps) {
  const range = useDateRange("30");
  const history = useHistory(range.from, range.to, open);

  useEffect(() => {
    if (!open) return;
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [open, onClose]);

  if (!open) return null;

  const todayStr = kyivTodayString();
  const rows = history.data?.daily ?? [];

  return (
    <div className={styles.backdrop} onClick={onClose}>
      <div
        className={`glass-card ${styles.panel}`}
        role="dialog"
        aria-modal="true"
        aria-label="Weather history"
        onClick={(event) => event.stopPropagation()}
      >
        <div className={styles.header}>
          <h2 className={styles.heading}>History</h2>
          <button type="button" className={styles.closeButton} onClick={onClose} aria-label="Close history">
            ✕
          </button>
        </div>

        <div className={styles.controls}>
          <DateRangeSelector range={range} idPrefix="history" />
        </div>

        <div className={styles.body}>
          {history.status === "loading" && (
            <p className={styles.state} role="status">
              Loading history…
            </p>
          )}
          {history.status === "error" && (
            <p className={styles.state} role="alert">
              Couldn't load history for this range. Please try again shortly.
            </p>
          )}
          {history.status === "ready" && rows.length === 0 && <p className={styles.state}>No recorded data for this range yet.</p>}
          {history.status === "ready" && rows.length > 0 && (
            <ol className={styles.list}>
              {rows.map((day) => {
                const { description, icon } = getWeatherInfo(day.weather_code, true);
                return (
                  <li key={day.weather_date} className={styles.row}>
                    <span className={styles.date}>{dayLabel(day.weather_date, todayStr)}</span>
                    <span className={styles.condition}>
                      <span aria-hidden="true">{icon}</span>
                      <span className={styles.conditionText}>{description}</span>
                    </span>
                    <span className={styles.avgTemp}>{Math.round(day.average_temperature)}°</span>
                    <span className={styles.range}>
                      {Math.round(day.temperature_min)}° / {Math.round(day.temperature_max)}°
                    </span>
                    <span className={styles.humidity}>
                      {day.average_humidity !== null ? `${Math.round(day.average_humidity)}% humidity` : "—"}
                    </span>
                  </li>
                );
              })}
            </ol>
          )}
        </div>
      </div>
    </div>
  );
}
