import type { DailyWeather } from "../types/weather";
import { dayLabel, kyivTodayString } from "../utils/dateFormat";
import { getWeatherInfo } from "../utils/weatherCode";
import styles from "./DailyHistory.module.css";

interface DailyHistoryProps {
  daily: DailyWeather[];
}

export function DailyHistory({ daily }: DailyHistoryProps) {
  if (daily.length === 0) return null;

  const todayStr = kyivTodayString();

  return (
    <section className={`glass-card ${styles.section}`} aria-label="Previous days">
      <h2 className={styles.heading}>Last 10 Days</h2>
      <ol className={styles.list}>
        {daily.map((day) => {
          const { description, icon } = getWeatherInfo(day.weather_code, true);
          const isToday = day.weather_date === todayStr;
          return (
            <li key={day.weather_date} className={`${styles.day} ${isToday ? styles.dayToday : ""}`}>
              <span className={styles.dayLabel}>{dayLabel(day.weather_date, todayStr)}</span>
              <span className={styles.condition}>
                <span aria-hidden="true">{icon}</span>
                <span className={styles.conditionText}>{description}</span>
              </span>
              <span className={styles.precip}>{day.precipitation_sum > 0 ? `${day.precipitation_sum.toFixed(1)} mm` : "—"}</span>
              <span className={styles.temps}>
                <span className={styles.maxTemp}>{Math.round(day.temperature_max)}°</span>
                <span className={styles.minTemp}>{Math.round(day.temperature_min)}°</span>
              </span>
            </li>
          );
        })}
      </ol>
    </section>
  );
}
