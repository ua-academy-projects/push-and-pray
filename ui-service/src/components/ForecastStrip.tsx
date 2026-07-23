import type { ForecastDay } from "../types/forecast";
import { formatShortDate, formatWeekday } from "../utils/dateFormat";
import { getWeatherInfo } from "../utils/weatherCode";
import styles from "./ForecastStrip.module.css";

interface ForecastStripProps {
  days: ForecastDay[];
}

/** A plain list of day-cards, deliberately not a chart -- forecast values are expected to
 * change before each date arrives, so a precise line+band chart would imply false precision.
 * Every card is visibly tagged "Predicted". */
export function ForecastStrip({ days }: ForecastStripProps) {
  if (days.length === 0) return null;

  return (
    <div className={styles.strip} role="list">
      {days.map((day) => {
        const { icon } = getWeatherInfo(day.weather_code, true);
        return (
          <div key={day.weather_date} role="listitem" className={`glass-chip ${styles.card}`}>
            <div className={styles.date}>
              {formatWeekday(day.weather_date)} {formatShortDate(day.weather_date)}
            </div>
            <div className={styles.icon} aria-hidden="true">
              {icon}
            </div>
            <div className={styles.temps}>
              <span className={styles.high}>{Math.round(day.temperature_max)}°</span>
              <span className={styles.low}>{Math.round(day.temperature_min)}°</span>
            </div>
            {day.precipitation_probability_max !== null && (
              <div className={styles.pop}>{Math.round(day.precipitation_probability_max)}% precip</div>
            )}
            <span className={styles.tag}>Predicted</span>
          </div>
        );
      })}
    </div>
  );
}
